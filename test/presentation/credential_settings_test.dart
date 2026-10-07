import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/app/studio_state.dart';
import 'package:wfform/config/app_config.dart';
import 'package:wfform/config/credential_preference.dart';
import 'package:wfform/features/history/history_repository.dart';
import 'package:wfform/presentation/studio_app.dart';
import 'package:wfform/presentation/utilities.dart';
import 'package:wfform/shared/diagnostics.dart';
import 'package:wfform/shared/platform.dart';

import '../history/history_state_test.dart'
    show FailingRepository, GatedRepository;
import '../shared/credential_preference_test.dart' show FailingCredentialStore;
import 'studio_test.dart' as fixtures;

class CredentialHarness {
  CredentialHarness({LocalStore? store, HistoryRepository? history}) {
    state = StudioState(
      config: const AppConfig(apiKey: 'runtime-key'),
      transport: transport,
      store: store ?? MemoryStore(),
      platform: fixtures.FakePlatform(),
      diagnostics: Diagnostics(const AppConfig(apiKey: 'runtime-key')),
      historyRepository: history,
    );
    addTearDown(() {
      state.dispose();
      unawaited(transport.chatBytes.close());
    });
  }
  final transport = fixtures.FakeTransport();
  late final StudioState state;

  Future<void> mount(WidgetTester tester, {bool narrow = false}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = narrow
        ? const Size(320, 700)
        : const Size(1280, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    if (narrow) state.setTextScale(2);
    await state.initialize();
    await tester.pumpWidget(StudioApp(state: state));
    await tester.pumpAndSettle();
    unawaited(openSettings(tester.element(find.byType(Scaffold).first), state));
    await tester.pumpAndSettle();
  }
}

Finder get keyField => find.byWidgetPredicate(
  (widget) =>
      widget is TextField &&
      widget.decoration?.labelText == 'OpenRouter API key',
);

Future<void> press(WidgetTester tester, String label) async {
  final button = find.text(label);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  for (final replacement in ['latest-browser-key', '']) {
    test(
      'runtime config waiting on history cannot override ${replacement.isEmpty ? 'a cleared' : 'a replaced'} key',
      () async {
        final store = MemoryStore();
        final history = GatedRepository();
        final h = CredentialHarness(store: store, history: history);
        final runtime = Completer<AppConfig?>();
        final initializing = h.state.initialize(
          loadConfiguration: () => runtime.future,
        );
        while (h.state.historyLoading) {
          await Future<void>.delayed(Duration.zero);
        }
        h.state.setDraft('Keep work during configuration loading');
        history.gate = Completer<void>();
        // The explicit save starts first and blocks at history persistence.
        final savingKey = h.state.changeKey(replacement);
        runtime.complete(
          const AppConfig(
            apiKey: 'late-runtime-key',
            healthTtl: Duration(minutes: 17),
          ),
        );
        // Runtime configuration now also waits on the same pending checkpoint,
        // having read the earlier preference. It must resolve again at apply.
        await Future<void>.delayed(Duration.zero);
        history.gate!.complete();
        await Future.wait([savingKey, initializing]);
        expect(h.state.config.apiKey, replacement);
        expect(h.state.config.healthTtl, const Duration(minutes: 17));
        expect(store.read(CredentialPreference.storageKey), replacement);
        expect(h.state.draft, 'Keep work during configuration loading');
      },
    );
  }

  test(
    'fresh state restores browser override while retaining runtime options',
    () async {
      final store = MemoryStore();
      final first = CredentialHarness(store: store);
      await first.state.initialize();
      await first.state.changeKey('browser-key');
      final restored = CredentialHarness(store: store);
      expect(restored.state.config.apiKey, 'browser-key');
      await restored.state.initialize(
        loadConfiguration: () async => const AppConfig(
          apiKey: 'different-runtime-key',
          healthTtl: Duration(minutes: 13),
          requestTimeout: Duration(seconds: 55),
        ),
      );
      expect(restored.state.config.apiKey, 'browser-key');
      expect(restored.state.config.healthTtl, const Duration(minutes: 13));
      expect(restored.state.config.requestTimeout, const Duration(seconds: 55));
      await restored.state.changeKey('');
      final cleared = CredentialHarness(store: store);
      await cleared.state.initialize(
        loadConfiguration: () async => const AppConfig(apiKey: 'runtime-key'),
      );
      expect(cleared.state.config.apiKey, isEmpty);
      expect(cleared.state.credentialPreference.overrideValue, '');
    },
  );

  test(
    'failed history flush does not persist or apply a replacement key',
    () async {
      final store = MemoryStore();
      final history = FailingRepository();
      final h = CredentialHarness(store: store, history: history);
      await h.state.initialize();
      h.state.setDraft('Preserve this draft');
      history.fail = true;
      await expectLater(
        h.state.changeKey('new-key'),
        throwsA(isA<AppFailure>()),
      );
      expect(h.state.config.apiKey, 'runtime-key');
      expect(store.read(CredentialPreference.storageKey), isNull);
      expect(h.state.draft, 'Preserve this draft');
    },
  );

  testWidgets('save replaces the key and explicit clear survives fresh state', (
    tester,
  ) async {
    final store = MemoryStore();
    final h = CredentialHarness(store: store);
    await h.mount(tester);
    await tester.ensureVisible(keyField);
    await tester.enterText(keyField, 'new-browser-key');
    await press(tester, 'Save key');
    expect(find.byTooltip('Close settings'), findsNothing);
    expect(h.state.config.apiKey, 'new-browser-key');
    expect(store.read(CredentialPreference.storageKey), 'new-browser-key');
    expect(find.text('API key saved in this browser.'), findsOneWidget);
    unawaited(
      openSettings(tester.element(find.byType(Scaffold).first), h.state),
    );
    await tester.pumpAndSettle();
    await press(tester, 'Clear saved key');
    expect(h.state.config.apiKey, isEmpty);
    expect(CredentialHarness(store: store).state.config.apiKey, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'denied storage keeps settings and typed key with visible error',
    (tester) async {
      final store = FailingCredentialStore();
      final h = CredentialHarness(store: store);
      await h.mount(tester);
      await tester.ensureVisible(keyField);
      await tester.enterText(keyField, 'unsaved-browser-key');
      store.failWrite = true;
      await press(tester, 'Save key');
      expect(find.byTooltip('Close settings'), findsOneWidget);
      expect(
        tester.widget<TextField>(keyField).controller!.text,
        'unsaved-browser-key',
      );
      expect(h.state.config.apiKey, 'runtime-key');
      expect(
        find.textContaining('Could not confirm the API key was saved'),
        findsOneWidget,
      );
      expect(find.text('API key saved in this browser.'), findsNothing);
      expect(
        h.state.diagnostics.export(),
        isNot(contains('unsaved-browser-key')),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'startup read error is visible and key controls fit 320px at 200%',
    (tester) async {
      final store = FailingCredentialStore()..failRead = true;
      final h = CredentialHarness(store: store);
      await h.mount(tester, narrow: true);
      expect(
        find.textContaining('The saved API key could not be read'),
        findsOneWidget,
      );
      for (final label in ['Save key', 'Clear saved key']) {
        final button = find.text(label);
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        expect(button.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
}
