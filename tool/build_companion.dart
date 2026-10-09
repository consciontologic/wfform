import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'build.dart' show isShellAsset;
import 'content_hash.dart';
import 'release_version.dart';

class CompanionPackageTarget {
  CompanionPackageTarget(this.os, this.architecture) {
    if (!(os == 'linux' && ['x64', 'arm64'].contains(architecture)) &&
        !(os == 'windows' && architecture == 'x64')) {
      throw UnsupportedError(
        'Supported companion targets: Linux x64/arm64 and Windows x64. macOS is deferred.',
      );
    }
  }
  final String os;
  final String architecture;
  String get platform => '$os-$architecture';
  String get installedBinaryName =>
      os == 'windows' ? 'wfformcomp.exe' : 'wfformcomp';
  String get binaryName =>
      'wfformcomp-${readReleaseVersion()}-$platform${os == 'windows' ? '.exe' : ''}';
  String get archiveName =>
      'wfformcomp-${readReleaseVersion()}-$platform.${os == 'windows' ? 'zip' : 'tar.gz'}';
  String get metadataName =>
      'wfformcomp-${readReleaseVersion()}-$platform.json';
}

/// Builds the current host binary and a portable Linux/Windows archive. Optional web
/// files must come from a trusted public build; private config is never copied.
Future<void> main(List<String> args) async {
  if (args.isNotEmpty && (args.length != 2 || args.first != '--web-root')) {
    stderr.writeln(
      'Usage: dart run tool/build_companion.dart [--web-root build/web]',
    );
    exitCode = 64;
    return;
  }
  if (!Platform.isLinux && !Platform.isWindows) {
    stderr.writeln('Build on Linux or Windows; macOS remains deferred.');
    exitCode = 64;
    return;
  }
  final target = CompanionPackageTarget(
    Platform.operatingSystem,
    Abi.current().toString().split('_').last,
  );
  final output = Directory('build/companion')..createSync(recursive: true);
  final binary = File('${output.path}/${target.binaryName}');
  final dart = Platform.resolvedExecutable;
  Future<void> run(String executable, List<String> arguments) async {
    final result = await Process.run(executable, arguments, runInShell: false);
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    if (result.exitCode != 0) {
      throw StateError(
        'Companion build step failed with exit ${result.exitCode}.',
      );
    }
  }

  await run(dart, ['run', 'tool/release_version.dart', '--check']);
  await run(dart, ['pub', 'get', '--offline', '-C', 'companion']);
  final temporaryBinary = File('${binary.path}.compiling-$pid');
  try {
    await run(dart, [
      'compile',
      'exe',
      'companion/bin/wfformcomp.dart',
      '-o',
      temporaryBinary.path,
    ]);
    temporaryBinary.renameSync(binary.path);
  } finally {
    if (temporaryBinary.existsSync()) temporaryBinary.deleteSync();
  }
  final package = output.createTempSync('package-');
  try {
    binary.copySync('${package.path}/${target.installedBinaryName}');
    if (!Platform.isWindows) {
      await run('chmod', [
        '755',
        '${package.path}/${target.installedBinaryName}',
      ]);
    }
    File('${package.path}/README.md').writeAsStringSync(
      companionPackageInstructions(
        File('docs/wfformcomp.md').readAsStringSync(),
      ),
    );
    File('${package.path}/TOOLS.md').writeAsStringSync(
      companionPackageInstructions(File('docs/tools.md').readAsStringSync()),
    );
    File(
      'companion/config.example.json',
    ).copySync('${package.path}/config.example.json');
    if (args.isNotEmpty) {
      copyCompanionWebBuild(
        Directory(args[1]),
        Directory('${package.path}/web'),
      );
    }
    final archive = File('${output.path}/${target.archiveName}');
    if (archive.existsSync()) archive.deleteSync();
    if (Platform.isWindows) {
      // Fixed PowerShell program; paths are data, never interpolated into code.
      final result = await Process.run(
        '${Platform.environment['SystemRoot']}\\System32\\WindowsPowerShell\\v1.0\\powershell.exe',
        [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          r'''$ErrorActionPreference = 'Stop'; Add-Type -AssemblyName System.IO.Compression.FileSystem; [System.IO.Compression.ZipFile]::CreateFromDirectory($env:WFFORM_PACKAGE_DIRECTORY, $env:WFFORM_PACKAGE_ARCHIVE)''',
        ],
        environment: {
          'WFFORM_PACKAGE_DIRECTORY': package.absolute.path,
          'WFFORM_PACKAGE_ARCHIVE': archive.absolute.path,
        },
        runInShell: false,
      );
      if (result.exitCode != 0) {
        throw StateError('Could not create Windows archive: ${result.stderr}');
      }
    } else {
      await run('tar', [
        '-czf',
        archive.absolute.path,
        '-C',
        package.path,
        '.',
      ]);
    }
    final checksum = sha256(archive.readAsBytesSync());
    File(
      '${archive.path}.sha256',
    ).writeAsStringSync('$checksum  ${archive.uri.pathSegments.last}\n');
    File('${output.path}/${target.metadataName}').writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({
        'name': 'wfformcomp',
        'version': readReleaseVersion(),
        'platform': target.platform,
        'archive': archive.uri.pathSegments.last,
        'sha256': checksum,
        'containsWebBuild': args.isNotEmpty,
        'protocolVersions': ['2025-11-25', '2025-06-18', '2025-03-26'],
      })}\n',
    );
    stdout.writeln('Companion package: ${archive.path}');
  } finally {
    package.deleteSync(recursive: true);
  }
}

