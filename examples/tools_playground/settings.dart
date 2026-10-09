import 'dart:convert';
import 'dart:io';

/// Creates a private, editable example configuration once, without overwriting
/// earlier settings or pairing. Paths come from the checkout, never the model.
Future<({File config, File token})> preparePlayground(
  Directory root,
  Directory private, {
  int port = 8766,
}) async {
  final config = File.fromUri(private.uri.resolve('config.json'));
  final token = File.fromUri(private.uri.resolve('pairing-token'));
  final configExists = FileSystemEntity.typeSync(
    config.path,
    followLinks: false,
  );
  final tokenExists = FileSystemEntity.typeSync(token.path, followLinks: false);
  if (configExists != FileSystemEntityType.notFound ||
      tokenExists != FileSystemEntityType.notFound) {
    if (configExists != FileSystemEntityType.file ||
        tokenExists != FileSystemEntityType.file) {
      throw const FormatException(
        'Expected both ordinary config.json and pairing-token files. '
        'Use a fresh private folder or restore the missing file.',
      );
    }
    // The companion validates private token permissions again when it starts.
    return (config: config, token: token);
  }
  if (port < 0 || port > 65535) throw ArgumentError.value(port, 'port');
  final directory = Directory.fromUri(
    root.absolute.uri.resolve('examples/tools_playground/'),
  );
  for (final name in ['server.dart', 'sales_report.dart']) {
    if (!File.fromUri(directory.uri.resolve(name)).existsSync()) {
      throw const FormatException('Run this example from a complete checkout.');
    }
  }
  final configuration = {
    'port': port,
    'allowedOrigins': [
      'https://wfform.com',
      'http://localhost:8765',
      'http://127.0.0.1:8765',
      'http://localhost:8080',
      'http://127.0.0.1:8080',
    ],
    'tools': [
      {
        'name': 'sales_report',
        'description':
            'Run the fixed local Dart program to summarize the '
            'bundled example sales CSV. Reads sample data only.',
        'executable': Platform.resolvedExecutable,
        'arguments': [
          File.fromUri(directory.uri.resolve('sales_report.dart')).path,
        ],
        'workingDirectory': root.absolute.path,
        'timeoutMs': 15000,
        'maxOutputBytes': 8192,
        'inputSchema': {
          'type': 'object',
          'properties': <String, Object?>{},
          'additionalProperties': false,
        },
      },
    ],
    'mcpServers': [
      {
        'name': 'playground',
        'executable': Platform.resolvedExecutable,
        'arguments': [File.fromUri(directory.uri.resolve('server.dart')).path],
        'workingDirectory': root.absolute.path,
        'allowedTools': ['add_numbers', 'read_sample'],
        'timeoutMs': 15000,
      },
    ],
  };
  // Use the shipped CLI's private setup, including Windows ACLs, rather than
  // duplicate credential handling in an example or print a token to stdout.
  final initialized = await Process.run(Platform.resolvedExecutable, [
    'run',
    File.fromUri(
      root.absolute.uri.resolve('companion/bin/wfformcomp.dart'),
    ).path,
    'init',
    '--config',
    config.path,
    '--token-file',
    token.path,
  ], workingDirectory: root.absolute.path);
  if (initialized.exitCode != 0) {
    throw const FormatException(
      'Companion private setup failed. Check that '
      'the private folder is writable and its files do not already exist.',
    );
  }
  config.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(configuration)}\n',
    flush: true,
  );
  return (config: config, token: token);
}
