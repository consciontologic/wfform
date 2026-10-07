import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/shared/platform.dart';

import 'studio_test.dart' show Harness, composer, resize;

final _sidebar = find.byKey(const ValueKey('expanded-sidebar'));
final _handle = find.byKey(const ValueKey('sidebar-resize-handle'));

void main() {
  testWidgets('sidebar pointer resize is bounded and persists on release', (
    tester,
  ) async {
    final memory = MemoryStore();
    final h = Harness(memory: memory);
    await h.mount(tester, const Size(1440, 1000));
    expect(_handle, findsOneWidget);
    expect(tester.getSize(_sidebar).width, 290);
    final pointer = await tester.startGesture(
      tester.getCenter(_handle),
      kind: PointerDeviceKind.mouse,
    );
    await pointer.moveBy(const Offset(80, 0));
    await tester.pump();
    expect(tester.getSize(_sidebar).width, 370);
    expect(memory.read('freeform.sidebarWidth'), isNull);
    await pointer.up();
    await tester.pump();
    expect(memory.read('freeform.sidebarWidth'), '370.0');
    await tester.drag(_handle, const Offset(1000, 0));
    await tester.pump();
    expect(tester.getSize(_sidebar).width, 440);
    await tester.drag(_handle, const Offset(-200, 0));
    await tester.pump();
    expect(tester.getSize(_sidebar).width, 240);
    expect(tester.takeException(), isNull);
    await h.dispose(tester);

    final reopened = Harness(memory: memory);
    await reopened.mount(tester, const Size(1440, 1000));
    expect(tester.getSize(_sidebar).width, 240);
    await reopened.dispose(tester);
  });

  testWidgets(
    'keyboard and screen-reader actions resize and reset the sidebar',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final h = Harness();
      await h.mount(tester, const Size(1440, 1000));
      expect(_handle, findsOneWidget);
      await tester.tap(_handle);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(tester.getSize(_sidebar).width, 306);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      expect(tester.getSize(_sidebar).width, 440);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      expect(tester.getSize(_sidebar).width, 240);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(tester.getSize(_sidebar).width, 290);
      final node = tester.getSemantics(find.bySemanticsLabel('Resize sidebar'));
      expect(node.value, '290 pixels');
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.increase),
        isTrue,
      );
      node.owner!.performAction(node.id, SemanticsAction.increase);
      await tester.pump();
      expect(tester.getSize(_sidebar).width, 306);
      expect(tester.takeException(), isNull);
      await h.dispose(tester);
      semantics.dispose();
    },
  );

  testWidgets('sidebar adapts to available chat space and large text', (
    tester,
  ) async {
    final h = Harness(
      memory: MemoryStore()..write('freeform.sidebarWidth', '440'),
    );
    h.state.setTextScale(1.5);
    await h.mount(tester, const Size(1600, 1100));
    expect(tester.getSize(_sidebar).width, 440);
    expect(find.byKey(const ValueKey('model-inspector')), findsOneWidget);
    await resize(tester, const Size(1440, 1100));
    expect(find.byKey(const ValueKey('model-inspector')), findsNothing);
    expect(tester.getSize(_sidebar).width, 440);
    await resize(tester, const Size(1120, 1100));
    expect(tester.getSize(_sidebar).width, lessThan(440));
    expect(tester.getSize(_sidebar).width, greaterThanOrEqualTo(300));
    expect(tester.getSize(composer).width, greaterThan(700));
    expect(tester.takeException(), isNull);
    await resize(tester, const Size(1600, 1100));
    expect(tester.getSize(_sidebar).width, 440);
    for (final size in [const Size(768, 1024), const Size(320, 740)]) {
      await resize(tester, size);
      expect(_handle, findsNothing);
      expect(composer, findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    h.state.setTextScale(2);
    await tester.pump();
    await tester.tap(find.byTooltip('Open sidebar'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byWidgetPredicate((widget) => widget is FilledButton),
        matching: find.text('New conversation'),
      ),
      findsOneWidget,
    );
    expect(find.text('Settings'), findsOneWidget);
    await tester.ensureVisible(find.text('Settings'));
    await tester.pump();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(_handle, findsNothing);
    expect(tester.takeException(), isNull);
    await h.dispose(tester);
  });

  testWidgets('interrupted drag keeps the saved width across breakpoints', (
    tester,
  ) async {
    final memory = MemoryStore()..write('freeform.sidebarWidth', '310.0');
    final h = Harness(memory: memory);
    await h.mount(tester, const Size(1440, 1000));
    final pointer = await tester.startGesture(tester.getCenter(_handle));
    await pointer.moveBy(const Offset(60, 0));
    await tester.pump();
    expect(tester.getSize(_sidebar).width, 370);
    await resize(tester, const Size(768, 1024));
    await pointer.cancel();
    await tester.pump();
    expect(_handle, findsNothing);
    expect(memory.read('freeform.sidebarWidth'), '310.0');
    await resize(tester, const Size(1440, 1000));
    expect(tester.getSize(_sidebar).width, 310);
    expect(tester.takeException(), isNull);
    await h.dispose(tester);
  });

  testWidgets(
    'short expanded sidebar scrolls to utility controls at large text',
    (tester) async {
      final h = Harness();
      h.state.setTextScale(1.5);
      await h.mount(tester, const Size(1440, 600));
      expect(_handle, findsOneWidget);
      await tester.ensureVisible(find.text('Settings'));
      await tester.pump();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close settings'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await h.dispose(tester);
    },
  );

  testWidgets('touch resize and breakpoint transitions preserve active chat', (
    tester,
  ) async {
    final h = Harness();
    await h.mount(tester, const Size(1440, 1000));
    await h.state.selectModel(h.state.catalog.models.first);
    h.state.health.recordSuccess('test/chat');
    await tester.pump();
    await tester.enterText(composer, 'Question');
    await tester.tap(find.byTooltip('Send message'));
    await tester.pump();
    await tester.pump();
    h.transport.text('Partial answer');
    await tester.pump();
    await tester.pump();
    await tester.enterText(composer, 'Next draft');
    final textField = tester.widget<TextField>(composer);
    final focus = textField.focusNode!;
    final controller = textField.controller!;
    final conversation = h.state.activeConversationId;
    expect(_handle, findsOneWidget);
    final pointer = await tester.startGesture(tester.getCenter(_handle));
    await pointer.moveBy(const Offset(100, 0));
    await tester.pump();
    await pointer.up();
    await tester.pump();
    expect(tester.getSize(_sidebar).width, 390);
    for (final size in [
      const Size(768, 1024),
      const Size(390, 844),
      const Size(1440, 1000),
    ]) {
      await resize(tester, size);
      expect(h.state.activeConversationId, conversation);
      expect(h.state.catalog.selectedId, 'test/chat');
      expect(h.state.draft, 'Next draft');
      expect(tester.widget<TextField>(composer).controller, same(controller));
      expect(tester.widget<TextField>(composer).focusNode, same(focus));
      expect(focus.hasFocus, isTrue);
      expect(h.state.chat.busy, isTrue);
      expect(h.transport.sends, 1);
      expect(h.transport.chatToken!.isCancelled, isFalse);
      expect(tester.takeException(), isNull);
    }
    expect(tester.getSize(_sidebar).width, 390);
    await tester.runAsync(h.transport.finish);
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(h.state.chat.messages.last.content, 'Partial answer');
    expect(h.state.chat.busy, isFalse);
    expect(h.state.draft, 'Next draft');
    await h.dispose(tester);
  });
}
