import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../../deploy/check.dart';

void main() {
  Map<String, String> valid() => {
    'x-content-type-options': 'nosniff',
    'x-frame-options': 'DENY',
    'referrer-policy': 'no-referrer',
    'cross-origin-opener-policy': 'same-origin',
    'cross-origin-resource-policy': 'same-origin',
    'permissions-policy':
        'camera=(), microphone=(), clipboard-read=(self), clipboard-write=(self)',
    'content-security-policy':
        "default-src 'none'; script-src 'self' 'wasm-unsafe-eval'; script-src-attr 'none'; connect-src 'self' https://openrouter.ai https://fonts.gstatic.com/s/; font-src 'self' data: https://fonts.gstatic.com/s/; frame-ancestors 'none'; object-src 'none'",
  };
  test(
    'HTTP header contract allows WASM but not general eval or embedding',
    () {
      validateHeaders(valid(), https: false);
      for (final field in valid().keys) {
        final missing = valid()..remove(field);
        expect(() => validateHeaders(missing, https: false), throwsStateError);
      }
      final broad = valid();
      broad['content-security-policy'] =
          "${broad['content-security-policy']}; script-src 'unsafe-eval'";
      expect(() => validateHeaders(broad, https: false), throwsStateError);
    },
  );
  test('HSTS is TLS-only and explicit', () {
    expect(() => validateHeaders(valid(), https: true), throwsStateError);
    final tls = valid()..['strict-transport-security'] = 'max-age=86400';
    validateHeaders(tls, https: true);
    expect(() => validateHeaders(tls, https: false), throwsStateError);
  });
  test(
    'editable paste needs same-origin clipboard read and write permissions',
    () {
      for (final directive in ['clipboard-read', 'clipboard-write']) {
        for (final replacement in ['$directive=()', '$directive=*']) {
          final policy = valid();
          policy['permissions-policy'] = policy['permissions-policy']!
              .replaceFirst('$directive=(self)', replacement);
          expect(() => validateHeaders(policy, https: false), throwsStateError);
        }
      }
      final configured = RegExp(r'add_header Permissions-Policy "([^"]+)"')
          .firstMatch(File('deploy/nginx/headers.conf').readAsStringSync())!
          .group(1)!;
      validateHeaders(
        valid()..['permissions-policy'] = configured,
        https: false,
      );
    },
  );
}
