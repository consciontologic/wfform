import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../config/app_config.dart';
import '../../shared/diagnostics.dart';
import '../../shared/transport.dart';
import '../models/health.dart';
import '../models/model.dart';
import 'attachment.dart';
import 'chat_api.dart';
import 'chat_metadata.dart';
export 'chat_metadata.dart';

class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.content,
    this.reasoning = '',
    this.modelId,
    this.complete = true,
    this.failure,
    this.attachments = const [],
    this.editedFrom,
    this.finishReason,
    this.usage,
    this.metrics,
  });
  final String role;
  final String content;
  final String reasoning;
  final String? modelId;
  final bool complete;
  final AppFailure? failure;
  final List<ChatAttachment> attachments;

  /// Index of the original user turn; editing always appends a new turn.
  final int? editedFrom;
  final String? finishReason;
  final ChatUsage? usage;
  final ChatMetrics? metrics;
  String get terminationLabel => switch (finishReason) {
    'length' => 'Stopped at the response token limit',
    'content_filter' => 'Stopped by the provider’s content filter',
    'stop' || null => complete ? 'Complete' : 'Incomplete',
    _ => 'Provider stopped the response ($finishReason)',
  };

  Map<String, dynamic> toJson() => {
    'role': role,
    'content': content,
    'reasoning': reasoning,
    'modelId': modelId,
    'complete': complete,
    if (attachments.isNotEmpty)
      'attachments': attachments
          .map((attachment) => attachment.toJson())
          .toList(),
    if (editedFrom != null) 'editedFrom': editedFrom,
    if (finishReason != null) 'finishReason': finishReason,
    if (usage != null) 'usage': usage!.toJson(),
    if (metrics != null) 'metrics': metrics!.toJson(),
    if (failure != null)
      'failure': {
        'kind': failure!.kind.name,
        'message': failure!.message,
        'status': failure!.status,
        'retryable': failure!.retryable,
      },
  };
}

class ChatController extends ChangeNotifier {
  ChatController({
    required this.config,
    required this.transport,
    required this.diagnostics,
    required this.health,
    this.validateModel,
  });
  final AppConfig config;
  final ApiTransport transport;
  final Diagnostics diagnostics;
  final HealthController health;
  final String? Function(FreeModel model)? validateModel;
  final _messages = <ChatMessage>[];
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool busy = false;
  bool _hasDispatchedUserContent = false;
  bool get hasDispatchedUserContent => _hasDispatchedUserContent;
  String progress = '';
  AppFailure? error;
  bool get canRetry => !busy && _retryUserIndex != null;
  String? get retryModelId => _retryModelId;
  String? get activeModelId => busy ? _retryModelId : null;
  int? _retryUserIndex;
  String? _retryModelId;
  CancelToken? _token;
  bool _disposed = false;
  int _generation = 0;
  final ChangeNotifier _statusChanges = ChangeNotifier();
  Listenable get statusChanges => _statusChanges;
  String _lastStatus = '';
  int _contextStartIndex = 0;
  int? _outputTokenLimit;
  final Map<ChatMessage, int> _textTokenEstimates = {};
  int get outputTokenLimit => _outputTokenLimit ?? config.maxOutputTokens;
  bool setOutputTokenLimit(int value) {
    if (busy || value < 16 || value > 32768) return false;
    _outputTokenLimit = value;
    _notify();
    return true;
  }

  int get contextStartIndex => _contextStartIndex;
  DateTime? get retryAt =>
      _retryModelId == null ? null : health.retryAtFor(_retryModelId!);
  bool get canContinue =>
      !busy &&
      _messages.isNotEmpty &&
      _messages.last.role == 'assistant' &&
      _messages.last.complete &&
      _messages.last.finishReason == 'length';

  bool setContextStartIndex(int index) {
    if (busy ||
        index < 0 ||
        index > _messages.length ||
        (index < _messages.length && _messages[index].role != 'user')) {
      return false;
    }
    _contextStartIndex = index;
    _notify();
    return true;
  }

