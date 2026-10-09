import 'dart:convert';
import 'dart:io';

import 'build.dart' show isShellAsset, writeAtomic;
import 'content_hash.dart';

const _ownershipFile = '.wfform-deployment.json';
final _digest = RegExp(r'^[a-f0-9]{64}$');

class WebsitePublication {
  WebsitePublication(this.version, this.changedPaths);
  final String version;
  final List<String> changedPaths;
}

/// Validates and copies one release into an already checked-out website repo.
/// Git operations belong to the CI script. All validation precedes mutation.
WebsitePublication prepareWebsite(Directory source, Directory target) {
  final sourcePath = _canonicalRoot(source);
  final targetPath = _canonicalRoot(target);
  bool contains(String parent, String child) =>
      child.startsWith(parent.endsWith('/') ? parent : '$parent/');
  if (sourcePath == targetPath ||
      contains(targetPath, sourcePath) ||
      contains(sourcePath, targetPath)) {
    throw ArgumentError(
      'Source and destination must be separate, non-nested directories.',
    );
  }
  if (FileSystemEntity.typeSync(
        '${target.path}/__releases',
        followLinks: false,
      ) ==
      FileSystemEntityType.link) {
    throw StateError('A legacy release directory must not be a symlink.');
  }
  final manifest = _object(_read(source, 'release.json'), 'release.json');
  final version = manifest['version'];
  final assets = manifest['assets'];
  if (manifest['format'] != 3 ||
      version is! String ||
      !_digest.hasMatch(version) ||
      assets is! Map<String, dynamic>) {
    throw const FormatException('Unsupported release.json structure.');
  }
  for (final directory in [source, target]) {
    if (FileSystemEntity.typeSync(
          '${directory.path}/config',
          followLinks: false,
        ) !=
        FileSystemEntityType.notFound) {
      throw StateError(
        'Public deployment must not contain config/. Build with --public in a clean output directory.',
      );
    }
  }
  final files = <String, List<int>>{};
  for (final entry in assets.entries) {
    final path = entry.key;
    final metadata = entry.value;
    if (!_safe(path) ||
        !isShellAsset(path) ||
        metadata is! Map ||
        metadata['sha256'] is! String ||
        !_digest.hasMatch(metadata['sha256'] as String) ||
        metadata['bytes'] is! int) {
      throw FormatException('Unsupported release asset metadata: $path');
    }
    for (final location in [path]) {
      final bytes = _read(source, location);
      if (bytes.length != metadata['bytes'] ||
          sha256(bytes) != metadata['sha256']) {
        throw StateError('Release asset integrity check failed: $location');
      }
      files[location] = bytes;
    }
  }
  for (final required in [
    'index.html',
    'main.dart.js',
    'flutter_bootstrap.js',
    'manifest.json',
  ]) {
    if (!files.containsKey(required)) {
      throw StateError('Incomplete public release: missing $required');
    }
  }
  files['release.json'] = _read(source, 'release.json');
  files['service_worker.js'] = _read(source, 'service_worker.js');
  files['.nojekyll'] = const [];
  files['CNAME'] = utf8.encode('wfform.com\n');
  final credential = RegExp(
    r'sk-or-v1-[A-Za-z0-9_-]{12,}|github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9]{20,}',
  );
  for (final entry in files.entries) {
    if (credential.hasMatch(latin1.decode(entry.value))) {
      throw StateError(
        'Refusing credential-bearing public asset: ${entry.key}',
      );
    }
  }

  final previous = <String, String>{};
  _checkPath(target, _ownershipFile);
  final ownership = File('${target.path}/$_ownershipFile');
  if (ownership.existsSync()) {
    final data = _object(ownership.readAsBytesSync(), _ownershipFile);
    final oldFiles = data['files'];
    if (data['format'] != 1 || oldFiles is! Map<String, dynamic>) {
      throw const FormatException('Unsupported website ownership manifest.');
    }
    for (final entry in oldFiles.entries) {
      if (!_previouslyManaged(entry.key) ||
          entry.value is! String ||
          !_digest.hasMatch(entry.value as String)) {
        throw const FormatException('Unsafe website ownership entry.');
      }
      previous[entry.key] = entry.value as String;
    }
  }
  // Setting the domain through GitHub can create CNAME before this publisher
  // owns it. Adopt only the exact intended domain, normalizing its line ending.
  // Other unowned domains and external edits still fail before any mutation.
  _checkPath(target, 'CNAME');
  final cname = File('${target.path}/CNAME');
  if (cname.existsSync() && !previous.containsKey('CNAME')) {
    final bytes = cname.readAsBytesSync();
    if (const {
      'wfform.com',
      'wfform.com\n',
      'wfform.com\r\n',
    }.contains(latin1.decode(bytes))) {
      previous['CNAME'] = sha256(bytes);
    }
  }
  final next = <String, String>{
    for (final entry in files.entries) entry.key: sha256(entry.value),
  };
  final removed = previous.keys.where((path) => !next.containsKey(path));
  final changed = <String>[];
  for (final path in {...previous.keys, ...files.keys}) {
    _checkPath(target, path);
    final file = File('${target.path}/$path');
    final existing = file.existsSync() ? sha256(file.readAsBytesSync()) : null;
    final oldHash = previous[path];
    final newHash = next[path];
    if (existing != null && existing != oldHash && existing != newHash) {
      throw StateError(
        'Refusing to overwrite an unowned or edited file: $path',
      );
    }
    if (files.containsKey(path) && existing != newHash) changed.add(path);
    if (removed.contains(path) && existing != null) changed.add(path);
  }
  final paths = next.keys.toList()..sort();
  final ownershipBytes = utf8.encode(
    '${const JsonEncoder.withIndent('  ').convert({
      'format': 1,
      'release': version,
      'files': {for (final path in paths) path: next[path]},
    })}\n',
  );
  if (!ownership.existsSync() ||
      sha256(ownership.readAsBytesSync()) != sha256(ownershipBytes)) {
    changed.add(_ownershipFile);
  }
  for (final path in changed) {
    if (path == _ownershipFile) continue;
    if (files.containsKey(path)) {
      writeAtomic(File('${target.path}/$path'), files[path]!);
    } else {
      File('${target.path}/$path').deleteSync();
    }
  }
  // Only remove directories that contained owned paths. Unmanaged empty
  // directories and links are user state and remain untouched.
  final oldDirectories = <String>{};
  for (final path in previous.keys.where(
    (path) => path.startsWith('__releases/'),
  )) {
    final parts = path.split('/');
    for (var length = 1; length < parts.length; length++) {
      oldDirectories.add(parts.take(length).join('/'));
    }
  }
  final directories = oldDirectories.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final path in directories) {
    final directory = Directory('${target.path}/$path');
    if (FileSystemEntity.typeSync(directory.path, followLinks: false) ==
            FileSystemEntityType.directory &&
        directory.listSync(followLinks: false).isEmpty) {
      directory.deleteSync();
    }
  }
  if (changed.contains(_ownershipFile)) writeAtomic(ownership, ownershipBytes);
  return WebsitePublication(version, changed..sort());
}

