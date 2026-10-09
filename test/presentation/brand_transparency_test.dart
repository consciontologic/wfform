import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/presentation/brand_artwork.dart';
import 'package:wfform/presentation/brand_mark.dart';

import '../../tool/icons.dart' as icons;

void main() {
  testWidgets('open cradle and companion interiors stay transparent', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      for (final (widget, interior) in <(Widget, Offset)>[
        (const WfformMark(size: 100), const Offset(55, 64)),
        (const BrandIcon(BrandGlyph.models, size: 100), const Offset(20, 55)),
        (const BrandIcon(BrandGlyph.chat, size: 100), const Offset(45, 57)),
        (const BrandIcon(BrandGlyph.history, size: 100), const Offset(30, 55)),
        (
          const BrandIcon(BrandGlyph.documents, size: 100),
          const Offset(45, 43),
        ),
        (const BrandIcon(BrandGlyph.settings, size: 100), const Offset(35, 48)),
        (
          const BrandIcon(BrandGlyph.diagnostics, size: 100),
          const Offset(24, 28),
        ),
        (const BrandIcon(BrandGlyph.context, size: 100), const Offset(43, 74)),
        (const BrandIcon(BrandGlyph.chats, size: 100), const Offset(48, 44)),
        (const BrandIcon(BrandGlyph.drafts, size: 100), const Offset(33, 62)),
        (const BrandIcon(BrandGlyph.archived, size: 100), const Offset(35, 70)),
      ]) {
        final data = await _render(tester, widget, brightness);
        expect(
          _alpha(data, interior),
          0,
          reason:
              '${widget is BrandIcon ? widget.glyph : 'main'} '
              '$brightness has no opaque interior',
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

  testWidgets('open companion interiors and knockouts preserve host surfaces', (
    tester,
  ) async {
    for (final background in [
      const Color(brandPaper),
      const Color(0xff65428b),
      const Color(brandInk),
    ]) {
      for (final (glyph, interior) in [
        (BrandGlyph.chat, const Offset(35, 43)),
        (BrandGlyph.documents, const Offset(40, 43)),
        (BrandGlyph.chats, const Offset(32, 44)),
        (BrandGlyph.context, const Offset(43, 74)),
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
  });

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
        expect(_alpha(data, const Offset(45, 57)), 0);
        expect(_opaqueCount(data, foreground.toARGB32()), greaterThan(100));
        expect(_opaqueCount(data, accent), greaterThan(100));
      }
    },
  );

  testWidgets('16 pixel cradle retains an open notch and linked AI nodes', (
    tester,
  ) async {
    const size = 16;
    for (final brightness in Brightness.values) {
      final pixels = await _render(
        tester,
        const WfformMark(size: 16),
        brightness,
        size: size,
      );
      final accent = brightness == Brightness.dark
          ? brandDarkLavender
          : brandLavender;
      // The broad upper opening and clear space below the seed survive even
      // when the whole mark is rendered at a browser tab's smallest size.
      for (final p in [const Offset(10, 2), const Offset(9, 10)]) {
        expect(_alpha(pixels, p, size: size), 0);
      }
      for (final p in [const Offset(6, 8), const Offset(10, 5)]) {
        expect(_rgb(pixels, p, size: size), accent);
        expect(_alpha(pixels, p, size: size), 255);
      }
      // A connected accent component proves the thin link still joins both
      // nodes, rather than degrading into two unrelated favicon dots.
      final remaining = <(int, int)>{
        for (var y = 0; y < size; y++)
          for (var x = 0; x < size; x++)
            if (_alpha(
                      pixels,
                      Offset(x.toDouble(), y.toDouble()),
                      size: size,
                    ) >=
                    64 &&
                _hasPremultipliedColor(
                  pixels,
                  Offset(x.toDouble(), y.toDouble()),
                  accent,
                  size: size,
                ))
              (x, y),
      };
      final connected = <(int, int)>{(6, 8)};
      final pending = <(int, int)>[(6, 8)];
      while (pending.isNotEmpty) {
        final (x, y) = pending.removeLast();
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final next = (x + dx, y + dy);
            if (remaining.remove(next) && connected.add(next)) {
              pending.add(next);
            }
          }
        }
      }
      expect(connected, contains((10, 5)));
    }
  });

  testWidgets('Flutter and exported cradle silhouettes share their geometry', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      for (final size in [16, 32, 100]) {
        final flutter = await _render(
          tester,
          WfformMark(size: size.toDouble()),
          brightness,
          size: size,
        );
        final exported = await tester.runAsync(() async {
          final codec = await ui.instantiateImageCodec(
            Uint8List.fromList(
              icons.iconPng(size, dark: brightness == Brightness.dark),
            ),
          );
          final frame = await codec.getNextFrame();
          final data = await frame.image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          frame.image.dispose();
          codec.dispose();
          return data!;
        });
        var alphaDifference = 0;
        var interiorPixels = 0;
        for (var offset = 0; offset < flutter.lengthInBytes; offset += 4) {
          alphaDifference +=
              (flutter.getUint8(offset + 3) - exported!.getUint8(offset + 3))
                  .abs();
          if (flutter.getUint8(offset + 3) == 255 &&
              exported.getUint8(offset + 3) == 255) {
            interiorPixels++;
            for (var channel = 0; channel < 3; channel++) {
              expect(
                flutter.getUint8(offset + channel),
                exported.getUint8(offset + channel),
                reason: 'Same band and seed colors at $size / $brightness',
              );
            }
          }
        }
        expect(interiorPixels, greaterThan(size));
        // Skia and the deterministic supersampler antialias edges differently;
        // their total coverage must still agree within 2% of the canvas area.
        expect(
          alphaDifference / (255 * size * size),
          lessThan(.02),
          reason: 'Matching cradle silhouette at $size / $brightness',
        );
      }
    }
  });
}

int _rgb(ByteData data, Offset p, {int size = 100}) {
  final offset = (p.dy.toInt() * size + p.dx.toInt()) * 4;
  return 0xff000000 |
      data.getUint8(offset) << 16 |
      data.getUint8(offset + 1) << 8 |
      data.getUint8(offset + 2);
}

bool _hasPremultipliedColor(
  ByteData data,
  Offset p,
  int color, {
  required int size,
}) {
  final offset = (p.dy.toInt() * size + p.dx.toInt()) * 4;
  final alpha = data.getUint8(offset + 3);
  for (var channel = 0; channel < 3; channel++) {
    final expected = (color >> (16 - channel * 8)) & 0xff;
    // rawRgba stores premultiplied channels, including the antialiased link.
    final premultiplied = (expected * alpha / 255).round();
    if ((data.getUint8(offset + channel) - premultiplied).abs() > 1) {
      return false;
    }
  }
  return true;
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
  int size = 100,
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
            child: SizedBox.square(dimension: size.toDouble(), child: widget),
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

int _alpha(ByteData data, Offset p, {int size = 100}) =>
    data.getUint8((p.dy.toInt() * size + p.dx.toInt()) * 4 + 3);
