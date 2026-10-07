import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';

/// Absolute reset timestamps only. Unknown formats stay unknown; never guess a
/// relative wait from an arbitrary provider value.
DateTime? rateLimitReset(String? value) {
  if (value == null) return null;
  final numeric = int.tryParse(value);
  if (numeric != null) {
    if (numeric >= 1000000000000 && numeric < 10000000000000) {
      return DateTime.fromMillisecondsSinceEpoch(numeric, isUtc: true);
    }
    if (numeric >= 1000000000 && numeric < 10000000000) {
      return DateTime.fromMillisecondsSinceEpoch(numeric * 1000, isUtc: true);
    }
    return null;
  }
  return DateTime.tryParse(value)?.toUtc();
}

enum FailureKind {
  authentication,
  account,
  rateLimit,
  provider,
  http,
  network,
  timeout,
  parsing,
  schema,
  stream,
  cancelled,
  offline,
  configuration,
  storage,
  pwa,
  flutter,
}

class AppFailure implements Exception {
  const AppFailure(
    this.kind,
    this.message, {
    this.status,
    this.retryable = false,
    this.retryAfter,
    this.field,
    this.expected,
    this.actual,
    this.details,
    this.requestId,
    this.provider,
  });
  final FailureKind kind;
  final String message;
  final int? status;
  final bool retryable;
  final Duration? retryAfter;
  final String? field, expected, actual, details, requestId, provider;

  factory AppFailure.from(Object error) {
    if (error is AppFailure) return error;
    if (error is TimeoutException) {
      return const AppFailure(
        FailureKind.timeout,
        'The request timed out. Received output is preserved.',
        retryable: true,
      );
    }
    if (error is FormatException) {
      return AppFailure(
        FailureKind.parsing,
        'The response could not be parsed.',
        details: error.message,
      );
    }
    return AppFailure(
      FailureKind.network,
      'The connection failed. Check connectivity and diagnostics, then retry.',
      retryable: true,
      details:
          'Transport error type: ${error.runtimeType}. Browser network failures do not establish CORS as the cause.',
    );
  }

  factory AppFailure.http(
    int status, {
    String? body,
    Map<String, String> headers = const {},
  }) {
    var effectiveStatus = status;
    String? provider, requestId;
    Map<String, dynamic> safe = {'httpStatus': status};
    try {
      final decoded = jsonDecode(body ?? '');
      if (decoded is Map && decoded['error'] is Map) {
        final err = decoded['error'] as Map;
        final code = int.tryParse('${err['code']}');
        if (code != null) effectiveStatus = code;
        safe['code'] = code ?? '[unrecognized code type]';
        // Error messages/raw provider bodies may echo user prompts. Do not retain them.
        safe['message'] = err['message'] is String
            ? '[upstream error text omitted for conversation privacy]'
            : '[absent]';
        if (err['metadata'] is Map) {
          final metadata = err['metadata'] as Map;
          provider = metadata['provider_name'] is String
              ? metadata['provider_name'] as String
              : null;
          safe['provider'] = provider;
          safe['raw'] = metadata.containsKey('raw')
              ? '[upstream raw body omitted for conversation privacy]'
              : null;
        }
      }
    } catch (_) {
      safe['body'] = '[non-JSON response omitted]';
    }
    requestId =
        headers['x-request-id'] ??
        headers['x-generation-id'] ??
        headers['cf-ray'];
    Duration? after;
    final retry = headers['retry-after'];
    if (retry != null) {
      final seconds = int.tryParse(retry);
      if (seconds != null && seconds >= 0) after = Duration(seconds: seconds);
      // HTTP date parsing is supported without dart:io for the browser.
      if (after == null) {
        final match = RegExp(
          r'\w+, (\d{2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT',
        ).firstMatch(retry);
        const months = [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec',
        ];
        if (match != null && months.contains(match[2])) {
          final date = DateTime.utc(
            int.parse(match[3]!),
            months.indexOf(match[2]!) + 1,
            int.parse(match[1]!),
            int.parse(match[4]!),
            int.parse(match[5]!),
            int.parse(match[6]!),
          );
          final difference = date.difference(DateTime.now().toUtc());
          after = difference.isNegative ? Duration.zero : difference;
        }
      }
    }
    if (effectiveStatus == 429) {
      final reset = rateLimitReset(headers['x-ratelimit-reset']);
      if (reset != null) {
        final wait = reset.difference(DateTime.now().toUtc());
        if (!wait.isNegative && (after == null || wait > after)) after = wait;
      }
    }
    final (kind, message, retryable) = switch (effectiveStatus) {
      401 => (
        FailureKind.authentication,
        'The API key was rejected. Update it in Settings.',
        false,
      ),
      402 => (
        FailureKind.account,
        'OpenRouter reported an account or credit limit. Check your account; no paid route was attempted.',
        false,
      ),
      403 => (
        FailureKind.authentication,
        'Access was denied. Check your key, account permissions, and provider policies.',
        false,
      ),
      429 => (
        FailureKind.rateLimit,
        'OpenRouter is rate-limiting requests. Wait for the cooldown before an explicit retry.',
        true,
      ),
      404 => (
        FailureKind.provider,
        'No eligible endpoint is available for this model and the free-only routing constraints.',
        true,
      ),
      408 || 504 => (
        FailureKind.timeout,
        'The provider timed out. Received output is preserved.',
        true,
      ),
      >= 500 => (
        FailureKind.provider,
        'The model provider could not complete this request. Received output is preserved.',
        true,
      ),
      _ => (
        FailureKind.http,
        'OpenRouter rejected the request (code $effectiveStatus). Inspect diagnostics for adapter details.',
        false,
      ),
    };
    return AppFailure(
      kind,
      message,
      status: status,
      retryable: retryable,
      retryAfter: after,
      provider: provider,
      requestId: requestId,
      details: jsonEncode(safe),
    );
  }
  @override
  String toString() => '${kind.name}: $message';
}

