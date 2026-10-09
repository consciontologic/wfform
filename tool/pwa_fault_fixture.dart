import 'dart:convert';
import 'dart:io';

import 'build.dart';

/// Disposable static-file fault fixture. Never reads/copies local credentials,
/// invokes inference, modifies the production output, or controls a browser.
void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/pwa_fault_fixture.dart setup|missing|corrupt|repair|status [--source=build/web] [--directory=work/pwa-fault-fixture]',
    );
    exitCode = 64;
    return;
  }
  final command = args.first;
  var source = 'build/web', directory = 'work/pwa-fault-fixture';
  for (final arg in args.skip(1)) {
    if (arg.startsWith('--source=')) {
      source = arg.substring(9);
    } else if (arg.startsWith('--directory=')) {
      directory = arg.substring(12);
    } else {
      throw ArgumentError('Unknown fixture option.');
    }
  }
  final fixture = Directory(directory).absolute;
  switch (command) {
    case 'setup':
      createFixture(Directory(source), fixture);
    case 'missing':
      publishFault(fixture, 'b', 'missing');
    case 'corrupt':
      publishFault(fixture, 'c', 'corrupt');
    case 'repair':
      repairFixture(fixture);
    case 'status':
      break;
    default:
      throw ArgumentError('Unknown fixture command.');
  }
  final state = readFixture(fixture);
  stdout.writeln(
    'Fixture ${state['variant']}: ${state['release']}; fault=${state['fault'] ?? 'none'}',
  );
  stdout.writeln(
    'Host: dart run tool/serve.dart --port=8766 --directory=${fixture.path}/host --isolated-config',
  );
}

void createFixture(Directory source, Directory fixture) {
  if (fixture.existsSync()) {
    throw StateError(
      'Fixture directory already exists. Choose a new disposable directory; no existing data was replaced.',
    );
  }
  if (!File('${source.path}/release.json').existsSync()) {
    throw StateError(
      'Use a complete content-addressed release produced by tool/build.dart.',
    );
  }
  fixture.createSync(recursive: true);
  final input = Directory('${fixture.path}/input')..createSync();
  for (final entity in source.listSync(recursive: true).whereType<File>()) {
    final path = entity.path
        .substring(source.path.length + 1)
        .replaceAll('\\', '/');
    if (!isShellAsset(path)) continue;
    final file = File('${input.path}/$path');
    file.parent.createSync(recursive: true);
    entity.copySync(file.path);
  }
  File(
    '${fixture.path}/worker-template.js',
  ).writeAsStringSync(File('web/service_worker.js').readAsStringSync());
  final state = <String, Object?>{
    'format': 1,
    'nonce': DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(36),
    'variant': 'a',
    'fault': null,
  };
  writeState(fixture, state);
  final release = fixtureRelease(fixture, 'a');
  publishFixtureRelease(fixture, release);
  state['release'] = release.version;
  writeState(fixture, state);
  writeAtomic(
    File('${fixture.path}/host/config/local.json'),
    utf8.encode('{"apiKey":""}'),
  );
}

Map<String, dynamic> readFixture(Directory fixture) {
  final file = File('${fixture.path}/fixture.json');
  if (!file.existsSync()) {
    throw StateError(
      'This is not a prepared disposable fixture. Run setup first.',
    );
  }
  final state = jsonDecode(file.readAsStringSync());
  if (state is! Map<String, dynamic> ||
      state['format'] != 1 ||
      state['nonce'] is! String ||
      !RegExp(r'^[a-z0-9]+$').hasMatch(state['nonce'] as String)) {
    throw StateError('Invalid disposable fixture metadata.');
  }
  return state;
}

void writeState(Directory fixture, Map<String, Object?> state) => writeAtomic(
  File('${fixture.path}/fixture.json'),
  utf8.encode(jsonEncode(state)),
);

Release fixtureRelease(Directory fixture, String variant) {
  final state = readFixture(fixture);
  final main = File('${fixture.path}/input/main.dart.js');
  final original = main.readAsBytesSync();
  try {
    // A harmless comment makes each fixture revision unique without changing UI.
    main.writeAsBytesSync([
      ...original,
      ...utf8.encode('\n// PWA fixture ${state['nonce']}: $variant\n'),
    ]);
    return prepareRelease(
      Directory('${fixture.path}/input'),
      File('${fixture.path}/worker-template.js').readAsStringSync(),
    );
  } finally {
    main.writeAsBytesSync(original);
  }
}

void publishFault(Directory fixture, String variant, String fault) {
  final state = readFixture(fixture);
  if (!const {'missing', 'corrupt'}.contains(fault)) {
    throw ArgumentError('Unknown static fixture fault.');
  }
  final release = fixtureRelease(fixture, variant);
  if (state['release'] == release.version) {
    throw StateError(
      'This revision was already published; choose another variant.',
    );
  }
  publishFixtureRelease(fixture, release, fault: fault);
  state.addAll({
    'variant': variant,
    'release': release.version,
    'fault': fault,
  });
  writeState(fixture, state);
}

/// Stage damage before publishing the worker, so even a background browser check
/// cannot install the unique changed asset successfully in the publication gap.
void publishFixtureRelease(
  Directory fixture,
  Release release, {
  String? fault,
}) {
  final stage = fixture.createTempSync('publication-');
  final host = Directory('${fixture.path}/host')..createSync();
  try {
    publishRelease(release, stage);
    final broken = File('${stage.path}/main.dart.js');
    if (fault == 'missing') {
      broken.deleteSync();
    }
    if (fault == 'corrupt') {
      broken.writeAsStringSync('/* deliberately corrupt static fixture */');
    }
    host.deleteSync(recursive: true);
    stage.renameSync(host.path);
    File('${host.path}/config/local.json')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{"apiKey":""}');
  } finally {
    if (stage.existsSync()) stage.deleteSync(recursive: true);
  }
}

void repairFixture(Directory fixture) {
  final state = readFixture(fixture);
  if (state['fault'] == null) {
    throw StateError('The current fixture has no active fault.');
  }
  final release = fixtureRelease(fixture, state['variant'] as String);
  if (release.version != state['release']) {
    throw StateError(
      'Fixture inputs changed; refusing to repair a different version.',
    );
  }
  writeAtomic(
    File('${fixture.path}/host/main.dart.js'),
    release.assets['main.dart.js']!,
  );
  state['fault'] = null;
  writeState(fixture, state);
}
