import 'dart:convert';
import 'dart:io';
import 'package:wfformcomp/wfformcomp.dart';

Future<void> main() async {
  final parent = Directory('.local/companion-tests')
    ..createSync(recursive: true);
  final scratch = parent.createTempSync('static-');
  final web = Directory('${scratch.path}/web')..createSync();
  File(
    '${web.path}/index.html',
  ).writeAsStringSync('<html>wfform fixture</html>');
  File('${web.path}/main.dart.js').writeAsStringSync('trusted-build');
  Directory('${web.path}/config').createSync();
  File(
    '${web.path}/config/local.json',
  ).writeAsStringSync('private-key-must-not-be-served');
  Link(
    '${web.path}/alias.json',
  ).createSync(File('${web.path}/config/local.json').absolute.path);
  File('${scratch.path}/private.txt').writeAsStringSync('outside-root');
  Link(
    '${web.path}/escape.txt',
  ).createSync(File('${scratch.path}/private.txt').absolute.path);
  final server = await CompanionServer.start(
    CompanionConfig.fromJson({
      'port': 0,
      'allowedOrigins': ['https://wfform.com'],
    }),
    '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN',
    webRoot: web,
  );
  final client = HttpClient();
  Future<({int status, String body, String? contentType})> get(
    String path, {
    String method = 'GET',
  }) async {
    final req = await client.openUrl(
      method,
      server.endpoint.replace(path: path),
    );
    final response = await req.close();
    return (
      status: response.statusCode,
      body: await utf8.decoder.bind(response).join(),
      contentType: response.headers.value('content-type'),
    );
  }

  try {
    final index = await get('/');
    if (index.status != 200 || !index.body.contains('wfform fixture')) {
      throw StateError('Optional static web root is not served.');
    }
    if ((await get('/conversation/new')).body != index.body) {
      throw StateError('SPA route missing.');
    }
    if ((await get('/main.dart.js')).contentType !=
        'text/javascript; charset=utf-8') {
      throw StateError('Wrong JS MIME type.');
    }
    if ((await get('/missing.js')).status != 404) {
      throw StateError('Missing asset received SPA HTML.');
    }
    if ((await get('/config/local.json')).status != 403) {
      throw StateError('Private local config leaked.');
    }
    if (Platform.isWindows) {
      for (final alias in ['/CONFIG/local.json', '/Config/LOCAL.JSON']) {
        if ((await get(alias)).status != 403) {
          throw StateError('Case-insensitive Windows config alias leaked.');
        }
      }
    }
    if ((await get('/alias.json')).status != 403) {
      throw StateError('A symlink exposed private local config.');
    }
    if ((await get('/escape.txt')).status != 403) {
      throw StateError('Symlink escaped web root.');
    }
    if ((await get('/.hidden')).status != 403) {
      throw StateError('Dotfile exposed.');
    }
    if ((await get('/index.html', method: 'HEAD')).body.isNotEmpty) {
      throw StateError('HEAD sent a body.');
    }
    stdout.writeln(
      'PASS optional static web build, SPA fallback, MIME/HEAD and config/symlink/dotfile guards',
    );
  } finally {
    client.close(force: true);
    await server.close();
    scratch.deleteSync(recursive: true);
  }
}
