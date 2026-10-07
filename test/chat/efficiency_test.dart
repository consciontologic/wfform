import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/config/app_config.dart';
import 'package:wfform/features/chat/chat_api.dart';
import 'package:wfform/features/chat/chat_controller.dart';
import 'package:wfform/features/models/health.dart';
import 'package:wfform/features/models/model.dart';
import 'package:wfform/shared/diagnostics.dart';
import 'package:wfform/shared/transport.dart';

import 'fakes.dart';

void main() {
  const config = AppConfig(apiKey: 'fixture');
  late Diagnostics diagnostics;
  late HealthController health;
  late ChatController chat;
  late FakeTransport transport;
  void create(
    FutureOr<ApiResponse> Function(SentRequest) handler, {
    FreeModel model = testModel,
  }) {
    diagnostics = Diagnostics(config);
    transport = FakeTransport(handler);
    health = HealthController(
      config: config,
      transport: transport,
      diagnostics: diagnostics,
    );
    health.reconcileModels([model]);
    health.recordSuccess(model.id);
    chat = ChatController(
      config: config,
      transport: transport,
      diagnostics: diagnostics,
      health: health,
    );
  }

  tearDown(() {
    chat.dispose();
    health.dispose();
    diagnostics.dispose();
  });

  test(
    'cooldown send refuses acceptance and repeated retries do not mutate history',
    () async {
      create((_) => streamResponse(delta('partial')));
      await chat.send(testModel, 'one');
      final messages = chat.exportSession();
      expect(chat.retryAt, isNotNull);
      for (var i = 0; i < 100; i++) {
        await chat.retry(testModel);
      }
      expect(chat.exportSession(), messages);
      expect(transport.requests.length, 1);
      var accepted = false;
      await chat.send(
        testModel,
        'unsent draft',
        onAccepted: () => accepted = true,
      );
      expect(accepted, isFalse);
      expect(chat.messages.length, 2);
      expect(transport.requests.length, 1);
    },
  );

  test(
    'explicit context window is preserved and excludes only chosen earlier turns',
    () async {
      create((_) => streamResponse('${delta('answer')}data: [DONE]\n\n'));
      await chat.send(testModel, 'first');
      await chat.send(testModel, 'second');
      expect(chat.setContextStartIndex(1), isFalse);
      expect(chat.setContextStartIndex(2), isTrue);
      expect(chat.setOutputTokenLimit(512), isTrue);
      await chat.send(testModel, 'third');
      expect(transport.requests.last.json['messages'], [
        {'role': 'user', 'content': 'second'},
        {'role': 'assistant', 'content': 'answer'},
        {'role': 'user', 'content': 'third'},
      ]);
      expect(transport.requests.last.json['max_tokens'], 512);
      expect(chat.messages.length, 6);
      final session = chat.exportSession();
      chat.clear();
      expect(chat.restoreSession(session), isTrue);
      expect(chat.contextStartIndex, 2);
      expect(chat.outputTokenLimit, 512);
      expect(chat.messages.first.content, 'first');
    },
  );

  test(
    'context over budget refuses send without accepting or probing',
    () async {
      const small = FreeModel(
        id: 'tiny/free',
        name: 'Tiny',
        contextLength: 128,
        supportedParameters: ['max_tokens'],
      );
      create((_) => throw StateError('Must not send'), model: small);
      final budget = chat.contextBudget(small, draft: 'a' * 400);
      expect(budget.fits, isFalse);
      var accepted = false;
      await chat.send(small, 'a' * 400, onAccepted: () => accepted = true);
      expect(accepted, isFalse);
      expect(chat.messages, isEmpty);
      expect(transport.requests, isEmpty);
      expect(chat.error?.message, contains('context'));
    },
  );

  test(
    'length termination retains usage and enables explicit continue without retrying',
    () async {
      create(
        (_) => streamResponse(
          '${delta('unfinished')}'
          'data: {"choices":[{"delta":{},"finish_reason":"length"}],"usage":{"prompt_tokens":22,"completion_tokens":16,"total_tokens":38,"completion_tokens_details":{"reasoning_tokens":4}}}\n\n'
          'data: [DONE]\n\n',
        ),
      );
      await chat.send(testModel, 'one');
      final message = chat.messages.last;
      expect(message.complete, isTrue);
      expect(message.terminationLabel, contains('token limit'));
      expect(message.usage?.totalTokens, 38);
      expect(message.usage?.reasoningTokens, 4);
      expect(message.metrics?.firstTokenMs, isNotNull);
      expect(chat.canContinue, isTrue);
      expect(chat.canRetry, isFalse);
      final session = chat.exportSession();
      chat.clear();
      chat.restoreSession(session);
      expect(chat.messages.last.finishReason, 'length');
      expect(chat.messages.last.usage?.promptTokens, 22);
      await chat.continueResponse(testModel);
      expect(transport.requests.length, 2);
      expect(
        transport.requests.last.json['messages'][1]['content'],
        'unfinished',
      );
      expect(chat.messages[2].content, startsWith('Continue'));
    },
  );

  test(
    'content-filter termination is visible and does not suggest automatic continuation',
    () async {
      create(
        (_) => streamResponse(
          '${delta('limited')}'
          'data: {"choices":[{"delta":{},"finish_reason":"content_filter"}]}\n\ndata: [DONE]\n\n',
        ),
      );
      await chat.send(testModel, 'one');
      expect(chat.messages.last.terminationLabel, contains('content filter'));
      expect(chat.canContinue, isFalse);
      expect(chat.error, isNull);
    },
  );

  test(
    'usage-only chunk is accepted; malformed optional counts do not lose response',
    () async {
      create(
        (_) => streamResponse(
          '${delta('answer')}'
          'data: {"choices":[],"usage":{"prompt_tokens":12,"completion_tokens":"unknown","total_tokens":19}}\n\ndata: [DONE]\n\n',
        ),
      );
      await chat.send(testModel, 'one');
      expect(chat.messages.last.content, 'answer');
      expect(chat.messages.last.usage?.promptTokens, 12);
      expect(chat.messages.last.usage?.completionTokens, isNull);
    },
  );

  testWidgets(
    'burst deltas publish once per interval and terminal error flushes remaining text',
    (tester) async {
      final source = StreamController<List<int>>();
      create(
        (_) => ApiResponse(200, {
          'content-type': 'text/event-stream',
        }, source.stream),
      );
      var contentChanges = 0, statusChanges = 0;
      String last = '';
      chat.addListener(() {
        final value = chat.messages.lastOrNull?.content ?? '';
        if (value != last) {
          last = value;
          contentChanges++;
        }
      });
      chat.statusChanges.addListener(() => statusChanges++);
      var finished = false;
      unawaited(chat.send(testModel, 'one').then((_) => finished = true));
      await tester.pump();
      source.add(utf8.encode(List.generate(1000, (_) => delta('x')).join()));
      await tester.pump();
      expect(contentChanges, 0);
      await tester.pump(const Duration(milliseconds: 32));
      expect(chat.messages.last.content, 'x' * 1000);
      expect(contentChanges, 1);
      final before = statusChanges;
      source.add(utf8.encode(List.generate(100, (_) => delta('y')).join()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));
      expect(contentChanges, 2);
      expect(statusChanges, before);
      source.add(
        utf8.encode('${delta('tail')}data: {"error":{"code":503}}\n\n'),
      );
      await tester.pump();
      await tester.pump();
      expect(
        chat.busy,
        isFalse,
        reason: 'The stream error must finalize without another frame.',
      );
      expect(finished, isTrue);
      expect(chat.messages.last.content, '${'x' * 1000}${'y' * 100}tail');
      expect(contentChanges, 3);
      expect(chat.messages.last.failure?.kind, FailureKind.provider);
      unawaited(source.close());
      await tester.pump();
    },
  );

  test('output cap is only sent when model advertises max_tokens', () {
    create((_) => endpoints());
    final api = ChatApi(config, transport);
    expect(
      api.requestBody(testModel, const [], outputTokens: 700)['max_tokens'],
      700,
    );
    expect(
      api
          .requestBody(
            const FreeModel(id: 'no/cap', name: 'No cap'),
            const [],
            outputTokens: 700,
          )
          .containsKey('max_tokens'),
      isFalse,
    );
  });
}
