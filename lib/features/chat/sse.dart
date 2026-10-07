import 'dart:async';
import 'dart:convert';

import '../../shared/diagnostics.dart';
import '../../shared/transport.dart';

/// One byte subscription with incremental UTF-8 and SSE framing. Keeping the
/// decoder synchronous avoids nested async-generator cancellation waiting for
/// an upstream socket that stays open after its terminal/error event.
Stream<String> decodeSse(
  Stream<List<int>> bytes, {
  CancelToken? cancel,
  int maxEventChars = 256000,
}) {
  late StreamController<String> controller;
  StreamSubscription<List<int>>? subscription;
  void Function()? unlink;
  var ended = false, firstLine = true, skipLf = false;
  final line = StringBuffer(), data = <String>[];
  var lineSize = 0, eventSize = 0;
  void fail(Object error, [StackTrace? stack]) {
    if (ended) return;
    ended = true;
    unlink?.call();
    controller.addError(error, stack);
    unawaited(subscription?.cancel());
    unawaited(controller.close());
  }

  void parseLine() {
    var value = line.toString();
    line.clear();
    lineSize = 0;
    if (firstLine) {
      firstLine = false;
      if (value.startsWith('\uFEFF')) value = value.substring(1);
    }
    if (value.isEmpty) {
      if (data.isNotEmpty) controller.add(data.join('\n'));
      data.clear();
      eventSize = 0;
      return;
    }
    if (value.startsWith(':')) return;
    final colon = value.indexOf(':');
    if ((colon < 0 ? value : value.substring(0, colon)) != 'data') return;
    value = colon < 0 ? '' : value.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    eventSize += value.length + 1;
    if (eventSize > maxEventChars) {
      throw AppFailure(
        FailureKind.stream,
        'A streaming event exceeded the configured size limit.',
        field: 'SSE.data',
        expected: 'at most $maxEventChars characters',
        actual: '$eventSize characters',
      );
    }
    data.add(value);
  }

  void addText(String chunk) {
    var start = 0;
    if (skipLf && chunk.isNotEmpty) {
      if (chunk.codeUnitAt(0) == 10) start = 1;
      skipLf = false;
    }
    for (var i = start; i < chunk.length; i++) {
      final unit = chunk.codeUnitAt(i);
      if (unit != 10 && unit != 13) continue;
      line.write(chunk.substring(start, i));
      lineSize += i - start;
      if (lineSize > maxEventChars) {
        throw AppFailure(
          FailureKind.stream,
          'A streaming line exceeded the configured size limit.',
          field: 'SSE.data',
          expected: 'at most $maxEventChars characters',
          actual: 'oversized line',
        );
      }
      parseLine();
      if (unit == 13) {
        if (i + 1 < chunk.length && chunk.codeUnitAt(i + 1) == 10) {
          i++;
        } else if (i + 1 == chunk.length) {
          skipLf = true;
        }
      }
      start = i + 1;
    }
    if (start < chunk.length) {
      line.write(chunk.substring(start));
      lineSize += chunk.length - start;
    }
    if (lineSize > maxEventChars) {
      throw AppFailure(
        FailureKind.stream,
        'A streaming line exceeded the configured size limit.',
        field: 'SSE.data',
        expected: 'at most $maxEventChars characters',
        actual: 'oversized line',
      );
    }
  }

  final decoder = utf8.decoder.startChunkedConversion(_TextSink(addText));
  controller = StreamController<String>(
    onListen: () {
      if (cancel?.isCancelled ?? false) {
        fail(
          const AppFailure(
            FailureKind.cancelled,
            'Request cancelled. Received text is kept.',
          ),
        );
        return;
      }
      unlink = cancel?.listen(
        () => fail(
          const AppFailure(
            FailureKind.cancelled,
            'Request cancelled. Received text is kept.',
          ),
        ),
      );
      subscription = bytes.listen(
        (chunk) {
          if (ended) return;
          try {
            decoder.add(chunk);
          } catch (error, stack) {
            fail(error, stack);
          }
        },
        onError: fail,
        onDone: () {
          if (ended) return;
          try {
            decoder.close();
            if (lineSize > 0) parseLine();
            if (data.isNotEmpty) {
              throw const AppFailure(
                FailureKind.stream,
                'The connection ended inside a streaming event. Received text is kept.',
                retryable: true,
              );
            }
            ended = true;
            unlink?.call();
            unawaited(controller.close());
          } catch (error, stack) {
            fail(error, stack);
          }
        },
      );
    },
    onPause: () => subscription?.pause(),
    onResume: () => subscription?.resume(),
    onCancel: () {
      ended = true;
      unlink?.call();
      return subscription?.cancel();
    },
  );
  return controller.stream;
}

class _TextSink implements Sink<String> {
  const _TextSink(this.onData);
  final void Function(String) onData;
  @override
  void add(String data) => onData(data);
  @override
  void close() {}
}
