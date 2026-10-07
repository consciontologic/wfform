// Opt-in real browser storage checks. Uses generated test-only databases.
// CHROME_EXECUTABLE=/path/to/chrome flutter test --platform chrome \
//   test/history/browser/indexeddb_checks.dart
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;
import 'package:wfform/features/history/conversation.dart';
import 'package:wfform/features/history/history_repository.dart';
import 'package:wfform/features/history/history_repository_web.dart';

import '../history_codec_test.dart' as fixture;

Future<JSAny?> result(web.IDBRequest request) {
  final done = Completer<JSAny?>();
  request.onsuccess = ((web.Event _) => done.complete(request.result)).toJS;
  request.onerror = ((web.Event _) => done.completeError(
    StateError(request.error?.name ?? 'IDB error'),
  )).toJS;
  return done.future;
}

Future<void> committed(web.IDBTransaction tx) {
  final done = Completer<void>();
  tx.oncomplete = ((web.Event _) => done.complete()).toJS;
  tx.onabort = ((web.Event _) => done.completeError(
    StateError('Aborted'),
  )).toJS;
  return done.future;
}

Future<web.IDBDatabase> open(String name, [int? version]) async =>
    (await result(
          version == null
              ? web.window.indexedDB.open(name)
              : web.window.indexedDB.open(name, version),
        ))
        as web.IDBDatabase;
Future<void> seedLegacy(String name, ConversationRecord record) async {
  final request = web.window.indexedDB.open(name, 1);
  request.onupgradeneeded = ((web.Event _) {
    final db = request.result as web.IDBDatabase;
    for (final name in ['records', 'summaries', 'meta']) {
      db.createObjectStore(name);
    }
  }).toJS;
  final db = (await result(request)) as web.IDBDatabase;
  final tx = db.transaction(
    ['records', 'summaries', 'meta'].jsify()!,
    'readwrite',
  );
  final done = committed(tx);
  tx
      .objectStore('records')
      .put(encodeHistoryRecord(record).toJS, record.id.toJS);
  tx
      .objectStore('summaries')
      .put(jsonEncode(record.summary.toJson()).toJS, record.id.toJS);
  tx.objectStore('meta').put(record.id.toJS, 'active'.toJS);
  await done;
  db.close();
}

Future<JSAny?> get(web.IDBDatabase db, String store, JSAny key) =>
    result(db.transaction(store.toJS, 'readonly').objectStore(store).get(key));
Future<void> put(
  web.IDBDatabase db,
  String store,
  JSAny key,
  JSAny value,
) async {
  final tx = db.transaction(store.toJS, 'readwrite');
  final done = committed(tx);
  tx.objectStore(store).put(value, key);
  await done;
}

JSAny key(Object part) => jsonEncode(['one', part]).toJS;

