import 'dart:convert';
import 'dart:io';

import 'content_hash.dart';

/// Compile away from the running host, then publish complete immutable releases.
/// No arbitrary compiler flags or dart-define credentials are accepted.
Future<void> main(List<String> args) async {
  var output = 'build/web';
  var skip = false;
  var public = false;
  String? baseHref;
  for (final arg in args) {
    if (arg == '--skip-build') {
      skip = true;
    } else if (arg == '--public') {
      public = true;
    } else if (arg.startsWith('--output=')) {
      output = arg.substring(9);
    } else if (arg.startsWith('--base-href=')) {
      baseHref = arg.substring(12);
    } else {
      stderr.writeln(
        'Usage: dart run tool/build.dart [--public] [--skip-build] [--output=build/web] [--base-href=/]',
      );
      exitCode = 64;
      return;
    }
  }
  if (baseHref != null &&
      (skip ||
          !RegExp(r'^/[A-Za-z0-9_/-]*$').hasMatch(baseHref) ||
          !baseHref.endsWith('/'))) {
    throw ArgumentError(
      '--base-href needs a full build and an absolute directory path ending in /.',
    );
  }
  final target = Directory(output).absolute;
  if (output.trim().isEmpty || target.path == Directory.current.path) {
    throw ArgumentError('Choose a dedicated release output directory.');
  }
  Directory('build').createSync();
  final temporary = Directory('build').createTempSync('pwa-input-');
  try {
    if (!skip) {
      final process = await Process.start('flutter', [
        'build',
        'web',
        '--release',
        '--no-web-resources-cdn',
        '--pwa-strategy=none',
        if (baseHref != null) '--base-href=$baseHref',
        '--output=${temporary.path}',
      ], mode: ProcessStartMode.inheritStdio);
      final result = await process.exitCode;
      if (result != 0) {
        exitCode = result;
        return;
      }
    }
    final release = prepareRelease(
      skip ? target : temporary,
      File('web/service_worker.js').readAsStringSync(),
    );
    publishRelease(release, target);
    // Network-only local configuration is outside the release/cache manifest.
    final local = File('config/local.json');
    final configTarget = File('${target.path}/config/local.json');
    syncLocalConfiguration(local, configTarget, public: public);
    stdout.writeln(
      'PWA release ${release.version}: ${release.assets.length} shell assets, ${release.bytes} bytes.',
    );
    stdout.writeln('Manifest: ${target.path}/release.json');
    stdout.writeln(
      'Serve: dart run tool/serve.dart --port=8765 --directory=$output',
    );
  } finally {
    temporary.deleteSync(recursive: true);
  }
}

/// Public artifacts must not inherit an ignored local development credential,
/// including when reusing an output directory that was previously served locally.
void syncLocalConfiguration(File local, File target, {required bool public}) {
  if (!public && local.existsSync()) {
    writeAtomic(target, local.readAsBytesSync());
  } else if (target.existsSync()) {
    target.deleteSync();
  }
  if (public &&
      target.parent.existsSync() &&
      target.parent.listSync().isEmpty) {
    target.parent.deleteSync();
  }
}

class Release {
  Release(this.version, this.assets, this.manifest, this.worker);
  final String version;
  final Map<String, List<int>> assets;
  final Map<String, Object?> manifest;
  final String worker;
  int get bytes => assets.values.fold(0, (sum, bytes) => sum + bytes.length);
}