/// Keep the two user guides mutually navigable in the extracted package.
String companionPackageInstructions(String source) => source
    .replaceAll('(tools.md', '(TOOLS.md')
    .replaceAll('(wfformcomp.md', '(README.md');

/// Copies the verified flat public package, never historical
/// release directories or unlisted local files. Validation precedes all writes.
void copyCompanionWebBuild(Directory web, Directory destination) {
  if (FileSystemEntity.typeSync(destination.path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    throw ArgumentError('Companion web destination must be a new directory.');
  }
  final source = Directory(web.resolveSymbolicLinksSync());
  final digest = RegExp(r'^[a-f0-9]{64}$');
  final credential = RegExp(
    r'sk-or-v1-[A-Za-z0-9_-]{12,}|github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----',
  );
  List<int> read(String relative) {
    final file = File('${source.path}/$relative');
    if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
            FileSystemEntityType.file ||
        file.resolveSymbolicLinksSync() != file.absolute.uri.toFilePath()) {
      throw StateError('Expected an ordinary public asset: $relative');
    }
    final bytes = file.readAsBytesSync();
    if (credential.hasMatch(latin1.decode(bytes))) {
      throw StateError('Refusing credential-bearing public asset: $relative');
    }
    return bytes;
  }

  final manifestBytes = read('release.json');
  final manifest = jsonDecode(utf8.decode(manifestBytes));
  if (manifest is! Map ||
      manifest['format'] != 3 ||
      manifest['packageVersion'] != readReleaseVersion() ||
      manifest['version'] is! String ||
      !digest.hasMatch(manifest['version'] as String) ||
      manifest['assets'] is! Map) {
    throw const FormatException('Expected a versioned public PWA release.');
  }
  final version = manifest['version'] as String;
  final assets = manifest['assets'] as Map;
  final files = <String, List<int>>{'release.json': manifestBytes};
  for (final entry in assets.entries) {
    final path = entry.key;
    final metadata = entry.value;
    if (path is! String ||
        !RegExp(r'^[A-Za-z0-9_./-]+$').hasMatch(path) ||
        path.startsWith('/') ||
        path.split('/').any((part) => part.isEmpty || part.startsWith('.')) ||
        !isShellAsset(path) ||
        metadata is! Map ||
        metadata['bytes'] is! int ||
        (metadata['bytes'] as int) < 0 ||
        metadata['sha256'] is! String ||
        !digest.hasMatch(metadata['sha256'] as String)) {
      throw const FormatException('Unsafe public asset path or metadata.');
    }
    for (final location in [path]) {
      final bytes = read(location);
      if (bytes.length != metadata['bytes'] ||
          sha256(bytes) != metadata['sha256']) {
        throw StateError('Public release integrity failed: $location');
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
    if (!assets.containsKey(required)) {
      throw StateError('Incomplete public release: missing $required');
    }
  }
  final worker = read('service_worker.js');
  if (!utf8.decode(worker).contains("const VERSION = '$version';")) {
    throw StateError('Service worker does not match the active release.');
  }
  files['service_worker.js'] = worker;
  if (sha256(read('release.json')) != sha256(manifestBytes)) {
    throw StateError('Public release changed during packaging; build again.');
  }
  for (final entry in files.entries) {
    final target = File('${destination.path}/${entry.key}');
    target.parent.createSync(recursive: true);
    target.writeAsBytesSync(entry.value, flush: true);
  }
}
