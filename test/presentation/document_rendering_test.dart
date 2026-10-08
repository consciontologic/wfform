import 'dart:collection';
import 'dart:convert';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/features/chat/attachment.dart';
import 'package:wfform/features/chat/chat_controller.dart';
import 'package:wfform/features/documents/document_format.dart';
import 'package:wfform/features/documents/document_view.dart';
import 'package:wfform/features/documents/code_highlighter.dart';
import 'package:wfform/presentation/attachment_widgets.dart';

import 'studio_test.dart' as fixture;

void main() {
  String? copied;
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    copied = null;
  });

  testWidgets(
    'assistant Markdown exposes a heading and an independent code copy action',
    (tester) async {
      final h = fixture.Harness();
      await h.mount(tester, const Size(1000, 1000));
      h.state.chat.restoreSession(
        jsonEncode({
          'version': 1,
          'messages': [
            const ChatMessage(
              role: 'assistant',
              content:
                  '## Result\n\n**Ready** for code.\n\n```javascript\nconst count = 3;\n```',
            ).toJson(),
          ],
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('Result', findRichText: true), findsOneWidget);
      expect(find.byTooltip('Copy code'), findsOneWidget);
      await tester.tap(find.byTooltip('Copy code'));
      expect(copied, 'const count = 3;\n');
      await h.dispose(tester);
    },
  );

  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    double width = 800,
    double scale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, navigator) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: navigator!,
        ),
        home: Scaffold(
          body: SelectionArea(child: SingleChildScrollView(child: child)),
        ),
      ),
    );
  }

  testWidgets(
    'Markdown keeps tables lists and Unicode code selectable without loading images',
    (tester) async {
      const source =
          '# Heading\n\n- First\n- Second\n\n| A | B |\n|---|---|\n| one | two |\n\n![alt](https://example.invalid/image.png)\n\n```json\n{"hello":"世界 👋"}\n```';
      await mount(tester, const DocumentView(source: source));
      expect(find.text('Heading', findRichText: true), findsOneWidget);
      expect(find.text('First', findRichText: true), findsOneWidget);
      expect(find.byType(Table), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      await tester.ensureVisible(find.byTooltip('Copy code'));
      await tester.tap(find.byTooltip('Copy code'));
      expect(copied, '{"hello":"世界 👋"}\n');
      final spans = tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .where((text) => text.textSpan != null)
          .map((text) => text.textSpan!);
      expect(spans.any((span) => span.toPlainText().contains('世界 👋')), true);
      await tester.ensureVisible(find.byTooltip('Copy source'));
      await tester.tap(find.byTooltip('Copy source'));
      expect(copied, source);
    },
  );

  testWidgets(
    'attachment preview shows actual filename and supports source at 320px 200 percent',
    (tester) async {
      final file = ChatAttachment.fromBytes(
        name: 'config.yml',
        mimeType: 'application/yaml',
        bytes: utf8.encode('name: 世界\nvalue: 3\n'),
      );
      await mount(tester, AttachmentList(files: [file]), width: 320, scale: 2);
      await tester.tap(find.byType(InputChip));
      await tester.pumpAndSettle();
      expect(find.textContaining('config.yml\nYAML'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Copy code'));
      expect(copied, file.textContent);
      await tester.tap(find.byTooltip('Close file preview'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
    },
  );

  testWidgets(
    'rendered rich text supports real pointer selection and keyboard copy',
    (tester) async {
      await mount(tester, const DocumentView(source: '**Ready** for code.'));
      final found = find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.textSpan?.toPlainText() == 'Ready for code.',
      );
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: found, matching: find.byType(RichText)).first,
      );
      Offset caret(int offset) => paragraph.localToGlobal(
        paragraph.getOffsetForCaret(
              TextPosition(offset: offset),
              const Rect.fromLTWH(0, 0, 2, 20),
            ) +
            Offset(0, paragraph.preferredLineHeight / 2),
      );
      final pointer = await tester.startGesture(
        caret(0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await pointer.moveTo(caret('Ready for code.'.length));
      await pointer.up();
      await pointer.removePointer();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(copied, 'Ready for code.');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('long filenames scroll with preview at narrow large-text sizes', (
    tester,
  ) async {
    final filename = '${List.filled(47, 'long-').join()}.json';
    final file = ChatAttachment.fromBytes(
      name: filename,
      mimeType: 'application/json',
      bytes: utf8.encode('{"value": 1}'),
    );
    await mount(tester, AttachmentList(files: [file]), width: 320, scale: 2);
    await tester.tap(find.byType(InputChip));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byTooltip('Copy source'));
    await tester.tap(find.byTooltip('Copy source'));
    expect(copied, file.textContent);
    await tester.tap(find.byTooltip('Close file preview'));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'large documents page without truncating full copy or Unicode boundaries',
    (tester) async {
      final source =
          '${List.filled(sourcePageCharacters - 1, 'a').join()}👋${List.filled(16000, 'b').join()}';
      await mount(tester, DocumentView(source: source));
      expect(find.text('Large document · paged source view'), findsOneWidget);
      final first = tester.widget<CodeBlock>(find.byType(CodeBlock)).source;
      expect(first.endsWith('a'), true);
      await tester.tap(find.byTooltip('Copy code'));
      expect(copied, source);
      await tester.ensureVisible(find.text('Next page'));
      await tester.tap(find.text('Next page'));
      await tester.pump();
      expect(
        tester
            .widget<CodeBlock>(find.byType(CodeBlock))
            .source
            .startsWith('👋'),
        true,
      );
    },
  );

  testWidgets(
    'stream coalesces previews and completion flushes the final source',
    (tester) async {
      await mount(
        tester,
        const DocumentView(source: '## First', streaming: true),
      );
      await mount(
        tester,
        const DocumentView(source: '## Latest', streaming: true),
      );
      expect(find.text('First', findRichText: true), findsOneWidget);
      expect(find.text('Latest', findRichText: true), findsNothing);
      await tester.pump(const Duration(milliseconds: 180));
      expect(find.text('Latest', findRichText: true), findsOneWidget);
      await mount(tester, const DocumentView(source: '## Complete'));
      expect(find.text('Complete', findRichText: true), findsOneWidget);
      await mount(tester, const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'streaming source highlights each displayed preview once, not every delta',
    (tester) async {
      const format = DocumentFormat('JavaScript', 'javascript');
      String source(int index) => 'const count = $index;';
      TextSpan renderedSpan() => tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .singleWhere((text) => text.textSpan != null)
          .textSpan!;
      await mount(
        tester,
        DocumentView(source: source(0), format: format, streaming: true),
      );
      final rendered = HashSet<TextSpan>.identity()..add(renderedSpan());
      for (var update = 1; update <= 20; update++) {
        await mount(
          tester,
          DocumentView(source: source(update), format: format, streaming: true),
        );
        await tester.pump(const Duration(milliseconds: 32));
        rendered.add(renderedSpan());
      }
      expect(
        rendered,
        hasLength(4),
        reason:
            'Twenty 32 ms updates expose only three new 180 ms previews; '
            'the unchanged source must reuse its highlighted spans.',
      );
      // Copy uses the newest complete input even before the preview catches up.
      await tester.tap(find.byTooltip('Copy code'));
      expect(copied, source(20));
      await mount(tester, DocumentView(source: source(20), format: format));
      expect(renderedSpan().toPlainText(), source(20));
      expect(rendered.contains(renderedSpan()), isFalse);
    },
  );

  testWidgets(
    'highlight memo follows source language and brightness while copy stays current',
    (tester) async {
      const source = 'const value = 3;';
      Future<void> show({
        String text = source,
        String language = 'javascript',
        Brightness brightness = Brightness.light,
        String? copySource,
      }) => tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
            body: CodeBlock(
              source: text,
              language: language,
              copySource: copySource,
            ),
          ),
        ),
      );
      TextSpan span() =>
          tester.widget<SelectableText>(find.byType(SelectableText)).textSpan!;
      await show();
      final original = span();
      await show(copySource: 'full source beyond this preview');
      expect(identical(span(), original), isTrue);
      await tester.tap(find.byTooltip('Copy code'));
      expect(copied, 'full source beyond this preview');
      await show(brightness: Brightness.dark);
      await tester.pumpAndSettle();
      final dark = span();
      expect(dark.toPlainText(), source);
      expect(identical(dark, original), isFalse);
      Set<Color> tokenColors(TextSpan value) {
        final result = <Color>{};
        void visit(InlineSpan node) {
          final color = node.style?.color;
          if (color != null) result.add(color);
          if (node is TextSpan) node.children?.forEach(visit);
        }

        visit(value);
        return result;
      }

      expect(tokenColors(original), contains(const Color(0xff683394)));
      expect(tokenColors(dark), contains(const Color(0xffcbb6ff)));
      await show(language: 'unknown', brightness: Brightness.dark);
      expect(span().text, source);
      await show(text: 'const value = 4;', brightness: Brightness.dark);
      expect(span().toPlainText(), 'const value = 4;');
      expect(identical(span(), dark), isFalse);
    },
  );

  test(
    'named syntax highlighting keeps exact source and safely falls back',
    () {
      for (final language in ['js', 'json', 'yaml', 'c', 'unknown']) {
        const source = 'const value = "世界";\r\n';
        expect(
          highlightedSource(source, language, Brightness.light).toPlainText(),
          source,
        );
      }
      final large = List.filled(maxHighlightedCodeCharacters + 1, 'x').join();
      expect(
        highlightedSource(large, 'javascript', Brightness.dark).text,
        large,
      );
      expect(documentFormatFor('README.md').markdown, true);
    },
  );
}