Release prepareRelease(Directory source, String workerTemplate) {
  final raw = <String, List<int>>{};
  if (!File('${source.path}/main.dart.js').existsSync()) {
    throw StateError('Build Flutter web first: main.dart.js is missing.');
  }
  final paths =
      source
          .listSync(recursive: true)
          .whereType<File>()
          .map(
            (file) => file.path
                .substring(source.path.length + 1)
                .replaceAll('\\', '/'),
          )
          .where(isShellAsset)
          .toList()
        ..sort();
  for (final path in paths) {
    var bytes = File('${source.path}/$path').readAsBytesSync();
    if (path == 'index.html') {
      bytes = utf8.encode(
        utf8
            .decode(bytes)
            .replaceAll(
              RegExp(r'__releases/[a-f0-9]{64}/flutter_bootstrap\.js'),
              'flutter_bootstrap.js',
            ),
      );
    }
    if (path == 'flutter_bootstrap.js') {
      bytes = utf8.encode(
        utf8
            .decode(bytes)
            .replaceAll(
              RegExp(r'__releases/[a-f0-9]{64}/'),
              '__RELEASE_BASE__',
            ),
      );
      if (!utf8.decode(bytes).contains('__RELEASE_BASE__')) {
        throw StateError(
          'This build predates versioned bootstrap support. Run a full build first.',
        );
      }
    }
    if ((path.endsWith('.js') || path.endsWith('.json')) &&
        RegExp(r'sk-or-v1-[A-Za-z0-9_-]{12,}').hasMatch(utf8.decode(bytes))) {
      throw StateError('Refusing a credential-bearing release asset: $path');
    }
    raw[path] = bytes;
  }
  for (final required in [
    'index.html',
    'flutter_bootstrap.js',
    'manifest.json',
  ]) {
    if (!raw.containsKey(required)) {
      throw StateError('Missing release asset: $required');
    }
  }
  if (!utf8.decode(raw['index.html']!).contains('src="flutter_bootstrap.js"')) {
    throw StateError(
      'The host must load flutter_bootstrap.js through its expected script tag.',
    );
  }
  // Normalized pre-stamp hashes avoid a circular dependency on the release ID.
  final version = sha256(
    utf8.encode(
      jsonEncode({
        'format': 2,
        'worker': sha256(utf8.encode(workerTemplate)),
        'assets': {
          for (final entry in raw.entries) entry.key: sha256(entry.value),
        },
      }),
    ),
  );
  final prefix = '__releases/$version/';
  raw['index.html'] = utf8.encode(
    utf8
        .decode(raw['index.html']!)
        .replaceAll(
          'src="flutter_bootstrap.js"',
          'src="${prefix}flutter_bootstrap.js"',
        ),
  );
  raw['flutter_bootstrap.js'] = utf8.encode(
    utf8
        .decode(raw['flutter_bootstrap.js']!)
        .replaceAll('__RELEASE_BASE__', prefix),
  );
  final entries = {
    for (final entry in raw.entries)
      entry.key: {'sha256': sha256(entry.value), 'bytes': entry.value.length},
  };
  final manifest = <String, Object?>{
    'format': 2,
    'version': version,
    'assets': entries,
  };
  final worker = workerTemplate
      .replaceAll('__BUILD_ID__', version)
      .replaceAll('__PRECACHE_MANIFEST__', jsonEncode(entries));
  return Release(version, raw, manifest, worker);
}

/// Publish immutable assets before changing either launch HTML or worker.
/// Pointer files are atomically renamed: no half-written entrypoint is served.
void publishRelease(Release release, Directory target) {
  target.createSync(recursive: true);
  final releases = Directory('${target.path}/__releases')..createSync();
  final immutable = Directory('${releases.path}/${release.version}');
  if (immutable.existsSync()) {
    for (final entry in release.assets.entries) {
      final file = File('${immutable.path}/${entry.key}');
      if (!file.existsSync() ||
          sha256(file.readAsBytesSync()) != sha256(entry.value)) {
        throw StateError(
          'Existing immutable release is damaged: ${entry.key}. Restore or remove that incomplete directory before publishing.',
        );
      }
    }
  } else {
    final stage = releases.createTempSync('staging-');
    try {
      for (final entry in release.assets.entries) {
        final file = File('${stage.path}/${entry.key}');
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(entry.value, flush: true);
      }
      File(
        '${stage.path}/release.json',
      ).writeAsStringSync(jsonEncode(release.manifest), flush: true);
      stage.renameSync(immutable.path);
    } finally {
      if (stage.existsSync()) stage.deleteSync(recursive: true);
    }
  }
  // Root aliases preserve identity and legacy upgrade support. New Flutter pages
  // load immutable URLs after the new index is published.
  for (final entry in release.assets.entries.where(
    (entry) => entry.key != 'index.html',
  )) {
    writeAtomic(File('${target.path}/${entry.key}'), entry.value);
  }
  writeAtomic(
    File('${target.path}/release.json'),
    utf8.encode(jsonEncode(release.manifest)),
  );
  writeAtomic(File('${target.path}/index.html'), release.assets['index.html']!);
  writeAtomic(
    File('${target.path}/service_worker.js'),
    utf8.encode(release.worker),
  );
  final legacy = File('${target.path}/flutter_service_worker.js');
  if (legacy.existsSync()) legacy.deleteSync();
  // Keep disk releases addressable for open clients. Static-host owners choose
  // their historical-release retention window; the browser cache prunes safely.
}

void writeAtomic(File target, List<int> bytes) {
  target.parent.createSync(recursive: true);
  final temporary = File('${target.path}.publishing-$pid');
  try {
    temporary.writeAsBytesSync(bytes, flush: true);
    temporary.renameSync(target.path);
  } finally {
    if (temporary.existsSync()) temporary.deleteSync();
  }
}

bool isShellAsset(String path) {
  if (path.split('/').any((segment) => segment == '..' || segment.isEmpty) ||
      path.contains('\\') ||
      path.contains('?') ||
      path.contains('#')) {
    return false;
  }
  if (path.startsWith('config/') ||
      path.endsWith('.map') ||
      path == 'service_worker.js' ||
      path == 'flutter_service_worker.js' ||
      path == '.last_build_id') {
    return false;
  }
  return path.startsWith('assets/') ||
      path.startsWith('icons/') ||
      (path.startsWith('canvaskit/') &&
          (path.endsWith('canvaskit.js') || path.endsWith('canvaskit.wasm'))) ||
      const {
        'index.html',
        'main.dart.js',
        'flutter.js',
        'flutter_bootstrap.js',
        'manifest.json',
        'favicon.png',
        'about.html',
        'robots.txt',
        'sitemap.xml',
      }.contains(path);
}
