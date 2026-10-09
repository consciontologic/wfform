import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/presentation/brand_artwork.dart';
import 'package:wfform/presentation/brand_mark.dart';

void main() {
  testWidgets('wrapper and overlapping companion interiors stay transparent', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      for (final (widget, interior) in <(Widget, Offset)>[
        (const WfformMark(size: 100), const Offset(20, 32)),
        (const BrandIcon(BrandGlyph.models, size: 100), const Offset(20, 55)),
        (const BrandIcon(BrandGlyph.chat, size: 100), const Offset(45, 43)),
        (const BrandIcon(BrandGlyph.history, size: 100), const Offset(30, 55)),
        (
          const BrandIcon(BrandGlyph.documents, size: 100),
          const Offset(45, 43),
        ),
        (const BrandIcon(BrandGlyph.settings, size: 100), const Offset(50, 28)),
        (
          const BrandIcon(BrandGlyph.diagnostics, size: 100),
          const Offset(24, 28),
        ),
        (const BrandIcon(BrandGlyph.context, size: 100), const Offset(50, 64)),
        (const BrandIcon(BrandGlyph.chats, size: 100), const Offset(48, 44)),
        (const BrandIcon(BrandGlyph.drafts, size: 100), const Offset(33, 62)),
        (const BrandIcon(BrandGlyph.archived, size: 100), const Offset(25, 70)),
      ]) {
        final data = await _render(tester, widget, brightness);
        expect(
          _alpha(data, interior),
          0,
          reason: '$widget $brightness has no opaque interior',
        );
      }
    }
  });

  testWidgets(
    'every symbol has legible theme variants without a background tile',
    (tester) async {
      for (final brightness in Brightness.values) {
        final ink = brightness == Brightness.dark ? brandPaper : brandInk;
        final accent = brightness == Brightness.dark
            ? brandDarkLavender
            : brandLavender;
        for (final glyph in BrandGlyph.values) {
          final data = await _render(
            tester,
            BrandIcon(glyph, size: 100),
            brightness,
          );
          expect(_alpha(data, const Offset(1, 1)), 0);
          expect(_alpha(data, const Offset(98, 98)), 0);
          expect(
            _opaqueCount(data, ink),
            greaterThan(100),
            reason: '$glyph $brightness visible outline',
          );
          expect(
            _opaqueCount(data, accent),
            greaterThan(30),
            reason: '$glyph $brightness restrained accent',
          );
          // Neither variant paints the opposite neutral color as an interior.
          expect(
            _opaqueCount(
              data,
              brightness == Brightness.dark ? brandInk : brandPaper,
            ),
            0,
          );
        }
      }
    },
  );

  testWidgets(
    'transparent front shapes mask rear strokes and preserve host surfaces',
    (tester) async {
      for (final background in [
        const Color(brandPaper),
        const Color(0xff65428b),
        const Color(brandInk),
      ]) {
        for (final (glyph, interior) in [
          (BrandGlyph.chat, const Offset(35, 43)),
          (BrandGlyph.documents, const Offset(40, 43)),
          (BrandGlyph.chats, const Offset(32, 44)),
          (BrandGlyph.context, const Offset(50, 64)),
        ]) {
          final data = await _render(
            tester,
            ColoredBox(color: background, child: BrandIcon(glyph, size: 100)),
            Brightness.light,
          );
          expect(
            _rgb(data, interior),
            background.toARGB32(),
            reason: '$glyph keeps host $background through its front shape',
          );
          expect(
            _alpha(data, interior),
            255,
            reason: 'Knockout never erases the host',
          );
        }
      }
    },
  );

  testWidgets(
    'inverted foregrounds choose matching accents with transparent interiors',
    (tester) async {
      for (final (brightness, foreground, accent) in [
        (Brightness.light, Colors.white, brandDarkLavender),
        (Brightness.dark, const Color(0xff29153e), brandLavender),
      ]) {
        final data = await _render(
          tester,
          const BrandIcon(BrandGlyph.chat, size: 100),
          brightness,
          foreground: foreground,
        );
        expect(_alpha(data, const Offset(45, 43)), 0);
        expect(_opaqueCount(data, foreground.toARGB32()), greaterThan(100));
        expect(_opaqueCount(data, accent), greaterThan(100));
      }
    },
  );
}

int _rgb(ByteData data, Offset p) {
  final offset = (p.dy.toInt() * 100 + p.dx.toInt()) * 4;
  return 0xff000000 |
      data.getUint8(offset) << 16 |
      data.getUint8(offset + 1) << 8 |
      data.getUint8(offset + 2);
}

int _opaqueCount(ByteData data, int color) {
  var count = 0;
  for (var y = 0; y < 100; y++) {
    for (var x = 0; x < 100; x++) {
      final point = Offset(x.toDouble(), y.toDouble());
      if (_alpha(data, point) == 255 && _rgb(data, point) == color) count++;
    }
  }
  return count;
}

Future<ByteData> _render(
  WidgetTester tester,
  Widget widget,
  Brightness brightness, {
  Color? foreground,
}) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Center(
        child: IconTheme(
          data: IconThemeData(
            color:
                foreground ??
                Color(brightness == Brightness.dark ? brandPaper : brandInk),
            opacity: 1,
          ),
          child: RepaintBoundary(
            key: key,
            child: SizedBox.square(dimension: 100, child: widget),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await tester.runAsync(() => boundary.toImage());
  final bytes = await tester.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
  );
  image!.dispose();
  return bytes!;
}

int _alpha(ByteData data, Offset p) =>
    data.getUint8((p.dy.toInt() * 100 + p.dx.toInt()) * 4 + 3);
