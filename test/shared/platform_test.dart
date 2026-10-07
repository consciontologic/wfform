import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/shared/platform.dart';
import '../../tool/build.dart' as build;
import '../../tool/icons.dart' as icons;
import '../../tool/serve.dart' as serve;

void main() {
  test('nonweb PWA inspection explicitly reports unavailable', () async {
    final platform = createPlatformBridge();
    addTearDown(platform.dispose);
    expect(await platform.inspectPwa(), containsPair('supported', false));
  });

  test(
    'memory store round trips, replaces, removes and isolates instances',
    () {
      final store = MemoryStore();
      expect(store.read('draft'), isNull);
      store.write('draft', 'hello 🌿');
      expect(store.read('draft'), 'hello 🌿');
      store.write('draft', 'changed');
      expect(store.read('draft'), 'changed');
      expect(MemoryStore().read('draft'), isNull);
      store.remove('draft');
      expect(store.read('draft'), isNull);
    },
  );
  test(
    'release cache allowlist excludes credentials, unknown files and maps',
    () {
      for (final path in [
        'config/local.json',
        'api/chat',
        'credentials.json',
        'main.dart.js.map',
        'service_worker.js',
        'flutter_service_worker.js',
      ]) {
        expect(build.isShellAsset(path), isFalse, reason: path);
      }
      for (final path in [
        'index.html',
        'main.dart.js',
        'assets/FontManifest.json',
        'canvaskit/canvaskit.wasm',
        'icons/Icon-192.png',
      ]) {
        expect(build.isShellAsset(path), isTrue, reason: path);
      }
    },
  );
  test(
    'worker does not runtime-cache; configuration and authenticated fetch bypass it',
    () {
      final worker = File('web/service_worker.js').readAsStringSync();
      expect(worker, contains("request.headers.has('authorization')"));
      expect(worker, contains("url.pathname.includes('/config/')"));
      expect(worker, contains("request.method !== 'GET'"));
      final fetchHandler = worker.substring(
        worker.indexOf("self.addEventListener('fetch'"),
      );
      expect(fetchHandler, isNot(contains('.put(')));
      expect(worker, contains("event.data?.type === 'APPLY_UPDATE'"));
    },
  );
  test(
    'manifest and original icons include installable sizes and maskable variants',
    () {
      final manifest =
          jsonDecode(File('web/manifest.json').readAsStringSync()) as Map;
      expect(manifest['display'], 'standalone');
      expect(manifest['start_url'], './');
      for (final icon in manifest['icons'] as List) {
        final bytes = File('web/${icon['src']}').readAsBytesSync();
        expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
        final header = ByteData.sublistView(bytes);
        final size = int.parse((icon['sizes'] as String).split('x').first);
        expect(header.getUint32(16), size);
        expect(header.getUint32(20), size);
      }
      expect(icons.crc32(ascii.encode('123456789')), 0xcbf43926);
    },
  );
  test(
    'static host serves correct wasm, JS, manifest and font media types',
    () {
      expect(serve.mimeType('x.wasm'), 'application/wasm');
      expect(serve.mimeType('x.js'), 'text/javascript; charset=utf-8');
      expect(
        serve.mimeType('manifest.json'),
        'application/json; charset=utf-8',
      );
      expect(serve.mimeType('x.woff2'), 'font/woff2');
    },
  );
}
