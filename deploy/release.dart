import 'dart:convert';
import 'dart:io';

import '../tool/build.dart' as pwa;
import '../tool/content_hash.dart';

void main() {
  final version = publishDeployment(
    source: Directory('build/container-input'),
    target: Directory('build/container-web'),
    policy: Directory('deploy/nginx'),
  );
  stdout.writeln('Docker PWA release with nginx policy: $version');
}

/// Response headers are part of the installed shell's policy. A changed CSP
/// must create new stamped HTML, otherwise an old worker returns the old CSP.
String publishDeployment({
  required Directory source,
  required Directory target,
  required Directory policy,
}) {
  final files =
      policy
          .listSync(followLinks: false)
          .whereType<File>()
          .where((file) => file.path.endsWith('.conf'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  if (files.isEmpty) throw StateError('nginx policy is missing.');
  final digest = sha256(
    utf8.encode(
      jsonEncode({
        for (final file in files)
          file.uri.pathSegments.last: sha256(file.readAsBytesSync()),
      }),
    ),
  );
  final worker =
      '${File('web/service_worker.js').readAsStringSync()}\n// Deployment response policy: $digest\n';
  final release = pwa.prepareRelease(source, worker);
  pwa.publishRelease(release, target);
  return release.version;
}
