import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/app/studio_state.dart';
import 'package:wfform/config/app_config.dart';
import 'package:wfform/features/history/history_repository.dart';
import 'package:wfform/features/models/health.dart';
import 'package:wfform/shared/diagnostics.dart';
import 'package:wfform/shared/platform.dart';
import 'package:wfform/shared/transport.dart';

import '../presentation/studio_test.dart'
    show modelFixture, jsonResponse, FakePlatform;

void main() {
  test(
    'safe update during an actual pending preflight does not persist or activate',
    () async {
      final h = LifecycleHarness();
      addTearDown(h.state.dispose);
      await h.initialize();
      h.state.setDraft('Keep my draft');
      final sending = h.state.chat.send(
        h.state.catalog.selected!,
        'Pending user content',
      );
      await h.transport.endpointStarted.future;
      expect(h.state.chat.busy, isTrue);
      await h.state.applyUpdate();
      expect(h.platform.applied, 0);
      expect(h.memory.read('freeform.updateSession.v1'), isNull);
      expect(
        (jsonDecode(h.memory.read('freeform.pendingDraft.v1')!)
            as Map)['draft'],
        'Keep my draft',
      );
      h.state.chat.cancel();
      await sending;
      expect(h.state.chat.error?.kind, FailureKind.cancelled);
      expect(h.transport.postCalls, 0);
    },
  );

  test(
    'safe update commits history before activation without legacy duplicate snapshots',
    () async {
      final h = LifecycleHarness();
      addTearDown(h.state.dispose);
      await h.initialize();
      h.state.setDraft('A draft with 🌿 Unicode');
      h.state.chat.restoreSession(conversationFixture());
      String? savedDraft;
      String? savedSession;
      h.platform.onApply = () {
        savedDraft =
            (jsonDecode(h.memory.read('freeform.pendingDraft.v1')!)
                    as Map)['draft']
                as String;
        savedSession =
            (jsonDecode(h.repository.records[h.state.activeConversationId]!)
                    as Map)['session']
                as String;
      };
      final originalId = h.state.activeConversationId;
      await h.state.applyUpdate();
      expect(h.platform.applied, 1);
      expect(savedDraft, 'A draft with 🌿 Unicode');
      final payload = jsonDecode(savedSession!) as Map;
      expect(payload['messages'], hasLength(2));
      expect(
        (payload['messages'] as List).last['reasoning'],
        'Fixture reasoning',
      );

      expect(h.memory.read('freeform.updateSession.v1'), isNull);
      expect(h.memory.read('freeform.draft.v1'), isNull);
      final restored = LifecycleHarness(
        memory: h.memory,
        repository: h.repository,
      );
      addTearDown(restored.state.dispose);
      await restored.state.initialize();
      expect(restored.state.draft, 'A draft with 🌿 Unicode');
      expect(restored.state.activeConversationId, originalId);
      expect(restored.state.catalog.selectedId, 'test/chat');
      expect(restored.state.chat.messages.last.content, 'Fixture answer');
      expect(restored.state.chat.messages.last.reasoning, 'Fixture reasoning');
      expect(restored.state.chat.busy, isFalse);
      expect(restored.transport.postCalls, 0);
      expect(
        h.memory.read('freeform.updateSession.v1'),
        isNull,
        reason:
            'Reload recovery is consumed rather than replayed on every launch.',
      );
    },
  );

  test(
    'quota failure during update blocks activation and retains in-memory recovery',
    () async {
      final memory = ToggleStore();
      final h = LifecycleHarness(memory: memory);
      addTearDown(h.state.dispose);
      await h.initialize();
      h.state.setDraft('Draft before storage fills');
      h.state.chat.restoreSession(conversationFixture());
      memory.failWrites = true;
      await h.state.applyUpdate();
      await Future<void>.delayed(Duration.zero);
      expect(h.platform.applied, 0);
      expect(h.state.store.persistenceAvailable, isFalse);
      expect(h.state.updateError, contains('Update paused'));
      expect(h.state.draft, 'Draft before storage fills');
      expect(h.state.chat.messages.last.content, 'Fixture answer');
      expect(
        (jsonDecode(
              h.state.recoveryStore.fallback.read('freeform.pendingDraft.v1')!,
            )
            as Map)['draft'],
        'Draft before storage fills',
      );
      expect(
        h.state.diagnostics.events.where(
          (event) => event.toJson()['kind'] == FailureKind.storage.name,
        ),
        hasLength(1),
      );
    },
  );

  test(
    'storage blocked from bootstrap prevents a later unsafe update',
    () async {
      final memory = ToggleStore()
        ..failReads = true
        ..failWrites = true;
      final h = LifecycleHarness(memory: memory);
      addTearDown(h.state.dispose);
      h.state.setDraft('Draft kept in this session');
      h.state.chat.restoreSession(conversationFixture());
      await h.state.applyUpdate();
      await Future<void>.delayed(Duration.zero);
      expect(h.platform.applied, 0);
      expect(h.state.store.persistenceAvailable, isFalse);
      expect(
        (jsonDecode(h.state.recoveryStore.read('freeform.pendingDraft.v1')!)
            as Map)['draft'],
        'Draft kept in this session',
      );
      expect(h.state.chat.messages, hasLength(2));
    },
  );

  for (final offlineSource in ['browser signal', 'Work offline control']) {
    test(
      '$offlineSource cancels manual health checks without starting inference',
      () async {
        final h = LifecycleHarness();
        addTearDown(h.state.dispose);
        await h.initialize();
        final checking = h.state.health.check(
          h.state.catalog.selected!,
          force: true,
        );
        await h.transport.endpointStarted.future;
        expect(
          h.state.health.forModel('test/chat').status,
          HealthStatus.checking,
        );
        if (offlineSource == 'browser signal') {
          h.platform.setOnline(false);
        } else {
          h.state.setOffline(true);
        }
        final observation = await checking;
        expect(h.state.online, isFalse);
        expect(h.transport.endpointToken!.isCancelled, isTrue);
        expect(observation.failure?.kind, FailureKind.cancelled);
        expect(h.transport.postCalls, 0);
        expect(h.state.catalog.selectedId, 'test/chat');
      },
    );
  }

  for (final change in ['disappeared', 'paid', 'incompatible']) {
    test(
      'selection $change during async preflight cancels before user content POST',
      () async {
        final h = LifecycleHarness();
        addTearDown(h.state.dispose);
        await h.initialize();
        h.state.setDraft('Preserve this draft');
        final sending = h.state.chat.send(
          h.state.catalog.selected!,
          'Protected user content',
        );
        await h.transport.endpointStarted.future;
        final changed = modelFixture();
        if (change == 'paid') {
          changed['pricing'] = {
            'prompt': '0.0001',
            'completion': '0',
            'request': '0',
          };
        } else if (change == 'incompatible') {
          changed['architecture'] = {
            'input_modalities': ['text'],
            'output_modalities': ['embeddings'],
          };
        }
        h.transport.catalogBody = {
          'data': change == 'disappeared' ? [] : [changed],
        };
        await h.state.catalog.refresh();
        await sending;
        expect(h.state.catalog.selected, isNull);
        expect(h.state.catalog.selectionNotice, isNotNull);
        expect(h.transport.endpointToken!.isCancelled, isTrue);
        expect(h.transport.postCalls, 0);
        expect(h.state.chat.busy, isFalse);
        expect(h.state.chat.error?.kind, FailureKind.cancelled);
        expect(h.state.chat.messages.first.content, 'Protected user content');
        expect(h.state.draft, 'Preserve this draft');
      },
    );
  }
}

