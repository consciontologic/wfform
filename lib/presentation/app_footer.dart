import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_identity.dart';
import '../app/studio_state.dart';
import '../app/theme.dart';
import '../shared/diagnostics.dart';
import 'selectable_surface.dart';

/// A compact route to product information without replacing the active chat.
class AppFooter extends StatelessWidget {
  const AppFooter({super.key, required this.state});
  final StudioState state;

  static const _information = {
    'About': 'about.html',
    'Terms and conditions': 'terms.html',
    'Liability': 'liability.html',
  };

  void _open(BuildContext context, String destination) {
    final uri = Uri.base.resolve(destination);
    try {
      // Synchronous activation preserves the browser's user-gesture allowance.
      state.platform.openUrl(uri);
    } catch (_) {
      state.diagnostics.record(
        'link.open',
        failure: const AppFailure(
          FailureKind.configuration,
          'This platform could not open an information link. Copy the link and open it in a browser.',
        ),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open $uri'),
          action: SnackBarAction(
            label: 'Copy link',
            onPressed: () => Clipboard.setData(ClipboardData(text: '$uri')),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final colors = StudioPalette.of(context);
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final compact = constraints.maxWidth < 680 * scale;
      final iconOnlyInfo = constraints.maxWidth < 380 && scale >= 1.5;
      final buttonStyle = TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        foregroundColor: colors.muted,
        textStyle: const TextStyle(fontSize: 12),
      );
      return Container(
        decoration: BoxDecoration(
          color: colors.paper,
          border: Border(top: BorderSide(color: colors.border)),
        ),
        padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 24),
        child: Row(
          children: [
            Semantics(
              label: 'Version $appVersion',
              excludeSemantics: true,
              child: Text(
                'v$appVersion',
                style: TextStyle(fontSize: 11, color: colors.muted),
              ),
            ),
            const Spacer(),
            if (compact)
              PopupMenuButton<String>(
                tooltip: 'Information links',
                onSelected: (destination) => _open(context, destination),
                itemBuilder: (context) => [
                  for (final entry in _information.entries)
                    PopupMenuItem(
                      value: entry.value,
                      child: Semantics(
                        link: true,
                        hint: 'Opens in a new tab',
                        child: Text(entry.key),
                      ),
                    ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    height: 48,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (iconOnlyInfo)
                          Icon(
                            Icons.info_outline,
                            size: 22,
                            color: colors.muted,
                          )
                        else
                          Text(
                            'Info',
                            style: TextStyle(fontSize: 12, color: colors.muted),
                          ),
                        const SizedBox(width: 4),
                        Icon(Icons.expand_less, size: 18, color: colors.muted),
                      ],
                    ),
                  ),
                ),
              )
            else
              for (final entry in _information.entries)
                Semantics(
                  key: ValueKey(
                    'footer-${entry.key.toLowerCase().split(' ').first}',
                  ),
                  link: true,
                  hint: 'Opens in a new tab',
                  child: TextButton(
                    onPressed: () => _open(context, entry.value),
                    style: buttonStyle,
                    child: Text(entry.key),
                  ),
                ),
            const SizedBox(width: 4),
            Semantics(
              link: true,
              hint: 'Opens in a new tab',
              child: SelectableTooltip(
                message: 'GitHub source code',
                child: TextButton(
                  key: const ValueKey('footer-github'),
                  onPressed: () => _open(context, sourceRepositoryUrl),
                  style: buttonStyle.copyWith(
                    padding: WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: compact ? 6 : 12),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _GitHubDoodle(),
                      if (!compact) ...[
                        const SizedBox(width: 7),
                        Text('GitHub', style: TextStyle(color: colors.ink)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// A small cat-and-code doodle, drawn locally and named by its surrounding link.
class _GitHubDoodle extends StatelessWidget {
  const _GitHubDoodle();

  @override
  Widget build(BuildContext context) {
    final colors = StudioPalette.of(context);
    return ExcludeSemantics(
      child: CustomPaint(
        size: const Size.square(32),
        painter: _GitHubPainter(colors.ink, colors.sage),
      ),
    );
  }
}

class _GitHubPainter extends CustomPainter {
  const _GitHubPainter(this.ink, this.fill);
  final Color ink, fill;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 40, size.height / 40);
    final pen = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawOval(const Rect.fromLTWH(1, 1, 37, 37), Paint()..color = fill);
    final cat = Path()
      ..moveTo(12, 29)
      ..cubicTo(6, 28, 5, 20, 9, 15)
      ..lineTo(9, 7)
      ..lineTo(16, 11)
      ..quadraticBezierTo(20, 10, 24, 11)
      ..lineTo(31, 7)
      ..lineTo(31, 15)
      ..cubicTo(35, 20, 34, 28, 27, 29)
      ..quadraticBezierTo(25, 30, 26, 35)
      ..moveTo(14, 35)
      ..lineTo(14, 29)
      ..moveTo(14, 32)
      ..cubicTo(7, 34, 8, 28, 4, 28);
    canvas.drawPath(cat, pen);
    canvas.drawOval(const Rect.fromLTWH(13, 19, 3, 4), Paint()..color = ink);
    canvas.drawOval(const Rect.fromLTWH(24, 19, 3, 4), Paint()..color = ink);
    canvas.drawPath(
      Path()
        ..moveTo(18, 26)
        ..quadraticBezierTo(20, 27, 22, 26),
      pen,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GitHubPainter oldDelegate) =>
      oldDelegate.ink != ink || oldDelegate.fill != fill;
}
