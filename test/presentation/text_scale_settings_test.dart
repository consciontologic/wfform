import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/presentation/utilities.dart';

import 'studio_test.dart' as fixtures;

void main() {
  testWidgets(
    '125 percent applies without losing the draft and survives restart',
    (tester) async {
      final h = fixtures.Harness();
      await h.mount(tester, const Size(1280, 900));
      await h.state.selectModel(h.state.catalog.models.first);
      await tester.enterText(fixtures.composer, 'Keep this unsent message');
      final selectedId = h.state.catalog.selectedId;
      unawaited(
        openSettings(tester.element(find.byType(Scaffold).first), h.state),
      );
      await tester.pumpAndSettle();
      final option = find.widgetWithText(ChoiceChip, '125% text');
      expect(option, findsOneWidget);
      await tester.ensureVisible(option);
      await tester.tap(option);
      await tester.pumpAndSettle();
      expect(h.state.textScale, 1.25);
      expect(tester.widget<ChoiceChip>(option).selected, isTrue);
      expect(h.state.draft, 'Keep this unsent message');
      expect(h.state.catalog.selectedId, selectedId);
      await tester.tap(find.byTooltip('Close settings'));
      await tester.pumpAndSettle();
      expect(
        MediaQuery.textScalerOf(tester.element(fixtures.composer)).scale(16),
        20,
      );
      await h.dispose(tester);
      final restored = fixtures.Harness(memory: h.store);
      expect(restored.state.textScale, 1.25);
      await restored.mount(tester, const Size(1280, 900));
      expect(
        MediaQuery.textScalerOf(tester.element(fixtures.composer)).scale(16),
        20,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'text-size choices remain reachable on narrow screens at 200 percent',
    (tester) async {
      final h = fixtures.Harness();
      h.state.setTextScale(2);
      await h.mount(tester, const Size(320, 700));
      unawaited(
        openSettings(tester.element(find.byType(Scaffold).first), h.state),
      );
      await tester.pumpAndSettle();
      for (final label in [
        '100% text',
        '125% text',
        '150% text',
        '200% text',
      ]) {
        final option = find.widgetWithText(ChoiceChip, label);
        expect(option, findsOneWidget);
        await tester.ensureVisible(option);
        await tester.pumpAndSettle();
        expect(option.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      final option = find.widgetWithText(ChoiceChip, '125% text');
      await tester.ensureVisible(option);
      await tester.tap(option);
      await tester.pumpAndSettle();
      expect(h.state.textScale, 1.25);
      expect(tester.takeException(), isNull);
    },
  );
}
