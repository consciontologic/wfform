import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../../deploy/package.dart';
import '../../tool/build.dart' as build;

void main() {
  late Directory scratch;
  late Directory source;
  late Directory output;
  setUp(() {
    Directory('work').createSync();
    scratch = Directory('work').createTempSync('deployment-test-');
    source = Directory('${scratch.path}/source')..createSync();
    output = Directory('${scratch.path}/context');
    final raw = Directory('${scratch.path}/raw')..createSync();
    for (final entry in {
      'main.dart.js': 'void fixture() {}',
      'index.html': '<script src="flutter_bootstrap.js" async></script>',
      'flutter_bootstrap.js': "const path = '__RELEASE_BASE__';",
      'manifest.json': '{"id":"./","name":"wfform"}',
    }.entries) {
      File('${raw.path}/${entry.key}').writeAsStringSync(entry.value);
    }
    build.publishRelease(
      build.prepareRelease(
        raw,
        File('web/service_worker.js').readAsStringSync(),
      ),
      source,
    );
    File('${source.path}/config/local.json')
      ..parent.createSync()
      ..writeAsStringSync('{"apiKey":"fixture credential must stay outside"}');
    File('${source.path}/.env').writeAsStringSync('LOCAL_SECRET=fixture');
    File('${source.path}/debug.txt').writeAsStringSync('not a shell asset');
  });
  tearDown(() => scratch.deleteSync(recursive: true));

  test('packaging never deletes an unrelated existing target directory', () {
    output.createSync();
    final unrelated = File('${output.path}/keep.txt')
      ..writeAsStringSync('keep');
    expect(
      () => packageRelease(source: source, target: output),
      throwsArgumentError,
    );
    expect(unrelated.readAsStringSync(), 'keep');
  });

  test(
    'context contains only validated shell generations and deployment files',
    () {
      packageRelease(source: source, target: output);
      expect(File('${output.path}/site/main.dart.js').existsSync(), isTrue);
      expect(
        File('${output.path}/site/service_worker.js').existsSync(),
        isTrue,
      );
      expect(File('${output.path}/Dockerfile').existsSync(), isTrue);
      expect(
        File('${output.path}/site/config/local.json').existsSync(),
        isFalse,
      );
      expect(File('${output.path}/site/.env').existsSync(), isFalse);
      expect(File('${output.path}/site/debug.txt').existsSync(), isFalse);
      expect(Directory('${output.path}/site/__releases').existsSync(), isFalse);
    },
  );

  test('damaged shell fails closed without replacing existing context', () {
    packageRelease(source: source, target: output);
    File('${source.path}/main.dart.js').writeAsStringSync('unexpected bytes');
    expect(
      () => packageRelease(source: source, target: output),
      throwsStateError,
    );
    expect(
      File('${output.path}/site/main.dart.js').readAsStringSync(),
      'void fixture() {}',
    );
  });

  test('manifest path traversal and configuration entries are rejected', () {
    final manifestFile = File('${source.path}/release.json');
    final manifest = jsonDecode(manifestFile.readAsStringSync()) as Map;
    (manifest['assets'] as Map)['../outside'] = {
      'sha256': '0' * 64,
      'bytes': 1,
    };
    manifestFile.writeAsStringSync(jsonEncode(manifest));
    expect(
      () => packageRelease(source: source, target: output),
      throwsFormatException,
    );
  });

  test(
    'symlinks and credential-bearing worker never reach the image context',
    () {
      final script = File('${source.path}/main.dart.js')..deleteSync();
      Link(script.path).createSync('${scratch.absolute.path}/outside');
      expect(
        () => packageRelease(source: source, target: output),
        throwsStateError,
      );
      Link(script.path).deleteSync();
      script.writeAsStringSync('void fixture() {}');
      File(
        '${source.path}/service_worker.js',
      ).writeAsStringSync("const bad = 'sk-or-v1-${'f' * 40}';");
      expect(
        () => packageRelease(source: source, target: output),
        throwsStateError,
      );
    },
  );
}
