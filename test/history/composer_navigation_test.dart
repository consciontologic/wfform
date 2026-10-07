import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/features/history/conversation.dart';
import 'package:wfform/features/history/history_repository.dart';
import 'package:wfform/shared/diagnostics.dart';

import 'attachment_history_test.dart'
    show AttachmentHarness, QuotaRepository, imageModel, otherModel, pngData;

ConversationRecord destinationDraft() => ConversationRecord(
  id: 'saved-destination-draft',
  title: 'Previous destination draft',
  modelId: otherModel.id,
  modelName: otherModel.name,
  createdAt: DateTime.utc(2026, 10, 7),
  updatedAt: DateTime.utc(2026, 10, 7),
  draft: 'Do not replace the destination draft',
  isDraft: true,
  session: jsonEncode({'version': 1, 'messages': []}),
);

void seedSentTurn(AttachmentHarness h, {bool dispatched = true}) {
  expect(
    h.state.chat.restoreSession(
      jsonEncode({
        'version': 1,
        'hasDispatchedUserContent': dispatched,
        'messages': [
          {
            'role': 'user',
            'content': 'Previously dispatched fixture turn',
            'reasoning': '',
            'modelId': imageModel.id,
            'complete': true,
          },
        ],
      }),
    ),
    isTrue,
  );
}

