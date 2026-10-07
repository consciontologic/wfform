import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/features/chat/attachment.dart';
import 'package:wfform/features/history/conversation.dart';
import 'package:wfform/presentation/history_browser.dart';
import 'package:wfform/shared/transport.dart';

import '../chat/fakes.dart';
import 'history_state_test.dart' show FailingRepository, HistoryHarness;

class DeleteRepository extends FailingRepository {
  final deletedIds = <String>[];
  final openedIds = <String>[];
  Completer<void>? deleteGate;
  bool failDelete = false;

  @override
  Future<void> setActive(String? id) async {
    if (id != null) openedIds.add(id);
    await super.setActive(id);
  }

  @override
  Future<void> delete(String id) async {
    deletedIds.add(id);
    await deleteGate?.future;
    if (failDelete) {
      throw historyFailure('Fixture deletion failed. Retry deleting.');
    }
    await super.delete(id);
  }
}

Future<HistoryHarness> seededHistory({
  DeleteRepository? repository,
  FutureOr<ApiResponse> Function(SentRequest)? respond,
}) async {
  final repo = repository ?? DeleteRepository();
  for (final (id, title, archived) in [
    ('first', 'Archived first', true),
    ('second', 'Archived second', true),
    ('active', 'Active conversation', false),
  ]) {
    await repo.save(
      ConversationRecord(
        id: id,
        title: title,
        archived: archived,
        modelId: testModel.id,
        modelName: testModel.name,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026, 1, id == 'second' ? 1 : 2),
        draft: archived ? 'Archived text' : 'Keep this draft',
        draftAttachments: archived
            ? const []
            : [
                ChatAttachment.fromBytes(
                  id: 'keep-file',
                  name: 'notes.txt',
                  mimeType: 'text/plain',
                  bytes: utf8.encode('Fixture attachment'),
                ),
              ],
        session: '{"version":1,"messages":[]}',
      ),
      makeActive: !archived,
    );
  }
  final h = HistoryHarness(repository: repo, respond: respond);
  await h.initialize();
  repo.openedIds.clear();
  return h;
}