void main() {
  String name = '';
  final repositories = <IndexedDbHistoryRepository>[];
  setUp(() {
    name = 'wfform-history-test-${DateTime.now().microsecondsSinceEpoch}';
  });
  tearDown(() async {
    for (final repo in repositories) {
      repo.close();
    }
    repositories.clear();
    web.window.sessionStorage.removeItem('$name.active.v2');
    await result(web.window.indexedDB.deleteDatabase(name));
  });
  IndexedDbHistoryRepository repository() {
    final repo = IndexedDbHistoryRepository(name: name);
    repositories.add(repo);
    return repo;
  }

  test(
    'readonly snapshot restores media without waiting for completion delivery',
    () async {
      final original = fixture.record(draft: 'Saved media draft', resend: true);
      await repository().save(original, makeActive: true);
      final suppressedCompletion = Completer<void>();
      final reader = IndexedDbHistoryRepository(
        name: name,
        onReadTransaction: (transaction) {
          // Actual IDB requests run normally. Prevent the later completion
          // event from reaching oncomplete: the prior read implementation
          // waited for that event and timed out despite a valid snapshot.
          transaction.addEventListener(
            'complete',
            ((web.Event event) {
              event.stopImmediatePropagation();
              suppressedCompletion.complete();
            }).toJS,
          );
        },
      );
      repositories.add(reader);
      expect((await reader.loadIndex()).activeId, original.id);
      final restored = (await reader
          .read(original.id)
          .timeout(const Duration(seconds: 3)))!;
      expect(restored.draft, original.draft);
      expect(restored.sessionData, original.sessionData);
      expect(restored.draftAttachments.single.base64Data, fixture.png);
      await suppressedCompletion.future.timeout(const Duration(seconds: 3));
      // A subsequent write still uses the restored revision and must commit.
      await reader.save(restored.copyWith(draft: 'Continued draft'));
      expect((await repository().read(original.id))!.draft, 'Continued draft');
    },
  );

  test(
    'an aborted pending read fails without publishing an empty snapshot',
    () async {
      final original = fixture.record(draft: 'Durable before aborted read');
      await repository().save(original, makeActive: true);
      var abortReads = true;
      final reader = IndexedDbHistoryRepository(
        name: name,
        onReadTransaction: (transaction) {
          if (!abortReads) return;
          // This request is queued before the repository's document request, so
          // its success deterministically aborts while that read is pending.
          final before = transaction
              .objectStore('documents_v2')
              .get('one'.toJS);
          before.onsuccess = ((web.Event _) => transaction.abort()).toJS;
        },
      );
      repositories.add(reader);
      await expectLater(
        reader.read(original.id).timeout(const Duration(seconds: 3)),
        throwsA(isA<Exception>()),
      );
      abortReads = false;
      final restored = (await reader.read(original.id))!;
      expect(restored.sessionData, original.sessionData);
      expect(restored.draft, original.draft);
    },
  );

  test(
    'real IndexedDB migrates V1 atomically, stores binary once and reads V2',
    () async {
      final legacy = fixture.record(answer: 'old', draft: 'keep', resend: true);
      await seedLegacy(name, legacy);
      final repo = repository();
      expect((await repo.loadIndex()).activeId, 'one');
      final loaded = (await repo.read('one'))!;
      expect(loaded.sessionData, legacy.sessionData);
      var db = await open(name);
      expect(
        (await get(db, 'records', 'one'.toJS)),
        isNotNull,
        reason: 'Read alone retains legacy data',
      );
      db.close();
      await repo.save(loaded.copyWith(draft: 'changed'), makeActive: true);
      db = await open(name);
      expect(await get(db, 'records', 'one'.toJS), isNull);
      final document =
          jsonDecode(
                (await get(db, 'documents_v2', 'one'.toJS))!.dartify()
                    as String,
              )
              as Map;
      expect(document['revision'], 1);
      expect(jsonEncode(document), isNot(contains(fixture.png)));
      expect(
        (await get(db, 'attachments_v2', key('media-one')) as JSUint8Array)
            .toDart,
        base64Decode(fixture.png),
      );
      expect(
        (await result(
          db
              .transaction('attachments_v2'.toJS)
              .objectStore('attachments_v2')
              .count(),
        ))!.dartify(),
        1,
      );
      db.close();
      final fresh = repository();
      final restored = (await fresh.read('one'))!;
      expect(restored.draft, 'changed');
      expect(restored.sessionData, legacy.sessionData);
    },
  );
  test(
    'real IndexedDB checkpoint writes changed message, not unchanged rows or media',
    () async {
      final repo = repository();
      await repo.save(fixture.record(answer: 'A'));
      final db = await open(name);
      final userRaw =
          (await get(db, 'messages_v2', key(0)))!.dartify() as String;
      final marked = jsonDecode(userRaw) as Map<String, dynamic>;
      marked['unchangedRowMarker'] = true;
      await put(db, 'messages_v2', key(0), jsonEncode(marked).toJS);
      final media =
          (await get(db, 'attachments_v2', key('media-one')) as JSUint8Array)
              .toDart;
      await repo.save(fixture.record(answer: 'AB'));
      expect(
        (await get(db, 'messages_v2', key(0)))!.dartify(),
        jsonEncode(marked),
      );
      final answer =
          jsonDecode(
                (await get(db, 'messages_v2', key(1)))!.dartify() as String,
              )
              as Map;
      expect(answer['content'], 'AB');
      expect(
        (await get(db, 'attachments_v2', key('media-one')) as JSUint8Array)
            .toDart,
        media,
      );
      await repo.delete('one');
      expect(await get(db, 'messages_v2', key(0)), isNull);
      expect(await get(db, 'attachments_v2', key('media-one')), isNull);
      db.close();
    },
  );
  test(
    'real IDB independent writers preserve conflict copy and broadcast changes',
    () async {
      final first = repository();
      final second = repository();
      final notice = second.changes.first.timeout(const Duration(seconds: 5));
      await first.save(fixture.record(draft: 'initial'));
      expect((await notice).id, 'one');
      final stale = (await second.read('one'))!;
      await first.save(fixture.record(draft: 'winner'));
      HistoryConflictFailure? conflict;
      try {
        await second.save(stale.copyWith(draft: 'recovered'), makeActive: true);
      } on HistoryConflictFailure catch (error) {
        conflict = error;
      }
      expect(conflict, isNotNull);
      expect((await first.read('one'))!.draft, 'winner');
      expect((await second.read(conflict!.recoveryId))!.draft, 'recovered');
      await second.save(
        stale.copyWith(id: conflict.recoveryId, draft: 'continued'),
      );
      expect((await second.read(conflict.recoveryId))!.draft, 'continued');
      expect((await second.loadIndex()).entries.length, 2);
    },
  );
  test(
    'an aborted normalized checkpoint retains earlier message and legacy backup',
    () async {
      final repo = repository();
      final original = fixture.record(answer: 'old');
      await repo.save(original);
      final db = await open(name);
      // A deliberately corrupted immutable metadata entry triggers the actual
      // transaction-abort path after a changed message write has been queued.
      final doc =
          jsonDecode(
                (await get(db, 'documents_v2', 'one'.toJS))!.dartify()
                    as String,
              )
              as Map;
      (doc['attachments'] as Map)['media-one']['name'] = 'inconsistent.png';
      await put(db, 'documents_v2', 'one'.toJS, jsonEncode(doc).toJS);
      await put(db, 'records', 'one'.toJS, encodeHistoryRecord(original).toJS);
      await expectLater(
        repo.save(fixture.record(answer: 'not committed')),
        throwsA(isA<Exception>()),
      );
      final answer =
          jsonDecode(
                (await get(db, 'messages_v2', key(1)))!.dartify() as String,
              )
              as Map;
      expect(answer['content'], 'old');
      expect(
        (await get(db, 'records', 'one'.toJS))!.dartify(),
        encodeHistoryRecord(original),
      );
      db.close();
    },
  );
}
