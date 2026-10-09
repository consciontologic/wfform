import 'dart:io';

/// Only explicitly supplied, trusted Flutter build files are served. Local
/// credential overrides are excluded even if a development build contains one.
class StaticHost {
  StaticHost(Directory directory)
    : root = directory.resolveSymbolicLinksSync() {
    if (!File('$root/index.html').existsSync()) {
      throw const FormatException(
        'Web root must contain a trusted Flutter build with index.html.',
      );
    }
  }
  final String root;
  Future<void> serve(HttpRequest request) async {
    final response = request.response;
    if (!['GET', 'HEAD'].contains(request.method)) {
      response.statusCode = 405;
      return;
    }
    final segments = request.uri.pathSegments;
    if (segments.any(
      (part) =>
          part == '..' ||
          part.startsWith('.') ||
          part.contains('\\') ||
          part.contains('/') ||
          part.contains('\u0000'),
    )) {
      response.statusCode = 403;
      return;
    }
    final relative = segments.where((part) => part.isNotEmpty).join('/');
    final checkedRelative = Platform.isWindows
        ? relative.toLowerCase()
        : relative;
    if (checkedRelative.startsWith('config/') || checkedRelative == 'config') {
      response.statusCode = 403;
      return;
    }
    var file = File('$root/${relative.isEmpty ? 'index.html' : relative}');
    if (!file.existsSync() && !relative.split('/').last.contains('.')) {
      file = File('$root/index.html');
    }
    if (!file.existsSync()) {
      response.statusCode = 404;
      return;
    }
    final resolved = file.resolveSymbolicLinksSync();
    final checkedResolved = Platform.isWindows
        ? resolved.toLowerCase()
        : resolved;
    final checkedRoot = Platform.isWindows ? root.toLowerCase() : root;
    if (!checkedResolved.startsWith('$checkedRoot${Platform.pathSeparator}')) {
      response.statusCode = 403;
      return;
    }
    final resolvedRelative = checkedResolved.substring(checkedRoot.length + 1);
    if (resolvedRelative
            .split(Platform.pathSeparator)
            .any((part) => part.startsWith('.')) ||
        resolvedRelative.startsWith('config${Platform.pathSeparator}')) {
      response.statusCode = 403;
      return;
    }
    response.headers.set(
      'Content-Type',
      const {
            'html': 'text/html; charset=utf-8',
            'js': 'text/javascript; charset=utf-8',
            'json': 'application/json; charset=utf-8',
            'wasm': 'application/wasm',
            'png': 'image/png',
            'jpg': 'image/jpeg',
            'jpeg': 'image/jpeg',
            'svg': 'image/svg+xml',
            'ico': 'image/x-icon',
            'woff': 'font/woff',
            'woff2': 'font/woff2',
            'ttf': 'font/ttf',
            'css': 'text/css; charset=utf-8',
            'txt': 'text/plain; charset=utf-8',
            'xml': 'application/xml; charset=utf-8',
          }[file.path.split('.').last.toLowerCase()] ??
          'application/octet-stream',
    );
    // Open once so an atomic build publication cannot change header/body identity.
    final descriptor = await file.open();
    try {
      var remaining = await descriptor.length();
      response.contentLength = remaining;
      if (request.method == 'GET') {
        while (remaining > 0) {
          final bytes = await descriptor.read(
            remaining > 65536 ? 65536 : remaining,
          );
          if (bytes.isEmpty) {
            throw const FileSystemException('Static file truncated.');
          }
          remaining -= bytes.length;
          response.add(bytes);
          await response.flush();
        }
      }
    } finally {
      await descriptor.close();
    }
  }
}
