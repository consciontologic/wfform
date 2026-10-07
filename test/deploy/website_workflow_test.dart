import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory scratch;
  late File calls;
  late Map<String, String> environment;

  Future<void> executable(String name, String body) async {
    final file = File('${scratch.path}/$name');
    file.writeAsStringSync('#!/usr/bin/env bash\nset -euo pipefail\n$body\n');
    expect((await Process.run('chmod', ['700', file.path])).exitCode, 0);
  }

  setUp(() async {
    Directory('work').createSync();
    scratch = Directory('work').createTempSync('website-workflow-').absolute;
    calls = File('${scratch.path}/calls');
    environment = {
      'PATH': '${scratch.path}:${Platform.environment['PATH']}',
      'GITHUB_ACTIONS': 'true',
      'GITHUB_REF': 'refs/heads/main',
      'GITHUB_EVENT_NAME': 'push',
      'GITHUB_SHA': 'fixture-source-sha',
      'GITHUB_REPOSITORY': 'consciontologic/wfform',
      'WFFORM_DEPLOY_TOKEN': 'fixture-deploy-token',
      'GH_TOKEN': 'fixture-read-token',
      'RUNNER_TEMP': scratch.path,
      'TEST_CALLS': calls.path,
    };
    await executable('gh', r'echo "${TEST_LATEST_SHA:-fixture-source-sha}"');
    await executable('dart', r'''
printf 'dart %s\n' "$*" >> "$TEST_CALLS"
printf 'index.html\0.wfform-deployment.json\0' > "$5"
''');
    await executable('git', r'''
printf 'git %s\n' "$*" >> "$TEST_CALLS"
if [[ " $* " == *' for-each-ref '* ]]; then
  printf '%s' "${TEST_HEADS:-}"
elif [[ " $* " == *' show-ref '* ]]; then
  exit "${TEST_MAIN_MISSING:-0}"
elif [[ " $* " == *' diff --cached --quiet '* ]]; then
  exit "${TEST_CHANGED:-1}"
elif [[ " $* " == *' push origin '* ]]; then
  exit "${TEST_PUSH_FAILURE:-0}"
fi
''');
  });
  tearDown(() => scratch.deleteSync(recursive: true));

  Future<ProcessResult> run() => Process.run('bash', [
    'deploy/scripts/publish-website.sh',
    'build/fixture-public',
  ], environment: environment);

  String commands() => calls.existsSync() ? calls.readAsStringSync() : '';

  test('public CLI and CI builds use the custom domain root', () {
    final makefile = File('Makefile').readAsStringSync();
    final workflow = File('.github/workflows/web.yml').readAsStringSync();
    const build =
        'dart run tool/build.dart --public --output=build/publish-web --base-href=/';
    expect(makefile, contains('build.public:\n\t$build\n'));
    expect(workflow, contains('        run: $build\n'));
  });

  test(
    'empty target is initialized and changed artifacts commit and push once',
    () async {
      final result = await run();
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(
        commands(),
        contains(
          'clone --no-checkout https://github.com/consciontologic/wfform.com.git ',
        ),
      );
      expect(commands(), isNot(contains('metaphy6/')));
      expect(commands(), contains('checkout --orphan main'));
      expect(commands(), contains('prepare_website.dart build/fixture-public'));
      expect(commands(), contains('add --all --force --pathspec-from-file='));
      expect(commands(), contains('--pathspec-file-nul'));
      expect(commands(), contains('consciontologic/wfform@fixture-source-sha'));
      expect(RegExp('push origin HEAD:main').allMatches(commands()).length, 1);
      expect(commands(), isNot(contains('fixture-deploy-token')));
      expect(
        scratch.listSync().where((f) => f.path.contains('askpass.')),
        isEmpty,
      );
    },
  );

  test(
    'existing main and unchanged artifacts produce no commit or push',
    () async {
      environment['TEST_HEADS'] = 'refs/remotes/origin/main';
      environment['TEST_CHANGED'] = '0';
      expect((await run()).exitCode, 0);
      expect(commands(), contains('checkout -B main origin/main'));
      expect(commands(), isNot(contains(' commit ')));
      expect(commands(), isNot(contains(' push ')));
    },
  );

  test('pull requests and stale source runs cannot publish', () async {
    environment['GITHUB_EVENT_NAME'] = 'pull_request';
    expect((await run()).exitCode, 1);
    expect(commands(), isEmpty);
    environment['GITHUB_EVENT_NAME'] = 'push';
    environment['TEST_LATEST_SHA'] = 'a-newer-commit';
    expect((await run()).exitCode, 0);
    expect(commands(), isEmpty);
  });

  test('missing deployment token fails before any Git operation', () async {
    environment['WFFORM_DEPLOY_TOKEN'] = '';
    final result = await run();
    expect(result.exitCode, 1);
    expect(result.stderr, contains('WFFORM_DEPLOY_TOKEN'));
    expect(commands(), isEmpty);
  });

  test(
    'another source repository cannot publish to the migrated destination',
    () async {
      environment['GITHUB_REPOSITORY'] = 'fixture/another-repository';
      final result = await run();
      expect(result.exitCode, 1);
      expect(commands(), isEmpty);
    },
  );

  test(
    'destination without main fails instead of replacing another branch',
    () async {
      environment['TEST_HEADS'] = 'refs/remotes/origin/another-branch';
      environment['TEST_MAIN_MISSING'] = '1';
      expect((await run()).exitCode, 1);
      expect(commands(), isNot(contains('checkout --orphan')));
      expect(commands(), isNot(contains(' push ')));
    },
  );

  test('a failed destination push is not forced or retried', () async {
    environment['TEST_PUSH_FAILURE'] = '1';
    expect((await run()).exitCode, 1);
    expect(RegExp('push origin HEAD:main').allMatches(commands()).length, 1);
    expect(commands(), isNot(contains('push --force')));
  });
}
