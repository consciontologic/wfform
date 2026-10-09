import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  switch (args.first) {
    case 'echo':
      stdout.write(jsonEncode(args.sublist(1)));
    case 'spawn':
      final child = await Process.start(Platform.resolvedExecutable, [
        Platform.script.toFilePath(),
        'wait',
      ]);
      stdout.write(child.pid.toString());
      await stdout.flush();
      if (args.length > 1) {
        File(args[1]).writeAsStringSync('${child.pid}', flush: true);
      }
      await child.exitCode;
    case 'wait':
      await Future<void>.delayed(const Duration(seconds: 10));
    case 'flood':
      stdout.write('x' * 300000);
    case 'fail':
      stderr.write('intentional failure');
      exitCode = 7;
  }
}
