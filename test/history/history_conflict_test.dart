import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/features/history/conversation.dart';
import 'package:wfform/features/history/history_repository.dart';
import 'package:wfform/shared/diagnostics.dart';

ConversationRecord record(String id, String draft) => ConversationRecord(
  id: id,
  title: 'Conversation',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  draft: draft,
  session: '{"version":1,"messages":[]}',
);
void main() {
  test(
    'two tabs preserve both versions, recover conflict and continue recovered copy',
    () async {
      final database = MemoryHistoryDatabase();
      final first = MemoryHistoryRepository(database: database);
      final second = MemoryHistoryRepository(database: database);
      await first.save(record('one', 'initial'), makeActive: true);
      final firstCopy = (await first.read('one'))!;
      final secondCopy = (await second.read('one'))!;
      await first.save(firstCopy.copyWith(draft: 'first tab'));
      HistoryConflictFailure? conflict;
      try {
        await second.save(
          secondCopy.copyWith(draft: 'second tab'),
          makeActive: true,
        );
      } on HistoryConflictFailure catch (error) {
        conflict = error;
      }
      expect(conflict, isNotNull);
      expect(conflict!.originalId, 'one');
      expect((await first.read('one'))!.draft, 'first tab');
      expect((await second.read(conflict.recoveryId))!.draft, 'second tab');
      expect(second.activeId, conflict.recoveryId);
      expect(first.activeId, 'one');
      await second.save(
        secondCopy.copyWith(id: conflict.recoveryId, draft: 'continued'),
      );
      expect((await second.read(conflict.recoveryId))!.draft, 'continued');
      expect(database.records.length, 2);
    },
  );
  test(
    'external deletion does not silently recreate or overwrite original identity',
    () async {
      final database = MemoryHistoryDatabase();
      final first = MemoryHistoryRepository(database: database);
      final second = MemoryHistoryRepository(database: database);
      await first.save(record('one', 'initial'));
      final stale = (await second.read('one'))!;
      await first.delete('one');
      await expectLater(
        second.save(stale.copyWith(draft: 'unsaved')),
        throwsA(isA<HistoryConflictFailure>()),
      );
      expect(database.records.containsKey('one'), isFalse);
      expect(database.records.length, 1);
      expect(
        (await second.loadIndex()).entries.single.title,
        startsWith('Recovered copy'),
      );
    },
  );
  test(
    'stale deletion is refused and other tab changes are broadcast only externally',
    () async {
      final database = MemoryHistoryDatabase();
      final first = MemoryHistoryRepository(database: database);
      final second = MemoryHistoryRepository(database: database);
      final own = <HistoryChange>[];
      final external = <HistoryChange>[];
      final a = first.changes.listen(own.add);
      final b = second.changes.listen(external.add);
      await first.save(record('one', 'initial'));
      await second.read('one');
      await first.save(record('one', 'new'));
      await expectLater(second.delete('one'), throwsA(isA<AppFailure>()));
      expect(own, isEmpty);
      expect(external.map((event) => event.revision), [1, 2]);
      expect((await first.read('one'))!.draft, 'new');
      await a.cancel();
      await b.cancel();
    },
  );
  test(
    'index refresh does not advance revision and hide an active conflict',
    () async {
      final database = MemoryHistoryDatabase();
      final first = MemoryHistoryRepository(database: database);
      final second = MemoryHistoryRepository(database: database);
      await first.save(record('one', 'initial'));
      final stale = (await second.read('one'))!;
      await first.save(record('one', 'other tab'));
      await second.loadIndex();
      await expectLater(
        second.save(stale),
        throwsA(isA<HistoryConflictFailure>()),
      );
      expect((await first.read('one'))!.draft, 'other tab');
    },
  );
  test(
    'capacity failure keeps original, does not claim recovery was saved',
    () async {
      final database = MemoryHistoryDatabase();
      final first = MemoryHistoryRepository(database: database);
      final second = MemoryHistoryRepository(database: database);
      await first.save(record('one', 'initial'));
      final stale = (await second.read('one'))!;
      await first.save(record('one', 'new'));
      for (var i = 1; i < maxHistoryRecords; i++) {
        await first.save(record('fill-$i', ''));
      }
      await expectLater(
        second.save(stale),
        throwsA(
          isA<AppFailure>().having(
            (failure) => failure is HistoryConflictFailure,
            'saved recovery',
            false,
          ),
        ),
      );
      expect(database.records.length, maxHistoryRecords);
      expect((await first.read('one'))!.draft, 'new');
    },
  );
}
