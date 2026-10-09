import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:wfformcomp/process_runner.dart'
    show isWindowsNativeExecutable, readLaunchRequest, windowsChildEnvironment;
import 'package:wfformcomp/process_group.dart';

Future<void> main(List<String> args) async {
  if (args.contains('--orphan-child')) {
    await Future<void>.delayed(const Duration(seconds: 20));
    return;
  }
  if (args.contains('--orphan-parent')) {
    final descendant = await Process.start(Platform.resolvedExecutable, [
      Platform.script.toFilePath(),
      '--orphan-child',
    ], mode: ProcessStartMode.inheritStdio);
    stdout.writeln(descendant.pid);
    await stdout.flush();
    exit(0);
  }
  if (args.contains('--stdio-child')) {
    await stdout.addStream(stdin);
    return;
  }
  if (args.contains('--environment-child')) {
    stdout.write(
      jsonEncode({
        'parent': Platform.environment['WFFORMCOMP_TEST_PARENT'],
        'allowed': Platform.environment['WFFORMCOMP_TEST_ALLOWED'],
        'compatibility': Platform.environment['WFFORMCOMP_CHILD'],
      }),
    );
    return;
  }
  if (args.contains('--environment-parent')) {
    final child = await startProgram(
      Platform.resolvedExecutable,
      [Platform.script.toFilePath(), '--environment-child'],
      environment: args.contains('--empty-environment')
          ? {}
          : {'WFFORMCOMP_TEST_ALLOWED': 'explicit'},
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
  final packets = StreamController<List<int>>();
  final input = StreamIterator(packets.stream);
  final gate = readLaunchRequest(input);
  packets.add(utf8.encode('{"arguments":["caf'));
  packets.add([0xc3]);
  packets.add([0xa9, ...utf8.encode('"]}\r\nfirst request\n')]);
  packets.add(utf8.encode('second request\n'));
  unawaited(packets.close());
  final request = await gate;
  if (request == null ||
      (request.message['arguments'] as List).single != 'café' ||
      utf8.decode(request.remaining) != 'first request\n' ||
      !await input.moveNext() ||
      utf8.decode(input.current) != 'second request\n' ||
      await input.moveNext()) {
    throw StateError('Async launch gate changed fragmented or queued bytes.');
  }
  await input.cancel();
  for (final bytes in [
    utf8.encode('{"unfinished":'),
    List<int>.filled(1024 * 1024 + 1, 32),
  ]) {
    final invalid = StreamIterator(Stream.value(bytes));
    var refused = false;
    try {
      await readLaunchRequest(invalid);
    } on FormatException {
      refused = true;
    } finally {
      await invalid.cancel();
    }
    if (!refused) throw StateError('Incomplete or oversized gate accepted.');
  }
  stdout.writeln('PASS async gate framing, byte preservation and size limit');
  final emptyEnvironment = <String, String>{};
  final windowsEmpty = windowsChildEnvironment(emptyEnvironment);
  if (emptyEnvironment.isNotEmpty ||
      windowsEmpty.length != 1 ||
      windowsEmpty['WFFORMCOMP_CHILD'] != '1') {
    throw StateError('Windows empty environment needs only a fixed marker.');
  }
  const configuredEnvironment = {
    'WFFORMCOMP_CHILD': 'user-configured',
    'WFFORMCOMP_TEST_ALLOWED': 'explicit',
  };
  if (!identical(
    windowsChildEnvironment(configuredEnvironment),
    configuredEnvironment,
  )) {
    throw StateError('Nonempty configured environment was changed.');
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
    environment: {
      'WFFORMCOMP_TEST_PARENT': 'must-not-reach-user-program',
      'WFFORMCOMP_CHILD': 'parent-marker-must-not-reach-user-program',
    },
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
      environmentResult['allowed'] != 'explicit' ||
      environmentResult['compatibility'] != null) {
    throw StateError('Configured program inherited its parent environment.');
  }
  final emptyProbe = await Process.run(
    Platform.resolvedExecutable,
    [
      Platform.script.toFilePath(),
      '--environment-parent',
      '--empty-environment',
    ],
    environment: {
      'WFFORMCOMP_TEST_PARENT': 'must-not-reach-user-program',
      'WFFORMCOMP_CHILD': 'parent-marker-must-not-reach-user-program',
    },
    runInShell: false,
  );
  if (emptyProbe.exitCode != 0 || emptyProbe.stderr != '') {
    throw StateError('Empty environment probe failed: ${emptyProbe.exitCode}.');
  }
  final emptyResult = jsonDecode(emptyProbe.stdout as String) as Map;
  if (emptyResult['parent'] != null ||
      emptyResult['allowed'] != null ||
      emptyResult['compatibility'] != (Platform.isWindows ? '1' : null)) {
    throw StateError(
      'Empty environment inherited private or unexpected values.',
    );
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
  await process.stdin.flush();
  final echoCode = await process.exitCode.timeout(const Duration(seconds: 10));
  await process.stdin.close();
  if (echoCode != 0 ||
      await errors != '' ||
      (jsonDecode(await output) as List).single !=
          r'a b & echo DO_NOT_EXECUTE; $(command)') {
    throw StateError('Runner changed argv, used a shell or lost output.');
  }
  stdout.writeln(
    'PASS child launch gate, literal argv/output and exit with open parent stdin',
  );
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

  final orphan = await startProgram(Platform.resolvedExecutable, [
    File('companion/lib/process_runner.dart').absolute.path,
  ], environment: {});
  final orphanPid = Completer<int>();
  final orphanOutput = utf8.decoder
      .bind(orphan.stdout)
      .transform(const LineSplitter())
      .listen((line) => orphanPid.complete(int.parse(line)))
      .asFuture<void>();
  final orphanErrors = utf8.decoder.bind(orphan.stderr).join();
  int? descendantPid;
  try {
    orphan.stdin.writeln(
      jsonEncode({
        'executable': Platform.resolvedExecutable,
        'arguments': [Platform.script.toFilePath(), '--orphan-parent'],
        'environment': <String, String>{},
      }),
    );
    // The exited child's descendant retains stdin without reading it. Pending
    // writes must not keep the helper alive and delay owning-job cleanup.
    orphan.stdin.add(List<int>.filled(256 * 1024, 65));
    final closedInput = (() async {
      try {
        await orphan.stdin.close();
      } on IOException {
        // The bounded helper exit closes this intentionally unread input.
      }
    })();
    descendantPid = await orphanPid.future.timeout(const Duration(seconds: 10));
    final orphanCode = await orphan.exitCode.timeout(
      const Duration(seconds: 3),
    );
    if (!Platform.isWindows) stopProgram(orphan);
    await orphanOutput;
    await closedInput;
    if (orphanCode != 71 ||
        !(await orphanErrors).contains(
          'child stream drain timed out; output may be incomplete.',
        )) {
      throw StateError('Exited child with inherited descendant pipes failed.');
    }
    if (Platform.isWindows) {
      final tasklist = await Process.run(
        '${Platform.environment['SystemRoot']}\\System32\\tasklist.exe',
        ['/FI', 'PID eq $descendantPid', '/FO', 'CSV', '/NH'],
      );
      if (tasklist.exitCode != 0 ||
          tasklist.stdout.toString().contains(',"$descendantPid",')) {
        throw StateError(
          'A descendant survived automatic Windows job cleanup.',
        );
      }
    }
  } finally {
    stopProgram(orphan);
    if (descendantPid != null) {
      Process.killPid(descendantPid, ProcessSignal.sigkill);
    }
  }
  stdout.writeln(
    'PASS direct child exit drains promptly despite descendant pipes',
  );

  final relay = await Process.start(Platform.resolvedExecutable, [
    'companion/lib/process_runner.dart',
  ]);
  final firstReply = Completer<void>();
  final relayed = <int>[];
  final relayErrors = utf8.decoder.bind(relay.stderr).join();
  final relayOutput = relay.stdout.listen((chunk) {
    relayed.addAll(chunk);
    if (!firstReply.isCompleted) firstReply.complete();
  }).asFuture<void>();
  final binary = List<int>.generate(128 * 1024, (index) => index % 256);
  relay.stdin.add([
    ...utf8.encode(
      '${jsonEncode({
        'executable': Platform.resolvedExecutable,
        'arguments': [Platform.script.toFilePath(), '--stdio-child'],
        'environment': <String, String>{},
      })}\n',
    ),
    ...binary,
  ]);
  await relay.stdin.flush();
  await firstReply.future.timeout(const Duration(seconds: 10));
  relay.stdin.add(binary);
  await relay.stdin.close();
  final relayCode = await relay.exitCode.timeout(const Duration(seconds: 10));
  await relayOutput;
  if (relayCode != 0 ||
      await relayErrors != '' ||
      relayed.length != binary.length * 2 ||
      relayed.indexed.any((item) => item.$2 != item.$1 % 256)) {
    throw StateError('Interactive child stream relay lost or changed bytes.');
  }
  stdout.writeln(
    'PASS interactive binary relay with pipe backpressure and EOF',
  );

  for (final body in [
    '{"private":"must-not-leak"',
    jsonEncode({
      'executable': File('.local/must-not-leak-missing.exe').absolute.path,
      'arguments': ['must-not-leak'],
      'environment': {'PRIVATE_VALUE': 'must-not-leak'},
    }),
  ]) {
    final rejected = await Process.start(Platform.resolvedExecutable, [
      'companion/lib/process_runner.dart',
    ]);
    final rejectedOutput = utf8.decoder.bind(rejected.stdout).join();
    final rejectedErrors = utf8.decoder.bind(rejected.stderr).join();
    rejected.stdin.writeln(body);
    await rejected.stdin.close();
    final rejectedCode = await rejected.exitCode.timeout(
      const Duration(seconds: 10),
    );
    final diagnostic = await rejectedErrors;
    if (rejectedCode != 71 ||
        await rejectedOutput != '' ||
        diagnostic.contains('must-not-leak') ||
        !RegExp(
          r'^wfformcomp: (launch gate|configured child launch) failed'
          r'( \(OS error -?\d+\))?\.\r?\n$',
        ).hasMatch(diagnostic)) {
      throw StateError('Launch failure lacks a safe stage/code diagnostic.');
    }
  }
  stdout.writeln('PASS launch failure diagnostics exclude private inputs');
}
