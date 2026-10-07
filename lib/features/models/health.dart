import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../config/app_config.dart';
import '../../shared/diagnostics.dart';
import '../../shared/transport.dart';
import '../../shared/platform.dart';
import '../chat/chat_api.dart';
import 'model.dart';

enum HealthStatus {
  unknown,
  checking,
  responsive,
  degraded,
  unavailable,
  rateLimited,
}

class HealthObservation {
  const HealthObservation({
    this.status = HealthStatus.unknown,
    this.checkedAt,
    this.message = 'No recent inference observation.',
    this.provider,
    this.retryAt,
    this.failure,
    this.endpointSummary,
  });
  final HealthStatus status;
  final DateTime? checkedAt;
  final String message;
  final String? provider;
  final DateTime? retryAt;
  final AppFailure? failure;
  final String? endpointSummary;
}

class QuotaSnapshot {
  const QuotaSnapshot({
    required this.checkedAt,
    this.used,
    this.limit,
    this.remaining,
    this.resetAt,
    this.source = 'OpenRouter key metadata',
  });
  final DateTime checkedAt;
  final int? used, limit, remaining;
  final DateTime? resetAt;
  final String source;
  String get summary => remaining == null
      ? 'Free-request quota is not reported.'
      : source == 'Rate-limit response headers'
      ? '$remaining requests remaining${limit == null ? '' : ' of $limit'} in the reported rate-limit window'
      : '$remaining free requests remaining${limit == null ? '' : ' of $limit'} · $source';
  Map<String, dynamic> toJson() => {
    'checkedAt': checkedAt.toIso8601String(),
    'used': used,
    'limit': limit,
    'remaining': remaining,
    'resetAt': resetAt?.toIso8601String(),
    'source': source,
  };
  static QuotaSnapshot? fromJson(Object? value) {
    if (value is! Map || value['checkedAt'] is! String) return null;
    final at = DateTime.tryParse(value['checkedAt'] as String);
    if (at == null) return null;
    int? count(String key) => value[key] is int && (value[key] as int) >= 0
        ? value[key] as int
        : null;
    return QuotaSnapshot(
      checkedAt: at,
      used: count('used'),
      limit: count('limit'),
      remaining: count('remaining'),
      resetAt: value['resetAt'] is String
          ? DateTime.tryParse(value['resetAt'] as String)
          : null,
      source: value['source'] == 'Rate-limit response headers'
          ? 'Rate-limit response headers'
          : 'OpenRouter key metadata',
    );
  }
}

