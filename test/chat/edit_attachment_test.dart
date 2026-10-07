import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/config/app_config.dart';
import 'package:wfform/features/chat/attachment.dart';
import 'package:wfform/features/chat/chat_controller.dart';
import 'package:wfform/features/models/health.dart';
import 'package:wfform/features/models/model.dart';
import 'package:wfform/shared/diagnostics.dart';
import 'package:wfform/shared/transport.dart';

import 'fakes.dart';

const mediaModel = FreeModel(
  id: 'maker/media:free',
  name: 'Media',
  inputModalities: ['text', 'image', 'audio', 'video', 'file'],
);

ChatAttachment imageAttachment({int bytes = 8}) => ChatAttachment.fromBytes(
  name: 'private-image.png',
  mimeType: 'image/png',
  bytes: [137, 80, 78, 71, 13, 10, 26, 10, ...List.filled(bytes - 8, 0)],
);

void main() {
  const config = AppConfig(apiKey: 'test-key');
  late Diagnostics diagnostics;
  late HealthController health;
  late ChatController chat;
  late FakeTransport transport;

  void create(
    FutureOr<ApiResponse> Function(SentRequest) handler, {
    String? Function(FreeModel)? validateModel,
    bool healthy = true,
  }) {
    diagnostics = Diagnostics(config);
    transport = FakeTransport(handler);
    health = HealthController(
      config: config,
      transport: transport,
      diagnostics: diagnostics,
    );
    if (healthy) health.recordSuccess(mediaModel.id);
    chat = ChatController(
      config: config,
      transport: transport,
      diagnostics: diagnostics,
      health: health,
      validateModel: validateModel,
    );
  }

  tearDown(() {
    chat.dispose();
    health.dispose();
    diagnostics.dispose();
  });

  test(
    'acceptance is synchronous before listeners, exactly once while busy reserved',
    () async {
      final source = StreamController<List<int>>();
      create(
        (_) => ApiResponse(200, {
          'content-type': 'text/event-stream',
        }, source.stream),
      );
      var accepted = 0;
      var notified = false;
      chat.addListener(() {
        notified = true;
        expect(accepted, 1);
      });
      final pending = chat.send(
        mediaModel,
        'new turn',
        onAccepted: () {
          accepted++;
          expect(chat.busy, isTrue);
          expect(chat.messages.first.content, 'new turn');
          expect(notified, isFalse);
        },
      );
      expect(accepted, 1);
      expect(chat.busy, isTrue);
      await chat.send(mediaModel, 'duplicate', onAccepted: () => accepted++);
      expect(accepted, 1);
      await Future<void>.delayed(Duration.zero);
      source.add(utf8.encode('${delta('response')}data: [DONE]\n\n'));
      await source.close();
      await pending;
      expect(
        chat.messages.where((message) => message.role == 'user').length,
        1,
      );
    },
  );

  test(
    'refused submissions keep composer ownership and create no new turn or request',
    () async {
      create((_) => streamResponse('${delta('unexpected')}data: [DONE]\n\n'));
      var accepted = 0;
      final image = imageAttachment();
      await chat.send(mediaModel, ' ', onAccepted: () => accepted++);
      await chat.send(
        mediaModel,
        'invalid edit',
        editedFrom: 0,
        onAccepted: () => accepted++,
      );
      await chat.send(
        testModel,
        'incompatible',
        attachments: [image],
        onAccepted: () => accepted++,
      );
      await chat.send(
        mediaModel,
        'duplicate attachment',
        attachments: [image, image],
        onAccepted: () => accepted++,
      );
      await chat.send(mediaModel, 'a' * 32001, onAccepted: () => accepted++);
      expect(accepted, 0);
      expect(chat.messages, isEmpty);
      expect(transport.requests, isEmpty);
    },
  );

  test('external offline or archived refusal never accepts a send', () async {
    create(
      (_) => endpoints(),
      validateModel: (_) => 'This conversation is archived.',
    );
    var accepted = false;
    await chat.send(
      mediaModel,
      'preserve draft',
      onAccepted: () => accepted = true,
    );
    expect(accepted, isFalse);
    expect(chat.messages, isEmpty);
    expect(transport.requests, isEmpty);
    expect(chat.error?.message, contains('archived'));
  });

  test(
    'catalog validation repeats after delayed health before submitting user content',
    () async {
      final probeArrived = Completer<void>();
      final finishProbe = Completer<ApiResponse>();
      var changed = false;
      create(
        (request) {
          if (request.method == 'GET') return endpoints();
          probeArrived.complete();
          return finishProbe.future;
        },
        validateModel: (_) =>
            changed ? 'Model capabilities changed. Select it again.' : null,
        healthy: false,
      );
      var accepted = false;
      final pending = chat.send(
        mediaModel,
        'private user content',
        attachments: [imageAttachment()],
        onAccepted: () => accepted = true,
      );
      expect(accepted, isTrue);
      await probeArrived.future;
      changed = true;
      finishProbe.complete(streamResponse('${delta('OK')}data: [DONE]\n\n'));
      await pending;
      expect(chat.busy, isFalse);
      expect(chat.canRetry, isTrue);
      expect(chat.error?.kind, FailureKind.configuration);
      expect(chat.error?.message, contains('capabilities changed'));
      expect(
        transport.requests.length,
        2,
      ); // Endpoint metadata and tiny probe only.
      expect(
        transport.requests.last.body.toString(),
        isNot(contains('private user content')),
      );
      expect(
        transport.requests.last.body.toString(),
        isNot(contains('image_url')),
      );
      expect(chat.messages.first.content, 'private user content');
      expect(
        health.isFresh(mediaModel.id),
        isTrue,
      ); // A catalog refusal is not model failure.
    },
  );

  test(
    'edit appends a user turn with original reference and retains original history',
    () async {
      create((_) => streamResponse('${delta('answer')}data: [DONE]\n\n'));
      final image = imageAttachment();
      await chat.send(mediaModel, 'original question', attachments: [image]);
      await chat.send(
        mediaModel,
        'corrected question',
        attachments: [image],
        editedFrom: 0,
      );
      expect(chat.messages.length, 4);
      expect(chat.messages[0].content, 'original question');
      expect(chat.messages[0].editedFrom, isNull);
      expect(chat.messages[2].content, 'corrected question');
      expect(chat.messages[2].editedFrom, 0);
      final outbound = transport.requests.last.json['messages'] as List;
      expect(outbound.length, 3);
      expect((outbound[0]['content'] as List).first, {
        'type': 'text',
        'text': 'original question',
      });
      expect((outbound[2]['content'] as List).first, {
        'type': 'text',
        'text': 'corrected question',
      });
      expect(outbound[2].containsKey('editedFrom'), isFalse);
      final session = chat.exportSession();
      chat.clear();
      expect(chat.restoreSession(session), isTrue);
      expect(chat.messages[2].editedFrom, 0);
      expect(chat.messages[2].attachments.single.toJson(), image.toJson());
    },
  );

  test(
    'attachment-only turn is sent; failed partial retry reuses original attachment without duplicate user',
    () async {
      var attempts = 0;
      create(
        (_) => streamResponse(
          ++attempts == 1
              ? delta('partial')
              : '${delta('complete')}data: [DONE]\n\n',
        ),
      );
      final image = imageAttachment();
      await chat.send(mediaModel, '', attachments: [image]);
      expect(chat.messages.last.content, 'partial');
      expect(chat.canRetry, isTrue);
      final saved = chat.exportSession();
      chat.clear();
      expect(chat.restoreSession(saved), isTrue);
      health.recordSuccess(mediaModel.id);
      await chat.retry(mediaModel);
      expect(
        chat.messages.where((message) => message.role == 'user').length,
        1,
      );
      expect(chat.messages[1].content, 'partial');
      expect(
        transport.requests[0].json['messages'],
        transport.requests[1].json['messages'],
      );
      expect(transport.requests.last.json['messages'], [
        {
          'role': 'user',
          'content': [image.toContentPart()],
        },
      ]);
      expect(diagnostics.export(), isNot(contains(image.name)));
      expect(diagnostics.export(), isNot(contains(image.base64Data)));
    },
  );

  test(
    'changed capabilities refuse both new sends and retries before user content is sent',
    () async {
      create((_) => streamResponse(delta('partial')));
      await chat.send(mediaModel, 'first', attachments: [imageAttachment()]);
      const changed = FreeModel(id: 'maker/media:free', name: 'Media');
      var accepted = false;
      await chat.send(changed, 'next', onAccepted: () => accepted = true);
      await chat.retry(changed);
      expect(accepted, isFalse);
      expect(transport.requests.length, 1);
      expect(chat.messages.length, 2);
      expect(chat.error?.message, contains('image'));
    },
  );

  test(
    'cancel preserves original attachment and corrupted restoration is atomic',
    () async {
      final source = StreamController<List<int>>();
      create(
        (_) => ApiResponse(200, {
          'content-type': 'text/event-stream',
        }, source.stream),
      );
      final image = imageAttachment();
      final pending = chat.send(mediaModel, 'first', attachments: [image]);
      await Future<void>.delayed(Duration.zero);
      source.add(utf8.encode(delta('partial')));
      await Future<void>.delayed(Duration.zero);
      chat.cancel();
      await pending;
      await source.close();
      final saved = chat.exportSession();
      chat.clear();
      expect(chat.restoreSession(saved), isTrue);
      expect(chat.messages.last.content, 'partial');
      expect(chat.messages.last.failure?.kind, FailureKind.cancelled);
      expect(chat.messages.first.attachments.single.toJson(), image.toJson());
      final broken = jsonDecode(saved) as Map<String, dynamic>;
      broken['messages'][0]['attachments'][0]['base64Data'] = 'damaged';
      expect(chat.restoreSession(jsonEncode(broken)), isFalse);
      expect(chat.messages.first.attachments.single.toJson(), image.toJson());
      expect(chat.messages.last.content, 'partial');
    },
  );

  test(
    'aggregate encoded attachments stop growth without evicting earlier turns',
    () async {
      create((_) => streamResponse('${delta('answer')}data: [DONE]\n\n'));
      final image = imageAttachment(bytes: 7 * 1024 * 1024);
      await chat.send(mediaModel, 'first', attachments: [image]);
      await chat.send(mediaModel, 'second', attachments: [image]);
      var accepted = false;
      await chat.send(
        mediaModel,
        'third',
        attachments: [image],
        onAccepted: () => accepted = true,
      );
      expect(accepted, isFalse);
      expect(chat.messages.length, 4);
      expect(transport.requests.length, 2);
      expect(chat.error?.message, contains('24 MiB'));
    },
  );
}