void main() {
  testWidgets(
    'archived actions have independent semantic bounds and activation',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final h = await seededHistory();
        addTearDown(h.state.dispose);
        final repo = h.repo as DeleteRepository;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 290,
                  child: ConversationHistory(state: h.state),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.widgetWithText(ChoiceChip, 'Archived'));
        await tester.pumpAndSettle();
        final delete = tester.getSemantics(
          find.byTooltip('Delete Archived second'),
        );
        expect(
          delete.getSemanticsData().hasAction(SemanticsAction.tap),
          isTrue,
        );
        for (
          var ancestor = delete.parent;
          ancestor != null;
          ancestor = ancestor.parent
        ) {
          expect(
            ancestor.getSemanticsData().hasAction(SemanticsAction.tap),
            isFalse,
            reason:
                'Delete must not be nested inside another tap target: ${ancestor.getSemanticsData().label}',
          );
        }
        delete.owner!.performAction(delete.id, SemanticsAction.tap);
        await tester.pumpAndSettle();
        expect(repo.deletedIds, ['second']);
        expect(repo.openedIds, isEmpty);
        expect(h.state.activeConversationId, 'active');
        expect(h.state.draft, 'Keep this draft');
        await tester.pumpWidget(const SizedBox());
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'unselected archive and restore actions have separate semantic targets',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final h = await seededHistory();
        addTearDown(h.state.dispose);
        final repo = h.repo as DeleteRepository;
        await h.state.restoreConversation('second');
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 290,
                  child: ConversationHistory(state: h.state),
                ),
              ),
            ),
          ),
        );
        for (final label in [
          'Export Archived second',
          'Archive Archived second',
        ]) {
          final action = tester.getSemantics(find.byTooltip(label));
          for (
            var ancestor = action.parent;
            ancestor != null;
            ancestor = ancestor.parent
          ) {
            expect(
              ancestor.getSemanticsData().hasAction(SemanticsAction.tap),
              isFalse,
              reason: label,
            );
          }
        }
        final archive = tester.getSemantics(
          find.byTooltip('Archive Archived second'),
        );
        archive.owner!.performAction(archive.id, SemanticsAction.tap);
        await tester.pumpAndSettle();
        expect((await repo.read('second'))!.archived, isTrue);
        expect(h.state.activeConversationId, 'active');
        expect(repo.openedIds, isEmpty);
        await tester.tap(find.widgetWithText(ChoiceChip, 'Archived'));
        await tester.pumpAndSettle();
        final restore = tester.getSemantics(
          find.byTooltip('Restore Archived second'),
        );
        for (
          var ancestor = restore.parent;
          ancestor != null;
          ancestor = ancestor.parent
        ) {
          expect(
            ancestor.getSemanticsData().hasAction(SemanticsAction.tap),
            isFalse,
          );
        }
        restore.owner!.performAction(restore.id, SemanticsAction.tap);
        await tester.pumpAndSettle();
        expect((await repo.read('second'))!.archived, isFalse);
        expect(h.state.activeConversationId, 'active');
        expect(h.state.draft, 'Keep this draft');
        expect(repo.openedIds, isEmpty);
        await tester.pumpWidget(const SizedBox());
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('second archived row deletes in one click without opening it', (
    tester,
  ) async {
    final h = await seededHistory();
    addTearDown(h.state.dispose);
    final repo = h.repo as DeleteRepository;
    var opened = 0;
    var interacted = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConversationHistory(
            state: h.state,
            onOpened: () => opened++,
            onInteracted: () => interacted++,
          ),
        ),
      ),
    );
    await tester.tap(find.widgetWithText(ChoiceChip, 'Archived'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete Archived second'));
    await tester.pumpAndSettle();
    expect(repo.deletedIds, ['second']);
    expect(repo.openedIds, isEmpty);
    expect(opened, 0);
    expect(interacted, 2);
    expect(find.byType(AlertDialog), findsNothing);
    expect(repo.records.keys, unorderedEquals(['first', 'active']));
    expect(h.state.activeConversationId, 'active');
    expect(repo.activeId, 'active');
    expect(h.state.draft, 'Keep this draft');
    expect(h.state.draftAttachments.single.id, 'keep-file');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'pending row deletion disables repeats while draft autosave continues',
    (tester) async {
      final repo = DeleteRepository()..deleteGate = Completer<void>();
      final h = await seededHistory(repository: repo);
      addTearDown(h.state.dispose);
      var interacted = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConversationHistory(
              state: h.state,
              onInteracted: () => interacted++,
            ),
          ),
        ),
      );
      await tester.tap(find.widgetWithText(ChoiceChip, 'Archived'));
      await tester.pumpAndSettle();
      h.state.setDraft('Autosave must keep running');
      final deletion = find.byTooltip('Delete Archived second');
      await tester.tap(deletion);
      await tester.pump();
      expect(h.state.isDeletingConversation('second'), isTrue);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.descendant(of: deletion, matching: find.byType(IconButton)),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(deletion);
      await tester.pump(const Duration(milliseconds: 900));
      expect(interacted, 2);
      expect(repo.deletedIds, ['second']);
      expect((await repo.read('active'))!.draft, 'Autosave must keep running');
      expect(h.state.activeConversationId, 'active');
      repo.deleteGate!.complete();
      await tester.pumpAndSettle();
      expect(h.state.isDeletingConversation('second'), isFalse);
      expect(find.byTooltip('Delete Archived second'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'duplicate target deletion is shared without locking another draft',
    () async {
      final repo = DeleteRepository()..deleteGate = Completer<void>();
      final h = await seededHistory(repository: repo);
      addTearDown(h.state.dispose);
      final first = h.state.deleteConversation('second');
      final duplicate = h.state.deleteConversation('second');
      expect(identical(first, duplicate), isTrue);
      expect(h.state.historyBusy, isFalse);
      expect(await h.state.openConversation('second'), isFalse);
      expect(await h.state.restoreConversation('second'), isFalse);
      h.state.setDraft('Still editable during deletion');
      expect(h.state.draft, 'Still editable during deletion');
      repo.deleteGate!.complete();
      expect(await first, isTrue);
      expect(await duplicate, isTrue);
      expect(repo.deletedIds, ['second']);
      expect(h.state.activeConversationId, 'active');
      await h.state.flushHistory();
      expect(
        (await repo.read('active'))!.draft,
        'Still editable during deletion',
      );
    },
  );

  testWidgets(
    'failed row deletion retains records and permits explicit retry',
    (tester) async {
      final repo = DeleteRepository()..failDelete = true;
      final h = await seededHistory(repository: repo);
      addTearDown(h.state.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ConversationHistory(state: h.state)),
        ),
      );
      await tester.tap(find.widgetWithText(ChoiceChip, 'Archived'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete Archived second'));
      await tester.pumpAndSettle();
      expect(repo.deletedIds, ['second']);
      expect(repo.records.keys, unorderedEquals(['first', 'second', 'active']));
      expect(find.byTooltip('Delete Archived second'), findsOneWidget);
      expect(find.textContaining('Fixture deletion failed.'), findsWidgets);
      expect(h.state.activeConversationId, 'active');
      expect(h.state.draft, 'Keep this draft');
      repo.failDelete = false;
      await tester.tap(find.byTooltip('Delete Archived second'));
      await tester.pumpAndSettle();
      expect(repo.deletedIds, ['second', 'second']);
      expect(repo.records.containsKey('second'), isFalse);
      expect(h.state.historyError, isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'unrelated archived deletion preserves a failed active checkpoint',
    () async {
      final repo = DeleteRepository();
      final h = await seededHistory(repository: repo);
      addTearDown(h.state.dispose);
      repo.fail = true;
      h.state.setDraft('Uncommitted active draft');
      expect(await h.state.flushHistory(), isFalse);
      final saveError = h.state.historyError;
      expect(await h.state.deleteConversation('second'), isTrue);
      expect(repo.deletedIds, ['second']);
      expect(h.state.historyError, same(saveError));
      expect(h.state.hasUnsavedHistoryChanges, isTrue);
      expect(h.state.draft, 'Uncommitted active draft');
      expect((await repo.read('active'))!.draft, 'Keep this draft');
    },
  );

  testWidgets('nonactive archived deletion leaves an ongoing response intact', (
    tester,
  ) async {
    final source = StreamController<List<int>>();
    final h = await seededHistory(
      respond: (_) => ApiResponse(200, {
        'content-type': 'text/event-stream',
      }, source.stream),
    );
    addTearDown(h.state.dispose);
    h.state.health.recordSuccess(testModel.id);
    final pending = h.state.chat.send(testModel, 'Fixture question');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ConversationHistory(state: h.state)),
      ),
    );
    await tester.tap(find.widgetWithText(ChoiceChip, 'Archived'));
    await tester.pump();
    expect(h.state.chat.busy, isTrue);
    await tester.tap(find.byTooltip('Delete Archived second'));
    await tester.pump();
    expect((h.repo as DeleteRepository).deletedIds, ['second']);
    expect(h.state.chat.busy, isTrue);
    expect(h.state.activeConversationId, 'active');
    expect(h.state.draft, 'Keep this draft');
    expect(h.state.draftAttachments.single.id, 'keep-file');
    source.add(utf8.encode('${delta('Uninterrupted reply')}data: [DONE]\n\n'));
    await source.close();
    await pending;
    expect(h.state.chat.messages.last.content, 'Uninterrupted reply');
    await h.state.flushHistory();
    expect(h.transport.requests.where((r) => r.method == 'POST'), hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });
}
