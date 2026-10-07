import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/config/app_config.dart';
import 'package:wfform/features/models/health.dart';
import 'package:wfform/features/models/model.dart';
import 'package:wfform/shared/diagnostics.dart';
import 'package:wfform/shared/transport.dart';

import '../chat/fakes.dart';

void main() {
  const config = AppConfig(
    apiKey: 'test-key',
    healthTtl: Duration(minutes: 5),
    cooldown: Duration(seconds: 10),
    maxBackoff: Duration(seconds: 40),
  );
  late DateTime now;
  late Diagnostics diagnostics;
  late FakeTransport transport;
  late HealthController health;

  setUp(() {
    now = DateTime.utc(2026, 10, 5);
    diagnostics = Diagnostics(config);
    transport = FakeTransport(
      (r) => r.method == 'GET' ? endpoints() : streamResponse(delta('OK')),
    );
    health = HealthController(
      config: config,
      transport: transport,
      diagnostics: diagnostics,
      now: () => now,
    );
  });
  tearDown(() {
    health.dispose();
    diagnostics.dispose();
  });

  test(
    'no startup probes; checks only selected model and TTL avoids repeats',
    () async {
      expect(transport.requests, isEmpty);
      final observation = await health.check(testModel);
      expect(observation.status, HealthStatus.responsive);
      expect(observation.endpointSummary, contains('Test provider'));
      expect(transport.requests.length, 2);
      expect(transport.requests.last.json['messages'], [
        {'role': 'user', 'content': 'Reply OK.'},
      ]);
      await health.check(testModel);
      expect(transport.requests.length, 2);
      now = now.add(const Duration(minutes: 5));
      expect(health.isFresh(testModel.id), isFalse);
      await health.check(testModel);
      // The stale inference is rechecked; still-fresh endpoint metadata is reused.
      expect(transport.requests.length, 3);
    },
  );

  test('deduplicates concurrent checks of same model', () async {
    final gate = Completer<ApiResponse>();
    transport = FakeTransport(
      (r) => r.method == 'GET' ? gate.future : streamResponse(delta('OK')),
    );
    health.dispose();
    health = HealthController(
      config: config,
      transport: transport,
      diagnostics: diagnostics,
      now: () => now,
    );
    final first = health.check(testModel);
    final second = health.check(testModel, force: true);
    expect(identical(first, second), isTrue);
    gate.complete(endpoints());
    await Future.wait([first, second]);
    expect(transport.requests.length, 2);
  });

  test(
    'probe respects mandatory reasoning and accepts reasoning output',
    () async {
      transport = FakeTransport((request) {
        if (request.method == 'GET') return endpoints();
        final reasoning = request.json['reasoning'];
        if (reasoning is Map && reasoning['enabled'] == false) {
          return jsonResponse({
            'error': {
              'code': 400,
              'message': 'Reasoning is mandatory and cannot be disabled.',
            },
          }, status: 400);
        }
        return streamResponse(delta('', reasoning: 'Probe reasoning'));
      });
      health.dispose();
      health = HealthController(
        config: config,
        transport: transport,
        diagnostics: diagnostics,
        now: () => now,
      );
      final observation = await health.check(testModel);
      expect(observation.status, HealthStatus.responsive);
      final inference = transport.requests.where((r) => r.method == 'POST');
      expect(inference, hasLength(1));
      expect(inference.single.json.containsKey('reasoning'), isFalse);
      expect(inference.single.json['max_tokens'], 16);
      expect(inference.single.cancel!.isCancelled, isTrue);
    },
  );

  testWidgets('silent probe retains its configured deadline and cancellation', (
    tester,
  ) async {
    final source = StreamController<List<int>>();
    transport = FakeTransport(
      (request) => request.method == 'GET'
          ? endpoints()
          : ApiResponse(200, {
              'content-type': 'text/event-stream',
            }, source.stream),
    );
    health.dispose();
    health = HealthController(
      config: config,
      transport: transport,
      diagnostics: diagnostics,
      now: () => now,
    );
    final pending = health.check(testModel);
    await tester.pump();
    expect(transport.requests.where((r) => r.method == 'POST'), hasLength(1));
    await tester.pump(config.probeTimeout + const Duration(milliseconds: 1));
    final observation = await pending;
    expect(observation.failure?.kind, FailureKind.timeout);
    expect(transport.requests.last.cancel!.isCancelled, isTrue);
    expect(transport.requests.where((r) => r.method == 'POST'), hasLength(1));
    unawaited(source.close());
    await tester.pump();
  });

  test('limits concurrent selected checks to two', () async {
    final gates = <Completer<ApiResponse>>[];
    transport = FakeTransport((r) {
      if (r.method != 'GET') return streamResponse(delta('OK'));
      final gate = Completer<ApiResponse>();
      gates.add(gate);
      return gate.future;
    });
    health.dispose();
    health = HealthController(
      config: config,
      transport: transport,
      diagnostics: diagnostics,
      now: () => now,
    );
    final first = health.check(testModel);
    final second = health.check(const FreeModel(id: 'maker/two', name: 'Two'));
    final third = await health.check(
      const FreeModel(id: 'maker/three', name: 'Three'),
    );
    expect(third.failure?.message, contains('concurrency'));
    expect(gates.length, 2);
    for (final gate in gates) {
      gate.complete(endpoints());
    }
    await Future.wait([first, second]);
  });

  test('forced checks respect exponential cooldown and cap', () async {
    const failure = AppFailure(
      FailureKind.provider,
      'Provider failed',
      status: 502,
      retryable: true,
    );
    health.recordFailure(testModel.id, failure);
    expect(
      health.forModel(testModel.id).retryAt,
      now.add(const Duration(seconds: 10)),
    );
    await health.check(testModel, force: true);
    expect(transport.requests, isEmpty);
    health.recordFailure(testModel.id, failure);
    expect(
      health.forModel(testModel.id).retryAt,
      now.add(const Duration(seconds: 20)),
    );
    health.recordFailure(testModel.id, failure);
    health.recordFailure(testModel.id, failure);
    expect(
      health.forModel(testModel.id).retryAt,
      now.add(const Duration(seconds: 40)),
    );
  });

  test(
    'rate-limit Retry-After exceeds local cap and applies across models',
    () async {
      health.recordFailure(
        testModel.id,
        const AppFailure(
          FailureKind.rateLimit,
          'Limited',
          retryAfter: Duration(seconds: 90),
          retryable: true,
        ),
      );
      final observation = await health.check(
        const FreeModel(id: 'maker/two', name: 'Two'),
        force: true,
      );
      expect(observation.status, HealthStatus.rateLimited);
      expect(observation.retryAt, now.add(const Duration(seconds: 90)));
      expect(transport.requests, isEmpty);
    },
  );

  test('credentials, account and network failures are not model outages', () {
    for (final kind in [
      FailureKind.authentication,
      FailureKind.account,
      FailureKind.network,
    ]) {
      health.recordFailure(
        testModel.id,
        AppFailure(kind, 'Independent failure'),
      );
      expect(health.forModel(testModel.id).status, HealthStatus.unknown);
      expect(health.forModel(testModel.id).failure?.kind, kind);
    }
    health.recordFailure(
      testModel.id,
      const AppFailure(FailureKind.provider, 'No providers', status: 503),
    );
    expect(health.forModel(testModel.id).status, HealthStatus.unavailable);
    health.recordSuccess(testModel.id);
    expect(health.isFresh(testModel.id), isTrue);
    expect(health.forModel(testModel.id).retryAt, isNull);
  });

  test('credential cooldown is not mislabeled as a rate limit', () async {
    health.recordFailure(
      testModel.id,
      const AppFailure(FailureKind.authentication, 'Bad key'),
    );
    final observation = await health.check(testModel, force: true);
    expect(observation.status, HealthStatus.unknown);
    expect(observation.failure?.kind, FailureKind.authentication);
    expect(transport.requests, isEmpty);
  });

  test(
    'deduplicated caller can cancel without aborting another caller',
    () async {
      final gate = Completer<ApiResponse>();
      transport = FakeTransport(
        (r) => r.method == 'GET' ? gate.future : streamResponse(delta('OK')),
      );
      health.dispose();
      health = HealthController(
        config: config,
        transport: transport,
        diagnostics: diagnostics,
        now: () => now,
      );
      final original = health.check(testModel);
      final token = CancelToken();
      final second = health.check(testModel, cancel: token);
      token.cancel();
      expect((await second).failure?.kind, FailureKind.cancelled);
      gate.complete(endpoints());
      expect((await original).status, HealthStatus.responsive);
      expect(transport.requests.length, 2);
    },
  );

  test(
    'metadata does not imply responsiveness; unsuccessful probe degrades',
    () async {
      transport = FakeTransport(
        (r) => r.method == 'GET'
            ? endpoints()
            : jsonResponse({
                'error': {'code': 503},
              }, status: 503),
      );
      health.dispose();
      health = HealthController(
        config: config,
        transport: transport,
        diagnostics: diagnostics,
        now: () => now,
      );
      expect((await health.check(testModel)).status, HealthStatus.unavailable);
      expect(health.isFresh(testModel.id), isFalse);
    },
  );

  test(
    'disposing an in-flight health check avoids late diagnostic writes',
    () async {
      final gate = Completer<ApiResponse>();
      transport = FakeTransport((_) => gate.future);
      health.dispose();
      health = HealthController(
        config: config,
        transport: transport,
        diagnostics: diagnostics,
        now: () => now,
      );
      final pending = health.check(testModel);
      health.dispose();
      diagnostics.dispose();
      gate.complete(endpoints());
      await pending;
      expect(transport.requests.length, 1);
      // Give teardown fresh owners; disposed notifiers must not be disposed twice.
      diagnostics = Diagnostics(config);
      health = HealthController(
        config: config,
        transport: transport,
        diagnostics: diagnostics,
        now: () => now,
      );
    },
  );

  test(
    'offline cancellation aborts a manual inference check and starts no replacement',
    () async {
      var closed = false;
      final cancelledSource = StreamController<List<int>>(
        onCancel: () {
          closed = true;
        },
      );
      transport = FakeTransport(
        (r) => r.method == 'GET'
            ? endpoints()
            : ApiResponse(200, {
                'content-type': 'text/event-stream',
              }, cancelledSource.stream),
      );
      health.dispose();
      health = HealthController(
        config: config,
        transport: transport,
        diagnostics: diagnostics,
        now: () => now,
      );
      final pending = health.check(testModel);
      await Future<void>.delayed(Duration.zero);
      expect(transport.requests.length, 2);
      health.cancelChecks();
      final observation = await pending;
      expect(observation.failure?.kind, FailureKind.cancelled);
      expect(closed, isTrue);
      expect(transport.requests.last.cancel!.isCancelled, isTrue);
      expect(transport.requests.length, 2);
      await cancelledSource.close();
    },
  );

  test('selection cleanup preserves the original model preflight', () async {
    final gate = Completer<ApiResponse>();
    transport = FakeTransport(
      (r) => r.method == 'GET' ? gate.future : streamResponse(delta('OK')),
    );
    health.dispose();
    health = HealthController(
      config: config,
      transport: transport,
      diagnostics: diagnostics,
      now: () => now,
    );
    final pending = health.check(testModel);
    health.cancelChecks(exceptModelId: testModel.id);
    expect(transport.requests.single.cancel!.isCancelled, isFalse);
    gate.complete(endpoints());
    expect((await pending).status, HealthStatus.responsive);
  });

  test(
    'malformed endpoint metadata is diagnosed but does not block guarded probe',
    () async {
      transport = FakeTransport(
        (r) => r.method == 'GET'
            ? jsonResponse({'renamed': []})
            : streamResponse(delta('OK')),
      );
      health.dispose();
      health = HealthController(
        config: config,
        transport: transport,
        diagnostics: diagnostics,
        now: () => now,
      );
      expect((await health.check(testModel)).status, HealthStatus.responsive);
      expect(diagnostics.export(), contains(r'$.data.endpoints'));
    },
  );
}
