import 'dart:ui'
    show PointerDeviceKind, ViewFocusDirection, ViewFocusEvent, ViewFocusState;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'studio_test.dart' as fixture;

void main() {
  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    testWidgets('$kind outside composer dismisses its focus and caret', (
      tester,
    ) async {
      final h = fixture.Harness();
      await h.mount(tester, const Size(1440, 1000));
      await tester.enterText(fixture.composer, 'Unsent draft');
      await tester.pump();
      final field = tester.widget<TextField>(fixture.composer);
      final editable = tester.state<EditableTextState>(
        find.descendant(
          of: fixture.composer,
          matching: find.byType(EditableText),
        ),
      );
      expect(field.focusNode!.hasFocus, isTrue);
      expect(tester.testTextInput.hasAnyClients, isTrue);
      await tester.tapAt(const Offset(700, 35), kind: kind);
      await tester.pump();
      expect(field.focusNode!.hasFocus, isFalse);
      expect(tester.testTextInput.hasAnyClients, isFalse);
      await tester.pump(const Duration(milliseconds: 600));
      expect(editable.cursorCurrentlyVisible, isFalse);
      expect(h.state.draft, 'Unsent draft');
      await h.dispose(tester);
    });
  }
  testWidgets(
    'touching an outside action stops the composer caret',
    (tester) async {
      final h = fixture.Harness();
      await h.mount(tester, const Size(1440, 1000));
      await tester.enterText(fixture.composer, 'Unsent draft');
      await tester.pump();
      final field = tester.widget<TextField>(fixture.composer);
      await tester.tap(find.byTooltip('Toggle model inspector'));
      await tester.pump();
      expect(field.focusNode!.hasFocus, isFalse);
      expect(tester.testTextInput.hasAnyClients, isFalse);
      expect(h.state.draft, 'Unsent draft');
      await h.dispose(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    testWidgets('$kind divider drag preserves composer focus and draft', (
      tester,
    ) async {
      final h = fixture.Harness();
      await h.mount(tester, const Size(1440, 1000));
      await tester.enterText(fixture.composer, 'Keep drafting after resize');
      await tester.pump();
      final field = tester.widget<TextField>(fixture.composer);
      final handle = find.byKey(const ValueKey('sidebar-resize-handle'));
      await tester.drag(handle, const Offset(70, 0), kind: kind);
      await tester.pump();
      expect(h.state.sidebarWidth, 360);
      expect(field.focusNode!.hasFocus, isTrue);
      expect(tester.testTextInput.hasAnyClients, isTrue);
      expect(h.state.draft, 'Keep drafting after resize');
      await h.dispose(tester);
    });
  }

  testWidgets(
    'keyboard focus transfer stops composer caret without erasing draft',
    (tester) async {
      final h = fixture.Harness();
      await h.mount(tester, const Size(768, 1024));
      await tester.enterText(fixture.composer, 'Keyboard draft');
      final field = tester.widget<TextField>(fixture.composer);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(field.focusNode!.hasFocus, isFalse);
      expect(tester.testTextInput.hasAnyClients, isFalse);
      expect(h.state.draft, 'Keyboard draft');
      await h.dispose(tester);
    },
  );

  testWidgets(
    'view focus loss closes input and stops caret without losing selection',
    (tester) async {
      final h = fixture.Harness();
      await h.mount(tester, const Size(768, 1024));
      await tester.enterText(fixture.composer, 'Selected draft');
      final field = tester.widget<TextField>(fixture.composer);
      field.controller!.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 8,
      );
      await tester.pump();
      tester.binding.handleViewFocusChanged(
        ViewFocusEvent(
          viewId: tester.view.viewId,
          state: ViewFocusState.unfocused,
          direction: ViewFocusDirection.undefined,
        ),
      );
      await tester.pump();
      expect(field.focusNode!.hasFocus, isFalse);
      expect(tester.testTextInput.hasAnyClients, isFalse);
      expect(
        field.controller!.selection,
        const TextSelection(baseOffset: 0, extentOffset: 8),
      );
      expect(h.state.draft, 'Selected draft');
      await h.dispose(tester);
    },
  );

  testWidgets(
    'outside actions preserve an active response and shortcut send stays usable',
    (tester) async {
      final h = fixture.Harness();
      await h.mount(tester, const Size(1440, 1000));
      await h.state.selectModel(
        h.state.catalog.models.firstWhere((m) => m.chatCompatible),
      );
      h.state.health.recordSuccess(h.state.catalog.selected!.id);
      await tester.pump();
      await tester.enterText(fixture.composer, 'Send with keyboard');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      await tester.pump();
      expect(h.transport.sends, 1);
      expect(h.state.chat.busy, isTrue);
      expect(h.state.draft, isEmpty);
      h.transport.text('Partial answer');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(fixture.composer, 'Draft while waiting');
      await tester.pump();
      final field = tester.widget<TextField>(fixture.composer);
      final conversation = h.state.activeConversationId;
      await tester.tap(find.byTooltip('Toggle model inspector'));
      await tester.pump();
      expect(field.focusNode!.hasFocus, isFalse);
      expect(tester.testTextInput.hasAnyClients, isFalse);
      expect(h.state.chat.busy, isTrue);
      expect(h.transport.chatToken!.isCancelled, isFalse);
      expect(h.state.draft, 'Draft while waiting');
      expect(h.state.chat.messages.last.content, 'Partial answer');
      await tester.tap(fixture.composer);
      await tester.pump();
      await fixture.resize(tester, const Size(390, 844));
      expect(
        tester.widget<TextField>(fixture.composer).controller,
        same(field.controller),
      );
      expect(field.focusNode!.hasFocus, isTrue);
      expect(h.state.activeConversationId, conversation);
      expect(h.transport.sends, 1);
      await tester.runAsync(h.transport.finish);
      await tester.pumpAndSettle();
      expect(h.state.chat.messages.last.content, 'Partial answer');
      expect(h.state.draft, 'Draft while waiting');
      await h.dispose(tester);
    },
  );
}
