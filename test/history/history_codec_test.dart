import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/features/chat/attachment.dart';
import 'package:wfform/features/history/conversation.dart';
import 'package:wfform/features/history/history_codec.dart';
import 'package:wfform/shared/diagnostics.dart';

const png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jh1sAAAAASUVORK5CYII=';
ChatAttachment image() => ChatAttachment.fromBytes(
  id: 'media-one',
  name: 'image.png',
  mimeType: 'image/png',
  bytes: base64Decode(png),
);
ConversationRecord record({
  String answer = '',
  String draft = '',
  bool resend = false,
}) {
  final file = image();
  final user = {
    'role': 'user',
    'content': 'Describe this',
    'reasoning': '',
    'complete': true,
    'attachments': [file.toJson()],
  };
  return ConversationRecord(
    id: 'one',
    title: 'One',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    draft: draft,
    draftAttachments: [file],
    sessionData: {
      'version': 1,
      'retryUserIndex': 0,
      'retryModelId': 'fixture/model',
      'messages': [
        user,
        {
          'role': 'assistant',
          'content': answer,
          'reasoning': '',
          'complete': false,
        },
        if (resend) {...user, 'editedFrom': 0},
      ],
    },
  );
}

void main() {
  test(
    'normalized checkpoint contains references; repeated files stored once',
    () {
      final packed = PackedHistoryRecord.pack(record(resend: true));
      expect(packed.attachments.length, 1);
      expect(packed.draftIds, ['media-one']);
      expect(jsonEncode(packed.document(1)), isNot(contains(png)));
      expect(packed.messages.join(), isNot(contains(png)));
      expect(packed.messages.first, contains('attachmentIds'));
      expect(packed.messages.last, contains('editedFrom'));
    },
  );
  test(
    'stream checkpoints change only active message, reuse validated media',
    () {
      final before = PackedHistoryRecord.pack(record(answer: 'Hello'));
      final after = PackedHistoryRecord.pack(
        record(answer: 'Hello world'),
        previous: before,
      );
      expect(after.messagesChangedSince(before), [1]);
      expect(
        identical(
          after.attachments['media-one'],
          before.attachments['media-one'],
        ),
        isTrue,
      );
      final draft = PackedHistoryRecord.pack(
        record(answer: 'Hello world', draft: 'Next prompt'),
        previous: after,
      );
      expect(draft.messagesChangedSince(after), isEmpty);
      expect(draft.messagesChangedSince(null), [0, 1]);
    },
  );
  test(
    'structured snapshot and legacy JSON round-trip to identical public record',
    () {
      final original = record(answer: 'Hi', draft: 'Next', resend: true);
      final packed = PackedHistoryRecord.pack(original);
      final restored =
          PackedHistoryRecord.unpack(packed.document(4), packed.messages, {
            for (final entry in packed.attachments.entries)
              entry.key: base64Decode(entry.value.base64Data),
          });
      expect(
        restored.toJson()..remove('session'),
        original.toJson()..remove('session'),
      );
      expect(restored.sessionData, original.sessionData);
      final legacy = ConversationRecord.fromJson(
        jsonDecode(jsonEncode(original.toJson())),
      );
      expect(PackedHistoryRecord.pack(legacy).messages, packed.messages);
    },
  );
  test(
    'missing bytes and wrong media bytes fail without inventing content',
    () {
      final packed = PackedHistoryRecord.pack(record());
      expect(
        () =>
            PackedHistoryRecord.unpack(packed.document(1), packed.messages, {}),
        throwsA(isA<AppFailure>()),
      );
      expect(
        () => PackedHistoryRecord.unpack(packed.document(1), packed.messages, {
          'media-one': [1, 2, 3],
        }),
        throwsA(isA<AppFailure>()),
      );
    },
  );
  test('changed attachment under same identity is refused', () {
    final original = record();
    final before = PackedHistoryRecord.pack(original);
    final changed = original.sessionData;
    final message = (changed['messages'] as List).first as Map;
    (message['attachments'] as List).first['name'] = 'renamed.png';
    expect(
      () => PackedHistoryRecord.pack(original, previous: before),
      throwsA(isA<AppFailure>()),
    );
  });
  test(
    'copyWith keeps structured session and can assign recovered identity',
    () {
      final original = record();
      final copied = original.copyWith(id: 'recovered', draft: 'new draft');
      expect(copied.id, 'recovered');
      expect(copied.sessionData, original.sessionData);
      final replacement = copied.copyWith(
        session: '{"version":1,"messages":[]}',
      );
      expect(replacement.sessionData['messages'], isEmpty);
      expect(replacement.draft, 'new draft');
    },
  );
}
