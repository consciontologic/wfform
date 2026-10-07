import 'dart:async';
import 'dart:convert';

import 'package:wfform/features/models/model.dart';
import 'package:wfform/shared/transport.dart';

const testModel = FreeModel(
  id: 'maker/example:free',
  name: 'Example',
  supportedParameters: ['reasoning', 'max_tokens'],
);

class SentRequest {
  SentRequest(this.method, this.uri, this.headers, this.body, this.cancel);
  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final Object? body;
  final CancelToken? cancel;
  Map<String, dynamic> get json =>
      jsonDecode(body as String) as Map<String, dynamic>;
}

class FakeTransport implements ApiTransport {
  FakeTransport(this.handler);
  final FutureOr<ApiResponse> Function(SentRequest) handler;
  final requests = <SentRequest>[];
  @override
  Future<ApiResponse> send(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    Object? body,
    required Duration timeout,
    CancelToken? cancel,
  }) async {
    final request = SentRequest(method, uri, headers, body, cancel);
    requests.add(request);
    cancel?.throwIfCancelled();
    return await handler(request);
  }
}

ApiResponse jsonResponse(
  Object object, {
  int status = 200,
  Map<String, String> headers = const {},
}) => ApiResponse(status, {
  'content-type': 'application/json',
  ...headers,
}, Stream.value(utf8.encode(jsonEncode(object))));

String delta(String content, {String? reasoning, String? provider}) =>
    'data: ${jsonEncode({
      'id': 'gen-test',
      'provider': ?provider,
      'choices': [
        {
          'index': 0,
          'delta': {'content': content, 'reasoning': ?reasoning},
        },
      ],
    })}\n\n';

ApiResponse streamResponse(String text, {int chunkSize = 7}) {
  final bytes = utf8.encode(text);
  final chunks = <List<int>>[];
  for (var i = 0; i < bytes.length; i += chunkSize) {
    chunks.add(
      bytes.sublist(
        i,
        i + chunkSize > bytes.length ? bytes.length : i + chunkSize,
      ),
    );
  }
  return ApiResponse(200, {
    'content-type': 'text/event-stream',
  }, Stream.fromIterable(chunks));
}

ApiResponse endpoints() => jsonResponse({
  'data': {
    'endpoints': [
      {
        'provider_name': 'Test provider',
        'status': 0,
        'uptime_last_30m': 99.9,
        'pricing': {'prompt': '0', 'completion': '0', 'request': '0'},
      },
    ],
  },
});
