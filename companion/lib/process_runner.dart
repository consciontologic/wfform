import 'dart:convert';
import 'dart:io';

/// Windows starts this inert child, assigns its job, then releases the gate.
/// Reading exactly one line synchronously leaves all subsequent MCP bytes on
/// the inherited stdin handle. No shell interprets command arguments.
Future<void> main() => runChild();

bool isWindowsNativeExecutable(String path) =>
    path.toLowerCase().endsWith('.exe');

Future<void> runChild() async {
  try {
    final bytes = <int>[];
    while (true) {
      final byte = stdin.readByteSync();
      if (byte == -1) return;
      if (byte == 10) break;
      bytes.add(byte);
      if (bytes.length > 1024 * 1024) throw const FormatException();
    }
    final message = jsonDecode(utf8.decode(bytes)) as Map;
    if (Platform.isWindows &&
        !isWindowsNativeExecutable(message['executable'] as String)) {
      throw const FormatException(
        'Windows tools must name an executable file.',
      );
    }
    final child = await Process.start(
      message['executable'] as String,
      (message['arguments'] as List).cast<String>(),
      workingDirectory: message['workingDirectory'] as String?,
      environment: (message['environment'] as Map).cast<String, String>(),
      includeParentEnvironment: false,
      runInShell: false,
      mode: ProcessStartMode.inheritStdio,
    );
    exitCode = await child.exitCode;
  } on Object {
    // Never echo a private path, environment, input or command argument.
    stderr.writeln('wfformcomp: configured child could not start.');
    exitCode = 71;
  }
}
