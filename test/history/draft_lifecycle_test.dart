import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/features/history/conversation.dart';
import 'package:wfform/features/history/history_codec.dart';
import 'package:wfform/shared/transport.dart';

import '../chat/fakes.dart';
import 'history_state_test.dart' show HistoryHarness, secondModel;

void main() {
  test(
    'empty launch, selection and New never create indexed ghost records',
    () async {
      final h = HistoryHarness();
      addTearDown(h.state.dispose);
      await h.state.initialize();
      expect(h.state.history, isEmpty);
      expect(h.repo.records, isEmpty);
      await h.state.selectModel(testModel);
      final workspace = h.state.activeConversationId;
      await h.state.newConversation();
      await h.state.newConversation();
      expect(h.state.activeConversationId, workspace);
      expect(h.state.catalog.selectedId, testModel.id);
      expect(h.state.history, isEmpty);
      expect(h.repo.records, isEmpty);
    },
  );

  test('model drafts resume independently and survive reload', () async {
    final h = HistoryHarness();
    await h.state.initialize();
    await h.state.selectModel(testModel);
    final first = h.state.activeConversationId;
    h.state.setDraft('First draft');
    await h.state.selectModel(secondModel);
    h.state.setDraft('Second draft');
    await h.state.newConversation();
    expect(h.state.draft, 'Second draft');
    await h.state.selectModel(testModel);
    expect(h.state.activeConversationId, first);
    expect(h.state.draft, 'First draft');
    expect(h.state.history, hasLength(2));
    expect(h.state.history.every((entry) => entry.isDraft), isTrue);
    await h.state.flushHistory();
    h.state.dispose();
    final reopened = HistoryHarness(repository: h.repo, preferences: h.store);
    addTearDown(reopened.state.dispose);
    await reopened.state.initialize();
    expect(reopened.state.activeConversationId, first);
    expect(reopened.state.draft, 'First draft');
    expect(reopened.state.history.every((entry) => entry.isDraft), isTrue);
  });

  test(
    'an unindexed selected workspace restores text and model before first checkpoint',
    () async {
      final h = HistoryHarness();
      await h.state.initialize();
      await h.state.selectModel(secondModel);
      final id = h.state.activeConversationId;
      h.state.setDraft('Uncheckpointed draft');
      expect(h.repo.records, isEmpty);
      h.state.dispose();
      final reopened = HistoryHarness(repository: h.repo, preferences: h.store);
      addTearDown(reopened.state.dispose);
      await reopened.state.initialize();
      expect(reopened.state.activeConversationId, id);
      expect(reopened.state.catalog.selectedId, secondModel.id);
      expect(reopened.state.draft, 'Uncheckpointed draft');
      expect(reopened.state.history.single.isDraft, isTrue);
    },
  );

  test(
    'corrupt workspace recovery cannot mask a valid active saved record',
    () async {
      final h = HistoryHarness();
      await h.state.initialize();
      h.state.setDraft('Durable saved draft');
      await h.state.flushHistory();
      final id = h.state.activeConversationId;
      h.state.dispose();
      h.store.write('freeform.pendingDraft.v1', '{broken');
      final reopened = HistoryHarness(repository: h.repo, preferences: h.store);
      addTearDown(reopened.state.dispose);
      await reopened.state.initialize();
      expect(reopened.state.activeConversationId, id);
      expect(reopened.state.draft, 'Durable saved draft');
      expect(reopened.state.history.single.isDraft, isTrue);
    },
  );

  test('preflight busy and failed probes do not promote a draft', () async {
    final probe = Completer<ApiResponse>();
    final arrived = Completer<void>();
    final h = HistoryHarness(
      respond: (request) {
        expect(
          (request.json['messages'] as List).single['content'],
          'Reply OK.',
        );
        arrived.complete();
        return probe.future;
      },
    );
    addTearDown(h.state.dispose);
    await h.state.initialize();
    await h.state.selectModel(testModel);
    final id = h.state.activeConversationId!;
    final sending = h.state.chat.send(
      testModel,
      'Do not dispatch this content',
    );
    await arrived.future;
    await h.state.flushHistory();
    expect(h.state.isConversationResponding(id), isTrue);
    expect(h.state.history.single.isDraft, isTrue);
    probe.complete(
      jsonResponse({
        'error': {'message': 'Unavailable'},
      }, status: 503),
    );
    await sending;
    await h.state.flushHistory();
    expect(h.state.history.single.isDraft, isTrue);
    expect(h.state.chat.hasDispatchedUserContent, isFalse);
    expect(h.state.chat.messages.first.content, 'Do not dispatch this content');
    expect(h.state.isConversationResponding(id), isFalse);
  });

  test(
    'actual content dispatch promotes immediately, including HTTP failure',
    () async {
      final response = Completer<ApiResponse>();
      final arrived = Completer<void>();
      final h = HistoryHarness(
        respond: (_) {
          arrived.complete();
          return response.future;
        },
      );
      addTearDown(h.state.dispose);
      await h.state.initialize();
      await h.state.selectModel(testModel);
      h.state.health.recordSuccess(testModel.id);
      final sending = h.state.chat.send(testModel, 'Dispatched content');
      await arrived.future;
      await Future<void>.delayed(Duration.zero);
      await h.state.flushHistory();
      expect(h.state.chat.busy, isTrue);
      expect(h.state.history.single.isDraft, isFalse);
      expect(h.state.chat.hasDispatchedUserContent, isTrue);
      response.complete(
        jsonResponse({
          'error': {'message': 'Unavailable'},
        }, status: 503),
      );
      await sending;
      await h.state.flushHistory();
      final record = await h.repo.read(h.state.activeConversationId!);
      expect(record!.isDraft, isFalse);
      expect(record.sessionData['hasDispatchedUserContent'], isTrue);
    },
  );

  test(
    'archiving an active sent chat activates a writable draft and reopening is read-only',
    () async {
      final h = HistoryHarness();
      addTearDown(h.state.dispose);
      await h.state.initialize();
      await h.state.selectModel(testModel);
      h.state.health.recordSuccess(testModel.id);
      await h.state.chat.send(testModel, 'Sent conversation');
      await h.state.flushHistory();
      final sent = h.state.activeConversationId!;
      await h.state.newConversation();
      final draft = h.state.activeConversationId;
      h.state.setDraft('Continue this workspace');
      await h.state.openConversation(sent);
      expect(await h.state.archiveConversation(sent), isTrue);
      expect(h.state.activeConversationId, draft);
      expect(h.state.activeConversationArchived, isFalse);
      expect(h.state.draft, 'Continue this workspace');
      expect((await h.repo.read(sent))!.archived, isTrue);
      await h.state.openConversation(sent);
      expect(h.state.activeConversationArchived, isTrue);
      h.state.setDraft('Must not replace archived text');
      expect(h.state.draft, isEmpty);
    },
  );

  test(
    'unsent work cannot be archived or deleted through state actions',
    () async {
      final h = HistoryHarness();
      addTearDown(h.state.dispose);
      await h.state.initialize();
      h.state.setDraft('Keep unsent work');
      await h.state.flushHistory();
      final id = h.state.activeConversationId!;
      expect(await h.state.archiveConversation(id), isFalse);
      expect(await h.state.deleteConversation(id), isFalse);
      expect((await h.repo.read(id))!.draft, 'Keep unsent work');
      expect(h.state.activeConversationArchived, isFalse);
    },
  );

  test(
    'summary draft metadata is optional for legacy records and validated when present',
    () {
      final old = ConversationSummary(
        id: 'legacy',
        title: 'Legacy',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ).toJson()..remove('isDraft');
      expect(ConversationSummary.fromJson(old).isDraft, isTrue);
      old['messageCount'] = 2;
      expect(ConversationSummary.fromJson(old).isDraft, isFalse);
      old['messageCount'] = 0;
      old['archived'] = true;
      expect(ConversationSummary.fromJson(old).isDraft, isFalse);
      old['isDraft'] = true;
      expect(ConversationSummary.fromJson(old).isDraft, isTrue);
      old['isDraft'] = 'true';
      expect(
        () => ConversationSummary.fromJson(old),
        throwsA(isA<Exception>()),
      );
    },
  );

  test(
    'preflight-only session stays a draft through normalized storage and reload',
    () async {
      final h = HistoryHarness(
        respond: (_) => jsonResponse({
          'error': {'message': 'Unavailable'},
        }, status: 503),
      );
      await h.state.initialize();
      await h.state.selectModel(testModel);
      await h.state.chat.send(testModel, 'Retain this attempted turn');
      await h.state.flushHistory();
      final stored = (await h.repo.read(h.state.activeConversationId!))!;
      final packed = PackedHistoryRecord.pack(stored);
      final unpacked = PackedHistoryRecord.unpack(
        packed.document(1),
        packed.messages,
        {},
      );
      expect(unpacked.isDraft, isTrue);
      expect(unpacked.sessionData['hasDispatchedUserContent'], isFalse);
      expect(
        ConversationRecord.fromJson(
          jsonDecode(jsonEncode(unpacked.toJson())),
        ).isDraft,
        isTrue,
      );
      h.state.dispose();
      final reopened = HistoryHarness(repository: h.repo, preferences: h.store);
      addTearDown(reopened.state.dispose);
      await reopened.state.initialize();
      expect(reopened.state.chat.hasDispatchedUserContent, isFalse);
      expect(reopened.state.history.single.isDraft, isTrue);
      expect(
        reopened.state.chat.messages.first.content,
        'Retain this attempted turn',
      );
      expect(reopened.state.chat.canRetry, isTrue);
    },
  );

  test(
    'legacy archived empty records remain inspectable, restorable and deletable',
    () async {
      final h = HistoryHarness();
      addTearDown(h.state.dispose);
      final legacy = ConversationRecord(
        id: 'archived-legacy',
        title: 'Old archived workspace',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        archived: true,
        draft: 'An older unsent draft',
        session: '{"version":1,"messages":[]}',
      ).toJson()..remove('isDraft');
      h.repo.records['archived-legacy'] = jsonEncode(legacy);
      await h.state.initialize();
      expect(h.state.history.single.isDraft, isFalse);
      expect(await h.state.openConversation('archived-legacy'), isTrue);
      expect(h.state.activeConversationArchived, isTrue);
      expect(h.state.draft, 'An older unsent draft');
      expect(await h.state.restoreConversation('archived-legacy'), isTrue);
      expect(h.state.activeConversationArchived, isFalse);
      await h.state.flushHistory();
      expect(h.state.history.single.isDraft, isFalse);
      expect(await h.state.archiveConversation('archived-legacy'), isTrue);
      expect(h.state.activeConversationArchived, isFalse);
      expect(await h.state.deleteConversation('archived-legacy'), isTrue);
      expect(h.repo.records.containsKey('archived-legacy'), isFalse);
    },
  );
}
