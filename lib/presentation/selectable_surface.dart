import 'package:flutter/material.dart';

/// Keep selection below each route's Overlay so its toolbar has an insertion
/// point and Select all never includes the screen behind an open dialog.
Future<T?> showSelectableDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) => showDialog<T>(
  context: context,
  barrierDismissible: barrierDismissible,
  builder: (context) => SelectionArea(child: builder(context)),
);

/// Flutter's standard tooltip disables selection and ignores pointer input.
/// An independent selection area inside its rich content keeps hints copyable
/// while the underlying control retains its usual tap and keyboard behavior.
class SelectableTooltip extends StatelessWidget {
  const SelectableTooltip({
    super.key,
    required this.message,
    required this.child,
    this.tooltipKey,
    this.waitDuration,
  });
  final String message;
  final Widget child;
  final GlobalKey<TooltipState>? tooltipKey;
  final Duration? waitDuration;

  @override
  Widget build(BuildContext context) => Tooltip(
    key: tooltipKey,
    richMessage: _TooltipTextSpan(
      message,
      ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: (MediaQuery.sizeOf(context).width - 48).clamp(160, 380),
        ),
        child: SelectionArea(child: Text(message)),
      ),
    ),
    ignorePointer: false,
    enableTapToDismiss: false,
    waitDuration: waitDuration,
    exitDuration: const Duration(milliseconds: 500),
    showDuration: const Duration(seconds: 10),
    child: child,
  );
}

/// A WidgetSpan normally flattens to an object placeholder. The tooltip needs
/// its real text for screen readers and existing tooltip lookup behavior.
class _TooltipTextSpan extends WidgetSpan {
  const _TooltipTextSpan(this.text, Widget content) : super(child: content);
  final String text;

  @override
  void computeToPlainText(
    StringBuffer buffer, {
    bool includeSemanticsLabels = true,
    bool includePlaceholders = true,
  }) => buffer.write(text);
}

class SelectableIconButton extends StatelessWidget {
  const SelectableIconButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });
  final String tooltip;
  final VoidCallback? onPressed;
  final Widget icon;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: SelectableTooltip(
      message: tooltip,
      child: IconButton(onPressed: onPressed, icon: icon),
    ),
  );
}
