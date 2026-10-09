import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'windows_job.dart';
import 'process_runner.dart' show isWindowsNativeExecutable;

final _groups = Expando<bool>();
final _jobs = Expando<WindowsJob>();

bool isWindowsDartSourceRuntime(String path) {
  final normalized = path.toLowerCase().replaceAll('/', r'\');
  return normalized.endsWith(r'\dart.exe') ||
      normalized.endsWith(r'\dartvm.exe');
}

/// On Linux, isolate the approved program and its descendants in a process
/// group. Windows gates launch until an owning job can kill all descendants.
Future<Process> startProgram(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  required Map<String, String> environment,
}) async {
  if (Platform.isWindows) {
    if (!isWindowsNativeExecutable(executable)) {
      throw ProcessException(
        executable,
        [],
        'Windows tools require a native .exe, not a batch or shell wrapper.',
      );
    }
    final runningFromSource = isWindowsDartSourceRuntime(
      Platform.resolvedExecutable,
    );
    final runner = runningFromSource
        ? (await Isolate.resolvePackageUri(
            Uri.parse('package:wfformcomp/process_runner.dart'),
          ))!.toFilePath()
        : '--internal-child';
    final process = await Process.start(
      Platform.resolvedExecutable,
      [runner],
      // Only our inert same-executable gate inherits runtime necessities. The
      // configured program is started by runChild with an explicit environment
      // and includeParentEnvironment:false, after job assignment succeeds.
      includeParentEnvironment: true,
      runInShell: false,
    );
    try {
      _jobs[process] = WindowsJob.attach(process.pid);
      unawaited(process.exitCode.then((_) => stopProgram(process)));
      process.stdin.writeln(
        jsonEncode({
          'executable': executable,
          'arguments': arguments,
          'workingDirectory': workingDirectory,
          'environment': environment,
        }),
      );
      await process.stdin.flush();
      return process;
    } on Object {
      stopProgram(process);
      rethrow;
    }
  }
  final grouped =
      Platform.isLinux &&
      File('/usr/bin/setsid').existsSync() &&
      File('/bin/kill').existsSync();
  final process = await Process.start(
    grouped ? '/usr/bin/setsid' : executable,
    grouped ? [executable, ...arguments] : arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    includeParentEnvironment: false,
    runInShell: false,
  );
  _groups[process] = grouped;
  return process;
}

void stopProgram(Process process) {
  final job = _jobs[process];
  if (job != null) {
    job.close();
  } else if (_groups[process] == true) {
    unawaited(_killGroup(process));
  } else {
    process.kill(ProcessSignal.sigkill);
  }
}

Future<void> _killGroup(Process process) async {
  try {
    final result = await Process.run('/bin/kill', [
      '-KILL',
      '--',
      '-${process.pid}',
    ], runInShell: false);
    // A group may already have exited before cancellation arrives.
    if (result.exitCode != 0) process.kill(ProcessSignal.sigkill);
  } on ProcessException {
    process.kill(ProcessSignal.sigkill);
  }
}
