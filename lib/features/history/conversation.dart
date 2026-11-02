import 'dart:convert';

import '../../shared/diagnostics.dart';
import '../chat/attachment.dart';
import '../tools/tools.dart';

class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.modelId,
    this.modelName,
    this.archived = false,
    this.messageCount = 0,
    bool? isDraft,
  }) : _isDraft = isDraft;
  final String id, title;
  final String? modelId, modelName;
  final DateTime createdAt, updatedAt;
  final bool archived;
  final int messageCount;
  final bool? _isDraft;

  /// Old archived work must remain accessible through its existing actions.
  /// New records carry an explicit dispatch-derived marker.
  bool get isDraft => _isDraft ?? (messageCount == 0 && !archived);

  Map<String, Object?> toJson() => {
    'version': 1,
    'id': id,
    'title': title,
    'modelId': modelId,
    'modelName': modelName,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'archived': archived,
    'messageCount': messageCount,
    'isDraft': isDraft,
  };

  factory ConversationSummary.fromJson(Object? value) {
    if (value is! Map ||
        value['version'] != 1 ||
        value['id'] is! String ||
        (value['id'] as String).isEmpty ||
        (value['id'] as String).length > 100 ||
        value['title'] is! String ||
        (value['title'] as String).length > 200 ||
        (value['modelId'] != null && value['modelId'] is! String) ||
        (value['modelName'] != null && value['modelName'] is! String) ||
        value['archived'] is! bool ||
        value['messageCount'] is! int ||
        (value['messageCount'] as int) < 0 ||
        (value.containsKey('isDraft') && value['isDraft'] is! bool) ||
        value['createdAt'] is! String ||
        value['updatedAt'] is! String) {
      throw historyFailure(
        'A saved conversation has an unsupported or damaged metadata format. It was retained unchanged.',
      );
    }
    final created = DateTime.tryParse(value['createdAt'] as String);
    final updated = DateTime.tryParse(value['updatedAt'] as String);
    if (created == null || updated == null) {
      throw historyFailure(
        'A saved conversation has invalid dates. It was retained unchanged.',
      );
    }
    return ConversationSummary(
      id: value['id'] as String,
      title: value['title'] as String,
      modelId: value['modelId'] as String?,
      modelName: value['modelName'] as String?,
      archived: value['archived'] as bool,
      createdAt: created,
      updatedAt: updated,
      messageCount: value['messageCount'] as int,
      isDraft: value['isDraft'] as bool?,
    );
  }
}

class ConversationRecord extends ConversationSummary {
  const ConversationRecord({
    required super.id,
    required super.title,
    required super.createdAt,
    required super.updatedAt,
    super.modelId,
    super.modelName,
    super.archived,
    super.messageCount,
    super.isDraft,
    required this.draft,
    String? session,
    Map<String, dynamic>? sessionData,
    this.draftAttachments = const [],
  }) : assert(session != null || sessionData != null),
       _session = session,
       _sessionData = sessionData;
  final String draft;
  final String? _session;
  final Map<String, dynamic>? _sessionData;

