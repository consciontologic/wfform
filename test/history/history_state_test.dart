import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/app/studio_state.dart';
import 'package:wfform/config/app_config.dart';
import 'package:wfform/features/history/conversation.dart';
import 'package:wfform/features/history/history_codec.dart';
import 'package:wfform/features/history/history_repository.dart';
import 'package:wfform/features/models/model.dart';
import 'package:wfform/presentation/history_browser.dart';
import 'package:wfform/shared/diagnostics.dart';
import 'package:wfform/shared/platform.dart';
import 'package:wfform/shared/transport.dart';

import '../chat/fakes.dart';

const secondModel = FreeModel(id: 'maker/second', name: 'Second');
const config = AppConfig(apiKey: 'fixture');

class HistoryHarness {
  HistoryHarness({
    MemoryHistoryRepository? repository,
    MemoryStore? preferences,
    FutureOr<ApiResponse> Function(SentRequest)? respond,
  }) {
    repo = repository ?? MemoryHistoryRepository();
    store = preferences ?? MemoryStore();
    transport = FakeTransport(
      (request) => request.method == 'GET'
          ? jsonResponse({
              'data': [testModel.toJson(), secondModel.toJson()],
            })
          : respond?.call(request) ??
                streamResponse('${delta('Answer')}data: [DONE]\n\n'),
    );
    state = StudioState(
      config: config,
      transport: transport,
      store: store,
      platform: createPlatformBridge(),
      diagnostics: Diagnostics(config),
      historyRepository: repo,
    );
  }
  late final MemoryHistoryRepository repo;
  late final MemoryStore store;
  late final FakeTransport transport;
  late final StudioState state;
  Future<void> initialize() async {
    await state.initialize();
    if (state.catalog.selected == null && state.activeConversationId == null) {
      await state.selectModel(testModel);
    }
  }
}

class FailingRepository extends MemoryHistoryRepository {
  bool fail = false;
  @override
  Future<void> save(ConversationRecord record, {bool makeActive = false}) {
    if (fail) {
      return Future.error(
        historyFailure('Fixture quota exceeded. Retry saving.'),
      );
    }
    return super.save(record, makeActive: makeActive);
  }
}

class GatedRepository extends MemoryHistoryRepository {
  Completer<void>? gate;
  @override
  Future<void> save(
    ConversationRecord record, {
    bool makeActive = false,
  }) async {
    await gate?.future;
    await super.save(record, makeActive: makeActive);
  }
}

/// Reproduces normalized IndexedDB reconstruction order without browser state.
class NormalizedReadRepository extends MemoryHistoryRepository {
  @override
  Future<ConversationRecord?> read(String id) async {
    final record = await super.read(id);
    if (record == null) return null;
    final packed = PackedHistoryRecord.pack(record);
    return PackedHistoryRecord.unpack(packed.document(1), packed.messages, {
      for (final entry in packed.attachments.entries)
        entry.key: base64Decode(entry.value.base64Data),
    });
  }
}

class ReadFailRepository extends MemoryHistoryRepository {
  bool failReads = true;
  @override
  Future<ConversationRecord?> read(String id) {
    if (failReads) {
      return Future.error(historyFailure('Fixture read timed out.'));
    }
    return super.read(id);
  }
}

