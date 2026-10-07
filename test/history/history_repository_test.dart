import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/features/history/conversation.dart';
import 'package:wfform/features/history/history_repository.dart';
import 'package:wfform/shared/diagnostics.dart';

ConversationRecord record(String id, {bool archived = false}) =>
    ConversationRecord(
      id: id,
      title: 'Conversation $id',
      modelId: 'maker/model',
      modelName: 'Model',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      archived: archived,
      draft: 'Saved draft 🌿',
      session: '{"version":1,"messages":[]}',
    );

void main() {
  test(
    'versioned records round-trip metadata and draft without credentials',
    () async {
      final repository = MemoryHistoryRepository();
      await repository.save(record('one'), makeActive: true);
      final index = await repository.loadIndex();
      expect(index.activeId, 'one');
      expect(index.entries.single.modelId, 'maker/model');
      expect((await repository.read('one'))!.draft, 'Saved draft 🌿');
      expect(jsonDecode(repository.records['one']!)['version'], 1);
      expect(repository.records['one'], isNot(contains('apiKey')));
    },
  );

  test(
    'archive retains content; explicit deletion removes only requested record',
    () async {
      final repository = MemoryHistoryRepository();
      await repository.save(record('one'), makeActive: true);
      await repository.save(record('two'));
      await repository.save(record('one', archived: true));
      expect((await repository.read('one'))!.archived, isTrue);
      expect((await repository.read('one'))!.draft, 'Saved draft 🌿');
      await repository.delete('one');
      expect((await repository.loadIndex()).activeId, isNull);
      expect((await repository.loadIndex()).entries.single.id, 'two');
    },
  );

  test(
    '200 record limit fails without evicting active or archived histories',
    () async {
      final repository = MemoryHistoryRepository();
      for (var i = 0; i < maxHistoryRecords; i++) {
        await repository.save(record('$i', archived: i.isEven));
      }
      await expectLater(
        repository.save(record('overflow')),
        throwsA(isA<AppFailure>()),
      );
      expect(repository.records.length, maxHistoryRecords);
      expect(repository.records.containsKey('0'), isTrue);
      await repository.save(record('0').copyWith(draft: 'Updated existing'));
      expect((await repository.read('0'))!.draft, 'Updated existing');
    },
  );

  test(
    'corrupt records and future versions remain untouched with actionable errors',
    () async {
      final repository = MemoryHistoryRepository();
      await repository.save(record('good'));
      repository.records['bad'] = '{broken';
      final future = record('future').toJson()..['version'] = 9;
      repository.records['future'] = jsonEncode(future);
      final index = await repository.loadIndex();
      expect(index.entries.single.id, 'good');
      expect(index.issues.length, 2);
      await expectLater(repository.read('bad'), throwsA(isA<AppFailure>()));
      expect(repository.records['bad'], '{broken');
      expect(repository.records.length, 3);
    },
  );
}
