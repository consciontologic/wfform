import 'dart:convert';
import 'dart:io';
import 'package:wfformcomp/wfformcomp.dart';
import 'package:wfformcomp/process_runner.dart' show runChild;
import 'package:wfformcomp/private_file.dart';

Future<void> main(List<String> args) async {
  if (Platform.isWindows &&
      args.length == 1 &&
      args.single == '--internal-child') {
    await runChild();
    return;
  }
  if (args.isEmpty || args.contains('--help')) {
    stdout.writeln(
      '''wfformcomp $companionVersion — optional local tools for wfform
Usage:
  wfformcomp init --config PATH --token-file PATH
  wfformcomp serve --config PATH --token-file PATH [--web-root PATH]
  wfformcomp --version

init writes an empty tool configuration and a private random pairing token.
Review allowedOrigins and configure fixed program tools before serving.
serve binds only 127.0.0.1. Pair /mcp in wfform using the token file contents.
The pairing token is never printed and is never embedded in the binary.''',
    );
    return;
  }
  if (args.length == 1 && args.single == '--version') {
    stdout.writeln(companionVersion);
    return;
  }
  try {
    if (![5, 7].contains(args.length) ||
        !['init', 'serve'].contains(args.first) ||
        args[1] != '--config' ||
        args[3] != '--token-file' ||
        (args.length == 7 &&
            (args.first != 'serve' || args[5] != '--web-root'))) {
      throw const FormatException('Use --help for command syntax.');
    }
    final configFile = File(args[2]);
    final tokenFile = File(args[4]);
    if (configFile.absolute.path == tokenFile.absolute.path) {
      throw const FormatException('Config and token paths must differ.');
    }
    if (args.first == 'init') {
      if (FileSystemEntity.typeSync(configFile.path, followLinks: false) !=
              FileSystemEntityType.notFound ||
          FileSystemEntity.typeSync(tokenFile.path, followLinks: false) !=
              FileSystemEntityType.notFound) {
        throw const FormatException(
          'Refusing to overwrite an existing config or token.',
        );
      }
      configFile.parent.createSync(recursive: true);
      tokenFile.parent.createSync(recursive: true);
      tokenFile.writeAsStringSync('', flush: true);
      try {
        await protectPrivateFile(tokenFile);
      } on Object {
        tokenFile.deleteSync();
        rethrow;
      }
      tokenFile.writeAsStringSync('${generateToken()}\n', flush: true);
      configFile.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert({
          'port': 8765,
          'allowedOrigins': ['https://wfform.com'],
          'tools': [],
        })}\n',
        flush: true,
      );
      stdout.writeln(
        'Created config and pairing token. Edit the config before starting.',
      );
      return;
    }
    await requirePrivateFile(tokenFile);
    final config = CompanionConfig.fromJson(
      object(jsonDecode(configFile.readAsStringSync()), 'config'),
    );
    final token = tokenFile.readAsStringSync().trim();
    final server = await CompanionServer.start(
      config,
      token,
      webRoot: args.length == 7 ? Directory(args[6]) : null,
    );
    stdout.writeln(
      'wfformcomp $companionVersion listening ${server.endpoint} (${server.toolCount} configured tools)',
    );
    if (args.length == 7) {
      stdout.writeln('Open ${server.endpoint.origin}/ for the local web app.');
    }
    Future<void> stop(ProcessSignal _) async {
      await server.close();
      exit(0);
    }

    ProcessSignal.sigint.watch().listen(stop);
    if (!Platform.isWindows) ProcessSignal.sigterm.watch().listen(stop);
  } on Object catch (error) {
    // Configuration errors may contain private paths; do not echo the data.
    stderr.writeln(
      error is FormatException
          ? 'wfformcomp: ${error.message}'
          : 'wfformcomp: could not start. Check config, token file and port.',
    );
    exitCode = 64;
  }
}
