import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:wfformcomp/private_file.dart';

Future<void> main() async {
  final parent = Directory('.local/companion-tests')
    ..createSync(recursive: true);
  final scratch = parent.createTempSync('cli-');
  final config = '${scratch.path}/config.json';
  final token = '${scratch.path}/pairing-token';
  final binary = Platform.environment['WFFORMCOMP_TEST_BINARY'];
  final webRoot = Platform.environment['WFFORMCOMP_TEST_WEB_ROOT'];
  Future<ProcessResult> run(List<String> args) =>
      Process.run(binary ?? Platform.resolvedExecutable, [
        if (binary == null) ...['run', 'companion/bin/wfformcomp.dart'],
        ...args,
      ]);
  try {
    final initialized = await run([
      'init',
      '--config',
      config,
      '--token-file',
      token,
    ]);
    if (initialized.exitCode != 0) throw StateError('CLI init failed.');
    final secret = File(token).readAsStringSync().trim();
    if (secret.length < 32 ||
        initialized.stdout.toString().contains(secret) ||
        initialized.stderr.toString().contains(secret)) {
      throw StateError('CLI exposed or failed to generate pairing token.');
    }
    await requirePrivateFile(File(token));
    final repeated = await run([
      'init',
      '--config',
      config,
      '--token-file',
      token,
    ]);
    if (repeated.exitCode == 0 ||
        File(token).readAsStringSync().trim() != secret) {
      throw StateError('CLI overwrote existing credentials.');
    }
    File(config).writeAsStringSync(
      jsonEncode({
        'port': 0,
        'allowedOrigins': ['https://wfform.com'],
        'tools': [
          {
            'name': 'echo',
            'description': 'Packaged CLI fixture',
            'executable': Platform.resolvedExecutable,
            'arguments': [
              File('companion/test/command_fixture.dart').absolute.path,
              'echo',
              'literal & value',
            ],
          },
        ],
      }),
    );
    final process = await Process.start(binary ?? Platform.resolvedExecutable, [
      if (binary == null) ...['run', 'companion/bin/wfformcomp.dart'],
      'serve',
      '--config',
      config,
      '--token-file',
      token,
      if (webRoot != null) ...['--web-root', webRoot],
    ]);
    final lines = StreamIterator(
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
    final diagnostics = process.stderr.transform(utf8.decoder).join();
    final client = HttpClient();
    try {
      if (!await lines.moveNext().timeout(const Duration(seconds: 10))) {
        throw StateError('CLI did not advertise endpoint.');
      }
      final match = RegExp(
        r'http://127\.0\.0\.1:\d+/mcp',
      ).firstMatch(lines.current);
      if (match == null || lines.current.contains(secret)) {
        throw StateError('CLI readiness output invalid.');
      }
      if (webRoot != null) {
        final web = await (await client.getUrl(
          Uri.parse(match.group(0)!).replace(path: '/'),
        )).close();
        final html = await utf8.decoder.bind(web).join();
        if (web.statusCode != 200 || !html.contains('flutter_bootstrap.js')) {
          throw StateError('Extracted package did not serve its web build.');
        }
      }
      final request = await client.postUrl(Uri.parse(match.group(0)!));
      request.headers.contentType = ContentType.json;
      request.headers.set('Authorization', 'Bearer $secret');
      request.headers.set('Origin', 'https://wfform.com');
      request.write(
        jsonEncode({'jsonrpc': '2.0', 'id': 1, 'method': 'tools/list'}),
      );
      final response = await request.close();
      final body = jsonDecode(await utf8.decoder.bind(response).join()) as Map;
      if (response.statusCode != 200 ||
          (body['result']['tools'] as List).single['name'] != 'echo') {
        throw StateError('CLI MCP endpoint not usable.');
      }
      final call = await client.postUrl(Uri.parse(match.group(0)!));
      call.headers.contentType = ContentType.json;
      call.headers.set('Authorization', 'Bearer $secret');
      call.write(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 2,
          'method': 'tools/call',
          'params': {'name': 'echo', 'arguments': <String, Object?>{}},
        }),
      );
      final called =
          jsonDecode(await utf8.decoder.bind(await call.close()).join()) as Map;
      final result = called['result'] as Map;
      final detail = jsonDecode(result['content'][0]['text'] as String) as Map;
      if (result['isError'] != false ||
          detail['stdout'] != '["literal & value"]') {
        throw StateError('Compiled CLI did not execute configured program.');
      }
    } finally {
      client.close(force: true);
      process.kill(ProcessSignal.sigterm);
      final status = await process.exitCode.timeout(const Duration(seconds: 5));
      await lines.cancel();
      final errors = await diagnostics;
      // Windows Process.kill terminates immediately; the OS closes job handles.
      // Graceful in-process server.close is tested by the protocol suites.
      if ((!Platform.isWindows && status != 0) || errors.contains(secret)) {
        throw StateError('CLI shutdown or log secrecy failed.');
      }
    }
    stdout.writeln(
      'PASS CLI init/private token/no overwrite, real serving/auth and clean shutdown',
    );
  } finally {
    scratch.deleteSync(recursive: true);
  }
}
