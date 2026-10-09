import 'dart:convert';
import 'dart:io';

import 'content_hash.dart';
import 'release_version.dart';

/// Compile away from the running host, then publish complete verified flat packages.
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
          !RegExp(r'^/(?:[A-Za-z0-9_.-]+/)*$').hasMatch(baseHref) ||
          baseHref.split('/').any((part) => part == '.' || part == '..'))) {
    throw ArgumentError(
      '--base-href needs a full build and an absolute directory path ending in /.',
    );
  }
  final target = Directory(output).absolute;
  if (output.trim().isEmpty || target.path == Directory.current.path) {
    throw ArgumentError('Choose a dedicated release output directory.');
  }
  validatePublicationTarget(target);
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
              RegExp(
                r'(?:__releases/[a-f0-9]{64}/)?flutter_bootstrap\.js(?:\?build=[a-f0-9]{64})?',
              ),
              'flutter_bootstrap.js',
            ),
      );
    }
    if (path == 'flutter_bootstrap.js') {
      bytes = utf8.encode(
        utf8
            .decode(bytes)
            .replaceAllMapped(
              RegExp(
                r"""(const (?:releasePath|path) = ['"])(?:__releases/)?[a-f0-9]{64}/?(['"])""",
              ),
              (match) => '${match[1]}__RELEASE_BASE__${match[2]}',
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
        'format': 3,
        'packageVersion': readReleaseVersion(),
        'worker': sha256(utf8.encode(workerTemplate)),
        'assets': {
          for (final entry in raw.entries) entry.key: sha256(entry.value),
        },
      }),
    ),
  );

  raw['index.html'] = utf8.encode(
    utf8
        .decode(raw['index.html']!)
        .replaceAll(
          'src="flutter_bootstrap.js"',
          'src="flutter_bootstrap.js?build=$version"',
        ),
  );
  raw['flutter_bootstrap.js'] = utf8.encode(
    utf8
        .decode(raw['flutter_bootstrap.js']!)
        .replaceAll('__RELEASE_BASE__', version),
  );
  final entries = {
    for (final entry in raw.entries)
      entry.key: {'sha256': sha256(entry.value), 'bytes': entry.value.length},
  };
  final manifest = <String, Object?>{
    'format': 3,
    'packageVersion': readReleaseVersion(),
    'version': version,
    'assets': entries,
  };
  final worker = workerTemplate
      .replaceAll('__BUILD_ID__', version)
      .replaceAll('__PRECACHE_MANIFEST__', jsonEncode(entries));
  return Release(version, raw, manifest, worker);
}

/// Replacement is restricted to an empty or recognized generated directory.
/// Canonical checks run before compilation or any mutation, including legacy imports.
void validatePublicationTarget(Directory target) {
  final root = Directory.current.resolveSymbolicLinksSync();
  final normalized = Directory.fromUri(target.absolute.uri.normalizePath());
  final path = normalized.path.replaceFirst(RegExp(r'[/\\]+$'), '');
  if (path == root ||
      root.startsWith('$path${Platform.pathSeparator}') ||
      path == normalized.parent.path) {
    throw ArgumentError('Output cannot be the project root or an ancestor.');
  }
  var ancestor = normalized;
  while (true) {
    if (FileSystemEntity.typeSync(ancestor.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw StateError(
        'Output directories must not contain symlink ancestors.',
      );
    }
    if (ancestor.parent.path == ancestor.path) break;
    ancestor = ancestor.parent;
  }
  if (!normalized.existsSync() ||
      normalized.listSync(followLinks: false).isEmpty) {
    return;
  }
  final manifestFile = File('$path/release.json');
  if (!manifestFile.existsSync() ||
      manifestFile.lengthSync() > 1024 * 1024 ||
      FileSystemEntity.typeSync(manifestFile.path, followLinks: false) !=
          FileSystemEntityType.file) {
    throw StateError(
      'Output contains unowned files; choose an empty dedicated build directory.',
    );
  }
  final manifest = jsonDecode(manifestFile.readAsStringSync());
  if (manifest is! Map ||
      ![2, 3].contains(manifest['format']) ||
      manifest['assets'] is! Map ||
      manifest['version'] is! String ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(manifest['version'] as String)) {
    throw StateError('Output is not a recognized generated PWA build.');
  }
  final owned = <String>{
    'release.json',
    'service_worker.js',
    'flutter_service_worker.js',
    '.wfform-public-build',
    'config/local.json',
  };
  for (final key in (manifest['assets'] as Map).keys) {
    if (key is! String || !isShellAsset(key)) {
      throw StateError('Invalid prior build ownership.');
    }
    owned.add(key);
  }
  for (final required in [
    'index.html',
    'main.dart.js',
    'flutter_bootstrap.js',
    'manifest.json',
  ]) {
    if (!owned.contains(required) || !File('$path/$required').existsSync()) {
      throw StateError('Incomplete prior build ownership.');
    }
  }
  for (final entry in normalized.listSync(
    recursive: true,
    followLinks: false,
  )) {
    final relative = entry.path
        .substring(path.length + 1)
        .replaceAll('\\', '/');
    final old = RegExp(r'^__releases/[a-f0-9]{64}/(.+)$').firstMatch(relative);
    final legacy =
        old != null &&
        (old.group(1) == 'release.json' || isShellAsset(old.group(1)!));
    if (entry is File && (owned.contains(relative) || legacy)) continue;
    if (entry is Directory &&
        (owned.any((file) => file.startsWith('$relative/')) ||
            relative == '__releases' ||
            RegExp(
              r'^__releases/[a-f0-9]{64}(?:/(?:assets|icons|canvaskit)(?:/.*)?)?$',
            ).hasMatch(relative))) {
      continue;
    }
    throw StateError('Output contains an unowned file or link: $relative');
  }
}

/// Assemble a complete flat static site beside the target before replacing it.
/// Installed clients retain their verified generation in browser Cache Storage.
void publishRelease(Release release, Directory target) {
  validatePublicationTarget(target);
  target.parent.createSync(recursive: true);
  final stage = target.parent.createTempSync('pwa-stage-');
  final previous = Directory('${target.path}.previous-$pid');
  if (previous.existsSync()) {
    throw StateError('A prior publication needs recovery.');
  }
  try {
    for (final entry in release.assets.entries) {
      writeAtomic(File('${stage.path}/${entry.key}'), entry.value);
    }
    writeAtomic(
      File('${stage.path}/.wfform-public-build'),
      utf8.encode('wfform generated static build 3\n'),
    );
    writeAtomic(
      File('${stage.path}/release.json'),
      utf8.encode(jsonEncode(release.manifest)),
    );
    writeAtomic(
      File('${stage.path}/service_worker.js'),
      utf8.encode(release.worker),
    );
    if (target.existsSync()) target.renameSync(previous.path);
    try {
      stage.renameSync(target.path);
    } catch (_) {
      if (previous.existsSync()) previous.renameSync(target.path);
      rethrow;
    }
    if (previous.existsSync()) previous.deleteSync(recursive: true);
  } finally {
    if (stage.existsSync()) stage.deleteSync(recursive: true);
  }
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
        'favicon-16.png',
        'favicon-32.png',
        'favicon-dark-16.png',
        'favicon-dark-32.png',
        'favicon-dark-48.png',
        'about.html',
        'terms.html',
        'liability.html',
        'site.css',
        'robots.txt',
        'sitemap.xml',
      }.contains(path);
}
