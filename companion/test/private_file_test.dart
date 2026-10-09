import 'dart:io';
import 'package:wfformcomp/private_file.dart';

Future<void> main() async {
  final parent = Directory('.local/companion-tests')
    ..createSync(recursive: true);
  final scratch = parent.createTempSync('private-');
  final token = File('${scratch.path}/private token.txt')
    ..writeAsStringSync('');
  try {
    await protectPrivateFile(token);
    await requirePrivateFile(token);
    token.writeAsStringSync('fixture secret');
    final ProcessResult widened;
    if (Platform.isWindows) {
      // SID is locale-independent. The changed permission must be refused.
      widened = await Process.run(
        '${Platform.environment['SystemRoot']}\\System32\\icacls.exe',
        [token.absolute.path, '/grant', '*S-1-1-0:R'],
      );
    } else {
      widened = await Process.run('chmod', ['644', token.absolute.path]);
    }
    if (widened.exitCode != 0) {
      throw StateError('Could not prepare unsafe permission fixture.');
    }
    var refused = false;
    try {
      await requirePrivateFile(token);
    } on FormatException {
      refused = true;
    }
    if (!refused) {
      throw StateError('A token accessible to other users was accepted.');
    }
    await protectPrivateFile(token);
    await requirePrivateFile(token);
    if (token.readAsStringSync() != 'fixture secret') {
      throw StateError('Permission update changed token contents.');
    }
    stdout.writeln(
      'PASS private credentials and refusal of widened ${Platform.operatingSystem} permissions',
    );
  } finally {
    scratch.deleteSync(recursive: true);
  }
}
