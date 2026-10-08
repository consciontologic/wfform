import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'composer_test.dart' show Picker, choose;
import 'studio_test.dart' as fixture;

// These exercise application geometry, not Flutter's browser engine. The engine
// regression is fixed by the pinned SDK; see mobile-keyboard-verification.md.
void main() {
  for (final scale in [1.0, 1.25, 2.0]) {
    testWidgets('keyboard cycles restore full height at text scale $scale', (
      tester,
    ) async {
      final picker = Picker();
      final h = fixture.Harness(picker: picker);
      final model = fixture.modelFixture();
      (model['architecture'] as Map)['input_modalities'] = ['text', 'image'];
      h.transport.catalogBody = {
        'data': [model],
      };
      h.state.setTextScale(scale);
      await h.mount(tester, const Size(412, 846));
      await choose(h, tester);
      await h.state.pickAttachments({'image/png'});
      await tester.pumpAndSettle();
      await tester.enterText(fixture.composer, 'Keep this draft while typing');
      final editor = tester.widget<TextField>(fixture.composer);
      final controller = editor.controller!;
      final focus = editor.focusNode!;
      controller.selection = const TextSelection.collapsed(offset: 9);
      await tester.pumpAndSettle();
      final attachment = h.state.draftAttachments.single;
      final originalComposer = tester.getRect(fixture.composer);
      addTearDown(tester.view.resetViewInsets);

      // Android's hide-keyboard button can keep the TextField focused. Returning
      // insets to zero must restore the layout without forcing a new focus.
      for (final height in [310.0, 280.0, 330.0]) {
        tester.view.viewInsets = FakeViewPadding(bottom: height);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('app-footer')), findsNothing);
        expect(
          tester.getRect(fixture.composer).bottom,
          lessThanOrEqualTo(846 - height),
        );
        expect(focus.hasFocus, isTrue);
        tester.view.viewInsets = const FakeViewPadding();
        await tester.pumpAndSettle();
        expect(tester.getRect(fixture.composer), originalComposer);
        expect(controller.text, 'Keep this draft while typing');
        expect(controller.selection, const TextSelection.collapsed(offset: 9));
        expect(h.state.draftAttachments.single.id, attachment.id);
        expect(
          h.state.draftAttachments.single.base64Data,
          attachment.base64Data,
        );
        expect(focus.hasFocus, isTrue);
        expect(tester.takeException(), isNull);
      }

      // Outside-tap dismissal also restores the full layout without submission.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(200, 30));
      tester.view.viewInsets = const FakeViewPadding();
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isFalse);
      expect(tester.getRect(fixture.composer), originalComposer);
      expect(controller.text, 'Keep this draft while typing');
      expect(h.transport.sends, 0);
      expect(tester.takeException(), isNull);
      await h.dispose(tester);
    });
  }
}
