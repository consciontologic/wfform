import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/features/history/conversation.dart';
import 'package:wfform/shared/diagnostics.dart';

import '../chat/fakes.dart';
import 'archived_delete_test.dart' show DeleteRepository, seededHistory;
import 'history_state_test.dart' show HistoryHarness, secondModel;

class SavingDeleteRepository extends DeleteRepository {
  Completer<void>? saveGate;
  @override
  Future<void> save(
    ConversationRecord record, {
    bool makeActive = false,
  }) async {
    await saveGate?.future;
    await super.save(record, makeActive: makeActive);
  }
}

void main() {
  test(
    'active draft deletion removes text/files and cannot recover on reload',
    () async {
      final h = await seededHistory();
      h.state.setDraft('Latest unsaved text');
      h.state.attachmentError = const AppFailure(
        FailureKind.configuration,
        'Fixture incompatible attachment',
      );
      expect(h.state.draftAttachments, isNotEmpty);
      expect(await h.state.deleteConversation('active'), isTrue);
      expect(h.state.activeConversationId, isNot('active'));
      expect(h.state.draft, isEmpty);
      expect(h.state.draftAttachments, isEmpty);
      expect(h.state.attachmentError, isNull);
      expect(await h.repo.read('active'), isNull);
      expect(await h.state.flushHistory(), isTrue);
      h.state.dispose();
      final reopened = HistoryHarness(repository: h.repo, preferences: h.store);
      addTearDown(reopened.state.dispose);
      await reopened.initialize();
      expect(reopened.state.draft, isEmpty);
      expect(reopened.state.draftAttachments, isEmpty);
      expect(
        reopened.state.history.any((entry) => entry.id == 'active'),
        isFalse,
      );
      reopened.state.setDraft('New writable work');
      expect(await reopened.state.flushHistory(), isTrue);
      expect(
        (await h.repo.read(reopened.state.activeConversationId!))!.draft,
        'New writable work',
      );
    },
  );

  test(
    'active deletion waits for save and rejects checkpoints until committed',
    () async {
      final repo = SavingDeleteRepository();
      final h = await seededHistory(repository: repo);
      addTearDown(h.state.dispose);
      repo.saveGate = Completer<void>();
      repo.deleteGate = Completer<void>();
      h.state.setDraft('A checkpoint in flight');
      final saving = h.state.flushHistory();
      final deleting = h.state.deleteConversation('active');
      final duplicate = h.state.deleteConversation('active');
      expect(identical(deleting, duplicate), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(repo.deletedIds, isEmpty);
      repo.saveGate!.complete();
      expect(await saving, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(repo.deletedIds, ['active']);
      expect(await h.state.flushHistory(), isFalse);
      h.state.setDraft('Must not replace work being deleted');
      expect(h.state.draft, 'A checkpoint in flight');
      repo.deleteGate!.complete();
      expect(await deleting, isTrue);
      expect(await h.state.flushHistory(), isTrue);
      expect(await repo.read('active'), isNull);
    },
  );

  test(
    'failed draft deletion preserves current text and attachments for retry',
    () async {
      final repo = DeleteRepository()..failDelete = true;
      final h = await seededHistory(repository: repo);
      addTearDown(h.state.dispose);
      h.state.setDraft('Latest work survives failure');
      expect(await h.state.deleteConversation('active'), isFalse);
      expect(h.state.activeConversationId, 'active');
      expect(h.state.draft, 'Latest work survives failure');
      expect(h.state.draftAttachments.single.id, 'keep-file');
      expect(await repo.read('active'), isNotNull);
      expect(h.state.historyError, isNotNull);
      repo.failDelete = false;
      expect(await h.state.deleteConversation('active'), isTrue);
      expect(h.state.historyError, isNull);
      expect(h.state.draftAttachments, isEmpty);
    },
  );

  test('model selection never resumes a draft with deletion pending', () async {
    final repo = DeleteRepository()..deleteGate = Completer<void>();
    await repo.save(
      ConversationRecord(
        id: 'target',
        title: 'Delete this draft',
        modelId: secondModel.id,
        modelName: secondModel.name,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        draft: 'Old target work',
        session: '{"version":1,"messages":[]}',
      ),
    );
    final h = HistoryHarness(repository: repo);
    addTearDown(h.state.dispose);
    await h.initialize();
    await h.state.selectModel(testModel);
    final source = h.state.activeConversationId;
    final deleting = h.state.deleteConversation('target');
    expect(await h.state.selectModel(secondModel), isTrue);
    expect(h.state.activeConversationId, source);
    expect(h.state.activeConversationId, isNot('target'));
    h.state.setDraft('Keep composing while another draft is deleted');
    expect(await h.state.flushHistory(), isTrue);
    repo.deleteGate!.complete();
    expect(await deleting, isTrue);
    expect(h.state.draft, 'Keep composing while another draft is deleted');
    expect(await repo.read('target'), isNull);
    expect(h.state.activeConversationId, source);
  });
}
