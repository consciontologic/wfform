import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:wfform/config/app_config.dart';
import 'package:wfform/shared/diagnostics.dart';
import 'package:wfform/shared/transport.dart';

TypeMatcher<AppFailure> failureOf(FailureKind kind) =>
    isA<AppFailure>().having((failure) => failure.kind, 'kind', kind);

void main() {
  group('configuration', () {
    test(
      'defaults validate and unrelated additions remain forward compatible',
      () {
        expect(const AppConfig().validate(), isEmpty);
        final config = AppConfig.fromJson({
          'apiBaseUrl': 'https://example.test/api///',
          'futureServerHint': {'ignored': true},
        });
        expect(config.apiBaseUrl, 'https://example.test/api');
        expect(config.requestTimeout, const Duration(seconds: 90));
        expect(config.apiKey, isEmpty);
      },
    );

    test('typed JSON settings preserve all policies when changing a key', () {
      final config = AppConfig.fromJson({
        'apiKey': 'development-only',
        'requestTimeoutSeconds': 40,
        'probeTimeoutSeconds': 10,
        'healthTtlSeconds': 120,
        'cooldownSeconds': 8,
        'maxBackoffSeconds': 64,
        'cacheTtlSeconds': 3600,
        'maxDiagnostics': 20,
        'maxDetailChars': 200,
        'maxMessages': 18,
        'maxResponseChars': 5000,
        'maxCatalogBytes': 12000,
        'firstResponseTimeoutSeconds': 20,
        'streamIdleTimeoutSeconds': 12,
        'streamOverallTimeoutSeconds': 100,
        'endpointTtlSeconds': 600,
        'quotaTtlSeconds': 60,
        'maxOutputTokens': 4096,
      });
      final updated = config.copyWith(apiKey: 'replacement');
      expect(updated.apiKey, 'replacement');
      expect(updated.requestTimeout, const Duration(seconds: 40));
      expect(updated.probeTimeout, const Duration(seconds: 10));
      expect(updated.healthTtl, const Duration(seconds: 120));
      expect(updated.cooldown, const Duration(seconds: 8));
      expect(updated.maxBackoff, const Duration(seconds: 64));
      expect(updated.cacheTtl, const Duration(hours: 1));
      expect(updated.maxDiagnostics, 20);
      expect(updated.maxDetailChars, 200);
      expect(updated.maxMessages, 18);
      expect(updated.maxResponseChars, 5000);
      expect(updated.maxCatalogBytes, 12000);
      expect(updated.firstResponseTimeout, const Duration(seconds: 20));
      expect(updated.streamIdleTimeout, const Duration(seconds: 12));
      expect(updated.streamOverallTimeout, const Duration(seconds: 100));
      expect(updated.endpointTtl, const Duration(minutes: 10));
      expect(updated.quotaTtl, const Duration(minutes: 1));
      expect(updated.maxOutputTokens, 4096);
    });

    test(
      'rejects wrong types rather than coercing malformed configuration',
      () {
        for (final input in <Map<String, dynamic>>[
          {'apiBaseUrl': 3},
          {'apiKey': null},
          {'requestTimeoutSeconds': '20'},
          {'maxMessages': 20.5},
          {'healthTtlSeconds': 0},
          {'cooldownSeconds': 50, 'maxBackoffSeconds': 10},
          {'maxDiagnostics': 1001},
          {'maxDetailChars': 99},
          {'maxResponseChars': 1000001},
          {'maxCatalogBytes': 1023},
          {'firstResponseTimeoutSeconds': '10'},
          {'streamIdleTimeoutSeconds': 0},
          {'streamOverallTimeoutSeconds': 2},
          {'maxOutputTokens': 15},
          {'maxOutputTokens': 32769},
        ]) {
          expect(
            () => AppConfig.fromJson(input),
            throwsFormatException,
            reason: input.keys.singleOrNull ?? input.keys.join(','),
          );
        }
      },
    );

    test('accepts HTTPS and local HTTP, rejects unsafe endpoint forms', () {
      for (final url in [
        'https://example.test/api',
        'http://localhost:8080/api',
        'http://127.0.0.1/api',
        'http://[::1]:8000/api',
      ]) {
        expect(AppConfig(apiBaseUrl: url).validate(), isEmpty, reason: url);
      }
      for (final url in [
        'http://remote.test/api',
        'file:///api',
        'https://user:pass@example.test',
        'https://example.test?key=value',
        'https://example.test#fragment',
        '',
      ]) {
        expect(AppConfig(apiBaseUrl: url).validate(), isNotEmpty, reason: url);
      }
      expect(const AppConfig(apiKey: 'line\nbreak').validate(), isNotEmpty);
    });

    test('duration upper bound is exactly thirty days', () {
      expect(const AppConfig(cacheTtl: Duration(days: 30)).validate(), isEmpty);
      expect(
        const AppConfig(cacheTtl: Duration(days: 30, seconds: 1)).validate(),
        isNotEmpty,
      );
    });
  });

  group('failure classification', () {
    test(
      'HTTP status separates credentials, account, limits and providers',
      () {
        final cases = <int, FailureKind>{
          401: FailureKind.authentication,
          403: FailureKind.authentication,
          402: FailureKind.account,
          429: FailureKind.rateLimit,
          404: FailureKind.provider,
          500: FailureKind.provider,
          502: FailureKind.provider,
          503: FailureKind.provider,
          408: FailureKind.timeout,
          504: FailureKind.timeout,
          400: FailureKind.http,
          422: FailureKind.http,
        };
        for (final entry in cases.entries) {
          final error = AppFailure.http(entry.key);
          expect(error.kind, entry.value, reason: '${entry.key}');
          expect(error.status, entry.key);
        }
        expect(AppFailure.http(401).retryable, isFalse);
        expect(AppFailure.http(402).retryable, isFalse);
        expect(AppFailure.http(429).retryable, isTrue);
      },
    );

    test(
      'HTTP-200 envelopes retain real HTTP status and effective error kind',
      () {
        final error = AppFailure.http(
          200,
          body: jsonEncode({
            'error': {
              'code': '429',
              'message': 'private prompt echoed by provider',
              'metadata': {
                'provider_name': 'Fixture provider',
                'raw': 'private response',
              },
            },
          }),
          headers: {'retry-after': '17', 'x-request-id': 'req-fixture'},
        );
        expect(error.kind, FailureKind.rateLimit);
        expect(error.status, 200);
        expect(error.retryAfter, const Duration(seconds: 17));
        expect(error.provider, 'Fixture provider');
        expect(error.requestId, 'req-fixture');
        expect(error.details, isNot(contains('private prompt')));
        expect(error.details, isNot(contains('private response')));
      },
    );

    test(
      'invalid retry hints are ignored and past HTTP dates have zero delay',
      () {
        expect(
          AppFailure.http(429, headers: {'retry-after': '-5'}).retryAfter,
          isNull,
        );
        expect(
          AppFailure.http(
            429,
            headers: {'retry-after': 'not a date'},
          ).retryAfter,
          isNull,
        );
        expect(
          AppFailure.http(
            429,
            headers: {'retry-after': 'Thu, 01 Jan 1970 00:00:00 GMT'},
          ).retryAfter,
          Duration.zero,
        );
      },
    );

    test(
      'malformed error code cannot smuggle arbitrary response content into diagnostics',
      () {
        final error = AppFailure.http(
          502,
          body: jsonEncode({
            'error': {
              'code': {'prompt': 'sensitive-conversation-fixture'},
              'message': 'ignored raw text',
            },
          }),
        );
        expect(error.kind, FailureKind.provider);
        expect(
          error.details,
          isNot(contains('sensitive-conversation-fixture')),
        );
      },
    );

    test(
      'network failures do not assert CORS; timeout and parsing are distinct',
      () {
        final network = AppFailure.from(
          http.ClientException('opaque network failure'),
        );
        expect(network.kind, FailureKind.network);
        expect(network.details, contains('do not establish CORS'));
        expect(
          AppFailure.from(TimeoutException('test')).kind,
          FailureKind.timeout,
        );
        expect(
          AppFailure.from(const FormatException('bad JSON')).kind,
          FailureKind.parsing,
        );
        const existing = AppFailure(FailureKind.offline, 'Offline');
        expect(identical(AppFailure.from(existing), existing), isTrue);
      },
    );
  });

  group('diagnostic privacy and bounds', () {
    test('activity details are bounded separately from readable summary', () {
      final diagnostics = Diagnostics(
        const AppConfig(apiKey: 'fixture-secret', maxDetailChars: 100),
      );
      addTearDown(diagnostics.dispose);
      diagnostics.record(
        'PWA inspection',
        note: 'Offline cache inspection completed.',
        details: 'fixture-secret ${'metadata ' * 100}',
      );
      final event = diagnostics.events.single;
      expect(event.isError, false);
      expect(event.data['summary'], 'Offline cache inspection completed.');
      expect(event.data['details'], contains('[REDACTED]'));
      expect(event.data['details'], endsWith('[truncated]'));
      expect(event.data['retryPolicy'], 'Not applicable to activity events');
      expect(diagnostics.export(), isNot(contains('fixture-secret')));
    });

    test(
      'expected offline and cancellation activity is distinct from errors',
      () {
        final diagnostics = Diagnostics(const AppConfig());
        addTearDown(diagnostics.dispose);
        diagnostics.record(
          'offline',
          failure: const AppFailure(FailureKind.offline, 'Offline'),
        );
        diagnostics.record(
          'cancel',
          failure: const AppFailure(FailureKind.cancelled, 'Cancelled'),
        );
        expect(diagnostics.events.every((event) => !event.isError), true);
        diagnostics.record(
          'catalog',
          failure: const AppFailure(FailureKind.schema, 'Invalid pricing'),
        );
        expect(diagnostics.events.first.isError, true);
        expect(diagnostics.events.first.data['kind'], 'schema');
      },
    );

    test(
      'redacts configured secrets, OpenRouter keys and authorization forms',
      () {
        final diagnostics = Diagnostics(
          const AppConfig(apiKey: 'custom-initial-secret'),
        );
        addTearDown(diagnostics.dispose);
        diagnostics.addSecret('custom-replacement-secret');
        const sample =
            'custom-initial-secret custom-replacement-secret '
            'sk-or-v1-fixture123456789 SK-OR-V1-FIXTUREOTHER '
            'Bearer fixture-bearer-key '
            'Authorization: opaque-auth-value '
            'api_key="fixture-api-key" apiKey=fixtureCamelKey';
        final output = diagnostics.sanitize(sample);
        for (final secret in [
          'custom-initial-secret',
          'custom-replacement-secret',
          'fixture123456789',
          'FIXTUREOTHER',
          'fixture-bearer-key',
          'opaque-auth-value',
          'fixture-api-key',
          'fixtureCamelKey',
        ]) {
          expect(output, isNot(contains(secret)), reason: secret);
        }
        expect(output, contains('[REDACTED]'));
      },
    );

    test(
      'bounded newest-first events retain investigation fields without user content',
      () {
        final diagnostics = Diagnostics(
          const AppConfig(maxDiagnostics: 10, maxDetailChars: 100),
        );
        addTearDown(diagnostics.dispose);
        for (var i = 0; i < 15; i++) {
          diagnostics.record(
            'request $i',
            model: 'model/fixture',
            duration: const Duration(milliseconds: 41),
            failure: AppFailure(
              FailureKind.schema,
              'Schema changed',
              status: 200,
              field: r'$.data[0].pricing.prompt',
              expected: 'numeric string',
              actual: 'object',
              details: 'x' * 1000,
              requestId: 'fixture-id',
              provider: 'fixture-provider',
              retryable: false,
            ),
          );
        }
        expect(diagnostics.events.length, 10);
        final first = diagnostics.events.first.toJson();
        expect(first['operation'], 'request 14');
        expect(first['durationMs'], 41);
        expect(first['httpStatus'], 200);
        expect(first['model'], 'model/fixture');
        expect(first['provider'], 'fixture-provider');
        expect(first['requestId'], 'fixture-id');
        expect(first['field'], r'$.data[0].pricing.prompt');
        expect(first['expected'], 'numeric string');
        expect(first['actual'], 'object');
        expect(first['retryable'], isFalse);
        expect(DateTime.tryParse(first['timestamp'] as String), isNotNull);
        expect((first['details'] as String).length, lessThan(130));
        expect(first['details'], endsWith('[truncated]'));
        final exported = jsonDecode(diagnostics.export()) as Map;
        expect(exported['events'], hasLength(10));
        diagnostics.clear();
        expect(diagnostics.events, isEmpty);
      },
    );

    test('every exported string field is sanitized', () {
      final diagnostics = Diagnostics(
        const AppConfig(apiKey: 'fixture-hidden-secret'),
      );
      addTearDown(diagnostics.dispose);
      diagnostics.record(
        'operation fixture-hidden-secret',
        model: 'fixture-hidden-secret',
        failure: const AppFailure(
          FailureKind.http,
          'fixture-hidden-secret',
          details: 'fixture-hidden-secret',
          requestId: 'fixture-hidden-secret',
          provider: 'fixture-hidden-secret',
          field: 'fixture-hidden-secret',
          expected: 'fixture-hidden-secret',
          actual: 'fixture-hidden-secret',
        ),
      );
      expect(diagnostics.export(), isNot(contains('fixture-hidden-secret')));
      expect(
        () => diagnostics.events.add(const DiagnosticEvent({})),
        throwsUnsupportedError,
      );
    });
  });

  group('transport lifecycle', () {
    test('response handles Unicode divided across byte boundaries', () async {
      final bytes = utf8.encode('hello 🌿 café');
      final response = ApiResponse(
        200,
        {},
        Stream.fromIterable(bytes.map((byte) => [byte])),
      );
      expect(await response.readText(maxBytes: bytes.length), 'hello 🌿 café');
    });

    test(
      'oversized response cancels upstream subscription and retains schema detail',
      () async {
        var cancelled = false;
        final body = StreamController<List<int>>(
          onCancel: () {
            cancelled = true;
          },
        );
        final response = ApiResponse(200, {}, body.stream);
        final result = expectLater(
          response.readText(maxBytes: 3),
          throwsA(
            failureOf(
              FailureKind.schema,
            ).having((failure) => failure.field, 'field', r'$'),
          ),
        );
        body.add([1, 2]);
        body.add([3, 4]);
        await result;
        expect(cancelled, isTrue);
        await body.close();
      },
    );

    test('malformed UTF-8 is an explicit parsing failure', () async {
      final response = ApiResponse(200, {}, Stream.value([0xc3, 0x28]));
      await expectLater(
        response.readText(),
        throwsA(failureOf(FailureKind.parsing)),
      );
    });

    test('pre-cancelled request never creates a network client', () async {
      final token = CancelToken()
        ..cancel()
        ..cancel();
      var created = false;
      await http.runWithClient(
        () async {
          await expectLater(
            HttpApiTransport().send(
              'GET',
              Uri.parse('https://fixture.test'),
              timeout: const Duration(seconds: 1),
              cancel: token,
            ),
            throwsA(failureOf(FailureKind.cancelled)),
          );
        },
        () {
          created = true;
          return ControlledClient();
        },
      );
      expect(created, isFalse);
      expect(token.isCancelled, isTrue);
      await token.whenCancelled;
    });

    test(
      'cancellation preserves delivered chunks and closes only the owned client',
      () async {
        final client = ControlledClient();
        final token = CancelToken();
        await http.runWithClient(() async {
          final response = await HttpApiTransport().send(
            'POST',
            Uri.parse('https://fixture.test'),
            headers: {'content-type': 'application/json'},
            body: {'model': 'fixture'},
            timeout: const Duration(seconds: 5),
            cancel: token,
          );
          final chunks = <int>[];
          final done = Completer<void>();
          final observed = Completer<Object>();
          response.body.listen(
            chunks.addAll,
            onError: observed.complete,
            onDone: done.complete,
          );
          client.body.add(utf8.encode('partial'));
          await Future<void>.delayed(Duration.zero);
          token.cancel();
          expect(await observed.future, failureOf(FailureKind.cancelled));
          await done.future;
          expect(utf8.decode(chunks), 'partial');
          expect(client.closeCount, greaterThanOrEqualTo(1));
          expect(client.request?.method, 'POST');
          expect(jsonDecode((client.request as http.Request).body), {
            'model': 'fixture',
          });
        }, () => client);
      },
    );

    testWidgets(
      'total timeout includes a stalled response body after HTTP headers',
      (tester) async {
        final client = ControlledClient();
        await http.runWithClient(() async {
          final response = await HttpApiTransport().send(
            'GET',
            Uri.parse('https://fixture.test'),
            timeout: const Duration(seconds: 2),
          );
          final result = expectLater(
            response.readText(),
            throwsA(failureOf(FailureKind.timeout)),
          );
          client.body.add(utf8.encode('partial'));
          await tester.pump(const Duration(seconds: 3));
          await result;
          expect(client.closeCount, greaterThanOrEqualTo(1));
        }, () => client);
      },
    );

    test(
      'cancelling one concurrent request leaves the other client usable',
      () async {
        final clients = [ControlledClient(), ControlledClient()];
        var nextClient = 0;
        final firstToken = CancelToken();
        await http.runWithClient(() async {
          final transport = HttpApiTransport();
          final first = await transport.send(
            'GET',
            Uri.parse('https://fixture.test/one'),
            timeout: const Duration(seconds: 5),
            cancel: firstToken,
          );
          final second = await transport.send(
            'GET',
            Uri.parse('https://fixture.test/two'),
            timeout: const Duration(seconds: 5),
          );
          final firstResult = expectLater(
            first.readText(),
            throwsA(failureOf(FailureKind.cancelled)),
          );
          final secondResult = second.readText();
          firstToken.cancel();
          await firstResult;
          expect(clients[1].closeCount, 0);
          clients[1].body.add(utf8.encode('second survives'));
          await clients[1].body.close();
          expect(await secondResult, 'second survives');
        }, () => clients[nextClient++]);
      },
    );

    test('successful body completion closes transport resources', () async {
      final client = ControlledClient();
      await http.runWithClient(() async {
        final response = await HttpApiTransport().send(
          'GET',
          Uri.parse('https://fixture.test'),
          timeout: const Duration(seconds: 5),
        );
        final content = response.readText();
        client.body.add(utf8.encode('done'));
        await client.body.close();
        expect(await content, 'done');
        expect(client.closeCount, 1);
      }, () => client);
    });
  });
}

/// Mimics only the documented abortable http-client contract, without sockets.
class ControlledClient extends http.BaseClient {
  final body = StreamController<List<int>>();
  http.BaseRequest? request;
  var closeCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    this.request = request;
    if (request is http.Abortable) {
      request.abortTrigger?.then((_) {
        if (!body.isClosed) {
          body.addError(http.RequestAbortedException(request.url));
          unawaited(body.close());
        }
      });
    }
    return http.StreamedResponse(
      body.stream,
      200,
      headers: {'x-request-id': 'fixture'},
    );
  }

  @override
  void close() {
    closeCount++;
  }
}
