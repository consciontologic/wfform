import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('quality workflows only listen for develop and main pull requests', () {
    for (final file in ['web', 'security', 'companion']) {
      final workflow = File('.github/workflows/$file.yml').readAsStringSync();
      expect(
        workflow,
        contains('  pull_request:\n    branches: [develop, main]'),
      );
      expect(workflow, contains('labeled, unlabeled'));
      expect(workflow, isNot(contains('  push:')));
      expect(workflow, isNot(contains('  schedule:')));
      if (file != 'companion') {
        expect(workflow, isNot(contains('  workflow_dispatch:')));
      }
    }
  });

  test('quality jobs admit every develop PR and only hotfixes into main', () {
    const lane =
        "github.event_name == 'pull_request' && (\n"
        "        github.base_ref == 'develop' || (github.base_ref == 'main' && (\n"
        "          startsWith(github.head_ref, 'hotfix/') ||\n"
        "          startsWith(github.head_ref, 'codex/hotfix/') ||\n"
        "          startsWith(github.head_ref, 'claude/hotfix/') ||\n"
        "          (github.event.pull_request.head.repo.full_name == github.repository &&\n"
        "           startsWith(github.head_ref, 'copilot/') &&\n"
        "           contains(github.event.pull_request.labels.*.name, 'work:hotfix'))\n"
        '        )))';
    for (final file in ['web', 'security', 'companion']) {
      final workflow = File('.github/workflows/$file.yml').readAsStringSync();
      final jobs = workflow.split('jobs:').last;
      final firstJob = jobs.split('    steps:').first;
      expect(
        firstJob,
        contains(lane),
        reason: '$file must gate before a runner starts',
      );
    }
    final release = File('.github/workflows/companion.yml').readAsStringSync();
    expect(
      release,
      contains(
        "github.event_name == 'workflow_dispatch' && github.ref == 'refs/heads/main'",
      ),
    );
    expect(release, contains('needs: authorization'));
    expect(release, contains('needs: linux'));
    expect(release, contains('needs: [linux, windows]'));
  });

  test('security scans run once and promotion publication stays isolated', () {
    final security = File('.github/workflows/security.yml').readAsStringSync();
    final packages = File('.github/workflows/companion.yml').readAsStringSync();
    expect(security, isNot(contains('  workflow_call:')));
    expect(
      packages,
      isNot(contains('uses: \$/.github/workflows/security.yml')),
    );
    expect(packages, isNot(contains('make security.report')));
    expect(
      File('.github/workflows/web.yml').readAsStringSync(),
      isNot(contains('publish-website.sh')),
    );
  });

  test(
    'read-only jobs cache locked dependencies and verified scanner downloads',
    () {
      for (final file in ['web', 'security', 'companion']) {
        final workflow = File(
          '.github/workflows/$file.yml',
        ).readAsStringSync().split('  publish:').first;
        for (final setup
            in workflow.split('uses: subosito/flutter-action@').skip(1)) {
          final settings = setup.split('      - name:').first;
          expect(settings, contains('cache: true'));
          expect(settings, contains('pub-cache: true'));
          expect(
            settings,
            contains("hashFiles('pubspec.lock', 'companion/pubspec.lock')"),
          );
        }
      }
      final security = File(
        '.github/workflows/security.yml',
      ).readAsStringSync();
      expect(
        security,
        contains('actions/cache@5a3ec84eff668545956fd18022155c47e93e2684'),
      );
      expect(
        security,
        contains('security-downloads-gitleaks-8.30.1-zizmor-1.30.1-v1'),
      );
      expect(security, contains('PIP_CACHE_DIR:'));
      expect(security, contains('sha256sum --check --strict'));
      expect(
        security.indexOf('sha256sum --check --strict'),
        lessThan(security.indexOf('tar -xzf')),
      );
      final publish = File(
        '.github/workflows/companion.yml',
      ).readAsStringSync().split('  publish:').last;
      expect(publish, contains('cache: false'));
      expect(publish, isNot(contains('actions/cache@')));
    },
  );
  test(
    'CI tests the immutable PR head and publication uses trusted run source',
    () {
      var checkouts = 0;
      for (final name in ['web', 'security', 'companion']) {
        final workflow = File('.github/workflows/$name.yml').readAsStringSync();
        final readOnly = workflow.split('  publish:').first;
        for (final checkout
            in readOnly.split('uses: actions/checkout@').skip(1)) {
          final settings = checkout.split('      - name:').first;
          expect(
            settings,
            contains(
              r'ref: ${{ github.event.pull_request.head.sha || github.sha }}',
            ),
          );
          expect(settings, contains('persist-credentials: false'));
          checkouts++;
        }
      }
      expect(checkouts, 5);
      final publish = File(
        '.github/workflows/companion.yml',
      ).readAsStringSync().split('  publish:').last;
      final checkout = publish
          .split('uses: actions/checkout@')
          .last
          .split('      - name:')
          .first;
      expect(checkout, contains(r'ref: ${{ github.sha }}'));
      expect(checkout, isNot(contains('pull_request')));
    },
  );
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
      'GITHUB_EVENT_NAME': 'workflow_dispatch',
      'GITHUB_SHA': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'WFFORM_RELEASE_SHA': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'WFFORM_RELEASE_VERSION': '1.0.0',
      'WFFORM_RELEASE_PR': '3',
      'GITHUB_REPOSITORY': 'consciontologic/wfform',
      'WFFORM_DEPLOY_TOKEN': 'fixture-deploy-token',
      'GH_TOKEN': 'fixture-read-token',
      'RUNNER_TEMP': scratch.path,
      'TEST_CALLS': calls.path,
    };
    await executable('gh', r'echo "${TEST_LATEST_SHA:-$GITHUB_SHA}"');
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
      expect(
        commands(),
        contains(
          'consciontologic/wfform@aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        ),
      );
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
    environment['GITHUB_EVENT_NAME'] = 'workflow_dispatch';
    environment['TEST_LATEST_SHA'] = 'a-newer-commit';
    expect((await run()).exitCode, 0);
    expect(commands(), isEmpty);
  });

  test('manual tags and wrong dispatch revisions cannot publish', () async {
    environment['GITHUB_REF'] = 'refs/tags/1.0.0';
    environment['GITHUB_EVENT_NAME'] = 'push';
    expect((await run()).exitCode, 1);
    expect(commands(), isEmpty);
    environment['GITHUB_REF'] = 'refs/heads/main';
    environment['GITHUB_EVENT_NAME'] = 'workflow_dispatch';
    environment['WFFORM_RELEASE_SHA'] =
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    expect((await run()).exitCode, 1);
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
