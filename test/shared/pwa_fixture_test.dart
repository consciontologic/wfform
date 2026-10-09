import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../../tool/build.dart' as build;
import '../../tool/content_hash.dart';
import '../../tool/pwa_fault_fixture.dart';
import '../../tool/serve.dart';

void main() {
  late Directory scratch;
  late Directory source;
  late Directory fixture;
  setUp(() {
    Directory('work').createSync();
    scratch = Directory('work').createTempSync('pwa-fixture-test-');
    final input = Directory('${scratch.path}/input')..createSync();
    for (final entry in {
      'index.html':
          '<base href="/"><script src="flutter_bootstrap.js" async></script>',
      'flutter_bootstrap.js': "const releasePath = '__RELEASE_BASE__';",
      'main.dart.js': 'console.log("static fixture");',
      'manifest.json': '{"id":"./"}',
      'assets/font.txt': 'fixture font',
    }.entries) {
      final file = File('${input.path}/${entry.key}');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value);
    }
    source = Directory('${scratch.path}/source');
    build.publishRelease(
      build.prepareRelease(
        input,
        File('web/service_worker.js').readAsStringSync(),
      ),
      source,
    );
    final private = File('${source.path}/config/local.json')
      ..parent.createSync();
    private.writeAsStringSync('{"apiKey":"private fixture value"}');
    fixture = Directory('${scratch.path}/fixture');
  });
  tearDown(() => scratch.deleteSync(recursive: true));

  test(
    'disposable setup keeps source unchanged and never copies local key',
    () {
      final before = File('${source.path}/main.dart.js').readAsBytesSync();
      createFixture(source, fixture);
      expect(File('${source.path}/main.dart.js').readAsBytesSync(), before);
      expect(
        jsonDecode(
          File('${fixture.path}/host/config/local.json').readAsStringSync(),
        ),
        {'apiKey': ''},
      );
      expect(
        File('${fixture.path}/input/config/local.json').existsSync(),
        isFalse,
      );
      expect(readFixture(fixture)['variant'], 'a');
      expect(() => createFixture(source, fixture), throwsStateError);
    },
  );
  test(
    'missing revision is staged before worker publication and repair keeps identity',
    () {
      createFixture(source, fixture);
      final old = readFixture(fixture)['release'];
      publishFault(fixture, 'b', 'missing');
      final state = readFixture(fixture);
      expect(state['release'], isNot(old));
      expect(state['fault'], 'missing');
      expect(
        File('${fixture.path}/host/__releases/$old/main.dart.js').existsSync(),
        isFalse,
      );
      final main = File('${fixture.path}/host/main.dart.js');
      expect(main.existsSync(), isFalse);
      expect(
        File('${fixture.path}/host/service_worker.js').readAsStringSync(),
        contains(state['release'] as String),
      );
      repairFixture(fixture);
      expect(readFixture(fixture)['release'], state['release']);
      expect(readFixture(fixture)['fault'], isNull);
      final manifest =
          jsonDecode(
                File('${fixture.path}/host/release.json').readAsStringSync(),
              )
              as Map;
      expect(
        sha256(main.readAsBytesSync()),
        (manifest['assets'] as Map)['main.dart.js']['sha256'],
      );
      expect(() => publishFault(fixture, 'b', 'missing'), throwsStateError);
    },
  );
  test(
    'corrupt revision fails its manifest hash and repair restores exact bytes',
    () {
      createFixture(source, fixture);
      publishFault(fixture, 'c', 'corrupt');
      final main = File('${fixture.path}/host/main.dart.js');
      final manifest =
          jsonDecode(
                File('${fixture.path}/host/release.json').readAsStringSync(),
              )
              as Map;
      final expected = (manifest['assets'] as Map)['main.dart.js']['sha256'];
      expect(sha256(main.readAsBytesSync()), isNot(expected));
      repairFixture(fixture);
      expect(sha256(main.readAsBytesSync()), expected);
      expect(() => repairFixture(fixture), throwsStateError);
    },
  );
  test(
    'unmarked directories cannot be mutated and isolated hosts exclude project config',
    () {
      expect(() => publishFault(fixture, 'b', 'missing'), throwsStateError);
      expect(() => repairFixture(fixture), throwsStateError);
      expect(
        shouldUseProjectConfig('config/local.json', isolatedConfig: true),
        isFalse,
      );
      expect(
        shouldUseProjectConfig('config/local.json', isolatedConfig: false),
        isTrue,
      );
      expect(
        shouldUseProjectConfig(
          'somewhere/config/local.json',
          isolatedConfig: false,
        ),
        isFalse,
      );
    },
  );
}
