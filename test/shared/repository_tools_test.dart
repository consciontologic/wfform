import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_repository.dart';

void main() {
  late Directory root;

  Future<ProcessResult> git(List<String> arguments) =>
      Process.run('git', arguments, workingDirectory: root.path);

  setUp(() async {
    root = Directory.systemTemp.createTempSync('wfform-repository-check-');
    expect((await git(['init', '-q', '-b', 'main'])).exitCode, 0);
    Directory('${root.path}/config').createSync();
    File('${root.path}/.gitignore').writeAsStringSync(
      '/config/local.json\n/build/\n/.local/\n/work/\n/outputs/\n',
    );
  });

  tearDown(() => root.deleteSync(recursive: true));

  test(
    'local key and build artifacts are excluded from prospective Git files',
    () async {
      File('${root.path}/config/local.json').writeAsStringSync(
        jsonEncode({'apiKey': 'local-test-credential-value'}),
      );
      File('${root.path}/README.md').writeAsStringSync('No credentials here.');
      expect(await checkRepository(root), isEmpty);
    },
  );

  test(
    'detects an exact local key in source without returning the key',
    () async {
      const secret = 'local-test-credential-value';
      File(
        '${root.path}/config/local.json',
      ).writeAsStringSync(jsonEncode({'apiKey': secret}));
      File('${root.path}/accidental.txt').writeAsStringSync(secret);
      final issues = await checkRepository(root);
      expect(issues.join('\n'), contains('accidental.txt'));
      expect(issues.join('\n'), isNot(contains(secret)));
    },
  );

  test(
    'detects staged secrets even if working copy was subsequently cleaned',
    () async {
      final secret = 'sk-or-v1-${List.filled(64, 'a').join()}';
      final leak = File('${root.path}/accidental.txt');
      leak.writeAsStringSync(secret);
      expect((await git(['add', 'accidental.txt'])).exitCode, 0);
      leak.writeAsStringSync('clean working copy');
      final issues = await checkRepository(root);
      expect(issues.join('\n'), contains('staged'));
      expect(issues.join('\n'), isNot(contains(secret)));
    },
  );

  test(
    'force-added local config is rejected even with an ignore rule',
    () async {
      File('${root.path}/config/local.json').writeAsStringSync('{}');
      expect((await git(['add', '-f', 'config/local.json'])).exitCode, 0);
      expect(
        (await checkRepository(root)).join('\n'),
        contains('config/local.json'),
      );
    },
  );

  test(
    'bootstrap reports an unborn branch without a fatal Git error',
    () async {
      Directory('${root.path}/xops/agent').createSync(recursive: true);
      Directory('${root.path}/xops/lib').createSync(recursive: true);
      File(
        'xops/agent/session-bootstrap.sh',
      ).copySync('${root.path}/xops/agent/session-bootstrap.sh');
      File('xops/lib/log.sh').copySync('${root.path}/xops/lib/log.sh');
      final result = await Process.run('bash', [
        '${root.path}/xops/agent/session-bootstrap.sh',
      ], workingDirectory: root.path);
      expect(result.exitCode, 0);
      final output = '${result.stdout}\n${result.stderr}';
      expect(output, contains('main'));
      expect(output, contains('no commits yet'));
      expect(output, isNot(contains('fatal:')));
    },
  );
}