class HealthController extends ChangeNotifier {
  HealthController({
    required this.config,
    required this.transport,
    required this.diagnostics,
    this.store,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    _loadCache();
  }
  final AppConfig config;
  final ApiTransport transport;
  final Diagnostics diagnostics;
  final LocalStore? store;
  final DateTime Function() _now;
  final _observations = <String, HealthObservation>{};
  final _inFlight = <String, Future<HealthObservation>>{};
  final _tokens = <CancelToken, String>{};
  final _failures = <String, int>{};
  final _lastAttempt = <String, DateTime>{};
  DateTime? _globalRetryAt;
  bool _disposed = false;
  final _signatures = <String, String>{};
  final _endpointCache = <String, ({DateTime at, String? summary})>{};
  final _modalities = <String, Map<String, HealthObservation>>{};
  static const _cacheKey = 'wfform.health.v2';
  QuotaSnapshot? quota;
  bool quotaLoading = false;
  AppFailure? quotaError;
  Future<void>? _quotaInFlight;
  CancelToken? _quotaToken;
  DateTime? _quotaRetryAt;
  DateTime? get quotaRetryAt =>
      _quotaRetryAt != null && _now().isBefore(_quotaRetryAt!)
      ? _quotaRetryAt
      : null;
  bool get quotaStale =>
      quota == null ||
      _now().isBefore(quota!.checkedAt) ||
      _now().difference(quota!.checkedAt) >= config.quotaTtl ||
      (quota!.resetAt != null && !_now().isBefore(quota!.resetAt!));

  Map<String, HealthObservation> modalityObservations(String id) =>
      Map.unmodifiable(_modalities[id] ?? const {});

  DateTime? retryAtFor(String id) {
    final at = _later(forModel(id).retryAt, _globalRetryAt);
    return at != null && _now().isBefore(at) ? at : null;
  }

  AppFailure? admissionFailure(FreeModel model) {
    _prepareModel(model);
    final at = retryAtFor(model.id);
    if (at == null) return null;
    final previous = forModel(model.id).failure;
    final global = _globalRetryAt != null && _now().isBefore(_globalRetryAt!);
    return AppFailure(
      global ? FailureKind.rateLimit : previous?.kind ?? FailureKind.provider,
      'Requests are cooling down until ${at.toLocal()}. No new attempt was created.',
      retryable: true,
      retryAfter: at.difference(_now()),
      status: previous?.status,
      provider: previous?.provider,
    );
  }

  void reconcileModels(Iterable<FreeModel> models) {
    for (final model in models) {
      _prepareModel(model);
    }
    _saveCache();
  }

  void _prepareModel(FreeModel model) {
    final previous = _signatures[model.id];
    if (previous != null && previous != model.signature) {
      _observations.remove(model.id);
      _lastAttempt.remove(model.id);
      _failures.remove(model.id);
      _endpointCache.remove(model.id);
      _modalities.remove(model.id);
    }
    _signatures[model.id] = model.signature;
    // Model signatures are also bounded, including models never probed.
    while (_signatures.length > 200) {
      _signatures.remove(_signatures.keys.first);
    }
  }

  Future<void> refreshQuota({bool force = false}) {
    if (_disposed) return Future.value();
    if (_quotaInFlight != null) return _quotaInFlight!;
    if (quotaRetryAt != null) {
      quotaError = AppFailure(
        FailureKind.rateLimit,
        'Quota checks are cooling down until ${quotaRetryAt!.toLocal()}.',
        retryable: true,
        retryAfter: quotaRetryAt!.difference(_now()),
      );
      notifyListeners();
      return Future.value();
    }
    if (!force && !quotaStale) return Future.value();
    final work = _refreshQuota();
    _quotaInFlight = work;
    return work.whenComplete(() => _quotaInFlight = null);
  }

  Future<void> _refreshQuota() async {
    quotaLoading = true;
    quotaError = null;
    notifyListeners();
    final watch = Stopwatch()..start();
    final token = CancelToken();
    _quotaToken = token;
    try {
      if (config.apiKey.trim().isEmpty) {
        throw const AppFailure(
          FailureKind.authentication,
          'Add an API key to check quota.',
        );
      }
      final response = await transport.send(
        'GET',
        Uri.parse('${config.apiBaseUrl}/key'),
        headers: {'Authorization': 'Bearer ${config.apiKey}'},
        timeout: config.requestTimeout,
        cancel: token,
      );
      final raw = await response.readText(maxBytes: 65536);
      if (response.status < 200 || response.status >= 300) {
        throw AppFailure.http(
          response.status,
          body: raw,
          headers: response.headers,
        );
      }
      final value = jsonDecode(raw);
      if (value is Map<String, dynamic> && value['error'] != null) {
        throw envelopeFailure(value, response.headers);
      }
      if (value is! Map || value['data'] is! Map) {
        throw const AppFailure(
          FailureKind.schema,
          'Quota response is missing its data object.',
          field: r'$.data',
          expected: 'object',
        );
      }
      final data = value['data'] as Map;
      final counters = data['free_model_daily_requests'];
      if (counters != null && counters is! Map) {
        throw const AppFailure(
          FailureKind.schema,
          'Free-request counters changed format.',
          field: r'$.data.free_model_daily_requests',
          expected: 'object',
        );
      }
      int? count(String key) {
        final value = counters is Map ? counters[key] : null;
        if (value == null) return null;
        if (value is! num ||
            !value.isFinite ||
            value < 0 ||
            value != value.roundToDouble()) {
          throw AppFailure(
            FailureKind.schema,
            'The quota $key field is not a request count.',
            field: '\$.data.free_model_daily_requests.$key',
            expected: 'nonnegative integer',
            actual: value.runtimeType.toString(),
          );
        }
        return value.toInt();
      }

      final now = _now().toUtc();
      if (_disposed || token.isCancelled) return;
      quota = QuotaSnapshot(
        checkedAt: now,
        used: count('used'),
        limit: count('limit'),
        remaining: count('remaining'),
        resetAt: DateTime.utc(now.year, now.month, now.day + 1),
      );
      _quotaRetryAt = null;
      // Counters are advisory: documented exempt accounts/routes may not be gated.
      _saveCache();
      diagnostics.record(
        'quota.refresh',
        duration: watch.elapsed,
        status: response.status,
        note:
            'Read free-request counters; values are advisory for exempt accounts/routes.',
      );
    } catch (error) {
      if (!_disposed) {
        quotaError = AppFailure.from(error);
        if (quotaError!.kind == FailureKind.rateLimit) {
          _quotaRetryAt = _now().add(quotaError!.retryAfter ?? config.cooldown);
          _saveCache();
        }
        diagnostics.record(
          'quota.refresh',
          duration: watch.elapsed,
          failure: quotaError,
        );
      }
    } finally {
      _quotaToken = null;
      if (!_disposed) {
        quotaLoading = false;
        notifyListeners();
      }
    }
  }

  void recordResponseHeaders(String id, Map<String, String> headers) {
    int? count(String key) {
      final v = int.tryParse(headers[key] ?? '');
      return v != null && v >= 0 ? v : null;
    }

    final remaining = count('x-ratelimit-remaining');
    final limit = count('x-ratelimit-limit');
    final reset = rateLimitReset(headers['x-ratelimit-reset']);
    if (remaining == null && limit == null && reset == null) return;
    quota = QuotaSnapshot(
      checkedAt: _now().toUtc(),
      remaining: remaining,
      limit: limit,
      resetAt: reset,
      source: 'Rate-limit response headers',
    );
    if (remaining == 0 && reset != null && _now().isBefore(reset)) {
      _globalRetryAt = _later(_globalRetryAt, reset);
    }
    _saveCache();
    if (!_disposed) notifyListeners();
  }

  void recordModalityResult(
    String id,
    Iterable<String> modalities, {
    AppFailure? failure,
    String? provider,
  }) {
    final outcomes = _modalities.putIfAbsent(id, () => {});
    for (final modality in modalities.toSet()) {
      outcomes[modality] = HealthObservation(
        status: failure == null
            ? HealthStatus.responsive
            : failure.kind == FailureKind.rateLimit
            ? HealthStatus.rateLimited
            : {
                FailureKind.provider,
                FailureKind.timeout,
                FailureKind.stream,
                FailureKind.schema,
                FailureKind.parsing,
              }.contains(failure.kind)
            ? HealthStatus.degraded
            : HealthStatus.unknown,
        checkedAt: _now(),
        provider: provider ?? failure?.provider,
        message: failure == null
            ? 'A real $modality request succeeded.'
            : 'A real $modality request failed (${failure.kind.name}); catalog support is not a guarantee.',
      );
    }
    _saveCache();
    if (!_disposed) notifyListeners();
  }

  HealthObservation forModel(String id) =>
      _observations[id] ?? const HealthObservation();

  bool isFresh(String id) {
    final observation = forModel(id);
    final checked = observation.checkedAt;
    return observation.status == HealthStatus.responsive &&
        checked != null &&
        !_now().isBefore(checked) &&
        _now().difference(checked) < config.healthTtl;
  }

  Future<HealthObservation> check(
    FreeModel model, {
    bool force = false,
    CancelToken? cancel,
  }) {
    _prepareModel(model);
    final existing = _inFlight[model.id];
    if (existing != null) {
      return cancel == null
          ? existing
          : Future.any([
              existing,
              cancel.whenCancelled.then(
                (_) => const HealthObservation(
                  failure: AppFailure(
                    FailureKind.cancelled,
                    'Request cancelled.',
                  ),
                  message: 'Request cancelled.',
                ),
              ),
            ]);
    }
    final current = forModel(model.id);
    if (_disposed) {
      return Future.value(current);
    }
    final blockedUntil = _later(current.retryAt, _globalRetryAt);
    if (blockedUntil != null && _now().isBefore(blockedUntil)) {
      return Future.value(
        HealthObservation(
          status: _globalRetryAt != null && _now().isBefore(_globalRetryAt!)
              ? HealthStatus.rateLimited
              : current.status,
          checkedAt: current.checkedAt,
          retryAt: blockedUntil,
          provider: current.provider,
          message: 'Checks are cooling down until ${blockedUntil.toLocal()}.',
          failure:
              current.failure ??
              AppFailure(
                FailureKind.rateLimit,
                'Wait for the current API cooldown before checking again.',
                retryable: true,
                retryAfter: blockedUntil.difference(_now()),
              ),
          endpointSummary: current.endpointSummary,
        ),
      );
    }
    if (!force && isFresh(model.id)) return Future.value(current);
    final last = _lastAttempt[model.id];
    if (last != null && _now().difference(last) < config.cooldown) {
      return Future.value(current);
    }
    // A short selected-only workload needs no unbounded background queue.
    if (_inFlight.length >= 2) {
      return Future.value(
        HealthObservation(
          message: 'Two checks are already running. Recheck shortly.',
          failure: AppFailure(
            FailureKind.configuration,
            'Health check concurrency limit reached. Try again shortly.',
            retryable: true,
          ),
        ),
      );
    }
    final token = cancel ?? CancelToken();
    _tokens[token] = model.id;
    _lastAttempt[model.id] = _now();
    final completer = Completer<HealthObservation>();
    final future = completer.future;
    _inFlight[model.id] = future;
    unawaited(
      _perform(model, token).then(completer.complete).whenComplete(() {
        _tokens.remove(token);
        if (_inFlight[model.id] == future) _inFlight.remove(model.id);
      }),
    );
    return future;
  }

  Future<HealthObservation> _perform(FreeModel model, CancelToken token) async {
    final watch = Stopwatch()..start();
    final previous = forModel(model.id);
    _set(
      model.id,
      HealthObservation(
        status: HealthStatus.checking,
        message: 'Checking endpoint metadata, then a tiny inference probe.',
        checkedAt: previous.checkedAt,
        provider: previous.provider,
        endpointSummary: previous.endpointSummary,
      ),
    );
    int? status;
    String? requestId;
    String? endpointSummary = previous.endpointSummary;
    try {
      token.throwIfCancelled();
      if (config.apiKey.trim().isEmpty) {
        throw AppFailure(
          FailureKind.authentication,
          'Add an OpenRouter API key in Settings to check responsiveness.',
        );
      }
      if (!model.chatCompatible) {
        throw AppFailure(
          FailureKind.configuration,
          model.incompatibilityReason ??
              'This model does not support text chat.',
        );
      }
      endpointSummary = await _endpoints(model, token);
      _set(
        model.id,
        HealthObservation(
          status: HealthStatus.checking,
          message:
              'Sending a small probe; no conversation content is included.',
          checkedAt: previous.checkedAt,
          endpointSummary: endpointSummary,
        ),
      );
      String? provider;
      var responsive = false;
      await for (final delta in ChatApi(config, transport).stream(
        model,
        const [
          {'role': 'user', 'content': 'Reply OK.'},
        ],
        cancel: token,
        probe: true,
        onResponse: (code, id) {
          status = code;
          requestId = id;
        },
        onHeaders: (headers) => recordResponseHeaders(model.id, headers),
      )) {
        provider = delta.provider ?? provider;
        requestId = delta.requestId ?? requestId;
        if (delta.content.isNotEmpty || delta.reasoning.isNotEmpty) {
          responsive = true;
          // First real inference output is enough. Cancelling the subscription
          // closes the request; no bulk probing or long generation is needed.
          break;
        }
      }
      if (!responsive) {
        throw AppFailure(
          FailureKind.provider,
          'The probe returned no inference output.',
          retryable: true,
        );
      }
      token.throwIfCancelled();
      recordSuccess(
        model.id,
        provider: provider,
        endpointSummary: endpointSummary,
      );
      diagnostics.record(
        'health.probe',
        model: model.id,
        status: status,
        duration: watch.elapsed,
        requestId: requestId,
        provider: provider,
        note: 'Received inference output; recent observation, not a guarantee.',
      );
    } catch (error) {
      if (_disposed) return forModel(model.id);
      final failure = AppFailure.from(error);
      recordFailure(model.id, failure, endpointSummary: endpointSummary);
      diagnostics.record(
        'health.probe',
        model: model.id,
        status: status ?? failure.status,
        duration: watch.elapsed,
        requestId: requestId ?? failure.requestId,
        provider: failure.provider,
        failure: failure,
      );
    }
    return forModel(model.id);
  }

  Future<String?> _endpoints(FreeModel model, CancelToken token) async {
    final cached = _endpointCache[model.id];
    if (cached != null &&
        !_now().isBefore(cached.at) &&
        _now().difference(cached.at) < config.endpointTtl) {
      return cached.summary;
    }
    final watch = Stopwatch()..start();
    int? status;
    try {
      final path = model.id.split('/').map(Uri.encodeComponent).join('/');
      final response = await transport.send(
        'GET',
        Uri.parse('${config.apiBaseUrl}/models/$path/endpoints'),
        headers: {'Authorization': 'Bearer ${config.apiKey}'},
        timeout: config.probeTimeout,
        cancel: token,
      );
      status = response.status;
      final text = await response.readText(maxBytes: 250000);
      token.throwIfCancelled();
      if (response.status < 200 || response.status >= 300) {
        throw AppFailure.http(
          response.status,
          body: text,
          headers: response.headers,
        );
      }
      Object? decoded;
      try {
        decoded = jsonDecode(text);
      } on FormatException {
        throw AppFailure(
          FailureKind.parsing,
          'Endpoint metadata was not valid JSON.',
          field: r'$.data.endpoints',
          expected: 'JSON object',
          actual: 'malformed JSON',
        );
      }
      if (decoded is Map<String, dynamic> && decoded['error'] != null) {
        throw envelopeFailure(decoded, response.headers);
      }
      final data = decoded is Map ? decoded['data'] : null;
      final endpoints = data is Map ? data['endpoints'] : null;
      if (endpoints is! List) {
        throw AppFailure(
          FailureKind.schema,
          'Endpoint metadata has changed.',
          field: r'$.data.endpoints',
          expected: 'array',
          actual: endpoints.runtimeType.toString(),
        );
      }
      final descriptions = <String>[];
      for (final endpoint in endpoints.take(20)) {
        if (endpoint is! Map) continue;
        final name = endpoint['provider_name'];
        if (name is! String) continue;
        final parts = <String>[name];
        final uptime = endpoint['uptime_last_30m'];
        if (uptime is num) {
          parts.add('${uptime.toStringAsFixed(1)}% uptime / 30m');
        }
        final statusCode = endpoint['status'];
        if (statusCode is num || statusCode is String) {
          parts.add('reported status $statusCode');
        }
        final pricing = endpoint['pricing'];
        if (pricing is Map) {
          final request = pricing['request'];
          parts.add(
            request == null
                ? 'request price not provided'
                : 'request price $request',
          );
        }
        descriptions.add(parts.join(' · '));
      }
      diagnostics.record(
        'health.endpoints',
        model: model.id,
        status: status,
        duration: watch.elapsed,
        note:
            '${endpoints.length} endpoint records; metadata is not inference health.',
      );
      final summary = descriptions.isEmpty
          ? '${endpoints.length} endpoint records; no provider detail available.'
          : descriptions.join('\n');
      _endpointCache[model.id] = (at: _now(), summary: summary);
      return summary;
    } catch (error) {
      if (_disposed) rethrow;
      final failure = AppFailure.from(error);
      diagnostics.record(
        'health.endpoints',
        model: model.id,
        status: status ?? failure.status,
        duration: watch.elapsed,
        failure: failure,
      );
      // Metadata is supplementary. A guarded inference can still verify a
      // model when metadata is absent or has changed. Account/rate limits and
      // cancellation must stop the sequence, however.
      if ({
        FailureKind.authentication,
        FailureKind.account,
        FailureKind.rateLimit,
        FailureKind.cancelled,
        FailureKind.offline,
        FailureKind.network,
      }.contains(failure.kind)) {
        rethrow;
      }
      return 'Endpoint metadata unavailable. See diagnostics.';
    }
  }

  void recordSuccess(String id, {String? provider, String? endpointSummary}) {
    _failures.remove(id);
    _set(
      id,
      HealthObservation(
        status: HealthStatus.responsive,
        checkedAt: _now(),
        message: 'Recently responsive. The next request can still fail.',
        provider: provider,
        endpointSummary: endpointSummary ?? forModel(id).endpointSummary,
      ),
    );
  }

  void recordFailure(String id, AppFailure failure, {String? endpointSummary}) {
    final current = forModel(id);
    final now = _now();
    final isCancellation = failure.kind == FailureKind.cancelled;
    final count = isCancellation ? 0 : (_failures[id] ?? 0) + 1;
    if (!isCancellation) _failures[id] = count;
    final exponential = math
        .min(
          config.maxBackoff.inMilliseconds,
          config.cooldown.inMilliseconds * math.pow(2, math.min(count - 1, 10)),
        )
        .toInt();
    // An explicit server Retry-After is a minimum, even when it exceeds our
    // locally configured maximum exponential backoff.
    final backoff = math.max(
      exponential,
      failure.retryAfter?.inMilliseconds ?? 0,
    );
    final retryAt = isCancellation
        ? null
        : now.add(Duration(milliseconds: backoff));
    var status = HealthStatus.unknown;
    if (failure.kind == FailureKind.rateLimit) {
      status = HealthStatus.rateLimited;
      _globalRetryAt = _later(_globalRetryAt, retryAt);
    } else if (failure.kind == FailureKind.provider) {
      status = failure.status == 404 || failure.status == 503
          ? HealthStatus.unavailable
          : HealthStatus.degraded;
    } else if ({
      FailureKind.timeout,
      FailureKind.stream,
      FailureKind.parsing,
      FailureKind.schema,
    }.contains(failure.kind)) {
      status = HealthStatus.degraded;
    } else if (failure.kind == FailureKind.http && failure.status == 404) {
      status = HealthStatus.unavailable;
    }
    _set(
      id,
      HealthObservation(
        status: status,
        checkedAt: now,
        message: failure.message,
        failure: failure,
        retryAt: retryAt,
        provider: failure.provider ?? current.provider,
        endpointSummary: endpointSummary ?? current.endpointSummary,
      ),
    );
  }

  void _set(String id, HealthObservation observation) {
    if (_disposed) return;
    // Bound observations even when a long-lived session explores many models.
    if (_observations.length >= 200 && !_observations.containsKey(id)) {
      final oldest = _observations.keys.first;
      _observations.remove(oldest);
      _failures.remove(oldest);
      _lastAttempt.remove(oldest);
      _endpointCache.remove(oldest);
      _modalities.remove(oldest);
      _signatures.remove(oldest);
    }
    _observations[id] = observation;
    if (observation.status != HealthStatus.checking) _saveCache();
    notifyListeners();
  }

  String get _scope {
    // This non-secret cache discriminator prevents observations crossing API,
    // key or policy changes. It is not an authentication/security primitive.
    final value =
        '${config.apiBaseUrl}|${config.apiKey}|${config.healthTtl}|${config.endpointTtl}|${config.quotaTtl}|${config.cooldown}|${config.maxBackoff}|${config.probeTimeout}';
    var hash = 0;
    for (final char in value.codeUnits) {
      hash = ((hash * 31) + char) & 0x7fffffff;
    }
    return hash.toRadixString(36);
  }

  Map<String, dynamic> _encodeObservation(HealthObservation value) => {
    'status': value.status.name,
    'checkedAt': value.checkedAt?.toUtc().toIso8601String(),
    'provider': value.provider,
    'retryAt': value.retryAt?.toUtc().toIso8601String(),
    'endpointSummary': value.endpointSummary,
    if (value.failure != null) 'failureKind': value.failure!.kind.name,
  };

  HealthObservation? _decodeObservation(Object? raw) {
    if (raw is! Map) return null;
    DateTime? date(String key) =>
        raw[key] is String ? DateTime.tryParse(raw[key] as String) : null;
    final checked = date('checkedAt'), retry = date('retryAt');
    final status = HealthStatus.values
        .where((s) => s.name == raw['status'])
        .firstOrNull;
    if (status == null ||
        status == HealthStatus.checking ||
        checked == null ||
        _now().isBefore(checked) ||
        _now().difference(checked) > const Duration(days: 30)) {
      return null;
    }
    final kind = FailureKind.values
        .where((k) => k.name == raw['failureKind'])
        .firstOrNull;
    return HealthObservation(
      status: status,
      checkedAt: checked,
      retryAt: retry,
      provider: raw['provider'] is String ? raw['provider'] as String : null,
      endpointSummary: raw['endpointSummary'] is String
          ? raw['endpointSummary'] as String
          : null,
      message: status == HealthStatus.responsive
          ? 'Recent saved inference observation. The next request can still fail.'
          : 'Saved ${status.name} observation; recheck after any cooldown.',
      failure: kind == null
          ? null
          : AppFailure(
              kind,
              'A previous ${kind.name} observation is still cooling down.',
              retryable: true,
            ),
    );
  }

  void _loadCache() {
    try {
      final saved = store?.read(_cacheKey);
      if (saved == null) return;
      if (saved.length > 500000) {
        throw const FormatException('Health cache too large');
      }
      final data = jsonDecode(saved);
      if (data is! Map || data['version'] != 2 || data['scope'] != _scope) {
        return;
      }
      final savedAt = data['savedAt'] is String
          ? DateTime.tryParse(data['savedAt'] as String)
          : null;
      if (savedAt == null || _now().isBefore(savedAt)) return;
      final global = data['globalRetryAt'];
      if (global is String) {
        final date = DateTime.tryParse(global);
        if (date != null &&
            _now().isBefore(date) &&
            date.difference(_now()) <= const Duration(days: 30)) {
          _globalRetryAt = date;
        }
      }
      final quotaRetry = data['quotaRetryAt'];
      if (quotaRetry is String) {
        final date = DateTime.tryParse(quotaRetry);
        if (date != null &&
            _now().isBefore(date) &&
            date.difference(_now()) <= const Duration(days: 30)) {
          _quotaRetryAt = date;
        }
      }
      quota = QuotaSnapshot.fromJson(data['quota']);
      if (quota != null && _now().isBefore(quota!.checkedAt)) quota = null;
      final entries = data['models'];
      if (entries is! List) return;
      for (final item in entries.take(200)) {
        if (item is! Map ||
            item['id'] is! String ||
            item['signature'] is! String) {
          continue;
        }
        final id = item['id'] as String;
        final observation = _decodeObservation(item['observation']);
        if (observation == null) continue;
        _observations[id] = observation;
        _signatures[id] = item['signature'] as String;
        if (item['failures'] is int && (item['failures'] as int) >= 0) {
          _failures[id] = math.min(item['failures'] as int, 30);
        }
        final endpoint = item['endpoint'];
        if (endpoint is Map &&
            endpoint['at'] is String &&
            endpoint['summary'] is String) {
          final at = DateTime.tryParse(endpoint['at'] as String);
          if (at != null &&
              !_now().isBefore(at) &&
              _now().difference(at) < config.endpointTtl) {
            _endpointCache[id] = (
              at: at,
              summary: endpoint['summary'] as String,
            );
          }
        }
        final modalities = item['modalities'];
        if (modalities is Map) {
          for (final key in ['text', 'image', 'audio', 'video', 'pdf']) {
            final result = _decodeObservation(modalities[key]);
            if (result != null) {
              _modalities.putIfAbsent(id, () => {})[key] = result;
            }
          }
        }
      }
    } catch (error) {
      diagnostics.record(
        'health.cache.read',
        failure: AppFailure(
          FailureKind.storage,
          'Saved health observations could not be restored; checks will run when needed.',
          details: error.runtimeType.toString(),
        ),
      );
    }
  }

  void _saveCache() {
    if (store == null || _disposed || config.apiKey.trim().isEmpty) return;
    try {
      final encoded = jsonEncode({
        'version': 2,
        'scope': _scope,
        'savedAt': _now().toUtc().toIso8601String(),
        'globalRetryAt': _globalRetryAt?.toUtc().toIso8601String(),
        'quotaRetryAt': _quotaRetryAt?.toUtc().toIso8601String(),
        'quota': quota?.toJson(),
        'models': [
          for (final entry in _observations.entries)
            if (_signatures.containsKey(entry.key) &&
                entry.value.status != HealthStatus.checking)
              {
                'id': entry.key,
                'signature': _signatures[entry.key],
                'observation': _encodeObservation(entry.value),
                'failures': _failures[entry.key],
                if (_endpointCache[entry.key] case final endpoint?)
                  'endpoint': {
                    'at': endpoint.at.toUtc().toIso8601String(),
                    'summary': endpoint.summary,
                  },
                'modalities': {
                  for (final result
                      in (_modalities[entry.key] ??
                              <String, HealthObservation>{})
                          .entries)
                    result.key: _encodeObservation(result.value),
                },
              },
        ],
      });
      if (encoded.length <= 500000) store!.write(_cacheKey, encoded);
    } catch (error) {
      diagnostics.record(
        'health.cache.write',
        failure: AppFailure(
          FailureKind.storage,
          'Health observations remain in memory because their cache could not be saved.',
          details: error.runtimeType.toString(),
        ),
      );
    }
  }

  DateTime? _later(DateTime? a, DateTime? b) => a == null
      ? b
      : b == null || a.isAfter(b)
      ? a
      : b;

  /// Stop manual probes as well as chat-owned preflight when going offline.
  /// Observations remain inspectable and no check resumes automatically.
  void cancelChecks({String? exceptModelId}) {
    for (final entry in _tokens.entries) {
      if (entry.value != exceptModelId) entry.key.cancel();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    cancelChecks();
    _quotaToken?.cancel();
    _tokens.clear();
    super.dispose();
  }
}
