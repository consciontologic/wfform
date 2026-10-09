import 'dart:convert';
import 'dart:io';
import 'package:wfformcomp/wfformcomp.dart';

Future<void> main() async {
  final server = await CompanionServer.start(
    CompanionConfig.fromJson({
      'port': 0,
      'allowedOrigins': ['https://wfform.com'],
      'tools': [],
      'mcpServers': [
        {
          'name': 'local',
          'executable': Platform.resolvedExecutable,
          'arguments': [
            File('companion/test/stdio_fixture.dart').absolute.path,
          ],
          'allowedTools': ['echo'],
        },
      ],
    }),
    '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN',
  );
  final client = HttpClient();
  var id = 0;
  Future<Map> rpc(String method, [Map params = const {}]) async {
    final request = await client.postUrl(server.endpoint);
    request.headers.contentType = ContentType.json;
    request.headers.set(
      'Authorization',
      'Bearer 0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN',
    );
    request.write(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': ++id,
        'method': method,
        'params': params,
      }),
    );
    final response = await request.close();
    return jsonDecode(await utf8.decoder.bind(response).join()) as Map;
  }

  try {
    final list = (await rpc('tools/list'))['result']['tools'] as List;
    if (list.length != 1 || list.single['name'] != 'local__echo') {
      throw StateError(
        'Stdio proxy did not expose only its explicitly allowed tool.',
      );
    }
    final result = await rpc('tools/call', {
      'name': 'local__echo',
      'arguments': {'text': 'unpredictable-local-result'},
    });
    if (result['result']['content'].single['text'] !=
        'unpredictable-local-result') {
      throw StateError('Stdio result lost.');
    }
    final denied = await rpc('tools/call', {
      'name': 'local__hidden',
      'arguments': {},
    });
    if (denied['error'] == null) {
      throw StateError('Unapproved MCP tool exposed.');
    }
    var cycleRejected = false;
    try {
      final invalid = await CompanionServer.start(
        CompanionConfig.fromJson({
          'port': 0,
          'allowedOrigins': ['https://wfform.com'],
          'mcpServers': [
            {
              'name': 'loop',
              'executable': Platform.resolvedExecutable,
              'arguments': [
                File('companion/test/stdio_fixture.dart').absolute.path,
                'cycling',
              ],
              'allowedTools': ['echo'],
            },
          ],
        }),
        '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN',
      ).timeout(const Duration(seconds: 3));
      await invalid.close();
    } on FormatException {
      cycleRejected = true;
    }
    if (!cycleRejected) {
      throw StateError('Cyclic empty MCP tool pages were not rejected.');
    }
    stdout.writeln(
      'PASS stdio initialize/discovery, prefix routing, allowed-tools restriction, bounded cyclic pagination and real child RPC',
    );
  } finally {
    client.close(force: true);
    await server.close();
  }
}
