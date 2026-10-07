import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/shared/transport.dart';
import 'package:wfform/shared/diagnostics.dart';

void main() {
  testWidgets('metadata does not postpone first useful output timeout', (
    tester,
  ) async {
    final source = StreamController<String>();
    final cancel = CancelToken();
    final errors = <Object>[];
    withPhaseTimeouts(
      source.stream,
      cancel: cancel,
      firstResponseTimeout: const Duration(seconds: 10),
      idleTimeout: const Duration(seconds: 3),
      overallTimeout: const Duration(seconds: 30),
      isProgress: (value) => value == 'text',
    ).listen((_) {}, onError: errors.add);
    await tester.pump(const Duration(seconds: 9));
    source.add('metadata');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect((errors.single as AppFailure).message, contains('First response'));
    expect(cancel.isCancelled, isTrue);
    unawaited(source.close());
    await tester.pump();
  });

  testWidgets(
    'idle watchdog resets on useful output while overall remains bounded',
    (tester) async {
      final source = StreamController<String>();
      final cancel = CancelToken();
      final errors = <Object>[];
      withPhaseTimeouts(
        source.stream,
        cancel: cancel,
        firstResponseTimeout: const Duration(seconds: 10),
        idleTimeout: const Duration(seconds: 3),
        overallTimeout: const Duration(seconds: 7),
        isProgress: (_) => true,
      ).listen((_) {}, onError: errors.add);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 2));
        source.add('text');
        await tester.pump();
      }
      expect(errors, isEmpty);
      await tester.pump(const Duration(seconds: 1));
      expect(
        (errors.single as AppFailure).message,
        contains('Overall request'),
      );
      unawaited(source.close());
      await tester.pump();
    },
  );

  testWidgets('idle failure preserves already delivered values', (
    tester,
  ) async {
    final source = StreamController<String>();
    final cancel = CancelToken();
    final values = <String>[], errors = <Object>[];
    withPhaseTimeouts(
      source.stream,
      cancel: cancel,
      firstResponseTimeout: const Duration(seconds: 10),
      idleTimeout: const Duration(seconds: 3),
      overallTimeout: const Duration(seconds: 30),
      isProgress: (_) => true,
    ).listen(values.add, onError: errors.add);
    source.add('kept');
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(values, ['kept']);
    expect((errors.single as AppFailure).message, contains('Response idle'));
    unawaited(source.close());
    await tester.pump();
  });

  testWidgets('finished stream releases all phase timers', (tester) async {
    final errors = <Object>[];
    withPhaseTimeouts(
      Stream.value('done'),
      cancel: CancelToken(),
      firstResponseTimeout: const Duration(seconds: 1),
      idleTimeout: const Duration(seconds: 1),
      overallTimeout: const Duration(seconds: 2),
      isProgress: (_) => true,
    ).listen((_) {}, onError: errors.add);
    await tester.pump();
    await tester.pump(const Duration(seconds: 20));
    expect(errors, isEmpty);
  });
}
