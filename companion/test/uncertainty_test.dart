import 'dart:async';
import 'dart:io';
import 'package:wfformcomp/wfformcomp.dart';
import 'package:wfformcomp/stdio_mcp.dart';

bool uncertain(Map result) =>
    (result['_meta'] as Map?)?['wfform.com/outcome'] == 'uncertain';
Future<void> main() async {
  for (final mode in ['wait', 'flood', 'fail']) {
    final tool = CommandTool.fromJson({
      'name': 'command',
      'description': 'Outcome fixture',
      'executable': Platform.resolvedExecutable,
      'arguments': [
        File('companion/test/command_fixture.dart').absolute.path,
        mode,
      ],
      'timeoutMs': mode == 'wait' ? 300 : 3000,
      'maxOutputBytes': 1024,
    });
    final result = await tool.call({}, Execution());
    if (uncertain(result) != (mode != 'fail')) {
      throw StateError(
        'Command $mode lost its machine-readable outcome certainty.',
      );
    }
    final rejected = await tool.call({'unexpected': true}, Execution());
    if (uncertain(rejected)) {
      throw StateError('Pre-dispatch validation failure was marked uncertain.');
    }
  }
  final cancelTool = CommandTool.fromJson({
    'name': 'cancel',
    'description': 'Cancellation fixture',
    'executable': Platform.resolvedExecutable,
    'arguments': [
      File('companion/test/command_fixture.dart').absolute.path,
      'wait',
    ],
    'timeoutMs': 3000,
  });
  final commandExecution = Execution();
  final pendingCommand = cancelTool.call({}, commandExecution);
  Timer(const Duration(milliseconds: 200), commandExecution.cancel);
  if (!uncertain(await pendingCommand)) {
    throw StateError('Dispatched command cancellation was not uncertain.');
  }
  for (final mode in [
    'delay',
    'disconnect',
    'malformed',
    'tool-error',
    'cancel',
  ]) {
    final bridge = await StdioMcp.start(
      StdioServerConfig.fromJson({
        'name': 'local',
        'executable': Platform.resolvedExecutable,
        'arguments': [
          File('companion/test/stdio_fixture.dart').absolute.path,
          mode == 'cancel' ? 'delay' : mode,
        ],
        'allowedTools': ['echo'],
        'timeoutMs': 700,
      }),
    );
    try {
      final execution = Execution();
      final pending = bridge.call('local__echo', {'text': 'hello'}, execution);
      if (mode == 'cancel') {
        Timer(const Duration(milliseconds: 100), execution.cancel);
      }
      final result = await pending;
      if (uncertain(result) != (mode != 'tool-error')) {
        throw StateError(
          'Stdio $mode lost its machine-readable outcome certainty.',
        );
      }
    } finally {
      await bridge.close();
    }
  }
  stdout.writeln(
    'PASS dispatched CLI/MCP interruption is machine-readable uncertain; definite failures stay definite',
  );
}
