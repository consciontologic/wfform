import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/shared/platform.dart';

import 'studio_test.dart' show Harness, composer, resize;

final _sidebar = find.byKey(const ValueKey('expanded-sidebar'));
final _divider = find.byKey(const ValueKey('sidebar-resize-handle'));
final _edge = find.byKey(const ValueKey('sidebar-reveal-edge'));
final _preview = find.byKey(const ValueKey('sidebar-hover-preview'));

Future<void> _collapse(WidgetTester tester) async {
  await tester.drag(_divider, const Offset(-1000, 0));
  await tester.pumpAndSettle();
  expect(_sidebar, findsNothing);
  expect(_divider, findsNothing);
  expect(_edge, findsOneWidget);
}

Future<TestGesture> _hoverReveal(WidgetTester tester) async {
  final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await pointer.addPointer(location: const Offset(600, 220));
  await pointer.moveTo(const Offset(2, 220));
  await tester.pumpAndSettle();
  expect(_preview, findsOneWidget);
  return pointer;
}

void main() {
  testWidgets('sidebar divider is a plain line without a resize grip', (
    tester,
  ) async {
    final h = Harness();
    await h.mount(tester, const Size(1440, 1000));
    expect(_divider, findsOneWidget);
    expect(
      find.descendant(of: _divider, matching: find.byType(Icon)),
      findsNothing,
    );
    await h.dispose(tester);
  });

  testWidgets('drag to edge hides navigation and persists across restart', (
    tester,
  ) async {
    final memory = MemoryStore();
    final h = Harness(memory: memory);
    await h.mount(tester, const Size(1440, 1000));
    await tester.enterText(composer, 'Keep the draft');
    final before = tester.getSize(composer).width;
    await _collapse(tester);
    expect(tester.getSize(composer).width, greaterThan(before + 250));
    expect(memory.read('freeform.sidebarCollapsed'), 'true');
    expect(h.state.draft, 'Keep the draft');
    expect(find.byTooltip('Diagnostics'), findsNothing);
    await h.dispose(tester);
    final restored = Harness(memory: memory);
    await restored.mount(tester, const Size(1440, 1000));
    expect(_sidebar, findsNothing);
    expect(_preview, findsNothing);
    expect(_edge, findsOneWidget);
    await restored.dispose(tester);
  });

  testWidgets(
    'utmost edge hover previews without reflow and exit hides again',
    (tester) async {
      final h = Harness();
      await h.mount(tester, const Size(1440, 1000));
      await _collapse(tester);
      final before = tester.getRect(composer);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(600, 220));
      await mouse.moveTo(const Offset(18, 220));
      await tester.pump();
      expect(_preview, findsNothing);
      await mouse.moveTo(const Offset(2, 220));
      await tester.pumpAndSettle();
      expect(_preview, findsOneWidget);
      expect(tester.getSize(_preview).width, 290);
      expect(tester.getRect(composer), before);
      await mouse.moveTo(const Offset(150, 300));
      await tester.pump();
      expect(_preview, findsOneWidget);
      await mouse.moveTo(const Offset(600, 300));
      await tester.pumpAndSettle();
      expect(_preview, findsNothing);
      expect(tester.getRect(composer), before);
      await mouse.removePointer();
      await h.dispose(tester);
    },
  );

  testWidgets(
    'first preview Settings click both opens settings and restores default width',
    (tester) async {
      final memory = MemoryStore()..write('freeform.sidebarWidth', '400');
      final h = Harness(memory: memory);
      await h.mount(tester, const Size(1440, 1000));
      await _collapse(tester);
      final mouse = await _hoverReveal(tester);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close settings'), findsOneWidget);
      await tester.tap(find.byTooltip('Close settings'));
      await tester.pumpAndSettle();
      expect(_preview, findsNothing);
      expect(tester.getSize(_sidebar).width, 290);
      expect(memory.read('freeform.sidebarCollapsed'), 'false');
      expect(memory.read('freeform.sidebarWidth'), '290.0');
      await mouse.moveTo(const Offset(700, 250));
      await tester.pump();
      expect(_sidebar, findsOneWidget);
      await mouse.removePointer();
      await h.dispose(tester);
    },
  );

  testWidgets(
    'touch preview New conversation resumes the draft on the first tap',
    (tester) async {
      final h = Harness();
      await h.mount(tester, const Size(1440, 1000));
      await tester.enterText(composer, 'Save my first draft');
      final oldId = h.state.activeConversationId;
      await _collapse(tester);
      await tester.tap(_edge);
      await tester.pumpAndSettle();
      final newConversation = find
          .descendant(
            of: _preview,
            matching: find.byWidgetPredicate(
              (widget) => widget is FilledButton,
            ),
          )
          .first;
      await tester.tap(newConversation);
      await tester.pumpAndSettle();
      expect(h.state.activeConversationId, oldId);
      expect(h.state.draft, 'Save my first draft');
      expect(
        tester.widget<TextField>(composer).controller!.text,
        'Save my first draft',
      );
      expect(tester.getSize(_sidebar).width, 290);
      expect(_preview, findsNothing);
      expect(tester.takeException(), isNull);
      await h.dispose(tester);
    },
  );

  testWidgets(
    'keyboard collapse reveal Escape and item activation are accessible',
    (tester) async {
      final h = Harness();
      await h.mount(tester, const Size(1440, 1000));
      await tester.tap(_divider);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(_edge, findsOneWidget);
      await tester.tap(_edge);
      await tester.pumpAndSettle();
      expect(_preview, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(_preview, findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(_preview, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(_sidebar, findsOneWidget);
      expect(_preview, findsNothing);
      expect(tester.takeException(), isNull);
      await h.dispose(tester);
    },
  );

  testWidgets(
    'collapse preference preserves compact and large-text navigation',
    (tester) async {
      final h = Harness();
      await h.mount(tester, const Size(1440, 1000));
      await _collapse(tester);
      await resize(tester, const Size(768, 1024));
      expect(find.byKey(const ValueKey('medium-rail')), findsOneWidget);
      expect(_edge, findsNothing);
      await resize(tester, const Size(320, 740));
      h.state.setTextScale(2);
      await tester.pump();
      await tester.tap(find.byTooltip('Open sidebar'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Settings'));
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close settings'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await h.dispose(tester);
    },
  );

  testWidgets(
    'keyboard Settings activation executes before the preview moves',
    (tester) async {
      final h = Harness();
      await h.mount(tester, const Size(1440, 1000));
      await _collapse(tester);
      await tester.tap(_edge);
      await tester.pumpAndSettle();
      Focus.of(tester.element(find.text('Settings'))).requestFocus();
      await tester.pump();
      expect(_preview, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close settings'), findsOneWidget);
      expect(h.state.sidebarCollapsed, isFalse);
      await tester.tap(find.byTooltip('Close settings'));
      await tester.pumpAndSettle();
      expect(tester.getSize(_sidebar).width, 290);
      expect(tester.takeException(), isNull);
      await h.dispose(tester);
    },
  );

  testWidgets('keyboard search focus survives restoration from preview', (
    tester,
  ) async {
    final h = Harness();
    await h.mount(tester, const Size(1440, 1000));
    await _collapse(tester);
    await tester.tap(_edge);
    await tester.pumpAndSettle();
    final search = find.widgetWithText(TextField, 'Search conversations');
    final editable = find.descendant(
      of: search,
      matching: find.byType(EditableText),
    );
    final field = tester.widget<EditableText>(editable);
    for (var i = 0; i < 12 && !field.focusNode.hasFocus; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(field.focusNode.hasFocus, isTrue);
    expect(h.state.sidebarCollapsed, isFalse);
    expect(_preview, findsNothing);
    expect(
      tester.widget<EditableText>(editable).focusNode,
      same(field.focusNode),
    );
    expect(
      tester.widget<EditableText>(editable).controller,
      same(field.controller),
    );
    await tester.enterText(search, 'Retained search query');
    expect(field.controller.text, 'Retained search query');
    expect(tester.takeException(), isNull);
    await h.dispose(tester);
  });

  testWidgets(
    'collapse and hover preserve a draft, focus and active response',
    (tester) async {
      final h = Harness();
      await h.mount(tester, const Size(1440, 1000));
      await h.state.selectModel(h.state.catalog.models.first);
      h.state.health.recordSuccess('test/chat');
      await tester.pump();
      await tester.enterText(composer, 'Original question');
      await tester.tap(find.byTooltip('Send message'));
      await tester.pump();
      await tester.pump();
      h.transport.text('Partial answer');
      await tester.pump();
      await tester.pump();
      await tester.enterText(composer, 'Next draft');
      final focus = tester.widget<TextField>(composer).focusNode!;
      final controller = tester.widget<TextField>(composer).controller!;
      final conversation = h.state.activeConversationId;
      await tester.drag(_divider, const Offset(-1000, 0));
      await tester.pump();
      expect(_sidebar, findsNothing);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(600, 220));
      await mouse.moveTo(const Offset(2, 220));
      await tester.pump();
      expect(_preview, findsOneWidget);
      expect(focus.hasFocus, isTrue);
      await mouse.moveTo(const Offset(600, 220));
      await tester.pump();
      expect(_preview, findsNothing);
      for (final size in [const Size(768, 1024), const Size(1440, 1000)]) {
        await resize(tester, size);
        expect(h.state.activeConversationId, conversation);
        expect(h.state.catalog.selectedId, 'test/chat');
        expect(h.state.draft, 'Next draft');
        expect(tester.widget<TextField>(composer).controller, same(controller));
        expect(focus.hasFocus, isTrue);
        expect(h.state.chat.busy, isTrue);
        expect(h.transport.sends, 1);
        expect(h.transport.chatToken!.isCancelled, isFalse);
        expect(tester.takeException(), isNull);
      }
      await mouse.removePointer();
      await tester.runAsync(h.transport.finish);
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(h.state.chat.messages.last.content, 'Partial answer');
      expect(h.state.draft, 'Next draft');
      await h.dispose(tester);
    },
  );
}
