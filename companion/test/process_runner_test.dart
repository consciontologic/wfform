import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:wfformcomp/process_runner.dart' show isWindowsNativeExecutable;
import 'package:wfformcomp/process_group.dart';

Future<void> main() async {
  if (!isWindowsNativeExecutable(r'C:\Program Files\nodejs\node.EXE') ||
      [
        r'C:\tools\test.cmd',
        r'C:\tools\test.bat',
        r'C:\tools\test.exe ',
        r'C:\tools\test',
      ].any(isWindowsNativeExecutable)) {
    throw StateError('Windows batch wrappers could invoke an implicit shell.');
  }
  if (Platform.isWindows) {
    final parent = Directory('.local/companion-tests')
      ..createSync(recursive: true);
    final scratch = parent.createTempSync('batch-refusal-').absolute;
    final batch = File('${scratch.path}/fixture.cmd')
      ..writeAsStringSync('@echo off\r\nexit /b 0\r\n');
    final marker = File('${scratch.path}/must-not-exist');
    try {
      var refused = false;
      try {
        final process = await startProgram(batch.path, [
          'x&echo unsafe>"${marker.path}"',
        ], environment: {});
        stopProgram(process);
        await process.exitCode;
      } on ProcessException {
        refused = true;
      }
      if (!refused || marker.existsSync()) {
        throw StateError('Windows batch tool was dispatched through a shell.');
      }
    } finally {
      scratch.deleteSync(recursive: true);
    }
  }
  final process = await Process.start(Platform.resolvedExecutable, [
    'companion/lib/process_runner.dart',
  ]);
  final output = process.stdout.transform(utf8.decoder).join();
  final errors = process.stderr.transform(utf8.decoder).join();
  var ended = false;
  unawaited(process.exitCode.then((_) => ended = true));
  await Future<void>.delayed(const Duration(milliseconds: 200));
  if (ended) {
    throw StateError('Runner did not wait for its job assignment gate.');
  }
  process.stdin.writeln(
    jsonEncode({
      'executable': Platform.resolvedExecutable,
      'arguments': [
        File('companion/test/command_fixture.dart').absolute.path,
        'echo',
        r'a b & echo DO_NOT_EXECUTE; $(command)',
      ],
      'environment': <String, String>{},
    }),
  );
  await process.stdin.close();
  if (await process.exitCode != 0 ||
      await errors != '' ||
      (jsonDecode(await output) as List).single !=
          r'a b & echo DO_NOT_EXECUTE; $(command)') {
    throw StateError('Runner changed argv, used a shell or lost output.');
  }
  stdout.writeln('PASS child launch gate and literal argv/output forwarding');
  final mcp = await Process.start(Platform.resolvedExecutable, [
    'companion/lib/process_runner.dart',
  ]);
  final mcpOutput = mcp.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .toList();
  final mcpErrors = mcp.stderr.transform(utf8.decoder).join();
  // Deliberately queue all bytes together: gate consumption must not swallow
  // the first actual protocol requests from the same pipe read.
  mcp.stdin.write(
    '${jsonEncode({
      'executable': Platform.resolvedExecutable,
      'arguments': [File('companion/test/stdio_fixture.dart').absolute.path],
      'environment': <String, String>{},
    })}\n${jsonEncode({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize'})}\n${jsonEncode({'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'})}\n',
  );
  await mcp.stdin.close();
  final code = await mcp.exitCode.timeout(const Duration(seconds: 10));
  final replies = (await mcpOutput)
      .map((line) => jsonDecode(line) as Map)
      .toList();
  if (code != 0 ||
      await mcpErrors != '' ||
      replies.length != 2 ||
      replies[0]['id'] != 1 ||
      replies[1]['id'] != 2 ||
      (replies[1]['result']['tools'] as List).length != 2) {
    throw StateError('Runner consumed or changed queued MCP protocol bytes.');
  }
  stdout.writeln('PASS launch gate preserves queued MCP stdin messages');
}
