import 'dart:convert';

import '../../config/app_config.dart';
import '../../shared/diagnostics.dart';
import '../../shared/transport.dart';
import '../models/model.dart';
import 'sse.dart';
import 'chat_metadata.dart';

class ChatDelta {
  const ChatDelta({
    this.content = '',
    this.reasoning = '',
    this.provider,
    this.requestId,
    this.done = false,
    this.finishReason,
    this.usage,
    this.failure,
  });
  final String content;
  final String reasoning;
  final String? provider;
  final String? requestId;
  final bool done;
  final String? finishReason;
  final ChatUsage? usage;
  final AppFailure? failure;
}

/// API adaptation lives here, away from widgets and conversation ownership.
class ChatApi {
  ChatApi(this.config, this.transport);
  final AppConfig config;
  final ApiTransport transport;

  Map<String, String> get headers => {
    'Content-Type': 'application/json',
    'Accept': 'text/event-stream',
    'Authorization': 'Bearer ${config.apiKey}',
  };

  Map<String, dynamic> requestBody(
    FreeModel model,
    List<Map<String, dynamic>> messages, {
    bool probe = false,
    int? outputTokens,
  }) => {
    'model': model.id,
    'messages': messages,
    'stream': true,
    'provider': {
      'allow_fallbacks': false,
      'max_price': {
        'prompt': '0',
        'completion': '0',
        'request': '0',
        'image': '0',
        'audio': '0',
      },
    },
    // The default PDF parser can fall back to a paid OCR engine. A native-only
    // parser is explicit whenever any retained user turn includes a PDF.
    if (messages.any(
      (message) =>
          message['content'] is List &&
          (message['content'] as List).any(
            (part) => part is Map && part['type'] == 'file',
          ),
    ))
      'plugins': [
        {
          'id': 'file-parser',
          'pdf': {'engine': 'native'},
        },
      ],
    // A probe must not disable a model's mandatory reasoning. Keep its default
    // behavior; the small output limit and probe timeout still bound the check.
    if (model.supportsReasoning && !probe) 'reasoning': {'enabled': true},
    if (probe && model.supportedParameters.contains('max_tokens'))
      'max_tokens': 16,
    if (!probe && model.supportedParameters.contains('max_tokens'))
      'max_tokens': outputTokens ?? config.maxOutputTokens,
  };

  Stream<ChatDelta> stream(
    FreeModel model,
    List<Map<String, dynamic>> messages, {
    required CancelToken cancel,
    bool probe = false,
    int? outputTokens,
    void Function(int status, String? requestId)? onResponse,
    void Function(Map<String, String> headers)? onHeaders,
    void Function()? onDispatch,
  }) {
    final requestCancel = CancelToken();
    final unlink = cancel.listen(requestCancel.cancel);
    final source = _stream(
      model,
      messages,
      cancel: requestCancel,
      probe: probe,
      outputTokens: outputTokens,
      onResponse: onResponse,
      onHeaders: onHeaders,
      onDispatch: onDispatch,
    );
    return withPhaseTimeouts(
      source,
      cancel: cancel,
      firstResponseTimeout: probe
          ? config.probeTimeout
          : config.firstResponseTimeout,
      idleTimeout: probe ? config.probeTimeout : config.streamIdleTimeout,
      overallTimeout: probe ? config.probeTimeout : config.streamOverallTimeout,
      isProgress: (delta) =>
          delta.content.isNotEmpty || delta.reasoning.isNotEmpty,
      onDispose: () {
        unlink();
        requestCancel.cancel();
      },
      errorFromValue: (delta) => delta.failure,
      isComplete: (delta) => delta.done,
    );
  }

