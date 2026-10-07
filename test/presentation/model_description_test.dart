import 'dart:async';
import 'dart:convert';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/features/models/model.dart';
import 'package:wfform/presentation/model_browser.dart';
import 'package:wfform/presentation/selectable_surface.dart';
import 'package:wfform/shared/diagnostics.dart';

import 'studio_test.dart' as fixtures;

void main() {
  test('complete bounded descriptions survive DTO and cache round trips', () {
    final description = List.generate(
      60,
      (i) =>
          'Paragraph $i describes model capabilities, limits and Unicode 日本語.',
    ).join('\n\n');
    final json = fixtures.modelFixture()..['description'] = description;
    final model = FreeModel.fromJson(json);
    expect(model.description, description);
    expect(
      FreeModel.fromJson(jsonDecode(jsonEncode(model.toJson()))).description,
      description,
    );
    expect(
      () => FreeModel.fromJson(json..['description'] = 'x' * 40001),
      throwsA(
        isA<AppFailure>()
            .having((failure) => failure.kind, 'kind', FailureKind.schema)
            .having(
              (failure) => failure.field,
              'field',
              r'$.model.description',
            ),
      ),
    );
  });

  testWidgets('model previews omit the repeated details instruction', (
    tester,
  ) async {
    final h = fixtures.Harness();
    await h.mount(tester, const Size(768, 1024));
    unawaited(openModels(tester.element(find.byType(Scaffold).first), h.state));
    await tester.pumpAndSettle();
    final previews = tester.widgetList<SelectableTooltip>(
      find.byType(SelectableTooltip),
    );
    expect(
      previews.any((t) => t.message.contains('8192 context tokens')),
      true,
    );
    expect(
      previews.any((t) => t.message.contains('Open Model details for pricing')),
      false,
    );
    expect(find.byTooltip('Model details: Quiet Chat'), findsOneWidget);
    await tester.tap(find.byTooltip('Model details: Quiet Chat'));
    await tester.pumpAndSettle();
    expect(find.text('MODEL PASSPORT'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final ending in ['...', '…']) {
    testWidgets(
      'upstream $ending is identified and its model link is copyable',
      (tester) async {
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          },
        );
        addTearDown(() {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          );
        });
        final h = fixtures.Harness();
        h.state.setTextScale(2);
        h.transport.catalogBody = {
          'data': [
            fixtures.modelFixture()
              ..['description'] = 'The API supplied this$ending',
          ],
        };
        await h.mount(tester, const Size(320, 740));
        final model = h.state.catalog.models.single;
        unawaited(
          openDetails(
            tester.element(find.byType(Scaffold).first),
            h.state,
            model,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(model.description), findsOneWidget);
        expect(find.text('Ellipsis supplied by OpenRouter.'), findsOneWidget);
        final linkCopy = find.byTooltip('Copy model page link');
        await tester.ensureVisible(linkCopy);
        await tester.pumpAndSettle();
        await tester.tap(linkCopy);
        await tester.pump();
        expect(copied, 'https://openrouter.ai/test/chat');
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final view in [
    (size: const Size(320, 740), scale: 2.0, dialog: true),
    (size: const Size(1600, 1050), scale: 1.0, dialog: false),
    (size: const Size(1600, 1050), scale: 2.0, dialog: true),
  ]) {
    testWidgets('full paragraphs wrap, scroll and copy at $view', (
      tester,
    ) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });
      final description = List.generate(
        8,
        (i) =>
            'Paragraph $i: complete capabilities, limitations, and examples. '
            'This sentence must remain readable without hiding the final words.',
      ).join('\n\n');
      final h = fixtures.Harness();
      h.state.setTextScale(view.scale);
      h.transport.catalogBody = {
        'data': [fixtures.modelFixture()..['description'] = description],
      };
      await h.mount(tester, view.size);
      final model = h.state.catalog.models.single;
      if (view.dialog) {
        unawaited(
          openDetails(
            tester.element(find.byType(Scaffold).first),
            h.state,
            model,
          ),
        );
      } else {
        await h.state.selectModel(model);
      }
      await tester.pumpAndSettle();
      expect(find.text(description), findsNothing);
      final expandDescription = find.text('Show full description');
      await tester.ensureVisible(expandDescription);
      await tester.tap(expandDescription);
      await tester.pumpAndSettle();
      final descriptionFinder = find.text(description);
      expect(descriptionFinder, findsOneWidget);
      final text = tester.widget<Text>(descriptionFinder);
      expect(text.maxLines, isNull);
      expect(text.overflow, isNot(TextOverflow.ellipsis));
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: descriptionFinder, matching: find.byType(RichText)),
      );
      expect(paragraph.didExceedMaxLines, false);
      expect(paragraph.text.toPlainText(), description);
      await Scrollable.ensureVisible(
        tester.element(descriptionFinder),
        alignment: 0,
      );
      await tester.pumpAndSettle();
      final start = paragraph.localToGlobal(
        paragraph.getOffsetForCaret(
              const TextPosition(offset: 0),
              const Rect.fromLTWH(0, 0, 2, 20),
            ) +
            Offset(0, paragraph.preferredLineHeight / 2),
      );
      final gesture = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(25, 0));
      await gesture.up();
      await gesture.removePointer();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(copied, contains(description));
      await Scrollable.ensureVisible(
        tester.element(descriptionFinder),
        alignment: 1,
      );
      await tester.pumpAndSettle();
      final viewport = tester.getRect(find.byType(ModelDetails));
      final end = paragraph.localToGlobal(
        paragraph.getOffsetForCaret(
          TextPosition(offset: description.length),
          const Rect.fromLTWH(0, 0, 2, 20),
        ),
      );
      expect(end.dy, lessThanOrEqualTo(view.size.height));
      expect(viewport.width, lessThan(view.size.width));
      expect(tester.takeException(), isNull);
    });
  }
}
