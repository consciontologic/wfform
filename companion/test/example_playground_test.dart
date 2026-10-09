import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:wfformcomp/wfformcomp.dart';
import 'package:wfformcomp/process_runner.dart' show windowsChildEnvironment;
import '../../examples/tools_playground/settings.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> checkResourceReadFailures(Directory private) async {
  final copied = Directory.fromUri(private.uri.resolve('example/'))
    ..createSync();
  final fixture = File.fromUri(copied.uri.resolve('fixtures/fruit.json'));
  fixture.parent.createSync();
  final script = File(
    'examples/tools_playground/server.dart',
  ).copySync(File.fromUri(copied.uri.resolve('server.dart')).path);
  final process = await Process.start(Platform.resolvedExecutable, [
    script.path,
  ]);
  final responses = StreamIterator(
    process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
  );
  try {
    var id = 0;
    Future<Map> request(String method, Map params) async {
      process.stdin.writeln(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': ++id,
          'method': method,
          'params': params,
        }),
      );
      check(
        await responses.moveNext().timeout(const Duration(seconds: 5)),
        'Copied example server returned no response.',
      );
      return jsonDecode(responses.current) as Map;
    }

    for (final scenario in ['missing', 'oversized']) {
      if (scenario == 'oversized') fixture.writeAsStringSync('x' * 4097);
      final resource = await request('resources/read', {
        'uri': 'playground://samples/fruit',
      });
      check(
        resource['error'] is Map && !resource.containsKey('result'),
        '$scenario resource failure must be a JSON-RPC error, not a tool result.',
      );
      final tool = await request('tools/call', {
        'name': 'read_sample',
        'arguments': {'sample': 'fruit'},
      });
      check(
        tool['result']?['isError'] == true && !tool.containsKey('error'),
        '$scenario tool failure must remain a tool execution error.',
      );
    }
  } finally {
    await responses.cancel();
    process.kill();
    await process.exitCode.timeout(const Duration(seconds: 5));
  }
}

