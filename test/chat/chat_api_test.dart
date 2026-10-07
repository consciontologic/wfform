import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/config/app_config.dart';
import 'package:wfform/features/chat/chat_api.dart';
import 'package:wfform/features/models/model.dart';
import 'package:wfform/shared/diagnostics.dart';
import 'package:wfform/shared/transport.dart';

import 'fakes.dart';

void main() {
  const config = AppConfig(apiKey: 'test-key');
  const input = [
    {'role': 'user', 'content': 'private prompt'},
  ];

  test(
    'selected exact ID, zero price guards, no fallbacks, supported reasoning',
    () {
      final api = ChatApi(config, FakeTransport((_) => endpoints()));
      final request = api.requestBody(testModel, input);
      expect(request['model'], testModel.id);
      expect(request.containsKey('models'), isFalse);
      expect(request['provider'], {
        'allow_fallbacks': false,
        'max_price': {
          'prompt': '0',
          'completion': '0',
          'request': '0',
          'image': '0',
          'audio': '0',
        },
      });
      expect(request['reasoning'], {'enabled': true});
      expect(
        api
            .requestBody(
              const FreeModel(id: 'other/model', name: 'Other'),
              input,
            )
            .containsKey('reasoning'),
        isFalse,
      );
      final probe = api.requestBody(testModel, input, probe: true);
      expect(probe['max_tokens'], 16);
      expect(probe.containsKey('reasoning'), isFalse);
    },
  );

  test('incremental unicode content and reasoning are separate', () async {
    final api = ChatApi(
      config,
      FakeTransport(
        (_) => streamResponse(
          ': keepalive\n\n${delta('çilek 🍓', reasoning: 'Count', provider: 'Test')}data: [DONE]\n\n',
          chunkSize: 1,
        ),
      ),
    );
    final output = await api
        .stream(testModel, input, cancel: CancelToken())
        .toList();
    expect(output.first.content, 'çilek 🍓');
    expect(output.first.reasoning, 'Count');
    expect(output.last.done, isTrue);
    expect(output.last.provider, 'Test');
  });

  test(
    'HTTP-200 JSON error is classified rather than treated as success',
    () async {
      final api = ChatApi(
        config,
        FakeTransport(
          (_) => jsonResponse({
            'error': {'code': 401, 'message': 'private prompt sk-or-v1-secret'},
          }),
        ),
      );
      await expectLater(
        api.stream(testModel, input, cancel: CancelToken()),
        emitsError(
          isA<AppFailure>()
              .having((e) => e.kind, 'kind', FailureKind.authentication)
              .having((e) => e.status, 'actual HTTP status', 200)
              .having(
                (e) => e.details,
                'does not retain prompt',
                isNot(contains('private prompt')),
              ),
        ),
      );
    },
  );

  test(
    'partial output precedes midstream error, rate limit retains retry-after',
    () async {
      final api = ChatApi(
        config,
        FakeTransport(
          (_) => ApiResponse(
            200,
            {'content-type': 'text/event-stream', 'retry-after': '45'},
            streamResponse(
              '${delta('partial')}data: {"error":{"code":429}}\n\n',
            ).body,
          ),
        ),
      );
      await expectLater(
        api.stream(testModel, input, cancel: CancelToken()),
        emitsInOrder([
          isA<ChatDelta>().having((d) => d.content, 'content', 'partial'),
          emitsError(
            isA<AppFailure>()
                .having((e) => e.kind, 'kind', FailureKind.rateLimit)
                .having(
                  (e) => e.retryAfter,
                  'backoff',
                  const Duration(seconds: 45),
                ),
          ),
        ]),
      );
    },
  );

  test(
    'malformed event reports a parsing path without raw conversation data',
    () async {
      final api = ChatApi(
        config,
        FakeTransport((_) => streamResponse('data: {private prompt}\n\n')),
      );
      await expectLater(
        api.stream(testModel, input, cancel: CancelToken()),
        emitsError(
          isA<AppFailure>()
              .having((e) => e.kind, 'kind', FailureKind.parsing)
              .having((e) => e.field, 'path', 'SSE.data')
              .having(
                (e) => e.details,
                'private payload omitted',
                isNot(contains('private prompt')),
              ),
        ),
      );
    },
  );

  test('finish reason without DONE is treated as truncated', () async {
    final api = ChatApi(
      config,
      FakeTransport((_) => streamResponse(delta('partial'))),
    );
    await expectLater(
      api.stream(testModel, input, cancel: CancelToken()),
      emitsInOrder([
        isA<ChatDelta>(),
        emitsError(
          isA<AppFailure>().having((e) => e.kind, 'kind', FailureKind.stream),
        ),
      ]),
    );
  });

  test('wrong delta type is actionable schema failure', () async {
    final api = ChatApi(
      config,
      FakeTransport(
        (_) =>
            streamResponse('data: {"choices":[{"delta":{"content":123}}]}\n\n'),
      ),
    );
    await expectLater(
      api.stream(testModel, input, cancel: CancelToken()),
      emitsError(
        isA<AppFailure>()
            .having((e) => e.kind, 'kind', FailureKind.schema)
            .having((e) => e.expected, 'expected', 'string or null'),
      ),
    );
  });

  test(
    'encrypted reasoning is not fabricated, summary reasoning is shown',
    () async {
      final api = ChatApi(
        config,
        FakeTransport(
          (_) => streamResponse(
            'data: {"choices":[{"delta":{"reasoning_details":[{"type":"reasoning.encrypted","data":"abc"},{"type":"reasoning.summary","summary":"Summary"}]}}]}\n\n'
            'data: [DONE]\n\n',
          ),
        ),
      );
      final output = await api
          .stream(testModel, input, cancel: CancelToken())
          .toList();
      expect(output.first.reasoning, 'Summary');
    },
  );

  test('unexpected model identity stops the response', () async {
    final api = ChatApi(
      config,
      FakeTransport(
        (_) => streamResponse(
          'data: {"model":"paid/other","choices":[{"delta":{"content":"bad"}}]}\n\n',
        ),
      ),
    );
    await expectLater(
      api.stream(testModel, input, cancel: CancelToken()),
      emitsError(
        isA<AppFailure>().having((e) => e.field, 'field', 'SSE.data.model'),
      ),
    );
  });
}
