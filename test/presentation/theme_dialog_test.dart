import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/app/theme.dart';
import 'package:wfform/presentation/brand_mark.dart';
import 'package:wfform/presentation/model_browser.dart';
import 'package:wfform/presentation/utilities.dart';

import 'studio_test.dart' as fixtures;

void main() {
  testWidgets(
    'dialog header paints each identity and keeps its controls accessible',
    (tester) async {
      for (final glyph in BrandGlyph.values) {
        var closed = false;
        await tester.pumpWidget(
          MaterialApp(
            theme: studioTheme(),
            home: Scaffold(
              body: StudioDialogHeader(
                title: 'Header fixture',
                glyph: glyph,
                color: StudioPalette.light.modelDetails,
                closeTooltip: 'Close fixture',
                onClose: () => closed = true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final iconFinder = find.descendant(
          of: find.byType(StudioDialogHeader),
          matching: find.byType(BrandIcon),
        );
        expect(iconFinder, findsOneWidget);
        expect(tester.widget<BrandIcon>(iconFinder).glyph, glyph);
        expect(find.byType(Image), findsNothing);
        expect(
          find.ancestor(
            of: iconFinder,
            matching: find.byType(ExcludeSemantics),
          ),
          findsWidgets,
        );
        expect(find.text('Header fixture'), findsOneWidget);
        await tester.tap(find.byTooltip('Close fixture'));
        expect(closed, true);
        expect(tester.takeException(), null);
      }
    },
  );

  testWidgets('model chooser refuses selection while a response is active', (
    tester,
  ) async {
    final h = fixtures.Harness();
    await h.mount(tester, const Size(768, 1024));
    // A deterministic pending-response state; no remote inference is needed.
    h.state.chat.busy = true;
    final context = tester.element(find.byType(Scaffold).first);
    unawaited(openModels(context, h.state));
    await tester.pumpAndSettle();
    final row = find.ancestor(
      of: find.text('Quiet Chat'),
      matching: find.byType(TextButton),
    );
    expect(tester.widget<TextButton>(row).onPressed, null);
    expect(
      find.textContaining('Finish or cancel the current response'),
      findsWidgets,
    );
    expect(h.state.catalog.selectedId, null);
    expect(find.byTooltip('Close model browser'), findsOneWidget);
    h.state.chat.busy = false;
    await h.dispose(tester);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      '${mode.name} popups use readable colorful identities at narrow 200 percent text',
      (tester) async {
        final h = fixtures.Harness();
        h.state.setThemeMode(mode);
        h.state.setTextScale(2);
        await h.mount(tester, const Size(320, 740));
        final palette = mode == ThemeMode.dark
            ? StudioPalette.dark
            : StudioPalette.light;
        final model = h.state.catalog.models.firstWhere(
          (model) => model.chatCompatible,
        );
        final context = tester.element(find.byType(Scaffold).first);
        final popups = [
          (
            () => openModels(context, h.state),
            BrandGlyph.models,
            palette.modelChooser,
            'Close model browser',
          ),
          (
            () => openDetails(context, h.state, model),
            BrandGlyph.models,
            palette.modelDetails,
            'Close model details',
          ),
          (
            () => openDiagnostics(context, h.state),
            BrandGlyph.diagnostics,
            palette.diagnostics,
            'Close diagnostics',
          ),
          (
            () => openSettings(context, h.state),
            BrandGlyph.settings,
            palette.lilac,
            'Close settings',
          ),
        ];
        for (final popup in popups) {
          unawaited(popup.$1());
          await tester.pumpAndSettle();
          final headerFinder = find.byType(StudioDialogHeader);
          final header = tester.widget<StudioDialogHeader>(headerFinder);
          expect(header.glyph, popup.$2);
          expect(header.color, popup.$3);
          expect(
            Theme.of(tester.element(headerFinder)).brightness,
            mode == ThemeMode.dark ? Brightness.dark : Brightness.light,
          );
          expect(tester.takeException(), null);
          await tester.tap(find.byTooltip(popup.$4));
          await tester.pumpAndSettle();
        }
        await h.dispose(tester);
      },
    );
  }

  testWidgets(
    'appearance control changes the open Settings dialog and preserves draft',
    (tester) async {
      final h = fixtures.Harness();
      h.state.setThemeMode(ThemeMode.light);
      await h.mount(tester, const Size(768, 1024));
      h.state.setDraft('A draft while changing appearance');
      final context = tester.element(find.byType(Scaffold).first);
      unawaited(openSettings(context, h.state));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Dark'));
      await tester.pumpAndSettle();
      expect(h.state.themeMode, ThemeMode.dark);
      expect(
        Theme.of(tester.element(find.byType(StudioDialogHeader))).brightness,
        Brightness.dark,
      );
      expect(h.state.draft, 'A draft while changing appearance');
      await tester.tap(find.widgetWithText(ChoiceChip, 'Light'));
      await tester.pumpAndSettle();
      expect(h.state.themeMode, ThemeMode.light);
      expect(
        Theme.of(tester.element(find.byType(StudioDialogHeader))).brightness,
        Brightness.light,
      );
      expect(tester.takeException(), null);
      await h.dispose(tester);
    },
  );
}
