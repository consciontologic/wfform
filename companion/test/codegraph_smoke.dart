import 'dart:convert';
import 'dart:io';
import 'package:wfformcomp/wfformcomp.dart';

/// Opt-in real local integration; requires `make codeg` and the pinned launcher.
Future<void> main() async {
  final server = await CompanionServer.start(
    CompanionConfig.fromJson({
      'port': 0,
      'allowedOrigins': ['https://wfform.com'],
      'mcpServers': [
        {
          'name': 'codegraph',
          'executable': File('xops/agent/codegraph.sh').absolute.path,
          'arguments': ['serve', '--mcp', '--path', Directory.current.path],
          'environment': {'PATH': Platform.environment['PATH']!},
          'allowedTools': ['codegraph_explore'],
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
    request.headers.set('Origin', 'https://wfform.com');
    request.headers.set('MCP-Protocol-Version', '2025-11-25');
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
    if (list.length != 1) {
      throw StateError(
        'CodeGraph tool count did not match the configured allowlist.',
      );
    }
    final search = await rpc('tools/call', {
      'name': 'codegraph__codegraph_explore',
      'arguments': {'query': 'ChatController send', 'maxFiles': 2},
    });
    final source = (search['result']['content'] as List)
        .map((e) => e['text'])
        .join('\n');
    if (!source.contains('ChatController') ||
        !source.contains('lib/features/chat/chat_controller.dart')) {
      throw StateError('CodeGraph did not find the current chat controller.');
    }
    stdout.writeln(
      'PASS real pinned CodeGraph discovery/source exploration through authenticated HTTP → stdio companion',
    );
  } finally {
    client.close(force: true);
    await server.close();
  }
}
