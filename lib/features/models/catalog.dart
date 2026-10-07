import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../config/app_config.dart';
import '../../shared/diagnostics.dart';
import '../../shared/platform.dart';
import '../../shared/transport.dart';
import 'model.dart';

class CatalogIssue {
  const CatalogIssue({
    required this.index,
    required this.failure,
    this.modelId,
  });
  final int index;
  final String? modelId;
  final AppFailure failure;
  String get message => failure.message;
  String? get field => failure.field;
  Map<String, dynamic> toJson() => {
    'index': index,
    'model': modelId,
    'field': failure.field,
    'expected': failure.expected,
    'actual': failure.actual,
    'message': failure.message,
  };
  @override
  String toString() => '${modelId ?? 'Entry $index'}: ${failure.message}';
}

class CatalogPage {
  const CatalogPage({
    required this.models,
    required this.issues,
    required this.exclusions,
    required this.entryCount,
    required this.validCount,
    this.unresolvedPricingCount = 0,
    this.totalCount,
    this.next,
  });
  final List<FreeModel> models;
  final List<CatalogIssue> issues;
  final Map<String, String> exclusions;
  final int entryCount;
  final int validCount;
  final int unresolvedPricingCount;
  final int? totalCount;
  final String? next;
}

/// Pure adapter. A valid empty `data` is different from an unrecognized schema
/// or a list where every entry failed parsing.
CatalogPage parseCatalog(
  Object? value, {
  int indexOffset = 0,
  bool allowAllInvalid = false,
}) {
  if (value is! Map<String, dynamic>) {
    throw schemaFailure(r'$', 'object containing data array', value);
  }
  if (value['error'] != null) {
    final envelope = value['error'];
    final status = envelope is Map ? envelope['code'] : null;
    throw AppFailure.http(
      status is int ? status : 502,
      body: jsonEncode({'error': envelope}),
    );
  }
  final data = value['data'];
  if (data is! List) throw schemaFailure(r'$.data', 'array', data);
  if (data.length > 10000) {
    throw AppFailure(
      FailureKind.schema,
      'The catalog exceeds the supported 10,000-entry safety limit.',
    );
  }
  final total = value['total_count'];
  if (total != null && (total is! int || total < 0)) {
    throw schemaFailure(r'$.total_count', 'nonnegative integer', total);
  }
  String? next;
  final links = value['links'];
  if (links != null) {
    if (links is! Map<String, dynamic>) {
      throw schemaFailure(r'$.links', 'object', links);
    }
    final rawNext = links['next'];
    if (rawNext != null && (rawNext is! String || rawNext.trim().isEmpty)) {
      throw schemaFailure(r'$.links.next', 'URL string or null', rawNext);
    }
    next = rawNext as String?;
  }
  final models = <FreeModel>[];
  final issues = <CatalogIssue>[];
  final exclusions = <String, String>{};
  var valid = 0;
  var unresolvedPricing = 0;
  final ids = <String>{};
  for (var i = 0; i < data.length; i++) {
    final item = data[i];
    final id = item is Map && item['id'] is String
        ? item['id'] as String
        : null;
    try {
      final parsed = parseModel(item, '\$.data[${indexOffset + i}]');
      if (!ids.add(parsed.id)) {
        throw AppFailure(
          FailureKind.schema,
          'Duplicate catalog model ID.',
          field: '\$.data[${indexOffset + i}].id',
          expected: 'unique ID',
          actual: parsed.id,
        );
      }
      valid++;
      if (parsed.model != null) {
        models.add(parsed.model!);
      } else {
        exclusions[parsed.id] = parsed.exclusionReason!;
        if (parsed.unresolvedPricing) unresolvedPricing++;
      }
    } catch (error) {
      final failure = AppFailure.from(error);
      issues.add(
        CatalogIssue(index: indexOffset + i, failure: failure, modelId: id),
      );
      if (id != null) {
        exclusions[id] =
            'Its catalog metadata could not be validated (${failure.field ?? 'schema'}).';
      }
    }
  }
  if (data.isNotEmpty && valid == 0 && !allowAllInvalid) {
    final first = issues.first.failure;
    throw AppFailure(
      FailureKind.schema,
      'Every catalog entry failed validation. The last valid catalog is retained. Review the catalog adapter and diagnostics.',
      field: first.field,
      expected: first.expected,
      actual: first.actual,
      details:
          '${issues.length} malformed entries. First error: ${first.message} ${first.details ?? ''}',
    );
  }
  return CatalogPage(
    models: models,
    issues: issues,
    exclusions: exclusions,
    entryCount: data.length,
    validCount: valid,
    unresolvedPricingCount: unresolvedPricing,
    totalCount: total as int?,
    next: next,
  );
}

