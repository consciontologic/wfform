import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'brand_artwork.dart';

/// An open folded band cradles two linked nodes. Decorative beside the name.
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
    // Knockouts belong to the artwork layer, never the actual host surface.
    canvas.saveLayer(const Rect.fromLTWH(0, 0, 100, 100), Paint());
    final outline = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = (150 / size.width).clamp(6.0, 9.4)
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    void stroke(Path path) => canvas.drawPath(path, outline);
    void node(Offset point, [double radius = 7]) => canvas.drawCircle(
      point,
      math.max(radius, (128 / size.width).clamp(7.0, 8.0)),
      Paint()..color = lavender,
    );
    void line(Offset from, Offset to) => canvas.drawLine(from, to, outline);
    void ring(Offset center, double radius) {
      canvas.drawCircle(center, radius, Paint()..blendMode = BlendMode.clear);
      canvas.drawCircle(center, radius, outline);
    }

    Path bubble(double x, double y, double w, double h) => Path()
      ..moveTo(x + w * .57, y)
      ..lineTo(x + 15, y)
      ..quadraticBezierTo(x, y, x, y + 15)
      ..lineTo(x, y + h - 15)
      ..quadraticBezierTo(x, y + h, x + 12, y + h)
      ..lineTo(x + 12, y + h + 10)
      ..quadraticBezierTo(x + 12, y + h + 13, x + 17, y + h + 9)
      ..lineTo(x + 29, y + h)
      ..lineTo(x + w - 15, y + h)
      ..quadraticBezierTo(x + w, y + h, x + w, y + h - 15)
      ..lineTo(x + w, y + 23);

    switch (glyph) {
      case null:
        for (final band in cradleBands) {
          final contour = Path()..moveTo(band.x, band.y);
          for (final c in band.curves) {
            contour.cubicTo(c[0], c[1], c[2], c[3], c[4], c[5]);
          }
          canvas.drawPath(contour..close(), Paint()..color = ink);
        }
        final first = cradleNodes.first;
        final second = cradleNodes.last;
        canvas.drawLine(
          Offset(first.x, first.y),
          Offset(second.x, second.y),
          Paint()
            ..color = lavender
            ..strokeWidth = cradleLinkWidth
            ..strokeCap = StrokeCap.round,
        );
        for (final point in cradleNodes) {
          canvas.drawCircle(
            Offset(point.x, point.y),
            point.radius,
            Paint()..color = lavender,
          );
        }
      case BrandGlyph.models:
        // Nested open cards, with the same rising entry and rounded cradle base.
        stroke(
          Path()
            ..moveTo(43, 16)
            ..lineTo(24, 23)
            ..quadraticBezierTo(14, 27, 14, 38)
            ..lineTo(14, 65)
            ..quadraticBezierTo(14, 78, 27, 78),
        );
        stroke(
          Path()
            ..moveTo(55, 22)
            ..lineTo(38, 28)
            ..quadraticBezierTo(28, 32, 28, 43)
            ..lineTo(28, 70)
            ..quadraticBezierTo(28, 84, 43, 84)
            ..lineTo(70, 84)
            ..quadraticBezierTo(85, 84, 85, 69)
            ..lineTo(85, 45),
        );
        line(const Offset(44, 55), const Offset(65, 55));
        node(const Offset(72, 30));
      case BrandGlyph.chat:
        stroke(bubble(13, 22, 73, 51));
        line(const Offset(34, 47), const Offset(58, 47));
        node(const Offset(77, 22));
      case BrandGlyph.history:
        stroke(
          Path()
            ..moveTo(45, 15)
            ..cubicTo(22, 15, 10, 34, 13, 56)
            ..cubicTo(16, 81, 42, 91, 64, 81)
            ..cubicTo(80, 74, 87, 60, 85, 44),
        );
        stroke(
          Path()
            ..moveTo(47, 32)
            ..lineTo(47, 53)
            ..lineTo(64, 61),
        );
        node(const Offset(76, 25));
      case BrandGlyph.documents:
        stroke(
          Path()
            ..moveTo(51, 15)
            ..lineTo(32, 15)
            ..quadraticBezierTo(19, 15, 19, 29)
            ..lineTo(19, 72)
            ..quadraticBezierTo(19, 85, 33, 85)
            ..lineTo(67, 85)
            ..quadraticBezierTo(81, 85, 81, 71)
            ..lineTo(81, 45),
        );
        stroke(
          Path()
            ..moveTo(52, 17)
            ..lineTo(52, 28)
            ..quadraticBezierTo(52, 39, 64, 39)
            ..lineTo(78, 39),
        );
        line(const Offset(33, 53), const Offset(63, 53));
        line(const Offset(33, 67), const Offset(54, 67));
        node(const Offset(73, 22));
      case BrandGlyph.settings:
        // A soft, open gear: the upper-right node occupies the deliberate break.
        final vertices = <Offset>[
          for (var i = 0; i <= 26; i++)
            Offset(
              50 +
                  (i % 4 < 2 ? 36 : 29) *
                      math.cos((-20 + i * 12) * math.pi / 180),
              50 +
                  (i % 4 < 2 ? 36 : 29) *
                      math.sin((-20 + i * 12) * math.pi / 180),
            ),
        ];
        final gear = Path()..moveTo(vertices.first.dx, vertices.first.dy);
        for (var i = 1; i < vertices.length - 1; i++) {
          final point = vertices[i];
          final end = (point + vertices[i + 1]) / 2;
          gear.quadraticBezierTo(point.dx, point.dy, end.dx, end.dy);
        }
        stroke(gear);
        ring(const Offset(50, 50), 11);
        node(const Offset(73, 23));
      case BrandGlyph.diagnostics:
        stroke(
          Path()
            ..moveTo(53, 18)
            ..lineTo(28, 18)
            ..quadraticBezierTo(13, 18, 13, 33)
            ..lineTo(13, 58)
            ..quadraticBezierTo(13, 72, 28, 72)
            ..lineTo(71, 72)
            ..quadraticBezierTo(86, 72, 86, 58)
            ..lineTo(86, 43),
        );
        stroke(
          Path()
            ..moveTo(26, 47)
            ..lineTo(36, 47)
            ..lineTo(44, 34)
            ..lineTo(55, 58)
            ..lineTo(65, 43)
            ..lineTo(75, 43),
        );
        line(const Offset(50, 73), const Offset(50, 84));
        line(const Offset(34, 85), const Offset(66, 85));
        node(const Offset(75, 22));
      case BrandGlyph.context:
        for (final y in [27.0, 50.0, 74.0]) {
          line(Offset(18, y), Offset(82, y));
        }
        ring(const Offset(35, 27), 9);
        ring(const Offset(43, 74), 9);
        canvas.drawCircle(
          const Offset(64, 50),
          11,
          Paint()..blendMode = BlendMode.clear,
        );
        node(const Offset(64, 50), 10);
      case BrandGlyph.chats:
        stroke(
          Path()
            ..moveTo(57, 15)
            ..lineTo(36, 15)
            ..quadraticBezierTo(22, 15, 22, 27),
        );
        stroke(
          Path()
            ..moveTo(87, 41)
            ..lineTo(87, 57)
            ..quadraticBezierTo(87, 71, 76, 73),
        );
        stroke(bubble(12, 29, 63, 44));
        for (final x in [29.0, 43.0, 57.0]) {
          canvas.drawCircle(Offset(x, 50), 3.5, Paint()..color = ink);
        }
        node(const Offset(77, 22));
      case BrandGlyph.drafts:
        stroke(
          Path()
            ..moveTo(50, 16)
            ..lineTo(30, 16)
            ..quadraticBezierTo(17, 16, 17, 30)
            ..lineTo(17, 71)
            ..quadraticBezierTo(17, 85, 31, 85)
            ..lineTo(61, 85)
            ..quadraticBezierTo(74, 85, 77, 73),
        );
        line(const Offset(30, 35), const Offset(50, 35));
        line(const Offset(30, 49), const Offset(43, 49));
        stroke(
          Path()
            ..moveTo(47, 62)
            ..lineTo(72, 34)
            ..quadraticBezierTo(76, 30, 80, 34)
            ..lineTo(85, 39)
            ..quadraticBezierTo(89, 43, 84, 48)
            ..lineTo(59, 74)
            ..lineTo(44, 78)
            ..lineTo(47, 62),
        );
        line(const Offset(49, 64), const Offset(58, 72));
        node(const Offset(75, 20));
      case BrandGlyph.archived:
        stroke(
          Path()
            ..moveTo(22, 46)
            ..lineTo(22, 70)
            ..quadraticBezierTo(22, 84, 37, 84)
            ..lineTo(65, 84)
            ..quadraticBezierTo(81, 84, 81, 69)
            ..lineTo(81, 46),
        );
        stroke(
          Path()
            ..moveTo(51, 20)
            ..lineTo(25, 20)
            ..quadraticBezierTo(14, 20, 14, 31)
            ..quadraticBezierTo(14, 41, 25, 41)
            ..lineTo(87, 41),
        );
        line(const Offset(39, 58), const Offset(63, 58));
        node(const Offset(76, 22));
    }
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BrandPainter oldDelegate) =>
      oldDelegate.glyph != glyph ||
      oldDelegate.ink != ink ||
      oldDelegate.lavender != lavender;
}
