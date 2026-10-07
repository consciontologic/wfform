import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'conversation.dart';
import 'history_codec.dart';
import 'history_repository.dart';

HistoryRepository createRepository() => IndexedDbHistoryRepository();

/// V2 keeps metadata, individual messages and immutable binary media separate.
/// Legacy V1 records migrate only on a successful atomic checkpoint. An aborted
/// migration leaves the original record and its summary intact.
class IndexedDbHistoryRepository implements HistoryRepository {
  IndexedDbHistoryRepository({
    this.name = databaseName,
    this.onReadTransaction,
  }) {
    try {
      _channel = web.BroadcastChannel('$name-changes');
      _channel!.onmessage = ((web.MessageEvent event) {
        final data = event.data.dartify();
        if (!_closed && data is Map && data['id'] is String) {
          _changes.add(
            HistoryChange(
              data['id'] as String,
              deleted: data['deleted'] == true,
              revision: data['revision'] is int ? data['revision'] as int : 0,
            ),
          );
        }
      }).toJS;
    } catch (_) {
      // Revision checks still protect every write where BroadcastChannel is
      // unavailable. Notifications are an enhancement, not the conflict guard.
    }
  }
  static const databaseName = 'freeform-conversations';
  static const _documents = 'documents_v2';
  static const _messages = 'messages_v2';
  static const _attachments = 'attachments_v2';
  static const _stores = [
    'records',
    'summaries',
    'meta',
    _documents,
    _messages,
    _attachments,
  ];
  final String name;

  /// Browser fault-test seam, called before a read queues its first request.
  /// Application callers leave this unset.
  final void Function(web.IDBTransaction)? onReadTransaction;
  String get _activeKey => '$name.active.v2';
  web.IDBDatabase? _database;
  Future<web.IDBDatabase>? _opening;
  web.BroadcastChannel? _channel;
  final _changes = StreamController<HistoryChange>.broadcast(sync: true);
  final Map<String, int?> _expected = {};
  // Keep only one decoded checkpoint: opening many chats must not retain all
  // their media. Revision numbers are small and remain safe to retain.
  PackedHistoryRecord? _cached;
  bool _closed = false;
  String? _tabActive;
  bool _activeLoaded = false;
  bool _sessionStorageUnavailable = false;
  @override
  Stream<HistoryChange> get changes => _changes.stream;

  Future<web.IDBDatabase> _open() {
    if (_closed) {
      return Future.error(
        historyFailure('Conversation storage is closed. Reload the app.'),
      );
    }
    if (_database != null) return Future.value(_database);
    return _opening ??= _openOnce().whenComplete(() => _opening = null);
  }

