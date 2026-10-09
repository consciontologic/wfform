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

String windowsAclFailureSummary(int exitCode, String standardError) {
  const stages = {
    10: 'identify user',
    11: 'construct ACL',
    12: 'apply ACL',
    13: 'read ACL',
    14: 'inspect ACL',
    30: 'unprotected ACL',
    31: 'owner mismatch',
    32: 'inherited access rule',
    33: 'another identity has access',
    34: 'non-allow access rule',
    35: 'missing user access rule',
  };
  final summary =
      '${stages[exitCode] ?? 'Windows security tool'}; exit $exitCode';
  final match = RegExp(
    r'^WFFORM_ACL_FAILURE:(10|11|12|13|14):(-?\d{1,10})(?::(\d{1,10}))?\r?\n?$',
  ).firstMatch(standardError);
  if (match == null || int.parse(match[1]!) != exitCode) return summary;
  final hresult = int.parse(match[2]!);
  final nativeCode = match[3] == null ? null : int.parse(match[3]!);
  if (hresult < -2147483648 ||
      hresult > 2147483647 ||
      (nativeCode != null && nativeCode > 2147483647)) {
    return summary;
  }
  return '$summary; HRESULT $hresult'
      '${nativeCode == null ? '' : '; OS error $nativeCode'}';
}

Future<void> _windowsFileSecurity(File file, {required bool protect}) async {
  // The encoded script is fixed. A user path goes through an environment value
  // and .NET file APIs, never PowerShell interpolation or command flags.
  const script = r'''
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$stage = 10
try {
  $path = $env:WFFORM_PRIVATE_FILE
  $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
  if ($env:WFFORM_PROTECT_FILE -eq '1') {
    $stage = 11
    $acl = [System.Security.AccessControl.FileSecurity]::new()
    $acl.SetOwner($user)
    $acl.SetAccessRuleProtection($true, $false)
    $rule = [System.Security.AccessControl.FileSystemAccessRule]::new($user, 'FullControl', 'Allow')
    $acl.AddAccessRule($rule)
    $stage = 12
    # Persist only the owner and DACL changed above. Set-Acl rewrites every
    # section, including group/audit sections this fresh descriptor never set.
    [System.IO.File]::SetAccessControl($path, $acl)
  }
  $stage = 13
  # A PowerShell 7 -> Dart -> Windows PowerShell launch inherits incompatible
  # PSModulePath entries. Use .NET directly, without any module autoloading.
  $sections = [System.Security.AccessControl.AccessControlSections]::Access -bor [System.Security.AccessControl.AccessControlSections]::Owner
  $acl = [System.IO.File]::GetAccessControl($path, $sections)
  $stage = 14
  if (!$acl.AreAccessRulesProtected) { exit 30 }
  if ($acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value -ne $user.Value) { exit 31 }
  $rules = $acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])
  $allowed = $false
  foreach ($rule in $rules) {
    if ($rule.IsInherited) { exit 32 }
    if ($rule.IdentityReference.Value -ne $user.Value) { exit 33 }
    if ($rule.AccessControlType -ne 'Allow') { exit 34 }
    $allowed = $true
  }
  if (!$allowed) { exit 35 }
} catch {
  $failure = $_.Exception.GetBaseException()
  $diagnostic = 'WFFORM_ACL_FAILURE:' + $stage + ':' + [int]$failure.HResult
  if ($failure -is [System.ComponentModel.Win32Exception]) {
    $diagnostic += ':' + [int]$failure.NativeErrorCode
  }
  [Console]::Error.WriteLine($diagnostic)
  exit $stage
}
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
    throw FormatException(
      'Pairing token needs a protected current-user-only Windows file ACL '
      '(${windowsAclFailureSummary(result.exitCode, result.stderr as String)}).',
    );
  }
}
