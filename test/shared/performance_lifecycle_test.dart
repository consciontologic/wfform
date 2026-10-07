import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/app/studio_state.dart';
import 'package:wfform/config/app_config.dart';
import 'package:wfform/features/history/history_repository.dart';
import 'package:wfform/features/history/conversation.dart';
import 'package:wfform/shared/diagnostics.dart';
import 'package:wfform/shared/platform.dart';
import 'package:wfform/shared/transport.dart';
import '../chat/fakes.dart' as net;
import '../presentation/studio_test.dart' as fixture;

class LocalPlatform extends fixture.FakePlatform {
  Completer<void>? registration;
  String? imported, exported;
  @override
  Future<void> initialize() async => registration?.future;
  @override
  Future<String?> importText({int maxBytes = 64 * 1024 * 1024}) async =>
      imported;
  @override
  void exportText(String filename, String content) => exported = content;
}

class UnavailableStorage extends MemoryHistoryRepository {
  bool fail = false;
  @override
  Future<void> save(ConversationRecord record, {bool makeActive = false}) {
    if (fail) return Future.error(historyFailure('Fixture storage is full.'));
    return super.save(record, makeActive: makeActive);
  }
}

StudioState studio(
  MemoryHistoryRepository repository, {
  LocalPlatform? platform,
  MemoryStore? recovery,
}) => StudioState(
  config: const AppConfig(apiKey: 'fixture'),
  transport: net.FakeTransport(
    (request) => net.jsonResponse({
      'data': [fixture.modelFixture()],
    }),
  ),
  store: MemoryStore(),
  recoveryStore: recovery ?? MemoryStore(),
  platform: platform ?? LocalPlatform(),
  diagnostics: Diagnostics(const AppConfig()),
  historyRepository: repository,
);

Future<void> ready(StudioState state) {
  if (!state.historyLoading) return Future.value();
  final result = Completer<void>();
  void changed() {
    if (!state.historyLoading) {
      state.removeListener(changed);
      result.complete();
    }
  }

  state.addListener(changed);
  return result.future.timeout(const Duration(seconds: 2));
}

