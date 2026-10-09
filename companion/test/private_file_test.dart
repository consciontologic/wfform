import 'dart:io';
import 'package:wfformcomp/private_file.dart';

Future<void> main() async {
  final diagnostic = windowsAclFailureSummary(
    12,
    'WFFORM_ACL_FAILURE:12:-2147024891\r\n',
  );
  if (diagnostic != 'apply ACL; exit 12; HRESULT -2147024891') {
    throw StateError('ACL diagnostic lost its safe failure stage or code.');
  }
  if (windowsAclFailureSummary(12, 'WFFORM_ACL_FAILURE:12:-2147024891:5') !=
      'apply ACL; exit 12; HRESULT -2147024891; OS error 5') {
    throw StateError('ACL diagnostic lost its numeric native error.');
  }
  for (final output in [
    'private path and fixture secret',
    'WFFORM_ACL_FAILURE:12:-2147024891\nprivate path and fixture secret',
    'WFFORM_ACL_FAILURE:99:-2147024891',
    'WFFORM_ACL_FAILURE:12:9999999999',
    'WFFORM_ACL_FAILURE:12:-2147024891:9999999999',
    'WFFORM_ACL_FAILURE:13:-2147024891',
  ]) {
    if (windowsAclFailureSummary(12, output) != 'apply ACL; exit 12') {
      throw StateError('ACL diagnostic exposed untrusted process output.');
    }
  }
  if (windowsAclFailureSummary(32, '') != 'inherited access rule; exit 32') {
    throw StateError('ACL policy rejection lost its fixed reason.');
  }
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
