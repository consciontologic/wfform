import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/config/app_config.dart';
import 'package:wfform/features/models/health.dart';
import 'package:wfform/features/models/model.dart';
import 'package:wfform/shared/diagnostics.dart';
import 'package:wfform/shared/platform.dart';
import 'package:wfform/shared/transport.dart';
import '../chat/fakes.dart';

void main() {
  const config = AppConfig(apiKey: 'fixture-key');
  late DateTime now;
  late MemoryStore store;
  late Diagnostics diagnostics;
  late FakeTransport transport;
  final controllers = <HealthController>[];
  HealthController create({AppConfig settings = config}) {
    final controller = HealthController(
      config: settings,
      transport: transport,
      diagnostics: diagnostics,
      store: store,
      now: () => now,
    );
    controllers.add(controller);
    return controller;
  }

  setUp(() {
    now = DateTime.utc(2026, 10, 6, 12);
    store = MemoryStore();
    diagnostics = Diagnostics(config);
    transport = FakeTransport(
      (r) => r.method == 'GET' ? endpoints() : streamResponse(delta('OK')),
    );
  });
  tearDown(() {
    for (final controller in controllers) {
      controller.dispose();
    }
    controllers.clear();
    diagnostics.dispose();
  });

  test(
    'fresh health survives reload, expired health probes with separately fresh endpoints',
    () async {
      final first = create();
      await first.check(testModel);
      expect(transport.requests.length, 2);
      final second = create();
      second.reconcileModels([testModel]);
      expect(second.isFresh(testModel.id), isTrue);
      await second.check(testModel);
      expect(transport.requests.length, 2);
      now = now.add(const Duration(minutes: 6));
      final third = create();
      await third.check(testModel);
      expect(transport.requests.length, 3);
      expect(transport.requests.last.method, 'POST');
    },
  );

  test(
    'account cooldown persists and configuration or model changes invalidate observations',
    () async {
      final first = create();
      first.reconcileModels([testModel]);
      first.recordSuccess(testModel.id);
      first.recordFailure(
        testModel.id,
        const AppFailure(
          FailureKind.rateLimit,
          'Limited',
          retryAfter: Duration(minutes: 2),
          retryable: true,
        ),
      );
      final second = create();
      expect(
        second.retryAtFor('another/model'),
        now.add(const Duration(minutes: 2)),
      );
      expect(second.admissionFailure(testModel)?.kind, FailureKind.rateLimit);
      final changedKey = create(
        settings: config.copyWith(apiKey: 'another-key'),
      );
      expect(changedKey.retryAtFor(testModel.id), isNull);
      expect(changedKey.isFresh(testModel.id), isFalse);
      now = now.add(const Duration(minutes: 3));
      first.recordSuccess(testModel.id);
      final changedModel = create();
      changedModel.reconcileModels([
        FreeModel(id: testModel.id, name: 'Changed', contextLength: 123),
      ]);
      expect(changedModel.isFresh(testModel.id), isFalse);
    },
  );

  test('clock rollback never restores a future fresh observation', () async {
    final first = create();
    await first.check(testModel);
    now = now.subtract(const Duration(minutes: 1));
    expect(create().isFresh(testModel.id), isFalse);
  });

  test(
    'quota deduplicates and caches documented optional counters without startup calls',
    () async {
      final gate = Completer<ApiResponse>();
      transport = FakeTransport((r) {
        expect(r.uri.path.endsWith('/key'), isTrue);
        return gate.future;
      });
      final health = create();
      expect(transport.requests, isEmpty);
      final first = health.refreshQuota(),
          second = health.refreshQuota(force: true);
      gate.complete(
        jsonResponse({
          'data': {
            'free_model_daily_requests': {
              'used': 7,
              'limit': 50,
              'remaining': 43,
            },
            'new_field': true,
          },
        }),
      );
      await Future.wait([first, second]);
      expect(transport.requests.length, 1);
      expect(health.quota?.remaining, 43);
      expect(health.quotaStale, isFalse);
      await health.refreshQuota();
      expect(transport.requests.length, 1);
      expect(create().quota?.used, 7);
      now = now.add(const Duration(minutes: 6));
      expect(health.quotaStale, isTrue);
    },
  );

  test(
    'bad quota refresh retains last valid counters and reports path',
    () async {
      var invalid = false;
      transport = FakeTransport(
        (_) => jsonResponse({
          'data': {
            'free_model_daily_requests': {
              'used': 4,
              'limit': 50,
              'remaining': invalid ? 'unknown' : 46,
            },
          },
        }),
      );
      final health = create();
      await health.refreshQuota();
      invalid = true;
      await health.refreshQuota(force: true);
      expect(health.quota?.remaining, 46);
      expect(
        health.quotaError?.field,
        r'$.data.free_model_daily_requests.remaining',
      );
    },
  );

  test(
    'missing quota counters remain unknown and zero advisory quota never fabricates cooldown',
    () async {
      transport = FakeTransport(
        (_) => jsonResponse({
          'data': {'is_free_tier': false},
        }),
      );
      final health = create();
      await health.refreshQuota();
      expect(health.quota?.remaining, isNull);
      expect(health.quotaError, isNull);
      transport = FakeTransport(
        (_) => jsonResponse({
          'data': {
            'free_model_daily_requests': {
              'used': 50,
              'limit': 50,
              'remaining': 0,
            },
          },
        }),
      );
      final zero = create();
      await zero.refreshQuota(force: true);
      expect(zero.quota?.remaining, 0);
      expect(zero.admissionFailure(testModel), isNull);
    },
  );

  test(
    'platform response headers supply a persisted absolute reset without guessing malformed values',
    () {
      final health = create();
      final reset = now.add(const Duration(minutes: 1));
      health.recordResponseHeaders(testModel.id, {
        'x-ratelimit-remaining': '0',
        'x-ratelimit-limit': '20',
        'x-ratelimit-reset': '${reset.millisecondsSinceEpoch ~/ 1000}',
      });
      expect(health.retryAtFor(testModel.id), reset);
      expect(create().retryAtFor('other/model'), reset);
      expect(rateLimitReset('20'), isNull);
      expect(rateLimitReset('nonsense'), isNull);
    },
  );

  test(
    'actual modality outcomes persist separately and account failures stay unknown',
    () async {
      final health = create();
      await health.check(testModel);
      health.recordModalityResult(testModel.id, ['image'], provider: 'Test');
      health.recordModalityResult(testModel.id, [
        'audio',
      ], failure: const AppFailure(FailureKind.account, 'Account'));
      final restored = create();
      expect(
        restored.modalityObservations(testModel.id)['image']?.status,
        HealthStatus.responsive,
      );
      expect(
        restored.modalityObservations(testModel.id)['audio']?.status,
        HealthStatus.unknown,
      );
      expect(
        restored.modalityObservations(testModel.id).containsKey('video'),
        isFalse,
      );
    },
  );

  test(
    'quota rate-limit cooldown survives reload and explicit recheck respects it',
    () async {
      transport = FakeTransport(
        (_) => jsonResponse(
          {
            'error': {'code': 429},
          },
          status: 429,
          headers: {'retry-after': '90'},
        ),
      );
      final health = create();
      await health.refreshQuota();
      expect(health.quotaRetryAt, now.add(const Duration(seconds: 90)));
      await health.refreshQuota(force: true);
      final restored = create();
      await restored.refreshQuota(force: true);
      expect(transport.requests.length, 1);
      expect(restored.quotaError?.kind, FailureKind.rateLimit);
    },
  );
}
