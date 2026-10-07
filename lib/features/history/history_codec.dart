import 'dart:convert';

import '../chat/attachment.dart';
import 'conversation.dart';
import 'history_repository.dart' show maxHistoryRecordBytes;

/// A checkpoint contains small message JSON and references to immutable media.
/// Binary media is written only when a new attachment ID enters a conversation.
class PackedHistoryRecord {
  PackedHistoryRecord._({
    required this.record,
    required this.messages,
    required this.sessionFields,
    required this.attachments,
    required this.draftIds,
  });
  final ConversationRecord record;
  final List<String> messages;
  final Map<String, dynamic> sessionFields;
  final Map<String, ChatAttachment> attachments;
  final List<String> draftIds;

  factory PackedHistoryRecord.pack(
    ConversationRecord record, {
    PackedHistoryRecord? previous,
  }) {
    ConversationSummary.fromJson(record.summary.toJson());
    final source = record.sessionData;
    if (source['version'] != 1 || source['messages'] is! List) {
      throw historyFailure(
        'The conversation session has an unsupported format.',
      );
    }
    final files = <String, ChatAttachment>{};
    ChatAttachment retain(Object? raw) {
      if (raw is! Map || raw['id'] is! String) {
        throw historyFailure('A conversation attachment is malformed.');
      }
      final id = raw['id'] as String;
      final known = files[id] ?? previous?.attachments[id];
      if (known != null && !_sameAttachment(known, raw)) {
        throw historyFailure(
          'An immutable attachment changed under the same local ID. The prior history was retained.',
        );
      }
      final file = known ?? ChatAttachment.fromJson(raw);
      files[id] = file;
      return file;
    }

    // Count the export's exact encoded size without serializing any base64
    // payload. Base64 is ASCII and gains no JSON escaping at either level.
    var payloadChars = 0;
    final sizedMessages = <Map<String, dynamic>>[];
    final messages = <String>[];
    for (final raw in source['messages'] as List) {
      if (raw is! Map ||
          !{'user', 'assistant'}.contains(raw['role']) ||
          raw['content'] is! String ||
          raw['reasoning'] is! String ||
          raw['complete'] is! bool ||
          (raw['modelId'] != null && raw['modelId'] is! String)) {
        throw historyFailure(
          'A conversation message has an unsupported format.',
        );
      }
      final message = Map<String, dynamic>.from(raw);
      final sizedMessage = Map<String, dynamic>.from(raw);
      final media = message.remove('attachments');
      if (media != null) {
        if (media is! List) throw historyFailure('Invalid attachment list.');
        final attached = media.map(retain).toList();
        validateAttachments(attached);
        message['attachmentIds'] = attached.map((file) => file.id).toList();
        sizedMessage['attachments'] = attached
            .map((file) => file.toJson()..['base64Data'] = '')
            .toList();
        for (final file in attached) {
          payloadChars += file.base64Data.length;
        }
      }
      final encoded = jsonEncode(message);
      messages.add(encoded);
      sizedMessages.add(sizedMessage);
    }
    validateAttachments(record.draftAttachments);
    for (final file in record.draftAttachments) {
      retain(file.toJson());
      payloadChars += file.base64Data.length;
    }
    final sessionFields = Map<String, dynamic>.from(source)..remove('messages');
    final sizedRecord = {
      ...record.summary.toJson(),
      'draft': record.draft,
      'session': jsonEncode({...sessionFields, 'messages': sizedMessages}),
      if (record.draftAttachments.isNotEmpty)
        'draftAttachments': record.draftAttachments
            .map((file) => file.toJson()..['base64Data'] = '')
            .toList(),
    };
    if (utf8.encode(jsonEncode(sizedRecord)).length + payloadChars >
        maxHistoryRecordBytes) {
      throw historyFailure(
        'This conversation exceeds the 32 MiB local record limit. Export it before starting a new chat; no history was deleted.',
      );
    }
    return PackedHistoryRecord._(
      record: record,
      messages: List.unmodifiable(messages),
      sessionFields: sessionFields,
      attachments: Map.unmodifiable(files),
      draftIds: record.draftAttachments.map((file) => file.id).toList(),
    );
  }

  Map<String, dynamic> document(int revision) => {
    'storageVersion': 2,
    'revision': revision,
    'summary': record.summary.toJson(),
    'draft': record.draft,
    'sessionFields': sessionFields,
    'messageCount': messages.length,
    'draftIds': draftIds,
    'attachments': {
      for (final file in attachments.values)
        file.id: Map<String, Object?>.from(file.toJson())..remove('base64Data'),
    },
  };

  Iterable<int> messagesChangedSince(PackedHistoryRecord? previous) sync* {
    for (var i = 0; i < messages.length; i++) {
      if (previous == null ||
          i >= previous.messages.length ||
          previous.messages[i] != messages[i]) {
        yield i;
      }
    }
  }

  static bool _sameAttachment(ChatAttachment file, Map raw) =>
      raw['version'] == 1 &&
      raw['id'] == file.id &&
      raw['name'] == file.name &&
      raw['mimeType'] == file.mimeType &&
      raw['kind'] == file.kind.name &&
      raw['byteLength'] == file.byteLength &&
      raw['base64Data'] == file.base64Data;

  /// Reconstitute only the requested conversation. Stored history summaries do
  /// not load either message text or media into memory.
  static ConversationRecord unpack(
    Map<String, dynamic> document,
    List<String> messages,
    Map<String, List<int>> bytes,
  ) {
    if (document['storageVersion'] != 2 ||
        document['revision'] is! int ||
        document['messageCount'] != messages.length ||
        document['draft'] is! String ||
        document['sessionFields'] is! Map ||
        document['attachments'] is! Map ||
        document['draftIds'] is! List) {
      throw historyFailure('The conversation storage format is damaged.');
    }
    final summary = ConversationSummary.fromJson(document['summary']);
    final files = <String, ChatAttachment>{};
    for (final entry in (document['attachments'] as Map).entries) {
      final raw = Map<String, dynamic>.from(entry.value as Map);
      final data = bytes[entry.key];
      if (data == null) throw historyFailure('A stored attachment is missing.');
      raw['base64Data'] = base64Encode(data);
      files[entry.key as String] = ChatAttachment.fromJson(raw);
    }
    final decodedMessages = messages.map((encoded) {
      final message = jsonDecode(encoded) as Map<String, dynamic>;
      final ids = message.remove('attachmentIds');
      if (ids != null) {
        message['attachments'] = (ids as List).map((id) {
          final file = files[id];
          if (file == null) {
            throw historyFailure('A stored attachment is missing.');
          }
          return file.toJson();
        }).toList();
      }
      return message;
    }).toList();
    final record = ConversationRecord(
      id: summary.id,
      title: summary.title,
      modelId: summary.modelId,
      modelName: summary.modelName,
      createdAt: summary.createdAt,
      updatedAt: summary.updatedAt,
      archived: summary.archived,
      messageCount: summary.messageCount,
      isDraft: summary.isDraft,
      draft: document['draft'] as String,
      sessionData: {
        ...Map<String, dynamic>.from(document['sessionFields'] as Map),
        'messages': decodedMessages,
      },
      draftAttachments: (document['draftIds'] as List).map((id) {
        final file = files[id];
        if (file == null) {
          throw historyFailure('A stored draft attachment is missing.');
        }
        return file;
      }).toList(),
    );
    PackedHistoryRecord.pack(record);
    return record;
  }
}