  Stream<ChatDelta> _stream(
    FreeModel model,
    List<Map<String, dynamic>> messages, {
    required CancelToken cancel,
    bool probe = false,
    int? outputTokens,
    void Function(int status, String? requestId)? onResponse,
    void Function(Map<String, String> headers)? onHeaders,
    void Function()? onDispatch,
  }) async* {
    if (config.apiKey.trim().isEmpty) {
      throw AppFailure(
        FailureKind.authentication,
        'Add an OpenRouter API key in Settings.',
      );
    }
    if (!model.chatCompatible) {
      throw AppFailure(
        FailureKind.configuration,
        model.incompatibilityReason ?? 'This model does not support text chat.',
      );
    }
    cancel.throwIfCancelled();
    final request = transport.send(
      'POST',
      Uri.parse('${config.apiBaseUrl}/chat/completions'),
      headers: headers,
      body: jsonEncode(
        requestBody(model, messages, probe: probe, outputTokens: outputTokens),
      ),
      timeout: probe ? config.probeTimeout : config.streamOverallTimeout,
      cancel: cancel,
    );
    // The marker belongs at the transport boundary, after local validation and
    // body encoding. A health probe has its own request and never supplies it.
    onDispatch?.call();
    final response = await request;
    var requestId =
        response.headers['x-generation-id'] ?? response.headers['x-request-id'];
    onResponse?.call(response.status, requestId);
    onHeaders?.call(response.headers);
    if (response.status < 200 || response.status >= 300) {
      throw AppFailure.http(
        response.status,
        body: await response.readText(maxBytes: 65536),
        headers: response.headers,
      );
    }
    final type = response.headers['content-type']?.toLowerCase() ?? '';
    if (!type.contains('text/event-stream')) {
      final raw = await response.readText(maxBytes: 65536);
      final object = _decode(raw, r'$');
      if (object['error'] != null) {
        throw envelopeFailure(object, response.headers);
      }
      throw AppFailure(
        FailureKind.schema,
        'The API returned an unexpected response format for a streaming request.',
        status: response.status,
        field: 'Content-Type',
        expected: 'text/event-stream',
        actual: type.isEmpty ? 'missing' : type,
        requestId: requestId,
      );
    }
    String? provider;
    var received = false;
    var total = 0;
    String? finishReason;
    ChatUsage? usage;
    await for (final event in decodeSse(
      response.body,
      cancel: cancel,
      maxEventChars: config.maxResponseChars * 2,
    )) {
      try {
        if (event == '[DONE]') {
          if (!received) {
            throw AppFailure(
              FailureKind.stream,
              'The API ended the response without any text or reasoning.',
              status: response.status,
              retryable: true,
              requestId: requestId,
              provider: provider,
            );
          }
          cancel.cancel();
          yield ChatDelta(
            done: true,
            provider: provider,
            requestId: requestId,
            finishReason: finishReason,
            usage: usage,
          );
          return;
        }
        final object = _decode(event, 'SSE.data');
        usage = ChatUsage.fromJson(object['usage']) ?? usage;
        if (object['error'] != null) {
          throw envelopeFailure(object, response.headers);
        }
        final returnedModel = object['model'];
        if (returnedModel is String &&
            returnedModel != model.id &&
            !(model.id.endsWith(':free') &&
                returnedModel == model.id.substring(0, model.id.length - 5))) {
          throw AppFailure(
            FailureKind.stream,
            'The response identified a different model. The request was stopped.',
            field: 'SSE.data.model',
            expected: model.id,
            actual: returnedModel,
            status: response.status,
            requestId: requestId,
          );
        }
        if (object['id'] is String) requestId = object['id'] as String;
        if (object['provider'] is String) {
          provider = object['provider'] as String;
        }
        final choices = object['choices'];
        if (choices is! List) {
          throw _schema('SSE.data.choices', 'array', choices);
        }
        if (choices.isEmpty && object['usage'] is Map) {
          yield ChatDelta(
            usage: usage,
            provider: provider,
            requestId: requestId,
          );
          continue;
        }
        if (choices.isEmpty || choices.first is! Map) {
          throw _schema(
            'SSE.data.choices[0]',
            'object',
            choices.isEmpty ? null : choices.first,
          );
        }
        final choice = choices.first as Map;
        final reason = choice['finish_reason'];
        if (reason is String && reason.isNotEmpty) finishReason = reason;
        if (choice['finish_reason'] == 'error') {
          throw AppFailure(
            FailureKind.provider,
            'The provider terminated the response with an error.',
            status: 200,
            retryable: true,
            requestId: requestId,
            provider: provider,
          );
        }
        final delta = choice['delta'];
        if (delta is! Map) {
          throw _schema('SSE.data.choices[0].delta', 'object', delta);
        }
        final content = _optionalText(
          delta['content'],
          'SSE.data.choices[0].delta.content',
        );
        var reasoning = _optionalText(
          delta['reasoning'] ?? delta['reasoning_content'],
          'SSE.data.choices[0].delta.reasoning',
        );
        // Prefer the plain representation to avoid displaying duplicated reasoning
        // when a provider emits both legacy and structured fields in one delta.
        if (reasoning.isEmpty && delta['reasoning_details'] != null) {
          final details = delta['reasoning_details'];
          if (details is! List) {
            throw _schema(
              'SSE.data.choices[0].delta.reasoning_details',
              'array',
              details,
            );
          }
          final buffer = StringBuffer();
          for (final detail in details) {
            if (detail is! Map) {
              throw _schema('SSE.data.reasoning_details[]', 'object', detail);
            }
            if (detail['type'] == 'reasoning.text') {
              buffer.write(
                _optionalText(detail['text'], 'reasoning_details[].text'),
              );
            } else if (detail['type'] == 'reasoning.summary') {
              buffer.write(
                _optionalText(detail['summary'], 'reasoning_details[].summary'),
              );
            }
            // Encrypted reasoning is not plaintext and is never invented/decrypted.
          }
          reasoning = buffer.toString();
        }
        total += content.length + reasoning.length;
        if (total > config.maxResponseChars) {
          throw AppFailure(
            FailureKind.stream,
            'The response reached the local size limit. Received text is kept.',
            status: response.status,
            requestId: requestId,
            provider: provider,
          );
        }
        received |= content.isNotEmpty || reasoning.isNotEmpty;
        yield ChatDelta(
          content: content,
          reasoning: reasoning,
          provider: provider,
          requestId: requestId,
          finishReason: finishReason,
          usage: usage,
        );
      } catch (error) {
        // Abort the byte source before unwinding async decoder cancellation.
        // A provider can emit an error and leave its HTTP stream open.
        yield ChatDelta(failure: AppFailure.from(error));
        cancel.cancel();
        return;
      }
    }
    throw AppFailure(
      FailureKind.stream,
      'The connection ended before the completion marker. Received text is kept.',
      status: response.status,
      retryable: true,
      requestId: requestId,
      provider: provider,
    );
  }
}

