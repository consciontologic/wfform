import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('browser and install surfaces consistently use the wfform identity', () {
    final html = File('web/index.html').readAsStringSync();
    final manifest =
        jsonDecode(File('web/manifest.json').readAsStringSync()) as Map;
    final bootstrap = File('web/flutter_bootstrap.js').readAsStringSync();
    expect(
      html,
      contains(
        '<title>wfform — Discover and Chat with Free OpenRouter Models</title>',
      ),
    );
    expect(
      html,
      contains('name="apple-mobile-web-app-title" content="wfform"'),
    );
    expect(html, contains('Opening wfform'));
    expect(manifest['name'], 'wfform');
    expect(manifest['short_name'], 'wfform');
    expect(bootstrap, contains('wfform could not start'));
    expect('$html $manifest $bootstrap', isNot(contains('Free Model Studio')));
  });

  test(
    'rename preserves installed PWA identity, launch scope and cache namespace',
    () {
      final manifest =
          jsonDecode(File('web/manifest.json').readAsStringSync()) as Map;
      final worker = File('web/service_worker.js').readAsStringSync();
      expect(manifest['id'], './');
      expect(manifest['start_url'], './');
      expect(manifest['scope'], './');
      expect(manifest['display'], 'standalone');
      expect(
        worker,
        contains("const CACHE = 'free-model-studio-__BUILD_ID__'"),
      );
      expect(worker, contains("key.startsWith('free-model-studio-')"));
    },
  );
}
