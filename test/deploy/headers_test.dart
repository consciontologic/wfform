import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../../deploy/check.dart';
import '../../tool/content_hash.dart';

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
        "default-src 'none'; script-src 'self' 'wasm-unsafe-eval' https://www.googletagmanager.com 'sha256-eT57Z1ypzgtV4l0KJ9uVPW8NoWW0r07qRLOWTCZONMo=' 'sha256-ceOprgawj2RQrm546DhERntcne7eurN77Kn5b5l2zns='; script-src-attr 'none'; connect-src 'self' https://openrouter.ai https://fonts.gstatic.com/s/ https://www.googletagmanager.com https://*.google-analytics.com https://www.google.com https://analytics.google.com; font-src 'self' data: https://fonts.gstatic.com/s/; frame-ancestors 'none'; object-src 'none'",
  };

  test('Google tag has a matching narrow CSP hash on every HTML page', () {
    final config = File('deploy/nginx/headers.conf').readAsStringSync();
    final policy = RegExp(
      r'add_header Content-Security-Policy "([^"]+)"',
    ).firstMatch(config)!.group(1)!;
    final scripts = policy
        .split(';')
        .singleWhere((part) => part.trim().startsWith('script-src '));
    expect(scripts, contains('https://www.googletagmanager.com'));
    expect(scripts, isNot(contains("'unsafe-inline'")));
    for (final file in Directory('web').listSync().whereType<File>().where(
      (file) => file.path.endsWith('.html'),
    )) {
      final inline = RegExp(r'<script>([\s\S]*?)</script>')
          .allMatches(file.readAsStringSync())
          .where(
            (match) =>
                match.group(1)!.contains("gtag('config', 'G-P3K2ZN7YTL')"),
          )
          .toList();
      expect(inline, hasLength(1), reason: file.path);
      final digest = sha256(utf8.encode(inline.single.group(1)!));
      final hash = base64.encode([
        for (var i = 0; i < digest.length; i += 2)
          int.parse(digest.substring(i, i + 2), radix: 16),
      ]);
      expect(scripts, contains("'sha256-$hash'"), reason: file.path);
    }
  });

  test('bootstrap download guard has its own exact narrow CSP hash', () {
    final html = File('web/index.html').readAsStringSync();
    final inline = RegExp(
      r'<script id="bootstrap-load-guard">([\s\S]*?)</script>',
    ).firstMatch(html);
    expect(inline, isNotNull);
    final digest = sha256(utf8.encode(inline!.group(1)!));
    final hash = base64.encode([
      for (var i = 0; i < digest.length; i += 2)
        int.parse(digest.substring(i, i + 2), radix: 16),
    ]);
    final config = File('deploy/nginx/headers.conf').readAsStringSync();
    final policy = RegExp(
      r'add_header Content-Security-Policy "([^"]+)"',
    ).firstMatch(config)!.group(1)!;
    final scripts = policy
        .split(';')
        .singleWhere((part) => part.trim().startsWith('script-src '));
    expect(scripts, contains("'sha256-$hash'"));
    expect(scripts, isNot(contains("'unsafe-inline'")));
    expect(scripts, isNot(contains("'unsafe-hashes'")));
    expect(policy, contains("script-src-attr 'none'"));
    validateHeaders(
      valid()..['content-security-policy'] = policy,
      https: false,
    );
  });

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