void main() {
  test(
    'provisional and failed runtime configuration preserve durable health and quota',
    () async {
      const configured = AppConfig(apiKey: 'runtime-fixture');
      final store = MemoryStore();
      final states = <StudioState>[];
      StudioState create(AppConfig config) {
        final state = StudioState(
          config: config,
          transport: net.FakeTransport(
            (request) => request.uri.path.endsWith('/key')
                ? net.jsonResponse({
                    'data': {
                      'free_model_daily_requests': {
                        'used': 22,
                        'limit': 50,
                        'remaining': 28,
                      },
                    },
                  })
                : net.jsonResponse({
                    'data': [fixture.modelFixture()],
                  }),
          ),
          store: store,
          recoveryStore: MemoryStore(),
          platform: LocalPlatform(),
          diagnostics: Diagnostics(config),
          historyRepository: MemoryHistoryRepository(),
        );
        states.add(state);
        return state;
      }

      addTearDown(() {
        for (final state in states) {
          state.dispose();
        }
      });
      final first = create(configured);
      await first.initialize();
      final model = first.catalog.models.single;
      first.health.recordSuccess(model.id);
      await first.health.refreshQuota();
      first.health.recordFailure(
        'other/provider',
        const AppFailure(
          FailureKind.rateLimit,
          'Fixture quota cooldown',
          retryAfter: Duration(minutes: 2),
          retryable: true,
        ),
      );
      final retryAt = first.health.retryAtFor(model.id);
      final snapshot = store.read('wfform.health.v2');
      expect(snapshot, isNotNull);
      expect(retryAt, isNotNull);

      // Failed configuration must also leave the real-key cache intact, even
      // when the fallback refresh succeeds and a keyless health action fails.
      final failed = create(const AppConfig());
      await failed.initialize(
        loadConfiguration: () =>
            Future.error(StateError('Fixture config failure')),
      );
      failed.health.recordFailure(
        model.id,
        const AppFailure(FailureKind.authentication, 'A key is required'),
      );
      expect(store.read('wfform.health.v2'), snapshot);

      final restored = create(const AppConfig());
      final gate = Completer<AppConfig?>();
      final initialized = restored.initialize(
        loadConfiguration: () => gate.future,
      );
      await ready(restored);
      expect(restored.configurationLoading, isTrue);
      expect(restored.catalog.models.single.id, model.id);
      expect(store.read('wfform.health.v2'), snapshot);
      gate.complete(configured);
      await initialized;
      expect(restored.health.isFresh(model.id), isTrue);
      expect(restored.health.quota?.remaining, 28);
      expect(restored.health.retryAtFor(model.id)?.toUtc(), retryAt?.toUtc());
      final requests = (restored.transport as net.FakeTransport).requests;
      expect(requests, hasLength(1));
      expect(requests.single.uri.path, '/api/v1/models');
    },
  );

  test(
    'runtime configuration causes exactly one catalog startup request',
    () async {
      for (final delayed in [false, true]) {
        final state = studio(MemoryHistoryRepository());
        addTearDown(state.dispose);
        final transport = state.transport as net.FakeTransport;
        final gate = Completer<AppConfig?>();
        if (!delayed) gate.complete(const AppConfig(apiKey: 'runtime-fixture'));
        final initialized = state.initialize(
          loadConfiguration: () => gate.future,
        );
        if (delayed) {
          await ready(state);
          expect(transport.requests, isEmpty);
          gate.complete(const AppConfig(apiKey: 'runtime-fixture'));
        }
        await initialized;
        expect(
          transport.requests.length,
          1,
          reason: 'delayed configuration: $delayed',
        );
        expect(transport.requests.single.method, 'GET');
        expect(transport.requests.single.uri.path, '/api/v1/models');
        expect(
          state.diagnostics.events
              .where((event) => event.data['operation'] == 'catalog.refresh')
              .length,
          1,
        );
      }
    },
  );

  test(
    'local history and drafting do not wait for configuration or PWA registration',
    () async {
      final platform = LocalPlatform()..registration = Completer<void>();
      final state = studio(MemoryHistoryRepository(), platform: platform);
      addTearDown(state.dispose);
      final configuration = Completer<AppConfig?>();
      final initialized = state.initialize(
        loadConfiguration: () => configuration.future,
      );
      await ready(state);
      expect(state.configurationLoading, true);
      expect(state.historyBusy, false);
      state.setDraft('Typed before connection settings arrived');
      expect(state.draft, startsWith('Typed before'));
      configuration.complete(
        const AppConfig(apiKey: 'new-fixture', maxOutputTokens: 512),
      );
      await initialized;
      expect(state.config.maxOutputTokens, 512);
      expect(state.draft, startsWith('Typed before'));
      expect(state.configurationLoading, false);
      expect(platform.registration!.isCompleted, false);
      platform.registration!.complete();
    },
  );

  test('slow catalog cannot keep restored history read-only', () async {
    final catalog = Completer<ApiResponse>();
    final state = StudioState(
      config: const AppConfig(),
      transport: net.FakeTransport((_) => catalog.future),
      store: MemoryStore(),
      platform: LocalPlatform(),
      diagnostics: Diagnostics(const AppConfig()),
      historyRepository: MemoryHistoryRepository(),
    );
    addTearDown(state.dispose);
    final initialized = state.initialize();
    await ready(state);
    expect(state.catalog.refreshing, true);
    expect(state.historyBusy, false);
    state.setDraft('Available during refresh');
    await state.flushHistory();
    expect(state.historyStatus.value, 'Saved');
    catalog.complete(
      net.jsonResponse({
        'data': [fixture.modelFixture()],
      }),
    );
    await initialized;
    expect(state.draft, 'Available during refresh');
  });

  test(
    'conflicting tabs adopt one recovery identity and continue without overwriting',
    () async {
      final database = MemoryHistoryDatabase();
      final firstRepo = MemoryHistoryRepository(database: database);
      final secondRepo = MemoryHistoryRepository(database: database);
      final first = studio(firstRepo), second = studio(secondRepo);
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      await first.initialize();
      final original = first.activeConversationId!;
      await secondRepo.setActive(original);
      await second.initialize();
      first.setDraft('First tab version');
      await first.flushHistory();
      second.setDraft('Second tab version');
      expect(await second.flushHistory(), false);
      final recovered = second.activeConversationId!;
      expect(recovered, isNot(original));
      expect(second.conversationNotice, contains('recovered'));
      second.setDraft('Second tab continues');
      expect(await second.flushHistory(), true);
      expect(second.activeConversationId, recovered);
      expect((await firstRepo.read(original))!.draft, 'First tab version');
      expect((await secondRepo.read(recovered))!.draft, 'Second tab continues');
      expect(
        (await secondRepo.read(recovered))!.title,
        startsWith('Recovered copy · '),
      );
      expect((await secondRepo.loadIndex()).entries, hasLength(2));
    },
  );

  test(
    'draft recovery is scoped to the tab and save status does not notify appearance',
    () async {
      final store = MemoryStore();
      final state = studio(MemoryHistoryRepository(), recovery: store);
      addTearDown(state.dispose);
      await state.initialize();
      var appearanceNotifications = 0;
      state.appearance.addListener(() => appearanceNotifications++);
      state.setDraft('A scoped recovery draft');
      expect(state.historyStatus.value, 'Unsaved changes');
      expect(
        (jsonDecode(store.read('freeform.pendingDraft.v1')!) as Map)['draft'],
        state.draft,
      );
      await state.flushHistory();
      expect(state.historyStatus.value, 'Saved');
      expect(appearanceNotifications, 0);
      expect(state.store.read('freeform.draft.v1'), isNull);
    },
  );

  test(
    'export and import preserve content as a separate record and malformed import is non-destructive',
    () async {
      final platform = LocalPlatform();
      final repo = MemoryHistoryRepository();
      final state = studio(repo, platform: platform);
      addTearDown(state.dispose);
      await state.initialize();
      state.setDraft('Portable draft 🌱');
      final original = state.activeConversationId!;
      await state.exportConversation(original);
      platform.imported = platform.exported;
      expect(await state.importConversation(), true);
      expect(state.activeConversationId, isNot(original));
      expect(state.draft, 'Portable draft 🌱');
      expect((await repo.read(original))!.draft, 'Portable draft 🌱');
      final imported = state.activeConversationId;
      platform.imported = '{"broken":true}';
      expect(await state.importConversation(), false);
      expect(state.activeConversationId, imported);
      expect((await repo.loadIndex()).entries, hasLength(2));
      expect(state.draft, 'Portable draft 🌱');
    },
  );

  test('export recovers the open draft when IndexedDB saving fails', () async {
    final repository = UnavailableStorage();
    final platform = LocalPlatform();
    final state = studio(repository, platform: platform);
    addTearDown(state.dispose);
    await state.initialize();
    repository.fail = true;
    state.setDraft('Recover this unsaved work');
    await state.exportConversation(state.activeConversationId!);
    expect(state.historyError, isNotNull);
    final exported = jsonDecode(platform.exported!) as Map;
    expect((exported['conversation'] as Map)['draft'], state.draft);
  });

  test(
    'a tab recovers unsent text after its active record was deleted elsewhere',
    () async {
      final repository = MemoryHistoryRepository()..activeId = 'deleted-record';
      final recovery = MemoryStore();
      recovery.write(
        'freeform.pendingDraft.v1',
        jsonEncode({
          'id': 'deleted-record',
          'draft': 'Still needed after another tab deleted the chat',
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      final state = studio(repository, recovery: recovery);
      addTearDown(state.dispose);
      await state.initialize();
      expect(state.draft, startsWith('Still needed'));
      expect(state.activeConversationId, isNot('deleted-record'));
      expect(state.conversationNotice, contains('recovered'));
      expect(state.chat.messages, isEmpty);
      expect(state.catalog.selectedId, isNull);
      expect(
        (await repository.read(state.activeConversationId!))!.draft,
        state.draft,
      );
    },
  );
}