  ContextBudget contextBudget(
    FreeModel model, {
    String draft = '',
    List<ChatAttachment> attachments = const [],
    int? throughIndex,
  }) {
    var tokens = 3, media = false;
    final retained = _messages.toSet();
    _textTokenEstimates.removeWhere(
      (message, _) => !retained.contains(message),
    );
    void add(String text, List<ChatAttachment> files, [ChatMessage? message]) {
      tokens += message == null
          ? (utf8.encode(text).length / 3).ceil() + 6
          : _textTokenEstimates.putIfAbsent(
              message,
              () => (utf8.encode(text).length / 3).ceil() + 6,
            );
      for (final file in files) {
        if (file.kind == AttachmentKind.text) {
          tokens += file.estimatedTextTokens;
        } else {
          media = true;
          tokens += file.kind == AttachmentKind.image ? 1024 : 4096;
        }
      }
    }

    final end = math.min(
      throughIndex ?? _messages.length - 1,
      _messages.length - 1,
    );
    for (var i = _contextStartIndex; i <= end; i++) {
      final message = _messages[i];
      if (message.role == 'user' ||
          (message.complete && message.failure == null)) {
        add(message.content, message.attachments, message);
      }
    }
    if (draft.trim().isNotEmpty || attachments.isNotEmpty) {
      add(draft, attachments);
    }
    final limit = model.contextLength;
    var reserve =
        _outputTokenLimit ??
        (limit == null
            ? config.maxOutputTokens
            : math.min(config.maxOutputTokens, math.max(16, limit ~/ 4)));
    final providerLimit = model.topProvider['max_completion_tokens'];
    if (providerLimit is int && providerLimit > 0) {
      reserve = math.min(reserve, providerLimit);
    }
    return ContextBudget(
      estimatedInputTokens: tokens,
      outputTokens: reserve,
      contextLimit: limit,
      startIndex: _contextStartIndex,
      hasAttachments: media,
    );
  }

  Future<void> continueResponse(FreeModel model) async {
    if (!canContinue) return;
    await send(
      model,
      'Continue the previous response from where it stopped. Do not repeat existing text.',
    );
  }

  bool _admit(FreeModel model, ContextBudget budget) {
    final block = health.admissionFailure(model);
    if (block != null) {
      error = block;
      _notify();
      return false;
    }
    if (!budget.fits) {
      _localFailure(budget.warning!);
      return false;
    }
    return true;
  }

  /// [onAccepted] runs synchronously once, after reserving the turn and before
  /// listeners or network work. It never runs for refused submissions.
  Future<void> send(
    FreeModel model,
    String text, {
    List<ChatAttachment> attachments = const [],
    int? editedFrom,
    VoidCallback? onAccepted,
  }) async {
    if (_disposed || busy || (text.trim().isEmpty && attachments.isEmpty)) {
      return;
    }
    final refusal = validateModel?.call(model);
    if (refusal != null) {
      _localFailure(refusal);
      return;
    }
    if (_messages.length + 2 > config.maxMessages) {
      _localFailure(
        'This conversation reached its ${config.maxMessages}-message limit. Start a new conversation.',
      );
      return;
    }
    if (text.length > math.min(config.maxResponseChars, 32000)) {
      _localFailure(
        'The draft exceeds the local message size limit. Shorten it before sending.',
      );
      return;
    }
    if (editedFrom != null &&
        (editedFrom < 0 ||
            editedFrom >= _messages.length ||
            _messages[editedFrom].role != 'user')) {
      _localFailure('The original message is no longer available for editing.');
      return;
    }
    if (!_validateHistoryAttachments(model, extra: attachments)) return;
    if (!_admit(
      model,
      contextBudget(model, draft: text, attachments: attachments),
    )) {
      return;
    }
    _messages.add(
      ChatMessage(
        role: 'user',
        content: text,
        modelId: model.id,
        attachments: List.unmodifiable(attachments),
        editedFrom: editedFrom,
      ),
    );
    _retryUserIndex = _messages.length - 1;
    _retryModelId = model.id;
    await _run(model, _retryUserIndex!, onAccepted: onAccepted);
  }

