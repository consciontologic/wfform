import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/app/studio_state.dart';
import 'package:wfform/config/app_config.dart';
import 'package:wfform/features/models/catalog.dart';
import 'package:wfform/presentation/studio_app.dart';
import 'package:wfform/presentation/brand_mark.dart';
import 'package:wfform/shared/diagnostics.dart';
import 'package:wfform/shared/platform.dart';
import 'package:wfform/shared/transport.dart';
import 'package:wfform/shared/attachment_picker.dart';

Map<String, dynamic> modelFixture({
  String id = 'test/chat',
  String name = 'Quiet Chat',
  bool compatible = true,
}) => {
  'id': id,
  'name': name,
  'description': 'A quiet test model with deterministic metadata.',
  'context_length': 8192,
  'architecture': {
    'input_modalities': ['text'],
    'output_modalities': [compatible ? 'text' : 'embeddings'],
  },
  'pricing': {'prompt': '0', 'completion': '0', 'request': '0'},
  'supported_parameters': ['max_tokens', 'reasoning'],
  'top_provider': {'context_length': 8192, 'is_moderated': false},
};

ApiResponse jsonResponse(Object value, {int status = 200}) =>
    ApiResponse(status, const {}, Stream.value(utf8.encode(jsonEncode(value))));

class FakePlatform extends PlatformBridge {
  bool connected = true;
  bool update = false;
  int applied = 0;
  int inspections = 0;
  @override
  bool get online => connected;
  @override
  bool get updateAvailable => update;
  @override
  bool get installAvailable => false;
  @override
  String? get pwaError => null;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> checkForUpdate() async {}
  @override
  Future<void> applyUpdate() async {
    applied++;
  }

  @override
  Future<void> install() async {}
  @override
  Future<Map<String, Object?>> inspectPwa() async {
    inspections++;
    return {
      'supported': true,
      'controlled': true,
      'cacheNames': ['fixture-shell-v1'],
      'entries': ['main.dart.js'],
    };
  }

  @override
  void exportText(String filename, String content) {}
  void setOnline(bool value) {
    connected = value;
    notifyListeners();
  }
}

class FakeTransport implements ApiTransport {
  Object catalogBody = {
    'data': [
      modelFixture(),
      modelFixture(
        id: 'test/embedding',
        name: 'Quiet Embedding',
        compatible: false,
      ),
    ],
  };
  Completer<ApiResponse>? catalogPending;
  AppFailure? catalogFailure;
  final chatBytes = StreamController<List<int>>();
  int catalogCalls = 0;
  int sends = 0;
  Object? lastChatBody;
  CancelToken? chatToken;
  @override
  Future<ApiResponse> send(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    Object? body,
    required Duration timeout,
    CancelToken? cancel,
  }) async {
    if (method == 'GET') {
      catalogCalls++;
      if (catalogFailure != null) throw catalogFailure!;
      if (catalogPending != null) return catalogPending!.future;
      return jsonResponse(catalogBody);
    }
    sends++;
    lastChatBody = body;
    chatToken = cancel;
    return ApiResponse(200, const {
      'content-type': 'text/event-stream',
    }, chatBytes.stream);
  }

  void text(String value) => chatBytes.add(
    utf8.encode(
      'data: ${jsonEncode({
        'choices': [
          {
            'delta': {'content': value},
            'finish_reason': null,
          },
        ],
      })}\n\n',
    ),
  );
  Future<void> finish() async {
    chatBytes.add(
      utf8.encode(
        'data: ${jsonEncode({
          'choices': [
            {'delta': {}, 'finish_reason': 'stop'},
          ],
        })}\n\ndata: [DONE]\n\n',
      ),
    );
    await chatBytes.close();
  }
}

