import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'brand_artwork.dart';

/// The soft W wraps a lavender module. Decorative beside the product name.
class WfformMark extends StatelessWidget {
  const WfformMark({super.key, this.size = 34});

  final double size;

  @override
  Widget build(BuildContext context) => _artwork(context, size, null, null);
}

enum BrandGlyph {
  models,
  chat,
  history,
  documents,
  settings,
  diagnostics,
  context,
  chats,
  drafts,
  archived,
}

/// Companion artwork. Its surrounding control supplies the accessible label.
class BrandIcon extends StatelessWidget {
  const BrandIcon(this.glyph, {super.key, this.size = 24, this.color});

  final BrandGlyph glyph;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => _artwork(context, size, glyph, color);
}

Widget _artwork(
  BuildContext context,
  double size,
  BrandGlyph? glyph,
  Color? color,
) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final iconTheme = IconTheme.of(context);
  final inherited = glyph == null ? null : iconTheme.color;
  final ink = color ?? inherited ?? Color(dark ? brandPaper : brandInk);
  // Inverted controls use the matching accent variant while their interiors
  // remain transparent, allowing the actual button or page surface to show.
  final lightInk =
      ThemeData.estimateBrightnessForColor(ink) == Brightness.light;
  // Respect both disabled button foreground alpha and IconTheme opacity.
  final opacity = (iconTheme.opacity ?? 1) * ink.a;
  return ExcludeSemantics(
    child: Opacity(
      opacity: opacity,
      child: CustomPaint(
        size: Size.square(size),
        painter: _BrandPainter(
          glyph,
          ink.withValues(alpha: 1),
          Color(lightInk ? brandDarkLavender : brandLavender),
        ),
      ),
    ),
  );
}

class _BrandPainter extends CustomPainter {
  const _BrandPainter(this.glyph, this.ink, this.lavender);

  final BrandGlyph? glyph;
  final Color ink, lavender;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    // Knock out overlapped rear artwork inside this isolated layer. Clearing
    // a front card/bubble never erases the widget's real background.
    canvas.saveLayer(const Rect.fromLTWH(0, 0, 100, 100), Paint());
    final outline = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = (160 / size.width).clamp(
        glyph == null ? wrapperStroke : 5,
        10,
      )
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    void shape(Path path, [Color? fill]) {
      canvas.drawPath(path, Paint()..blendMode = BlendMode.clear);
      if (fill != null) canvas.drawPath(path, Paint()..color = fill);
      canvas.drawPath(path, outline);
    }

