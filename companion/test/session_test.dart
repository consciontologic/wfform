import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:wfformcomp/wfformcomp.dart';

Future<void> main() async {
  const token = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN';
  final server = await CompanionServer.start(
    CompanionConfig.fromJson({
      'port': 0,
      'allowedOrigins': ['https://wfform.com'],
      'tools': [
        {
          'name': 'wait',
          'description': 'Wait fixture',
          'executable': Platform.resolvedExecutable,
          'arguments': [
            File('companion/test/command_fixture.dart').absolute.path,
            'wait',
          ],
          'timeoutMs': 3000,
        },
      ],
    }),
    token,
  );
  final client = HttpClient();
  Future<({int status, Map? body, String? session, String? exposed})> call(
    String method,
    Object? id, {
    String? session,
    Map params = const {},
    String verb = 'POST',
  }) async {
    final request = await client.openUrl(verb, server.endpoint);
    request.headers.contentType = ContentType.json;
    request.headers.set('Authorization', 'Bearer $token');
    request.headers.set('Origin', 'https://wfform.com');
    if (session != null) request.headers.set('MCP-Session-Id', session);
    if (verb == 'POST') {
      request.write(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': ?id,
          'method': method,
          'params': params,
        }),
      );
    }
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    return (
      status: response.statusCode,
      body: text.isEmpty ? null : jsonDecode(text) as Map,
      session: response.headers.value('mcp-session-id'),
      exposed: response.headers.value('access-control-expose-headers'),
    );
  }

  try {
    final first = await call(
      'initialize',
      1,
      params: {'protocolVersion': '2025-11-25'},
    );
    final second = await call(
      'initialize',
      1,
      params: {'protocolVersion': '2025-11-25'},
    );
    if (first.session == null ||
        second.session == null ||
        first.session == second.session ||
        !first.exposed!.contains('MCP-Session-Id')) {
      throw StateError(
        'Initialize did not issue distinct browser-visible sessions.',
      );
    }
    final a = call(
      'tools/call',
      2,
      session: first.session,
      params: {'name': 'wait', 'arguments': {}},
    );
    var secondDone = false;
    final b =
        call(
          'tools/call',
          2,
          session: second.session,
          params: {'name': 'wait', 'arguments': {}},
        ).then((result) {
          secondDone = true;
          return result;
        });
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await call(
      'notifications/cancelled',
      null,
      session: first.session,
      params: {'requestId': 2},
    );
    final cancelled = await a;
    if (cancelled.body?['result']?['isError'] != true) {
      throw StateError('First session did not cancel.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (secondDone) {
      throw StateError(
        'Another tab with the same request ID was cancelled/rejected.',
      );
    }
    await call(
      'notifications/cancelled',
      null,
      session: second.session,
      params: {'requestId': 2},
    );
    if ((await b).body?['result']?['isError'] != true) {
      throw StateError('Second session did not cancel independently.');
    }
    if ((await call('tools/list', 3, session: 'unknown-session')).status !=
        404) {
      throw StateError('Unknown session was accepted.');
    }
    if ((await call('', null, session: first.session, verb: 'DELETE')).status !=
        204) {
      throw StateError('Session deletion failed.');
    }
    if ((await call('tools/list', 4, session: first.session)).status != 404) {
      throw StateError('Deleted session remained usable.');
    }
    stdout.writeln(
      'PASS browser-visible sessions isolate duplicate request IDs and cancellation between tabs',
    );
  } finally {
    client.close(force: true);
    await server.close();
  }
}