  Future<web.IDBDatabase> _openOnce() async {
    final watch = Stopwatch()..start();
    final completion = Completer<web.IDBDatabase>();
    final request = web.window.indexedDB.open(name, 2);
    request.onupgradeneeded = ((web.Event _) {
      final database = request.result as web.IDBDatabase;
      for (final store in _stores) {
        if (!database.objectStoreNames.contains(store)) {
          database.createObjectStore(store);
        }
      }
    }).toJS;
    request.onblocked = ((web.Event _) {
      if (!completion.isCompleted) {
        completion.completeError(
          historyFailure(
            'Conversation storage upgrade is blocked by another open tab. Close the other app tabs and retry.',
          ),
        );
      }
    }).toJS;
    request.onerror = ((web.Event _) {
      if (!completion.isCompleted) {
        completion.completeError(_storageError('open', request.error?.name));
      }
    }).toJS;
    request.onsuccess = ((web.Event _) {
      final database = request.result as web.IDBDatabase;
      if (_closed || completion.isCompleted) {
        database.close();
        return;
      }
      database.onversionchange = ((web.Event _) {
        database.close();
        if (identical(_database, database)) _database = null;
      }).toJS;
      _database = database;
      completion.complete(database);
    }).toJS;
    return completion.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        final failure = historyFailure(
          'Conversation storage did not open in time. Retry or check browser storage permissions.',
          details:
              'operation=open; elapsedMs=${watch.elapsedMilliseconds}; requestState=${request.readyState}. Conversation content omitted.',
        );
        if (!completion.isCompleted) completion.completeError(failure);
        throw failure;
      },
    );
  }

  Future<JSAny?> _result(
    web.IDBRequest request, {
    bool bounded = true,
    void Function()? onSuccess,
  }) {
    final completion = Completer<JSAny?>();
    final watch = Stopwatch()..start();
    request.onsuccess = ((web.Event _) {
      onSuccess?.call();
      completion.complete(request.result);
    }).toJS;
    request.onerror = ((web.Event _) {
      completion.completeError(_storageError('read', request.error?.name));
    }).toJS;
    if (!bounded) return completion.future;
    return completion.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw historyFailure(
        'Conversation storage did not respond in time. Retry opening history; its stored data was retained.',
        details:
            'operation=read request; elapsedMs=${watch.elapsedMilliseconds}; requestState=${request.readyState}. Conversation content omitted.',
      ),
    );
  }

  Future<void> _committed(
    web.IDBTransaction transaction, {
    required String operation,
    required String Function() phase,
  }) {
    final watch = Stopwatch()..start();
    final completion = Completer<void>();
    transaction.oncomplete = ((web.Event _) {
      if (!completion.isCompleted) completion.complete();
    }).toJS;
    transaction.onabort = ((web.Event _) {
      if (!completion.isCompleted) {
        completion.completeError(
          _storageError('commit', transaction.error?.name),
        );
      }
    }).toJS;
    transaction.onerror = ((web.Event _) {
      /* Abort owns error completion. */
    }).toJS;
    return completion.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        final details =
            'operation=$operation; phase=${phase()}; elapsedMs=${watch.elapsedMilliseconds}; mode=${transaction.mode}; transactionError=${transaction.error?.name ?? 'none'}. Conversation content omitted.';
        try {
          transaction.abort();
        } catch (_) {
          /* Already finished. */
        }
        throw historyFailure(
          'Conversation storage did not finish in time. Your in-memory content is retained; retry saving.',
          details: details,
        );
      },
    );
  }

  Map<String, dynamic>? _document(JSAny? value) =>
      value == null || value.isUndefined
      ? null
      : jsonDecode(value.dartify() as String) as Map<String, dynamic>;
  JSAny _partKey(String id, Object part) => jsonEncode([id, part]).toJS;

  @override
  Future<HistoryIndex> loadIndex() async {
    final database = await _open();
    final transaction = database.transaction(
      ['summaries', 'meta'].jsify()!,
      'readonly',
    );
    final rows = _result(transaction.objectStore('summaries').getAll());
    final legacyActive = _result(
      transaction.objectStore('meta').get('active'.toJS),
    );
    final result = await Future.wait([rows, legacyActive]);
    final entries = <ConversationSummary>[];
    final issues = <String>[];
    final values = result[0]?.dartify();
    if (values is! List) {
      throw historyFailure(
        'The conversation index returned an unsupported format. Stored data was retained.',
      );
    }
    for (final value in values) {
      try {
        entries.add(ConversationSummary.fromJson(jsonDecode(value as String)));
      } catch (_) {
        issues.add(
          'A conversation index entry could not be read. Its stored data was retained.',
        );
      }
    }
    entries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (!_activeLoaded) {
      String? saved;
      try {
        saved = web.window.sessionStorage.getItem(_activeKey);
      } catch (_) {
        _sessionStorageUnavailable = true;
      }
      final legacyId = result[1]?.dartify();
      _tabActive = saved == null
          ? (legacyId is String ? legacyId : null)
          : (saved.isEmpty ? null : saved);
      _activeLoaded = true;
      await setActive(_tabActive);
    }
    if (_sessionStorageUnavailable) {
      issues.add(
        'Tab-local session storage is unavailable. History is durable, but this tab’s last-opened conversation will not be remembered after closing it.',
      );
    }
    return HistoryIndex(entries, activeId: _tabActive, issues: issues);
  }

  @override
  Future<ConversationRecord?> read(String id) async {
    final database = await _open();
    final transaction = database.transaction(_stores.jsify()!, 'readonly');
    final result = Completer<ConversationRecord?>();
    final watch = Stopwatch()..start();
    var phase = 'reading document';
    var queued = 1;
    var received = 0;
    web.IDBRequest? latestRequest;
    void fail(Object error) {
      if (!result.isCompleted) result.completeError(error);
    }

    // Every requested value comes from the same readonly snapshot. Once all
    // values are received and decoded, there is no mutation to commit. Waiting
    // for a later completion event can falsely reject an already valid read.
    // Writes below still require their transaction's commit acknowledgment.
    transaction.onabort = ((web.Event _) {
      fail(_storageError('read snapshot', transaction.error?.name));
    }).toJS;
    onReadTransaction?.call(transaction);
    final deadline = Timer(const Duration(seconds: 15), () {
      if (result.isCompleted) return;
      final details =
          'operation=read snapshot; phase=$phase; elapsedMs=${watch.elapsedMilliseconds}; requestsReceived=$received/$queued; latestRequestState=${latestRequest?.readyState ?? 'none'}; transactionError=${transaction.error?.name ?? 'none'}. Conversation content omitted.';
      fail(
        historyFailure(
          'Conversation storage did not return its saved content in time. Retry opening history; its stored data was retained.',
          details: details,
        ),
      );
      try {
        transaction.abort();
      } catch (_) {
        /* Already finished. */
      }
    });
    late final web.IDBRequest request;
    try {
      request = transaction.objectStore(_documents).get(id.toJS);
    } catch (_) {
      deadline.cancel();
      rethrow;
    }
    latestRequest = request;
    request.onerror = ((web.Event _) {
      fail(_storageError('read', request.error?.name));
    }).toJS;
    request.onsuccess = ((web.Event _) {
      if (result.isCompleted) return;
      received++;
      try {
        final document = _document(request.result);
        if (document == null) {
          phase = 'reading legacy record';
          queued++;
          final legacy = transaction.objectStore('records').get(id.toJS);
          latestRequest = legacy;
          legacy.onerror = ((web.Event _) {
            fail(_storageError('read', legacy.error?.name));
          }).toJS;
          legacy.onsuccess = ((web.Event _) {
            if (result.isCompleted) return;
            received++;
            try {
              final raw = legacy.result?.dartify();
              if (raw == null) {
                _expected[id] = null;
                result.complete(null);
                return;
              }
              final record = ConversationRecord.fromJson(
                jsonDecode(raw as String),
              );
              _cached = PackedHistoryRecord.pack(record);
              _expected[id] = 0;
              result.complete(record);
            } catch (_) {
              fail(
                historyFailure(
                  'The selected legacy conversation is damaged. Its stored data was retained.',
                ),
              );
            }
          }).toJS;
          return;
        }
        final count = document['messageCount'] as int;
        if (count < 0 || count > 200) throw const FormatException();
        final metadata = document['attachments'] as Map;
        phase = 'reading messages and attachments';
        queued += count + metadata.length;
        Future<JSAny?> readPart(String store, Object part) {
          final request = transaction
              .objectStore(store)
              .get(_partKey(id, part));
          latestRequest = request;
          return _result(request, bounded: false, onSuccess: () => received++);
        }

        final messageResults = [
          for (var i = 0; i < count; i++) readPart(_messages, i),
        ];
        final mediaResults = <String, Future<JSAny?>>{
          for (final key in metadata.keys)
            key as String: readPart(_attachments, key),
        };
        // Every IDB request is queued while this callback is active. Waiting on
        // their results cannot cause a transaction-inactive error in Safari.
        Future.wait([...messageResults, ...mediaResults.values]).then(
          (values) {
            if (result.isCompleted) return;
            phase = 'decoding snapshot';
            try {
              final messages = values
                  .take(count)
                  .map((value) => value!.dartify() as String)
                  .toList();
              final media = <String, List<int>>{};
              var index = count;
              for (final key in mediaResults.keys) {
                media[key] = (values[index++] as JSUint8Array).toDart;
              }
              final record = PackedHistoryRecord.unpack(
                document,
                messages,
                media,
              );
              _cached = PackedHistoryRecord.pack(record);
              _expected[id] = document['revision'] as int;
              result.complete(record);
            } catch (_) {
              fail(
                historyFailure(
                  'The selected conversation is damaged or has missing media. Its stored data was retained.',
                ),
              );
            }
          },
          onError: (Object error) {
            fail(error);
          },
        );
      } catch (_) {
        fail(
          historyFailure(
            'The selected conversation has an unsupported storage format. Its stored data was retained.',
          ),
        );
      }
    }).toJS;
    return result.future.whenComplete(deadline.cancel);
  }

  @override
  Future<void> save(
    ConversationRecord record, {
    bool makeActive = false,
  }) async {
    var packed = PackedHistoryRecord.pack(
      record,
      previous: _cached?.record.id == record.id ? _cached : null,
    );
    final database = await _open();
    final transaction = database.transaction(_stores.jsify()!, 'readwrite');
    var phase = 'reading current document';
    final complete = _committed(
      transaction,
      operation: 'save',
      phase: () => phase,
    );
    Object? failure;
    HistoryConflictFailure? conflict;
    var revision = 0;
    final documents = transaction.objectStore(_documents);
    final request = documents.get(record.id.toJS);
    request.onsuccess = ((web.Event _) {
      try {
        final previous = _document(request.result);
        phase = 'reading legacy record';
        final legacy = transaction.objectStore('records').get(record.id.toJS);
        legacy.onsuccess = ((web.Event _) {
          try {
            final legacyExists =
                legacy.result != null && !legacy.result.isUndefined;
            final int? actual =
                previous?['revision'] as int? ?? (legacyExists ? 0 : null);
            if (actual != _expected[record.id]) {
              final recovered = recoveryCopy(record);
              conflict = HistoryConflictFailure(
                originalId: record.id,
                recoveryId: recovered.id,
              );
              packed = PackedHistoryRecord.pack(recovered, previous: packed);
            }
            final targetPrevious = conflict == null ? previous : null;
            revision = conflict == null ? (actual ?? 0) + 1 : 1;
            phase = 'checking record capacity';
            final countRequest = transaction.objectStore('summaries').count();
            countRequest.onsuccess = ((web.Event _) {
              try {
                final isNew = conflict != null || actual == null;
                if (isNew &&
                    (countRequest.result!.dartify() as num).toInt() >=
                        maxHistoryRecords) {
                  throw historyFailure(
                    'The 200-conversation storage limit has been reached. Your work remains in memory; export it or explicitly delete an unneeded history before saving.',
                  );
                }
                _enqueueCheckpoint(
                  transaction,
                  packed,
                  revision,
                  targetPrevious,
                  previousPacked:
                      conflict == null && _cached?.record.id == record.id
                      ? _cached
                      : null,
                );
                phase =
                    'checkpoint queued (${packed.messages.length} messages, ${packed.attachments.length} attachments); awaiting commit';
              } catch (error) {
                failure = error;
                transaction.abort();
              }
            }).toJS;
          } catch (error) {
            failure = error;
            transaction.abort();
          }
        }).toJS;
      } catch (error) {
        failure = error;
        transaction.abort();
      }
    }).toJS;
    try {
      await complete;
    } catch (error) {
      throw failure ?? error;
    }
    _cached = packed;
    _expected[packed.record.id] = revision;
    if (makeActive) await setActive(packed.record.id);
    _publish(HistoryChange(packed.record.id, revision: revision));
    if (conflict != null) throw conflict!;
  }

  void _enqueueCheckpoint(
    web.IDBTransaction transaction,
    PackedHistoryRecord packed,
    int revision,
    Map<String, dynamic>? previous, {
    PackedHistoryRecord? previousPacked,
  }) {
    final id = packed.record.id;
    final oldCount = previous?['messageCount'] as int? ?? 0;
    final oldFiles = previous?['attachments'] as Map? ?? const {};
    final messages = transaction.objectStore(_messages);
    for (final i in packed.messagesChangedSince(
      previous == null ? null : previousPacked,
    )) {
      messages.put(packed.messages[i].toJS, _partKey(id, i));
    }
    for (var i = packed.messages.length; i < oldCount; i++) {
      messages.delete(_partKey(id, i));
    }
    final media = transaction.objectStore(_attachments);
    for (final file in packed.attachments.values) {
      final old = oldFiles[file.id];
      if (old != null) {
        final currentMetadata = Map<String, Object?>.from(file.toJson())
          ..remove('base64Data');
        if (jsonEncode(old) != jsonEncode(currentMetadata) ||
            (previousPacked?.attachments[file.id] != null &&
                previousPacked!.attachments[file.id]!.base64Data !=
                    file.base64Data)) {
          throw historyFailure(
            'An immutable attachment changed under the same ID. The prior history was retained.',
          );
        }
      } else {
        media.put(base64Decode(file.base64Data).toJS, _partKey(id, file.id));
      }
    }
    for (final oldId in oldFiles.keys) {
      if (!packed.attachments.containsKey(oldId)) {
        media.delete(_partKey(id, oldId));
      }
    }
    transaction
        .objectStore(_documents)
        .put(jsonEncode(packed.document(revision)).toJS, id.toJS);
    transaction
        .objectStore('summaries')
        .put(jsonEncode(packed.record.summary.toJson()).toJS, id.toJS);
    // Removal participates in the same transaction as all V2 writes. Abort,
    // quota failure or process interruption cannot leave a half-migrated chat.
    transaction.objectStore('records').delete(id.toJS);
  }

  @override
  Future<void> setActive(String? id) async {
    _tabActive = id;
    _activeLoaded = true;
    try {
      web.window.sessionStorage.setItem(_activeKey, id ?? '');
    } catch (_) {
      _sessionStorageUnavailable = true;
    }
  }

  @override
  Future<void> delete(String id) async {
    final database = await _open();
    final transaction = database.transaction(_stores.jsify()!, 'readwrite');
    var phase = 'reading current document';
    final complete = _committed(
      transaction,
      operation: 'delete',
      phase: () => phase,
    );
    Object? failure;
    final request = transaction.objectStore(_documents).get(id.toJS);
    request.onsuccess = ((web.Event _) {
      try {
        final document = _document(request.result);
        if (document != null) {
          if (_expected.containsKey(id) &&
              document['revision'] != _expected[id]) {
            throw historyFailure(
              'Another tab changed this conversation. Reopen it and review the latest version before deleting it.',
            );
          }
          for (var i = 0; i < (document['messageCount'] as int); i++) {
            transaction.objectStore(_messages).delete(_partKey(id, i));
          }
          for (final key in (document['attachments'] as Map).keys) {
            transaction.objectStore(_attachments).delete(_partKey(id, key));
          }
          transaction.objectStore(_documents).delete(id.toJS);
        }
        transaction.objectStore('records').delete(id.toJS);
        transaction.objectStore('summaries').delete(id.toJS);
        phase = 'deletes queued; checking legacy active record';
        final legacyActive = transaction.objectStore('meta').get('active'.toJS);
        legacyActive.onsuccess = ((web.Event _) {
          if (legacyActive.result?.dartify() == id) {
            transaction.objectStore('meta').delete('active'.toJS);
          }
          phase = 'deletes queued; awaiting commit';
        }).toJS;
      } catch (error) {
        failure = error;
        transaction.abort();
      }
    }).toJS;
    try {
      await complete;
    } catch (error) {
      throw failure ?? error;
    }
    _expected.remove(id);
    if (_cached?.record.id == id) _cached = null;
    if (_tabActive == id) await setActive(null);
    _publish(HistoryChange(id, deleted: true));
  }

  void _publish(HistoryChange change) {
    _channel?.postMessage(
      {
        'id': change.id,
        'deleted': change.deleted,
        'revision': change.revision,
      }.jsify(),
    );
  }

  Object _storageError(String operation, String? errorName) => historyFailure(
    errorName == 'QuotaExceededError'
        ? 'Browser storage is full. This conversation remains in memory. Explicitly delete unneeded histories or free browser storage, then retry saving.'
        : 'Conversation storage could not $operation. Check browser storage permissions and retry. Current content remains in memory.',
    details:
        'IndexedDB operation: $operation; error type: ${errorName ?? 'unknown'}. Conversation content omitted.',
  );

  @override
  void close() {
    _closed = true;
    _database?.close();
    _database = null;
    _cached = null;
    _channel?.close();
    _changes.close();
  }
}
