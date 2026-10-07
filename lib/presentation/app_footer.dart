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
            Expanded(
              child: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Semantics(
                    label: 'Version $appVersion',
                    excludeSemantics: true,
                    child: Text(
                      'v$appVersion',
                      style: TextStyle(fontSize: 11, color: colors.muted),
                    ),
                  ),
                  Semantics(
                    key: const ValueKey('footer-source'),
                    link: true,
                    hint: 'Opens in a new tab',
                    child: SelectableTooltip(
                      message: 'GitHub source code',
                      child: TextButton(
                        key: const ValueKey('footer-github'),
                        onPressed: () => _open(context, sourceRepositoryUrl),
                        style: buttonStyle.copyWith(
                          padding: const WidgetStatePropertyAll(
                            EdgeInsets.symmetric(horizontal: 6),
                          ),
                        ),
                        child: const Text('GitHub'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
          ],
        ),
      );
    },
  );
}