Future<void> main() async {
  final root = Directory.current;
  final scratch = Directory('.local').absolute..createSync(recursive: true);
  final private = scratch.createTempSync('playground-test-');
  final client = HttpClient();
  CompanionServer? server;
  Process? child;
  StreamIterator<String>? lines;
  try {
    await checkResourceReadFailures(private);
    final settings = await preparePlayground(root, private, port: 0);
    final originalConfig = settings.config.readAsStringSync();
    final originalToken = settings.token.readAsStringSync();
    await preparePlayground(root, private, port: 8788);
    check(
      settings.config.readAsStringSync() == originalConfig &&
          settings.token.readAsStringSync() == originalToken,
      'Starting again must preserve private configuration and pairing.',
    );
    if (!Platform.isWindows) {
      check(
        (settings.token.statSync().mode & 0x3f) == 0,
        'Pairing token must be owner-only.',
      );
    }
    server = await CompanionServer.start(
      CompanionConfig.fromJson(object(jsonDecode(originalConfig), 'config')),
      originalToken.trim(),
    );
    var id = 0;
    String? session;
    Future<Map> rpc(String method, [Map params = const {}]) async {
      final request = await client.postUrl(server!.endpoint);
      request.headers.contentType = ContentType.json;
      request.headers.set('Authorization', 'Bearer ${originalToken.trim()}');
      request.headers.set('Origin', 'http://localhost:8765');
      request.headers.set('Accept', 'application/json, text/event-stream');
      request.headers.set('MCP-Protocol-Version', '2025-11-25');
      if (session != null) request.headers.set('Mcp-Session-Id', session!);
      request.write(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': ++id,
          'method': method,
          'params': params,
        }),
      );
      final response = await request.close();
      check(response.statusCode == 200, 'Example HTTP request failed.');
      session ??= response.headers.value('Mcp-Session-Id');
      return jsonDecode(await utf8.decoder.bind(response).join()) as Map;
    }

    final init = await rpc('initialize', {
      'protocolVersion': '2025-11-25',
      'capabilities': {},
      'clientInfo': {'name': 'playground-smoke', 'version': '1.0.0'},
    });
    check(
      init['result']['capabilities']['tools'] is Map,
      'Real companion did not initialize with tools.',
    );
    final tools = (await rpc('tools/list'))['result']['tools'] as List;
    check(
      tools.map((tool) => tool['name']).toSet().containsAll({
            'playground__add_numbers',
            'playground__read_sample',
            'sales_report',
          }) &&
          tools.length == 3,
      'Unexpected playground tool discovery.',
    );
    final sum = (await rpc('tools/call', {
      'name': 'playground__add_numbers',
      'arguments': {'a': 17, 'b': 25},
    }))['result'];
    check(
      jsonDecode(sum['content'][0]['text'])['sum'] == 42,
      'Real stdio MCP result was not forwarded.',
    );
    final sample = (await rpc('tools/call', {
      'name': 'playground__read_sample',
      'arguments': {'sample': 'fruit'},
    }))['result'];
    check(
      jsonDecode(sample['content'][0]['text'])['fruit'][0]['name'] == 'apple',
      'MCP tool must return the actual bundled fixture.',
    );
    for (final arguments in [
      {'a': 1000001, 'b': 1},
      {'a': 1.5, 'b': 1},
      {'a': 1, 'b': 1, 'command': 'whoami'},
    ]) {
      final invalid = (await rpc('tools/call', {
        'name': 'playground__add_numbers',
        'arguments': arguments,
      }))['result'];
      check(invalid['isError'] == true, 'MCP server accepted invalid input.');
    }
    final traversal = (await rpc('tools/call', {
      'name': 'playground__read_sample',
      'arguments': {'sample': '../../config/local.json'},
    }))['result'];
    check(
      traversal['isError'] == true,
      'Arbitrary paths must not be accepted.',
    );
    final cli = (await rpc('tools/call', {
      'name': 'sales_report',
      'arguments': {},
    }))['result'];
    final execution = jsonDecode(cli['content'][0]['text']);
    final report = jsonDecode(execution['stdout']);
    check(
      cli['isError'] == false &&
          execution['exitCode'] == 0 &&
          report['rows'] == 3 &&
          report['totalCents'] == 1950,
      'Fixed local CLI must calculate real sample CSV totals.',
    );
    final badCli = (await rpc('tools/call', {
      'name': 'sales_report',
      'arguments': {'path': '/etc/passwd'},
    }))['result'];
    check(badCli['isError'] == true, 'CLI must not accept arbitrary inputs.');

    // Exercise the same standalone server through stdio, including resources
    // for MCP clients that support them (wfform currently exposes tools only).
    child = await Process.start(
      Platform.resolvedExecutable,
      [File('examples/tools_playground/server.dart').absolute.path],
      environment: Platform.isWindows
          ? windowsChildEnvironment(const {})
          : const {},
      includeParentEnvironment: false,
    );
    lines = StreamIterator(
      child.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
    Future<Map> stdio(Object message) async {
      child!.stdin.writeln(message is String ? message : jsonEncode(message));
      check(
        await lines!.moveNext().timeout(const Duration(seconds: 5)),
        'Example stdio server exited without a response.',
      );
      return jsonDecode(lines.current) as Map;
    }

    check(
      (await stdio('{broken'))['error']['code'] == -32700,
      'Malformed JSON needs a protocol error.',
    );
    final initialized = await stdio({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'initialize',
      'params': {'protocolVersion': '2024-11-05'},
    });
    check(
      initialized['result']['protocolVersion'] == '2024-11-05',
      'Standalone stdio must negotiate its supported version.',
    );
    final resources = await stdio({
      'jsonrpc': '2.0',
      'id': 2,
      'method': 'resources/list',
    });
    check(
      resources['result']['resources'].length == 2,
      'Example resources were not advertised.',
    );
    final resource = await stdio({
      'jsonrpc': '2.0',
      'id': 3,
      'method': 'resources/read',
      'params': {'uri': 'playground://samples/fruit'},
    });
    check(
      resource['result']['contents'][0]['text'] == sample['content'][0]['text'],
      'Resource and tool must use the same fixture.',
    );
    final denied = await stdio({
      'jsonrpc': '2.0',
      'id': 4,
      'method': 'resources/read',
      'params': {'uri': 'file:///etc/passwd'},
    });
    check(
      denied['error']['code'] == -32602,
      'Unknown resources must be denied.',
    );
    check(
      (await stdio('x' * 9000))['error']['code'] == -32600,
      'Oversized input must be bounded and rejected.',
    );
    final ping = await stdio({'jsonrpc': '2.0', 'id': 5, 'method': 'ping'});
    check(
      ping['result'] is Map,
      'A rejected request must not corrupt the next.',
    );
    stdout.writeln(
      'PASS real playground stdio MCP, companion HTTP bridge, '
      'local CLI, fixtures/resources, input bounds and private setup',
    );
  } finally {
    await lines?.cancel();
    child?.kill();
    client.close(force: true);
    await server?.close();
    private.deleteSync(recursive: true);
  }
}