    Path rounded(double x, double y, double w, double h, double r) => Path()
      ..addRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r)),
      );

    switch (glyph) {
      case null:
        final wrapper = Path()..moveTo(20, 19);
        for (final c in wrapperCurves) {
          wrapper.cubicTo(c[0], c[1], c[2], c[3], c[4], c[5]);
        }
        wrapper.close();
        shape(wrapper);
        canvas.drawPath(
          rounded(
            wrapperCore.left,
            wrapperCore.top,
            wrapperCore.width,
            wrapperCore.height,
            wrapperCoreRadius,
          ),
          Paint()..color = lavender,
        );
      case BrandGlyph.models:
        canvas.save();
        canvas.translate(33, 54);
        canvas.rotate(-.32);
        shape(rounded(-20, -25, 35, 51, 9));
        canvas.restore();
        canvas.save();
        canvas.translate(68, 54);
        canvas.rotate(.32);
        shape(rounded(-15, -25, 35, 51, 9));
        canvas.restore();
        shape(rounded(34, 18, 33, 53, 9), lavender);
      case BrandGlyph.chat:
        final back = Path()
          ..moveTo(49, 32)
          ..lineTo(72, 32)
          ..quadraticBezierTo(89, 32, 89, 49)
          ..lineTo(89, 61)
          ..quadraticBezierTo(89, 72, 79, 74)
          ..lineTo(79, 84)
          ..lineTo(65, 75)
          ..lineTo(50, 75)
          ..quadraticBezierTo(34, 75, 34, 60)
          ..lineTo(34, 48)
          ..quadraticBezierTo(34, 32, 49, 32)
          ..close();
        shape(back, lavender);
        final front = Path()
          ..moveTo(28, 21)
          ..lineTo(52, 21)
          ..quadraticBezierTo(68, 21, 68, 37)
          ..lineTo(68, 53)
          ..quadraticBezierTo(68, 66, 53, 66)
          ..lineTo(37, 66)
          ..lineTo(23, 76)
          ..lineTo(23, 66)
          ..quadraticBezierTo(12, 64, 12, 52)
          ..lineTo(12, 37)
          ..quadraticBezierTo(12, 21, 28, 21)
          ..close();
        shape(front);
      case BrandGlyph.history:
        final arc = Path()
          ..moveTo(17, 60)
          ..cubicTo(26, 99, 82, 92, 85, 54)
          ..cubicTo(89, 16, 38, 1, 20, 33);
        canvas.drawPath(arc, outline);
        final arrow = Path()
          ..moveTo(16, 26)
          ..lineTo(19, 39)
          ..lineTo(30, 31)
          ..close();
        shape(arrow, ink);
        canvas.drawPath(
          Path()
            ..moveTo(51, 29)
            ..lineTo(51, 51)
            ..lineTo(65, 63),
          outline,
        );
        canvas.drawCircle(const Offset(51, 51), 7.5, Paint()..color = lavender);
      case BrandGlyph.documents:
        final back = Path()
          ..moveTo(48, 16)
          ..lineTo(68, 16)
          ..lineTo(85, 32)
          ..lineTo(85, 68)
          ..quadraticBezierTo(85, 78, 75, 78)
          ..lineTo(48, 78)
          ..quadraticBezierTo(39, 78, 39, 69)
          ..lineTo(39, 26)
          ..quadraticBezierTo(39, 16, 48, 16)
          ..close();
        shape(back, lavender);
        canvas.drawPath(
          Path()
            ..moveTo(67, 18)
            ..lineTo(67, 30)
            ..quadraticBezierTo(67, 35, 73, 35)
            ..lineTo(84, 35),
          outline,
        );
        shape(rounded(14, 28, 49, 57, 10));
        for (final y in [49.0, 64.0]) {
          canvas.drawLine(Offset(27, y), Offset(50, y), outline);
        }
      case BrandGlyph.settings:
        final vertices = <Offset>[
          for (var i = 0; i < 24; i++)
            Offset(
              50 + (i % 4 < 2 ? 38 : 29) * math.cos(i * math.pi / 12),
              50 + (i % 4 < 2 ? 38 : 29) * math.sin(i * math.pi / 12),
            ),
        ];
        final first = (vertices.last + vertices.first) / 2;
        final gear = Path()..moveTo(first.dx, first.dy);
        for (var i = 0; i < vertices.length; i++) {
          final point = vertices[i];
          final end = (point + vertices[(i + 1) % vertices.length]) / 2;
          gear.quadraticBezierTo(point.dx, point.dy, end.dx, end.dy);
        }
        shape(gear..close());
        // Preserve a visible center after the minimum small-size outline.
        final hubRadius = (240 / size.width).clamp(11.0, 15.0);
        canvas.drawCircle(
          const Offset(50, 50),
          hubRadius,
          Paint()..color = lavender,
        );
        canvas.drawCircle(const Offset(50, 50), hubRadius, outline);
      case BrandGlyph.diagnostics:
        shape(rounded(12, 18, 76, 53, 10));
        canvas.drawPath(
          Path()
            ..moveTo(22, 47)
            ..lineTo(34, 47)
            ..lineTo(42, 33)
            ..lineTo(54, 59)
            ..lineTo(64, 43)
            ..lineTo(77, 43),
          outline,
        );
        canvas.drawCircle(
          const Offset(77, 43),
          (112 / size.width).clamp(5.0, 7.0),
          Paint()..color = lavender,
        );
        canvas.drawLine(const Offset(50, 72), const Offset(50, 83), outline);
        canvas.drawLine(const Offset(33, 84), const Offset(67, 84), outline);
      case BrandGlyph.context:
        for (final x in [25.0, 50.0, 75.0]) {
          canvas.drawLine(Offset(x, 18), Offset(x, 82), outline);
        }
        final knobWidth = (384 / size.width).clamp(16.0, 24.0);
        final knobHeight = (416 / size.width).clamp(20.0, 26.0);
        Path knob(double x, double y) => rounded(
          x - knobWidth / 2,
          y - knobHeight / 2,
          knobWidth,
          knobHeight,
          6,
        );
        shape(knob(25, 39), lavender);
        shape(knob(50, 66));
        shape(knob(75, 34));
      case BrandGlyph.chats:
        // Three offset cards communicate a collection, distinct from Chat's
        // two conversational speech bubbles.
        shape(rounded(32, 16, 54, 48, 9));
        shape(rounded(24, 24, 54, 48, 9));
        final front = Path()
          ..moveTo(25, 32)
          ..lineTo(60, 32)
          ..quadraticBezierTo(69, 32, 69, 41)
          ..lineTo(69, 69)
          ..quadraticBezierTo(69, 79, 59, 79)
          ..lineTo(35, 79)
          ..lineTo(22, 87)
          ..lineTo(22, 78)
          ..quadraticBezierTo(15, 76, 15, 68)
          ..lineTo(15, 42)
          ..quadraticBezierTo(15, 32, 25, 32)
          ..close();
        shape(front);
        for (final x in [26.0, 42.0, 58.0]) {
          canvas.drawCircle(
            Offset(x, 55),
            (112 / size.width).clamp(3.5, 7.0),
            Paint()..color = lavender,
          );
        }
      case BrandGlyph.drafts:
        shape(rounded(19, 15, 53, 70, 10));
        canvas.drawLine(const Offset(31, 32), const Offset(55, 32), outline);
        canvas.drawLine(const Offset(31, 46), const Offset(46, 46), outline);
        final pencil = Path()
          ..moveTo(44, 70)
          ..lineTo(70, 40)
          ..quadraticBezierTo(75, 35, 80, 40)
          ..lineTo(84, 44)
          ..quadraticBezierTo(88, 48, 84, 53)
          ..lineTo(57, 82)
          ..lineTo(41, 87)
          ..close();
        shape(pencil, lavender);
        final tip = Path()
          ..moveTo(44, 70)
          ..lineTo(57, 82)
          ..lineTo(41, 87)
          ..close();
        canvas.drawPath(tip, Paint()..color = lavender);
        canvas.drawPath(tip, outline);
        canvas.drawLine(const Offset(69, 43), const Offset(81, 55), outline);
      case BrandGlyph.archived:
        shape(rounded(18, 35, 64, 48, 9));
        shape(rounded(13, 20, 74, 20, 7));
        final handleWidth = (512 / size.width).clamp(24.0, 32.0);
        final handleHeight = (352 / size.width).clamp(11.0, 22.0);
        shape(
          rounded(
            50 - handleWidth / 2,
            57.5 - handleHeight / 2,
            handleWidth,
            handleHeight,
            5,
          ),
          lavender,
        );
    }
    canvas.restore(); // isolated artwork layer
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BrandPainter oldDelegate) =>
      oldDelegate.glyph != glyph ||
      oldDelegate.ink != ink ||
      oldDelegate.lavender != lavender;
}