  Future<void> retry(FreeModel model) async {
    if (!canRetry || _disposed) return;
    final refusal = validateModel?.call(model);
    if (refusal != null) {
      _localFailure(refusal);
      return;
    }
    if (model.id != _retryModelId) {
      _localFailure(
        'Select the original model ($_retryModelId) to retry this turn, or send a new message.',
      );
      return;
    }
    if (_messages.length + 1 > config.maxMessages) {
      _localFailure(
        'This conversation reached its message limit. Start a new conversation.',
      );
      return;
    }
    if (!_validateHistoryAttachments(model)) return;
    if (_contextStartIndex > _retryUserIndex!) {
      _localFailure(
        'Include the original user turn in the context before retrying.',
      );
      return;
    }
    if (!_admit(model, contextBudget(model, throughIndex: _retryUserIndex!))) {
      return;
    }
    // Keep the old failed assistant attempt on-screen. The exact original user
    // turn is reused; failed/partial answers never enter the outbound history.
    await _run(model, _retryUserIndex!);
  }

  Future<void> _run(
    FreeModel model,
    int userIndex, {
    VoidCallback? onAccepted,
  }) async {
    busy = true;
    error = null;
    progress = 'Checking selected model…';
    final generation = ++_generation;
    final token = CancelToken();
    _token = token;
    final assistantIndex = _messages.length;
    _messages.add(
      ChatMessage(
        role: 'assistant',
        content: '',
        modelId: model.id,
        complete: false,
      ),
    );
    final watch = Stopwatch()..start();
    int? status;
    String? requestId;
    String? provider;
    var inferenceStarted = false;
    final generationWatch = Stopwatch();
    var preflightMs = 0;
    int? firstTokenMs;
    String? finishReason;
    ChatUsage? usage;
    final contentBuffer = StringBuffer(), reasoningBuffer = StringBuffer();
    Timer? publishTimer;
    var completed = false;
    void publish() {
      publishTimer?.cancel();
      publishTimer = null;
      if (_disposed || generation != _generation) return;
      final previous = _messages[assistantIndex];
      _messages[assistantIndex] = ChatMessage(
        role: 'assistant',
        content: previous.content + contentBuffer.toString(),
        reasoning: previous.reasoning + reasoningBuffer.toString(),
        modelId: model.id,
        complete: completed,
        finishReason: finishReason,
        usage: usage,
        metrics: ChatMetrics(
          preflightMs: preflightMs,
          generationMs: generationWatch.elapsedMilliseconds,
          firstTokenMs: firstTokenMs,
        ),
      );
      contentBuffer.clear();
      reasoningBuffer.clear();
      _notify();
    }

    Set<String> requestModalities = {'text'};
    try {
      onAccepted?.call();
      _notify();
      // Even a fresh model must observe account-wide rate-limit cooldowns.
      final observation = await health.check(model, cancel: token);
      token.throwIfCancelled();
      if (observation.failure != null || !health.isFresh(model.id)) {
        throw observation.failure ??
            AppFailure(
              FailureKind.provider,
              observation.message,
              retryable: true,
              provider: observation.provider,
            );
      }
      token.throwIfCancelled();
      // Catalog capabilities, zero-price eligibility, archival state or the
      // selected conversation can change while a selected-model probe awaits.
      // Recheck immediately before user content enters the inference request.
      final refusal = validateModel?.call(model);
      if (refusal != null) {
        throw AppFailure(FailureKind.configuration, refusal);
      }
      progress = 'Waiting for first response…';
      _notify();
      final history = <Map<String, dynamic>>[];
      for (var index = _contextStartIndex; index <= userIndex; index++) {
        final message = _messages[index];
        if (message.role == 'user' ||
            (message.complete && message.failure == null)) {
          history.add({
            'role': message.role,
            'content': message.attachments.isEmpty
                ? message.content
                : [
                    if (message.content.isNotEmpty)
                      {'type': 'text', 'text': message.content},
                    ...message.attachments.map(
                      (attachment) => attachment.toContentPart(),
                    ),
                  ],
          });
          requestModalities.addAll(message.attachments.map((a) => a.kind.name));
        }
      }
      final budget = contextBudget(model, throughIndex: userIndex);
      if (!budget.fits) {
        throw AppFailure(FailureKind.configuration, budget.warning!);
      }
      preflightMs = watch.elapsedMilliseconds;
      generationWatch.start();
      inferenceStarted = true;
      await for (final delta in ChatApi(config, transport).stream(
        model,
        history,
        cancel: token,
        outputTokens: budget.outputTokens,
        onDispatch: () {
          if (_hasDispatchedUserContent) return;
          _hasDispatchedUserContent = true;
          _notify();
        },
        onResponse: (code, id) {
          status = code;
          requestId = id;
        },
        onHeaders: (headers) => health.recordResponseHeaders(model.id, headers),
      )) {
        if (_disposed || generation != _generation) return;
        token.throwIfCancelled();
        provider = delta.provider ?? provider;
        requestId = delta.requestId ?? requestId;
        if (delta.content.isNotEmpty || delta.reasoning.isNotEmpty) {
          firstTokenMs ??= generationWatch.elapsedMilliseconds;
        }
        contentBuffer.write(delta.content);
        reasoningBuffer.write(delta.reasoning);
        finishReason = delta.finishReason ?? finishReason;
        usage = delta.usage ?? usage;
        completed |= delta.done;
        if (delta.content.isNotEmpty || delta.reasoning.isNotEmpty) {
          progress = delta.reasoning.isNotEmpty && delta.content.isEmpty
              ? 'Receiving reasoning…'
              : 'Receiving response…';
        }
        if (delta.done) {
          generationWatch.stop();
          publish();
        } else {
          publishTimer ??= Timer(const Duration(milliseconds: 32), publish);
        }
      }
      generationWatch.stop();
      publish();
      token.throwIfCancelled();
      if (!completed) {
        throw AppFailure(
          FailureKind.stream,
          'The response ended unexpectedly. Received text is kept.',
          retryable: true,
        );
      }
      health.recordSuccess(model.id, provider: provider);
      health.recordModalityResult(
        model.id,
        requestModalities,
        provider: provider,
      );
      _retryUserIndex = null;
      _retryModelId = null;
      progress = _messages[assistantIndex].terminationLabel;
      diagnostics.record(
        'chat.send',
        model: model.id,
        duration: watch.elapsed,
        status: status,
        requestId: requestId,
        provider: provider,
        note:
            'Stream finished (${finishReason ?? 'unspecified finish reason'}). Preflight ${preflightMs}ms; first token ${firstTokenMs ?? 'unknown'}ms; generation ${generationWatch.elapsedMilliseconds}ms; prompt tokens ${usage?.promptTokens ?? 'unreported'}; completion tokens ${usage?.completionTokens ?? 'unreported'}.',
      );
    } catch (caught) {
      if (_disposed || generation != _generation) return;
      generationWatch.stop();
      publish();
      final failure = AppFailure.from(caught);
      error = failure;
      final previous = _messages[assistantIndex];
      _messages[assistantIndex] = ChatMessage(
        role: 'assistant',
        content: previous.content,
        reasoning: previous.reasoning,
        modelId: model.id,
        complete: false,
        failure: failure,
        finishReason: finishReason,
        usage: usage,
        metrics: previous.metrics,
      );
      progress = failure.kind == FailureKind.cancelled
          ? 'Cancelled · sent message and received text kept'
          : 'Request failed · received text kept';
      // Preflight already records its own observation. Only actual chat
      // transport errors should additionally alter recent health.
      if (inferenceStarted && failure.kind != FailureKind.cancelled) {
        health.recordFailure(model.id, failure);
        health.recordModalityResult(
          model.id,
          requestModalities,
          failure: failure,
          provider: provider,
        );
      }
      diagnostics.record(
        'chat.send',
        model: model.id,
        duration: watch.elapsed,
        status: status ?? failure.status,
        requestId: requestId ?? failure.requestId,
        provider: provider ?? failure.provider,
        failure: failure,
      );
    } finally {
      publishTimer?.cancel();
      // Abort a request on parser failure/size limits too, not just user cancel.
      token.cancel();
      if (!_disposed && generation == _generation) {
        busy = false;
        _token = null;
        _notify();
      }
    }
  }