void main() {
  test('text and files follow model changes and survive reload', () async {
    final h = AttachmentHarness();
    await h.initialize();
    h.state.setDraft('Keep this unsent composition 🌿');
    await h.pick();
    final id = h.state.activeConversationId;
    final fileId = h.state.draftAttachments.single.id;
    expect(await h.state.selectModel(otherModel), isTrue);
    expect(h.state.catalog.selectedId, otherModel.id);
    expect(h.state.draft, 'Keep this unsent composition 🌿');
    expect(h.state.activeConversationId, id);
    expect(h.state.draftAttachments.single.id, fileId);
    expect(h.state.draftAttachments.single.base64Data, pngData);
    expect(h.state.history, hasLength(1));
    expect(h.state.history.single.isDraft, isTrue);
    expect(otherModel.acceptsImages, isFalse);
    h.state.dispose();
    final restored = AttachmentHarness(
      repository: h.repository,
      preferences: h.preferences,
    );
    addTearDown(restored.state.dispose);
    await restored.initialize();
    expect(restored.state.activeConversationId, id);
    expect(restored.state.catalog.selectedId, otherModel.id);
    expect(restored.state.draft, 'Keep this unsent composition 🌿');
    expect(restored.state.draftAttachments.single.id, fileId);
    expect(restored.state.draftAttachments.single.base64Data, pngData);
    expect(await restored.state.selectModel(imageModel), isTrue);
    expect(restored.state.draftAttachments.single.id, fileId);
    expect(restored.transport.requests.every((r) => r.method == 'GET'), isTrue);
  });

  test(
    'switching a draft never overwrites an existing destination draft',
    () async {
      final repository = MemoryHistoryRepository();
      await repository.save(destinationDraft());
      final h = AttachmentHarness(repository: repository);
      addTearDown(h.state.dispose);
      await h.initialize();
      h.state.setDraft('Current composition takes the selected model');
      await h.pick();
      final id = h.state.activeConversationId;
      expect(await h.state.selectModel(otherModel), isTrue);
      expect(h.state.draft, 'Current composition takes the selected model');
      expect(h.state.activeConversationId, id);
      expect(h.state.draftAttachments, hasLength(1));
      expect(
        (await repository.read(destinationDraft().id))!.draft,
        destinationDraft().draft,
      );
      expect(h.state.history, hasLength(2));
    },
  );

  test(
    'sent history stays bound while the current composition follows a new model',
    () async {
      final repository = MemoryHistoryRepository();
      await repository.save(destinationDraft());
      final h = AttachmentHarness(repository: repository);
      addTearDown(h.state.dispose);
      await h.initialize();
      seedSentTurn(h);
      h.state.setDraft('Next unsent question');
      await h.pick();
      final original = h.state.activeConversationId!;
      final fileId = h.state.draftAttachments.single.id;
      expect(await h.state.selectModel(otherModel), isTrue);
      expect(h.state.activeConversationId, isNot(original));
      expect(h.state.activeConversationId, isNot(destinationDraft().id));
      expect(h.state.draft, 'Next unsent question');
      expect(h.state.draftAttachments.single.id, fileId);
      expect(h.state.chat.messages, isEmpty);
      final previous = (await repository.read(original))!;
      expect(previous.modelId, imageModel.id);
      expect(previous.sessionData['messages'], hasLength(1));
      expect(previous.draft, 'Next unsent question');
      expect(previous.draftAttachments.single.id, fileId);
      expect(
        (await repository.read(destinationDraft().id))!.draft,
        destinationDraft().draft,
      );
      expect(h.transport.requests.every((r) => r.method == 'GET'), isTrue);
    },
  );

  test(
    'accepted preflight failures keep their original model and draft history',
    () async {
      final h = AttachmentHarness();
      addTearDown(h.state.dispose);
      await h.initialize();
      seedSentTurn(h, dispatched: false);
      h.state.setDraft('A newer composer draft');
      await h.pick();
      final original = h.state.activeConversationId!;
      expect(await h.state.selectModel(otherModel), isTrue);
      expect(h.state.activeConversationId, isNot(original));
      expect(h.state.draft, 'A newer composer draft');
      expect(h.state.draftAttachments, hasLength(1));
      expect(h.state.chat.messages, isEmpty);
      final previous = (await h.repository.read(original))!;
      expect(previous.isDraft, isTrue);
      expect(previous.modelId, imageModel.id);
      expect(previous.sessionData['messages'], hasLength(1));
      expect(h.transport.requests.every((r) => r.method == 'GET'), isTrue);
    },
  );

  test(
    'archived composer is not carried or described as current composition',
    () async {
      final repository = MemoryHistoryRepository();
      await repository.save(destinationDraft());
      final h = AttachmentHarness(repository: repository);
      addTearDown(h.state.dispose);
      await h.initialize();
      seedSentTurn(h);
      h.state.setDraft('Read-only archived composer');
      await h.state.flushHistory();
      final original = h.state.activeConversationId!;
      expect(await h.state.archiveConversation(original), isTrue);
      expect(await h.state.openConversation(original), isTrue);
      expect(await h.state.selectModel(otherModel), isTrue);
      expect(h.state.activeConversationId, destinationDraft().id);
      expect(h.state.draft, destinationDraft().draft);
      expect(h.state.conversationNotice, isNot(contains('followed')));
      expect(
        (await repository.read(original))!.draft,
        'Read-only archived composer',
      );
    },
  );

  test(
    'preparing same-tab navigation commits text and files for return',
    () async {
      final h = AttachmentHarness();
      await h.initialize();
      await h.pick();
      h.state.setDraft('Latest text before About');
      final id = h.state.activeConversationId;
      expect(await h.state.prepareToLeave(), isTrue);
      expect(h.state.historyBusy, isFalse);
      h.state.dispose();
      final returned = AttachmentHarness(
        repository: h.repository,
        preferences: h.preferences,
      );
      addTearDown(returned.state.dispose);
      await returned.initialize();
      expect(returned.state.activeConversationId, id);
      expect(returned.state.draft, 'Latest text before About');
      expect(returned.state.draftAttachments.single.base64Data, pngData);
    },
  );

  test(
    'failed navigation checkpoint preserves composition and unlocks retry',
    () async {
      final repository = QuotaRepository();
      final h = AttachmentHarness(repository: repository);
      addTearDown(h.state.dispose);
      await h.initialize();
      await h.pick();
      h.state.setDraft('Retain despite failed save');
      repository.fail = true;
      expect(await h.state.prepareToLeave(), isFalse);
      expect(h.state.historyBusy, isFalse);
      expect(h.state.historyError?.kind, FailureKind.storage);
      expect(h.state.draft, 'Retain despite failed save');
      expect(h.state.draftAttachments.single.base64Data, pngData);
      repository.fail = false;
      expect(await h.state.prepareToLeave(), isTrue);
    },
  );

  test(
    'page navigation refuses active response and attachment picking',
    () async {
      final h = AttachmentHarness();
      addTearDown(h.state.dispose);
      await h.initialize();
      h.state.chat.busy = true;
      expect(await h.state.prepareToLeave(), isFalse);
      expect(h.state.conversationNotice, contains('Finish or cancel'));
      h.state.chat.busy = false;
      h.picker.gate = Completer();
      final picking = h.pick();
      expect(await h.state.prepareToLeave(), isFalse);
      expect(h.state.conversationNotice, contains('adding files'));
      h.picker.gate!.complete(h.picker.files);
      await picking;
      expect(h.state.draftAttachments, hasLength(1));
      expect(await h.state.prepareToLeave(), isTrue);
    },
  );
}
