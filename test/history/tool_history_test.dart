import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/features/history/conversation.dart';
import 'package:wfform/features/history/history_codec.dart';
import 'package:wfform/shared/diagnostics.dart';

Map<String, dynamic> turn(
  String role, {
  String content = '',
  Map<String, dynamic> fields = const {},
}) => {
  'role': role,
  'content': content,
  'reasoning': '',
  'complete': true,
  ...fields,
};

const call = {
  'id': 'call-1',
  'type': 'function',
  'function': {'name': 'fixture_read', 'arguments': '{"path":"note.txt"}'},
};

ConversationRecord record(
  List<Map<String, dynamic>> messages, {
  Map<String, dynamic> fields = const {},
}) => ConversationRecord(
  id: 'tools',
  title: 'Tool history',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  draft: 'Next question',
  messageCount: messages.length,
  sessionData: {'version': 1, 'messages': messages, ...fields},
);

void main() {
  test(
    'tool calls, results, reasoning and settings survive both storage formats',
    () {
      final original = record(
        [
          turn('user', content: 'Read the note'),
          turn(
            'assistant',
            fields: {
              'toolCalls': [call],
              'reasoningDetails': [
                {
                  'type': 'reasoning.encrypted',
                  'data': 'opaque-provider-data',
                  'index': 0,
                },
              ],
            },
          ),
          turn('tool', content: 'Saved note', fields: {'toolCallId': 'call-1'}),
          turn('assistant', content: 'The note says hello.'),
        ],
        fields: {
          'requestParameters': {'temperature': 0, 'logprobs': false},
          'enabledTools': ['fixture_read'],
          'toolAttempted': true,
        },
      );
      final legacy = ConversationRecord.fromJson(original.toJson());
      expect(legacy.sessionData, original.sessionData);
      final packed = PackedHistoryRecord.pack(original);
      final restored = PackedHistoryRecord.unpack(
        packed.document(1),
        packed.messages,
        {},
      );
      expect(restored.sessionData, original.sessionData);
      expect(restored.draft, 'Next question');
    },
  );

  test(
    'interrupted trailing tool group is retained without inventing results',
    () {
      final original = record([
        turn('user', content: 'Read the note'),
        turn(
          'assistant',
          fields: {
            'toolCalls': [call],
            'complete': false,
          },
        ),
      ]);
      final legacy = ConversationRecord.fromJson(original.toJson());
      final packed = PackedHistoryRecord.pack(legacy);
      final restored = PackedHistoryRecord.unpack(
        packed.document(1),
        packed.messages,
        {},
      );
      expect(
        restored.sessionData['messages'],
        original.sessionData['messages'],
      );
    },
  );

  test(
    'orphan, duplicate, malformed and interrupted interior groups are refused',
    () {
      final requests = turn(
        'assistant',
        fields: {
          'toolCalls': [call],
        },
      );
      final result = turn('tool', fields: {'toolCallId': 'call-1'});
      final invalid = <List<Map<String, dynamic>>>[
        [result],
        [requests, result, result],
        [requests, turn('user', content: 'New question')],
        [
          requests,
          turn('tool', fields: {'toolCallId': 'different'}),
        ],
        [
          turn(
            'user',
            fields: {
              'toolCalls': [call],
            },
          ),
        ],
        [
          turn(
            'assistant',
            fields: {
              'toolCalls': {'bad': true},
            },
          ),
        ],
        [
          turn(
            'assistant',
            fields: {
              'toolCalls': [
                {'id': 'bad'},
              ],
            },
          ),
        ],
        [
          requests,
          turn(
            'tool',
            fields: {
              'toolCallId': 'call-1',
              'toolCalls': {'bad': true},
            },
          ),
        ],
        [
          turn('assistant', fields: {'reasoningDetails': 'bad'}),
        ],
        [
          turn(
            'assistant',
            fields: {
              'reasoningDetails': [1],
            },
          ),
        ],
      ];
      for (final messages in invalid) {
        final original = record(messages);
        expect(
          () => ConversationRecord.fromJson(original.toJson()),
          throwsA(isA<AppFailure>()),
        );
        expect(
          () => PackedHistoryRecord.pack(original),
          throwsA(isA<AppFailure>()),
        );
      }
    },
  );

  test(
    'malformed per-conversation settings are refused without losing original data',
    () {
      for (final fields in [
        {'requestParameters': []},
        {'enabledTools': 'fixture_read'},
        {
          'enabledTools': [123],
        },
        {
          'enabledTools': ['invalid name'],
        },
        {'toolAttempted': 'yes'},
      ]) {
        final original = record([], fields: fields);
        expect(
          () => ConversationRecord.fromJson(original.toJson()),
          throwsA(isA<AppFailure>()),
        );
        expect(
          () => PackedHistoryRecord.pack(original),
          throwsA(isA<AppFailure>()),
        );
        expect(
          original.sessionData,
          containsPair(fields.keys.first, fields.values.first),
        );
      }
    },
  );
}
