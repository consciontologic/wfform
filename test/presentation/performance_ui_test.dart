import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/features/chat/chat_controller.dart';
import 'package:wfform/presentation/retry_control.dart';
import 'studio_test.dart' as fixture;

String conversation({String? finishReason}) => jsonEncode({
  'version': 1,
  'messages': [
    const ChatMessage(role: 'user', content: 'First question').toJson(),
    const ChatMessage(role: 'assistant', content: 'First answer').toJson(),
    const ChatMessage(role: 'user', content: 'Second question').toJson(),
    ChatMessage(
      role: 'assistant',
      content: 'Second answer',
      finishReason: finishReason,
    ).toJson(),
  ],
});

void main() {
  testWidgets(
    'cooldown countdown disables retry without sending and disposes its timer',
    (tester) async {
      var now = DateTime.utc(2026, 10, 6);
      var calls = 0;
      final until = now.add(const Duration(seconds: 2));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RetryControl(
              retryAt: until,
              now: () => now,
              onRetry: () => calls++,
            ),
          ),
        ),
      );
      expect(find.text('Retry in 2s'), findsOneWidget);
      await tester.tap(find.text('Retry in 2s'));
      expect(calls, 0);
      now = until;
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Retry'), findsOneWidget);
      expect(calls, 0);
      await tester.tap(find.text('Retry'));
      expect(calls, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'context controls persist an explicit boundary and response cap without deleting history',
    (tester) async {
      final h = fixture.Harness();
      await h.mount(tester, const Size(768, 1024));
      await h.state.selectModel(
        h.state.catalog.models.firstWhere((m) => m.chatCompatible),
      );
      h.state.chat.restoreSession(conversation());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Context'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Message 3: Second question').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Maximum response tokens'),
        '512',
      );
      await tester.tap(find.text('Apply to next request'));
      await tester.pumpAndSettle();
      expect(h.state.chat.contextStartIndex, 2);
      expect(h.state.chat.outputTokenLimit, 512);
      expect(h.state.chat.messages, hasLength(4));
      expect(h.state.chat.messages.first.content, 'First question');
      expect(find.text('Context from #3'), findsOneWidget);
      expect((h.state.chat.exportSessionData())['contextStartIndex'], 2);
      await tester.tap(find.text('Context from #3'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next message only').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply to next request'));
      await tester.pumpAndSettle();
      expect(h.state.chat.contextStartIndex, 4);
      await tester.tap(find.text('Context from #5'));
      await tester.pumpAndSettle();
      expect(find.text('Next message only'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await h.dispose(tester);
    },
  );

  testWidgets(
    'truncated response is labeled and explicit continuation is offered',
    (tester) async {
      final h = fixture.Harness();
      await h.mount(tester, const Size(768, 1024));
      await h.state.selectModel(
        h.state.catalog.models.firstWhere((m) => m.chatCompatible),
      );
      h.state.chat.restoreSession(conversation(finishReason: 'length'));
      await tester.pumpAndSettle();
      expect(
        find.text(h.state.chat.messages.last.terminationLabel),
        findsOneWidget,
      );
      expect(find.text('Continue answer'), findsOneWidget);
      expect(h.transport.sends, 0);
      await h.dispose(tester);
    },
  );

  testWidgets(
    'context controls remain reachable at 320px and 200 percent text',
    (tester) async {
      final h = fixture.Harness();
      h.state.setTextScale(2);
      await h.mount(tester, const Size(320, 740));
      await tester.ensureVisible(find.text('Context'));
      await tester.tap(find.text('Context'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(TextField, 'Maximum response tokens'),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Maximum response tokens'),
        '256',
      );
      await tester.ensureVisible(find.text('Apply to next request'));
      await tester.tap(find.text('Apply to next request'));
      await tester.pumpAndSettle();
      expect(h.state.chat.outputTokenLimit, 256);
      expect(tester.takeException(), isNull);
      await h.dispose(tester);
    },
  );
}