Map<String, dynamic> _object(List<int> bytes, String path) {
  final value = jsonDecode(utf8.decode(bytes));
  if (value is! Map<String, dynamic>) {
    throw FormatException('Expected JSON object: $path');
  }
  return value;
}

String _canonicalRoot(Directory directory) {
  var existing = Directory.fromUri(directory.absolute.uri.normalizePath());
  final suffix = <String>[];
  while (!existing.existsSync()) {
    final parts = existing.uri.pathSegments.where((part) => part.isNotEmpty);
    suffix.insert(0, parts.last);
    existing = existing.parent;
  }
  return [existing.resolveSymbolicLinksSync(), ...suffix].join('/');
}

List<int> _read(Directory directory, String path) {
  _checkPath(directory, path);
  final file = File('${directory.path}/$path');
  if (!file.existsSync()) throw StateError('Missing release file: $path');
  return file.readAsBytesSync();
}

bool _safe(String path) =>
    path.isNotEmpty &&
    !path.contains('\\') &&
    !path.contains('?') &&
    !path.contains('#') &&
    path
        .split('/')
        .every((part) => part.isNotEmpty && part != '.' && part != '..');

bool _previouslyManaged(String path) {
  // Historical ownership must outlive a retired asset's release eligibility:
  // remove its owned root alias and retired copies during the flat migration.
  const retiredAssets = {'github-mark.svg'};
  if (!_safe(path)) return false;
  if (const {
    'CNAME',
    '.nojekyll',
    'service_worker.js',
    'release.json',
  }.contains(path)) {
    return true;
  }
  if (path.startsWith('__releases/')) {
    final parts = path.split('/');
    if (parts.length < 3 || !_digest.hasMatch(parts[1])) return false;
    final asset = parts.skip(2).join('/');
    return asset == 'release.json' ||
        isShellAsset(asset) ||
        retiredAssets.contains(asset);
  }
  return isShellAsset(path) || retiredAssets.contains(path);
}

void _checkPath(Directory root, String path) {
  if (!_safe(path)) throw FormatException('Unsafe path: $path');
  if (FileSystemEntity.typeSync(root.path, followLinks: false) ==
      FileSystemEntityType.link) {
    throw StateError('Release and destination roots cannot be symlinks.');
  }
  var current = root.absolute.path;
  final parts = path.split('/');
  for (var index = 0; index < parts.length; index++) {
    final part = parts[index];
    current = '$current/$part';
    final type = FileSystemEntity.typeSync(current, followLinks: false);
    if (type == FileSystemEntityType.link) {
      throw StateError('Symlinks cannot be deployed: $path');
    }
    if (index < parts.length - 1 && type == FileSystemEntityType.file) {
      throw StateError('A file blocks a release directory: $path');
    }
  }
  final type = FileSystemEntity.typeSync(current, followLinks: false);
  if (type != FileSystemEntityType.notFound &&
      type != FileSystemEntityType.file) {
    throw StateError('Expected a file: $path');
  }
}

void main(List<String> args) {
  if (args.length < 2 || args.length > 3) {
    stderr.writeln(
      'Usage: dart run tool/prepare_website.dart RELEASE_DIRECTORY WEBSITE_CHECKOUT [CHANGED_PATHS_FILE]',
    );
    exitCode = 64;
    return;
  }
  final result = prepareWebsite(Directory(args[0]), Directory(args[1]));
  if (args.length == 3) {
    File(args[2]).writeAsStringSync(
      result.changedPaths.map((path) => '$path\u0000').join(),
    );
  }
  stdout.writeln(
    'Validated release ${result.version}; ${result.changedPaths.length} website files changed.',
  );
}
