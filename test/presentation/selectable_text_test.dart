import 'dart:convert';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/presentation/selectable_surface.dart';

import 'studio_test.dart' as fixture;

Offset _position(RenderParagraph paragraph, int offset) =>
    paragraph.localToGlobal(
      paragraph.getOffsetForCaret(
            TextPosition(offset: offset),
            const Rect.fromLTWH(0, 0, 2, 20),
          ) +
          Offset(0, paragraph.preferredLineHeight / 2),
    );

Future<void> _selectText(WidgetTester tester, String text, {int? end}) async {
  final found = find
      .byWidgetPredicate((widget) => widget is Text && widget.data == text)
      .last;
  await tester.ensureVisible(found);
  await tester.pumpAndSettle();
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: found, matching: find.byType(RichText)).first,
  );
  final gesture = await tester.startGesture(
    _position(paragraph, 0),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  await gesture.moveTo(_position(paragraph, end ?? text.length));
  await gesture.up();
  await gesture.removePointer();
  await tester.pump();
}

Future<void> _shortcut(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

void main() {
  String? copied;
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          if (call.method == 'Clipboard.hasStrings') {
            return {'value': copied?.isNotEmpty ?? false};
          }
          if (call.method == 'Clipboard.getData') return {'text': copied};
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    copied = null;
  });

  testWidgets(
    'subtitle, status and composer use real independent clipboard selection',
    (tester) async {
      final h = fixture.Harness();
      await h.mount(tester, const Size(1440, 1000));
      const subtitle = 'Wrapper for Free Open Router Models';
      expect(find.text('Your conversations, your models'), findsNothing);
      await _selectText(tester, subtitle);
      await _shortcut(tester, LogicalKeyboardKey.keyC);
      expect(copied, subtitle);

      await _selectText(tester, 'OPENROUTER / FREE ONLY');
      await _shortcut(tester, LogicalKeyboardKey.keyC);
      expect(copied, 'OPENROUTER / FREE ONLY');

      await tester.enterText(fixture.composer, 'Independent composer draft');
      await tester.tap(fixture.composer);
      await _shortcut(tester, LogicalKeyboardKey.keyA);
      await _shortcut(tester, LogicalKeyboardKey.keyC);
      expect(copied, 'Independent composer draft');
      expect(h.state.draft, 'Independent composer draft');
      expect(tester.takeException(), isNull);
      await h.dispose(tester);
    },
  );

  testWidgets(
    'model dialog selection copies only its route and keeps controls working',
    (tester) async {
      final h = fixture.Harness();
      await h.mount(tester, const Size(1440, 1000));
      await tester.enterText(fixture.composer, 'Keep my unsent draft');
      await tester.tap(find.byKey(const ValueKey('model-selector')));
      await tester.pumpAndSettle();
      await _selectText(tester, 'Quiet Chat');
      await _shortcut(tester, LogicalKeyboardKey.keyC);
      expect(copied, 'Quiet Chat');
      expect(h.state.catalog.selectedId, isNull);
      await tester.tap(find.byTooltip('Model details: Quiet Chat'));
      await tester.pumpAndSettle();
      const description = 'A quiet test model with deterministic metadata.';
      await _selectText(tester, description);
      await _shortcut(tester, LogicalKeyboardKey.keyC);
      expect(copied, description);
      await _shortcut(tester, LogicalKeyboardKey.keyA);
      await _shortcut(tester, LogicalKeyboardKey.keyC);
      expect(copied, contains(description));
      expect(copied, isNot(contains('Wrapper for Free Open Router Models')));
      expect(copied, isNot(contains('Keep my unsent draft')));
      await tester.tap(find.byTooltip('Close model details'));
      await tester.pumpAndSettle();
      expect(h.state.draft, 'Keep my unsent draft');
      await tester.tap(find.text('Quiet Chat').last);
      await tester.pumpAndSettle();
      expect(h.state.catalog.selectedId, 'test/chat');
      expect(tester.takeException(), isNull);
      await h.dispose(tester);
    },
  );

  testWidgets('tooltip text is selectable without firing its control', (
    tester,
  ) async {
    var invoked = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SelectableIconButton(
              tooltip: 'Copy this helpful hint',
              onPressed: () => invoked++,
              icon: const Icon(Icons.info_outline),
            ),
          ),
        ),
      ),
    );
    tester
        .state<TooltipState>(find.byTooltip('Copy this helpful hint'))
        .ensureTooltipVisible();
    await tester.pumpAndSettle();
    await _selectText(tester, 'Copy this helpful hint');
    await _shortcut(tester, LogicalKeyboardKey.keyC);
    expect(copied, 'Copy this helpful hint');
    expect(invoked, 0);
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    expect(invoked, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'history titles and settings and diagnostics labels copy directly',
    (tester) async {
      final h = fixture.Harness();
      await h.mount(tester, const Size(1440, 1000));
      h.state.setDraft('Saved title');
      await h.state.flushHistory();
      await tester.pumpAndSettle();
      final original = h.state.activeConversationId;
      await _selectText(tester, 'Saved title');
      await _shortcut(tester, LogicalKeyboardKey.keyC);
      expect(copied, 'Saved title');
      expect(h.state.activeConversationId, original);

      const fullTitle = 'A saved conversation title beyond the row width';
      h.state.setDraft(fullTitle);
      await h.state.flushHistory();
      await tester.pumpAndSettle();
      tester
          .state<TooltipState>(find.byTooltip(fullTitle))
          .ensureTooltipVisible();
      await tester.pumpAndSettle();
      await _selectText(tester, fullTitle);
      await _shortcut(tester, LogicalKeyboardKey.keyC);
      expect(copied, fullTitle);
      Tooltip.dismissAllToolTips();
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await _selectText(tester, 'Appearance');
      await _shortcut(tester, LogicalKeyboardKey.keyC);
      expect(copied, 'Appearance');
      await _selectText(tester, 'Dark');
      await _shortcut(tester, LogicalKeyboardKey.keyC);
      expect(copied, 'Dark');
      expect(h.state.themeMode, ThemeMode.system);
      await tester.tap(find.byTooltip('Close settings'));
      await tester.pumpAndSettle();

      h.state.diagnostics.clear();
      await tester.tap(find.byTooltip('Diagnostics'));
      await tester.pumpAndSettle();
      await _selectText(tester, 'No diagnostic events yet.');
      await _shortcut(tester, LogicalKeyboardKey.keyC);
      expect(copied, 'No diagnostic events yet.');
      await _shortcut(tester, LogicalKeyboardKey.keyA);
      await _shortcut(tester, LogicalKeyboardKey.keyC);
      expect(copied, contains('No errors recorded'));
      expect(copied, isNot(contains(fullTitle)));
      await tester.tap(find.byTooltip('Close diagnostics'));
      await tester.pumpAndSettle();
      expect(h.state.draft, fullTitle);
      expect(tester.takeException(), isNull);
      await h.dispose(tester);
    },
  );

  testWidgets(
    'model details label unresolved pricing without implying a negative charge',
    (tester) async {
      final h = fixture.Harness();
      final model = fixture.modelFixture();
      (model['pricing'] as Map<String, Object>)['audio'] = '-1';
      h.transport.catalogBody = {
        'data': [model],
      };
      await h.mount(tester, const Size(1440, 1000));
      await tester.tap(find.byKey(const ValueKey('model-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Model details: Quiet Chat'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('audio: Unresolved (reported: -1)'),
        findsOneWidget,
      );
      expect(find.textContaining('audio: -1'), findsNothing);
      await h.dispose(tester);
    },
  );

  testWidgets(
    'expanded inspector description has reliable independent selection',
    (tester) async {
      final h = fixture.Harness();
      await h.mount(tester, const Size(1440, 1000));
      await h.state.selectModel(
        h.state.catalog.models.firstWhere((m) => m.chatCompatible),
      );
      await tester.pumpAndSettle();
      const description = 'A quiet test model with deterministic metadata.';
      await _selectText(tester, description);
      await _shortcut(tester, LogicalKeyboardKey.keyC);
      expect(copied, description);
      expect(tester.takeException(), isNull);
      await h.dispose(tester);
    },
  );

  testWidgets(
    'context option copy preserves full text and native selection at narrow 200 percent scale',
    (tester) async {
      final h = fixture.Harness();
      h.state.setTextScale(2);
      await h.mount(tester, const Size(320, 800));
      final question = List.filled(24, 'Long question').join(' ');
      h.state.chat.restoreSession(
        jsonEncode({
          'version': 1,
          'messages': [
            {'role': 'user', 'content': 'First question', 'reasoning': ''},
            {
              'role': 'assistant',
              'content': 'An earlier answer',
              'reasoning': '',
            },
            {'role': 'user', 'content': question, 'reasoning': ''},
          ],
        }),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Context'));
      await tester.tap(find.text('Context'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(DropdownButtonFormField<int>));
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      final label = 'Message 3: $question';
      final hint = 'Copy option: ${label.substring(0, 80)}…';
      await tester.ensureVisible(find.byTooltip(hint).last);
      await tester.tap(find.byTooltip(hint).last);
      await tester.pumpAndSettle();
      expect(copied, label);
      expect(h.state.chat.contextStartIndex, 0);
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Apply to next request'));
      await tester.tap(find.text('Apply to next request'));
      await tester.pumpAndSettle();
      expect(h.state.chat.contextStartIndex, 2);
      expect(h.state.chat.messages, hasLength(3));
      expect(tester.takeException(), isNull);
      await h.dispose(tester);
    },
  );

  testWidgets(
    'touch selection can open the copy toolbar below the route overlay',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SelectionArea(child: Text('Selectable status'))),
        ),
      );
      await tester.longPress(find.text('Selectable status'));
      await tester.pumpAndSettle();
      expect(find.text('Copy'), findsOneWidget);
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      expect(copied, anyOf('Selectable', 'status'));
      expect(tester.takeException(), isNull);
    },
  );
}