class DiagnosticEvent {
  const DiagnosticEvent(this.data);
  final Map<String, Object?> data;
  bool get isError =>
      !const {'success', 'cancelled', 'offline'}.contains(data['kind']);
  Map<String, Object?> toJson() => data;
}

class Diagnostics extends ChangeNotifier {
  Diagnostics(this.config) {
    addSecret(config.apiKey);
  }
  AppConfig config;
  final List<DiagnosticEvent> _events = [];
  final Set<String> _secrets = {};
  List<DiagnosticEvent> get events => List.unmodifiable(_events);
  void updateConfig(AppConfig value) {
    config = value;
    addSecret(value.apiKey);
    if (_events.length > value.maxDiagnostics) {
      _events.removeRange(value.maxDiagnostics, _events.length);
    }
    notifyListeners();
  }

  void addSecret(String secret) {
    if (secret.isNotEmpty) _secrets.add(secret);
  }

  String sanitize(String text) {
    var result = text;
    for (final secret in _secrets) {
      result = result.replaceAll(secret, '[REDACTED]');
    }
    result = result.replaceAll(
      RegExp(r'sk-or-v1-[A-Za-z0-9_-]+', caseSensitive: false),
      '[REDACTED]',
    );
    result = result.replaceAll(
      RegExp(r'Bearer\s+[^\s"\x27,}]+', caseSensitive: false),
      'Bearer [REDACTED]',
    );
    result = result.replaceAllMapped(
      RegExp(
        r'(authorization|api[_-]?key)\s*["\x27]?\s*[:=]\s*["\x27]?[^\s,}\n]+',
        caseSensitive: false,
      ),
      (match) => '${match[1]}: [REDACTED]',
    );
    return result.length > config.maxDetailChars
        ? '${result.substring(0, config.maxDetailChars)}…[truncated]'
        : result;
  }

  void record(
    String operation, {
    String? model,
    Duration? duration,
    int? status,
    AppFailure? failure,
    String? note,
    String? details,
    String? requestId,
    String? provider,
  }) {
    String? clean(String? text) => text == null ? null : sanitize(text);
    _events.insert(
      0,
      DiagnosticEvent({
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'operation': clean(operation),
        'durationMs': duration?.inMilliseconds,
        'httpStatus': status ?? failure?.status,
        'model': clean(model),
        'provider': clean(provider ?? failure?.provider),
        'requestId': clean(requestId ?? failure?.requestId),
        'kind': failure?.kind.name ?? 'success',
        'summary': clean(failure?.message ?? note ?? 'Completed'),
        'retryable': failure?.retryable ?? false,
        'retryAfterMs': failure?.retryAfter?.inMilliseconds,
        'retryPolicy': failure == null
            ? 'Not applicable to activity events'
            : 'Explicit retry only; no automatic content resend',
        'field': clean(failure?.field),
        'expected': clean(failure?.expected),
        'actual': clean(failure?.actual),
        'details': clean(failure?.details ?? details),
      }),
    );
    if (_events.length > config.maxDiagnostics) {
      _events.removeRange(config.maxDiagnostics, _events.length);
    }
    notifyListeners();
  }

  String export() => const JsonEncoder.withIndent('  ').convert({
    'application': 'wfform',
    'privacy':
        'No request headers, prompts, completions or upstream error text are captured.',
    'events': _events.map((e) => e.toJson()).toList(),
  });
  void clear() {
    _events.clear();
    notifyListeners();
  }
}
