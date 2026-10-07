import 'package:flutter/material.dart';

import '../app/theme.dart';

/// A conversation enclosed by brackets: a wrapper around model conversations.
/// Decorative next to the readable product name; it is not an action.
class WfformMark extends StatelessWidget {
  const WfformMark({super.key, this.size = 34});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = StudioPalette.of(context);
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: _WrapperPainter(colors.ink, colors.sage),
      ),
    );
  }
}

class _WrapperPainter extends CustomPainter {
  const _WrapperPainter(this.ink, this.fill);
  final Color ink, fill;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 48, size.height / 48);
    final outline = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final brackets = Path()
      ..moveTo(10, 9)
      ..lineTo(4, 9)
      ..lineTo(4, 39)
      ..lineTo(10, 39)
      ..moveTo(38, 9)
      ..lineTo(44, 9)
      ..lineTo(44, 39)
      ..lineTo(38, 39);
    final chat = Path()
      ..moveTo(14, 15)
      ..lineTo(34, 15)
      ..lineTo(34, 30)
      ..lineTo(24, 30)
      ..lineTo(18, 35)
      ..lineTo(18, 30)
      ..lineTo(14, 30)
      ..close();
    canvas.drawPath(brackets, outline);
    canvas.drawPath(chat, Paint()..color = fill);
    canvas.drawPath(chat, outline);
    for (final x in [19.0, 24.0, 29.0]) {
      canvas.drawCircle(Offset(x, 22.5), 1.25, Paint()..color = ink);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WrapperPainter oldDelegate) =>
      oldDelegate.ink != ink || oldDelegate.fill != fill;
}
