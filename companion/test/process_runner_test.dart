import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:wfformcomp/process_runner.dart' show isWindowsNativeExecutable;
import 'package:wfformcomp/process_group.dart';

Future<void> main(List<String> args) async {
  if (args.contains('--environment-child')) {
    stdout.write(
      jsonEncode({
        'parent': Platform.environment['WFFORMCOMP_TEST_PARENT'],
        'allowed': Platform.environment['WFFORMCOMP_TEST_ALLOWED'],
      }),
    );
    return;
  }
  if (args.contains('--environment-parent')) {
    final child = await startProgram(
      Platform.resolvedExecutable,
      [Platform.script.toFilePath(), '--environment-child'],
      environment: {'WFFORMCOMP_TEST_ALLOWED': 'explicit'},
    );
    final output = utf8.decoder.bind(child.stdout).join();
    final errors = utf8.decoder.bind(child.stderr).join();
    try {
      await child.stdin.close();
      final code = await child.exitCode.timeout(const Duration(seconds: 10));
      if (code != 0 || await errors != '') {
        throw StateError('Environment fixture could not run: exit $code.');
      }
      stdout.write(await output);
    } finally {
      stopProgram(child);
    }
    return;
  }
  if (!isWindowsNativeExecutable(r'C:\Program Files\nodejs\node.EXE') ||
      [
        r'C:\tools\test.cmd',
        r'C:\tools\test.bat',
        r'C:\tools\test.exe ',
        r'C:\tools\test',
      ].any(isWindowsNativeExecutable)) {
    throw StateError('Windows batch wrappers could invoke an implicit shell.');
  }
  for (final runtime in [
    r'C:\sdk\bin\dart.exe',
    r'C:\sdk\bin\dartvm.exe',
    r'C:/sdk/bin/DARTVM.EXE',
    r'\\server\sdk\DART.EXE',
  ]) {
    if (!isWindowsDartSourceRuntime(runtime)) {
      throw StateError('Windows source runtime was not recognized.');
    }
  }
  for (final compiled in [
    r'C:\tools\wfformcomp.exe',
    r'C:\tools\otherdartvm.exe',
    r'C:\tools\dartvm.exe.bat',
    r'C:\tools\dartvm.exe ',
  ]) {
    if (isWindowsDartSourceRuntime(compiled)) {
      throw StateError('A compiled companion or wrapper was treated as Dart.');
    }
  }
  final environmentProbe = await Process.run(
    Platform.resolvedExecutable,
    [Platform.script.toFilePath(), '--environment-parent'],
    environment: {'WFFORMCOMP_TEST_PARENT': 'must-not-reach-user-program'},
    runInShell: false,
  );
  if (environmentProbe.exitCode != 0 || environmentProbe.stderr != '') {
    throw StateError(
      'Environment isolation probe failed: ${environmentProbe.exitCode}.',
    );
  }
  final environmentResult =
      jsonDecode(environmentProbe.stdout as String) as Map;
  if (environmentResult['parent'] != null ||
      environmentResult['allowed'] != 'explicit') {
    throw StateError('Configured program inherited its parent environment.');
  }
  stdout.writeln(
    'PASS source runtime selection and explicit child environment',
  );
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
