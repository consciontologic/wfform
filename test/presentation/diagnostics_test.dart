import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/presentation/utilities.dart';
import 'package:wfform/shared/diagnostics.dart';

import 'studio_test.dart' as fixtures;

void main() {
  testWidgets('diagnostics separates routine activity and genuine errors', (
    tester,
  ) async {
    final h = fixtures.Harness();
    await h.mount(tester, const Size(1440, 1000));
    h.state.diagnostics.clear();
    h.state.diagnostics.record('catalog.refresh', note: 'Catalog refreshed.');
    h.state.diagnostics.record(
      'chat.cancel',
      failure: const AppFailure(FailureKind.cancelled, 'Cancelled by user.'),
    );
    h.state.diagnostics.record(
      'offline',
      failure: const AppFailure(FailureKind.offline, 'Working offline.'),
    );
    final context = tester.element(find.byType(Scaffold).first);
    unawaited(openDiagnostics(context, h.state));
    await tester.pumpAndSettle();
    expect(find.text('No errors recorded · 3 activity events'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsNothing);

    h.state.diagnostics.record(
      'catalog.quarantine',
      failure: const AppFailure(
        FailureKind.schema,
        'A price is malformed.',
        field: r'$.data[0].pricing.prompt',
        expected: 'decimal price',
        actual: 'String',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 error recorded · 3 activity events'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    await tester.tap(find.text('catalog.quarantine · schema'));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText &&
            ((widget.data ?? widget.textSpan?.toPlainText())?.contains(
                  r'$.data[0].pricing.prompt',
                ) ??
                false),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Clear log'));
    await tester.pumpAndSettle();
    expect(find.text('No errors recorded · 0 activity events'), findsOneWidget);
    expect(find.text('No diagnostic events yet.'), findsOneWidget);
    await tester.tap(find.byTooltip('Close diagnostics'));
    await tester.pumpAndSettle();
    await h.dispose(tester);
  });

  testWidgets(
    'PWA inspection keeps JSON in details rather than the log summary',
    (tester) async {
      final h = fixtures.Harness();
      await h.mount(tester, const Size(1440, 1200));
      final context = tester.element(find.byType(Scaffold).first);
      unawaited(openSettings(context, h.state));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Inspect offline cache'));
      await tester.tap(find.text('Inspect offline cache'));
      await tester.pumpAndSettle();
      final event = h.state.diagnostics.events.first;
      expect(event.data['operation'], 'PWA inspection');
      expect(event.isError, false);
      expect(
        event.data['summary'],
        startsWith('Offline cache inspection completed.'),
      );
      expect(event.data['summary'], isNot(contains('fixture-shell-v1')));
      expect(event.data['details'], contains('fixture-shell-v1'));
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SelectableText &&
              ((widget.data ?? widget.textSpan?.toPlainText())?.contains(
                    'fixture-shell-v1',
                  ) ??
                  false),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close settings'));
      await tester.pumpAndSettle();
      await h.dispose(tester);
    },
  );
}
