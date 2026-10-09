import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:wfformcomp/process_group.dart';
import 'package:wfformcomp/wfformcomp.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> checkUnfinishedOversizedRequest(
  Uri endpoint,
  String token, {
  required bool chunked,
}) async {
  final socket = await Socket.connect(endpoint.host, endpoint.port);
  final response = utf8.decoder
      .bind(socket)
      .transform(const LineSplitter())
      .first
      .then<Object>((line) => line, onError: (Object error) => error);
  try {
    socket.write(
      'POST /mcp HTTP/1.1\r\n'
      'Host: ${endpoint.authority}\r\n'
      'Authorization: Bearer $token\r\n'
      'Content-Type: application/json\r\n'
      '${chunked ? 'Transfer-Encoding: chunked' : 'Content-Length: 270000'}\r\n'
      '\r\n',
    );
    if (chunked) {
      // Cross the limit without finishing the body. Cancellation must not
      // destroy the connection before the server sends its rejection.
      socket.write('40001\r\n${'a' * 262145}\r\n');
    }
    await socket.flush();
    final status = await response.timeout(const Duration(seconds: 3));
    check(
      status == 'HTTP/1.1 413 Request Entity Too Large',
      '${chunked ? 'Chunked' : 'Declared'} oversized request lost its 413: $status',
    );
  } finally {
    socket.destroy();
  }
}

