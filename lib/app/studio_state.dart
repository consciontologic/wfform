import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import '../config/app_config.dart';
import '../features/chat/chat_controller.dart';
import '../features/chat/attachment.dart';
import '../features/models/catalog.dart';
import '../features/models/health.dart';
import '../features/models/model.dart';
import '../features/history/conversation.dart';
import '../features/history/history_repository.dart';
import '../shared/diagnostics.dart';
import '../shared/platform.dart';
import '../shared/transport.dart';
import '../shared/attachment_picker.dart';

class StudioState extends ChangeNotifier {
  StudioState({
    required this.config,
    required this.transport,
    required LocalStore store,
    LocalStore? recoveryStore,
    required this.platform,
    required this.diagnostics,
    HistoryRepository? historyRepository,
    AttachmentPicker? attachmentPicker,
  }) {
    this.historyRepository = historyRepository ?? createHistoryRepository();
    this.attachmentPicker = attachmentPicker ?? createAttachmentPicker();
    this.store = GuardedStore(store, diagnostics);
    this.recoveryStore = recoveryStore == null
        ? this.store
        : GuardedStore(recoveryStore, diagnostics);
    _createControllers();
    workOffline = this.store.read('freeform.workOffline') == 'true';
    draft = this.store.read('freeform.draft.v1') ?? '';
    try {
      final pending = this.recoveryStore.read('freeform.pendingDraft.v1');
      if (pending != null) {
        final decoded = jsonDecode(pending);
        if (decoded is Map &&
            decoded['id'] == null &&
            decoded['draft'] is String) {
          draft = decoded['draft'] as String;
        }
      }
    } catch (_) {
      diagnostics.record(
        'draft.recovery',
        failure: const AppFailure(
          FailureKind.storage,
          'The tab recovery draft could not be read. Saved conversations are retained.',
        ),
      );
    }
    final savedTheme = this.store.read('freeform.themeMode');
    themeMode =
        ThemeMode.values.where((mode) => mode.name == savedTheme).firstOrNull ??
        ThemeMode.system;
    textScale =
        double.tryParse(
          this.store.read('freeform.textScale') ?? '',
        )?.clamp(1, 2) ??
        1;
    final session = this.store.read('freeform.updateSession.v1');
    _legacyUpdateSession = session;
    if (session != null) {
      try {
        chat.restoreSession(session);
      } catch (error) {
        diagnostics.record(
          'restore conversation',
          failure: AppFailure.from(error),
        );
      }
      // Removed only after successful migration into durable history.
    }
    _wasOnline = platform.online;
    platform.addListener(_platformChanged);
    _historySubscription = this.historyRepository.changes.listen(
      _externalHistoryChanged,
    );
  }
  AppConfig config;
  final ApiTransport transport;
  late final GuardedStore store;
  late final GuardedStore recoveryStore;
  late final HistoryRepository historyRepository;
  late final AttachmentPicker attachmentPicker;
  final PlatformBridge platform;
  final Diagnostics diagnostics;
  late CatalogController catalog;
  late HealthController health;
  late ChatController chat;
  String draft = '';
  List<ChatAttachment> _draftAttachments = const [];
  List<ChatAttachment> get draftAttachments => _draftAttachments;
  AppFailure? attachmentError;
  bool attachmentPicking = false;
  CancelToken? _attachmentCancel;
  double textScale = 1;
  bool _wasOnline = true;
  String? _lastPwaError;
  bool _disposed = false;
  bool _keyOverride = false;
  Future<void>? _reconnect;
  String? updateError;
  String? _observedSelection;
  bool workOffline = false;
  bool get online => platform.online && !workOffline;
  ThemeMode themeMode = ThemeMode.system;
  final appearance = ValueNotifier<int>(0);
  final historyIndexChanges = ValueNotifier<int>(0);
  final historyStatus = ValueNotifier<String>('Opening history…');
  bool configurationLoading = false;
  final List<ConversationSummary> _history = [];
  List<ConversationSummary> get history => List.unmodifiable(_history);
  bool historyLoading = true;
  bool historySaving = false;
  AppFailure? historyError;
  String? conversationNotice;
  ConversationRecord? _activeRecord;
  String? get activeConversationId => _activeRecord?.id;
  bool get activeConversationArchived => _activeRecord?.archived ?? false;
  bool _historySwitching = false;
  String? _legacyUpdateSession;
  bool get historyBusy => historyLoading || _historySwitching;
  bool _suppressHistory = false;
  bool _previousChatBusy = false;
  int _revision = 0, _savedRevision = 0;
  bool get hasUnsavedHistoryChanges => _savedRevision != _revision;
  Timer? _historyTimer;
  Future<bool>? _saving;
  StreamSubscription<HistoryChange>? _historySubscription;
  Future<void>? _indexRefresh;
  bool _indexRefreshRequested = false;
  static const _emptySession =
      '{"version":1,"messages":[],"retryUserIndex":null,"retryModelId":null}';
  void _createControllers() {
    catalog = CatalogController(
      config: config,
      transport: transport,
      store: store,
      diagnostics: diagnostics,
    );
    health = HealthController(
      config: config,
      transport: transport,
      diagnostics: diagnostics,
      store: store,
    );
    chat = ChatController(
      config: config,
      transport: transport,
      diagnostics: diagnostics,
      health: health,
      validateModel: (model) {
        if (configurationLoading) {
          return 'Connection settings are still loading. Your draft is saved.';
        }
        if (historyBusy) return 'Wait for the conversation to finish opening.';
        if (activeConversationArchived) {
          return 'Restore this archived conversation before continuing.';
        }
        if (_activeRecord?.modelId != null &&
            _activeRecord!.modelId != model.id) {
          return 'Choose this model through the model selector to start a separate conversation.';
        }
        if (catalog.selected?.id != model.id) {
          return 'Select a currently available free model before sending.';
        }
        if (catalog.selected!.signature != model.signature) {
          return 'This model’s capabilities or pricing changed. Review its current details and send again.';
        }
        return null;
      },
    );
    catalog.addListener(_catalogChanged);
    chat.addListener(_chatChanged);
  }