void main() {
  test(
    'explicit settings on a blank composer persist as a draft across reload',
    () async {
      for (final parametersOnly in [true, false]) {
        final h = HistoryHarness();
        await h.initialize();
        final id = h.state.activeConversationId;
        if (parametersOnly) {
          expect(
            h.state.chat.setRequestParameters({
              'temperature': 0,
              'logprobs': false,
            }),
            true,
          );
        } else {
          expect(h.state.chat.setEnabledTools({'fixture_read'}), true);
        }
        expect(h.state.draft, isEmpty);
        expect(h.state.chat.messages, isEmpty);
        expect(await h.state.flushHistory(), true);
        expect(h.repo.records, hasLength(1));
        expect(h.state.history.single.isDraft, true);
        h.state.dispose();

        final restored = HistoryHarness(
          repository: h.repo,
          preferences: h.store,
        );
        addTearDown(restored.state.dispose);
        await restored.initialize();
        expect(restored.state.activeConversationId, id);
        expect(
          restored.state.chat.requestParameters,
          parametersOnly ? {'temperature': 0, 'logprobs': false} : isEmpty,
        );
        expect(
          restored.state.chat.enabledTools,
          parametersOnly ? isEmpty : {'fixture_read'},
        );
        expect(restored.state.toolConnections.registry.connections, isEmpty);
        expect(
          restored.transport.requests.every(
            (request) => request.method == 'GET',
          ),
          true,
        );
        expect(restored.state.draft, isEmpty);
        expect(restored.state.history.single.isDraft, true);
      }
    },
  );

  testWidgets('failed startup read offers row recovery, not a no-op save', (
    tester,
  ) async {
    final repository = ReadFailRepository();
    await repository.save(
      ConversationRecord(
        id: 'saved',
        title: 'Saved conversation',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        draft: 'Durable original draft',
        session: '{"version":1,"messages":[]}',
      ),
      makeActive: true,
    );
    final h = HistoryHarness(repository: repository);
    addTearDown(h.state.dispose);
    await h.state.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ConversationHistory(state: h.state)),
      ),
    );
    expect(h.state.historyError, isNotNull);
    expect(h.state.historyStatus.value, 'Save failed');
    expect(find.text('Retry saving'), findsNothing);
    expect(
      find.textContaining('Open a saved conversation from history'),
      findsOneWidget,
    );
    repository.failReads = false;
    await tester.tap(find.widgetWithText(ChoiceChip, 'Drafts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saved conversation'));
    await tester.pumpAndSettle();
    expect(h.state.historyError, isNull);
    expect(h.state.historyStatus.value, 'Saved');
    expect(h.state.draft, 'Durable original draft');
    expect(repository.records, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a failed dirty checkpoint keeps an effective save retry', (
    tester,
  ) async {
    final repository = FailingRepository();
    final h = HistoryHarness(repository: repository);
    addTearDown(h.state.dispose);
    await h.state.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ConversationHistory(state: h.state)),
      ),
    );
    repository.fail = true;
    h.state.setDraft('New unsaved draft');
    expect(await h.state.flushHistory(), false);
    await tester.pump();
    expect(find.text('Retry saving'), findsOneWidget);
    repository.fail = false;
    await tester.tap(find.text('Retry saving'));
    await tester.pumpAndSettle();
    expect(h.state.historyError, isNull);
    expect(h.state.historyStatus.value, 'Saved');
    expect(
      (await repository.read(h.state.activeConversationId!))!.draft,
      'New unsaved draft',
    );
    expect(find.text('Retry saving'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'newer tab recovery text commits before startup reports Saved',
    () async {
      final repository = MemoryHistoryRepository();
      await repository.save(
        ConversationRecord(
          id: 'saved',
          title: 'Saved conversation',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
          draft: 'Older durable draft',
          session: '{"version":1,"messages":[]}',
        ),
        makeActive: true,
      );
      final preferences = MemoryStore();
      preferences.write(
        'freeform.pendingDraft.v1',
        jsonEncode({
          'id': 'saved',
          'draft': 'Recovered newer text',
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      final h = HistoryHarness(
        repository: repository,
        preferences: preferences,
      );
      addTearDown(h.state.dispose);
      await h.initialize();
      expect(h.state.activeConversationId, 'saved');
      expect(h.state.historyStatus.value, 'Saved');
      expect((await repository.read('saved'))!.draft, 'Recovered newer text');
      expect(repository.records, hasLength(1));
    },
  );

  test(
    'model-less draft keeps identity through normalized safe update and repeated reloads',
    () async {
      final repository = NormalizedReadRepository();
      var h = HistoryHarness(repository: repository);
      await h.initialize();
      expect(h.state.catalog.selected, isNull);
      h.state.setDraft('Model-less draft survives update');
      await h.state.flushHistory();
      final id = h.state.activeConversationId;
      final store = h.store;
      await h.state.applyUpdate();
      expect(store.read('freeform.updateSession.v1'), isNull);
      expect(store.read('freeform.draft.v1'), isNull);
      h.state.dispose();
      for (var reload = 0; reload < 2; reload++) {
        h = HistoryHarness(repository: repository, preferences: store);
        await h.initialize();
        expect(h.state.activeConversationId, id);
        expect(h.state.draft, 'Model-less draft survives update');
        expect(h.state.catalog.selected, isNull);
        expect(h.state.history, hasLength(1));
        expect(repository.records, hasLength(1));
        h.state.dispose();
      }
    },
  );

  test(
    'equivalent legacy update ignores JSON key order and optional session defaults',
    () async {
      final repository = NormalizedReadRepository();
      final h = HistoryHarness(repository: repository);
      await h.initialize();
      h.state.setDraft('Same saved model-less draft');
      await h.state.flushHistory();
      final id = h.state.activeConversationId!;
      final legacy = h.state.chat.exportSessionData()
        ..remove('contextStartIndex');
      final legacyJson = jsonEncode(legacy);
      expect(legacyJson, isNot((await repository.read(id))!.session));
      h.store.write('freeform.updateSession.v1', legacyJson);
      h.store.write('freeform.draft.v1', h.state.draft);
      h.state.dispose();
      final restored = HistoryHarness(
        repository: repository,
        preferences: h.store,
      );
      addTearDown(restored.state.dispose);
      await restored.initialize();
      expect(restored.state.activeConversationId, id);
      expect(restored.state.draft, 'Same saved model-less draft');
      expect(restored.state.history, hasLength(1));
      expect(repository.records, hasLength(1));
      expect(h.store.read('freeform.updateSession.v1'), isNull);
    },
  );

  test(
    'overlapping opens are refused while the departing conversation commits',
    () async {
      final repository = GatedRepository();
      final h = HistoryHarness(repository: repository);
      addTearDown(h.state.dispose);
      await h.initialize();
      await h.state.selectModel(testModel);
      final first = h.state.activeConversationId!;
      h.state.setDraft('First saved draft');
      await h.state.flushHistory();
      await repository.save(
        (await repository.read(first))!.copyWith(
          id: 'separate-departing-draft',
          modelId: secondModel.id,
          modelName: secondModel.name,
          draft: '',
        ),
      );
      await h.state.openConversation('separate-departing-draft');
      final second = h.state.activeConversationId!;
      h.state.setDraft('Second departing draft');
      repository.gate = Completer<void>();
      final opening = h.state.openConversation(first);
      expect(h.state.historyBusy, isTrue);
      expect(await h.state.openConversation(second), isFalse);
      h.state.setDraft('An edit forbidden during navigation');
      expect(h.state.draft, 'Second departing draft');
      repository.gate!.complete();
      expect(await opening, isTrue);
      expect(h.state.activeConversationId, first);
      expect(h.state.draft, 'First saved draft');
      expect((await repository.read(second))!.draft, 'Second departing draft');
    },
  );

  test(
    'explicit deletion waits for an in-flight save and cannot be resurrected by it',
    () async {
      final repository = GatedRepository();
      final h = HistoryHarness(repository: repository);
      addTearDown(h.state.dispose);
      await h.initialize();
      await h.state.selectModel(testModel);
      h.state.health.recordSuccess(testModel.id);
      await h.state.chat.send(testModel, 'A sent conversation to delete');
      await h.state.flushHistory();
      final id = h.state.activeConversationId!;
      h.state.setDraft('Deleting this draft deliberately');
      repository.gate = Completer<void>();
      final saving = h.state.flushHistory();
      final deleting = h.state.deleteConversation(id);
      repository.gate!.complete();
      expect(await saving, isTrue);
      expect(await deleting, isTrue);
      expect(await repository.read(id), isNull);
      expect(h.state.history.where((entry) => entry.id == id), isEmpty);
      expect(h.state.activeConversationId, isNot(id));
      expect(h.state.draft, isEmpty);
      final recovery =
          jsonDecode(h.state.recoveryStore.read('freeform.pendingDraft.v1')!)
              as Map<String, dynamic>;
      expect(recovery['id'], h.state.activeConversationId);
      expect(recovery['draft'], isEmpty);
    },
  );

  test(
    'model changes retain sent history and carry the current composer',
    () async {
      final h = HistoryHarness();
      addTearDown(h.state.dispose);
      await h.initialize();
      expect(await h.state.selectModel(testModel), isTrue);
      final originalId = h.state.activeConversationId!;
      expect(
        h.state.chat.restoreSession(
          jsonEncode({
            'version': 1,
            'messages': [
              {
                'role': 'user',
                'content': 'Find this saved draft',
                'reasoning': '',
                'complete': true,
                'modelId': testModel.id,
              },
            ],
          }),
        ),
        isTrue,
      );
      h.state.setDraft('Find this saved draft');
      expect(await h.state.selectModel(secondModel), isTrue);
      final secondId = h.state.activeConversationId!;
      expect(secondId, isNot(originalId));
      expect(h.state.draft, 'Find this saved draft');
      expect((await h.repo.read(originalId))!.draft, 'Find this saved draft');
      expect((await h.repo.read(originalId))!.title, 'Find this saved draft');
      h.state.setDraft('Second draft');
      expect(await h.state.openConversation(originalId), isTrue);
      expect(h.state.catalog.selectedId, testModel.id);
      expect(h.state.draft, 'Find this saved draft');
      expect((await h.repo.read(secondId))!.draft, 'Second draft');
      expect(h.transport.requests.where((r) => r.method == 'POST'), isEmpty);
    },
  );

  test(
    'archive opens read-only, restore re-enables it, delete is explicit',
    () async {
      final h = HistoryHarness();
      addTearDown(h.state.dispose);
      await h.initialize();
      await h.state.selectModel(testModel);
      final id = h.state.activeConversationId!;
      h.state.health.recordSuccess(testModel.id);
      await h.state.chat.send(testModel, 'A sent conversation to archive');
      await h.state.flushHistory();
      final sentRequests = h.transport.requests
          .where((r) => r.method == 'POST')
          .length;
      h.state.setDraft('Archived draft');
      expect(await h.state.archiveConversation(id), isTrue);
      expect(h.state.activeConversationArchived, isFalse);
      expect(h.state.activeConversationId, isNot(id));
      expect(await h.state.openConversation(id), isTrue);
      expect(h.state.activeConversationArchived, isTrue);
      h.state.setDraft('Must not overwrite archived data');
      expect(h.state.draft, 'Archived draft');
      await h.state.chat.send(testModel, 'Should refuse');
      expect(
        h.transport.requests.where((r) => r.method == 'POST').length,
        sentRequests,
      );
      expect(await h.state.restoreConversation(id), isTrue);
      expect(h.state.activeConversationArchived, isFalse);
      expect(await h.state.deleteConversation(id), isTrue);
      expect(await h.repo.read(id), isNull);
      expect(h.state.chat.messages, isEmpty);
      expect(h.state.draft, isEmpty);
    },
  );

  test(
    'failed partial and next draft survive reload without sending inference',
    () async {
      final h = HistoryHarness(
        respond: (_) => streamResponse(delta('Partial answer')),
      );
      await h.initialize();
      await h.state.selectModel(testModel);
      h.state.health.recordSuccess(testModel.id);
      h.state.setDraft('Preserved composer');
      await h.state.chat.send(testModel, 'Question');
      await h.state.flushHistory();
      final id = h.state.activeConversationId;
      h.state.dispose();
      final restored = HistoryHarness(repository: h.repo, preferences: h.store);
      addTearDown(restored.state.dispose);
      await restored.initialize();
      expect(restored.state.activeConversationId, id);
      expect(restored.state.catalog.selectedId, testModel.id);
      expect(restored.state.draft, 'Preserved composer');
      expect(restored.state.chat.messages.last.content, 'Partial answer');
      expect(
        restored.state.chat.messages.last.failure?.kind,
        FailureKind.stream,
      );
      expect(restored.state.chat.canRetry, isTrue);
      expect(
        restored.transport.requests.where((r) => r.method == 'POST'),
        isEmpty,
      );
    },
  );

  test(
    'latest draft survives reload before throttled database save and is ID scoped',
    () async {
      final h = HistoryHarness();
      await h.initialize();
      await h.state.selectModel(testModel);
      final original = h.state.activeConversationId!;
      h.state.setDraft('Earlier checkpoint');
      await h.state.flushHistory();
      final writes = h.repo.writes;
      h.state.setDraft('Latest character 🌿');
      expect(h.repo.writes, writes);
      h.state.dispose();
      final restored = HistoryHarness(repository: h.repo, preferences: h.store);
      addTearDown(restored.state.dispose);
      await restored.initialize();
      expect(restored.state.activeConversationId, original);
      expect(restored.state.draft, 'Latest character 🌿');
      await h.repo.save(
        (await h.repo.read(original))!.copyWith(
          id: 'other-conversation',
          modelId: secondModel.id,
          modelName: secondModel.name,
          draft: '',
        ),
      );
      await restored.state.openConversation('other-conversation');
      final other = restored.state.activeConversationId!;
      expect(other, isNot(original));
      expect(restored.state.draft, isEmpty);
    },
  );

  test(
    'save failure retains old content and refuses destructive navigation, then retries',
    () async {
      final repository = FailingRepository();
      final h = HistoryHarness(repository: repository);
      addTearDown(h.state.dispose);
      await h.initialize();
      await h.state.selectModel(testModel);
      final id = h.state.activeConversationId;
      h.state.setDraft('Unsaved content');
      repository.fail = true;
      expect(await h.state.newConversation(), isFalse);
      expect(h.state.activeConversationId, id);
      expect(h.state.draft, 'Unsaved content');
      expect(h.state.historyError?.kind, FailureKind.storage);
      repository.fail = false;
      expect(await h.state.flushHistory(), isTrue);
      expect((await repository.read(id!))!.draft, 'Unsaved content');
      expect(h.state.historyError, isNull);
    },
  );

  test(
    'busy chat refuses switching and completion flushes without per-token writes',
    () async {
      final source = StreamController<List<int>>();
      final h = HistoryHarness(
        respond: (_) => ApiResponse(200, {
          'content-type': 'text/event-stream',
        }, source.stream),
      );
      addTearDown(h.state.dispose);
      await h.initialize();
      await h.state.selectModel(testModel);
      h.state.health.recordSuccess(testModel.id);
      final id = h.state.activeConversationId;
      final before = h.repo.writes;
      final pending = h.state.chat.send(testModel, 'Question');
      await Future<void>.delayed(Duration.zero);
      expect(
        h.repo.writes,
        before + 2,
      ); // Accepted draft, then content dispatch.
      expect((await h.repo.read(id!))!.session, contains('Question'));
      for (var i = 0; i < 10; i++) {
        source.add(utf8.encode(delta('x')));
      }
      await Future<void>.delayed(Duration.zero);
      expect(h.repo.writes, before + 2);
      expect(await h.state.selectModel(secondModel), isFalse);
      expect(await h.state.newConversation(), isFalse);
      expect(h.state.activeConversationId, id);
      source.add(utf8.encode('data: [DONE]\n\n'));
      await source.close();
      await pending;
      await h.state.flushHistory();
      expect((await h.repo.read(id))!.session, contains('xxxxxxxxxx'));
      expect(h.repo.writes - before, 3); // One final completion checkpoint.
    },
  );

  test(
    'unavailable historical model clears selection instead of substituting another',
    () async {
      final h = HistoryHarness();
      addTearDown(h.state.dispose);
      await h.initialize();
      await h.state.selectModel(testModel);
      final id = h.state.activeConversationId!;
      expect(
        h.state.chat.restoreSession(
          jsonEncode({
            'version': 1,
            'messages': [
              {
                'role': 'user',
                'content': 'Historical turn',
                'reasoning': '',
                'complete': true,
                'modelId': testModel.id,
              },
            ],
          }),
        ),
        isTrue,
      );
      h.state.setDraft('Keep original');
      await h.state.selectModel(secondModel);
      h.state.catalog.models = [secondModel];
      expect(await h.state.openConversation(id), isTrue);
      expect(h.state.catalog.selectedId, isNull);
      expect(h.state.draft, 'Keep original');
      expect(h.state.conversationNotice, contains('unavailable'));
      expect(h.transport.requests.where((r) => r.method == 'POST'), isEmpty);
    },
  );

  test(
    'different legacy update snapshot preserves both records and restores recovered content',
    () async {
      final h = HistoryHarness();
      await h.initialize();
      await h.state.selectModel(testModel);
      h.state.setDraft('Existing saved draft');
      await h.state.flushHistory();
      final originalId = h.state.activeConversationId!;
      h.store.write(
        'freeform.updateSession.v1',
        jsonEncode({
          'version': 1,
          'messages': [
            {
              'role': 'user',
              'content': 'Recovered question',
              'reasoning': '',
              'modelId': testModel.id,
              'complete': true,
            },
          ],
          'retryUserIndex': null,
          'retryModelId': null,
        }),
      );
      h.store.write('freeform.draft.v1', 'Recovered update draft');
      h.state.dispose();
      final restored = HistoryHarness(repository: h.repo, preferences: h.store);
      addTearDown(restored.state.dispose);
      await restored.initialize();
      expect(restored.state.activeConversationId, isNot(originalId));
      expect(restored.state.chat.messages.single.content, 'Recovered question');
      expect(restored.state.draft, 'Recovered update draft');
      expect((await h.repo.read(originalId))!.draft, 'Existing saved draft');
      expect(h.store.read('freeform.updateSession.v1'), isNull);
    },
  );

  test(
    'theme preference persists without changing active conversation or draft',
    () async {
      final h = HistoryHarness();
      addTearDown(h.state.dispose);
      await h.initialize();
      final id = h.state.activeConversationId;
      h.state.setDraft('Theme must not reset me');
      h.state.setThemeMode(ThemeMode.dark);
      expect(h.store.read('freeform.themeMode'), 'dark');
      expect(h.state.activeConversationId, id);
      expect(h.state.draft, 'Theme must not reset me');
    },
  );
}
