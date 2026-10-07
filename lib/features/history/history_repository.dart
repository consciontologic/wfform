import 'dart:async';
import 'dart:convert';

import '../../shared/diagnostics.dart';

import 'conversation.dart';
import 'history_repository_stub.dart'
    if (dart.library.js_interop) 'history_repository_web.dart'
    as implementation;

const maxHistoryRecords = 200;
const maxHistoryRecordBytes = 32 * 1024 * 1024;

abstract interface class HistoryRepository {
  /// Other tabs changed durable history. This does not replace a loaded record
  /// or advance its expected revision: unsaved work must remain conflict-safe.
  Stream<HistoryChange> get changes;
  Future<HistoryIndex> loadIndex();
  Future<ConversationRecord?> read(String id);
  Future<void> save(ConversationRecord record, {bool makeActive = false});
  Future<void> setActive(String? id);
  Future<void> delete(String id);
  void close();
}

class HistoryChange {
  const HistoryChange(this.id, {this.deleted = false, this.revision = 0});
  final String id;
  final bool deleted;
  final int revision;
}

class HistoryConflictFailure extends AppFailure {
  HistoryConflictFailure({required this.originalId, required this.recoveryId})
    : super(
        FailureKind.storage,
        'Another tab changed this conversation. Your work was saved as a separate recovered conversation; the other version was not overwritten.',
      );
  final String originalId, recoveryId;
}

ConversationRecord recoveryCopy(ConversationRecord record) {
  final prefix = record.id.substring(0, record.id.length.clamp(0, 40));
  return record.copyWith(
    id: '$prefix-recovered-${DateTime.now().microsecondsSinceEpoch}',
    title:
        'Recovered copy · ${record.title.substring(0, record.title.length.clamp(0, 180))}',
    archived: false,
    updatedAt: DateTime.now().toUtc(),
  );
}

HistoryRepository createHistoryRepository() =>
    implementation.createRepository();

String encodeHistoryRecord(ConversationRecord record) {
  final encoded = jsonEncode(record.toJson());
  if (utf8.encode(encoded).length > maxHistoryRecordBytes) {
    throw historyFailure(
      'This conversation exceeds the 32 MiB local record limit. Copy or export it before starting a new chat; no history was deleted.',
    );
  }
  ConversationRecord.fromJson(record.toJson());
  return encoded;
}

/// Replaceable in-memory implementation for deterministic tests and future ports.
/// Browser failures do not silently fall back to this repository.
class MemoryHistoryDatabase {
  final Map<String, String> records = {};
  final Map<String, int> revisions = {};
  final events =
      StreamController<({Object source, HistoryChange change})>.broadcast(
        sync: true,
      );
}

class MemoryHistoryRepository implements HistoryRepository {
  MemoryHistoryRepository({MemoryHistoryDatabase? database})
    : database = database ?? MemoryHistoryDatabase();
  final MemoryHistoryDatabase database;
  Map<String, String> get records => database.records;
  final Map<String, int?> _expected = {};
  @override
  Stream<HistoryChange> get changes => database.events.stream
      .where((event) => !identical(event.source, this))
      .map((event) => event.change);
  String? activeId;
  int writes = 0;
  @override
  Future<HistoryIndex> loadIndex() async {
    final entries = <ConversationSummary>[];
    final issues = <String>[];
    for (final entry in records.entries) {
      try {
        entries.add(
          ConversationRecord.fromJson(jsonDecode(entry.value)).summary,
        );
      } catch (_) {
        issues.add(
          'Conversation ${entry.key} could not be read; its stored data was retained.',
        );
      }
    }
    entries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return HistoryIndex(entries, activeId: activeId, issues: issues);
  }

  @override
  Future<ConversationRecord?> read(String id) async {
    final raw = records[id];
    if (raw == null) return null;
    try {
      final record = ConversationRecord.fromJson(jsonDecode(raw));
      _expected[id] = database.revisions[id] ?? 0;
      return record;
    } catch (_) {
      throw historyFailure(
        'Conversation $id could not be read. Its stored data was retained.',
      );
    }
  }

  @override
  Future<void> save(
    ConversationRecord record, {
    bool makeActive = false,
  }) async {
    final encoded = encodeHistoryRecord(record);
    final current = records.containsKey(record.id)
        ? database.revisions[record.id] ?? 0
        : null;
    if (current != _expected[record.id]) {
      final recovered = recoveryCopy(record);
      await save(recovered, makeActive: makeActive);
      throw HistoryConflictFailure(
        originalId: record.id,
        recoveryId: recovered.id,
      );
    }
    if (!records.containsKey(record.id) &&
        records.length >= maxHistoryRecords) {
      throw historyFailure(
        'The 200-conversation storage limit has been reached. Explicitly delete a conversation before saving another; archiving does not free storage.',
      );
    }
    records[record.id] = encoded;
    final revision = (current ?? 0) + 1;
    database.revisions[record.id] = revision;
    _expected[record.id] = revision;
    if (makeActive) activeId = record.id;
    writes++;
    database.events.add((
      source: this,
      change: HistoryChange(record.id, revision: revision),
    ));
  }

  @override
  Future<void> setActive(String? id) async {
    activeId = id;
  }

  @override
  Future<void> delete(String id) async {
    final current = records.containsKey(id)
        ? database.revisions[id] ?? 0
        : null;
    if (_expected.containsKey(id) && current != _expected[id]) {
      throw historyFailure(
        'Another tab changed this conversation. Reopen it and review the latest version before deleting it.',
      );
    }
    records.remove(id);
    database.revisions.remove(id);
    _expected.remove(id);
    if (activeId == id) activeId = null;
    database.events.add((
      source: this,
      change: HistoryChange(id, deleted: true),
    ));
  }

  @override
  void close() {}
}
