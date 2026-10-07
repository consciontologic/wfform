import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'tracked text files contain no machine-specific home directories',
    () async {
      final inventory = await Process.run('git', [
        'ls-files',
        '--cached',
        '--others',
        '--exclude-standard',
        '-z',
      ]);
      expect(inventory.exitCode, 0);
      final personalPath = RegExp(
        r'/(?:home|Users)/[A-Za-z0-9._-]+/|[A-Za-z]:\\Users\\[A-Za-z0-9._-]+\\',
      );
      final failures = <String>[];
      for (final path in (inventory.stdout as String).split('\u0000').toSet()) {
        if (path.isEmpty) continue;
        final file = File(path);
        if (!file.existsSync()) continue;
        final bytes = file.readAsBytesSync();
        if (bytes.contains(0)) continue; // Binary assets are not documentation.
        final text = utf8.decode(bytes, allowMalformed: true);
        if (personalPath.hasMatch(text)) failures.add(path);
      }
      expect(
        failures,
        isEmpty,
        reason: 'Use repository-relative paths or shell variables.',
      );
    },
  );
}
