import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/app/theme.dart';

double contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  return ((a > b ? a : b) + .05) / ((a > b ? b : a) + .05);
}

void main() {
  for (final brightness in Brightness.values) {
    test('${brightness.name} palette keeps text and controls readable', () {
      final theme = studioTheme(brightness: brightness);
      final palette = theme.extension<StudioPalette>()!;
      final surfaces = {
        'paper': palette.paper,
        'surface': palette.surface,
        'cream': palette.cream,
        'sage': palette.sage,
        'peach': palette.peach,
        'lilac': palette.lilac,
        'diagnostics header': palette.diagnostics,
        'model details header': palette.modelDetails,
        'model chooser header': palette.modelChooser,
      };
      for (final entry in surfaces.entries) {
        expect(
          contrast(palette.ink, entry.value),
          greaterThanOrEqualTo(4.5),
          reason: 'Normal text on ${entry.key}',
        );
      }
      for (final surface in [palette.paper, palette.surface, palette.cream]) {
        expect(
          contrast(palette.muted, surface),
          greaterThanOrEqualTo(4.5),
          reason: 'Secondary text remains readable',
        );
        expect(
          contrast(palette.border, surface),
          greaterThanOrEqualTo(3),
          reason: 'Input and panel boundaries remain visible',
        );
      }
      expect(
        contrast(theme.colorScheme.primary, theme.colorScheme.onPrimary),
        greaterThanOrEqualTo(4.5),
        reason: 'Filled button text',
      );
      expect(theme.brightness, brightness);
      expect(theme.inputDecorationTheme.fillColor, palette.surface);
      expect(theme.scaffoldBackgroundColor, palette.paper);
      expect({
        palette.diagnostics,
        palette.modelDetails,
        palette.modelChooser,
      }, hasLength(3));
    });
  }

  test(
    'dark surfaces are intentionally dark, not a light palette with inverted text',
    () {
      expect(StudioPalette.dark.paper.computeLuminance(), lessThan(.03));
      expect(StudioPalette.dark.surface.computeLuminance(), lessThan(.05));
      expect(StudioPalette.light.paper.computeLuminance(), greaterThan(.85));
      expect(StudioPalette.dark.ink.computeLuminance(), greaterThan(.8));
    },
  );
}