class Harness {
  Harness({MemoryStore? memory, AttachmentPicker? picker}) {
    state = StudioState(
      config: config,
      transport: transport,
      store: memory ?? store,
      platform: platform,
      diagnostics: Diagnostics(config),
      attachmentPicker: picker,
    );
  }
  static const config = AppConfig(
    apiKey: 'test-key',
    requestTimeout: Duration(seconds: 10),
  );
  final store = MemoryStore();
  final platform = FakePlatform();
  final transport = FakeTransport();
  late final StudioState state;
  bool disposed = false;
  Future<void> mount(
    WidgetTester tester,
    Size size, {
    bool initialize = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    addTearDown(() => dispose(tester));
    if (initialize) await state.initialize();
    await tester.pumpWidget(StudioApp(state: state));
    await tester.pump();
  }

  Future<void> dispose(WidgetTester tester) async {
    if (disposed) return;
    disposed = true;
    await tester.pumpWidget(const SizedBox());
    state.dispose();
    if (!transport.chatBytes.isClosed) unawaited(transport.chatBytes.close());
  }
}

Finder get composer => find.byKey(const ValueKey('composer'));
Future<void> resize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets(
    'model changes create separate saved conversations with archive restore and delete',
    (tester) async {
      final h = Harness();
      h.transport.catalogBody = {
        'data': [
          modelFixture(),
          modelFixture(id: 'test/second', name: 'Second Model'),
        ],
      };
      await h.mount(tester, const Size(1440, 1000));
      await h.state.selectModel(
        h.state.catalog.models.firstWhere((m) => m.id == 'test/chat'),
      );
      h.state.chat.restoreSession(
        jsonEncode({
          'version': 1,
          'messages': [
            {
              'role': 'user',
              'content': 'Alpha conversation',
              'reasoning': '',
              'modelId': 'test/chat',
              'complete': true,
            },
            {
              'role': 'assistant',
              'content': 'Saved fixture reply',
              'reasoning': '',
              'modelId': 'test/chat',
              'complete': true,
            },
          ],
        }),
      );
      await tester.pumpAndSettle();
      await tester.enterText(composer, 'Continue Alpha later');
      await h.state.flushHistory();
      final firstId = h.state.activeConversationId!;
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('model-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Second Model'));
      await tester.pumpAndSettle();
      expect(h.state.catalog.selectedId, 'test/second');
      expect(h.state.activeConversationId, isNot(firstId));
      expect(h.state.chat.messages, isEmpty);
      expect(tester.widget<TextField>(composer).controller!.text, isEmpty);
      await tester.enterText(composer, 'Beta draft');
      await h.state.flushHistory();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alpha conversation'));
      await tester.pumpAndSettle();
      expect(h.state.catalog.selectedId, 'test/chat');
      expect(h.state.chat.messages.last.content, 'Saved fixture reply');
      expect(
        tester.widget<TextField>(composer).controller!.text,
        'Continue Alpha later',
      );
      await tester.tap(find.byTooltip('Archive Alpha conversation'));
      await tester.pumpAndSettle();
      expect(h.state.activeConversationId, isNot(firstId));
      expect(h.state.activeConversationArchived, false);
      expect(tester.widget<TextField>(composer).readOnly, false);
      await tester.enterText(composer, 'Keep writing after archive');
      expect(h.state.draft, 'Keep writing after archive');
      await tester.tap(find.widgetWithText(ChoiceChip, 'Archived'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Restore Alpha conversation'));
      await tester.pumpAndSettle();
      expect(h.state.activeConversationArchived, false);
      expect(tester.widget<TextField>(composer).readOnly, false);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Chats'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Archive Alpha conversation'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Archived'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete Alpha conversation'));
      await tester.pumpAndSettle();
      expect(find.text('Delete conversation?'), findsNothing);
      expect(h.state.history.any((entry) => entry.id == firstId), false);
      expect(h.state.history.any((entry) => entry.title == 'Beta draft'), true);
      expect(h.transport.sends, 0);
      expect(tester.takeException(), null);
      await h.dispose(tester);
    },
  );

  testWidgets(
    'theme switch persists and preserves the composer while utility controls stay unique',
    (tester) async {
      final h = Harness();
      await h.mount(tester, const Size(1440, 900));
      expect(find.text('wfform'), findsOneWidget);
      expect(find.byTooltip('Diagnostics'), findsOneWidget);
      expect(find.byTooltip('Settings'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byTooltip('Settings')).dy,
        greaterThan(tester.getTopLeft(find.byTooltip('Diagnostics')).dy),
      );
      expect(find.byTooltip('Selected model details'), findsNothing);
      expect(find.byTooltip('Browse models'), findsNothing);
      expect(tester.widget<TextField>(composer).minLines, 3);
      await tester.enterText(composer, 'Theme keeps this draft');
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Dark'));
      await tester.pumpAndSettle();
      expect(h.state.themeMode, ThemeMode.dark);
      expect(
        Theme.of(tester.element(find.byType(Dialog))).brightness,
        Brightness.dark,
      );
      await tester.tap(find.byTooltip('Close settings'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(composer).controller!.text,
        'Theme keeps this draft',
      );
      await resize(tester, const Size(390, 844));
      await tester.tap(find.byTooltip('Open sidebar'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Diagnostics'), findsOneWidget);
      expect(find.byTooltip('Settings'), findsOneWidget);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Light'));
      await tester.pumpAndSettle();
      expect(h.state.themeMode, ThemeMode.light);
      await tester.tap(find.byTooltip('Close settings'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(composer).controller!.text,
        'Theme keeps this draft',
      );
      expect(h.store.read('freeform.themeMode'), 'light');
      expect(tester.takeException(), null);
      await h.dispose(tester);
    },
  );

  testWidgets(
    'expanded diagnostic technical details are exposed in semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final h = Harness();
      try {
        await h.mount(tester, const Size(1440, 900));
        h.state.diagnostics.clear();
        h.state.diagnostics.record(
          'catalog.fixture.validation',
          model: 'test/chat',
          status: 200,
          duration: const Duration(milliseconds: 17),
          failure: const AppFailure(
            FailureKind.schema,
            'Fixture schema mismatch.',
            field: r'$.data[2].pricing.prompt',
            expected: 'nonnegative decimal',
            actual: 'boolean',
            details: 'Fixture response had pricing.prompt=true.',
            requestId: 'fixture-correlation-123',
          ),
        );
        await tester.tap(find.byTooltip('Diagnostics'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('catalog.fixture.validation · schema'));
        await tester.pumpAndSettle();
        final technical = find.bySemanticsLabel(
          RegExp('fixture-correlation-123'),
        );
        expect(technical, findsWidgets);
        final label = tester
            .getSemantics(technical.first)
            .getSemanticsData()
            .label;
        expect(label, contains(r'$.data[2].pricing.prompt'));
        expect(label, contains('nonnegative decimal'));
        expect(label, contains('boolean'));
        expect(label, contains('"httpStatus": 200'));
        expect(label, contains('"durationMs": 17'));
        expect(label, contains('Fixture response had pricing.prompt=true.'));
        expect(h.transport.sends, 0);
        expect(tester.takeException(), null);
      } finally {
        await h.dispose(tester);
        semantics.dispose();
      }
    },
  );

  testWidgets('PWA inspection metadata is exposed in dialog semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final h = Harness();
    try {
      await h.mount(tester, const Size(768, 1024));
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Inspect offline cache'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inspect offline cache'));
      await tester.pumpAndSettle();
      expect(find.text('Offline cache & startup'), findsOneWidget);
      final report = find.bySemanticsLabel(RegExp('fixture-shell-v1'));
      expect(report, findsWidgets);
      final label = tester.getSemantics(report.first).getSemanticsData().label;
      expect(label, contains('"controlled": true'));
      expect(label, contains('main.dart.js'));
      expect(h.platform.inspections, 1);
      expect(h.transport.sends, 0);
      expect(tester.takeException(), null);
    } finally {
      await h.dispose(tester);
      semantics.dispose();
    }
  });

  testWidgets(
    'completed answer, reasoning and exact model details reach the semantics tree',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final h = Harness();
      const answer = 'Fixture answer: strawberry contains three letters r.';
      const reasoning = 'Fixture reasoning: count each occurrence in the word.';
      try {
        await h.mount(tester, const Size(768, 1024));
        await h.state.selectModel(
          h.state.catalog.models.firstWhere((model) => model.id == 'test/chat'),
        );
        h.state.chat.restoreSession(
          jsonEncode({
            'version': 1,
            'messages': [
              {
                'role': 'user',
                'content': 'Fixture question',
                'reasoning': '',
                'modelId': 'test/chat',
                'complete': true,
              },
              {
                'role': 'assistant',
                'content': answer,
                'reasoning': reasoning,
                'modelId': 'test/chat',
                'complete': true,
              },
            ],
          }),
        );
        await tester.pumpAndSettle();
        final answerNode = find.bySemanticsLabel(RegExp(RegExp.escape(answer)));
        expect(answerNode, findsOneWidget);
        expect(
          tester.getSemantics(answerNode).getSemanticsData().label,
          contains(answer),
        );
        await tester.tap(find.text('Model reasoning'));
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel(reasoning), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('model-selector')));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Model details: Quiet Chat'));
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel('Quiet Chat'), findsWidgets);
        final idNode = find.bySemanticsLabel('test/chat');
        expect(idNode, findsWidgets);
        expect(
          tester.getSemantics(idNode.first).getSemanticsData().label,
          'test/chat',
        );
        await tester.ensureVisible(find.text('Provider & context'));
        await tester.tap(find.text('Provider & context'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('8192 tokens'));
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel('8192 tokens'), findsWidgets);
        await tester.ensureVisible(find.text('Files'));
        await tester.tap(find.text('Files'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('text → text'));
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel('text → text'), findsWidgets);
        expect(h.transport.sends, 0);
        expect(tester.takeException(), null);
      } finally {
        await h.dispose(tester);
        semantics.dispose();
      }
    },
  );

  for (final entry in {
    'compact': const Size(390, 844),
    'medium': const Size(768, 1024),
    'expanded': const Size(1440, 900),
  }.entries) {
    testWidgets('${entry.key} layout has its intended navigation', (
      tester,
    ) async {
      final h = Harness();
      await h.mount(tester, entry.value);
      expect(
        find.byKey(const ValueKey('expanded-sidebar')),
        entry.key == 'expanded' ? findsOneWidget : findsNothing,
      );
      expect(
        find.byKey(const ValueKey('medium-rail')),
        entry.key == 'medium' ? findsOneWidget : findsNothing,
      );
      expect(composer, findsOneWidget);
      expect(find.byType(WfformMark), findsOneWidget);
      expect(find.byIcon(Icons.south_east), findsNothing);
      expect(find.byKey(const ValueKey('model-selector')), findsOneWidget);
      expect(tester.takeException(), null);
      await h.dispose(tester);
    });
  }

  testWidgets('loading, empty and API failure have distinct presentations', (
    tester,
  ) async {
    final h = Harness();
    final pending = Completer<ApiResponse>();
    h.transport.catalogPending = pending;
    final initialization = h.state.initialize();
    await h.mount(tester, const Size(1440, 900), initialize: false);
    await tester.tap(find.byKey(const ValueKey('model-selector')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Loading models…'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsWidgets);
    pending.complete(jsonResponse({'data': []}));
    await initialization;
    await tester.pump();
    expect(
      find.text('No eligible free models are currently listed.'),
      findsOneWidget,
    );
    h.transport.catalogPending = null;
    h.transport.catalogFailure = const AppFailure(
      FailureKind.network,
      'The fixture network failed.',
      retryable: true,
    );
    await h.state.catalog.refresh();
    await tester.pump();
    expect(
      find.text('Catalog unavailable. Refresh to try again.'),
      findsOneWidget,
    );
    expect(find.text('The fixture network failed.'), findsOneWidget);
    expect(tester.takeException(), null);
    await h.dispose(tester);
  });

  testWidgets('cached stale catalog stays inspectable when offline', (
    tester,
  ) async {
    final memory = MemoryStore();
    memory.write(
      CatalogController.cacheKey,
      jsonEncode({
        'version': 1,
        'apiBaseUrl': Harness.config.apiBaseUrl,
        'savedAt': DateTime.now()
            .subtract(const Duration(days: 2))
            .toUtc()
            .toIso8601String(),
        'models': [modelFixture()],
      }),
    );
    final h = Harness(memory: memory);
    h.platform.setOnline(false);
    h.transport.catalogFailure = const AppFailure(
      FailureKind.network,
      'Offline fixture connection.',
    );
    await h.mount(tester, const Size(1440, 900));
    expect(h.state.catalog.stale, true);
    await tester.tap(find.byKey(const ValueKey('model-selector')));
    await tester.pumpAndSettle();
    expect(find.text('Offline · cached catalog'), findsOneWidget);
    expect(find.textContaining('remote chat is unavailable'), findsOneWidget);
    expect(find.text('Quiet Chat'), findsOneWidget);
    await tester.tap(find.byTooltip('Close model browser'));
    await tester.pumpAndSettle();
    final send = tester.widget<IconButton>(
      find.descendant(
        of: find.byTooltip('Chat unavailable offline'),
        matching: find.byType(IconButton),
      ),
    );
    expect(send.onPressed, null);
    await tester.enterText(composer, 'Offline draft survives');
    h.transport.catalogFailure = null;
    h.platform.setOnline(true);
    await tester.pump();
    await tester.pump();
    expect(h.state.online, true);
    expect(h.state.draft, 'Offline draft survives');
    expect(h.transport.catalogCalls, 1);
    expect(tester.takeException(), null);
    await h.dispose(tester);
  });

  testWidgets(
    'saved Work offline preference restores draft without a launch request',
    (tester) async {
      final memory = MemoryStore();
      memory.write('freeform.workOffline', 'true');
      memory.write('freeform.draft.v1', 'Saved offline draft');
      final h = Harness(memory: memory);
      await h.mount(tester, const Size(390, 844));
      expect(h.state.workOffline, true);
      expect(h.state.online, false);
      expect(h.transport.catalogCalls, 0);
      expect(
        tester.widget<TextField>(composer).controller!.text,
        'Saved offline draft',
      );
      expect(find.byTooltip('Chat unavailable offline'), findsOneWidget);
      expect(tester.takeException(), null);
      await h.dispose(tester);
    },
  );

  testWidgets(
    'searchable chooser exposes accessible tap details for incompatible models',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final h = Harness();
      await h.mount(tester, const Size(390, 844));
      await tester.tap(find.byKey(const ValueKey('model-selector')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Search free models'),
        'embedding',
      );
      await tester.pump();
      expect(find.text('Quiet Chat'), findsNothing);
      expect(find.text('Quiet Embedding'), findsOneWidget);
      final row = find.ancestor(
        of: find.text('Quiet Embedding'),
        matching: find.byType(TextButton),
      );
      expect(tester.widget<TextButton>(row).onPressed, null);
      final details = find.byTooltip('Model details: Quiet Embedding');
      final data = tester.getSemantics(details).getSemanticsData();
      expect(
        '${data.label} ${data.tooltip}',
        contains('Model details: Quiet Embedding'),
      );
      expect(data.hasAction(SemanticsAction.tap), true);
      await tester.tap(details);
      await tester.pumpAndSettle();
      expect(find.text('MODEL PASSPORT'), findsOneWidget);
      expect(find.text('test/embedding'), findsWidgets);
      expect(find.text('Context window'), findsOneWidget);
      expect(h.state.catalog.selectedId, null);
      await tester.tap(find.byTooltip('Close model details'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Search free models'),
        'chat',
      );
      await tester.pump();
      await tester.tap(find.text('Quiet Chat'));
      await tester.pumpAndSettle();
      expect(h.state.catalog.selectedId, 'test/chat');
      expect(find.byTooltip('Close model browser'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('model-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Model details: Quiet Chat'));
      await tester.pumpAndSettle();
      expect(find.text('MODEL PASSPORT'), findsOneWidget);
      expect(tester.takeException(), null);
      await h.dispose(tester);
      semantics.dispose();
    },
  );

  testWidgets(
    'keyboard focus exposes model information and activates selection',
    (tester) async {
      final h = Harness();
      await h.mount(tester, const Size(1440, 900));
      await tester.tap(find.byKey(const ValueKey('model-selector')));
      await tester.pumpAndSettle();
      final target = find.ancestor(
        of: find.text('Quiet Chat'),
        matching: find.byType(TextButton),
      );
      final buttonContext = tester.element(target);
      Focus.of(buttonContext).requestFocus();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.textContaining('8192 context tokens'), findsWidgets);
      // Enter on the actual model button is exercised through keyboard traversal.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(h.state.catalog.selectedId, 'test/chat');
      expect(tester.takeException(), null);
      await h.dispose(tester);
    },
  );

  testWidgets(
    'draft, selection, composer focus and active stream survive breakpoint transitions',
    (tester) async {
      final h = Harness();
      await h.mount(tester, const Size(390, 844));
      await h.state.selectModel(
        h.state.catalog.models.firstWhere((model) => model.id == 'test/chat'),
      );
      h.state.health.recordSuccess('test/chat');
      await tester.pump();
      await tester.enterText(composer, 'Original question');
      await tester.tap(find.byTooltip('Send message'));
      await tester.pump();
      await tester.pump();
      expect(h.state.chat.busy, true);
      expect(h.transport.sends, 1);
      h.transport.text('Partial answer');
      await tester.pump();
      await tester.pump();
      await tester.enterText(composer, 'Next draft, still here');
      final focus = tester.widget<TextField>(composer).focusNode!;
      expect(focus.hasFocus, true);
      for (final size in [
        const Size(768, 1024),
        const Size(1440, 900),
        const Size(390, 844),
      ]) {
        await resize(tester, size);
        expect(h.state.catalog.selectedId, 'test/chat');
        expect(h.state.draft, 'Next draft, still here');
        expect(
          tester.widget<TextField>(composer).controller!.text,
          'Next draft, still here',
        );
        expect(
          identical(tester.widget<TextField>(composer).focusNode, focus),
          true,
        );
        expect(focus.hasFocus, true);
        expect(h.state.chat.busy, true);
        expect(h.transport.sends, 1);
        expect(h.transport.chatToken!.isCancelled, false);
        expect(tester.takeException(), null);
      }
      await tester.runAsync(() async {
        await h.transport.finish();
      });
      await tester.pumpAndSettle();
      // Async stream cancellation completes outside the widget fake clock.
      // Drain one real event-loop turn, then flush the resulting UI microtasks.
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(h.state.chat.busy, false);
      expect(h.state.chat.messages.last.content, 'Partial answer');
      expect(h.state.draft, 'Next draft, still here');
      await h.dispose(tester);
    },
  );

  testWidgets(
    '320px viewport at 200 percent text keeps composer and dialogs reachable',
    (tester) async {
      final h = Harness();
      h.state.setTextScale(2);
      await h.mount(tester, const Size(320, 740));
      expect(composer, findsOneWidget);
      expect(tester.takeException(), null);
      await tester.tap(find.byKey(const ValueKey('model-selector')));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(TextField, 'Search free models'),
        findsOneWidget,
      );
      expect(tester.takeException(), null);
      await tester.scrollUntilVisible(
        find.byTooltip('Model details: Quiet Chat'),
        220,
        scrollable: find
            .descendant(
              of: find.byType(Dialog),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.byTooltip('Model details: Quiet Chat'));
      await tester.pumpAndSettle();
      expect(find.text('MODEL PASSPORT'), findsOneWidget);
      expect(find.byTooltip('Close model details'), findsOneWidget);
      expect(tester.takeException(), null);
      await h.dispose(tester);
    },
  );

  testWidgets('software keyboard and reduced motion do not hide the composer', (
    tester,
  ) async {
    final h = Harness();
    await h.mount(tester, const Size(390, 844));
    tester.view.viewInsets = const FakeViewPadding(bottom: 310);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(() {
      tester.view.resetViewInsets();
      tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
    });
    await tester.tap(composer);
    await tester.pump();
    expect(tester.getBottomRight(composer).dy, lessThanOrEqualTo(844 - 310));
    expect(tester.takeException(), null);
    await h.dispose(tester);
  });
}
