import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Windows starts this inert child, assigns its job, then releases the gate.
/// Windows process pipes require asynchronous I/O. The gate retains bytes after
/// its first line and relays them to the configured child without a shell.
Future<void> main() => runChild();

bool isWindowsNativeExecutable(String path) =>
    path.toLowerCase().endsWith('.exe');

Map<String, String> windowsChildEnvironment(Map<String, String> configured) {
  // Dart 3.10.9 process_win.cc gives an empty map only one UTF-16 NUL;
  // CreateProcessW requires two. A fixed marker makes the block valid without
  // inheriting host credentials or changing any explicitly configured value.
  return configured.isEmpty ? const {'WFFORMCOMP_CHILD': '1'} : configured;
}

Future<({Map<String, Object?> message, List<int> remaining})?>
readLaunchRequest(StreamIterator<List<int>> input) async {
  final bytes = BytesBuilder(copy: false);
  while (await input.moveNext()) {
    final chunk = input.current;
    final newline = chunk.indexOf(10);
    final length = newline < 0 ? chunk.length : newline;
    if (bytes.length + length > 1024 * 1024) {
      throw const FormatException('Launch gate exceeds its byte limit.');
    }
    bytes.add(newline < 0 ? chunk : chunk.sublist(0, newline));
    if (newline >= 0) {
      final message = jsonDecode(utf8.decode(bytes.takeBytes()));
      if (message is! Map<String, Object?>) {
        throw const FormatException('Launch gate must contain an object.');
      }
      return (message: message, remaining: chunk.sublist(newline + 1));
    }
  }
  if (bytes.isNotEmpty) {
    throw const FormatException('Launch gate ended before its newline.');
  }
  return null;
}

Future<void> _forwardInput(
  StreamIterator<List<int>> input,
  List<int> remaining,
  IOSink childInput,
) async {
  try {
    childInput.add(remaining);
    await childInput.flush();
    while (await input.moveNext()) {
      childInput.add(input.current);
      await childInput.flush();
    }
  } on IOException {
    // A configured program may finish without consuming all of its input.
  } finally {
    await input.cancel();
    try {
      await childInput.close();
    } on IOException {
      // Closing an already broken child pipe is normal after program exit.
    }
  }
}

Future<void> _forwardOutput(
  StreamIterator<List<int>> input,
  IOSink output,
) async {
  while (await input.moveNext()) {
    output.add(input.current);
    await output.flush();
  }
}

Future<Never> _fail(String diagnostic) async {
  try {
    stderr.writeln('wfformcomp: $diagnostic');
    await stderr.flush().timeout(const Duration(milliseconds: 100));
  } on IOException {
    // The caller may already have closed its diagnostic pipe.
  } on TimeoutException {
    // A blocked caller must not prevent the owning job from being closed.
  }
  // This function runs only in the isolated launch helper. Exiting releases
  // pending pipe writes; the parent then closes the owning Windows job.
  exit(71);
}

Future<void> runChild() async {
  final input = StreamIterator<List<int>>(stdin);
  StreamIterator<List<int>>? childOutput;
  StreamIterator<List<int>>? childErrors;
  var stage = 'launch gate';
  Process? child;
  try {
    final request = await readLaunchRequest(input);
    if (request == null) return;
    final message = request.message;
    if (Platform.isWindows &&
        !isWindowsNativeExecutable(message['executable'] as String)) {
      throw const FormatException(
        'Windows tools must name an executable file.',
      );
    }
    stage = 'configured child launch';
    final environment = (message['environment'] as Map).cast<String, String>();
    child = await Process.start(
      message['executable'] as String,
      (message['arguments'] as List).cast<String>(),
      workingDirectory: message['workingDirectory'] as String?,
      environment: Platform.isWindows
          ? windowsChildEnvironment(environment)
          : environment,
      includeParentEnvironment: false,
      runInShell: false,
    );
    stage = 'configured child streams';
    childOutput = StreamIterator(child.stdout);
    childErrors = StreamIterator(child.stderr);
    final output = Future.wait<void>([
      _forwardOutput(childOutput, stdout),
      _forwardOutput(childErrors, stderr),
    ], eagerError: true);
    final forwarding = Future.wait<void>([
      _forwardInput(input, request.remaining, child.stdin),
      output,
    ], eagerError: true);
    await Future.wait<void>([
      child.exitCode.then((code) async {
        exitCode = code;
        try {
          await (() async {
            await input.cancel();
            await forwarding;
          })().timeout(const Duration(milliseconds: 250));
        } on TimeoutException {
          // Descendants can retain output handles or block pending stdin
          // writes. Report incomplete capture instead of claiming success.
          await _fail(
            'child stream drain timed out; output may be incomplete.',
          );
        }
      }),
      forwarding,
    ], eagerError: true);
  } on Object catch (error) {
    child?.kill();
    // Never echo a private path, environment, input or command argument.
    final code = switch (error) {
      ProcessException() => error.errorCode,
      StdinException() => error.osError?.errorCode,
      FileSystemException() => error.osError?.errorCode,
      _ => null,
    };
    await _fail('$stage failed${code == null ? '' : ' (OS error $code)'}.');
  } finally {
    await input.cancel();
    await childOutput?.cancel();
    await childErrors?.cancel();
  }
}
