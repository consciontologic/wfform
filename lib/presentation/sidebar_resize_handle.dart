import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';
import 'selectable_surface.dart';

/// A full-height pointer/touch target and keyboard-adjustable width control.
/// Drag previews stay in the view; storage is updated only after release.
class SidebarResizeHandle extends StatefulWidget {
  const SidebarResizeHandle({
    super.key,
    required this.value,
    required this.minimum,
    required this.maximum,
    required this.onChanged,
    required this.onChangeEnd,
    required this.onCancelled,
    required this.onCollapse,
  });

  static const extent = 24.0;
  final double value, minimum, maximum;
  final ValueChanged<double> onChanged, onChangeEnd;
  final VoidCallback onCancelled;
  final ValueChanged<bool> onCollapse;

  @override
  State<SidebarResizeHandle> createState() => _SidebarResizeHandleState();
}

class _SidebarResizeHandleState extends State<SidebarResizeHandle> {
  final _focus = FocusNode(debugLabel: 'Resize sidebar');
  bool _highlight = false;
  bool _hover = false;
  bool _dragging = false;
  double _dragStart = 0;
  double _dragWidth = 0;
  double _dragValue = 0;
  double get _direction =>
      Directionality.of(context) == TextDirection.rtl ? -1 : 1;

  double _bound(double value) => value.clamp(widget.minimum, widget.maximum);

  void _set(double value) => widget.onChangeEnd(_bound(value));

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = StudioPalette.of(context);
    final active = _highlight || _hover || _dragging;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _set(widget.value + 16 * _direction),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _set(widget.value - 16 * _direction),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _set(widget.value + 16),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _set(widget.value - 16),
        const SingleActivator(LogicalKeyboardKey.home): () =>
            _set(widget.minimum),
        const SingleActivator(LogicalKeyboardKey.end): () =>
            _set(widget.maximum),
        const SingleActivator(LogicalKeyboardKey.enter): () => _set(290),
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            widget.onCollapse(true),
      },
      child: FocusableActionDetector(
        focusNode: _focus,
        mouseCursor: SystemMouseCursors.resizeColumn,
        onShowFocusHighlight: (value) => setState(() => _highlight = value),
        onShowHoverHighlight: (value) => setState(() => _hover = value),
        child: Semantics(
          label: 'Resize sidebar',
          value: '${widget.value.round()} pixels',
          hint:
              'Drag, or use arrow keys. Home for minimum, End for maximum, '
              'Enter to reset. Drag to the left edge or press Escape to hide.',
          slider: true,
          increasedValue: widget.value < widget.maximum
              ? '${_bound(widget.value + 16).round()} pixels'
              : null,
          decreasedValue: widget.value > widget.minimum
              ? '${_bound(widget.value - 16).round()} pixels'
              : null,
          onIncrease: widget.value < widget.maximum
              ? () => _set(widget.value + 16)
              : null,
          onDecrease: widget.value > widget.minimum
              ? () => _set(widget.value - 16)
              : null,
          child: SelectableTooltip(
            message:
                'Drag to resize sidebar. Arrow keys adjust; '
                'Home / End set limits; Enter resets; Escape hides.',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              dragStartBehavior: DragStartBehavior.down,
              // A tap focuses the control. Dragging preserves composer focus.
              onTap: _focus.requestFocus,
              onHorizontalDragStart: (details) {
                _dragStart = details.globalPosition.dx;
                _dragWidth = widget.value;
                _dragValue = widget.value;
                setState(() => _dragging = true);
              },
              onHorizontalDragUpdate: (details) {
                _dragValue =
                    (_dragWidth +
                            (details.globalPosition.dx - _dragStart) *
                                _direction)
                        .clamp(0.0, widget.maximum);
                widget.onChanged(_dragValue);
              },
              onHorizontalDragEnd: (_) {
                setState(() => _dragging = false);
                if (_dragValue <= 32) {
                  widget.onCollapse(false);
                } else {
                  widget.onChangeEnd(_bound(_dragValue));
                }
              },
              onHorizontalDragCancel: () {
                setState(() => _dragging = false);
                widget.onCancelled();
              },
              child: SizedBox(
                width: SidebarResizeHandle.extent,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // The generous drag target straddles the visual boundary.
                    // Match both adjoining surfaces up to the centered line;
                    // Row mirrors the sidebar half in right-to-left layouts.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: ColoredBox(color: palette.cream)),
                        Expanded(child: ColoredBox(color: palette.paper)),
                      ],
                    ),
                    Center(
                      child: SizedBox(
                        width: active ? 3 : 1.5,
                        height: double.infinity,
                        child: ColoredBox(
                          color: active ? palette.ink : palette.border,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