class CatalogController extends ChangeNotifier {
  CatalogController({
    required this.config,
    required this.transport,
    required this.store,
    required this.diagnostics,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const cacheKey = 'free-model-studio.catalog.v1';
  static const selectionKey = 'free-model-studio.selection.v1';
  final AppConfig config;
  final ApiTransport transport;
  final LocalStore store;
  final Diagnostics diagnostics;
  final DateTime Function() _now;
  List<FreeModel> models = const [];
  List<CatalogIssue> issues = const [];
  int issueCount = 0;
  int unresolvedPricingCount = 0;
  int scannedCount = 0;
  int changedCount = 0;
  bool refreshing = false;
  bool fromCache = false;
  DateTime? lastSuccess;
  AppFailure? error;
  String? selectedId;
  String? selectionNotice;
  Future<void>? _inflight;
  CancelToken? _cancel;
  bool _initialized = false;
  bool _disposed = false;
  bool _refreshFailed = false;

  bool get stale =>
      lastSuccess != null &&
      (_refreshFailed || _now().difference(lastSuccess!) >= config.cacheTtl);

  FreeModel? get selected {
    for (final model in models) {
      if (model.id == selectedId && model.chatCompatible) return model;
    }
    return null;
  }

  void select(String id) {
    final candidate = models.where((model) => model.id == id).firstOrNull;
    if (candidate == null || !candidate.chatCompatible) {
      selectionNotice =
          candidate?.incompatibilityReason ??
          'That model is no longer in the free catalog. Refresh and select a valid model.';
      _notify();
      return;
    }
    selectedId = id;
    selectionNotice = null;
    _storeSelection();
    _notify();
  }

  void clearSelection({String? notice}) {
    selectedId = null;
    selectionNotice = notice;
    _storeSelection();
    _notify();
  }

  Future<void> initialize({bool refresh = true}) {
    if (_initialized) return _inflight ?? Future.value();
    _initialized = true;
    _loadCache();
    return refresh ? this.refresh() : Future.value();
  }

  Future<void> refresh() {
    if (_disposed) return Future.value();
    final existing = _inflight;
    if (existing != null) return existing;
    final work = _refresh();
    _inflight = work;
    return work.whenComplete(() => _inflight = null);
  }

  void _loadCache() {
    try {
      final encoded = store.read(cacheKey);
      selectedId = store.read(selectionKey);
      if (encoded == null) return;
      if (utf8.encode(encoded).length > config.maxCatalogBytes) {
        throw AppFailure(
          FailureKind.storage,
          'The saved catalog exceeds the configured cache size.',
        );
      }
      final saved = jsonDecode(encoded);
      if (saved is! Map<String, dynamic> ||
          saved['version'] != 1 ||
          saved['apiBaseUrl'] != config.apiBaseUrl ||
          saved['savedAt'] is! String) {
        throw AppFailure(
          FailureKind.storage,
          'The saved catalog uses an unsupported format or API source. Refresh to replace it.',
        );
      }
      final timestamp = DateTime.tryParse(saved['savedAt'] as String);
      if (timestamp == null ||
          timestamp.isAfter(_now().add(const Duration(minutes: 5)))) {
        throw AppFailure(
          FailureKind.storage,
          'The saved catalog has an invalid refresh timestamp.',
        );
      }
      final parsed = parseCatalog({'data': saved['models']});
      if (parsed.issues.isNotEmpty) {
        throw AppFailure(
          FailureKind.storage,
          'The saved catalog is partially malformed. Fetching a fresh copy.',
        );
      }
      models = List.unmodifiable(parsed.models);
      lastSuccess = timestamp;
      fromCache = true;
      _validateSelection(parsed.exclusions);
      _notify();
    } catch (problem) {
      diagnostics.record(
        'catalog.cache.read',
        failure: AppFailure.from(problem),
      );
    }
  }

  Future<void> _refresh() async {
    refreshing = true;
    error = null;
    _notify();
    final timer = Stopwatch()..start();
    final cancel = CancelToken();
    _cancel = cancel;
    try {
      final base = Uri.parse(
        '${config.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '')}/models',
      );
      Uri? uri = base.replace(queryParameters: {'output_modalities': 'all'});
      final visited = <String>{};
      final all = <FreeModel>[];
      final allIssues = <CatalogIssue>[];
      final exclusions = <String, String>{};
      final ids = <String>{};
      var scanned = 0;
      var validEntries = 0;
      var unresolvedPricing = 0;
      var bytes = 0;
      int? expectedTotal;
      while (uri != null) {
        cancel.throwIfCancelled();
        if (!visited.add(uri.toString()) || visited.length > 100) {
          throw AppFailure(
            FailureKind.schema,
            'Catalog pagination repeated or exceeded its 100-page safety limit.',
            field: r'$.links.next',
          );
        }
        final response = await transport.send(
          'GET',
          uri,
          headers: const {'Accept': 'application/json'},
          timeout: config.requestTimeout,
          cancel: cancel,
        );
        final body = await response.readText(
          maxBytes: config.maxCatalogBytes - bytes,
        );
        bytes += utf8.encode(body).length;
        if (response.status < 200 || response.status >= 300) {
          throw AppFailure.http(
            response.status,
            body: body,
            headers: response.headers,
          );
        }
        final Object? decoded;
        try {
          decoded = jsonDecode(body);
        } on FormatException {
          throw AppFailure(
            FailureKind.parsing,
            'The models API returned malformed JSON. The last valid catalog is retained.',
            status: response.status,
            field: r'$',
            expected: 'JSON object',
            actual: 'invalid JSON',
            details: body.length > 500 ? body.substring(0, 500) : body,
          );
        }
        final page = parseCatalog(
          decoded,
          indexOffset: scanned,
          allowAllInvalid: true,
        );
        validEntries += page.validCount;
        unresolvedPricing += page.unresolvedPricingCount;
        expectedTotal ??= page.totalCount;
        if (page.totalCount != null && expectedTotal != page.totalCount) {
          throw AppFailure(
            FailureKind.schema,
            'The catalog changed during pagination. Refresh again to get a consistent list.',
            field: r'$.total_count',
            retryable: true,
          );
        }
        scanned += page.entryCount;
        if (scanned > 10000) {
          throw AppFailure(
            FailureKind.schema,
            'The catalog exceeds the 10,000-entry safety limit.',
          );
        }
        for (final model in page.models) {
          if (!ids.add(model.id)) {
            throw AppFailure(
              FailureKind.schema,
              'A model repeated across catalog pages. Refresh again.',
              field: r'$.data[].id',
              retryable: true,
            );
          }
          all.add(model);
        }
        allIssues.addAll(page.issues);
        exclusions.addAll(page.exclusions);
        if (page.next == null) {
          uri = null;
        } else {
          final next = base.resolve(page.next!);
          if (next.origin != base.origin ||
              next.path != base.path ||
              next.userInfo.isNotEmpty ||
              next.fragment.isNotEmpty) {
            throw AppFailure(
              FailureKind.schema,
              'The API returned an unsafe or unrelated pagination URL.',
              field: r'$.links.next',
              expected: 'same-origin models endpoint',
              actual: 'different origin or path',
            );
          }
          uri = next.replace(
            queryParameters: {
              ...next.queryParameters,
              'output_modalities': 'all',
            },
          );
        }
      }
      if (expectedTotal != null && scanned != expectedTotal) {
        throw AppFailure(
          FailureKind.schema,
          'The catalog response is incomplete ($scanned entries for reported total $expectedTotal). The last valid catalog is retained.',
          field: r'$.total_count',
        );
      }
      if (scanned > 0 && validEntries == 0) {
        final first = allIssues.first.failure;
        throw AppFailure(
          FailureKind.schema,
          'Every catalog entry failed validation. The last valid catalog is retained. Review the catalog adapter and diagnostics.',
          field: first.field,
          expected: first.expected,
          actual: first.actual,
          details:
              '${allIssues.length} malformed entries. First error: ${first.message} ${first.details ?? ''}',
        );
      }
      if (_disposed || cancel.isCancelled) return;
      final previous = {for (final model in models) model.id: model.signature};
      final current = {for (final model in all) model.id: model.signature};
      changedCount = {
        ...previous.keys,
        ...current.keys,
      }.where((id) => previous[id] != current[id]).length;
      final oldSelected = selected;
      all.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      models = List.unmodifiable(all);
      // Counts are exact, details bounded; diagnostics also has its own bound.
      issueCount = allIssues.length;
      unresolvedPricingCount = unresolvedPricing;
      issues = List.unmodifiable(allIssues.take(100));
      scannedCount = scanned;
      lastSuccess = _now().toUtc();
      fromCache = false;
      _refreshFailed = false;
      _validateSelection(exclusions);
      if (oldSelected != null &&
          selected != null &&
          oldSelected.signature != selected!.signature) {
        selectedId = null;
        selectionNotice =
            'The selected model’s pricing or capabilities changed. Review the details and select it again before chatting.';
        _storeSelection();
      }
      _saveCache();
      for (final issue in issues) {
        diagnostics.record(
          'catalog.quarantine',
          model: issue.modelId,
          failure: issue.failure,
        );
      }
      diagnostics.record(
        'catalog.refresh',
        duration: timer.elapsed,
        status: 200,
        note:
            '$scanned entries inspected; ${models.length} free-price candidates; $unresolvedPricingCount excluded with unresolved pricing (-1); $issueCount quarantined; $changedCount changed; ${visited.length} pages.',
      );
    } catch (problem) {
      if (!_disposed && !cancel.isCancelled) {
        error = AppFailure.from(problem);
        _refreshFailed = true;
        diagnostics.record(
          'catalog.refresh',
          duration: timer.elapsed,
          failure: error,
        );
      }
    } finally {
      refreshing = false;
      _cancel = null;
      _notify();
    }
  }

  void _validateSelection(Map<String, String> exclusions) {
    final oldId = selectedId;
    if (oldId == null) return;
    final candidate = models.where((model) => model.id == oldId).firstOrNull;
    if (candidate == null || !candidate.chatCompatible) {
      selectedId = null;
      selectionNotice =
          '$oldId is no longer available for this chat. ${candidate?.incompatibilityReason ?? exclusions[oldId] ?? 'It disappeared from the current free-model catalog.'} Select a valid model to continue.';
      _storeSelection();
    }
  }

  void _saveCache() {
    try {
      final encoded = jsonEncode({
        'version': 1,
        'apiBaseUrl': config.apiBaseUrl,
        'savedAt': lastSuccess!.toIso8601String(),
        'models': models.map((model) => model.toJson()).toList(),
      });
      if (utf8.encode(encoded).length > config.maxCatalogBytes) {
        throw AppFailure(
          FailureKind.storage,
          'Catalog loaded into memory but exceeds the configured cache size.',
        );
      }
      store.write(cacheKey, encoded);
    } catch (problem) {
      diagnostics.record(
        'catalog.cache.write',
        failure: AppFailure.from(problem),
      );
    }
  }

  void _storeSelection() {
    try {
      final id = selectedId;
      if (id == null) {
        store.remove(selectionKey);
      } else {
        store.write(selectionKey, id);
      }
    } catch (problem) {
      diagnostics.record(
        'catalog.selection.write',
        failure: AppFailure.from(problem),
      );
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel?.cancel();
    super.dispose();
  }
}