Map<String, dynamic> _decode(String raw, String path) {
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    throw AppFailure(
      FailureKind.parsing,
      'The API returned malformed JSON.',
      field: path,
      expected: 'JSON object',
      actual: 'malformed JSON',
      details:
          'Raw content omitted because inference responses can contain conversation content.',
    );
  }
  if (decoded is! Map<String, dynamic>) throw _schema(path, 'object', decoded);
  return decoded;
}

String _optionalText(Object? value, String path) {
  if (value == null) return '';
  if (value is String) return value;
  throw _schema(path, 'string or null', value);
}

AppFailure _schema(String path, String expected, Object? actual) => AppFailure(
  FailureKind.schema,
  'The API response changed at $path.',
  field: path,
  expected: expected,
  actual: actual == null ? 'null/missing' : actual.runtimeType.toString(),
);

/// Error envelopes may occur before streaming or in a stream whose HTTP status
/// is already 200. Do not classify the outer 200 as inference success.
AppFailure envelopeFailure(
  Map<String, dynamic> object,
  Map<String, String> headers,
) {
  final error = object['error'];
  if (error is! Map) return _schema('error', 'object', error);
  final rawCode = error['code'];
  final code = rawCode is int ? rawCode : int.tryParse('$rawCode');
  final status = code != null && code >= 400 && code <= 599 ? code : 502;
  final safeCode =
      rawCode is num ||
          (rawCode is String &&
              RegExp(r'^[A-Za-z0-9_-]{1,60}$').hasMatch(rawCode))
      ? rawCode.toString()
      : 'unrecognized';
  // Omit upstream raw messages: providers sometimes echo the entire prompt.
  // Classification and bounded structural metadata remain available.
  final base = AppFailure.http(status, headers: headers);
  final metadata = error['metadata'];
  final provider = object['provider'] is String
      ? object['provider'] as String
      : metadata is Map && metadata['provider_name'] is String
      ? metadata['provider_name'] as String
      : null;
  return AppFailure(
    base.kind,
    base.message,
    status: 200,
    retryable: base.retryable,
    retryAfter: base.retryAfter,
    requestId: object['id'] is String ? object['id'] as String : base.requestId,
    provider: provider,
    details:
        'API error code: $safeCode. '
        'Provider message and raw inference payload omitted to protect conversation content.',
  );
}
