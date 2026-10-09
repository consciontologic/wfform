import 'dart:io';
import 'package:wfformcomp/private_file.dart';

Future<void> main(List<String> arguments) async {
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
  // The .NET write/read must treat the path literally, including characters
  // significant to PowerShell and wildcards.
  const tokenName = r"private [token] $ ; '.txt";
  final token = File('${scratch.path}/$tokenName')..writeAsStringSync('');
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
    if (Platform.isWindows && arguments.isEmpty) {
      // PowerShell 7 -> Dart -> Windows PowerShell retains PSModulePath, unlike
      // a direct shell launch. An incompatible shared module must not affect
      // the helper's .NET ACL operations or execute any module code.
      final moduleRoot = Directory('${scratch.path}/modules');
      final incompatible = Directory(
        '${moduleRoot.path}/Microsoft.PowerShell.Security',
      )..createSync(recursive: true);
      File(
        '${incompatible.path}/Microsoft.PowerShell.Security.psd1',
      ).writeAsStringSync('''
@{
  RootModule = 'Microsoft.PowerShell.Security.psm1'
  ModuleVersion = '7.0.0'
  PowerShellVersion = '7.0'
  FunctionsToExport = @('Get-Acl', 'Set-Acl')
}
''');
      File(
        '${incompatible.path}/Microsoft.PowerShell.Security.psm1',
      ).writeAsStringSync("throw 'The ACL helper loaded a fixture module.'");
      final isolated = await Process.run(
        Platform.resolvedExecutable,
        [Platform.script.toFilePath(), '--module-isolation'],
        environment: {
          for (final entry in Platform.environment.entries)
            if (entry.key.toUpperCase() != 'PSMODULEPATH')
              entry.key: entry.value,
          'PSModulePath': moduleRoot.absolute.path,
        },
        includeParentEnvironment: false,
        runInShell: false,
      );
      if (isolated.exitCode != 0) {
        throw StateError(
          'Private-file protection depended on inherited PowerShell modules '
          '(exit ${isolated.exitCode}).',
        );
      }
      stdout.writeln('PASS Windows ACL operations ignore incompatible modules');
    }
    stdout.writeln(
      'PASS private credentials and refusal of widened ${Platform.operatingSystem} permissions',
    );
  } finally {
    scratch.deleteSync(recursive: true);
  }
}
