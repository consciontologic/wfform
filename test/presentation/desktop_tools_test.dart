import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/app/studio_state.dart';
import 'package:wfform/config/app_config.dart';
import 'package:wfform/features/tools/mcp_client.dart';
import 'package:wfform/features/tools/tools.dart';
import 'package:wfform/shared/transport.dart';
import 'package:wfform/presentation/studio_app.dart';
import 'package:wfform/shared/diagnostics.dart';
import 'package:wfform/shared/platform.dart';
import '../chat/fakes.dart';
import 'studio_test.dart' show FakePlatform, modelFixture;

class MobilePlatform extends FakePlatform {
  @override
  bool get toolsAvailable => false;
}

void main() {
  const config = AppConfig(apiKey: 'fixture-key');
  StudioState create({
    required bool mobile,
    required FakeTransport transport,
  }) => StudioState(
    config: config,
    transport: transport,
    store: MemoryStore(),
    platform: mobile ? MobilePlatform() : FakePlatform(),
    diagnostics: Diagnostics(config),
  );

  for (final size in [const Size(390, 844), const Size(1024, 1366)]) {
    testWidgets('phone/tablet tools explain desktop requirement at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final transport = FakeTransport(
        (_) => jsonResponse({
          'data': [modelFixture()],
        }),
      );
      final state = create(mobile: true, transport: transport)..setTextScale(2);
      addTearDown(state.dispose);
      final semantics = tester.ensureSemantics();
      try {
        await state.initialize();
        await tester.pumpWidget(StudioApp(state: state));
        await tester.pumpAndSettle();
        final faded = find.ancestor(
          of: find.text('Tools'),
          matching: find.byType(Opacity),
        );
        expect(tester.widget<Opacity>(faded).opacity, lessThan(1));
        expect(
          find.bySemanticsLabel(RegExp('Tools unavailable on this device')),
          findsWidgets,
        );
        await tester.tap(find.text('Tools'));
        await tester.pumpAndSettle();
        expect(find.text('Tools need a desktop computer'), findsOneWidget);
        expect(find.textContaining('Chatting works as usual'), findsOneWidget);
        expect(find.text('Connect'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets('a narrow desktop window still opens tool connections', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = create(
      mobile: false,
      transport: FakeTransport(
        (_) => jsonResponse({
          'data': [modelFixture()],
        }),
      ),
    );
    addTearDown(state.dispose);
    await state.initialize();
    await tester.pumpWidget(StudioApp(state: state));
    await tester.pumpAndSettle();
    final opacity = find.ancestor(
      of: find.text('Tools'),
      matching: find.byType(Opacity),
    );
    expect(tester.widget<Opacity>(opacity).opacity, 1);
    await tester.tap(find.text('Tools'));
    await tester.pumpAndSettle();
    expect(find.text('Tools & connections'), findsOneWidget);
    expect(find.text('Tools need a desktop computer'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Connect'),
      180,
      scrollable: find
          .descendant(
            of: find.byType(Dialog),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Connect').hitTestable(), findsOneWidget);
  });

  test(
    'mobile saved tool selections do not block ordinary chat or dispatch tools',
    () async {
      final transport = FakeTransport(
        (request) => request.method == 'GET'
            ? jsonResponse({
                'data': [modelFixture()],
              })
            : streamResponse(
                '${delta('Hello from ordinary chat')}data: [DONE]\n\n',
              ),
      );
      final state = create(mobile: true, transport: transport);
      addTearDown(state.dispose);
      await state.initialize();
      final model = state.catalog.models.first;
      await state.selectModel(model);
      state.health.recordSuccess(model.id);
      expect(
        state.chat.restoreSession(
          jsonEncode({
            'version': 1,
            'messages': [],
            'enabledTools': ['saved_tool'],
            'requestParameters': {
              'tool_choice': 'required',
              'parallel_tool_calls': true,
            },
          }),
        ),
        true,
      );
      await state.chat.send(model, 'Hello');
      expect(state.chat.error, isNull);
      expect(state.chat.messages.last.content, 'Hello from ordinary chat');
      final sent = transport.requests
          .where((r) => r.method == 'POST')
          .single
          .json;
      expect(sent, isNot(contains('tools')));
      expect(sent, isNot(contains('tool_choice')));
      expect(sent, isNot(contains('parallel_tool_calls')));
      expect(state.chat.enabledTools, {'saved_tool'});
      expect(state.chat.requestParameters['tool_choice'], 'required');
    },
  );

  test('mobile connection attempts make no MCP request', () async {
    final transport = FakeTransport(
      (_) => throw StateError('MCP must not be contacted'),
    );
    final state = create(mobile: true, transport: transport);
    addTearDown(state.dispose);
    expect(
      await state.toolConnections.connect(
        McpConnection(
          id: 'demo',
          name: 'Demo',
          url: 'http://localhost:8787/mcp',
        ),
      ),
      false,
    );
    expect(state.toolConnections.error, contains('desktop computer'));
    expect(state.chat.setEnabledTools({'arbitrary_tool'}), false);
    final registry = state.toolConnections.registry;
    await expectLater(
      registry.connect(
        McpConnection(
          id: 'bypass',
          name: 'Bypass',
          url: 'http://localhost:8787/mcp',
        ),
        cancel: CancelToken(),
      ),
      throwsA(isA<AppFailure>()),
    );
    var approved = false;
    final result = await registry.execute(
      const ToolCall(id: 'call', name: 'arbitrary_tool', arguments: '{}'),
      enabledNames: {'arbitrary_tool'},
      cancel: CancelToken(),
      confirm: (_, _) async {
        approved = true;
        return true;
      },
    );
    expect(result.isError, true);
    expect(result.dispatched, false);
    expect(result.content, contains('desktop computer'));
    expect(approved, false);
    expect(transport.requests, isEmpty);
  });
}
