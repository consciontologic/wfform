import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/app/studio_state.dart';
import 'package:wfform/config/app_config.dart';
import 'package:wfform/features/history/conversation.dart';
import 'package:wfform/features/history/history_repository.dart';
import 'package:wfform/features/models/model.dart';
import 'package:wfform/shared/attachment_picker.dart';
import 'package:wfform/shared/diagnostics.dart';
import 'package:wfform/shared/platform.dart';
import 'package:wfform/shared/platform_stub.dart';
import 'package:wfform/shared/transport.dart';

import '../chat/fakes.dart';

const imageModel = FreeModel(
  id: 'fixture/vision:free',
  name: 'Vision fixture',
  inputModalities: ['text', 'image'],
);
const otherModel = FreeModel(id: 'fixture/text', name: 'Text fixture');
const pngData =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jh1sAAAAASUVORK5CYII=';

PickedAttachmentFile pickedPng([String name = 'fixture.png']) =>
    PickedAttachmentFile(
      name: name,
      mimeType: 'image/png',
      bytes: base64Decode(pngData),
    );

class RecordingPreferences extends MemoryStore {
  final writes = <String, String>{};
  @override
  void write(String key, String value) {
    writes[key] = value;
    super.write(key, value);
  }
}

class FakePicker implements AttachmentPicker {
  List<PickedAttachmentFile> files = [pickedPng()];
  Completer<List<PickedAttachmentFile>>? gate;
  int calls = 0;
  int? existingCount, existingBytes;
  Set<String>? offeredTypes;
  bool disposed = false;
  @override
  Future<List<PickedAttachmentFile>> pick({
    required Set<String> allowedMimeTypes,
    int existingCount = 0,
    int existingBytes = 0,
    CancelToken? cancel,
  }) async {
    calls++;
    offeredTypes = allowedMimeTypes;
    this.existingCount = existingCount;
    this.existingBytes = existingBytes;
    return gate == null ? files : gate!.future;
  }

  @override
  void dispose() => disposed = true;
}

class QuotaRepository extends MemoryHistoryRepository {
  bool fail = false;
  @override
  Future<void> save(ConversationRecord record, {bool makeActive = false}) {
    if (fail) return Future.error(historyFailure('Fixture quota exceeded.'));
    return super.save(record, makeActive: makeActive);
  }
}

class UpdatePlatform extends StubPlatformBridge {
  int updates = 0;
  @override
  Future<void> applyUpdate() async => updates++;
}

class AttachmentHarness {
  AttachmentHarness({
    MemoryHistoryRepository? repository,
    RecordingPreferences? preferences,
    FakePicker? picker,
  }) : repository = repository ?? MemoryHistoryRepository(),
       preferences = preferences ?? RecordingPreferences(),
       picker = picker ?? FakePicker() {
    transport = FakeTransport((request) {
      expect(request.method, 'GET', reason: 'History tests never infer.');
      return jsonResponse({
        'data': [imageModel.toJson(), otherModel.toJson()],
      });
    });
    state = StudioState(
      config: const AppConfig(),
      transport: transport,
      store: this.preferences,
      platform: platform,
      diagnostics: Diagnostics(const AppConfig()),
      historyRepository: this.repository,
      attachmentPicker: this.picker,
    );
  }
  final MemoryHistoryRepository repository;
  final RecordingPreferences preferences;
  final FakePicker picker;
  final platform = UpdatePlatform();
  late final FakeTransport transport;
  late final StudioState state;
  Future<void> initialize() async {
    await state.initialize();
    if (state.catalog.selected == null) {
      expect(await state.selectModel(imageModel), true);
    }
  }

  Future<void> pick() =>
      state.pickAttachments(imageModel.allowedAttachmentMimeTypes);
}

