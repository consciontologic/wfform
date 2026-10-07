import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/config/app_config.dart';
import 'package:wfform/features/chat/chat_controller.dart';
import 'package:wfform/features/models/health.dart';
import 'package:wfform/features/models/model.dart';
import 'package:wfform/shared/diagnostics.dart';
import 'package:wfform/shared/transport.dart';

import 'fakes.dart';

void main() {
  const config = AppConfig(apiKey: 'test-key');
  late Diagnostics diagnostics;
  late HealthController health;
  late ChatController chat;
  late FakeTransport transport;

  void create(
    FutureOr<ApiResponse> Function(SentRequest) handler, {
    bool healthy = true,
  }) {
    diagnostics = Diagnostics(config);
    transport = FakeTransport(handler);
    health = HealthController(
      config: config,
      transport: transport,
      diagnostics: diagnostics,
    );
    if (healthy) health.recordSuccess(testModel.id);
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
    'preserves failed partial and explicit retry does not duplicate user',
    () async {
      var attempts = 0;
      create((r) {
        attempts++;
        return streamResponse(
          attempts == 1
              ? delta('partial')
              : '${delta('complete', reasoning: 'Count')}data: [DONE]\n\n',
        );
      });
      await chat.send(testModel, 'private prompt');
      expect(chat.messages.last.content, 'partial');
      expect(chat.messages.last.failure?.kind, FailureKind.stream);
      expect(chat.canRetry, isTrue);
      health.recordSuccess(
        testModel.id,
      ); // deterministic explicit health recovery
      await chat.retry(testModel);
      expect(chat.messages.where((m) => m.role == 'user').length, 1);
      expect(chat.messages.length, 3);
      expect(chat.messages[1].content, 'partial');
      expect(chat.messages.last.content, 'complete');
      expect(chat.messages.last.reasoning, 'Count');
      expect(chat.messages.last.complete, isTrue);
      expect(chat.canRetry, isFalse);
      expect(transport.requests.last.json['messages'], [
        {'role': 'user', 'content': 'private prompt'},
      ]);
      expect(diagnostics.export(), isNot(contains('private prompt')));
      expect(diagnostics.export(), isNot(contains('partial')));
    },
  );

  test(
    'double send during active response makes one request; cancel preserves output',
    () async {
      final source = StreamController<List<int>>();
      final arrived = Completer<void>();
      create((_) {
        arrived.complete();
        return ApiResponse(200, {
          'content-type': 'text/event-stream',
        }, source.stream);
      });
      final first = chat.send(testModel, 'one');
      await arrived.future;
      source.add(utf8.encode(delta('kept')));
      await Future<void>.delayed(Duration.zero);
      await chat.send(testModel, 'duplicate');
      expect(transport.requests.length, 1);
      chat.cancel();
      await first;
      expect(chat.busy, isFalse);
      expect(chat.messages.last.content, 'kept');
      expect(chat.messages.last.failure?.kind, FailureKind.cancelled);
      expect(chat.canRetry, isTrue);
      await source.close();
    },
  );

  test(
    'clear while pending does not let late output mutate a new conversation',
    () async {
      final source = StreamController<List<int>>();
      create(
        (_) => ApiResponse(200, {
          'content-type': 'text/event-stream',
        }, source.stream),
      );
      final pending = chat.send(testModel, 'one');
      await Future<void>.delayed(Duration.zero);
      chat.clear();
      await pending;
      expect(chat.messages, isEmpty);
      expect(chat.busy, isFalse);
      await source.close();
    },
  );

  test(
    'stale health preflight does not submit conversation if authentication fails',
    () async {
      create(
        (_) => jsonResponse({
          'error': {'code': 401},
        }, status: 401),
        healthy: false,
      );
      await chat.send(testModel, 'must not reach server');
      expect(transport.requests.length, 1);
      expect(transport.requests.single.method, 'GET');
      expect(chat.error?.kind, FailureKind.authentication);
      expect(chat.messages.first.content, 'must not reach server');
      expect(chat.canRetry, isTrue);
    },
  );

  test('stream controller close completes the chat finalization', () async {
    final source = StreamController<List<int>>();
    create(
      (_) => ApiResponse(200, {
        'content-type': 'text/event-stream',
      }, source.stream),
    );
    final pending = chat.send(testModel, 'one');
    await Future<void>.delayed(Duration.zero);
    source.add(
      utf8.encode(
        '${delta('answer')}data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\ndata: [DONE]\n\n',
      ),
    );
    await source.close();
    await pending.timeout(const Duration(seconds: 2));
    expect(chat.busy, isFalse);
    expect(chat.messages.last.complete, isTrue);
  });

  test('retry requires original model and never silently switches', () async {
    create((_) => streamResponse(delta('partial')));
    await chat.send(testModel, 'one');
    await chat.retry(const FreeModel(id: 'maker/other', name: 'Other'));
    expect(transport.requests.length, 1);
    expect(chat.error?.kind, FailureKind.configuration);
  });

  test('fresh selected model still honors account-wide rate limit', () async {
    create((_) => streamResponse('${delta('must not send')}data: [DONE]\n\n'));
    health.recordFailure(
      'maker/other',
      const AppFailure(
        FailureKind.rateLimit,
        'Limited',
        retryAfter: Duration(minutes: 1),
        retryable: true,
      ),
    );
    expect(health.isFresh(testModel.id), isTrue);
    await chat.send(testModel, 'do not submit');
    expect(transport.requests, isEmpty);
    expect(chat.error?.kind, FailureKind.rateLimit);
  });

  test(
    'update session restores partial output and explicit retry state',
    () async {
      create((_) => streamResponse(delta('partial')));
      await chat.send(testModel, 'saved draft');
      final saved = chat.exportSession();
      chat.clear();
      chat.restoreSession(saved);
      expect(chat.messages.length, 2);
      expect(chat.messages.first.content, 'saved draft');
      expect(chat.messages.last.content, 'partial');
      expect(chat.messages.last.complete, isFalse);
      expect(chat.canRetry, isTrue);
      expect(chat.retryModelId, testModel.id);
      expect(transport.requests.length, 1);
    },
  );

  test(
    'bad session is reported without destroying current conversation',
    () async {
      create((_) => streamResponse('${delta('answer')}data: [DONE]\n\n'));
      await chat.send(testModel, 'question');
      chat.restoreSession('{malformed');
      expect(chat.messages.length, 2);
      expect(chat.error?.kind, FailureKind.storage);
      expect(diagnostics.export(), contains('chat.restore'));
    },
  );
}
