import 'dart:convert';
import 'dart:io';

import '../tool/content_hash.dart';

/// Build an allowlisted context. Never copy the repository or runtime config.
void main(List<String> arguments) {
  if (arguments.length > 2) {
    throw ArgumentError(
      'Usage: dart run deploy/package.dart [release] [context]',
    );
  }
  final source = Directory(
    arguments.isEmpty ? 'build/container-web' : arguments[0],
  );
  final target = Directory(
    arguments.length < 2 ? 'build/docker-context' : arguments[1],
  );
  packageRelease(source: source, target: target);
  stdout.writeln('Validated credential-free Docker context: ${target.path}');
}

void packageRelease({required Directory source, required Directory target}) {
  const marker = '.wfform-docker-context';
  if (target.absolute.path == source.absolute.path ||
      source.absolute.path.startsWith('${target.absolute.path}/') ||
      target.absolute.path == Directory.current.absolute.path ||
      (target.existsSync() && !File('${target.path}/$marker').existsSync())) {
    throw ArgumentError('Context must be a separate dedicated directory.');
  }
  target.parent.createSync(recursive: true);
  final stage = target.parent.createTempSync('docker-context-');
  try {
    final site = Directory('${stage.path}/site')..createSync();
    _copyGeneration(source, site);
    _copyChecked(
      File('${source.path}/service_worker.js'),
      File('${site.path}/service_worker.js'),
    );
    for (final path in ['Dockerfile', '.dockerignore']) {
      _copyChecked(File(path), File('${stage.path}/$path'));
    }
    for (final entity in Directory(
      'deploy/nginx',
    ).listSync(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.conf')) continue;
      _copyChecked(
        entity,
        File('${stage.path}/nginx/${entity.uri.pathSegments.last}'),
      );
    }
    File(
      '${stage.path}/$marker',
    ).writeAsStringSync('wfform generated context v1\n');
    // Validation completes before an existing usable context is replaced.
    if (target.existsSync()) target.deleteSync(recursive: true);
    stage.renameSync(target.path);
  } finally {
    if (stage.existsSync()) stage.deleteSync(recursive: true);
  }
}

void _copyGeneration(Directory source, Directory target) {
  final manifestFile = File('${source.path}/release.json');
  final manifestBytes = _readChecked(manifestFile);
  final value = jsonDecode(utf8.decode(manifestBytes));
  if (value is! Map ||
      value['format'] != 3 ||
      value['version'] is! String ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(value['version'] as String) ||
      value['assets'] is! Map) {
    throw const FormatException('Expected a versioned PWA release manifest.');
  }
  final assets = value['assets'] as Map;
  for (final required in [
    'index.html',
    'flutter_bootstrap.js',
    'main.dart.js',
    'manifest.json',
  ]) {
    if (!assets.containsKey(required)) {
      throw StateError('Incomplete PWA release.');
    }
  }
  for (final entry in assets.entries) {
    final path = entry.key;
    final metadata = entry.value;
    if (path is! String ||
        !RegExp(r'^[A-Za-z0-9_./-]+$').hasMatch(path) ||
        path.startsWith('/') ||
        path.split('/').any((part) => part.isEmpty || part.startsWith('.')) ||
        path.startsWith('config/') ||
        path.startsWith('__releases/') ||
        metadata is! Map ||
        metadata['bytes'] is! int ||
        metadata['sha256'] is! String) {
      throw const FormatException(
        'Unsafe release path or invalid asset metadata.',
      );
    }
    final bytes = _readChecked(File('${source.path}/$path'));
    if (bytes.length != metadata['bytes'] ||
        sha256(bytes) != metadata['sha256']) {
      throw StateError('Release integrity failed: $path');
    }
    final destination = File('${target.path}/$path')
      ..parent.createSync(recursive: true);
    destination.writeAsBytesSync(bytes, flush: true);
  }
  File(
    '${target.path}/release.json',
  ).writeAsBytesSync(manifestBytes, flush: true);
}

List<int> _readChecked(File source) {
  if (FileSystemEntity.typeSync(source.path, followLinks: false) !=
          FileSystemEntityType.file ||
      source.resolveSymbolicLinksSync() != source.absolute.path) {
    throw StateError(
      'Expected an ordinary file without symlink ancestors: ${source.path}',
    );
  }
  final bytes = source.readAsBytesSync();
  // Byte-to-code-unit scanning avoids decoding binary WASM/fonts. It is a final
  // guard, not a promise to recognize every possible custom secret format.
  final text = String.fromCharCodes(bytes);
  if (RegExp(r'sk-or-v1-[A-Za-z0-9_-]{12,}').hasMatch(text) ||
      RegExp('-----BEGIN [A-Z ]*PRIVATE KEY-----').hasMatch(text)) {
    throw StateError(
      'Refusing credential-bearing deployment material: ${source.path}',
    );
  }
  return bytes;
}

void _copyChecked(File source, File destination) {
  final bytes = _readChecked(source);
  destination.parent.createSync(recursive: true);
  destination.writeAsBytesSync(bytes, flush: true);
}
