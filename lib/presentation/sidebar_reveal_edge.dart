import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';

/// No permanent navigation rail: only the outermost pixels reveal on hover.
/// A wider invisible tap target and a named focus stop provide touch/keyboard
/// access to the same preview without requiring precise pointer positioning.
class SidebarRevealEdge extends StatefulWidget {
  const SidebarRevealEdge({
    super.key,
    required this.focusNode,
    required this.onReveal,
    required this.onHoverReveal,
    required this.onPointerExit,
    required this.onDismiss,
  });

  final FocusNode focusNode;
  final VoidCallback onReveal, onHoverReveal, onPointerExit, onDismiss;

  @override
  State<SidebarRevealEdge> createState() => _SidebarRevealEdgeState();
}

class _SidebarRevealEdgeState extends State<SidebarRevealEdge> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.enter): widget.onReveal,
      const SingleActivator(LogicalKeyboardKey.space): widget.onReveal,
      const SingleActivator(LogicalKeyboardKey.arrowRight): widget.onReveal,
      const SingleActivator(LogicalKeyboardKey.escape): widget.onDismiss,
    },
    child: FocusableActionDetector(
      focusNode: widget.focusNode,
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      child: Semantics(
        label: 'Show sidebar',
        hint: 'Preview navigation. Choose an item to keep it open.',
        button: true,
        onTap: widget.onReveal,
        child: MouseRegion(
          onEnter: (event) {
            if (event.localPosition.dx <= 4) widget.onHoverReveal();
          },
          onHover: (event) {
            // Fresh pointer movement is deliberate, unlike the synthetic enter
            // caused by mounting this region beneath a just-finished drag.
            if (event.localPosition.dx <= 4) widget.onReveal();
          },
          onExit: (_) => widget.onPointerExit(),
          child: GestureDetector(
            excludeFromSemantics: true,
            behavior: HitTestBehavior.opaque,
            onTap: () {
              widget.focusNode.requestFocus();
              widget.onReveal();
            },
            child: SizedBox(
              width: 24,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: _focused ? 3 : 0,
                  height: double.infinity,
                  child: ColoredBox(color: StudioPalette.of(context).ink),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
