import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/app/studio_state.dart';
import 'package:wfform/config/app_config.dart';
import 'package:wfform/features/tools/tools.dart';
import 'package:wfform/features/documents/document_view.dart';
import 'package:wfform/presentation/connections_dialog.dart';
import 'package:wfform/shared/diagnostics.dart';
import 'package:wfform/shared/platform.dart';
import '../chat/fakes.dart';
import 'studio_test.dart' show FakePlatform;

void main() {
  // CachingAssetBundle retains futures whose decoding callbacks belong to the
  // widget test's fake-async zone. Each test needs its own asset futures.
  setUp(rootBundle.clear);

  testWidgets(
    'tools guides close cleanly with active mouse hover and semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      final state = StudioState(
        config: const AppConfig(),
        transport: FakeTransport((_) => jsonResponse({})),
        store: MemoryStore(),
        platform: FakePlatform(),
        diagnostics: Diagnostics(const AppConfig()),
      );
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => openTools(context, state),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await mouse.addPointer(location: Offset.zero);
        Future<void> click(Finder finder) async {
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
          final position = tester.getCenter(finder);
          await mouse.moveTo(position);
          await tester.pump(const Duration(milliseconds: 800));
          await mouse.down(position);
          await mouse.up();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }

        for (var i = 0; i < 2; i++) {
          await click(find.text('Open'));
          await click(find.text('How to use tools'));
          await click(find.text('Companion setup'));
          await click(find.byTooltip('Back to tools guide'));
          await click(find.byTooltip('Close tools guide'));
          await click(find.byTooltip('Close tools'));
        }
        expect(find.byType(Dialog), findsNothing);
      } finally {
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox());
        state.dispose();
        semantics.dispose();
      }
    },
  );

  testWidgets('connection setup remains reachable at 200 percent on 320px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = StudioState(
      config: const AppConfig(),
      transport: FakeTransport((_) => jsonResponse({})),
      store: MemoryStore(),
      platform: FakePlatform(),
      diagnostics: Diagnostics(const AppConfig()),
    );
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => openTools(context, state),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Connect'),
      260,
      scrollable: find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          )
          .first,
      maxScrolls: 20,
    );
    expect(find.text('Connect').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('connections remain optional and pairing token is obscured', (
    tester,
  ) async {
    final state = StudioState(
      config: const AppConfig(),
      transport: FakeTransport((_) => jsonResponse({})),
      store: MemoryStore(),
      platform: FakePlatform(),
      diagnostics: Diagnostics(const AppConfig()),
    );
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => openTools(context, state),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ordinary chat works'), findsOneWidget);
    await tester.tap(find.text('How to use tools'));
    await tester.pumpAndSettle();
    expect(find.byType(DocumentView), findsOneWidget);
    expect(
      tester.widget<DocumentView>(find.byType(DocumentView)).source,
      contains('Allow once'),
    );
    await tester.tap(find.text('Companion setup'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DocumentView>(
            find.descendant(
              of: find.byType(Dialog).last,
              matching: find.byType(DocumentView),
            ),
          )
          .source,
      contains('wfformcomp'),
    );
    await tester.tap(find.byTooltip('Back to tools guide'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close tools guide'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('mcp-token')))
          .obscureText,
      isTrue,
    );
    await tester.scrollUntilVisible(
      find.text('Connect'),
      220,
      scrollable: find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          )
          .first,
    );
    expect(find.text('Connect'), findsOneWidget);
  });
  testWidgets(
    'tool approval displays server and arguments and defaults to denial',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      bool? result;
      const tool = ConnectedTool(
        name: 'mcp_read',
        serverName: 'My computer',
        connectionId: 'one',
        originalName: 'read_file',
        description: 'Read selected file',
        inputSchema: {},
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await approveTool(context, tool, {
                    'path': 'notes.txt',
                    'code': 'print("hi")\nprint(2)',
                  });
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('My computer'), findsOneWidget);
      expect(find.textContaining('notes.txt'), findsOneWidget);
      expect(find.text(r'$.code · decoded text'), findsOneWidget);
      expect(
        tester
            .widgetList<CodeBlock>(find.byType(CodeBlock))
            .any((block) => block.source == 'print("hi")\nprint(2)'),
        true,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Deny'));
      await tester.pumpAndSettle();
      expect(result, false);
    },
  );
}
