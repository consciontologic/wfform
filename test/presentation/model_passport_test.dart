import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/app/studio_state.dart';
import 'package:wfform/presentation/model_browser.dart';
import 'package:wfform/shared/diagnostics.dart';
import 'package:wfform/shared/platform.dart';

import 'studio_test.dart' as fixtures;

class _ModelLinksPlatform extends fixtures.FakePlatform {
  Uri? opened;
  bool fail = false;
  @override
  void openUrl(Uri url) {
    if (fail) throw UnsupportedError('Fixture link failure');
    opened = url;
  }
}

void main() {
  test('context labels are concise and leave unknown values unknown', () {
    expect(modelContextLabel(null), 'Not reported');
    expect(modelContextLabel(0), '0 tokens');
    expect(modelContextLabel(512), '512 tokens');
    expect(modelContextLabel(8192), '8.2K tokens');
    expect(modelContextLabel(262144), '262K tokens');
    expect(modelContextLabel(1000000), '1M tokens');
  });

  test(
    'description preview uses one original sentence and bounds long text',
    () {
      expect(modelDescriptionPreview('One sentence.'), 'One sentence.');
      expect(
        modelDescriptionPreview(
          'First sentence. Second sentence. Third sentence.',
        ),
        'First sentence.',
      );
      final sentence = 'A very long sentence about capabilities ' * 30;
      final preview = modelDescriptionPreview(sentence);
      expect(preview.runes.length, lessThanOrEqualTo(180));
      expect(sentence.startsWith(preview), true);
      expect(preview.endsWith(' '), false);
      final unicode = '😀' * 300;
      expect(modelDescriptionPreview(unicode), '😀' * 180);
      expect(
        modelDescriptionPreview(
          'Version 3.1 supports code. It handles text. More.',
        ),
        'Version 3.1 supports code.',
      );
      expect(modelDescriptionPreview('最初の文。次の文。'), '最初の文。');
    },
  );

  testWidgets(
    'passport shows overview then explicitly reveals exact metadata',
    (tester) async {
      final h = fixtures.Harness();
      final dto = fixtures.modelFixture()
        ..['context_length'] = 262144
        ..['description'] = 'First sentence. Second sentence. Third sentence.';
      h.transport.catalogBody = {
        'data': [dto],
      };
      await h.mount(tester, const Size(390, 844));
      unawaited(
        openDetails(
          tester.element(find.byType(Scaffold).first),
          h.state,
          h.state.catalog.models.single,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('262K tokens'), findsOneWidget);
      expect(find.text('Text input'), findsOneWidget);
      expect(find.text('Text output'), findsOneWidget);
      expect(find.text('test/chat'), findsOneWidget);
      expect(find.text('First sentence.'), findsOneWidget);
      expect(find.text(dto['description'] as String), findsNothing);
      expect(find.text('max_tokens, reasoning'), findsNothing);
      expect(find.textContaining('prompt: 0'), findsNothing);
      await tester.ensureVisible(find.text('Show full description'));
      await tester.tap(find.text('Show full description'));
      await tester.pumpAndSettle();
      expect(find.text(dto['description'] as String), findsOneWidget);
      h.state.health.recordSuccess('test/chat', provider: 'Fixture provider');
      await tester.pumpAndSettle();
      expect(find.text(dto['description'] as String), findsOneWidget);
      await tester.tap(find.text('Show less'));
      await tester.pumpAndSettle();
      for (final entry in {
        'Pricing': 'prompt: 0',
        'Parameters': 'max_tokens, reasoning',
        'Provider & context': '262144 tokens',
        'Files': 'UTF-8 text and source files:',
        'Availability details': h.state.health.forModel('test/chat').message,
      }.entries) {
        await tester.ensureVisible(find.text(entry.key));
        await tester.tap(find.text(entry.key));
        await tester.pumpAndSettle();
        expect(find.textContaining(entry.value), findsWidgets);
      }
      expect(find.byTooltip('Recheck availability'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Gemma-style overview at 125% keeps only its first sentence', (
    tester,
  ) async {
    const first =
        "Gemma 4 31B Instruct is Google DeepMind's 30.7B dense "
        'multimodal model supporting text and image input with text output.';
    const full =
        '$first Features a 256K token context window, configurable '
        'thinking/reasoning mode, native function...';
    expect(
      modelDescriptionPreview(full.replaceFirst('supporting ', 'supporting\n')),
      first.replaceFirst('supporting ', 'supporting\n'),
    );
    final h = fixtures.Harness();
    h.state.setTextScale(1.25);
    h.transport.catalogBody = {
      'data': [fixtures.modelFixture()..['description'] = full],
    };
    await h.mount(tester, const Size(1600, 1050));
    await h.state.selectModel(h.state.catalog.models.single);
    await tester.pumpAndSettle();
    expect(find.text(first), findsOneWidget);
    expect(find.text(full), findsNothing);
    await tester.ensureVisible(find.text('Show full description'));
    await tester.tap(find.text('Show full description'));
    await tester.pumpAndSettle();
    expect(find.text(full), findsOneWidget);
    expect(find.text('Ellipsis supplied by OpenRouter.'), findsOneWidget);
    await tester.tap(find.text('Show less'));
    await tester.pumpAndSettle();
    expect(find.text(first), findsOneWidget);
    expect(find.text(full), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('passport disclosure controls work by keyboard at narrow 200%', (
    tester,
  ) async {
    final h = fixtures.Harness();
    h.state.setTextScale(2);
    await h.mount(tester, const Size(320, 740));
    unawaited(
      openDetails(
        tester.element(find.byType(Scaffold).first),
        h.state,
        h.state.catalog.models.first,
      ),
    );
    await tester.pumpAndSettle();
    for (final entry in {
      'Availability details': 'No recent inference observation.',
      'Pricing': 'prompt: 0',
      'Parameters': 'max_tokens, reasoning',
      'Files': 'UTF-8 text and source files:',
      'Provider & context': '8192 tokens',
    }.entries) {
      final title = find.text(entry.key);
      final content = find.textContaining(entry.value);
      expect(content, findsNothing);
      await tester.ensureVisible(title);
      await tester.pumpAndSettle();
      Focus.of(tester.element(title)).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(content, findsWidgets, reason: entry.key);
      expect(tester.takeException(), isNull);
      await tester.tap(title);
      await tester.pumpAndSettle();
      expect(content, findsNothing, reason: entry.key);
    }
  });

  testWidgets(
    'compact model source opens exact URL and reports adapter failure',
    (tester) async {
      final platform = _ModelLinksPlatform();
      final transport = fixtures.FakeTransport();
      final state = StudioState(
        config: fixtures.Harness.config,
        transport: transport,
        store: MemoryStore(),
        platform: platform,
        diagnostics: Diagnostics(fixtures.Harness.config),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        state.dispose();
        unawaited(transport.chatBytes.close());
      });
      await state.initialize();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ModelDetails(
                state: state,
                model: state.catalog.models.first,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Model page'));
      expect(platform.opened.toString(), 'https://openrouter.ai/test/chat');
      platform.fail = true;
      await tester.tap(find.text('Model page'));
      await tester.pump();
      expect(
        find.textContaining('Could not open the model page.'),
        findsOneWidget,
      );
      expect(find.byTooltip('Copy model page link'), findsOneWidget);
      expect(transport.catalogCalls, 1);
      expect(transport.sends, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
