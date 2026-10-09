import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:wfformcomp/wfformcomp.dart';

Future<void> main() async {
  const token = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN';
  final parent = Directory('.local/companion-tests')
    ..createSync(recursive: true);
  final scratch = parent.createTempSync('stdio-sessions-');
  final calls = File('${scratch.path}/calls');
  final server = await CompanionServer.start(
    CompanionConfig.fromJson({
      'port': 0,
      'allowedOrigins': ['https://wfform.com'],
      'mcpServers': [
        {
          'name': 'local',
          'executable': Platform.resolvedExecutable,
          'arguments': [
            File('companion/test/stdio_fixture.dart').absolute.path,
            'record',
            calls.absolute.path,
          ],
          'allowedTools': ['echo'],
          'timeoutMs': 1500,
        },
      ],
    }),
    token,
  );
  final client = HttpClient();
  Future<({Map? body, String? session})> rpc(
    String method,
    Object? id, {
    String? session,
    Map params = const {},
  }) async {
    final request = await client.postUrl(server.endpoint);
    request.headers.contentType = ContentType.json;
    request.headers.set('Authorization', 'Bearer $token');
    request.headers.set('Origin', 'https://wfform.com');
    if (session != null) request.headers.set('MCP-Session-Id', session);
    request.write(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': ?id,
        'method': method,
        'params': params,
      }),
    );
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    return (
      body: text.isEmpty ? null : jsonDecode(text) as Map,
      session: response.headers.value('mcp-session-id'),
    );
  }

  try {
    final a = (await rpc('initialize', 1)).session!;
    final b = (await rpc('initialize', 1)).session!;
    final pending = rpc(
      'tools/call',
      2,
      session: a,
      params: {
        'name': 'local__echo',
        'arguments': {'text': 'A'},
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final rejected = await rpc(
      'tools/call',
      2,
      session: b,
      params: {
        'name': 'local__echo',
        'arguments': {'text': 'B'},
      },
    );
    final error = rejected.body?['result'] as Map?;
    if (error?['isError'] != true ||
        !error!['content'].single['text'].toString().contains('busy') ||
        error.containsKey('_meta')) {
      throw StateError(
        'Tab B was dispatched or made uncertain while tab A owned the shared stdio child.',
      );
    }
    await rpc(
      'notifications/cancelled',
      null,
      session: a,
      params: {'requestId': 2},
    );
    final interrupted = (await pending).body?['result'] as Map;
    if (interrupted['_meta']?['wfform.com/outcome'] != 'uncertain') {
      throw StateError('Tab A cancellation lost uncertainty.');
    }
    if (calls.readAsLinesSync().join(',') != 'A') {
      throw StateError('A second tab reached the child process.');
    }
    stdout.writeln(
      'PASS a shared stdio child admits one call; another tab is rejected before dispatch and cancellation stays scoped',
    );
  } finally {
    client.close(force: true);
    await server.close();
    scratch.deleteSync(recursive: true);
  }
}