String conversationFixture() => jsonEncode({
  'version': 1,
  'messages': [
    {
      'role': 'user',
      'content': 'Fixture question',
      'reasoning': '',
      'modelId': 'test/chat',
      'complete': true,
    },
    {
      'role': 'assistant',
      'content': 'Fixture answer',
      'reasoning': 'Fixture reasoning',
      'modelId': 'test/chat',
      'complete': true,
    },
  ],
  'retryUserIndex': null,
  'retryModelId': null,
});

class LifecycleHarness {
  LifecycleHarness({MemoryStore? memory, MemoryHistoryRepository? repository})
    : memory = memory ?? MemoryStore(),
      repository = repository ?? MemoryHistoryRepository() {
    state = StudioState(
      config: config,
      transport: transport,
      store: this.memory,
      platform: platform,
      diagnostics: Diagnostics(config),
      historyRepository: this.repository,
    );
  }
  static const config = AppConfig(apiKey: 'fixture-only');
  final MemoryStore memory;
  final MemoryHistoryRepository repository;
  final platform = ObservedPlatform();
  final transport = LifecycleTransport();
  late final StudioState state;

  Future<void> initialize() async {
    await state.initialize();
    state.catalog.select('test/chat');
  }
}

class ObservedPlatform extends FakePlatform {
  void Function()? onApply;
  @override
  Future<void> applyUpdate() async {
    onApply?.call();
    await super.applyUpdate();
  }
}

class ToggleStore extends MemoryStore {
  bool failReads = false;
  bool failWrites = false;
  @override
  String? read(String key) {
    if (failReads) throw StateError('Fixture storage unavailable');
    return super.read(key);
  }

  @override
  void write(String key, String value) {
    if (failWrites) throw StateError('Fixture quota exceeded');
    super.write(key, value);
  }
}

class LifecycleTransport implements ApiTransport {
  Object catalogBody = {
    'data': [modelFixture()],
  };
  final endpointStarted = Completer<void>();
  final endpointResponse = Completer<ApiResponse>();
  CancelToken? endpointToken;
  int postCalls = 0;

  @override
  Future<ApiResponse> send(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    Object? body,
    required Duration timeout,
    CancelToken? cancel,
  }) async {
    if (method == 'GET' && uri.path.endsWith('/endpoints')) {
      endpointToken = cancel;
      if (!endpointStarted.isCompleted) endpointStarted.complete();
      return Future.any([
        endpointResponse.future,
        cancel!.whenCancelled.then<ApiResponse>((_) {
          cancel.throwIfCancelled();
          throw StateError('Cancellation fixture was not cancelled');
        }),
      ]);
    }
    if (method == 'GET') return jsonResponse(catalogBody);
    postCalls++;
    throw StateError(
      'No inference request should occur in these lifecycle fixtures',
    );
  }
}
