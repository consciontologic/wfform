import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/presentation/brand_mark.dart';
import 'package:wfform/presentation/history_browser.dart';
import 'package:wfform/shared/attachment_picker.dart';
import 'package:wfform/shared/transport.dart';

import 'studio_test.dart' as fixture;

class _DocumentPicker implements AttachmentPicker {
  int calls = 0;

  @override
  Future<List<PickedAttachmentFile>> pick({
    required Set<String> allowedMimeTypes,
    int existingCount = 0,
    int existingBytes = 0,
    CancelToken? cancel,
  }) async {
    calls++;
    return [
      PickedAttachmentFile(
        name: 'wrapper.md',
        mimeType: 'text/markdown',
        bytes: utf8.encode('# A wrapped document'),
      ),
    ];
  }

  @override
  void dispose() {}
}

Finder _glyph(BrandGlyph glyph) => find.byWidgetPredicate(
  (widget) => widget is BrandIcon && widget.glyph == glyph,
);

void main() {
  setUpAll(fixture.loadAppFonts);
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    for (final (size, scale) in [
      (const Size(320, 740), 2.0),
      (const Size(390, 844), 1.0),
      (const Size(1440, 1000), 1.0),
    ]) {
      testWidgets(
        '${mode.name} navigation glyphs preserve actions at $size and $scale text',
        (tester) async {
          final h = fixture.Harness();
          h.state.setThemeMode(mode);
          h.state.setTextScale(scale);
          await h.mount(tester, size);
          await tester.enterText(
            fixture.composer,
            'Preserve branded navigation',
          );
          final contextButton = find.ancestor(
            of: find.text('Context'),
            matching: find.byWidgetPredicate((widget) => widget is TextButton),
          );
          expect(
            find.descendant(
              of: contextButton,
              matching: _glyph(BrandGlyph.context),
            ),
            findsOneWidget,
          );
          await tester.ensureVisible(contextButton);
          await tester.pumpAndSettle();
          expect(contextButton.hitTestable(), findsOneWidget);
          await tester.tap(contextButton);
          await tester.pumpAndSettle();
          expect(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: _glyph(BrandGlyph.context),
            ),
            findsOneWidget,
          );
          final tokens = find.byWidgetPredicate(
            (widget) =>
                widget is TextField &&
                widget.decoration?.labelText == 'Maximum response tokens',
          );
          await tester.ensureVisible(tokens);
          await tester.enterText(tokens, '1024');
          await tester.ensureVisible(find.text('Apply to next request'));
          await tester.tap(find.text('Apply to next request'));
          await tester.pumpAndSettle();
          expect(h.state.chat.outputTokenLimit, 1024);
          Future<void> openSidebar() async {
            if (size.width < 1050) {
              await tester.tap(find.byTooltip('Open sidebar'));
              await tester.pumpAndSettle();
            }
          }

          await openSidebar();
          for (final (label, glyph, selected) in [
            ('Chats', BrandGlyph.chats, true),
            ('Drafts', BrandGlyph.drafts, false),
            ('Archived', BrandGlyph.archived, false),
          ]) {
            final chip = find.widgetWithText(ChoiceChip, label);
            expect(
              find.descendant(of: chip, matching: _glyph(glyph)),
              findsOneWidget,
            );
            expect(tester.widget<ChoiceChip>(chip).selected, selected);
            expect(tester.widget<ChoiceChip>(chip).showCheckmark, isTrue);
          }
          for (final (label, emptyText, glyph) in [
            ('Archived', 'No archived conversations.', BrandGlyph.archived),
            (
              'Chats',
              'Sent conversations appear here. Unsent work is in Drafts.',
              BrandGlyph.chats,
            ),
          ]) {
            final chip = find.widgetWithText(ChoiceChip, label);
            await tester.ensureVisible(chip);
            await tester.tap(chip);
            await tester.pumpAndSettle();
            expect(tester.widget<ChoiceChip>(chip).selected, isTrue);
            expect(find.text(emptyText), findsOneWidget);
            expect(
              find.descendant(
                of: find.byType(ConversationHistory),
                matching: _glyph(glyph),
              ),
              findsNWidgets(2),
            );
          }
          for (final (label, glyph, close) in [
            ('Diagnostics', BrandGlyph.diagnostics, 'Close diagnostics'),
            ('Settings', BrandGlyph.settings, 'Close settings'),
          ]) {
            final action = find.widgetWithText(ListTile, label);
            expect(
              find.descendant(of: action, matching: _glyph(glyph)),
              findsOneWidget,
            );
            await tester.ensureVisible(action);
            await tester.tap(action);
            await tester.pumpAndSettle();
            expect(
              find.descendant(of: find.byType(Dialog), matching: _glyph(glyph)),
              findsOneWidget,
            );
            await tester.tap(find.byTooltip(close));
            await tester.pumpAndSettle();
            if (label == 'Diagnostics') await openSidebar();
          }
          expect(h.state.draft, 'Preserve branded navigation');
          expect(h.transport.sends, 0);
          expect(tester.takeException(), isNull);
          await h.dispose(tester);
        },
      );
    }
  }

  for (final size in [const Size(390, 844), const Size(1440, 1000)]) {
    testWidgets('brand family keeps labeled controls and drafts at $size', (
      tester,
    ) async {
      final picker = _DocumentPicker();
      final h = fixture.Harness(picker: picker);
      await h.mount(tester, size);
      expect(find.byType(WfformMark), findsOneWidget);
      final selector = find.byKey(const ValueKey('model-selector'));
      expect(
        find.descendant(of: selector, matching: _glyph(BrandGlyph.models)),
        findsOneWidget,
      );
      expect(_glyph(BrandGlyph.chat), findsWidgets);
      final addFiles = find.ancestor(
        of: find.text('Attachments'),
        matching: find.byWidgetPredicate((widget) => widget is TextButton),
      );
      expect(tester.widget<TextButton>(addFiles).onPressed, isNull);
      expect(
        find.descendant(of: addFiles, matching: _glyph(BrandGlyph.documents)),
        findsOneWidget,
      );

      await tester.tap(selector);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('Choose a free model'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: _glyph(BrandGlyph.models),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Quiet Chat'));
      await tester.pumpAndSettle();
      expect(h.state.catalog.selectedId, 'test/chat');
      await tester.enterText(fixture.composer, 'Keep this wrapper draft');
      await tester.tap(addFiles);
      await tester.pumpAndSettle();
      expect(picker.calls, 1);
      final attachment = find.byType(InputChip);
      expect(
        find.descendant(of: attachment, matching: _glyph(BrandGlyph.documents)),
        findsOneWidget,
      );
      await tester.tap(attachment);
      await tester.pumpAndSettle();
      expect(find.text('File preview'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: _glyph(BrandGlyph.documents),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Close file preview'));
      await tester.pumpAndSettle();
      if (size.width < 1050) {
        await tester.tap(find.byTooltip('Open sidebar'));
        await tester.pumpAndSettle();
      }
      expect(_glyph(BrandGlyph.chats), findsNWidgets(2));
      final newChat = find.ancestor(
        of: find.text('New conversation'),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      );
      expect(
        find.descendant(of: newChat, matching: _glyph(BrandGlyph.chat)),
        findsOneWidget,
      );
      await tester.tap(newChat);
      await tester.pumpAndSettle();
      expect(h.state.draft, 'Keep this wrapper draft');
      expect(h.state.draftAttachments.single.name, 'wrapper.md');
      expect(h.transport.sends, 0);
      expect(tester.takeException(), isNull);
      await h.dispose(tester);
    });
  }
}
