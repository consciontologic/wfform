import 'dart:io';

/// A local static-file development host only: no API, proxy or backend routes.
Future<void> main(List<String> args) async {
  var port = 8080;
  var directory = 'build/web';
  var isolatedConfig = false;
  for (final arg in args) {
    if (arg.startsWith('--port=')) {
      port = int.parse(arg.substring(7));
    } else if (arg.startsWith('--directory=')) {
      directory = arg.substring(12);
    } else if (arg == '--isolated-config') {
      isolatedConfig = true;
    } else {
      stderr.writeln(
        'Usage: dart run tool/serve.dart [--port=8080] [--directory=build/web] [--isolated-config]',
      );
      exitCode = 64;
      return;
    }
  }
  final root = Directory(directory).absolute;
  if (!File('${root.path}/index.html').existsSync()) {
    throw StateError(
      'No index.html in ${root.path}; run dart run tool/build.dart.',
    );
  }
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  stdout.writeln('Static release host: http://localhost:${server.port}');
  await for (final request in server) {
    try {
      if (request.method != 'GET' && request.method != 'HEAD') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
        await request.response.close();
        continue;
      }
      final segments = request.uri.pathSegments;
      if (segments.any(
        (part) => part == '..' || part.startsWith('.') || part.contains('\\'),
      )) {
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
        continue;
      }
      final relative = segments.where((part) => part.isNotEmpty).join('/');
      var file = File(
        '${root.path}/${relative.isEmpty ? 'index.html' : relative}',
      );
      // Development convenience: read this one explicitly named local file.
      // It is never bundled into Flutter, cached, logged, or proxied upstream.
      final localConfig = File('config/local.json').absolute;
      final isLocalConfig =
          shouldUseProjectConfig(relative, isolatedConfig: isolatedConfig) &&
          localConfig.existsSync();
      if (isLocalConfig) file = localConfig;
      if (!file.existsSync()) {
        request.response.statusCode = HttpStatus.notFound;
        request.response.headers.set('Cache-Control', 'no-store');
        request.response.write('Static file not found.');
        await request.response.close();
        continue;
      }
      // Prevent symlinks from escaping the chosen static root.
      if (!isLocalConfig &&
          !file.resolveSymbolicLinksSync().startsWith(
            '${root.resolveSymbolicLinksSync()}/',
          )) {
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
        continue;
      }
      request.response.headers
        ..set('Content-Type', mimeType(file.path))
        ..set('Cache-Control', cacheControlFor(relative))
        ..set('X-Content-Type-Options', 'nosniff');
      // Open once before reading length. Atomic publication may rename a root
      // pointer between awaits; this descriptor keeps headers/body consistent.
      final descriptor = await file.open();
      try {
        final bytes = await descriptor.length();
        request.response.contentLength = bytes;
        if (request.method == 'GET') {
          await request.response.addStream(readOpenedFile(descriptor, bytes));
        }
      } finally {
        await descriptor.close();
      }
      await request.response.close();
    } catch (error) {
      stderr.writeln('Static host request failed: ${error.runtimeType}');
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {
        // The client may already have closed its socket.
      }
    }
  }
}

bool shouldUseProjectConfig(String relative, {required bool isolatedConfig}) =>
    !isolatedConfig && relative == 'config/local.json';

String mimeType(String path) {
  final extension = path.split('.').last.toLowerCase();
  return const {
        'html': 'text/html; charset=utf-8',
        'js': 'text/javascript; charset=utf-8',
        'json': 'application/json; charset=utf-8',
        'wasm': 'application/wasm',
        'png': 'image/png',
        'svg': 'image/svg+xml',
        'ico': 'image/x-icon',
        'woff': 'font/woff',
        'woff2': 'font/woff2',
        'ttf': 'font/ttf',
        'css': 'text/css; charset=utf-8',
        'txt': 'text/plain; charset=utf-8',
        'xml': 'application/xml; charset=utf-8',
      }[extension] ??
      'application/octet-stream';
}

String cacheControlFor(String path) => 'no-store';

Stream<List<int>> readOpenedFile(
  RandomAccessFile descriptor,
  int bytes,
) async* {
  var remaining = bytes;
  while (remaining > 0) {
    final chunk = await descriptor.read(remaining > 65536 ? 65536 : remaining);
    if (chunk.isEmpty) {
      throw const FileSystemException(
        'Static file was truncated while reading.',
      );
    }
    remaining -= chunk.length;
    yield chunk;
  }
}
