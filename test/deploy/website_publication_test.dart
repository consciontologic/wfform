import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/build.dart';
import '../../tool/prepare_website.dart';

void main() {
  late Directory scratch;
  late Directory source;
  late Directory target;

  Release release(String value, {bool obsolete = false}) {
    final raw = Directory('${scratch.path}/raw-$value')..createSync();
    for (final entry in {
      'main.dart.js': 'fixture $value',
      'index.html': '<script src="flutter_bootstrap.js" async></script>',
      'flutter_bootstrap.js': "const path = '__RELEASE_BASE__';",
      'manifest.json': '{"id":"./"}',
      if (obsolete) 'assets/old.txt': 'an old asset',
    }.entries) {
      final file = File('${raw.path}/${entry.key}');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value);
    }
    final result = prepareRelease(raw, '// __BUILD_ID__ __PRECACHE_MANIFEST__');
    publishRelease(result, source);
    return result;
  }

  setUp(() {
    Directory('work').createSync();
    scratch = Directory('work').createTempSync('website-publication-');
    source = Directory('${scratch.path}/source');
    target = Directory('${scratch.path}/target')..createSync();
  });
  tearDown(() => scratch.deleteSync(recursive: true));

  test(
    'first publish is complete and repeated artifacts produce no changes',
    () {
      final built = release('first');
      final first = prepareWebsite(source, target);
      expect(first.version, built.version);
      expect(first.changedPaths, contains('index.html'));
      expect(File('${target.path}/CNAME').readAsStringSync(), 'wfform.com\n');
      expect(File('${target.path}/.nojekyll').existsSync(), isTrue);
      expect(prepareWebsite(source, target).changedPaths, isEmpty);
    },
  );

  test(
    'preserves unmanaged files and old immutable assets, removes owned aliases',
    () {
      Directory('${target.path}/.git').createSync();
      File('${target.path}/.git/config').writeAsStringSync('git metadata');
      Directory('${target.path}/docs').createSync();
      File('${target.path}/docs/manual.md').writeAsStringSync('manual');
      final first = release('first', obsolete: true);
      prepareWebsite(source, target);
      final second = release('second');
      final changed = prepareWebsite(source, target).changedPaths;
      expect(changed, contains('assets/old.txt'));
      expect(File('${target.path}/assets/old.txt').existsSync(), isFalse);
      expect(
        File(
          '${target.path}/__releases/${first.version}/assets/old.txt',
        ).existsSync(),
        isTrue,
      );
      expect(
        File(
          '${target.path}/__releases/${second.version}/index.html',
        ).existsSync(),
        isTrue,
      );
      expect(
        File('${target.path}/.git/config').readAsStringSync(),
        'git metadata',
      );
      expect(
        File('${target.path}/docs/manual.md').readAsStringSync(),
        'manual',
      );
    },
  );

  test('rejects local configuration before modifying destination', () {
    release('first');
    Directory('${source.path}/config').createSync();
    File('${source.path}/config/local.json').writeAsStringSync('{}');
    expect(() => prepareWebsite(source, target), throwsStateError);
    expect(target.listSync(), isEmpty);
  });

  test('public build configuration cleanup can be published', () {
    release('first');
    Directory('${source.path}/config').createSync();
    File('${source.path}/config/local.json').writeAsStringSync('{}');
    syncLocalConfiguration(
      File('${scratch.path}/absent-local.json'),
      File('${source.path}/config/local.json'),
      public: true,
    );
    expect(prepareWebsite(source, target).changedPaths, isNotEmpty);
    expect(Directory('${target.path}/config').existsSync(), isFalse);
  });

  test('rejects equal, nested and parent destination roots', () {
    release('first');
    for (final destination in [
      source,
      Directory('${source.path}/nested'),
      scratch,
      Directory('/'),
    ]) {
      expect(() => prepareWebsite(source, destination), throwsArgumentError);
    }
  });

  test('a file blocking an asset directory fails before any copy', () {
    release('first', obsolete: true);
    File('${target.path}/assets').writeAsStringSync('owned by someone else');
    expect(() => prepareWebsite(source, target), throwsStateError);
    expect(target.listSync().length, 1);
    expect(
      File('${target.path}/assets').readAsStringSync(),
      'owned by someone else',
    );
  });

  test('rejects damaged assets before modifying destination', () {
    release('first');
    File('${source.path}/main.dart.js').writeAsStringSync('damaged');
    expect(() => prepareWebsite(source, target), throwsStateError);
    expect(target.listSync(), isEmpty);
  });

  test('rejects secret-bearing shell files without exposing credentials', () {
    release('first');
    final secret = 'sk-or-v1-${List.filled(64, 'b').join()}';
    File('${source.path}/service_worker.js').writeAsStringSync(secret);
    expect(
      () => prepareWebsite(source, target),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          isNot(contains(secret)),
        ),
      ),
    );
    expect(target.listSync(), isEmpty);
  });

  test(
    'refuses conflicting unowned files and external edits of owned files',
    () {
      release('first');
      File('${target.path}/index.html').writeAsStringSync('existing website');
      expect(() => prepareWebsite(source, target), throwsStateError);
      File('${target.path}/index.html').deleteSync();
      prepareWebsite(source, target);
      File('${target.path}/index.html').writeAsStringSync('human edit');
      release('second');
      expect(() => prepareWebsite(source, target), throwsStateError);
      expect(
        File('${target.path}/index.html').readAsStringSync(),
        'human edit',
      );
    },
  );

  test('rejects unsafe ownership paths and symlinks', () {
    release('first');
    File('${target.path}/.wfform-deployment.json').writeAsStringSync(
      jsonEncode({
        'format': 1,
        'files': {'../outside.txt': '0' * 64},
      }),
    );
    expect(() => prepareWebsite(source, target), throwsFormatException);
    File('${target.path}/.wfform-deployment.json').deleteSync();
    Link(
      '${target.path}/index.html',
    ).createSync('${scratch.absolute.path}/outside');
    expect(() => prepareWebsite(source, target), throwsStateError);
  });

  test('ignores source files outside the release allowlist', () {
    release('first');
    File('${source.path}/README.md').writeAsStringSync('unowned input');
    prepareWebsite(source, target);
    expect(File('${target.path}/README.md').existsSync(), isFalse);
  });
}
