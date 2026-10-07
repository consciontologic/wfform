import 'dart:convert';
import 'dart:io';

import 'build.dart' show isShellAsset;
import 'content_hash.dart';

/// Read-only artifact measurements. Never invokes Flutter or changes a release.
Future<void> main(List<String> args) async {
  var directory = 'build/web';
  String? output;
  String? compare;
  for (final arg in args) {
    if (arg.startsWith('--directory=')) {
      directory = arg.substring(12);
    } else if (arg.startsWith('--output=')) {
      output = arg.substring(9);
    } else if (arg.startsWith('--compare=')) {
      compare = arg.substring(10);
    } else {
      stderr.writeln(
        'Usage: dart run tool/measure.dart [--directory=build/web] [--output=path.json] [--compare=baseline.json]',
      );
      exitCode = 64;
      return;
    }
  }
  final measurement = measureArtifacts(Directory(directory));
  if (compare != null) {
    final baseline = jsonDecode(File(compare).readAsStringSync()) as Map;
    measurement['comparison'] = compareArtifacts(baseline, measurement);
  }
  final text = const JsonEncoder.withIndent('  ').convert(measurement);
  if (output != null) {
    final target = File(output);
    target.parent.createSync(recursive: true);
    target.writeAsStringSync('$text\n');
    stdout.writeln(
      'Measured ${measurement['shellAssets']} shell assets (${measurement['shellBytes']} bytes). Saved $output',
    );
  } else {
    stdout.writeln(text);
  }
}

Map<String, Object?> measureArtifacts(Directory directory) {
  final files =
      directory
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (file) => isShellAsset(
              file.path
                  .substring(directory.path.length + 1)
                  .replaceAll('\\', '/'),
            ),
          )
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  if (files.isEmpty) {
    throw StateError('No release shell assets in ${directory.path}');
  }
  final assets = <String, Object?>{};
  var bytes = 0, gzipBytes = 0;
  final watch = Stopwatch()..start();
  for (final file in files) {
    final path = file.path
        .substring(directory.path.length + 1)
        .replaceAll('\\', '/');
    final data = file.readAsBytesSync();
    final compressed = GZipCodec(level: 6).encode(data).length;
    bytes += data.length;
    gzipBytes += compressed;
    assets[path] = {
      'bytes': data.length,
      'gzipBytes': compressed,
      'sha256': sha256(data),
    };
  }
  watch.stop();
  // Reproducible bounded CPU workload, separate from UI startup/frame timing.
  final fixture = List<int>.generate(1024 * 1024, (i) => i & 255);
  for (var i = 0; i < 2; i++) {
    sha256(fixture);
  }
  final samples = <int>[];
  for (var i = 0; i < 7; i++) {
    final timer = Stopwatch()..start();
    sha256(fixture);
    timer.stop();
    samples.add(timer.elapsedMicroseconds);
  }
  samples.sort();
  final manifestFile = File('${directory.path}/release.json');
  return {
    'measuredAtUtc': DateTime.now().toUtc().toIso8601String(),
    'dartVersion': Platform.version,
    'operatingSystem': Platform.operatingSystem,
    'logicalProcessors': Platform.numberOfProcessors,
    'release': manifestFile.existsSync()
        ? (jsonDecode(manifestFile.readAsStringSync()) as Map)['version']
        : 'legacy/unversioned',
    'shellAssets': files.length,
    'shellBytes': bytes,
    'shellGzipBytes': gzipBytes,
    'serviceWorkerBytes':
        File('${directory.path}/service_worker.js').existsSync()
        ? File('${directory.path}/service_worker.js').lengthSync()
        : 0,
    'releaseManifestBytes': manifestFile.existsSync()
        ? manifestFile.lengthSync()
        : 0,
    'artifactMeasurementMicroseconds': watch.elapsedMicroseconds,
    'sha2561MiB': {
      'warmups': 2,
      'samples': 7,
      'medianMicroseconds': samples[3],
      'minMicroseconds': samples.first,
      'maxMicroseconds': samples.last,
    },
    'assets': assets,
    'notes': [
      'Gzip is an offline level-6 estimate; the local host serves uncompressed bytes.',
      'CPU samples are Dart VM tooling work, not Flutter frame timings or browser startup.',
      'Config, source maps, historical releases and API/user data are excluded.',
    ],
  };
}

Map<String, Object?> compareArtifacts(Map baseline, Map current) {
  final previous = baseline['assets'] as Map;
  final now = current['assets'] as Map;
  var unchanged = 0, reusableBytes = 0, changedBytes = 0;
  for (final key in now.keys) {
    final value = now[key] as Map;
    if (previous[key] is Map &&
        (previous[key] as Map)['sha256'] == value['sha256']) {
      unchanged++;
      reusableBytes += value['bytes'] as int;
    } else {
      changedBytes += value['bytes'] as int;
    }
  }
  return {
    'baselineRelease': baseline['release'],
    'unchangedAssets': unchanged,
    'reusableBytes': reusableBytes,
    'changedOrAddedAssets': now.length - unchanged,
    'changedOrAddedBytes': changedBytes,
    'removedAssets': previous.keys.where((key) => !now.containsKey(key)).length,
    'shellByteDelta':
        (current['shellBytes'] as int) - (baseline['shellBytes'] as int),
    'note':
        'Potential verified shell-cache reuse by matching path and content hash; not a measured network transfer.',
  };
}
