import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'diagnostics.dart';

class CancelToken {
  final Completer<void> _completer = Completer<void>();
  final _listeners = <void Function()>{};
  bool get isCancelled => _completer.isCompleted;
  Future<void> get whenCancelled => _completer.future;
  void cancel() {
    if (isCancelled) return;
    _completer.complete();
    for (final listener in List.of(_listeners)) {
      listener();
    }
    _listeners.clear();
  }

  /// Resource owners can release timers synchronously during dispose.
  void Function() listen(void Function() listener) {
    if (isCancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void throwIfCancelled() {
    if (isCancelled) {
      throw const AppFailure(
        FailureKind.cancelled,
        'Request cancelled. Received output is preserved.',
      );
    }
  }
}

abstract interface class ApiTransport {
  Future<ApiResponse> send(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    Object? body,
    required Duration timeout,
    CancelToken? cancel,
  });
}

class ApiResponse {
  const ApiResponse(this.status, this.headers, this.body);
  final int status;
  final Map<String, String> headers;
  final Stream<List<int>> body;
  Future<String> readText({int maxBytes = 8000000}) async {
    final bytes = <int>[];
    await for (final chunk in body) {
      if (bytes.length + chunk.length > maxBytes) {
        throw const AppFailure(
          FailureKind.schema,
          'Response exceeded the configured size limit.',
          field: r'$',
          expected: 'bounded response',
          actual: 'oversized response',
        );
      }
      bytes.addAll(chunk);
    }
    try {
      return utf8.decode(bytes);
    } catch (_) {
      throw const AppFailure(
        FailureKind.parsing,
        'Response contains invalid UTF-8.',
        expected: 'UTF-8',
        actual: 'invalid byte sequence',
      );
    }
  }
}

/// Fetch-backed http BrowserClient supports incremental bytes and AbortController.
/// Each request owns its client, so abort never closes another operation.
class HttpApiTransport implements ApiTransport {
  @override
  Future<ApiResponse> send(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    Object? body,
    required Duration timeout,
    CancelToken? cancel,
  }) async {
    cancel?.throwIfCancelled();
    final client = http.Client();
    final abort = Completer<void>();
    var timedOut = false;
    var closed = false;
    void stop() {
      if (!abort.isCompleted) abort.complete();
      client.close();
    }

    final timer = Timer(timeout, () {
      timedOut = true;
      stop();
    });
    cancel?.whenCancelled.then((_) {
      if (!closed) stop();
    });
    void close() {
      closed = true;
      timer.cancel();
      client.close();
    }

    AppFailure failure(Object error) => timedOut
        ? const AppFailure(
            FailureKind.timeout,
            'The total request time limit was reached. Partial output is preserved.',
            retryable: true,
          )
        : (cancel?.isCancelled ?? false)
        ? const AppFailure(
            FailureKind.cancelled,
            'Request cancelled. Partial output is preserved.',
          )
        : AppFailure.from(error);
    try {
      final request =
          http.AbortableRequest(method, uri, abortTrigger: abort.future)
            ..followRedirects = false
            ..headers.addAll(headers);
      if (body != null) request.body = body is String ? body : jsonEncode(body);
      final response = await client.send(request);
      Stream<List<int>> bytes() async* {
        try {
          await for (final part in response.stream) {
            cancel?.throwIfCancelled();
            yield part;
          }
        } catch (error) {
          throw failure(error);
        } finally {
          close();
        }
      }

      return ApiResponse(response.statusCode, response.headers, bytes());
    } catch (error) {
      close();
      throw failure(error);
    }
  }
}

/// Watches useful inference output, not heartbeat bytes. Metadata/comments do
/// not indefinitely extend a stalled generation. Cancelling closes the source.
Stream<T> withPhaseTimeouts<T>(
  Stream<T> source, {
  required CancelToken cancel,
  required Duration firstResponseTimeout,
  required Duration idleTimeout,
  required Duration overallTimeout,
  required bool Function(T value) isProgress,
  void Function()? onDispose,
  AppFailure? Function(T value)? errorFromValue,
  bool Function(T value)? isComplete,
}) {
  late StreamController<T> controller;
  StreamSubscription<T>? subscription;
  Timer? phaseTimer, overallTimer;
  void Function()? removeCancelListener;
  var finished = false;
  var disposed = false;
  void cancelSource() {
    final cleanup = subscription?.cancel();
    if (cleanup != null) {
      unawaited(
        cleanup.catchError((Object error, StackTrace stack) {
          // Cancelling an async generator can surface its already-delivered
          // cancellation through the cleanup Future as well as its event stream.
          if (error is AppFailure && error.kind == FailureKind.cancelled) {
            return;
          }
          Error.throwWithStackTrace(error, stack);
        }),
      );
    }
  }

  void stopTimers() {
    phaseTimer?.cancel();
    overallTimer?.cancel();
    removeCancelListener?.call();
    if (!disposed) {
      disposed = true;
      onDispose?.call();
    }
  }

  void timeout(String phase) {
    if (finished) return;
    finished = true;
    stopTimers();
    controller.addError(
      AppFailure(
        FailureKind.timeout,
        '$phase timeout reached. Received output is preserved.',
        retryable: true,
        details: 'Timeout phase: $phase',
      ),
    );
    cancel.cancel();
    cancelSource();
    unawaited(controller.close());
  }

  controller = StreamController<T>(
    onListen: () {
      if (cancel.isCancelled) {
        finished = true;
        controller.addError(
          const AppFailure(
            FailureKind.cancelled,
            'Request cancelled. Received output is preserved.',
          ),
        );
        unawaited(controller.close());
        return;
      }
      phaseTimer = Timer(firstResponseTimeout, () => timeout('First response'));
      overallTimer = Timer(overallTimeout, () => timeout('Overall request'));
      removeCancelListener = cancel.listen(() {
        if (finished) return;
        finished = true;
        stopTimers();
        controller.addError(
          const AppFailure(
            FailureKind.cancelled,
            'Request cancelled. Received output is preserved.',
          ),
        );
        cancelSource();
        unawaited(controller.close());
      });
      subscription = source.listen(
        (value) {
          if (finished) return;
          final error = errorFromValue?.call(value);
          if (error != null || (isComplete?.call(value) ?? false)) {
            finished = true;
            stopTimers();
            if (error != null) {
              controller.addError(error);
            } else {
              controller.add(value);
            }
            cancelSource();
            unawaited(controller.close());
            return;
          }
          if (isProgress(value)) {
            phaseTimer?.cancel();
            phaseTimer = Timer(idleTimeout, () => timeout('Response idle'));
          }
          controller.add(value);
        },
        onError: (Object error, StackTrace stack) {
          if (finished) return;
          finished = true;
          stopTimers();
          controller.addError(error, stack);
          cancelSource();
          unawaited(controller.close());
        },
        onDone: () {
          if (finished) return;
          finished = true;
          stopTimers();
          unawaited(controller.close());
        },
      );
    },
    onPause: () => subscription?.pause(),
    onResume: () => subscription?.resume(),
    onCancel: () {
      finished = true;
      stopTimers();
      // A decoder can itself be awaiting cancellation of a nested stream.
      // Do not make delivery of its terminal error wait on that cleanup chain.
      cancelSource();
    },
  );
  return controller.stream;
}
