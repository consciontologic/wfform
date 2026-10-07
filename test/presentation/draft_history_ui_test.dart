import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/presentation/history_browser.dart';

import 'studio_test.dart' as fixture;

Finder get _history => find.byType(ConversationHistory);
Finder _row(String id) => find.descendant(
  of: _history,
  matching: find.byKey(ValueKey('history-$id')),
);
Finder _tab(String label) => find.widgetWithText(ChoiceChip, label);

Future<void> _beginResponse(WidgetTester tester, fixture.Harness h) async {
  await h.state.selectModel(
    h.state.catalog.models.firstWhere((model) => model.chatCompatible),
  );
  h.state.health.recordSuccess(h.state.catalog.selected!.id);
  await tester.pump();
  await tester.enterText(fixture.composer, 'Saved conversation');
  await tester.tap(find.byTooltip('Send message'));
  await tester.pump();
  await tester.pump();
  expect(h.transport.sends, 1);
  expect(h.state.chat.busy, isTrue);
}

Future<String> _sentChat(WidgetTester tester, fixture.Harness h) async {
  await _beginResponse(tester, h);
  h.transport.text('Saved response');
  await tester.runAsync(h.transport.finish);
  await tester.pumpAndSettle();
  return h.state.activeConversationId!;
}

void main() {
  testWidgets(
    'unsent workspace appears only in Drafts without archive or delete',
    (tester) async {
      final h = fixture.Harness();
      await h.mount(tester, const Size(1440, 1000));
      await tester.enterText(fixture.composer, 'Unsent workspace');
      await h.state.flushHistory();
      await tester.pumpAndSettle();
      final id = h.state.activeConversationId!;
      expect(_row(id), findsNothing);
      await tester.tap(_tab('Drafts'));
      await tester.pumpAndSettle();
      expect(_row(id), findsOneWidget);
      expect(find.byTooltip('Archive Unsent workspace'), findsNothing);
      expect(find.byTooltip('Delete Unsent workspace'), findsNothing);
      expect(find.byTooltip('Export Unsent workspace'), findsOneWidget);
      await tester.tap(_tab('Archived'));
      await tester.pumpAndSettle();
      expect(_row(id), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'New conversation resumes draft and navigation restores its composer',
    (tester) async {
      final h = fixture.Harness();
      await h.mount(tester, const Size(1440, 1000));
      final chatId = await _sentChat(tester, h);
      await tester.tap(find.text('New conversation'));
      await tester.pumpAndSettle();
      await tester.enterText(fixture.composer, 'Continue this draft');
      await h.state.flushHistory();
      await tester.pumpAndSettle();
      final draftId = h.state.activeConversationId!;
      await tester.tap(find.text('New conversation'));
      await tester.pumpAndSettle();
      expect(h.state.activeConversationId, draftId);
      expect(
        tester.widget<TextField>(fixture.composer).controller!.text,
        'Continue this draft',
      );
      await tester.tap(
        find.descendant(of: _row(chatId), matching: find.byType(ListTile)),
      );
      await tester.pumpAndSettle();
      expect(h.state.activeConversationId, chatId);
      expect(
        tester.widget<TextField>(fixture.composer).controller!.text,
        isEmpty,
      );
      await tester.tap(_tab('Drafts'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: _row(draftId), matching: find.byType(ListTile)),
      );
      await tester.pumpAndSettle();
      expect(h.state.activeConversationId, draftId);
      expect(
        tester.widget<TextField>(fixture.composer).controller!.text,
        'Continue this draft',
      );
      expect(h.state.catalog.selectedId, 'test/chat');
      expect(h.transport.sends, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('archiving the active chat leaves a writable composer', (
    tester,
  ) async {
    final h = fixture.Harness();
    await h.mount(tester, const Size(1440, 1000));
    final chatId = await _sentChat(tester, h);
    await tester.tap(find.byTooltip('Archive Saved conversation'));
    await tester.pumpAndSettle();
    expect(h.state.activeConversationId, isNot(chatId));
    expect(h.state.activeConversationArchived, isFalse);
    expect(tester.widget<TextField>(fixture.composer).readOnly, isFalse);
    await tester.enterText(fixture.composer, 'Writable after archive');
    expect(h.state.draft, 'Writable after archive');
    await tester.tap(_tab('Archived'));
    await tester.pumpAndSettle();
    expect(_row(chatId), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final outcome in ['complete', 'cancel', 'error']) {
    testWidgets('responding row indicator stops after $outcome', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final h = fixture.Harness();
      await h.mount(tester, const Size(1440, 1000));
      await _beginResponse(tester, h);
      final id = h.state.activeConversationId!;
      final indicator = find.byKey(ValueKey('history-responding-$id'));
      expect(indicator, findsOneWidget);
      expect(tester.getSemantics(indicator).label, 'Responding');
      semantics.dispose();
      expect(
        find.descendant(
          of: indicator,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      h.transport.text('Partial answer');
      await tester.pump(const Duration(milliseconds: 80));
      expect(indicator, findsOneWidget);
      if (outcome == 'complete') {
        await tester.runAsync(h.transport.finish);
      } else if (outcome == 'cancel') {
        h.state.chat.cancel();
      } else {
        h.transport.chatBytes.add(
          utf8.encode(
            'data: {"error":{"code":503,"message":"Fixture provider error"}}\n\n',
          ),
        );
      }
      await tester.pumpAndSettle();
      expect(indicator, findsNothing);
      expect(h.state.chat.messages.last.content, 'Partial answer');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'sending from Drafts follows the responding conversation into Chats',
    (tester) async {
      final h = fixture.Harness();
      await h.mount(tester, const Size(1440, 1000));
      await h.state.selectModel(h.state.catalog.models.first);
      await tester.pumpAndSettle();
      await tester.tap(_tab('Drafts'));
      await tester.pump();
      await _beginResponse(tester, h);
      expect(tester.widget<ChoiceChip>(_tab('Chats')).selected, isTrue);
      expect(
        find.byKey(
          ValueKey('history-responding-${h.state.activeConversationId}'),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.ancestor(
                of: find.text('New conversation'),
                matching: find.byWidgetPredicate(
                  (widget) => widget is FilledButton,
                ),
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(_tab('Drafts'));
      await tester.pump();
      expect(tester.widget<ChoiceChip>(_tab('Drafts')).selected, isTrue);
      h.state.chat.cancel();
      await tester.pumpAndSettle();
      expect(h.transport.sends, 1);
    },
  );

  testWidgets('reduced motion keeps a semantic static response indicator', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final semantics = tester.ensureSemantics();
    final h = fixture.Harness();
    await h.mount(tester, const Size(1440, 1000));
    await _beginResponse(tester, h);
    final indicator = find.byKey(
      ValueKey('history-responding-${h.state.activeConversationId}'),
    );
    expect(tester.getSemantics(indicator).label, 'Responding');
    semantics.dispose();
    expect(
      find.descendant(
        of: indicator,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );
    expect(
      find.descendant(of: indicator, matching: find.byIcon(Icons.sync)),
      findsOneWidget,
    );
    h.state.chat.cancel();
    await tester.pumpAndSettle();
    expect(indicator, findsNothing);
  });

  for (final size in [const Size(768, 1024), const Size(320, 740)]) {
    testWidgets('Drafts remains usable at $size with 200 percent text', (
      tester,
    ) async {
      final h = fixture.Harness();
      h.state.setTextScale(2);
      await h.mount(tester, size);
      await tester.enterText(fixture.composer, 'Narrow draft');
      await h.state.flushHistory();
      await tester.pumpAndSettle();
      final id = h.state.activeConversationId!;
      await tester.tap(find.byTooltip('Open sidebar'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(_tab('Drafts'));
      await tester.tap(_tab('Drafts'));
      await tester.pumpAndSettle();
      final tile = find.descendant(
        of: _row(id),
        matching: find.byType(ListTile),
      );
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(_history, findsNothing);
      expect(
        tester.widget<TextField>(fixture.composer).controller!.text,
        'Narrow draft',
      );
      expect(tester.widget<TextField>(fixture.composer).readOnly, isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