  void cancel() {
    if (!busy) return;
    progress = 'Cancelling…';
    _token?.cancel();
    _notify();
  }

  void clear() {
    _token?.cancel();
    _generation++;
    _token = null;
    _messages.clear();
    _hasDispatchedUserContent = false;
    _textTokenEstimates.clear();
    _contextStartIndex = 0;
    _outputTokenLimit = null;
    _retryUserIndex = null;
    _retryModelId = null;
    busy = false;
    progress = '';
    error = null;
    _notify();
  }

  Map<String, dynamic> exportSessionData() => {
    'version': 1,
    'hasDispatchedUserContent': _hasDispatchedUserContent,
    'messages': _messages.map((message) => message.toJson()).toList(),
    'retryUserIndex': _retryUserIndex,
    'retryModelId': _retryModelId,
    'contextStartIndex': _contextStartIndex,
    if (_outputTokenLimit != null) 'outputTokenLimit': _outputTokenLimit,
  };
  String exportSession() => jsonEncode(exportSessionData());

  /// Used only for explicit local draft/session persistence around PWA updates.
  /// Stored unfinished attempts become retryable; no request resumes by itself.
  bool restoreSession(String serialized) {
    if (busy || _disposed) return false;
    try {
      if (serialized.length >
          math.min(
            32 * 1024 * 1024,
            config.maxMessages * config.maxResponseChars * 3 +
                maxConversationAttachmentBase64Chars +
                65536,
          )) {
        throw const FormatException('Session exceeds local size limit.');
      }
      final object = jsonDecode(serialized);
      if (object is! Map ||
          object['version'] != 1 ||
          object['messages'] is! List ||
          (object.containsKey('hasDispatchedUserContent') &&
              object['hasDispatchedUserContent'] is! bool)) {
        throw const FormatException('Unsupported session format.');
      }
      final list = object['messages'] as List;
      if (list.length > config.maxMessages) {
        throw const FormatException('Too many stored messages.');
      }
      final restored = <ChatMessage>[];
      var attachmentChars = 0;
      for (final item in list) {
        if (item is! Map ||
            !{'user', 'assistant'}.contains(item['role']) ||
            item['content'] is! String ||
            item['reasoning'] is! String ||
            (item['modelId'] != null && item['modelId'] is! String)) {
          throw const FormatException('Invalid stored message.');
        }
        final content = item['content'] as String;
        final reasoning = item['reasoning'] as String;
        if (content.length + reasoning.length > config.maxResponseChars) {
          throw const FormatException(
            'Stored message exceeds local size limit.',
          );
        }
        final attachmentData = item['attachments'];
        if (attachmentData != null && attachmentData is! List) {
          throw const FormatException('Invalid stored attachment list.');
        }
        if (attachmentData is List && attachmentData.length > 4) {
          throw const FormatException(
            'Too many stored attachments in one turn.',
          );
        }
        final attachments = (attachmentData as List? ?? const [])
            .map(ChatAttachment.fromJson)
            .toList(growable: false);
        validateAttachments(attachments);
        if (item['role'] != 'user' && attachments.isNotEmpty) {
          throw const FormatException(
            'Stored attachments must belong to a user turn.',
          );
        }
        attachmentChars += attachments.fold<int>(
          0,
          (total, file) => total + file.base64Data.length,
        );
        if (attachmentChars > maxConversationAttachmentBase64Chars) {
          throw const FormatException(
            'Stored attachments exceed the conversation size limit.',
          );
        }
        final editedFrom = item['editedFrom'];
        if (editedFrom != null &&
            (editedFrom is! int ||
                item['role'] != 'user' ||
                editedFrom < 0 ||
                editedFrom >= restored.length ||
                restored[editedFrom].role != 'user')) {
          throw const FormatException(
            'Invalid original message reference for an edited turn.',
          );
        }
        final complete = item['complete'] == true;
        AppFailure? savedFailure;
        final failure = item['failure'];
        if (!complete && failure is Map && failure['message'] is String) {
          final kinds = FailureKind.values.where(
            (kind) => kind.name == failure['kind'],
          );
          if (kinds.isNotEmpty) {
            savedFailure = AppFailure(
              kinds.first,
              failure['message'] as String,
              status: failure['status'] is int
                  ? failure['status'] as int
                  : null,
              retryable: failure['retryable'] == true,
            );
          }
        }
        restored.add(
          ChatMessage(
            role: item['role'] as String,
            content: content,
            reasoning: reasoning,
            modelId: item['modelId'] as String?,
            complete: complete,
            attachments: List.unmodifiable(attachments),
            editedFrom: editedFrom as int?,
            finishReason: item['finishReason'] is String
                ? item['finishReason'] as String
                : null,
            usage: ChatUsage.fromJson(item['usage']),
            metrics: ChatMetrics.fromJson(item['metrics']),
            failure: complete
                ? null
                : savedFailure ??
                      AppFailure(
                        FailureKind.cancelled,
                        'This attempt was interrupted before the app reloaded. Received text is kept.',
                        retryable: true,
                      ),
          ),
        );
      }
      _messages.clear();
      _messages.addAll(restored);
      _hasDispatchedUserContent =
          object['hasDispatchedUserContent'] as bool? ??
          restored.any((message) => message.role == 'user');
      final start = object['contextStartIndex'];
      _contextStartIndex =
          start is int &&
              start >= 0 &&
              start <= restored.length &&
              (start == restored.length || restored[start].role == 'user')
          ? start
          : 0;
      final outputLimit = object['outputTokenLimit'];
      _outputTokenLimit =
          outputLimit is int && outputLimit >= 16 && outputLimit <= 32768
          ? outputLimit
          : null;
      final retryIndex = object['retryUserIndex'];
      if (retryIndex is int &&
          retryIndex >= 0 &&
          retryIndex < _messages.length &&
          _messages[retryIndex].role == 'user' &&
          object['retryModelId'] is String) {
        _retryUserIndex = retryIndex;
        _retryModelId = object['retryModelId'] as String;
      } else {
        _retryUserIndex = null;
        _retryModelId = null;
      }
      error = canRetry ? _messages.last.failure : null;
      _notify();
      return true;
    } catch (caught) {
      final failure = AppFailure(
        FailureKind.storage,
        'The saved conversation could not be restored.',
        details: caught is FormatException
            ? caught.message
            : caught.runtimeType.toString(),
      );
      diagnostics.record('chat.restore', failure: failure);
      error = failure;
      _notify();
      return false;
    }
  }

