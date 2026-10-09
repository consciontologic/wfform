import 'dart:io';
import 'settings.dart';

Future<void> main(List<String> args) async {
  if (args.isNotEmpty) {
    stderr.writeln('Usage: dart run examples/tools_playground/start.dart');
    exitCode = 64;
    return;
  }
  final root = Directory.fromUri(Platform.script.resolve('../../'));
  final private = Directory.fromUri(
    root.uri.resolve('.local/tools-playground/'),
  );
  try {
    final settings = await preparePlayground(root, private);
    stdout.writeln('Playground settings: ${settings.config.path}');
    stdout.writeln(
      'Open ${settings.token.path} in your editor for the pairing '
      'token. Paste it only into wfform’s bearer/pairing token field.',
    );
    stdout.writeln(
      'In desktop wfform: Tools → Add a connection. '
      'Use the endpoint printed below. Keep this terminal open.',
    );
    final process = await Process.start(
      Platform.resolvedExecutable,
      [
        'run',
        File.fromUri(root.uri.resolve('companion/bin/wfformcomp.dart')).path,
        'serve',
        '--config',
        settings.config.path,
        '--token-file',
        settings.token.path,
      ],
      workingDirectory: root.path,
      mode: ProcessStartMode.inheritStdio,
    );
    exitCode = await process.exitCode;
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
  } on Object {
    stderr.writeln(
      'Could not start the playground. Check your Dart SDK, '
      'checkout permissions and private settings.',
    );
    exitCode = 64;
  }
}