  void _catalogChanged() {
    if (_disposed) return;
    // A provisional startup controller has not loaded the runtime key yet.
    // It must not replace another configuration's durable health snapshot.
    if (!configurationLoading && config.apiKey.trim().isNotEmpty) {
      health.reconcileModels(catalog.models);
    }
    if (_observedSelection != catalog.selectedId) {
      final before = _observedSelection;
      _observedSelection = catalog.selectedId;
      health.cancelChecks(exceptModelId: chat.activeModelId);
      if (!_suppressHistory &&
          !historyLoading &&
          !_historySwitching &&
          catalog.selected != null) {
        final model = catalog.selected!;
        if (chat.busy && model.id != chat.activeModelId) {
          _suppressHistory = true;
          final original = chat.activeModelId ?? before;
          if (original != null) catalog.select(original);
          _suppressHistory = false;
          conversationNotice =
              'Finish or cancel the current response before switching models.';
          notifyListeners();
        } else if (_activeRecord?.modelId == null && !chat.busy) {
          _activeRecord = (_activeRecord ?? _blankRecord(model)).copyWith(
            modelId: model.id,
            modelName: model.name,
          );
          _markHistoryDirty();
        } else if (_activeRecord == null ||
            _activeRecord!.modelId != model.id) {
          unawaited(selectModel(model));
        }
      }
    }
    // A refresh can invalidate the model after a send's asynchronous preflight
    // began. Abort that attempt rather than submitting to an invalid selection.
    if (chat.busy && catalog.selected == null) {
      chat.cancel();
      health.cancelChecks();
    }
    if (_activeRecord?.modelId != null &&
        catalog.selected == null &&
        !historyLoading) {
      conversationNotice =
          '${_activeRecord!.modelName ?? _activeRecord!.modelId} is unavailable in the current free-model catalog. This history is preserved. Choose a model to start a new conversation.';
      notifyListeners();
    }
  }

  Future<void> initialize({
    Future<AppConfig?> Function()? loadConfiguration,
  }) async {
    final watch = Stopwatch()..start();
    configurationLoading = loadConfiguration != null;
    // Configuration, remote discovery, PWA registration and local data each
    // have their own readiness. None prevents reading/editing local history.
    unawaited(
      platform.initialize().catchError((Object error) {
        if (!_disposed) {
          diagnostics.record('PWA initialize', failure: AppFailure.from(error));
        }
      }),
    );
    final configuration = loadConfiguration == null
        ? null
        : _loadRuntimeConfiguration(loadConfiguration);
    final catalogWork = catalog.initialize(
      refresh: online && configuration == null,
    );
    await _loadHistory();
    if (_disposed) return;
    historyLoading = false;
    historyStatus.value = historyError != null
        ? 'Save failed'
        : _savedRevision == _revision
        ? 'Saved'
        : 'Unsaved changes';
    _bindOriginalModel();
    if (_activeRecord == null &&
        (draft.isNotEmpty || chat.messages.isNotEmpty)) {
      _revision++;
      await flushHistory();
    } else if (_activeRecord == null && historyError == null) {
      _activeRecord = _blankRecord(catalog.selected);
      _revision++;
      await flushHistory();
    } else if (_activeRecord != null && _savedRevision != _revision) {
      // A newer tab-local draft recovered during startup is not durable until
      // this checkpoint. Do not show Saved while only sessionStorage has it.
      await flushHistory();
    }
    notifyListeners();
    diagnostics.record(
      'startup.localReady',
      duration: watch.elapsed,
      note:
          'Local initialization finished with history status: ${historyStatus.value}; remote initialization is independent.',
    );
    if (configuration != null) {
      final next = await configuration;
      if (_disposed) return;
      if (next != null && !_keyOverride) {
        await _replaceConfig(next);
      } else if (online) {
        await catalog.refresh();
      }
      configurationLoading = false;
      if (!_disposed) {
        if (config.apiKey.trim().isNotEmpty) {
          health.reconcileModels(catalog.models);
        }
        notifyListeners();
      }
    } else {
      await catalogWork;
    }
    if (!_disposed) _bindOriginalModel();
  }

