import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/features/chat/chat_controller.dart';
import 'package:wfform/presentation/brand_mark.dart';
import 'package:wfform/shared/attachment_picker.dart';
import 'package:wfform/shared/diagnostics.dart';
import 'package:wfform/shared/transport.dart';

import 'studio_test.dart' as fixture;

const png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/RZkAAAAASUVORK5CYII=';

class Picker implements AttachmentPicker {
  int calls = 0;
  int count = 1;
  bool waitForCancel = false;
  CancelToken? activeToken;
  @override
  Future<List<PickedAttachmentFile>> pick({
    required Set<String> allowedMimeTypes,
    int existingCount = 0,
    int existingBytes = 0,
    CancelToken? cancel,
  }) async {
    calls++;
    activeToken = cancel;
    if (waitForCancel) {
      await cancel!.whenCancelled;
      cancel.throwIfCancelled();
    }
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
  setUpAll(fixture.loadAppFonts);
  for (final size in [
    const Size(320, 740),
    const Size(390, 844),
    const Size(820, 1180),
    const Size(1440, 1000),
  ]) {
    testWidgets('composer actions use one compact ordered row at $size', (
      tester,
    ) async {
      final h = fixture.Harness();
      await h.mount(tester, size);
      await choose(h, tester);
      await tester.pumpAndSettle();
      final attachments = find.ancestor(
        of: find.byWidgetPredicate(
          (widget) =>
              widget is BrandIcon && widget.glyph == BrandGlyph.documents,
        ),
        matching: find.byWidgetPredicate((widget) => widget is TextButton),
      );
      final actions = [
        for (final label in ['Context', 'Parameters', 'Tools'])
          find.ancestor(
            of: find.text(label),
            matching: find.byWidgetPredicate((widget) => widget is TextButton),
          ),
        attachments,
      ];
      final bounds = actions.map(tester.getRect).toList();
      final editor = tester.getRect(fixture.composer);
      for (var i = 0; i < bounds.length; i++) {
        expect(bounds[i].center.dy, closeTo(bounds.first.center.dy, .1));
        expect(bounds[i].height, greaterThanOrEqualTo(48));
        expect(bounds[i].left, greaterThanOrEqualTo(editor.left));
        expect(bounds[i].right, lessThanOrEqualTo(editor.right));
        expect(actions[i].hitTestable(), findsOneWidget);
        if (i > 0) {
          expect(bounds[i].left, greaterThanOrEqualTo(bounds[i - 1].right));
        }
      }
      expect(bounds.last.bottom - editor.bottom, lessThanOrEqualTo(48));
      expect(
        find.descendant(of: attachments, matching: find.text('Attachments')),
        findsOneWidget,
      );
      if (size.width <= 820) {
        expect(
          h.state.chat.setRequestParameters({
            'temperature': .2,
            'max_tokens': 1000,
          }),
          isTrue,
        );
        expect(
          h.state.chat.setEnabledTools({
            for (var i = 0; i < 64; i++) 'tool_$i',
          }),
          isTrue,
        );
        await tester.pumpAndSettle();
        for (var i = 0; i < actions.length; i++) {
          expect(tester.getRect(actions[i]), bounds[i]);
          expect(actions[i].hitTestable(), findsOneWidget);
        }
        expect(find.byTooltip('2 parameter overrides'), findsOneWidget);
        expect(find.byTooltip('64 enabled tools'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await h.dispose(tester);
    });
  }

  testWidgets('large composer labels scroll in one row and all actions work', (
    tester,
  ) async {
    final picker = Picker();
    final h = fixture.Harness(picker: picker);
    final model = fixture.modelFixture();
    (model['architecture'] as Map)['input_modalities'] = ['text', 'image'];
    h.transport.catalogBody = {
      'data': [model],
    };
    h.state.setTextScale(2);
    await h.mount(tester, const Size(320, 740));
    await choose(h, tester);
    await tester.enterText(fixture.composer, 'Keep this draft');
    await tester.pumpAndSettle();
    final labels = ['Context', 'Parameters', 'Tools', 'Attachments'];
    final top = tester.getCenter(find.text(labels.first)).dy;
    for (final label in labels) {
      final text = find.text(label);
      expect(tester.getCenter(text).dy, closeTo(top, .1));
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: text, matching: find.byType(RichText)),
      );
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(paragraph.textScaler.scale(11), 22);
      await tester.ensureVisible(text);
      await tester.pumpAndSettle();
      expect(text.hitTestable(), findsOneWidget);
      await tester.tap(text);
      await tester.pumpAndSettle();
      switch (label) {
        case 'Context':
          expect(find.text('Conversation context'), findsOneWidget);
          await tester.tap(find.text('Cancel'));
        case 'Parameters':
          expect(
            find.descendant(
              of: find.byType(Dialog),
              matching: find.text('Parameters'),
            ),
            findsOneWidget,
          );
          await tester.tap(find.text('Cancel'));
        case 'Tools':
          expect(find.text('Tools & connections'), findsOneWidget);
          await tester.tap(find.byTooltip('Close tools'));
        case 'Attachments':
          expect(picker.calls, 1);
          expect(h.state.draftAttachments, hasLength(1));
      }
      await tester.pumpAndSettle();
      expect(h.state.draft, 'Keep this draft');
      expect(tester.takeException(), isNull);
    }
    await h.dispose(tester);
  });

  testWidgets('compact attachments action keeps cancellation and draft state', (
    tester,
  ) async {
    final picker = Picker()..waitForCancel = true;
    final h = fixture.Harness(picker: picker);
    final model = fixture.modelFixture();
    (model['architecture'] as Map)['input_modalities'] = ['text', 'image'];
    h.transport.catalogBody = {
      'data': [model],
    };
    await h.mount(tester, const Size(320, 740));
    await choose(h, tester);
    await tester.enterText(fixture.composer, 'Keep my unsent text');
    await tester.tap(find.text('Attachments'));
    await tester.pumpAndSettle();
    expect(h.state.attachmentPicking, isTrue);
    final cancel = find.text('Cancel attachments');
    expect(
      tester.getCenter(cancel).dy,
      tester.getCenter(find.text('Context')).dy,
    );
    await tester.ensureVisible(cancel);
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(picker.activeToken!.isCancelled, isTrue);
    expect(h.state.attachmentPicking, isFalse);
    expect(h.state.draftAttachments, isEmpty);
    expect(h.state.attachmentError, isNull);
    expect(h.state.draft, 'Keep my unsent text');
    expect(find.text('Attachments'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await h.dispose(tester);
  });

  for (final hasSentMessages in [false, true]) {
    testWidgets(
      'model dropdown preserves visible text and file from ${hasSentMessages ? 'a sent chat' : 'an unsent workspace'}',
      (tester) async {
        final picker = Picker();
        final h = fixture.Harness(picker: picker);
        final first = fixture.modelFixture();
        final second = fixture.modelFixture(
          id: 'test/second-image',
          name: 'Second Image Model',
        );
        for (final model in [first, second]) {
          (model['architecture'] as Map)['input_modalities'] = [
            'text',
            'image',
          ];
        }
        h.transport.catalogBody = {
          'data': [first, second],
        };
        await h.mount(
          tester,
          hasSentMessages ? const Size(1440, 1000) : const Size(390, 844),
        );
        await choose(h, tester);
        if (hasSentMessages) {
          h.state.chat.restoreSession(
            jsonEncode({
              'version': 1,
              'messages': [
                const ChatMessage(
                  role: 'user',
                  content: 'Earlier question',
                  modelId: 'test/chat',
                ).toJson(),
                const ChatMessage(
                  role: 'assistant',
                  content: 'Earlier reply',
                  modelId: 'test/chat',
                ).toJson(),
              ],
            }),
          );
          await tester.pumpAndSettle();
        }
        await tester.enterText(fixture.composer, 'Compare this image with me');
        await tester.tap(find.text('Attachments'));
        await tester.pumpAndSettle();
        await h.state.flushHistory();
        final originalId = h.state.activeConversationId;
        final attachment = h.state.draftAttachments.single;
        expect(find.byTooltip('Remove example-0.png'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('model-selector')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Second Image Model'));
        await tester.pumpAndSettle();

        expect(h.state.catalog.selectedId, 'test/second-image');
        expect(
          h.state.activeConversationId,
          hasSentMessages ? isNot(originalId) : originalId,
        );
        expect(h.state.chat.messages, isEmpty);
        expect(h.state.draft, 'Compare this image with me');
        expect(
          tester.widget<TextField>(fixture.composer).controller!.text,
          'Compare this image with me',
        );
        expect(find.byTooltip('Remove example-0.png'), findsOneWidget);
        expect(find.text('example-0.png · 1 KB'), findsOneWidget);
        expect(h.state.draftAttachments.single.id, attachment.id);
        expect(h.state.draftAttachments.single.base64Data, png);
        expect(picker.calls, 1);
        expect(h.transport.sends, 0);
        if (hasSentMessages) {
          expect(await h.state.openConversation(originalId!), isTrue);
          await tester.pumpAndSettle();
          expect(h.state.chat.messages.map((message) => message.content), [
            'Earlier question',
            'Earlier reply',
          ]);
          expect(
            h.state.chat.messages.every((m) => m.modelId == 'test/chat'),
            isTrue,
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

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
      await tester.tap(find.text('Attachments'));
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
                of: find.text('Attachments'),
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
      await tester.ensureVisible(find.text('Attachments'));
      await tester.tap(find.text('Attachments'));
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