Future<void> main() async {
  void pass(String title) => stdout.writeln('PASS $title');

  const token = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN';
  const literal = r'hello; $(touch SHOULD_NOT_EXIST) " && echo injected';
  final direct = await (() async {
    try {
      return await startProgram(Platform.resolvedExecutable, [
        File('companion/test/command_fixture.dart').absolute.path,
        'echo',
        literal,
      ], environment: {});
    } on ProcessException catch (error) {
      throw StateError(
        'Direct startProgram launch failed: ${error.message} '
        '(errorCode=${error.errorCode}).',
      );
    }
  })();
  final directOutput = utf8.decoder.bind(direct.stdout).join();
  final directErrors = utf8.decoder.bind(direct.stderr).join();
  try {
    await direct.stdin.close();
    final code = await direct.exitCode.timeout(const Duration(seconds: 10));
    final errors = await directErrors;
    check(code == 0, 'Direct startProgram launch exited with $code: $errors');
    check(errors.isEmpty, 'Direct startProgram wrote stderr: $errors');
    check(
      (jsonDecode(await directOutput) as List).single == literal,
      'Direct startProgram launch changed argv.',
    );
    pass('direct startProgram launch gate and argv forwarding');
  } finally {
    stopProgram(direct);
  }
  final config = CompanionConfig.fromJson({
    'port': 0,
    'allowedOrigins': ['http://localhost:8080'],
    'tools': [
      for (final mode in ['echo', 'wait', 'flood', 'fail'])
        {
          'name': mode,
          'description': 'Test $mode',
          'executable': Platform.resolvedExecutable,
          'arguments': [
            File('companion/test/command_fixture.dart').absolute.path,
            mode,
            if (mode == 'echo') '{value}',
          ],
          'timeoutMs': mode == 'wait' ? 400 : 3000,
          'maxOutputBytes': 1024,
          'inputSchema': {
            'type': 'object',
            'properties': {
              if (mode == 'echo') 'value': {'type': 'string', 'minLength': 1},
            },
            'required': [if (mode == 'echo') 'value'],
            'additionalProperties': false,
          },
        },
    ],
  });
  final server = await CompanionServer.start(config, token);
  final client = HttpClient();
  var count = 0;
  Future<({int status, String body, HttpHeaders headers})> request(
    String method, {
    Object? body,
    String? auth = token,
    String? origin = 'http://localhost:8080',
    String protocol = '2025-11-25',
    String accept = 'application/json, text/event-stream',
    String? path,
    String? host,
  }) async {
    final req = await client.openUrl(
      method,
      path == null ? server.endpoint : server.endpoint.replace(path: path),
    );
    req.headers.contentType = ContentType.json;
    req.headers.set('Accept', accept);
    if (auth != null) req.headers.set('Authorization', 'Bearer $auth');
    if (origin != null) req.headers.set('Origin', origin);
    if (host != null) req.headers.set('Host', host);
    req.headers.set('MCP-Protocol-Version', protocol);
    if (body != null) req.write(jsonEncode(body));
    final res = await req.close();
    return (
      status: res.statusCode,
      body: await utf8.decoder.bind(res).join(),
      headers: res.headers,
    );
  }

  Future<Map<String, Object?>> rpc(
    String method, {
    Map<String, Object?> params = const {},
    Object? id,
  }) async {
    final res = await request(
      'POST',
      body: {
        'jsonrpc': '2.0',
        'id': id ?? ++count,
        'method': method,
        'params': params,
      },
    );
    check(res.status == 200, 'RPC HTTP failure: ${res.status}');
    return object(jsonDecode(res.body), 'response');
  }

  try {
    await checkUnfinishedOversizedRequest(
      server.endpoint,
      token,
      chunked: true,
    );
    await checkUnfinishedOversizedRequest(
      server.endpoint,
      token,
      chunked: false,
    );
    pass('unfinished oversized uploads receive 413 before client EOF');
    for (final auth in <String?>[null, 'wrong-token']) {
      check(
        (await request(
              'POST',
              auth: auth,
              body: {'jsonrpc': '2.0', 'id': 1, 'method': 'tools/list'},
            )).status ==
            401,
        'Unauthenticated tool access was allowed.',
      );
    }
    pass('missing/incorrect bearer is rejected');
    check(
      (await request(
            'POST',
            origin: 'https://attacker.invalid',
            body: {},
          )).status ==
          403,
      'Unexpected origin accepted',
    );
    check(
      (await request('POST', host: 'attacker.invalid', body: {})).status == 403,
      'Unexpected host accepted',
    );
    final preflight = await request('OPTIONS', auth: null);
    check(
      preflight.status == 204 &&
          preflight.headers.value('access-control-allow-origin') ==
              'http://localhost:8080',
      'Allowed preflight failed',
    );
    check(
      (await request(
            'OPTIONS',
            auth: null,
            origin: 'https://attacker.invalid',
          )).status ==
          403,
      'Unknown preflight origin accepted',
    );
    pass(
      'exact origins, DNS rebinding host guard and unauthenticated preflight',
    );
    check(
      (await request('GET', auth: null, path: '/health')).status == 200,
      'Health unavailable',
    );
    check(
      (await request('GET')).status == 405,
      'Unsupported standalone SSE accepted',
    );
    check(
      (await request('POST', protocol: 'future', body: {})).status == 400,
      'Unknown protocol accepted',
    );
    final init = await rpc('initialize', params: {'protocolVersion': 'future'});
    check(
      object(init['result'], 'result')['protocolVersion'] == '2025-11-25',
      'Version not negotiated',
    );
    final notification = await request(
      'POST',
      body: {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
    );
    check(
      notification.status == 202 && notification.body.isEmpty,
      'Notification should return empty202',
    );
    pass(
      'health, method/version checks, initialization negotiation and notifications',
    );
    final list =
        object((await rpc('tools/list'))['result'], 'result')['tools'] as List;
    check(list.length == 4, 'Tool discovery lost a tool');
    final unknown = await rpc(
      'tools/call',
      params: {'name': 'unknown', 'arguments': {}},
    );
    check(
      object(unknown['error'], 'error')['code'] == -32602,
      'Unknown tool accepted',
    );
    final missing = object(
      (await rpc(
        'tools/call',
        params: {'name': 'echo', 'arguments': {}},
      ))['result'],
      'result',
    );
    check(missing['isError'] == true, 'Required arguments not validated');
    final extra = object(
      (await rpc(
        'tools/call',
        params: {
          'name': 'echo',
          'arguments': {'value': 'ok', 'extra': 1},
        },
      ))['result'],
      'result',
    );
    check(extra['isError'] == true, 'Unexpected arguments accepted');
    pass('tool discovery and name/schema validation');
    final echoed = object(
      (await rpc(
        'tools/call',
        params: {
          'name': 'echo',
          'arguments': {'value': literal},
        },
      ))['result'],
      'result',
    );
    check(
      echoed['isError'] == false,
      'Echo tool failed before payload decode: '
      '${((echoed['content'] as List).single as Map)['text']}',
    );
    final payload =
        jsonDecode(
              ((echoed['content'] as List).single as Map)['text'] as String,
            )
            as Map;
    check(
      echoed['isError'] == false &&
          jsonDecode(payload['stdout'] as String).single == literal,
      'argv changed user input',
    );
    pass('program argv preserves shell metacharacters literally');
    for (final mode in ['wait', 'flood', 'fail']) {
      final result = object(
        (await rpc(
          'tools/call',
          params: {'name': mode, 'arguments': {}},
        ))['result'],
        'result',
      );
      check(result['isError'] == true, '$mode was not an execution error');
      final detail =
          jsonDecode(
                ((result['content'] as List).single as Map)['text'] as String,
              )
              as Map;
      if (mode == 'wait') {
        check(detail['timedOut'] == true, 'Timeout not marked');
      }
      if (mode == 'flood') {
        check(
          detail['outputLimitExceeded'] == true &&
              (detail['stdout'] as String).length <= 1024,
          'Output limit not enforced',
        );
      }
      if (mode == 'fail') {
        check(
          detail['exitCode'] == 7 && detail['stderr'] == 'intentional failure',
          'Exit/stderr lost',
        );
      }
    }
    pass('deadline, output bound and nonzero exit diagnostics');
    final pending = rpc(
      'tools/call',
      id: 'cancel-me',
      params: {'name': 'wait', 'arguments': {}},
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await request(
      'POST',
      body: {
        'jsonrpc': '2.0',
        'method': 'notifications/cancelled',
        'params': {'requestId': 'cancel-me'},
      },
    );
    final cancelled = object((await pending)['result'], 'result');
    check(
      cancelled['isError'] == true &&
          ((cancelled['content'] as List).single as Map)['text']
              .toString()
              .contains('cancelled'),
      'Cancellation not recorded',
    );
    pass('MCP cancellation stops the active process');
    final sse = await request(
      'POST',
      accept: 'text/event-stream',
      body: {'jsonrpc': '2.0', 'id': 99, 'method': 'tools/list'},
    );
    check(
      sse.headers.contentType?.mimeType == 'text/event-stream' &&
          sse.body.startsWith('event: message\ndata: '),
      'SSE response malformed',
    );
    final malformed = await request('POST', body: []);
    check(
      object(jsonDecode(malformed.body), 'response')['error'] != null,
      'Batch accepted',
    );
    final large = await request('POST', body: {'x': 'a' * 270000});
    check(large.status == 413, 'Oversized request accepted');
    pass('SSE response, malformed envelope and request byte limits');
    for (final value in [
      '*',
      'http://example.com',
      'https://wfform.com/path',
      'null',
    ]) {
      var rejected = false;
      try {
        CompanionConfig.fromJson({
          'allowedOrigins': [value],
        });
      } on FormatException {
        rejected = true;
      }
      check(rejected, 'Unsafe origin accepted');
    }
    var unsupported = false;
    try {
      CompanionConfig.fromJson({
        'allowedOrigins': ['https://wfform.com'],
        'tools': [
          {
            'name': 'bad',
            'description': 'bad',
            'executable': Platform.resolvedExecutable,
            'inputSchema': {
              'type': 'object',
              'additionalProperties': false,
              'oneOf': [],
            },
          },
        ],
      });
    } on FormatException {
      unsupported = true;
    }
    check(unsupported, 'Unsupported JSON schema silently ignored');
    final disconnected = HttpClient();
    final abandoned = await disconnected.postUrl(server.endpoint);
    abandoned.headers.contentType = ContentType.json;
    abandoned.headers.set('Authorization', 'Bearer $token');
    abandoned.write(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': 'abandoned',
        'method': 'tools/call',
        'params': {'name': 'wait', 'arguments': {}},
      }),
    );
    final disconnectedDone = (() async {
      try {
        await (await abandoned.close()).drain<void>();
      } on IOException {
        /* Expected client abort. */
      }
    })();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    disconnected.close(force: true);
    await disconnectedDone;
    await Future<void>.delayed(const Duration(milliseconds: 450));
    check(
      (await rpc('ping'))['result'] is Map,
      'Closed browser socket stopped the server',
    );
    pass(
      'unsafe configuration/schema rejection and disconnected-client recovery',
    );
  } finally {
    client.close(force: true);
    await server.close();
  }
}
