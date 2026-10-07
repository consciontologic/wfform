import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../../tool/build.dart' as build;
import '../../tool/content_hash.dart';
import '../../tool/measure.dart';
import '../../tool/serve.dart';

void main() {
  late Directory scratch;
  late Directory source;
  final template = File('web/service_worker.js').readAsStringSync();
  setUp(() {
    Directory('work').createSync();
    scratch = Directory('work').createTempSync('pwa-test-');
    source = Directory('${scratch.path}/source')..createSync();
    final files = {
      'index.html':
          '<base href="/"><script src="flutter_bootstrap.js" async></script>',
      'flutter_bootstrap.js': "const releasePath = '__RELEASE_BASE__';",
      'main.dart.js': 'console.log("fixture");',
      'manifest.json': '{"name":"wfform","id":"./"}',
      'assets/example.txt': 'offline fixture',
    };
    for (final entry in files.entries) {
      final file = File('${source.path}/${entry.key}');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value);
    }
  });
  tearDown(() => scratch.deleteSync(recursive: true));

  test(
    'CLI forwards a dotted Pages base and rejects traversal before compiling',
    () async {
      final bin = Directory('${scratch.path}/bin')..createSync();
      final arguments = File('${scratch.path}/flutter-arguments').absolute;
      final flutter = File('${bin.path}/flutter')
        ..writeAsStringSync(r'''#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "$TEST_BUILD_ARGUMENTS"
for arg in "$@"; do
  case "$arg" in
    --output=*) output="${arg#--output=}" ;;
    --base-href=*) base="${arg#--base-href=}" ;;
  esac
done
mkdir -p "$output"
printf '<base href="%s"><script src="flutter_bootstrap.js" async></script>' "$base" > "$output/index.html"
printf 'const releasePath = "__RELEASE_BASE__";' > "$output/flutter_bootstrap.js"
printf 'fixture' > "$output/main.dart.js"
printf '{"name":"wfform","id":"./"}' > "$output/manifest.json"
''');
      expect((await Process.run('chmod', ['700', flutter.path])).exitCode, 0);
      final target = Directory('${scratch.path}/cli-public');
      Future<ProcessResult> compile(String base) => Process.run(
        'dart',
        [
          'tool/build.dart',
          '--public',
          '--output=${target.path}',
          '--base-href=$base',
        ],
        environment: {
          'PATH': '${bin.absolute.path}:${Platform.environment['PATH']}',
          'TEST_BUILD_ARGUMENTS': arguments.path,
        },
      );
      final result = await compile('/wfform.com/');
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(
        arguments.readAsStringSync(),
        contains('--base-href=/wfform.com/'),
      );
      expect(
        File('${target.path}/index.html').readAsStringSync(),
        contains('<base href="/wfform.com/">'),
      );
      expect(File('${target.path}/config/local.json').existsSync(), isFalse);
      arguments.deleteSync();
      for (final invalid in ['/../', '/./', '//', '/wfform.com']) {
        expect((await compile(invalid)).exitCode, isNot(0), reason: invalid);
        expect(arguments.existsSync(), isFalse, reason: invalid);
      }
    },
  );

  test('public SEO documents are hashed and published with the shell', () {
    for (final path in [
      'about.html',
      'terms.html',
      'liability.html',
      'site.css',
      'robots.txt',
      'sitemap.xml',
    ]) {
      File('${source.path}/$path').writeAsStringSync('public fixture $path');
    }
    final release = build.prepareRelease(source, template);
    final target = Directory('${scratch.path}/public');
    build.publishRelease(release, target);
    for (final path in [
      'about.html',
      'terms.html',
      'liability.html',
      'site.css',
      'robots.txt',
      'sitemap.xml',
    ]) {
      expect(release.assets, contains(path));
      expect(
        File('${target.path}/$path').readAsStringSync(),
        'public fixture $path',
      );
    }
    expect(mimeType('sitemap.xml'), 'application/xml; charset=utf-8');
  });

  test('retired source artwork is excluded even from stale build output', () {
    File('${source.path}/github-mark.svg').writeAsStringSync('<svg/>');
    final release = build.prepareRelease(source, template);
    final target = Directory('${scratch.path}/public');
    build.publishRelease(release, target);
    expect(release.assets, isNot(contains('github-mark.svg')));
    expect(
      release.manifest['assets'] as Map,
      isNot(contains('github-mark.svg')),
    );
    expect(File('${target.path}/github-mark.svg').existsSync(), isFalse);
  });

  test('public builds never read or retain development configuration', () {
    final local = File('${scratch.path}/local.json')
      ..writeAsStringSync('{"apiKey":"local-test-credential"}');
    final target = File('${scratch.path}/public/config/local.json')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('old development config');
    build.syncLocalConfiguration(local, target, public: true);
    expect(target.existsSync(), isFalse);
    expect(target.parent.existsSync(), isFalse);
    expect(local.existsSync(), isTrue);
    build.syncLocalConfiguration(local, target, public: false);
    expect(target.readAsStringSync(), local.readAsStringSync());
    local.deleteSync();
    build.syncLocalConfiguration(local, target, public: false);
    expect(target.existsSync(), isFalse);
  });

  test('SHA-256 matches published empty, short and multi-block vectors', () {
    expect(
      sha256([]),
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    );
    expect(
      sha256(utf8.encode('abc')),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    expect(
      sha256(
        utf8.encode('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'),
      ),
      '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
    );
    expect(
      sha256(List.filled(1000000, 97)),
      'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0',
    );
  });
  test(
    'identical shell and configuration-only changes retain release identity',
    () {
      final first = build.prepareRelease(source, template);
      final config = File('${source.path}/config/local.json')
        ..parent.createSync();
      config.writeAsStringSync('{"apiKey":"unbundled local fixture"}');
      File(
        '${source.path}/main.dart.js.map',
      ).writeAsStringSync('changed source map');
      File(
        '${source.path}/release.json',
      ).writeAsStringSync('old generated metadata');
      final second = build.prepareRelease(source, template);
      expect(second.version, first.version);
      expect(second.worker, first.worker);
      expect(second.assets.keys, isNot(contains('config/local.json')));
      expect(second.assets.keys, isNot(contains('release.json')));
    },
  );
  test('asset or worker policy changes produce a different release', () {
    final first = build.prepareRelease(source, template);
    File(
      '${source.path}/assets/example.txt',
    ).writeAsStringSync('updated fixture');
    final changed = build.prepareRelease(source, template);
    expect(changed.version, isNot(first.version));
    expect(
      build.prepareRelease(source, '$template\n// policy revision').version,
      isNot(changed.version),
    );
  });
  test('manifest hashes describe stamped bytes and immutable startup URLs', () {
    final release = build.prepareRelease(source, template);
    final entries = release.manifest['assets'] as Map;
    for (final entry in release.assets.entries) {
      expect((entries[entry.key] as Map)['sha256'], sha256(entry.value));
      expect((entries[entry.key] as Map)['bytes'], entry.value.length);
    }
    expect(
      utf8.decode(release.assets['index.html']!),
      contains('__releases/${release.version}/flutter_bootstrap.js'),
    );
    expect(
      utf8.decode(release.assets['flutter_bootstrap.js']!),
      contains('__releases/${release.version}/'),
    );
    expect(release.worker, isNot(contains('__BUILD_ID__')));
    expect(release.worker, isNot(contains('__PRECACHE_MANIFEST__')));
  });
  test('real host keeps its bootstrap guard identity after URL stamping', () {
    File('${source.path}/index.html').writeAsStringSync(
      File(
        'web/index.html',
      ).readAsStringSync().replaceAll(r'$FLUTTER_BASE_HREF', '/'),
    );
    final release = build.prepareRelease(source, template);
    final index = utf8.decode(release.assets['index.html']!);
    expect(index, contains('<script id="bootstrap-load-guard">'));
    expect(
      index,
      contains(
        '<script id="flutter-bootstrap" src="__releases/${release.version}/flutter_bootstrap.js" async>',
      ),
    );
    expect(index, isNot(contains('src="flutter_bootstrap.js"')));
  });
  test('publishing creates complete immutable release before pointer files', () {
    final release = build.prepareRelease(source, template);
    final target = Directory('${scratch.path}/published');
    build.publishRelease(release, target);
    for (final entry in release.assets.entries) {
      expect(
        File(
          '${target.path}/__releases/${release.version}/${entry.key}',
        ).readAsBytesSync(),
        entry.value,
      );
    }
    expect(
      jsonDecode(File('${target.path}/release.json').readAsStringSync()),
      release.manifest,
    );
    expect(
      File('${target.path}/service_worker.js').readAsStringSync(),
      release.worker,
    );
    expect(
      target
          .listSync(recursive: true)
          .where(
            (entry) =>
                entry.path.contains('publishing-') ||
                entry.path.contains('staging-'),
          ),
      isEmpty,
    );
    // Reassembling stamped output is stable; changed policy keeps old URLs alive.
    expect(build.prepareRelease(target, template).version, release.version);
    final update = build.prepareRelease(source, '$template\n// next policy');
    build.publishRelease(update, target);
    expect(
      File(
        '${target.path}/__releases/${release.version}/main.dart.js',
      ).existsSync(),
      isTrue,
    );
    expect(
      File(
        '${target.path}/__releases/${update.version}/main.dart.js',
      ).existsSync(),
      isTrue,
    );
  });
  test(
    'missing assets, old bootstrap and credential-like scripts fail closed',
    () {
      final original = File(
        '${source.path}/flutter_bootstrap.js',
      ).readAsStringSync();
      File(
        '${source.path}/flutter_bootstrap.js',
      ).writeAsStringSync('old loader');
      expect(() => build.prepareRelease(source, template), throwsStateError);
      File('${source.path}/flutter_bootstrap.js').writeAsStringSync(original);
      final marker = 'sk-or-v1-${List.filled(3, 'fixture').join()}';
      File('${source.path}/main.dart.js').writeAsStringSync(marker);
      expect(() => build.prepareRelease(source, template), throwsStateError);
      File('${source.path}/main.dart.js').deleteSync();
      expect(() => build.prepareRelease(source, template), throwsStateError);
    },
  );
  test('subpath hosts preserve their base while release paths stay relative', () {
    File('${source.path}/index.html').writeAsStringSync(
      '<base href="/studio/"><script src="flutter_bootstrap.js" async></script>',
    );
    final release = build.prepareRelease(source, template);
    final index = utf8.decode(release.assets['index.html']!);
    expect(index, contains('<base href="/studio/">'));
    expect(
      index,
      contains('src="__releases/${release.version}/flutter_bootstrap.js"'),
    );
    final scope = Uri.parse('https://example.test/studio/');
    expect(
      scope.resolve('__releases/${release.version}/main.dart.js').path,
      '/studio/__releases/${release.version}/main.dart.js',
    );
  });
  test(
    'damaged immutable releases refuse publication before pointer changes',
    () {
      final release = build.prepareRelease(source, template);
      final target = Directory('${scratch.path}/published');
      build.publishRelease(release, target);
      final worker = File(
        '${target.path}/service_worker.js',
      ).readAsStringSync();
      File(
        '${target.path}/__releases/${release.version}/main.dart.js',
      ).writeAsStringSync('damaged');
      expect(() => build.publishRelease(release, target), throwsStateError);
      expect(
        File('${target.path}/service_worker.js').readAsStringSync(),
        worker,
      );
    },
  );
  test(
    'unknown directories, secrets and malformed paths are never shell assets',
    () {
      for (final path in [
        'config/local.json',
        '__releases/previous/main.dart.js',
        'release.json',
        'service_worker.js',
        'assets/../config/local.json',
        'assets/item?token=value',
        'assets/item#fragment',
        '/main.dart.js',
      ]) {
        expect(build.isShellAsset(path), isFalse, reason: path);
      }
    },
  );
  test('immutable HTTP caching applies only to versioned release URLs', () {
    expect(
      cacheControlFor('__releases/${'a' * 64}/main.dart.js'),
      'public, max-age=31536000, immutable',
    );
    for (final path in [
      'index.html',
      'service_worker.js',
      'config/local.json',
      '__releases/not-a-hash/main.dart.js',
    ]) {
      expect(cacheControlFor(path), 'no-store');
    }
  });
  test(
    'static host keeps response length and body consistent during pointer replacement',
    () async {
      final file = File('${scratch.path}/pointer.txt')
        ..writeAsStringSync('previous complete value');
      final descriptor = await file.open();
      try {
        final length = await descriptor.length();
        build.writeAtomic(file, utf8.encode('next value'));
        final bytes = await readOpenedFile(
          descriptor,
          length,
        ).expand((chunk) => chunk).toList();
        expect(bytes.length, length);
        expect(utf8.decode(bytes), 'previous complete value');
        expect(file.readAsStringSync(), 'next value');
      } finally {
        await descriptor.close();
      }
    },
  );
  test(
    'artifact comparison reports reuse by path and bytes without network claims',
    () {
      final before = {
        'release': 'old',
        'shellBytes': 12,
        'assets': {
          'unchanged': {'sha256': 'one', 'bytes': 5},
          'changed': {'sha256': 'two', 'bytes': 4},
          'removed': {'sha256': 'three', 'bytes': 3},
        },
      };
      final after = {
        'release': 'new',
        'shellBytes': 14,
        'assets': {
          'unchanged': {'sha256': 'one', 'bytes': 5},
          'changed': {'sha256': 'new', 'bytes': 6},
          'added': {'sha256': 'four', 'bytes': 3},
        },
      };
      final comparison = compareArtifacts(before, after);
      expect(comparison['unchangedAssets'], 1);
      expect(comparison['reusableBytes'], 5);
      expect(comparison['changedOrAddedBytes'], 9);
      expect(comparison['removedAssets'], 1);
      expect(comparison['shellByteDelta'], 2);
    },
  );
  test(
    'worker publishes completion only after verified install and removes failed cache',
    () {
      final installed = template.indexOf('await Promise.all(workers);');
      final marker = template.indexOf('await cache.put(markerUrl(VERSION)');
      expect(installed, greaterThan(0));
      expect(marker, greaterThan(installed));
      expect(template, contains("crypto.subtle.digest('SHA-256', bytes)"));
      expect(template, contains('bytes.byteLength !== expected.bytes'));
      expect(template, contains("headers.delete('Content-Encoding')"));
      expect(template, contains("headers.delete('Content-Length')"));
      expect(template, contains('await Promise.allSettled(workers)'));
      expect(template, contains('await caches.delete(CACHE)'));
      expect(template, contains('await verified(response, expected)'));
      expect(RegExp("cache: 'reload'").allMatches(template), hasLength(1));
    },
  );
  test(
    'worker fetch has no runtime writes and preserves release and API boundaries',
    () {
      final fetch = template.substring(
        template.indexOf("self.addEventListener('fetch'"),
      );
      expect(fetch, isNot(contains('.put(')));
      expect(fetch, contains("request.headers.has('authorization')"));
      expect(fetch, contains("url.pathname.includes('/config/')"));
      expect(fetch, contains('url.search'));
      expect(fetch, contains('releaseUrl(version, path)'));
      expect(
        fetch,
        contains('if (!(await caches.has(name))) return fetch(request);'),
      );
      expect(template, contains('if (unknown) return;'));
      expect(template, contains('keep.add(PREFIX + version)'));
      expect(template, contains("event.data?.type === 'APPLY_UPDATE'"));
      expect(template, isNot(contains('setInterval(')));
    },
  );
}