  bool _validateHistoryAttachments(
    FreeModel model, {
    List<ChatAttachment> extra = const [],
  }) {
    try {
      if (!model.chatCompatible) {
        throw AppFailure(
          FailureKind.configuration,
          model.incompatibilityReason ??
              'This model does not support text chat.',
        );
      }
      validateAttachments(extra, model: model);
      var chars = extra.fold<int>(
        0,
        (total, file) => total + file.base64Data.length,
      );
      for (var index = 0; index < _messages.length; index++) {
        final message = _messages[index];
        if (message.role == 'user' &&
            message.modelId != null &&
            message.modelId != model.id) {
          throw const AppFailure(
            FailureKind.configuration,
            'This conversation belongs to a different model. Start a new conversation to change models.',
          );
        }
        validateAttachments(
          message.attachments,
          model: index >= _contextStartIndex ? model : null,
        );
        chars += message.attachments.fold<int>(
          0,
          (total, file) => total + file.base64Data.length,
        );
      }
      if (chars > maxConversationAttachmentBase64Chars) {
        throw const AppFailure(
          FailureKind.configuration,
          'This conversation reached its 24 MiB encoded attachment limit. Start a new conversation before adding these files.',
        );
      }
      return true;
    } on AppFailure catch (failure) {
      error = failure;
      _notify();
      return false;
    }
  }

  void _localFailure(String message) {
    error = AppFailure(FailureKind.configuration, message);
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    final status =
        '$busy|$progress|${error?.kind}|${error?.message}|$canRetry|$_retryModelId|$_contextStartIndex|$_outputTokenLimit|$canContinue';
    if (status != _lastStatus) {
      _lastStatus = status;
      _statusChanges.notifyListeners();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _token?.cancel();
    _statusChanges.dispose();
    super.dispose();
  }
}
