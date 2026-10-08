import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_identity.dart';
import '../app/studio_state.dart';
import '../app/theme.dart';
import '../shared/diagnostics.dart';
import 'selectable_surface.dart';

/// Information pages reuse this tab so their return links recover its draft.
class AppFooter extends StatelessWidget {
  const AppFooter({super.key, required this.state, this.inSidebar = false});
  final StudioState state;
  final bool inSidebar;

  static const _information = {
    'About': 'about.html',
    'Terms and conditions': 'terms.html',
    'Liability': 'liability.html',
  };

  Future<void> _open(BuildContext context, String destination) async {
    final uri = Uri.base.resolve(destination);
    try {
      if (_information.containsValue(destination)) {
        final ready = await state.prepareToLeave();
        if (!context.mounted) return;
        if (!ready) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                state.historyError?.message ??
                    state.conversationNotice ??
                    'Your draft could not be saved. Stay here and try again.',
              ),
            ),
          );
          return;
        }
        state.platform.navigateTo(uri);
      } else {
        // External links retain synchronous activation for popup allowance.
        state.platform.openUrl(uri);
      }
    } catch (_) {
      if (!context.mounted) return;
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
      final identityItems = <Widget>[
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
      ];
      final identity = inSidebar
          ? Padding(
              padding: const EdgeInsets.only(left: 8),
              child: OverflowBar(
                alignment: MainAxisAlignment.start,
                overflowAlignment: OverflowBarAlignment.start,
                spacing: 8,
                children: identityItems,
              ),
            )
          : Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: identityItems,
            );
      Widget informationLink(MapEntry<String, String> entry) => Semantics(
        key: ValueKey('footer-${entry.key.toLowerCase().split(' ').first}'),
        link: true,
        hint: 'Saves your draft and opens in this tab',
        child: TextButton(
          onPressed: () => _open(context, entry.value),
          style: inSidebar
              ? buttonStyle.copyWith(
                  alignment: Alignment.centerLeft,
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                )
              : buttonStyle,
          child: Text(entry.key),
        ),
      );
      if (inSidebar) {
        // The drawer owns scrolling so short screens and large text can reach
        // these direct links without another menu or a fixed-height footer.
        return Container(
          decoration: BoxDecoration(
            color: colors.cream,
            border: Border(top: BorderSide(color: colors.border)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              identity,
              const SizedBox(height: 4),
              for (final entry in _information.entries) informationLink(entry),
            ],
          ),
        );
      }
      return Container(
        decoration: BoxDecoration(
          color: colors.paper,
          border: Border(top: BorderSide(color: colors.border)),
        ),
        padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 24),
        child: Row(
          children: [
            Expanded(child: identity),
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
                        hint: 'Saves your draft and opens in this tab',
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
              for (final entry in _information.entries) informationLink(entry),
          ],
        ),
      );
    },
  );
}
