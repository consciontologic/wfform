import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:wfformcomp/wfformcomp.dart';

Future<void> main() async {
  if (!Platform.isLinux && !Platform.isWindows) {
    throw UnsupportedError('This acceptance check requires Linux or Windows.');
  }
  const token = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN';
  final parent = Directory('.local/companion-tests')
    ..createSync(recursive: true);
  final scratch = parent.createTempSync('tree-');
  final ready = File('${scratch.path}/child-pid').absolute;
  final server = await CompanionServer.start(
    CompanionConfig.fromJson({
      'port': 0,
      'allowedOrigins': ['https://wfform.com'],
      'tools': [
        {
          'name': 'spawn',
          'description': 'Child cleanup fixture',
          'executable': Platform.resolvedExecutable,
          'arguments': [
            File('companion/test/command_fixture.dart').absolute.path,
            'spawn',
            ready.path,
          ],
          'timeoutMs': 15000,
        },
      ],
    }),
    token,
  );
  final client = HttpClient();
  Future<String> rpc(Map<String, Object?> body) async {
    final req = await client.postUrl(server.endpoint);
    req.headers.contentType = ContentType.json;
    req.headers.set('Authorization', 'Bearer $token');
    req.write(jsonEncode(body));
    return utf8.decoder.bind(await req.close()).join();
  }

  try {
    final pending = rpc({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'tools/call',
      'params': {'name': 'spawn', 'arguments': {}},
    });
    final startup = Stopwatch()..start();
    while (!ready.existsSync() && startup.elapsedMilliseconds < 10000) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (!ready.existsSync()) {
      throw StateError('Fixture child never became ready.');
    }
    final watch = Stopwatch()..start();
    await rpc({
      'jsonrpc': '2.0',
      'method': 'notifications/cancelled',
      'params': {'requestId': 1},
    });
    final result = (jsonDecode(await pending) as Map)['result'] as Map;
    final detail =
        jsonDecode((result['content'] as List).single['text'] as String) as Map;
    if (detail['cancelled'] != true || watch.elapsedMilliseconds > 3000) {
      throw StateError(
        'Cancellation failed to close descendant pipes promptly.',
      );
    }
    final child = int.parse(detail['stdout'] as String);
    if (Platform.isWindows) {
      final tasklist = await Process.run(
        '${Platform.environment['SystemRoot']}\\System32\\tasklist.exe',
        ['/FI', 'PID eq $child', '/FO', 'CSV', '/NH'],
      );
      if (tasklist.exitCode != 0 ||
          tasklist.stdout.toString().contains(',"$child",')) {
        throw StateError('A descendant survived Windows job cancellation.');
      }
    } else {
      final stat = File('/proc/$child/stat');
      if (stat.existsSync()) {
        final value = stat.readAsStringSync();
        if (value.substring(value.lastIndexOf(')') + 2).split(' ').first !=
            'Z') {
          throw StateError('A descendant survived process-group cancellation.');
        }
      }
    }
    stdout.writeln(
      'PASS ${Platform.operatingSystem} cancellation terminates descendants and releases inherited pipes',
    );
  } finally {
    client.close(force: true);
    await server.close();
    scratch.deleteSync(recursive: true);
  }
}
