import 'dart:convert';
import 'dart:io';

/// Checks prospective Git files and the index without printing secret values.
/// The local credential is optional; known OpenRouter key shapes are checked
/// even on clean CI checkouts that have no local configuration.
Future<List<String>> checkRepository(Directory root) async {
  final issues = <String>[];
  Future<ProcessResult> git(List<String> args, {bool binary = false}) =>
      Process.run(
        'git',
        args,
        workingDirectory: root.path,
        stdoutEncoding: binary ? null : utf8,
      );
  final inventory = await git([
    'ls-files',
    '--cached',
    '--others',
    '--exclude-standard',
    '-z',
  ]);
  if (inventory.exitCode != 0) {
    return ['Cannot inspect Git files. Run this check from the project root.'];
  }
  final candidates = (inventory.stdout as String)
      .split('\u0000')
      .where((e) => e.isNotEmpty)
      .toSet();
  final indexed = await git(['ls-files', '--cached', '-z']);
  if (indexed.exitCode != 0) return ['Cannot inspect the Git index.'];
  final staged = (indexed.stdout as String)
      .split('\u0000')
      .where((e) => e.isNotEmpty)
      .toSet();
  const ignoredPaths = [
    'config/local.json',
    'build/check-secret.json',
    '.local/check-secret.json',
    'work/check-secret.json',
    'outputs/check-secret.json',
  ];
  for (final path in ignoredPaths) {
    final result = await git(['check-ignore', '--no-index', '-q', path]);
    if (result.exitCode != 0) issues.add('Missing ignore protection: $path');
  }
  for (final path in staged) {
    if (path == 'config/local.json' ||
        path.startsWith('build/') ||
        path.startsWith('.local/') ||
        path.startsWith('work/') ||
        path.startsWith('outputs/')) {
      issues.add('Private or generated path is staged: $path');
    }
  }
  String? localKey;
  final local = File('${root.path}/config/local.json');
  if (local.existsSync()) {
    try {
      final decoded = jsonDecode(local.readAsStringSync());
      if (decoded is Map && decoded['apiKey'] is String) {
        final key = (decoded['apiKey'] as String).trim();
        if (key.length >= 8) localKey = key;
      }
    } on Object {
      issues.add('Cannot validate config/local.json; check its JSON locally.');
    }
  }
  final keyPattern = RegExp(r'sk-or-v1-[a-fA-F0-9]{64}');
  bool hasCredential(List<int> bytes) {
    final value = utf8.decode(bytes, allowMalformed: true);
    return keyPattern.hasMatch(value) ||
        (localKey != null && value.contains(localKey));
  }

  for (final path in candidates) {
    final file = File('${root.path}/$path');
    if (!file.existsSync()) continue; // A tracked deletion is checked below.
    if (file.lengthSync() > 20000000) {
      issues.add('File exceeds the bounded credential scan limit: $path');
    } else if (hasCredential(file.readAsBytesSync())) {
      issues.add('Possible API credential in working file: $path');
    }
  }
  for (final path in staged) {
    final result = await git(['show', ':$path'], binary: true);
    if (result.exitCode != 0) {
      issues.add('Cannot inspect staged file: $path');
    } else if (hasCredential(result.stdout as List<int>)) {
      issues.add('Possible API credential in staged file: $path');
    }
  }
  return issues;
}

Future<void> main() async {
  final issues = await checkRepository(Directory.current);
  if (issues.isEmpty) {
    stdout.writeln(
      'Repository check passed: local configuration is ignored; '
      'no API keys found in prospective or staged files.',
    );
  } else {
    for (final issue in issues) {
      stderr.writeln(issue);
    }
    exitCode = 1;
  }
}
