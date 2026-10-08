import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/presentation/history_browser.dart';

import 'composer_test.dart' show Picker, choose;
import 'studio_test.dart' as fixture;

void main() {
  for (final size in [
    const Size(390, 844),
    const Size(820, 1180),
    const Size(1024, 768),
  ]) {
    testWidgets('small-screen chrome yields room to chat at $size', (
      tester,
    ) async {
      final h = fixture.Harness();
      await h.mount(tester, size);
      await choose(h, tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('app-footer')), findsNothing);
      expect(find.byKey(const ValueKey('medium-rail')), findsNothing);
      expect(find.byTooltip('Open sidebar'), findsOneWidget);
      expect(find.text('Context'), findsOneWidget);
      expect(find.text('Add files'), findsOneWidget);
      expect(find.text('Saved'), findsNothing);
      expect(find.text('Text & source files'), findsNothing);
      expect(find.textContaining('Estimated input:'), findsNothing);
      expect(find.textContaining('Enter for a new line'), findsNothing);
      expect(
        tester.getBottomLeft(find.byKey(const ValueKey('model-selector'))).dy,
        lessThanOrEqualTo(70),
      );
      await tester.tap(find.text('Context'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Current request: Estimated input:'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('model-selector')));
      await tester.pumpAndSettle();
      expect(find.text('Choose a free model'), findsOneWidget);
      expect(find.text('Quiet Chat'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await h.dispose(tester);
    });
  }

  for (final (size, scale) in [
    (const Size(320, 740), 1.0),
    (const Size(320, 740), 2.0),
    (const Size(390, 844), 1.25),
    (const Size(820, 1180), 2.0),
  ]) {
    testWidgets('Models label stays visible at $size and $scale text scale', (
      tester,
    ) async {
      final h = fixture.Harness();
      h.state.setTextScale(scale);
      await h.mount(tester, size);
      final selector = find.byKey(const ValueKey('model-selector'));
      expect(
        find.descendant(of: selector, matching: find.text('Models')),
        findsOneWidget,
      );
      expect(find.text('Models').hitTestable(), findsOneWidget);
      expect(tester.getRect(selector).right, lessThanOrEqualTo(size.width));
      await tester.tap(selector);
      await tester.pumpAndSettle();
      expect(find.text('Choose a free model'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await h.dispose(tester);
    });
  }

  testWidgets('phone drawer gives reclaimed footer space to history', (
    tester,
  ) async {
    final h = fixture.Harness();
    await h.mount(tester, const Size(390, 844));
    await tester.tap(find.byTooltip('Open sidebar'));
    await tester.pumpAndSettle();
    final footer = tester.getRect(
      find.byKey(const ValueKey('sidebar-app-footer')),
    );
    expect(footer.height, lessThanOrEqualTo(56));
    expect(footer.bottom, closeTo(844, 1));
    expect(
      tester.getSize(find.byType(ConversationHistory)).height,
      greaterThan(584),
    );
    expect(tester.takeException(), isNull);
    await h.dispose(tester);
  });

  testWidgets(
    'small model control and drawer preserve composition across layouts',
    (tester) async {
      final h = fixture.Harness(picker: Picker());
      final model = fixture.modelFixture();
      (model['architecture'] as Map)['input_modalities'] = ['text', 'image'];
      h.transport.catalogBody = {
        'data': [model],
      };
      await h.mount(tester, const Size(390, 844));
      await choose(h, tester);
      await tester.enterText(fixture.composer, 'Keep my draft');
      await tester.tap(find.text('Add files'));
      await tester.pumpAndSettle();
      final file = h.state.draftAttachments.single;
      final editor = tester.widget<TextField>(fixture.composer);
      editor.controller!.selection = const TextSelection.collapsed(offset: 4);
      for (final size in [
        const Size(820, 1180),
        const Size(1440, 900),
        const Size(320, 740),
      ]) {
        await fixture.resize(tester, size);
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(fixture.composer).controller,
          same(editor.controller),
        );
        expect(editor.controller!.text, 'Keep my draft');
        expect(editor.controller!.selection.baseOffset, 4);
        expect(h.state.draftAttachments.single.id, file.id);
        expect(h.state.catalog.selectedId, 'test/chat');
        expect(tester.takeException(), isNull);
      }
      h.state.setTextScale(2);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('model-selector')));
      await tester.pumpAndSettle();
      expect(find.text('Choose a free model'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await h.dispose(tester);
    },
  );
}