  /// The application supplies structured snapshots so routine checkpoints never
  /// encode media. The legacy string remains available for import and restore.
  Map<String, dynamic> get sessionData =>
      _sessionData ?? jsonDecode(_session!) as Map<String, dynamic>;
  String get session => _session ?? jsonEncode(_sessionData);
  final List<ChatAttachment> draftAttachments;
  ConversationSummary get summary => ConversationSummary(
    id: id,
    title: title,
    createdAt: createdAt,
    updatedAt: updatedAt,
    modelId: modelId,
    modelName: modelName,
    archived: archived,
    messageCount: messageCount,
    isDraft: isDraft,
  );
  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'draft': draft,
    'session': session,
    if (draftAttachments.isNotEmpty)
      'draftAttachments': draftAttachments
          .map((file) => file.toJson())
          .toList(),
  };
  ConversationRecord copyWith({
    String? id,
    bool? archived,
    String? draft,
    String? session,
    Map<String, dynamic>? sessionData,
    String? title,
    String? modelId,
    String? modelName,
    DateTime? updatedAt,
    int? messageCount,
    bool? isDraft,
    List<ChatAttachment>? draftAttachments,
  }) => ConversationRecord(
    id: id ?? this.id,
    title: title ?? this.title,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    modelId: modelId ?? this.modelId,
    modelName: modelName ?? this.modelName,
    archived: archived ?? this.archived,
    draft: draft ?? this.draft,
    session: session ?? (sessionData == null ? _session : null),
    sessionData: session == null ? sessionData ?? _sessionData : null,
    messageCount: messageCount ?? this.messageCount,
    isDraft: isDraft ?? this.isDraft,
    draftAttachments: draftAttachments ?? this.draftAttachments,
  );

  factory ConversationRecord.fromJson(Object? value) {
    final summary = ConversationSummary.fromJson(value);
    final map = value as Map;
    if (map['draft'] is! String || map['session'] is! String) {
      throw historyFailure(
        'The saved conversation body is damaged. It was retained unchanged.',
      );
    }
    List<ChatAttachment> draftAttachments = const [];
    try {
      final files = map['draftAttachments'];
      if (files != null) {
        if (files is! List || files.length > 4) throw const FormatException();
        draftAttachments = List.unmodifiable(
          files.map(ChatAttachment.fromJson),
        );
        validateAttachments(draftAttachments);
      }
      final parsed = jsonDecode(map['session'] as String);
      validateHistorySession(parsed);
    } catch (_) {
      throw historyFailure(
        'The saved conversation session is damaged or unsupported. It was retained unchanged.',
      );
    }
    return ConversationRecord(
      id: summary.id,
      title: summary.title,
      createdAt: summary.createdAt,
      updatedAt: summary.updatedAt,
      modelId: summary.modelId,
      modelName: summary.modelName,
      archived: summary.archived,
      messageCount: summary.messageCount,
      isDraft: summary.isDraft,
      draft: map['draft'] as String,
      session: map['session'] as String,
      draftAttachments: draftAttachments,
    );
  }
}

/// Shared by legacy imports and packed checkpoints. Incomplete trailing tool
/// groups are retained as evidence; restoration decides how to close them
/// without resuming external actions.
List<Map<String, dynamic>> validateHistorySession(Object? value) {
  try {
    if (value is! Map || value['version'] != 1 || value['messages'] is! List) {
      throw const FormatException('Unsupported session format.');
    }
    final parameters = value['requestParameters'];
    if (parameters != null &&
        (parameters is! Map ||
            parameters.keys.any((key) => key is! String) ||
            jsonEncode(parameters).length > 65536)) {
      throw const FormatException('Invalid stored parameters.');
    }
    final tools = value['enabledTools'];
    if (tools != null &&
        (tools is! List ||
            tools.length > 64 ||
            tools.any(
              (name) =>
                  name is! String ||
                  !RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(name),
            ))) {
      throw const FormatException('Invalid stored tool selection.');
    }
    if (value.containsKey('toolAttempted') && value['toolAttempted'] is! bool) {
      throw const FormatException('Invalid stored tool execution state.');
    }
    final messages = <Map<String, dynamic>>[];
    for (final raw in value['messages'] as List) {
      if (raw is! Map ||
          !{'user', 'assistant', 'tool'}.contains(raw['role']) ||
          raw['content'] is! String ||
          raw['reasoning'] is! String ||
          raw['complete'] is! bool ||
          (raw['modelId'] != null && raw['modelId'] is! String) ||
          (raw.containsKey('toolCalls') && raw['toolCalls'] is! List) ||
          (raw['toolCallId'] != null && raw['toolCallId'] is! String) ||
          (raw['role'] == 'tool' && raw['complete'] != true)) {
        throw const FormatException('Invalid stored message.');
      }
      // The saved format uses camelCase. Accepting API aliases here would let
      // a later local restore silently discard the associated call evidence.
      if (raw.containsKey('tool_calls') ||
          raw.containsKey('tool_call_id') ||
          raw.containsKey('reasoning_details')) {
        throw const FormatException(
          'API message fields are not local history fields.',
        );
      }
      final details = raw['reasoningDetails'];
      if (details != null &&
          (details is! List ||
              details.any(
                (item) =>
                    item is! Map || item.keys.any((key) => key is! String),
              ))) {
        throw const FormatException('Invalid stored reasoning details.');
      }
      messages.add(Map<String, dynamic>.from(raw));
    }
    validateToolTranscript(messages, allowPending: true);
    return messages;
  } catch (_) {
    throw historyFailure(
      'The saved conversation session is damaged or unsupported. It was retained unchanged.',
    );
  }
}

AppFailure historyFailure(String message, {String? details}) =>
    AppFailure(FailureKind.storage, message, retryable: true, details: details);

class HistoryIndex {
  const HistoryIndex(this.entries, {this.activeId, this.issues = const []});
  final List<ConversationSummary> entries;
  final String? activeId;
  final List<String> issues;
}
