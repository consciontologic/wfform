import 'dart:io';

final semanticVersion = RegExp(
  r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$',
);

String readReleaseVersion() {
  final match = RegExp(
    r'^version:\s*(\S+)\s*$',
    multiLine: true,
  ).firstMatch(File('pubspec.yaml').readAsStringSync());
  final version = match?.group(1) ?? '';
  if (!semanticVersion.hasMatch(version)) {
    throw const FormatException('Use a plain x.y.z version in pubspec.yaml.');
  }
  return version;
}

/// The root pubspec is authoritative. CI checks generated identities without edits.
void main(List<String> args) {
  if (args.length != 1 || !['--check', '--sync'].contains(args.single)) {
    throw ArgumentError(
      'Usage: dart run tool/release_version.dart --check|--sync',
    );
  }
  final version = readReleaseVersion();
  final substitutions = <String, (RegExp, String)>{
    'companion/pubspec.yaml': (
      RegExp(r'^version:.*$', multiLine: true),
      'version: $version',
    ),
    'lib/app/app_identity.dart': (
      RegExp(r"const appVersion = '[^']+';"),
      "const appVersion = '$version';",
    ),
    'companion/lib/wfformcomp.dart': (
      RegExp(r"const companionVersion = '[^']+';"),
      "const companionVersion = '$version';",
    ),
    for (final page in ['about', 'terms', 'liability'])
      'web/$page.html': (
        RegExp(r'(<p class="footer-version">wfform <span>)[^<]+(</span></p>)'),
        '<p class="footer-version">wfform <span>$version</span></p>',
      ),
  };
  for (final entry in substitutions.entries) {
    final file = File(entry.key);
    final source = file.readAsStringSync();
    if (entry.value.$1.allMatches(source).length != 1) {
      throw StateError('Expected one version identity: ${entry.key}');
    }
    final expected = source.replaceAll(entry.value.$1, entry.value.$2);
    if (source == expected) continue;
    if (args.single == '--check') {
      throw StateError('Version drift: ${entry.key}; run make version.sync');
    }
    file.writeAsStringSync(expected);
  }
  stdout.writeln('✅ Release identities agree: $version');
}
