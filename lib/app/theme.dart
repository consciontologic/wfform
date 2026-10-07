import 'package:flutter/material.dart';

/// Baseline constants retained for callers that intentionally need a fixed color.
/// Application surfaces should resolve [StudioPalette.of] instead.
abstract final class StudioColors {
  static const ink = Color(0xFF292F2D);
  static const paper = Color(0xFFF8F6F0);
  static const cream = Color(0xFFF0EEE6);
  static const sage = Color(0xFFDFE8D8);
  static const peach = Color(0xFFF1DFD2);
  static const lilac = Color(0xFFE7E2EC);
  static const muted = Color(0xFF59645D);
}

@immutable
class StudioPalette extends ThemeExtension<StudioPalette> {
  const StudioPalette({
    required this.ink,
    required this.paper,
    required this.cream,
    required this.surface,
    required this.sage,
    required this.peach,
    required this.lilac,
    required this.muted,
    required this.border,
    required this.diagnostics,
    required this.modelDetails,
    required this.modelChooser,
    required this.shadow,
  });

  final Color ink, paper, cream, surface, sage, peach, lilac, muted, border;
  final Color diagnostics, modelDetails, modelChooser, shadow;

  static const light = StudioPalette(
    ink: Color(0xFF29243B),
    paper: Color(0xFFF8F5FC),
    cream: Color(0xFFEEE8F5),
    surface: Color(0xFFFFFFFF),
    sage: Color(0xFFDBEFE5),
    peach: Color(0xFFF9E0D3),
    lilac: Color(0xFFE9DFF7),
    muted: Color(0xFF615970),
    border: Color(0xFF756981),
    diagnostics: Color(0xFFEDB075),
    modelDetails: Color(0xFFBD9AE8),
    modelChooser: Color(0xFF80C9AC),
    shadow: Color(0xFFCFC5DB),
  );
  static const dark = StudioPalette(
    ink: Color(0xFFF4EDFF),
    paper: Color(0xFF191722),
    cream: Color(0xFF242130),
    surface: Color(0xFF2C2839),
    sage: Color(0xFF263F37),
    peach: Color(0xFF4A302D),
    lilac: Color(0xFF3D304E),
    muted: Color(0xFFCBC0DB),
    border: Color(0xFF9F8EAF),
    diagnostics: Color(0xFF764629),
    modelDetails: Color(0xFF593679),
    modelChooser: Color(0xFF215D49),
    shadow: Color(0xFF0C0A12),
  );

  static StudioPalette of(BuildContext context) =>
      Theme.of(context).extension<StudioPalette>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);

  @override
  StudioPalette copyWith({
    Color? ink,
    Color? paper,
    Color? cream,
    Color? surface,
    Color? sage,
    Color? peach,
    Color? lilac,
    Color? muted,
    Color? border,
    Color? diagnostics,
    Color? modelDetails,
    Color? modelChooser,
    Color? shadow,
  }) => StudioPalette(
    ink: ink ?? this.ink,
    paper: paper ?? this.paper,
    cream: cream ?? this.cream,
    surface: surface ?? this.surface,
    sage: sage ?? this.sage,
    peach: peach ?? this.peach,
    lilac: lilac ?? this.lilac,
    muted: muted ?? this.muted,
    border: border ?? this.border,
    diagnostics: diagnostics ?? this.diagnostics,
    modelDetails: modelDetails ?? this.modelDetails,
    modelChooser: modelChooser ?? this.modelChooser,
    shadow: shadow ?? this.shadow,
  );

  @override
  StudioPalette lerp(covariant StudioPalette? other, double t) {
    if (other == null) return this;
    return StudioPalette(
      ink: Color.lerp(ink, other.ink, t)!,
      paper: Color.lerp(paper, other.paper, t)!,
      cream: Color.lerp(cream, other.cream, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      sage: Color.lerp(sage, other.sage, t)!,
      peach: Color.lerp(peach, other.peach, t)!,
      lilac: Color.lerp(lilac, other.lilac, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      border: Color.lerp(border, other.border, t)!,
      diagnostics: Color.lerp(diagnostics, other.diagnostics, t)!,
      modelDetails: Color.lerp(modelDetails, other.modelDetails, t)!,
      modelChooser: Color.lerp(modelChooser, other.modelChooser, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}

ThemeData studioTheme({Brightness brightness = Brightness.light}) {
  final dark = brightness == Brightness.dark;
  final p = dark ? StudioPalette.dark : StudioPalette.light;
  final primary = dark ? const Color(0xFFD4B6FA) : const Color(0xFF65428B);
  final onPrimary = dark ? const Color(0xFF29153E) : Colors.white;
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    extensions: [p],
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF785398),
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      secondary: dark ? const Color(0xFFB1DAC7) : const Color(0xFF426D5B),
      surface: p.paper,
      onSurface: p.ink,
      onSurfaceVariant: p.muted,
      outline: p.border,
      error: dark ? const Color(0xFFFFB4A6) : const Color(0xFF9F352E),
    ),
    scaffoldBackgroundColor: p.paper,
    canvasColor: p.paper,
    fontFamily: 'Roboto',
    textTheme: TextTheme(
      headlineLarge: TextStyle(
        color: p.ink,
        fontSize: 44,
        fontWeight: FontWeight.w700,
        height: 1.12,
        letterSpacing: -1.8,
      ),
      headlineMedium: TextStyle(
        color: p.ink,
        fontSize: 30,
        fontWeight: FontWeight.w700,
        height: 1.15,
        letterSpacing: -.8,
      ),
      titleLarge: TextStyle(
        color: p.ink,
        fontSize: 21,
        fontWeight: FontWeight.w700,
        height: 1.25,
      ),
      titleMedium: TextStyle(
        color: p.ink,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.4,
      ),
      bodyLarge: TextStyle(color: p.ink, fontSize: 16, height: 1.5),
      bodyMedium: TextStyle(color: p.ink, fontSize: 14, height: 1.45),
      labelLarge: TextStyle(
        color: p.ink,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    ),
    dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      contentPadding: const EdgeInsets.all(14),
      labelStyle: TextStyle(color: p.muted),
      hintStyle: TextStyle(color: p.muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(5),
        borderSide: BorderSide(color: p.border, width: 1.3),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(5),
        borderSide: BorderSide(color: p.border, width: 1.3),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(5),
        borderSide: BorderSide(color: primary, width: 2.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.ink,
        minimumSize: const Size(48, 48),
        side: BorderSide(color: p.border, width: 1.3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: p.ink),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: p.ink,
        minimumSize: const Size(48, 48),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
      preferBelow: true,
      decoration: BoxDecoration(
        color: p.ink,
        borderRadius: BorderRadius.circular(5),
      ),
      textStyle: TextStyle(color: p.paper, fontSize: 13),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.paper,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: p.border, width: 2),
      ),
    ),
  );
}
