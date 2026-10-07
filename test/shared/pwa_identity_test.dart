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
    expect(html, contains('wfform could not start'));
    expect(manifest['name'], 'wfform');
    expect(manifest['short_name'], 'wfform');
    expect(bootstrap, contains("document.getElementById('startup-error')"));
    expect('$html $manifest $bootstrap', isNot(contains('Free Model Studio')));
  });

  test(
    'bootstrap reveals failure details only after an unsuccessful start',
    () {
      final bootstrap = File('web/flutter_bootstrap.js').readAsStringSync();
      expect(
        bootstrap,
        contains("document.getElementById('startup-error-details')"),
      );
      expect(
        bootstrap,
        contains('details.textContent = String(error).slice(0, 300)'),
      );
      expect(bootstrap, contains('failure.hidden = false'));
      expect(bootstrap, contains('catch (error)'));
      expect(bootstrap, contains('showStartupError(error)'));
      expect(bootstrap, contains('.catch(showStartupError)'));
      expect(
        bootstrap.indexOf("document.getElementById('startup-error')?.remove()"),
        greaterThan(bootstrap.indexOf('await appRunner.runApp()')),
      );
      expect(bootstrap, isNot(contains('innerHTML')));
    },
  );

  test(
    'host handles a missing bootstrap download without requiring Flutter',
    () {
      final html = File('web/index.html').readAsStringSync();
      final guard = RegExp(
        r'<script id="bootstrap-load-guard">([\s\S]*?)</script>',
      ).firstMatch(html);
      expect(guard, isNotNull);
      final code = guard!.group(1)!;
      expect(code, contains("window.addEventListener('error'"));
      expect(code, contains('event.target instanceof HTMLScriptElement'));
      expect(code, contains("event.target.id !== 'flutter-bootstrap'"));
      expect(code, contains('}, true)'));
      expect(code, contains('failure.hidden = false'));
      expect(
        code,
        contains('The application startup file could not be loaded.'),
      );
      expect(code, isNot(contains('_flutter')));
      final bootstrap = RegExp(
        r'<script id="flutter-bootstrap" src="flutter_bootstrap.js" async>',
      ).firstMatch(html);
      expect(bootstrap, isNotNull);
      expect(guard.end, lessThan(bootstrap!.start));
      expect(html, isNot(contains('onerror=')));
    },
  );

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
