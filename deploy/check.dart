import 'dart:convert';
import 'dart:io';

import '../tool/content_hash.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    throw ArgumentError(
      'Usage: dart run deploy/check.dart http[s]://localhost:port [--certificate=path]',
    );
  }
  final base = Uri.parse(args.first);
  if (!['http', 'https'].contains(base.scheme) ||
      !['localhost', '127.0.0.1', '::1'].contains(base.host)) {
    throw ArgumentError(
      'This bounded check is for an explicit loopback deployment.',
    );
  }
  final security = SecurityContext(withTrustedRoots: true);
  for (final arg in args.skip(1)) {
    if (!arg.startsWith('--certificate=')) {
      throw ArgumentError('Unknown check option.');
    }
    security.setTrustedCertificates(arg.substring(14));
  }
  final client = HttpClient(context: security)
    ..connectionTimeout = const Duration(seconds: 10);
  try {
    Future<({List<int> body, Map<String, String> headers, int status})> read(
      String path, {
      String method = 'GET',
    }) async {
      final request = await client
          .openUrl(method, base.resolve(path))
          .timeout(const Duration(seconds: 10));
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      final body = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 10))) {
        body.addAll(chunk);
        if (body.length > 50 * 1024 * 1024) {
          throw StateError('Local response too large.');
        }
      }
      final headers = <String, String>{};
      response.headers.forEach(
        (name, values) => headers[name] = values.join(', '),
      );
      validateHeaders(headers, https: base.scheme == 'https');
      return (body: body, headers: headers, status: response.statusCode);
    }

    final health = await read('/healthz');
    if (health.status != 200 || utf8.decode(health.body).trim() != 'ok') {
      throw StateError('Health check failed.');
    }
    for (final path in [
      '/',
      '/service_worker.js',
      '/release.json',
      '/manifest.json',
    ]) {
      final response = await read(path);
      if (response.status != 200 ||
          response.headers['cache-control'] != 'no-store') {
        throw StateError('Entrypoint/cache policy failed: $path');
      }
    }
    final missing = await read('/__releases/${'0' * 64}/missing.js');
    if (missing.status != 404 ||
        missing.headers['cache-control'] != 'no-store') {
      throw StateError('Asset miss must be an uncached 404.');
    }
    if ((await read('/.git/config')).status != 404 ||
        (await read('/', method: 'POST')).status != 405) {
      throw StateError('Static-only access policy failed.');
    }
    final config = await read('/config/local.json');
    if (![200, 404].contains(config.status) ||
        config.headers['cache-control'] != 'no-store') {
      throw StateError('Runtime configuration cache policy failed.');
    }
    final manifestResponse = await read('/release.json');
    final manifest = jsonDecode(utf8.decode(manifestResponse.body)) as Map;
    final version = manifest['version'] as String;
    final assets = manifest['assets'] as Map;
    for (final entry in assets.entries) {
      final response = await read('/__releases/$version/${entry.key}');
      final metadata = entry.value as Map;
      if (response.status != 200 ||
          response.body.length != metadata['bytes'] ||
          sha256(response.body) != metadata['sha256']) {
        throw StateError(
          'Served immutable asset failed integrity: ${entry.key}',
        );
      }
      if (response.headers['cache-control'] !=
          'public, max-age=31536000, immutable') {
        throw StateError('Immutable cache policy missing.');
      }
      if ((entry.key as String).endsWith('.wasm') &&
          response.headers['content-type'] != 'application/wasm') {
        throw StateError('WASM MIME type missing.');
      }
    }
    stdout.writeln(
      'PASS $base: health, enforced security headers, error/method policy, config no-store, ${assets.length} immutable assets with SHA-256, WASM MIME. Release $version',
    );
    stdout.writeln(
      'Runtime configuration: ${config.status == 404 ? 'absent (session key)' : 'explicitly mounted; contents not logged'}.',
    );
  } finally {
    client.close(force: true);
  }
}

void validateHeaders(Map<String, String> headers, {required bool https}) {
  for (final entry in {
    'x-content-type-options': 'nosniff',
    'x-frame-options': 'DENY',
    'referrer-policy': 'no-referrer',
    'cross-origin-opener-policy': 'same-origin',
    'cross-origin-resource-policy': 'same-origin',
  }.entries) {
    if (headers[entry.key] != entry.value) {
      throw StateError('Missing/incorrect ${entry.key}.');
    }
  }
  final csp = headers['content-security-policy'] ?? '';
  for (final directive in [
    "default-src 'none'",
    "script-src 'self' 'wasm-unsafe-eval'",
    "script-src-attr 'none'",
    "connect-src 'self' https://openrouter.ai https://fonts.gstatic.com/s/",
    "font-src 'self' data: https://fonts.gstatic.com/s/",
    "frame-ancestors 'none'",
    "object-src 'none'",
  ]) {
    if (!csp.split(';').map((part) => part.trim()).contains(directive)) {
      throw StateError('CSP directive missing: $directive');
    }
  }
  if (csp.contains("'unsafe-eval'") ||
      csp.contains('https:;') ||
      csp.contains('*')) {
    throw StateError('CSP unexpectedly broad.');
  }
  final permissions = (headers['permissions-policy'] ?? '')
      .split(',')
      .map((directive) => directive.trim());
  for (final directive in [
    'camera=()',
    'microphone=()',
    'clipboard-read=(self)',
    'clipboard-write=(self)',
  ]) {
    if (!permissions.contains(directive)) {
      throw StateError('Permissions policy missing: $directive');
    }
  }
  if (https && headers['strict-transport-security'] != 'max-age=86400') {
    throw StateError('TLS HSTS rollout policy missing.');
  }
  if (!https && headers.containsKey('strict-transport-security')) {
    throw StateError('HSTS must not be sent over HTTP.');
  }
}
