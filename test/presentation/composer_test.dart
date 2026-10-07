import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/features/chat/chat_controller.dart';
import 'package:wfform/shared/attachment_picker.dart';
import 'package:wfform/shared/diagnostics.dart';
import 'package:wfform/shared/transport.dart';

import 'studio_test.dart' as fixture;

const png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/RZkAAAAASUVORK5CYII=';

class Picker implements AttachmentPicker {
  int calls = 0;
  int count = 1;
  @override
  Future<List<PickedAttachmentFile>> pick({
    required Set<String> allowedMimeTypes,
    int existingCount = 0,
    int existingBytes = 0,
    CancelToken? cancel,
  }) async {
    calls++;
    expect(allowedMimeTypes, contains('image/png'));
    return List.generate(
      count,
      (i) => PickedAttachmentFile(
        name: 'example-$i.png',
        mimeType: 'image/png',
        bytes: base64Decode(png),
      ),
    );
  }

  @override
  void dispose() {}
}

Future<void> choose(fixture.Harness h, WidgetTester tester) async {
  await h.state.selectModel(h.state.catalog.models.first);
  h.state.health.recordSuccess(h.state.catalog.selected!.id);
  await tester.pump();
}

void main() {
  testWidgets(
    'accepted sends clear immediately; later failure keeps the next draft',
    (tester) async {
      final h = fixture.Harness();
      await h.mount(tester, const Size(768, 1024));
      await choose(h, tester);
      await tester.enterText(fixture.composer, 'Send this now');
      await tester.tap(find.byTooltip('Send message'));
      await tester.pump();
      expect(h.state.chat.busy, true);
      expect(h.state.draft, isEmpty);
      expect(
        tester.widget<TextField>(fixture.composer).controller!.text,
        isEmpty,
      );
      expect(h.state.chat.messages.first.content, 'Send this now');
      await tester.enterText(fixture.composer, 'My next draft');
      h.transport.chatBytes.addError(
        const AppFailure(
          FailureKind.network,
          'Fixture disconnected',
          retryable: true,
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(h.state.chat.canRetry, true);
      expect(h.state.draft, 'My next draft');
      expect(h.state.chat.messages.first.content, 'Send this now');
      await h.dispose(tester);
    },
  );

  testWidgets(
    'edit sends a new turn and preserves original messages and composer draft',
    (tester) async {
      final h = fixture.Harness();
      await h.mount(tester, const Size(768, 1024));
      await choose(h, tester);
      h.state.chat.restoreSession(
        jsonEncode({
          'version': 1,
          'messages': [
            const ChatMessage(
              role: 'user',
              content: 'Original question',
              modelId: 'test/chat',
            ).toJson(),
            const ChatMessage(
              role: 'assistant',
              content: 'Original answer',
              modelId: 'test/chat',
            ).toJson(),
          ],
        }),
      );
      await tester.pump();
      await tester.enterText(fixture.composer, 'Unrelated draft');
      await tester.tap(find.byTooltip('Edit and resend message 1'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('edit-message')),
        'Updated question',
      );
      await tester.tap(find.text('Send as new message'));
      await tester.pumpAndSettle();
      expect(find.text('Edit and resend'), findsNothing);
      expect(h.state.chat.messages.map((m) => m.content).take(3), [
        'Original question',
        'Original answer',
        'Updated question',
      ]);
      expect(h.state.chat.messages[2].editedFrom, 0);
      expect(h.state.draft, 'Unrelated draft');
      expect(h.transport.sends, 1);
      final body = jsonDecode(h.transport.lastChatBody! as String) as Map;
      expect((body['messages'] as List).length, 3);
      expect(find.text('Edited copy of message 1'), findsOneWidget);
      await h.dispose(tester);
    },
  );

  testWidgets(
    'image selection sends multimodal parts and clears attachment draft',
    (tester) async {
      final picker = Picker();
      final h = fixture.Harness(picker: picker);
      final model = fixture.modelFixture();
      (model['architecture'] as Map)['input_modalities'] = ['text', 'image'];
      h.transport.catalogBody = {
        'data': [model],
      };
      await h.mount(tester, const Size(390, 844));
      await choose(h, tester);
      await tester.tap(find.text('Add files'));
      await tester.pumpAndSettle();
      expect(picker.calls, 1);
      expect(h.state.draftAttachments, hasLength(1));
      expect(find.byTooltip('Remove example-0.png'), findsOneWidget);
      await tester.tap(find.byTooltip('Send message'));
      await tester.pumpAndSettle();
      expect(h.state.draftAttachments, isEmpty);
      expect(h.state.chat.messages.first.attachments, hasLength(1));
      final body = jsonDecode(h.transport.lastChatBody! as String) as Map;
      final content = (body['messages'] as List).first['content'] as List;
      expect(content.last['type'], 'image_url');
      expect(
        content.last['image_url']['url'],
        startsWith('data:image/png;base64,'),
      );
      expect(h.state.diagnostics.export(), isNot(contains(png)));
      await h.dispose(tester);
    },
  );

  testWidgets(
    'text-only selection enables source files; refused sends retain draft',
    (tester) async {
      final picker = Picker();
      final h = fixture.Harness(picker: picker);
      await h.mount(tester, const Size(768, 1024));
      await choose(h, tester);
      expect(
        tester
            .widget<TextButton>(
              find.ancestor(
                of: find.text('Add files'),
                matching: find.byWidgetPredicate(
                  (widget) => widget is TextButton,
                ),
              ),
            )
            .onPressed,
        isNotNull,
      );
      h.state.setOffline(true);
      await tester.pump();
      await tester.enterText(fixture.composer, 'Keep until online');
      await tester.tap(find.byTooltip('Chat unavailable offline'));
      await tester.pump();
      expect(h.state.draft, 'Keep until online');
      expect(h.transport.sends, 0);
      expect(picker.calls, 0);
      await h.dispose(tester);
    },
  );

  testWidgets(
    'attachment composer stays usable at narrow 200 percent text and keyboard inset',
    (tester) async {
      final picker = Picker()..count = 4;
      final h = fixture.Harness(picker: picker);
      final model = fixture.modelFixture();
      (model['architecture'] as Map)['input_modalities'] = ['text', 'image'];
      h.transport.catalogBody = {
        'data': [model],
      };
      h.state.setTextScale(2);
      await h.mount(tester, const Size(320, 740));
      await choose(h, tester);
      await tester.ensureVisible(find.text('Add files'));
      await tester.tap(find.text('Add files'));
      await tester.pumpAndSettle();
      expect(h.state.draftAttachments, hasLength(4));
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(fixture.composer, findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Send message'));
      expect(
        tester.getCenter(find.byTooltip('Send message')).dy,
        lessThan(500),
      );
      await h.dispose(tester);
    },
  );
}