void main() {
  test(
    'picker refuses absent model and caller types outside selected capabilities',
    () async {
      final h = AttachmentHarness();
      addTearDown(h.state.dispose);
      await h.state.initialize();
      expect(h.state.catalog.selected, null);
      await h.pick();
      expect(h.picker.calls, 0);
      expect(h.state.attachmentError?.kind, FailureKind.configuration);
      expect(await h.state.selectModel(imageModel), true);
      await h.state.pickAttachments({'audio/wav'});
      expect(h.picker.calls, 0);
      expect(h.state.attachmentError?.kind, FailureKind.configuration);
      expect(h.state.draftAttachments, isEmpty);
    },
  );

  test(
    'safe PWA update commits sent and draft files without a localStorage payload snapshot',
    () async {
      final h = AttachmentHarness();
      addTearDown(h.state.dispose);
      await h.initialize();
      await h.pick();
      final sentFile = h.state.draftAttachments.single;
      expect(
        h.state.chat.restoreSession(
          jsonEncode({
            'version': 1,
            'messages': [
              {
                'role': 'user',
                'content': 'Describe the sent image',
                'reasoning': '',
                'modelId': imageModel.id,
                'complete': true,
                'attachments': [sentFile.toJson()],
              },
              {
                'role': 'assistant',
                'content': 'A deterministic image answer',
                'reasoning': '',
                'modelId': imageModel.id,
                'complete': true,
              },
            ],
          }),
        ),
        true,
      );
      h.state.clearDraftAttachments();
      h.state.setDraft('Keep the next draft through update');
      h.picker.files = [pickedPng('next-draft.png')];
      await h.pick();
      await h.state.applyUpdate();
      expect(h.state.updateError, null);
      expect(h.platform.updates, 1);
      final saved = (await h.repository.read(h.state.activeConversationId!))!;
      expect(saved.session, contains(pngData));
      expect(saved.draftAttachments.single.name, 'next-draft.png');
      expect(saved.draft, 'Keep the next draft through update');
      expect(h.preferences.read('freeform.updateSession.v1'), null);
      expect(
        h.preferences.writes.values.any((value) => value.contains(pngData)),
        false,
      );
      expect(
        h.preferences.writes.values.any(
          (value) => value.contains('base64Data'),
        ),
        false,
      );
    },
  );

  test(
    'picked bytes persist in history and reload without localStorage payloads',
    () async {
      final h = AttachmentHarness();
      await h.initialize();
      h.state.setDraft('Describe the fixture');
      await h.pick();
      final id = h.state.activeConversationId!;
      final attachment = h.state.draftAttachments.single;
      expect(attachment.base64Data, pngData);
      expect(attachment.name, 'fixture.png');
      final record = (await h.repository.read(id))!;
      expect(record.draftAttachments.single.toJson(), attachment.toJson());
      expect(record.draft, 'Describe the fixture');
      expect(
        h.preferences.writes.values.any((value) => value.contains(pngData)),
        false,
      );
      expect(
        h.preferences.writes.values.any(
          (value) => value.contains('base64Data'),
        ),
        false,
      );
      h.state.dispose();
      expect(h.picker.disposed, true);

      final restored = AttachmentHarness(
        repository: h.repository,
        preferences: h.preferences,
      );
      addTearDown(restored.state.dispose);
      await restored.initialize();
      expect(restored.state.activeConversationId, id);
      expect(restored.state.catalog.selectedId, imageModel.id);
      expect(
        restored.state.draftAttachments.single.toJson(),
        attachment.toJson(),
      );
      expect(restored.picker.calls, 0);
      expect(
        restored.transport.requests.every((request) => request.method == 'GET'),
        true,
      );
    },
  );

  test(
    'new chats and model switches isolate files; reopening restores and removals persist',
    () async {
      final h = AttachmentHarness();
      addTearDown(h.state.dispose);
      await h.initialize();
      await h.pick();
      final original = h.state.activeConversationId!;
      final firstFile = h.state.draftAttachments.single.id;
      expect(await h.state.newConversation(), true);
      expect(h.state.activeConversationId, isNot(original));
      expect(h.state.draftAttachments, isEmpty);
      expect(await h.state.openConversation(original), true);
      expect(h.state.draftAttachments.single.id, firstFile);
      expect(await h.state.selectModel(otherModel), true);
      expect(h.state.draftAttachments, isEmpty);
      expect(await h.state.openConversation(original), true);
      expect(h.state.draftAttachments.single.id, firstFile);

      h.picker.files = [pickedPng('second.png')];
      await h.pick();
      expect(h.picker.existingCount, 1);
      expect(h.picker.existingBytes, base64Decode(pngData).length);
      h.state.removeDraftAttachment(firstFile);
      await h.state.flushHistory();
      expect(
        (await h.repository.read(original))!.draftAttachments.single.name,
        'second.png',
      );
      h.state.clearDraftAttachments();
      await h.state.flushHistory();
      expect((await h.repository.read(original))!.draftAttachments, isEmpty);
    },
  );

  test(
    'malformed saved draft attachments refuse opening and preserve both records',
    () async {
      final h = AttachmentHarness();
      addTearDown(h.state.dispose);
      await h.initialize();
      await h.pick();
      final damagedId = h.state.activeConversationId!;
      await h.state.newConversation();
      final active = h.state.activeConversationId!;
      h.state.setDraft('Keep the current draft');
      await h.state.flushHistory();
      final json =
          jsonDecode(h.repository.records[damagedId]!) as Map<String, dynamic>;
      ((json['draftAttachments'] as List).single as Map)['base64Data'] =
          'not-base64';
      final damaged = jsonEncode(json);
      h.repository.records[damagedId] = damaged;
      expect(await h.state.openConversation(damagedId), false);
      expect(h.state.historyError?.kind, FailureKind.storage);
      expect(h.state.activeConversationId, active);
      expect(h.state.draft, 'Keep the current draft');
      expect(h.repository.records[damagedId], damaged);
      expect(
        (await h.repository.read(active))!.draft,
        'Keep the current draft',
      );
    },
  );

  test(
    'quota failures retain unsaved file drafts and block navigation until saved',
    () async {
      final repository = QuotaRepository();
      final h = AttachmentHarness(repository: repository);
      addTearDown(h.state.dispose);
      await h.initialize();
      await h.pick();
      final id = h.state.activeConversationId!;
      final durable = repository.records[id];
      h.state.setDraft('Keep draft after quota failure');
      h.picker.files = [pickedPng('unsaved.png')];
      repository.fail = true;
      await h.pick();
      expect(h.state.draftAttachments, hasLength(2));
      expect(h.state.historyError?.kind, FailureKind.storage);
      expect(repository.records[id], durable);
      expect(await h.state.newConversation(), false);
      expect(await h.state.selectModel(otherModel), false);
      expect(h.state.activeConversationId, id);
      expect(h.state.draft, 'Keep draft after quota failure');
      repository.fail = false;
      expect(await h.state.flushHistory(), true);
      expect(h.state.historyError, null);
      expect((await repository.read(id))!.draftAttachments, hasLength(2));
    },
  );

  test(
    'invalid picker results add no partial files and preserve existing content',
    () async {
      final h = AttachmentHarness();
      addTearDown(h.state.dispose);
      await h.initialize();
      await h.pick();
      final original = h.state.draftAttachments.single;
      final stored = h.repository.records[h.state.activeConversationId];
      h.picker.files = [
        pickedPng('valid.png'),
        PickedAttachmentFile(
          name: 'fake.png',
          mimeType: 'image/png',
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
      ];
      await h.pick();
      expect(h.state.attachmentError?.kind, FailureKind.configuration);
      expect(h.state.draftAttachments.single.id, original.id);
      expect(h.repository.records[h.state.activeConversationId], stored);
    },
  );

  test(
    'a pending picker blocks navigation; cancellation keeps existing files',
    () async {
      final h = AttachmentHarness();
      addTearDown(h.state.dispose);
      await h.initialize();
      await h.pick();
      final id = h.state.activeConversationId;
      final original = h.state.draftAttachments.single.id;
      h.picker.gate = Completer<List<PickedAttachmentFile>>();
      final pending = h.pick();
      expect(h.state.attachmentPicking, true);
      expect(await h.state.newConversation(), false);
      expect(await h.state.selectModel(otherModel), false);
      expect(h.state.conversationNotice, contains('adding files'));
      h.state.cancelAttachmentPick();
      h.picker.gate!.complete([pickedPng('cancelled.png')]);
      await pending;
      expect(h.state.attachmentPicking, false);
      expect(h.state.attachmentError, null);
      expect(h.state.activeConversationId, id);
      expect(h.state.draftAttachments.single.id, original);
    },
  );

  test(
    'older saved conversations without draftAttachments remain readable',
    () async {
      final h = AttachmentHarness();
      addTearDown(h.state.dispose);
      await h.initialize();
      final id = h.state.activeConversationId!;
      final json =
          jsonDecode(h.repository.records[id]!) as Map<String, dynamic>;
      json.remove('draftAttachments');
      final legacy = ConversationRecord.fromJson(json);
      expect(legacy.draftAttachments, isEmpty);
      expect(legacy.id, id);
    },
  );
}
