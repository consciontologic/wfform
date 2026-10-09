import 'dart:convert';
import 'dart:io';

import 'build_companion.dart' show copyCompanionWebBuild;
import 'content_hash.dart';
import 'release_version.dart';

/// Produce a versioned GitHub Releases asset from the same verified public site.
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    throw ArgumentError(
      'Usage: dart run tool/package_web.dart PUBLIC_WEB_DIRECTORY',
    );
  }
  final version = readReleaseVersion();
  final output = Directory('build/release')..createSync(recursive: true);
  final stage = output.createTempSync('web-package-');
  try {
    final site = Directory('${stage.path}/web');
    copyCompanionWebBuild(Directory(args.single), site);
    final archive = File('${output.path}/wfform-$version-web.tar.gz');
    final result = await Process.run('tar', [
      '-czf',
      archive.absolute.path,
      '-C',
      site.path,
      '.',
    ]);
    if (result.exitCode != 0) {
      throw StateError('Web archive failed: ${result.stderr}');
    }
    final checksum = sha256(archive.readAsBytesSync());
    File(
      '${archive.path}.sha256',
    ).writeAsStringSync('$checksum  ${archive.uri.pathSegments.last}\n');
    File('${output.path}/wfform-$version-web.json').writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({'name': 'wfform', 'version': version, 'archive': archive.uri.pathSegments.last, 'sha256': checksum, 'build': jsonDecode(File('${site.path}/release.json').readAsStringSync())})}\n',
    );
    stdout.writeln('📦 ${archive.path}');
  } finally {
    stage.deleteSync(recursive: true);
  }
}
