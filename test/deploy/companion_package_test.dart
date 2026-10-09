import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/build.dart';
import '../../tool/build_companion.dart';

void main() {
  test('archive instructions keep local guide links and anchors usable', () {
    expect(
      companionPackageInstructions(
        '[Guide](tools.md) [Setup](wfformcomp.md#setup)',
      ),
      '[Guide](TOOLS.md) [Setup](README.md#setup)',
    );
  });
  test('release dispatch requires approved main and both native packages', () {
    final workflow = File('.github/workflows/companion.yml').readAsStringSync();
    expect(workflow, contains('  workflow_dispatch:'));
    expect(workflow, contains('permissions:\n  contents: read'));
    expect(workflow, contains('runs-on: windows-2022'));
    expect(workflow, contains('needs: [linux, windows]'));
    expect(
      workflow,
      allOf(
        contains("github.event_name == 'workflow_dispatch'"),
        contains("github.ref == 'refs/heads/main'"),
        contains('release_delivery.py publish'),
        contains('environment: production'),
      ),
    );
    final commands = workflow
        .split('  windows:')
        .last
        .split('  publish:')
        .first;
    expect(commands, contains('Expand-Archive'));
    expect(commands, contains('WFFORMCOMP_TEST_BINARY'));
    expect(commands, contains('WFFORMCOMP_TEST_WEB_ROOT'));
    expect(commands, contains('companion/test/cli_test.dart'));
    expect(commands, contains('process_group'));
    expect(commands, contains('private_file'));
    expect(commands, contains('process_runner'));
  });
  test(
    'release dispatch packages without repeating PR quality or runtime tests',
    () {
      final workflow = File(
        '.github/workflows/companion.yml',
      ).readAsStringSync();
      final steps = workflow.split('      - name:').skip(1);
      var guarded = 0;
      for (final step in steps) {
        if (step.contains('make verify') ||
            step.contains('dart analyze ') ||
            step.contains('flutter test ') ||
            step.contains('companion/test/') ||
            step.contains('Verify Windows package can be rebuilt')) {
          expect(
            step,
            contains("if: github.event_name == 'pull_request'"),
            reason: step.split('\n').first,
          );
          guarded++;
        }
      }
      expect(guarded, 4);
      expect(workflow, isNot(contains('make verify')));
      expect(workflow, contains('Build Windows executable and ZIP'));
      expect(workflow, contains('Verify Windows package can be rebuilt'));
      expect(workflow, contains('make release.package'));
      expect(workflow, contains('release_delivery.py approval'));
      expect(workflow, isNot(contains('workflow/security.yml')));
    },
  );
  test('native package identity uses Windows exe and zip, Linux tar', () {
    final windows = CompanionPackageTarget('windows', 'x64');
    expect(windows.binaryName, 'wfformcomp-1.0.0-windows-x64.exe');
    expect(windows.installedBinaryName, 'wfformcomp.exe');
    expect(windows.archiveName, 'wfformcomp-1.0.0-windows-x64.zip');
    expect(windows.metadataName, 'wfformcomp-1.0.0-windows-x64.json');
    final linux = CompanionPackageTarget('linux', 'x64');
    expect(linux.binaryName, 'wfformcomp-1.0.0-linux-x64');
    expect(linux.installedBinaryName, 'wfformcomp');
    expect(linux.archiveName, 'wfformcomp-1.0.0-linux-x64.tar.gz');
    expect(
      () => CompanionPackageTarget('macos', 'arm64'),
      throwsUnsupportedError,
    );
    expect(
      () => CompanionPackageTarget('windows', 'arm64'),
      throwsUnsupportedError,
    );
  });

  late Directory scratch;
  late Directory source;
  late Directory target;
  late Release active;
  late Release historical;

  Release publish(String label, {bool obsolete = false}) {
    final raw = Directory('${scratch.path}/raw-$label')..createSync();
    for (final entry in {
      'main.dart.js': 'fixture $label',
      'index.html': '<script src="flutter_bootstrap.js" async></script>',
      'flutter_bootstrap.js': "const path = '__RELEASE_BASE__';",
      'manifest.json': '{"id":"./"}',
      'assets/current.txt': label,
      if (obsolete) 'assets/obsolete.txt': 'obsolete',
    }.entries) {
      final file = File('${raw.path}/${entry.key}');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value);
    }
    final release = prepareRelease(
      raw,
      File('web/service_worker.js').readAsStringSync(),
    );
    publishRelease(release, source);
    return release;
  }

  setUp(() {
    Directory('work').createSync();
    scratch = Directory('work').createTempSync('companion-package-');
    source = Directory('${scratch.path}/source');
    target = Directory('${scratch.path}/packaged-web');
    historical = publish('previous', obsolete: true);
    active = publish('active');
    File('${source.path}/config/local.json')
      ..parent.createSync()
      ..writeAsStringSync('{"apiKey":"private fixture"}');
    File('${source.path}/.env').writeAsStringSync('private fixture');
    File('${source.path}/stale.js').writeAsStringSync('old root alias');
  });
  tearDown(() => scratch.deleteSync(recursive: true));

  test(
    'Windows archive child rebuilds module paths and preserves packaging data',
    () async {
      final package = Directory('${scratch.path}/package with spaces')
        ..createSync();
      final archive = File('${scratch.path}/archive with spaces.zip');
      final parent = {
        'SYSTEMROOT': r'C:\Windows',
        'Path': r'C:\Windows\System32',
        'TEMP': 'preserved temporary directory',
        'PSModulePath': 'incompatible PowerShell 7 modules',
        'psmodulepath': 'another incompatible casing',
        'PsMoDuLePaTh': 'mixed incompatible casing',
        'WFFORM_PACKAGE_DIRECTORY': 'wrong inherited source',
        'WFFORM_PACKAGE_ARCHIVE': 'wrong inherited archive',
        'wfform_package_directory': 'wrong inherited source casing',
        'wfform_package_archive': 'wrong inherited archive casing',
      };
      final before = Map<String, String>.of(parent);
      var calls = 0;
      await createWindowsCompanionArchive(
        package,
        archive,
        parentEnvironment: parent,
        runner:
            (
              executable,
              arguments, {
              required environment,
              required includeParentEnvironment,
              required runInShell,
            }) async {
              calls++;
              expect(
                executable,
                r'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe',
              );
              expect(includeParentEnvironment, isFalse);
              expect(runInShell, isFalse);
              expect(
                environment.keys.any(
                  (key) => key.toUpperCase() == 'PSMODULEPATH',
                ),
                isFalse,
              );
              expect(environment['Path'], parent['Path']);
              expect(environment['TEMP'], parent['TEMP']);
              expect(environment['SYSTEMROOT'], parent['SYSTEMROOT']);
              expect(
                environment['WFFORM_PACKAGE_DIRECTORY'],
                package.absolute.path,
              );
              expect(
                environment['WFFORM_PACKAGE_ARCHIVE'],
                archive.absolute.path,
              );
              expect(
                environment.keys.where(
                  (key) => key.toUpperCase().startsWith('WFFORM_PACKAGE_'),
                ),
                unorderedEquals([
                  'WFFORM_PACKAGE_DIRECTORY',
                  'WFFORM_PACKAGE_ARCHIVE',
                ]),
              );
              expect(arguments.take(3), [
                '-NoProfile',
                '-NonInteractive',
                '-Command',
              ]);
              expect(
                arguments.last,
                contains(r'$env:WFFORM_PACKAGE_DIRECTORY'),
              );
              expect(arguments.last, contains(r'$env:WFFORM_PACKAGE_ARCHIVE'));
              expect(arguments.last, isNot(contains(package.path)));
              return ProcessResult(1, 0, '', '');
            },
      );
      expect(calls, 1);
      expect(parent, before);
    },
  );

  if (Platform.isWindows) {
    test(
      'Windows ZIP succeeds with incompatible inherited module path',
      () async {
        final package = Directory('${scratch.path}/native package')
          ..createSync();
        File(
          '${package.path}/payload.txt',
        ).writeAsStringSync('native ZIP fixture');
        final archive = File('${scratch.path}/native archive.zip');
        await createWindowsCompanionArchive(
          package,
          archive,
          parentEnvironment: {
            ...Platform.environment,
            'PSModulePath': '${scratch.absolute.path}\\missing-ps7-modules',
            'WFFORM_PACKAGE_DIRECTORY': 'wrong inherited source',
            'WFFORM_PACKAGE_ARCHIVE': 'wrong inherited archive',
          },
        );
        final bytes = archive.readAsBytesSync();
        expect(bytes.take(4), [0x50, 0x4b, 0x03, 0x04]);
        expect(latin1.decode(bytes), contains('payload.txt'));
      },
    );
  }

  test('packages only active verified flat assets and required root files', () {
    copyCompanionWebBuild(source, target);
    final files = target
        .listSync(recursive: true)
        .whereType<File>()
        .map(
          (file) =>
              file.path.substring(target.path.length + 1).replaceAll('\\', '/'),
        );
    expect(
      files,
      unorderedEquals([
        ...active.assets.keys,
        'release.json',
        'service_worker.js',
      ]),
    );
    expect(
      File('${target.path}/index.html').readAsStringSync(),
      contains(active.version),
    );
    expect(
      File('${target.path}/service_worker.js').readAsStringSync(),
      active.worker,
    );
    expect(Directory('${source.path}/__releases').existsSync(), isFalse);
    for (final entry in active.assets.entries) {
      expect(
        File('${target.path}/${entry.key}').readAsBytesSync(),
        entry.value,
      );
    }
  });

  test('refuses a verified web build from a different package version', () {
    final file = File('${source.path}/release.json');
    final manifest = jsonDecode(file.readAsStringSync()) as Map;
    manifest['packageVersion'] = '0.3.0';
    file.writeAsStringSync(jsonEncode(manifest));
    expect(() => copyCompanionWebBuild(source, target), throwsFormatException);
    expect(target.existsSync(), isFalse);
  });

  test('rejects config or traversal paths in active manifest', () {
    final manifestFile = File('${source.path}/release.json');
    final manifest = jsonDecode(manifestFile.readAsStringSync()) as Map;
    for (final path in ['config/local.json', '../outside', 'assets/.private']) {
      (manifest['assets'] as Map)[path] = {'bytes': 0, 'sha256': '0' * 64};
      manifestFile.writeAsStringSync(jsonEncode(manifest));
      expect(
        () => copyCompanionWebBuild(source, target),
        throwsFormatException,
      );
      (manifest['assets'] as Map).remove(path);
    }
    expect(target.existsSync(), isFalse);
  });

  test('rejects damaged active assets before writing a partial package', () {
    File('${source.path}/main.dart.js').writeAsStringSync('damaged');
    expect(() => copyCompanionWebBuild(source, target), throwsStateError);
    expect(target.existsSync(), isFalse);
  });

  test('rejects selected symlinks even when they point inside the build', () {
    final bootstrap = File('${source.path}/flutter_bootstrap.js')..deleteSync();
    Link(bootstrap.path).createSync('${source.absolute.path}/main.dart.js');
    expect(() => copyCompanionWebBuild(source, target), throwsStateError);
    expect(target.existsSync(), isFalse);
  });

  test('refuses a worker from another release', () {
    File(
      '${source.path}/service_worker.js',
    ).writeAsStringSync(historical.worker);
    expect(() => copyCompanionWebBuild(source, target), throwsStateError);
    expect(target.existsSync(), isFalse);
  });
}
