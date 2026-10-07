import 'dart:async';
import 'package:flutter/material.dart';

/// A local countdown never retries a request. Only an explicit click can send.
class RetryControl extends StatefulWidget {
  const RetryControl({
    super.key,
    required this.retryAt,
    required this.onRetry,
    this.now,
  });
  final DateTime Function()? now;
  final DateTime? retryAt;
  final VoidCallback? onRetry;
  @override
  State<RetryControl> createState() => _RetryControlState();
}

class _RetryControlState extends State<RetryControl> {
  Timer? _timer;
  int get seconds => widget.retryAt == null
      ? 0
      : (widget.retryAt!
                    .difference(widget.now?.call() ?? DateTime.now())
                    .inMilliseconds /
                1000)
            .ceil()
            .clamp(0, 2147483647);
  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant RetryControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.retryAt != widget.retryAt) _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (seconds <= 0) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {});
      if (seconds == 0) timer.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: seconds > 0 ? null : widget.onRetry,
    child: Text(seconds > 0 ? 'Retry in ${seconds}s' : 'Retry'),
  );
}