  Future<AppConfig?> _loadRuntimeConfiguration(
    Future<AppConfig?> Function() load,
  ) async {
    try {
      return await load();
    } catch (error) {
      if (!_disposed) {
        diagnostics.record('configuration', failure: AppFailure.from(error));
      }
      return null;
    }
  }

  void setDraft(String value) {
    if (activeConversationArchived || _historySwitching || value == draft) {
      return;
    }
    draft = value;
    _persistDraft();
    _markHistoryDirty();
  }

  void _persistDraft() {
    recoveryStore.write(
      'freeform.pendingDraft.v1',
      jsonEncode({
        'id': activeConversationId,
        'draft': draft,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  }

  void setThemeMode(ThemeMode value) {
    themeMode = value;
    store.write('freeform.themeMode', value.name);
    appearance.value++;
    notifyListeners();
  }

  void clearDraftAttachments() {
    _draftAttachments = const [];
    attachmentError = null;
    _markHistoryDirty();
    if (!_disposed) notifyListeners();
  }

  void removeDraftAttachment(String id) {
    if (historyBusy || activeConversationArchived || attachmentPicking) return;
    _draftAttachments = List.unmodifiable(
      _draftAttachments.where((file) => file.id != id),
    );
    attachmentError = null;
    _markHistoryDirty();
    notifyListeners();
  }

  Future<void> pickAttachments(Set<String> allowedMimeTypes) async {
    if (attachmentPicking ||
        historyBusy ||
        activeConversationArchived ||
        chat.busy ||
        allowedMimeTypes.isEmpty) {
      return;
    }
    final model = catalog.selected;
    if (model == null ||
        !model.allowedAttachmentMimeTypes.containsAll(allowedMimeTypes)) {
      attachmentError = const AppFailure(
        FailureKind.configuration,
        'Choose a compatible model before adding files.',
      );
      notifyListeners();
      return;
    }
    attachmentPicking = true;
    attachmentError = null;
    final conversation = activeConversationId;
    final token = CancelToken();
    _attachmentCancel = token;
    notifyListeners();
    final watch = Stopwatch()..start();
    try {
      final files = await attachmentPicker.pick(
        allowedMimeTypes: allowedMimeTypes,
        existingCount: _draftAttachments.length,
        existingBytes: _draftAttachments.fold(
          0,
          (sum, file) => sum + file.byteLength,
        ),
        cancel: token,
      );
      token.throwIfCancelled();
      if (_disposed || conversation != activeConversationId) return;
      if (catalog.selected?.id != model.id) {
        throw const AppFailure(
          FailureKind.configuration,
          'The selected model changed or became unavailable while reading files. Choose a model and add them again.',
        );
      }
      final added = files
          .map(
            (file) => ChatAttachment.fromBytes(
              name: file.name,
              mimeType: file.mimeType,
              bytes: file.bytes,
            ),
          )
          .toList();
      if (added.isNotEmpty) {
        final combined = List<ChatAttachment>.unmodifiable([
          ..._draftAttachments,
          ...added,
        ]);
        validateAttachments(combined, model: catalog.selected);
        // Refuse additions before changing the draft if they cannot fit a record.
        encodeHistoryRecord(
          _snapshotRecord().copyWith(draftAttachments: combined),
        );
        _draftAttachments = combined;
        _markHistoryDirty();
        await flushHistory();
      }
    } catch (error) {
      if (!_disposed && conversation == activeConversationId) {
        final failure = error is AppFailure
            ? error
            : AppFailure(
                FailureKind.storage,
                'The selected files could not be prepared. Try selecting them again; inspect diagnostics if this continues.',
                retryable: true,
                details:
                    'Local attachment preparation error type: ${error.runtimeType}. File names and contents omitted.',
              );
        if (failure.kind != FailureKind.cancelled) {
          attachmentError = failure;
          diagnostics.record(
            'attachment.pick',
            failure: failure,
            duration: watch.elapsed,
          );
        }
      }
    } finally {
      _attachmentCancel = null;
      attachmentPicking = false;
      if (!_disposed) notifyListeners();
    }
  }

  void cancelAttachmentPick() => _attachmentCancel?.cancel();

  Future<void> _loadHistory() async {
    final legacySession = _legacyUpdateSession;
    final legacyDraft = draft;
    try {
      final index = await historyRepository.loadIndex();
      if (_disposed) return;
      _history
        ..clear()
        ..addAll(index.entries);
      if (index.issues.isNotEmpty) {
        _historyFailure(historyFailure(index.issues.join('\n')));
      }
      if (index.activeId != null) {
        final loaded = await historyRepository.read(index.activeId!);
        if (loaded == null) {
          final pendingText = recoveryStore.read('freeform.pendingDraft.v1');
          if (pendingText != null) {
            final pending = jsonDecode(pendingText);
            if (pending is Map &&
                pending['id'] == index.activeId &&
                pending['draft'] is String &&
                (pending['draft'] as String).trim().isNotEmpty) {
              final blank = _blankRecord(null);
              final recovered = blank.copyWith(
                id: '${blank.id}-recovered-draft',
                draft: pending['draft'] as String,
                title: 'Recovered draft',
              );
              await historyRepository.save(recovered, makeActive: true);
              _upsertHistory(recovered.summary);
              _activateRecord(recovered);
              conversationNotice =
                  'The previous conversation was deleted in another tab. Your unsent text was recovered as a separate draft.';
              return;
            }
          }
          throw historyFailure(
            'The last-opened conversation was not found. Other history entries remain available.',
          );
        }
        ConversationRecord record = loaded;
        var recoveredDraftChanged = false;
        final pending =
            recoveryStore.read('freeform.pendingDraft.v1') ??
            store.read('freeform.pendingDraft.v1');
        if (pending != null) {
          try {
            final value = jsonDecode(pending);
            if (value is Map &&
                !record.archived &&
                value['id'] == record.id &&
                value['draft'] is String &&
                value['updatedAt'] is String) {
              final changed = DateTime.tryParse(value['updatedAt'] as String);
              if (changed != null && !changed.isBefore(record.updatedAt)) {
                recoveredDraftChanged = value['draft'] != record.draft;
                record = record.copyWith(draft: value['draft'] as String);
              }
            }
          } catch (_) {
            _historyFailure(
              historyFailure(
                'The recovery draft could not be parsed. The valid saved conversation was retained; recovery content was omitted from diagnostics.',
              ),
            );
          }
        }
        if (legacySession != null &&
            (!_sameLegacySession(legacySession, record.sessionData) ||
                legacyDraft != record.draft)) {
          // Untimestamped legacy update snapshots cannot safely replace an
          // existing record. Keep both and open the recovered update snapshot.
          final recovered = _snapshotRecord().copyWith(
            draft: legacyDraft,
            session: legacySession,
          );
          await historyRepository.save(recovered, makeActive: true);
          _upsertHistory(recovered.summary);
          store.remove('freeform.updateSession.v1');
          _legacyUpdateSession = null;
          if (!_activateRecord(recovered)) {
            throw historyFailure(
              'The update snapshot could not be restored; both stored histories were retained.',
            );
          }
          return;
        }
        if (!_activateRecord(record, needsCheckpoint: recoveredDraftChanged)) {
          throw historyFailure(
            'The saved conversation exceeds current session limits or has an unsupported format. Its stored data was retained.',
          );
        }
        if (legacySession != null) {
          store.remove('freeform.updateSession.v1');
          _legacyUpdateSession = null;
        }
      }
    } catch (error) {
      if (!_disposed) {
        _historyFailure(
          error,
          guidance: _activeRecord == null
              ? 'Open a saved conversation from history to retry loading. If the list is unavailable, reload the app. Stored content was retained.'
              : null,
        );
      }
    }
  }

  void _chatChanged() {
    if (_disposed || _suppressHistory) return;
    final started = !_previousChatBusy && chat.busy;
    final completed = _previousChatBusy && !chat.busy;
    _previousChatBusy = chat.busy;
    _markHistoryDirty();
    // Commit accepted turns immediately; only incremental output is throttled.
    if (started || completed) unawaited(flushHistory());
  }

  void _markHistoryDirty() {
    if (_disposed ||
        _suppressHistory ||
        historyLoading ||
        activeConversationArchived) {
      return;
    }
    _revision++;
    if (!historySaving) historyStatus.value = 'Unsaved changes';
    _historyTimer ??= Timer(const Duration(milliseconds: 800), () {
      _historyTimer = null;
      unawaited(flushHistory());
    });
  }

  ConversationRecord _blankRecord(FreeModel? model) {
    final now = DateTime.now().toUtc();
    final suffix = Random.secure().nextInt(0x7fffffff).toRadixString(36);
    return ConversationRecord(
      id: '${now.microsecondsSinceEpoch}-$suffix',
      title: 'New conversation',
      modelId: model?.id,
      modelName: model?.name,
      createdAt: now,
      updatedAt: now,
      draft: '',
      session: _emptySession,
    );
  }

  ConversationRecord _snapshotRecord() {
    var record = _activeRecord ?? _blankRecord(catalog.selected);
    final firstUser = chat.messages
        .where((message) => message.role == 'user')
        .firstOrNull;
    final firstText = (firstUser?.content ?? draft).trim().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    var title = firstText.isEmpty
        ? record.title
        : firstText.length > 80
        ? '${firstText.substring(0, 80)}…'
        : firstText;
    if (record.id.contains('-recovered-') &&
        !title.startsWith('Recovered copy · ')) {
      title = 'Recovered copy · $title';
    }
    final messageModel = chat.messages
        .map((message) => message.modelId)
        .whereType<String>()
        .firstOrNull;
    final modelId = record.modelId ?? messageModel ?? catalog.selected?.id;
    final modelName = catalog.models
        .where((model) => model.id == modelId)
        .firstOrNull
        ?.name;
    record = record.copyWith(
      title: title,
      modelId: modelId,
      modelName: modelName,
      draft: draft,
      sessionData: chat.exportSessionData(),
      draftAttachments: _draftAttachments,
      messageCount: chat.messages.length,
      updatedAt: DateTime.now().toUtc(),
    );
    _activeRecord = record;
    return record;
  }

  Future<bool> flushHistory() {
    _historyTimer?.cancel();
    _historyTimer = null;
    if (_disposed || historyLoading) return Future.value(false);
    if (activeConversationArchived) return Future.value(true);
    return _saving ??= _flushHistoryOnce().whenComplete(() {
      _saving = null;
      if (!_disposed && historyError == null && _savedRevision != _revision) {
        _historyTimer ??= Timer(const Duration(milliseconds: 800), () {
          _historyTimer = null;
          unawaited(flushHistory());
        });
      }
    });
  }

  Future<bool> _flushHistoryOnce() async {
    historySaving = true;
    historyStatus.value = 'Saving…';
    var attemptedRevision = _savedRevision;
    try {
      while (_savedRevision != _revision) {
        final revision = _revision;
        attemptedRevision = revision;
        final snapshot = _snapshotRecord();
        await historyRepository.save(snapshot, makeActive: true);
        if (_disposed) return true;
        _savedRevision = revision;
        _upsertHistory(snapshot.summary);
        historyError = null;
        // Only a successful durable commit retires the update migration source.
        store.remove('freeform.updateSession.v1');
      }
      return true;
    } catch (error) {
      if (!_disposed && error is HistoryConflictFailure) {
        // Adopt the already committed recovery identity before any further
        // checkpoint. A stream can then finish without overwriting either tab.
        _activeRecord = _snapshotRecord().copyWith(
          id: error.recoveryId,
          title: 'Recovered copy · ${_activeRecord?.title ?? 'Conversation'}',
        );
        _savedRevision = attemptedRevision;
        await historyRepository.setActive(error.recoveryId);
        _persistDraft();
        conversationNotice = error.message;
        historyError = null;
        _markHistoryDirty();
        await _refreshHistoryIndex();
        if (!_disposed) notifyListeners();
        return false;
      }
      if (!_disposed) _historyFailure(error);
      return false;
    } finally {
      historySaving = false;
      if (!_disposed) {
        historyStatus.value = historyError != null
            ? 'Save failed'
            : _savedRevision != _revision
            ? 'Unsaved changes'
            : 'Saved';
      }
    }
  }

  void _externalHistoryChanged(HistoryChange change) {
    if (_disposed) return;
    if (change.id == activeConversationId) {
      conversationNotice = change.deleted
          ? 'Another tab deleted this conversation. Your open copy is retained and will be saved separately if you continue.'
          : 'Another tab changed this conversation. Your open work is retained; conflicting changes will be saved as a recovered copy.';
      notifyListeners();
    }
    unawaited(_refreshHistoryIndex());
  }

  Future<void> _refreshHistoryIndex() {
    _indexRefreshRequested = true;
    return _indexRefresh ??= _refreshHistoryIndexOnce().whenComplete(
      () => _indexRefresh = null,
    );
  }

  Future<void> _refreshHistoryIndexOnce() async {
    try {
      do {
        _indexRefreshRequested = false;
        final index = await historyRepository.loadIndex();
        if (_disposed) return;
        _history
          ..clear()
          ..addAll(index.entries);
        historyIndexChanges.value++;
      } while (_indexRefreshRequested);
    } catch (error) {
      if (!_disposed) _historyFailure(error);
    }
  }

  Future<void> exportConversation(String id) async {
    try {
      final exportOpenCopy = id == activeConversationId;
      if (exportOpenCopy) await flushHistory();
      // Export is also the escape hatch when the browser cannot commit data.
      final record = exportOpenCopy
          ? _snapshotRecord()
          : await historyRepository.read(id);
      if (record == null) {
        throw historyFailure('This conversation is no longer available.');
      }
      platform.exportText(
        'wfform-conversation.json',
        jsonEncode({
          'application': 'wfform',
          'version': 1,
          'conversation': record.toJson(),
        }),
      );
    } catch (error) {
      if (!_disposed) _historyFailure(error);
    }
  }

  Future<bool> importConversation() async {
    if (!_beginHistoryNavigation()) return false;
    try {
      final text = await platform.importText(
        maxBytes: maxHistoryRecordBytes * 2,
      );
      if (text == null || _disposed) return false;
      final value = jsonDecode(text);
      if (value is! Map ||
          value['application'] != 'wfform' ||
          value['version'] != 1) {
        throw historyFailure(
          'Choose a wfform conversation export (version 1).',
        );
      }
      final imported = ConversationRecord.fromJson(value['conversation']);
      encodeHistoryRecord(imported);
      final checker = ChatController(
        config: config,
        transport: transport,
        diagnostics: diagnostics,
        health: health,
      );
      final valid = checker.restoreSession(imported.session);
      checker.dispose();
      if (!valid) {
        throw historyFailure(
          'This export exceeds current conversation limits or contains unsupported messages.',
        );
      }
      if (!await flushHistory()) return false;
      final record = imported.copyWith(
        id: _blankRecord(null).id,
        archived: false,
        updatedAt: DateTime.now().toUtc(),
      );
      await historyRepository.save(record, makeActive: true);
      _activateRecord(record);
      _upsertHistory(record.summary);
      conversationNotice =
          'Imported a separate copy. The original conversation was not replaced.';
      return true;
    } catch (error) {
      if (!_disposed) _historyFailure(error);
      return false;
    } finally {
      _historySwitching = false;
      if (!_disposed) notifyListeners();
    }
  }

  void _upsertHistory(ConversationSummary entry) {
    _history.removeWhere((record) => record.id == entry.id);
    _history.add(entry);
    _history.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    historyIndexChanges.value++;
  }

  void _historyFailure(Object error, {String? guidance}) {
    if (error is HistoryConflictFailure) {
      conversationNotice = error.message;
      unawaited(_refreshHistoryIndex());
    }
    historyStatus.value = 'Save failed';
    final failure = error is AppFailure
        ? error
        : historyFailure(
            'Conversation storage failed. Current content remains in memory. Retry saving before leaving this chat.',
            details:
                'Error type: ${error.runtimeType}; conversation content omitted.',
          );
    diagnostics.record('history.storage', failure: failure);
    historyError = guidance == null
        ? failure
        : historyFailure(guidance, details: failure.details ?? failure.message);
    if (!_disposed) notifyListeners();
  }

  bool _activateRecord(
    ConversationRecord record, {
    bool needsCheckpoint = false,
  }) {
    _suppressHistory = true;
    try {
      if (!chat.restoreSession(record.session)) return false;
      _activeRecord = record;
      draft = record.draft;
      _draftAttachments = List.unmodifiable(record.draftAttachments);
      attachmentError = null;
      _persistDraft();
      _savedRevision = 0;
      _revision = needsCheckpoint ? 1 : 0;
      historyStatus.value = needsCheckpoint ? 'Unsaved changes' : 'Saved';
      _previousChatBusy = false;
      conversationNotice = record.archived
          ? 'Archived conversation. Restore it to continue.'
          : null;
      _bindOriginalModel();
      return true;
    } finally {
      _suppressHistory = false;
    }
  }

  void _bindOriginalModel() {
    if (historyLoading) return;
    final id = _activeRecord?.modelId;
    if (id == null) {
      if (_activeRecord != null && catalog.selectedId != null) {
        final previous = _suppressHistory;
        _suppressHistory = true;
        catalog.clearSelection(
          notice: 'Choose a free model for this conversation.',
        );
        _suppressHistory = previous;
      }
      return;
    }
    final original = catalog.models
        .where((model) => model.id == id && model.chatCompatible)
        .firstOrNull;
    final previous = _suppressHistory;
    _suppressHistory = true;
    if (original == null) {
      conversationNotice =
          'The original model ($id) is unavailable in the current free-model catalog. This history is preserved. Choose a model to start a new conversation.';
      catalog.clearSelection(notice: conversationNotice);
    } else {
      catalog.select(id);
    }
    _suppressHistory = previous;
  }

  bool _beginHistoryNavigation() {
    if (chat.busy || historyBusy || attachmentPicking) {
      conversationNotice = chat.busy
          ? 'Finish or cancel the current response before changing conversations or models.'
          : attachmentPicking
          ? 'Finish or cancel adding files before changing conversations or models.'
          : 'Wait for the current conversation operation to finish.';
      notifyListeners();
      return false;
    }
    _historySwitching = true;
    notifyListeners();
    return true;
  }

  Future<bool> selectModel(FreeModel model) async {
    if (!_beginHistoryNavigation()) return false;
    try {
      final currentModel = catalog.models
          .where(
            (candidate) => candidate.id == model.id && candidate.chatCompatible,
          )
          .firstOrNull;
      if (currentModel == null) {
        conversationNotice =
            'That model is no longer available for free text chat. Refresh the catalog and choose another.';
        return false;
      }
      if (_activeRecord?.modelId == model.id && !activeConversationArchived) {
        _suppressHistory = true;
        catalog.select(model.id);
        _suppressHistory = false;
        conversationNotice = null;
        return true;
      }
      if (!await flushHistory()) return false;
      final emptyUnbound =
          _activeRecord?.modelId == null &&
          chat.messages.isEmpty &&
          _draftAttachments.isEmpty &&
          draft.isEmpty;
      final record = emptyUnbound && _activeRecord != null
          ? _activeRecord!.copyWith(modelId: model.id, modelName: model.name)
          : _blankRecord(model);
      await historyRepository.save(record, makeActive: true);
      _activateRecord(record);
      _upsertHistory(record.summary);
      historyError = null;
      return true;
    } catch (error) {
      _historyFailure(error);
      return false;
    } finally {
      _historySwitching = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<bool> newConversation() async {
    if (!_beginHistoryNavigation()) return false;
    try {
      if (!await flushHistory()) return false;
      final record = _blankRecord(catalog.selected);
      await historyRepository.save(record, makeActive: true);
      _activateRecord(record);
      _upsertHistory(record.summary);
      historyError = null;
      return true;
    } catch (error) {
      _historyFailure(error);
      return false;
    } finally {
      _historySwitching = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<bool> openConversation(String id) async {
    if (!_beginHistoryNavigation()) return false;
    try {
      if (!await flushHistory()) return false;
      final record = await historyRepository.read(id);
      if (record == null) {
        throw historyFailure(
          'This conversation was not found. It may have been deleted in another tab.',
        );
      }
      if (!_activateRecord(record)) {
        throw historyFailure(
          'The conversation could not be opened. Its stored record was retained unchanged.',
        );
      }
      await historyRepository.setActive(id);
      historyError = null;
      return true;
    } catch (error) {
      _historyFailure(error);
      return false;
    } finally {
      _historySwitching = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<bool> archiveConversation(String id) => _setArchived(id, true);
  Future<bool> restoreConversation(String id) => _setArchived(id, false);

  Future<bool> _setArchived(String id, bool value) async {
    if (!_beginHistoryNavigation()) return false;
    try {
      if (!await flushHistory()) return false;
      final record = await historyRepository.read(id);
      if (record == null) {
        throw historyFailure('This conversation was not found.');
      }
      final updated = record.copyWith(
        archived: value,
        updatedAt: DateTime.now().toUtc(),
      );
      await historyRepository.save(
        updated,
        makeActive: id == activeConversationId,
      );
      if (id == activeConversationId) {
        _activeRecord = updated;
        conversationNotice = value
            ? 'Archived conversation. Restore it to continue.'
            : null;
        if (!value) _bindOriginalModel();
      }
      _upsertHistory(updated.summary);
      historyError = null;
      return true;
    } catch (error) {
      _historyFailure(error);
      return false;
    } finally {
      _historySwitching = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<bool> deleteConversation(String id) async {
    if (!_beginHistoryNavigation()) return false;
    try {
      if (id != activeConversationId && !await flushHistory()) return false;
      await _saving;
      _historyTimer?.cancel();
      _historyTimer = null;
      await historyRepository.delete(id);
      _history.removeWhere((record) => record.id == id);
      if (id == activeConversationId) {
        _suppressHistory = true;
        chat.clear();
        draft = '';
        _draftAttachments = const [];
        store.write('freeform.draft.v1', '');
        _activeRecord = _blankRecord(catalog.selected);
        _revision = _savedRevision = 0;
        conversationNotice = null;
        _suppressHistory = false;
      }
      historyError = null;
      return true;
    } catch (error) {
      _historyFailure(error);
      return false;
    } finally {
      _historySwitching = false;
      if (!_disposed) notifyListeners();
    }
  }

  void setTextScale(double value) {
    textScale = value;
    store.write('freeform.textScale', '$value');
    appearance.value++;
    notifyListeners();
  }

  void setOffline(bool value) {
    workOffline = value;
    store.write('freeform.workOffline', '$value');
    if (value) {
      chat.cancel();
      health.cancelChecks();
    }
    if (!value && platform.online) unawaited(_restoreConnection());
    notifyListeners();
  }

  void _platformChanged() {
    if (_disposed) return;
    if (!platform.online) {
      chat.cancel();
      health.cancelChecks();
    }
    if (!_wasOnline && platform.online && !workOffline) {
      unawaited(_restoreConnection());
    }
    _wasOnline = platform.online;
    if (platform.pwaError != null && platform.pwaError != _lastPwaError) {
      _lastPwaError = platform.pwaError;
      diagnostics.record(
        'PWA',
        failure: AppFailure(FailureKind.pwa, platform.pwaError!),
      );
    }
    notifyListeners();
  }

  Future<void> changeKey(String key) async {
    _keyOverride = true;
    final next = config.copyWith(apiKey: key.trim());
    final problems = next.validate();
    if (problems.isNotEmpty) {
      throw AppFailure(FailureKind.configuration, problems.join('; '));
    }
    await _replaceConfig(next);
  }

  Future<void> _replaceConfig(AppConfig next) async {
    if (!await flushHistory()) return;
    final session = chat.exportSession();
    catalog.dispose();
    health.dispose();
    chat.dispose();
    config = next;
    diagnostics.updateConfig(next);
    _createControllers();
    _suppressHistory = true;
    chat.restoreSession(session);
    _suppressHistory = false;
    notifyListeners();
    await catalog.initialize(refresh: online);
    _bindOriginalModel();
  }

  Future<void> _restoreConnection() {
    return _reconnect ??= _reconnectOnce().whenComplete(
      () => _reconnect = null,
    );
  }

  Future<void> _reconnectOnce() async {
    // Runtime credentials are intentionally not cached. Recover them from the
    // local network-only file after an offline launch, without losing the draft.
    if (kIsWeb && config.apiKey.isEmpty && !_keyOverride) {
      try {
        final response = await transport.send(
          'GET',
          Uri.base.resolve('config/local.json'),
          headers: const {'Cache-Control': 'no-store'},
          timeout: const Duration(seconds: 4),
        );
        final body = await response.readText(maxBytes: 16384);
        if (response.status == 200) {
          final value = jsonDecode(body);
          if (value is! Map<String, dynamic>) {
            throw const FormatException('Expected a configuration object');
          }
          final restored = AppConfig.fromJson(value);
          if (!_disposed && online && !chat.busy) {
            await _replaceConfig(restored);
            return;
          }
        }
      } catch (error) {
        if (!_disposed) {
          diagnostics.record(
            'configuration reconnect',
            failure: const AppFailure(
              FailureKind.configuration,
              'Runtime configuration could not be recovered. Paste a key in Settings.',
            ),
          );
        }
      }
    }
    if (!_disposed && online) await catalog.refresh();
  }

  Future<void> applyUpdate() async {
    if (attachmentPicking) {
      updateError = 'Finish or cancel adding files before updating.';
      notifyListeners();
      return;
    }
    if (chat.busy) return;
    if (!await flushHistory()) {
      updateError =
          'Update paused: conversation history could not be saved. Resolve the storage error or export your content before reloading.';
      notifyListeners();
      return;
    }
    // The awaited transaction already owns messages, files and draft under the
    // original conversation ID. Writing another unscoped legacy snapshot here
    // can be mistaken for a different chat by this or another tab after reload.
    // Keep legacy readers for older versions, but never create new snapshots.
    store.remove('freeform.updateSession.v1');
    store.remove('freeform.draft.v1');
    _legacyUpdateSession = null;
    _persistDraft();
    if (!store.persistenceAvailable || !recoveryStore.persistenceAvailable) {
      updateError =
          'Update paused: browser storage could not save your draft and conversation. Copy them before a manual reload.';
      notifyListeners();
      return;
    }
    await platform.applyUpdate();
  }

  @override
  void dispose() {
    _attachmentCancel?.cancel();
    attachmentPicker.dispose();
    _disposed = true;
    _historyTimer?.cancel();
    unawaited(_historySubscription?.cancel());
    platform.removeListener(_platformChanged);
    catalog.dispose();
    health.dispose();
    chat.dispose();
    platform.dispose();
    diagnostics.dispose();
    historyRepository.close();
    appearance.dispose();
    historyIndexChanges.dispose();
    historyStatus.dispose();
    super.dispose();
  }
}

/// V2 storage reconstructs objects in a different key order. Compare content,
/// including defaults for optional older-session fields, rather than the JSON
/// spelling. Truly different legacy work is still recovered separately.
bool _sameLegacySession(String legacy, Map<String, dynamic> current) {
  Object? canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: canonical(value[key])};
    }
    if (value is List) return value.map(canonical).toList();
    return value;
  }

  Map<String, dynamic> normalize(Object? value) {
    if (value is! Map || value['messages'] is! List) {
      throw const FormatException('Invalid legacy conversation');
    }
    final session = Map<String, dynamic>.from(value);
    session.putIfAbsent('retryUserIndex', () => null);
    session.putIfAbsent('retryModelId', () => null);
    session.putIfAbsent('contextStartIndex', () => 0);
    session.putIfAbsent('outputTokenLimit', () => null);
    session['messages'] = (session['messages'] as List).map((value) {
      final message = Map<String, dynamic>.from(value as Map);
      message.putIfAbsent('modelId', () => null);
      message.putIfAbsent('attachments', () => const []);
      message.putIfAbsent('editedFrom', () => null);
      message.putIfAbsent('finishReason', () => null);
      message.putIfAbsent('usage', () => null);
      message.putIfAbsent('failure', () => null);
      return message;
    }).toList();
    return session;
  }

  try {
    return jsonEncode(canonical(normalize(jsonDecode(legacy)))) ==
        jsonEncode(canonical(normalize(current)));
  } catch (_) {
    return false;
  }
}

class GuardedStore implements LocalStore {
  GuardedStore(this.inner, this.diagnostics);
  final LocalStore inner;
  final Diagnostics diagnostics;
  final MemoryStore fallback = MemoryStore();
  bool _reported = false;
  bool get persistenceAvailable => !_reported;
  void _failed() {
    if (_reported) return;
    _reported = true;
    // Storage can fail synchronously while a widget edits its draft.
    scheduleMicrotask(
      () => diagnostics.record(
        'local storage',
        failure: const AppFailure(
          FailureKind.storage,
          'Browser storage is unavailable or full. This session can continue, but reload recovery may be unavailable.',
        ),
      ),
    );
  }

  @override
  String? read(String key) {
    try {
      return inner.read(key) ?? fallback.read(key);
    } catch (_) {
      _failed();
      return fallback.read(key);
    }
  }

  @override
  void write(String key, String value) {
    fallback.write(key, value);
    try {
      inner.write(key, value);
    } catch (_) {
      _failed();
    }
  }

  @override
  void remove(String key) {
    fallback.remove(key);
    try {
      inner.remove(key);
    } catch (_) {
      _failed();
    }
  }
}
