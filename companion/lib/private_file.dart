import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Restrict a newly created empty file before writing credentials to it.
Future<void> protectPrivateFile(File file) async {
  if (Platform.isWindows) {
    await _windowsFileSecurity(file, protect: true);
  } else {
    final result = await Process.run('chmod', [
      '600',
      file.absolute.path,
    ], runInShell: false);
    if (result.exitCode != 0) {
      throw const FormatException('Could not protect the private file.');
    }
  }
}

Future<void> requirePrivateFile(File file) async {
  if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw const FormatException(
      'Pairing token must be an ordinary private file.',
    );
  }
  if (Platform.isWindows) {
    await _windowsFileSecurity(file, protect: false);
  } else if ((file.statSync().mode & 0x3f) != 0) {
    throw const FormatException(
      'Pairing token file must be private (chmod 600).',
    );
  }
}

Future<void> _windowsFileSecurity(File file, {required bool protect}) async {
  // The encoded script is fixed. A user path goes through an environment value
  // and LiteralPath, never PowerShell source interpolation or command flags.
  const script = r'''
$ErrorActionPreference = 'Stop'
try {
  $path = $env:WFFORM_PRIVATE_FILE
  $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
  if ($env:WFFORM_PROTECT_FILE -eq '1') {
    $acl = New-Object System.Security.AccessControl.FileSecurity
    $acl.SetOwner($user)
    $acl.SetAccessRuleProtection($true, $false)
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($user, 'FullControl', 'Allow')
    $acl.AddAccessRule($rule)
    Set-Acl -LiteralPath $path -AclObject $acl
  }
  $acl = Get-Acl -LiteralPath $path
  if (!$acl.AreAccessRulesProtected -or $acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value -ne $user.Value) { exit 2 }
  $rules = $acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])
  $allowed = $false
  foreach ($rule in $rules) {
    if ($rule.IsInherited -or $rule.IdentityReference.Value -ne $user.Value -or $rule.AccessControlType -ne 'Allow') { exit 2 }
    $allowed = $true
  }
  if (!$allowed) { exit 2 }
} catch { exit 2 }
''';
  final units = script.codeUnits;
  final bytes = ByteData(units.length * 2);
  for (var i = 0; i < units.length; i++) {
    bytes.setUint16(i * 2, units[i], Endian.little);
  }
  final systemRoot = Platform.environment['SystemRoot'];
  if (systemRoot == null || !Directory(systemRoot).isAbsolute) {
    throw const FormatException('Cannot locate Windows file security tools.');
  }
  final result = await Process.run(
    '$systemRoot\\System32\\WindowsPowerShell\\v1.0\\powershell.exe',
    [
      '-NoProfile',
      '-NonInteractive',
      '-EncodedCommand',
      base64Encode(bytes.buffer.asUint8List()),
    ],
    environment: {
      'WFFORM_PRIVATE_FILE': file.absolute.path,
      'WFFORM_PROTECT_FILE': protect ? '1' : '0',
    },
    runInShell: false,
  );
  if (result.exitCode != 0) {
    throw const FormatException(
      'Pairing token needs a protected current-user-only Windows file ACL.',
    );
  }
}
