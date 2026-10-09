import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/build.dart';
import '../../tool/content_hash.dart';
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

  String addPreviouslyOwnedArtwork(Release prior) {
    final immutable = '__releases/${prior.version}/github-mark.svg';
    final ownership = File('${target.path}/.wfform-deployment.json');
    final previous =
        jsonDecode(ownership.readAsStringSync()) as Map<String, dynamic>;
    // Format-1 deployments before 0.1.2 owned both these exact paths.
    for (final path in ['github-mark.svg', immutable]) {
      final file = File('${target.path}/$path')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('<svg>previous artwork</svg>');
      (previous['files'] as Map<String, dynamic>)[path] = sha256(
        file.readAsBytesSync(),
      );
    }
    ownership.writeAsStringSync(jsonEncode(previous));
    return immutable;
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

  for (final alreadyRemoved in [false, true]) {
    test('preserves or restores owned CNAME, removed: $alreadyRemoved', () {
      final prior = release('prior');
      prepareWebsite(source, target);
      // This is the actual format-1 ownership entry written by older releases.
      final cname = File('${target.path}/CNAME')
        ..writeAsStringSync('wfform.com\n');
      final ownership = File('${target.path}/.wfform-deployment.json');
      final previous =
          jsonDecode(ownership.readAsStringSync()) as Map<String, dynamic>;
      (previous['files'] as Map<String, dynamic>)['CNAME'] = sha256(
        cname.readAsBytesSync(),
      );
      ownership.writeAsStringSync(jsonEncode(previous));
      if (alreadyRemoved) cname.deleteSync();
      release('next');
      final result = prepareWebsite(source, target);
      expect(cname.readAsStringSync(), 'wfform.com\n');
      expect(result.changedPaths.contains('CNAME'), alreadyRemoved);
      expect(
        (jsonDecode(ownership.readAsStringSync()) as Map)['files'],
        containsPair('CNAME', sha256(utf8.encode('wfform.com\n'))),
      );
      expect(
        File(
          '${target.path}/__releases/${prior.version}/index.html',
        ).existsSync(),
        isFalse,
      );
      expect(prepareWebsite(source, target).changedPaths, isEmpty);
    });
  }

  for (final content in ['wfform.com', 'wfform.com\n', 'wfform.com\r\n']) {
    test('adopts matching GitHub-created CNAME: ${jsonEncode(content)}', () {
      release('first');
      final cname = File('${target.path}/CNAME')..writeAsStringSync(content);
      prepareWebsite(source, target);
      expect(cname.readAsStringSync(), 'wfform.com\n');
      final ownership =
          jsonDecode(
                File(
                  '${target.path}/.wfform-deployment.json',
                ).readAsStringSync(),
              )
              as Map;
      expect(
        ownership['files'],
        containsPair('CNAME', sha256(utf8.encode('wfform.com\n'))),
      );
      expect(prepareWebsite(source, target).changedPaths, isEmpty);
    });
  }

  for (final content in [
    'another.example\n',
    'www.wfform.com\n',
    'wfform.com\nanother.example\n',
  ]) {
    test('conflicting unowned CNAME is preserved: ${jsonEncode(content)}', () {
      release('first');
      final cname = File('${target.path}/CNAME')..writeAsStringSync(content);
      expect(() => prepareWebsite(source, target), throwsStateError);
      expect(cname.readAsStringSync(), content);
      expect(target.listSync().length, 1);
    });
  }

  test('manually changed owned CNAME is preserved and reported', () {
    release('first');
    prepareWebsite(source, target);
    final ownership = File('${target.path}/.wfform-deployment.json');
    final previous =
        jsonDecode(ownership.readAsStringSync()) as Map<String, dynamic>;
    (previous['files'] as Map<String, dynamic>)['CNAME'] = sha256(
      utf8.encode('wfform.com\n'),
    );
    ownership.writeAsStringSync(jsonEncode(previous));
    final cname = File('${target.path}/CNAME')
      ..writeAsStringSync('human-edit.example\n');
    final originalIndex = File('${target.path}/index.html').readAsStringSync();
    release('next');
    expect(() => prepareWebsite(source, target), throwsStateError);
    expect(cname.readAsStringSync(), 'human-edit.example\n');
    expect(File('${target.path}/index.html').readAsStringSync(), originalIndex);
  });

  test('preserves unmanaged files and removes obsolete owned assets', () {
    Directory('${target.path}/.git').createSync();
    File('${target.path}/.git/config').writeAsStringSync('git metadata');
    Directory('${target.path}/docs').createSync();
    File('${target.path}/docs/manual.md').writeAsStringSync('manual');
    final first = release('first', obsolete: true);
    prepareWebsite(source, target);
    release('second');
    final changed = prepareWebsite(source, target).changedPaths;
    expect(changed, contains('assets/old.txt'));
    expect(File('${target.path}/assets/old.txt').existsSync(), isFalse);
    expect(
      File(
        '${target.path}/__releases/${first.version}/assets/old.txt',
      ).existsSync(),
      isFalse,
    );
    expect(File('${target.path}/index.html').existsSync(), isTrue);
    expect(
      File('${target.path}/.git/config').readAsStringSync(),
      'git metadata',
    );
    expect(File('${target.path}/docs/manual.md').readAsStringSync(), 'manual');
  });

  for (final alreadyRemoved in [false, true]) {
    test('migrates retired owned artwork, root removed: $alreadyRemoved', () {
      final prior = release('prior');
      prepareWebsite(source, target);
      final immutable = addPreviouslyOwnedArtwork(prior);
      final root = File('${target.path}/github-mark.svg');
      if (alreadyRemoved) root.deleteSync();
      final next = release('next');

      final result = prepareWebsite(source, target);
      expect(root.existsSync(), isFalse);
      expect(result.changedPaths.contains('github-mark.svg'), !alreadyRemoved);
      expect(File('${target.path}/$immutable').existsSync(), isFalse);
      expect(
        File(
          '${target.path}/__releases/${next.version}/github-mark.svg',
        ).existsSync(),
        isFalse,
      );
      final ownership =
          jsonDecode(
                File(
                  '${target.path}/.wfform-deployment.json',
                ).readAsStringSync(),
              )
              as Map;
      expect(ownership['files'] as Map, isNot(contains('github-mark.svg')));
      expect(ownership['files'] as Map, isNot(contains(immutable)));
      expect(Directory('${target.path}/__releases').existsSync(), isFalse);
      expect(prepareWebsite(source, target).changedPaths, isEmpty);
    });
  }

  for (final editImmutable in [false, true]) {
    test('preserves edited retired artwork, immutable: $editImmutable', () {
      final prior = release('prior');
      prepareWebsite(source, target);
      final immutable = addPreviouslyOwnedArtwork(prior);
      final path = editImmutable ? immutable : 'github-mark.svg';
      final edited = File('${target.path}/$path')
        ..writeAsStringSync('human edit');
      final index = File('${target.path}/index.html').readAsStringSync();
      final ownership = File(
        '${target.path}/.wfform-deployment.json',
      ).readAsStringSync();
      release('next');

      expect(() => prepareWebsite(source, target), throwsStateError);
      expect(edited.readAsStringSync(), 'human edit');
      expect(File('${target.path}/index.html').readAsStringSync(), index);
      expect(
        File('${target.path}/.wfform-deployment.json').readAsStringSync(),
        ownership,
      );
    });
  }

  test('retired compatibility does not allow new release artwork', () {
    release('next');
    final manifest = File('${source.path}/release.json');
    final data =
        jsonDecode(manifest.readAsStringSync()) as Map<String, dynamic>;
    (data['assets'] as Map<String, dynamic>)['github-mark.svg'] = {
      'sha256': sha256(utf8.encode('<svg/>')),
      'bytes': 6,
    };
    manifest.writeAsStringSync(jsonEncode(data));
    expect(
      () => prepareWebsite(source, target),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Unsupported release asset metadata: github-mark.svg',
        ),
      ),
    );
    expect(target.listSync(), isEmpty);
  });

  test('retired compatibility never deletes an unowned root artwork file', () {
    release('next');
    final unowned = File('${target.path}/github-mark.svg')
      ..writeAsStringSync('unowned content');
    final result = prepareWebsite(source, target);
    expect(unowned.readAsStringSync(), 'unowned content');
    expect(result.changedPaths, isNot(contains('github-mark.svg')));
  });

  test('retired compatibility rejects other unrecognized ownership paths', () {
    release('next');
    final ownership = File('${target.path}/.wfform-deployment.json');
    for (final path in [
      'other-mark.svg',
      'nested/github-mark.svg',
      '__releases/not-a-digest/github-mark.svg',
      '__releases/${'a' * 64}/nested/github-mark.svg',
    ]) {
      ownership.writeAsStringSync(
        jsonEncode({
          'format': 1,
          'files': {path: 'b' * 64},
        }),
      );
      expect(
        () => prepareWebsite(source, target),
        throwsFormatException,
        reason: path,
      );
      expect(target.listSync(), hasLength(1));
    }
  });

  test('missing retired assets do not block the flat migration', () {
    final prior = release('prior');
    prepareWebsite(source, target);
    final immutable = addPreviouslyOwnedArtwork(prior);
    File('${target.path}/$immutable').deleteSync();
    release('next');
    prepareWebsite(source, target);
    expect(File('${target.path}/github-mark.svg').existsSync(), isFalse);
    expect(Directory('${target.path}/__releases').existsSync(), isFalse);
  });

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

  test('unowned legacy symlinks fail before any publication mutation', () {
    release('next');
    final external = Directory('${scratch.path}/external')..createSync();
    final keep = Directory('${external.path}/keep')..createSync();
    Link('${target.path}/__releases').createSync(external.absolute.path);
    expect(() => prepareWebsite(source, target), throwsStateError);
    expect(keep.existsSync(), isTrue);
    expect(File('${target.path}/index.html').existsSync(), isFalse);
  });

  test('flat migration preserves unmanaged empty legacy directories', () {
    final prior = release('prior');
    prepareWebsite(source, target);
    addPreviouslyOwnedArtwork(prior);
    final keep = Directory('${target.path}/__releases/unmanaged')..createSync();
    release('next');
    prepareWebsite(source, target);
    expect(keep.existsSync(), isTrue);
  });

  test('ignores source files outside the release allowlist', () {
    release('first');
    File('${source.path}/README.md').writeAsStringSync('unowned input');
    prepareWebsite(source, target);
    expect(File('${target.path}/README.md').existsSync(), isFalse);
  });
}
