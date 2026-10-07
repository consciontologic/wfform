import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../../deploy/release.dart';

void main() {
  test(
    'nginx policy changes release identity, retains old assets and is stable',
    () {
      Directory('work').createSync();
      final scratch = Directory('work').createTempSync('deployment-release-');
      addTearDown(() => scratch.deleteSync(recursive: true));
      final raw = Directory('${scratch.path}/raw')..createSync();
      for (final entry in {
        'main.dart.js': 'fixture',
        'index.html': '<script src="flutter_bootstrap.js" async></script>',
        'flutter_bootstrap.js': "const path = '__RELEASE_BASE__';",
        'manifest.json': '{"id":"./"}',
      }.entries) {
        File('${raw.path}/${entry.key}').writeAsStringSync(entry.value);
      }
      final policy = Directory('${scratch.path}/nginx')..createSync();
      final header = File('${policy.path}/headers.conf')
        ..writeAsStringSync('policy one');
      final target = Directory('${scratch.path}/published');
      final first = publishDeployment(
        source: raw,
        target: target,
        policy: policy,
      );
      header.writeAsStringSync('policy two');
      final second = publishDeployment(
        source: raw,
        target: target,
        policy: policy,
      );
      expect(second, isNot(first));
      expect(
        publishDeployment(source: raw, target: target, policy: policy),
        second,
      );
      expect(
        File('${target.path}/__releases/$first/index.html').existsSync(),
        isTrue,
      );
      expect(
        File('${target.path}/__releases/$second/index.html').readAsStringSync(),
        contains(second),
      );
      expect(File('${target.path}/config/local.json').existsSync(), isFalse);
    },
  );
}
