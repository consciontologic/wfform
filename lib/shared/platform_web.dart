import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'platform.dart';
import 'diagnostics.dart';

LocalStore createStore() => BrowserStore();
LocalStore createSessionStore() => BrowserSessionStore();
PlatformBridge createBridge() => BrowserPlatformBridge();

class BrowserStore implements LocalStore {
  @override
  String? read(String key) => web.window.localStorage.getItem(key);
  @override
  void write(String key, String value) =>
      web.window.localStorage.setItem(key, value);
  @override
  void remove(String key) => web.window.localStorage.removeItem(key);
}

extension type _InstallEvent(JSObject _) implements web.Event {
  external JSPromise<JSAny?> prompt();
}

class BrowserSessionStore implements LocalStore {
  @override
  String? read(String key) => web.window.sessionStorage.getItem(key);
  @override
  void write(String key, String value) =>
      web.window.sessionStorage.setItem(key, value);
  @override
  void remove(String key) => web.window.sessionStorage.removeItem(key);
}

class BrowserPlatformBridge extends PlatformBridge {
  bool _online = web.window.navigator.onLine;
  bool _updateAvailable = false;
  bool _disposed = false;
  bool _initialized = false;
  String? _pwaError;
  _InstallEvent? _installEvent;
  web.ServiceWorkerRegistration? _registration;
  Completer<void>? _activation;
  final List<void Function()> _removeListeners = [];

  @override
  bool get online => _online;
  @override
  bool get updateAvailable => _updateAvailable;
  @override
  bool get installAvailable => _installEvent != null;
  @override
  String? get pwaError => _pwaError;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _listen(
    web.EventTarget target,
    String name,
    void Function(web.Event) fn,
  ) {
    final listener = fn.toJS;
    target.addEventListener(name, listener);
    _removeListeners.add(() => target.removeEventListener(name, listener));
  }

  void _failure(String operation, Object error) {
    _pwaError = '$operation: $error';
    _notify();
  }

  @override
  Future<void> initialize() async {
    if (_initialized || _disposed) return;
    _initialized = true;
    for (final event in ['online', 'offline']) {
      _listen(web.window, event, (_) {
        _online = web.window.navigator.onLine;
        _notify();
      });
    }
    _listen(web.window, 'beforeinstallprompt', (event) {
      event.preventDefault();
      _installEvent = _InstallEvent(event);
      _notify();
    });
    _listen(web.window, 'appinstalled', (_) {
      _installEvent = null;
      _notify();
    });
    // Flutter development serving does not produce the release precache list.
    if (!kReleaseMode) return;
    try {
      final container = web.window.navigator.serviceWorker;
      _listen(container, 'controllerchange', (_) {
        final activation = _activation;
        if (activation != null && !activation.isCompleted) {
          activation.complete();
        }
      });
      _listen(container, 'message', (event) {
        final message = (event as web.MessageEvent).data.dartify();
        if (message is Map && message['type'] == 'PWA_ERROR') {
          _failure('Offline cache', message['message'] ?? 'Unknown error');
        }
      });
      final registration = await container
          .register(
            'service_worker.js'.toJS,
            web.RegistrationOptions(updateViaCache: 'none'),
          )
          .toDart
          .timeout(const Duration(seconds: 20));
      if (_disposed) return;
      _registration = registration;
      _updateAvailable = registration.waiting != null;
      _listen(registration, 'updatefound', (_) {
        final worker = registration.installing;
        if (worker == null) return;
        _listen(worker, 'statechange', (_) {
          if (worker.state == 'installed') {
            _updateAvailable =
                registration.waiting != null && container.controller != null;
            _notify();
          } else if (worker.state == 'redundant') {
            _failure(
              'Offline cache',
              'Worker installation failed. '
                  'Check network access, storage quota, and static asset URLs.',
            );
          }
        });
      });
      _notify();
    } catch (error) {
      _failure('PWA registration', error);
    }
  }

  @override
  Future<void> checkForUpdate() async {
    try {
      await _registration?.update().toDart.timeout(const Duration(seconds: 20));
      _updateAvailable = _registration?.waiting != null;
      _pwaError = null;
      _notify();
    } catch (error) {
      _failure('Update check', error);
    }
  }

  @override
  Future<void> applyUpdate() async {
    final waiting = _registration?.waiting;
    if (waiting == null) return;
    try {
      _activation = Completer<void>();
      waiting.postMessage({'type': 'APPLY_UPDATE'}.jsify());
      await _activation!.future.timeout(const Duration(seconds: 15));
      if (!_disposed) web.window.location.reload();
    } catch (error) {
      _failure('Update activation', error);
    } finally {
      _activation = null;
    }
  }

  @override
  Future<void> install() async {
    final event = _installEvent;
    if (event == null) return;
    try {
      await event.prompt().toDart;
      _installEvent = null;
      _notify();
    } catch (error) {
      _failure('Installation prompt', error);
    }
  }

  @override
  Future<Map<String, Object?>> inspectPwa() async {
    final result = <String, Object?>{
      'inspectedAt': DateTime.now().toUtc().toIso8601String(),
      'secureContext': web.window.isSecureContext,
      'onlineHint': web.window.navigator.onLine,
      'installPromptAvailable': installAvailable,
      'privacy':
          'Metadata only; no response bodies, header values or URL queries.',
    };
    final supportsWorkers = web.window.navigator
        .hasProperty('serviceWorker'.toJS)
        .toDart;
    result['serviceWorkerSupported'] = supportsWorkers;
    Map<String, Object?>? workerInfo(web.ServiceWorker? worker) =>
        worker == null
        ? null
        : {
            'scriptPath': Uri.tryParse(worker.scriptURL)?.path,
            'state': worker.state,
          };
    if (supportsWorkers) {
      try {
        final container = web.window.navigator.serviceWorker;
        final registration = await container.getRegistration().toDart.timeout(
          const Duration(seconds: 5),
        );
        result['controller'] = workerInfo(container.controller);
        result['registrationActive'] = workerInfo(registration?.active);
        result['registrationWaiting'] = workerInfo(registration?.waiting);
        result['registrationInstalling'] = workerInfo(registration?.installing);
      } catch (error) {
        result['workerInspectionError'] =
            'Inspection failed (${error.runtimeType}).';
      }
    }
    final supportsCaches = web.window.hasProperty('caches'.toJS).toDart;
    result['cacheStorageSupported'] = supportsCaches;
    if (supportsCaches) {
      try {
        final storage = web.window.caches;
        final names =
            (await storage.keys().toDart.timeout(const Duration(seconds: 5)))
                .toDart
                .map((name) => name.toDart)
                .where((name) => name.startsWith('free-model-studio-'))
                .toList();
        final generations = <Map<String, Object?>>[];
        final installs = <Map<String, Object?>>[];
        var totalEntries = 0, configEntries = 0, apiEntries = 0;
        var authorizationEntries = 0, queryEntries = 0, crossOriginEntries = 0;
        var violations = 0;
        // Expected population is two generations. Bound inspection of damaged storage.
        for (final name in names.reversed.take(10)) {
          final cache = await storage
              .open(name)
              .toDart
              .timeout(const Duration(seconds: 5));
          final requests = (await cache.keys().toDart.timeout(
            const Duration(seconds: 5),
          )).toDart;
          totalEntries += requests.length;
          for (final request in requests.take(5000)) {
            final uri = Uri.tryParse(request.url);
            final configuration =
                uri != null && RegExp(r'(^|/)config(?:/|$)').hasMatch(uri.path);
            final api =
                uri != null &&
                (uri.host == 'openrouter.ai' ||
                    RegExp(r'(^|/)api(?:/|$)').hasMatch(uri.path));
            final authorization = request.headers.has('authorization');
            final query = uri?.hasQuery ?? false;
            final crossOrigin =
                uri != null &&
                (!const {'http', 'https'}.contains(uri.scheme) ||
                    uri.origin != Uri.base.origin);
            if (configuration) configEntries++;
            if (api) apiEntries++;
            if (authorization) authorizationEntries++;
            if (query) queryEntries++;
            if (crossOrigin) crossOriginEntries++;
            if (configuration || api || authorization || query || crossOrigin) {
              violations++;
            }
            // Only the generated shell completion marker contains these
            // counters. Never inspect application/API/cache response bodies.
            if (!crossOrigin &&
                uri != null &&
                RegExp(
                  r'/__releases/[a-f0-9]{64}/release\.json$',
                ).hasMatch(uri.path)) {
              final marker = await cache.match(request).toDart;
              if (marker != null) {
                final raw = (await marker.text().toDart).toDart;
                if (raw.length < 65536) {
                  final decoded = jsonDecode(raw);
                  if (decoded is Map && decoded['install'] is Map) {
                    final counts = decoded['install'] as Map;
                    installs.add({
                      'release': uri.path.split('/').reversed.skip(1).first,
                      for (final key in [
                        'reusedAssets',
                        'reusedBytes',
                        'fetchedAssets',
                        'fetchedBytes',
                      ])
                        if (counts[key] is int && (counts[key] as int) >= 0)
                          key: counts[key],
                    });
                  }
                }
              }
            }
          }
          generations.add({
            'name':
                RegExp(r'^free-model-studio-[a-z0-9-]{1,80}$').hasMatch(name)
                ? name
                : '[unexpected generation name omitted]',
            'entries': requests.length,
            if (requests.length > 5000) 'inspectionTruncated': true,
          });
        }
        result['cacheGenerations'] = generations;
        result['releaseInstallCounters'] = installs;
        result['cacheGenerationCount'] = names.length;
        result['cacheEntryCount'] = totalEntries;
        result['cacheViolationCount'] = violations;
        result['cachedConfigurationCount'] = configEntries;
        result['cachedApiCount'] = apiEntries;
        result['cachedAuthorizationCount'] = authorizationEntries;
        result['cachedQueryCount'] = queryEntries;
        result['cachedCrossOriginCount'] = crossOriginEntries;
        if (names.length > 10) result['cacheInspectionTruncated'] = true;
      } catch (error) {
        result['cacheInspectionError'] =
            'Inspection failed (${error.runtimeType}).';
      }
    }
    try {
      final entries = web.window.performance
          .getEntriesByType('resource')
          .toDart;
      var sameOrigin = 0,
          configuration = 0,
          catalog = 0,
          endpoints = 0,
          chat = 0;
      var otherOpenRouter = 0,
          scripts = 0,
          transfer = 0,
          encoded = 0,
          decoded = 0;
      final catalogTimings = <Map<String, Object?>>[];
      for (final entry in entries) {
        final uri = Uri.tryParse(entry.name);
        if (uri == null || !const {'http', 'https'}.contains(uri.scheme)) {
          continue;
        }
        if (uri.origin == Uri.base.origin) {
          sameOrigin++;
          if (RegExp(r'(^|/)config(?:/|$)').hasMatch(uri.path)) configuration++;
          if (uri.path.endsWith('.js')) {
            final timing = entry as web.PerformanceResourceTiming;
            scripts++;
            transfer += timing.transferSize;
            encoded += timing.encodedBodySize;
            decoded += timing.decodedBodySize;
          }
        }
        if (uri.host == 'openrouter.ai') {
          if (uri.path == '/api/v1/models') {
            catalog++;
            if (catalogTimings.length < 12) {
              final timing = entry as web.PerformanceResourceTiming;
              // Additive optional browser field; older engines/package:web
              // versions may not expose it. Never include URLs or query data.
              final rawStatus = timing
                  .getProperty<JSAny?>('responseStatus'.toJS)
                  ?.dartify();
              catalogTimings.add({
                'path': '/api/v1/models',
                'initiatorType': timing.initiatorType.length <= 40
                    ? timing.initiatorType
                    : 'unrecognized',
                'startTimeMs': (timing.startTime * 100).round() / 100,
                'durationMs': (timing.duration * 100).round() / 100,
                'responseStatus':
                    rawStatus is num && rawStatus >= 0 && rawStatus <= 599
                    ? rawStatus.toInt()
                    : null,
              });
            }
          } else if (uri.path.endsWith('/endpoints')) {
            endpoints++;
          } else if (uri.path == '/api/v1/chat/completions') {
            chat++;
          } else {
            otherOpenRouter++;
          }
        }
      }
      result['resources'] = {
        'window':
            'Since navigation; bounded browser timing buffer; excludes SW install requests.',
        'entries': entries.length,
        'sameOriginRequests': sameOrigin,
        'configurationRequests': configuration,
        'openRouterCatalogRequests': catalog,
        'catalogTimingEntries': catalogTimings,
        'catalogTimingTruncated': catalog > catalogTimings.length,
        'requestCountNote':
            'Counts are browser ResourceTiming entries, not an application transport counter. They include all matching entries since navigation; failed/cancelled requests may be present and responseStatus 0 can mean unavailable cross-origin timing.',
        'openRouterEndpointRequests': endpoints,
        'openRouterChatRequests': chat,
        'otherOpenRouterRequests': otherOpenRouter,
        'javascriptResources': scripts,
        'javascriptTransferBytes': transfer,
        'javascriptEncodedBodyBytes': encoded,
        'javascriptDecodedBodyBytes': decoded,
        'sizeNote':
            'Zero transfer can indicate cached delivery or unavailable timing data.',
      };
    } catch (error) {
      result['resourceInspectionError'] =
          'Inspection failed (${error.runtimeType}).';
    }
    return result;
  }

  @override
  Future<String?> importText({int maxBytes = 64 * 1024 * 1024}) async {
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..accept = '.json,application/json';
    input.style.display = 'none';
    web.document.body?.append(input);
    final result = Completer<String?>();
    final change = ((web.Event _) {
      final file = input.files?.item(0);
      if (file == null) {
        if (!result.isCompleted) result.complete(null);
        return;
      }
      if (file.size <= 0 || file.size > maxBytes) {
        if (!result.isCompleted) {
          result.completeError(
            const AppFailure(
              FailureKind.storage,
              'Choose a nonempty conversation export within the import size limit.',
            ),
          );
        }
        return;
      }
      file
          .text()
          .toDart
          .timeout(const Duration(seconds: 15))
          .then(
            (text) {
              if (!result.isCompleted) result.complete(text.toDart);
            },
            onError: (Object error) {
              if (!result.isCompleted) {
                result.completeError(
                  const AppFailure(
                    FailureKind.storage,
                    'The conversation export could not be read. Try choosing it again.',
                  ),
                );
              }
            },
          );
    }).toJS;
    final cancel = ((web.Event _) {
      if (!result.isCompleted) result.complete(null);
    }).toJS;
    input.addEventListener('change', change);
    input.addEventListener('cancel', cancel);
    try {
      input.click();
      return await result.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () => null,
      );
    } finally {
      input.removeEventListener('change', change);
      input.removeEventListener('cancel', cancel);
      input.remove();
    }
  }

  @override
  void openUrl(Uri url) {
    if (url.scheme != 'https' && url.scheme != 'http') {
      throw ArgumentError.value(url.scheme, 'url.scheme', 'Expected HTTP(S)');
    }
    final anchor = web.HTMLAnchorElement()
      ..href = url.toString()
      ..target = '_blank'
      ..rel = 'noopener noreferrer';
    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
  }

  @override
  void exportText(String filename, String content) {
    final blob = web.Blob(
      [content.toJS].toJS,
      web.BlobPropertyBag(type: 'application/json;charset=utf-8'),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = filename;
    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    // Give the browser its own event turn to begin the download.
    Timer(const Duration(seconds: 1), () => web.URL.revokeObjectURL(url));
  }

  @override
  void dispose() {
    _disposed = true;
    for (final remove in _removeListeners) {
      remove();
    }
    _removeListeners.clear();
    super.dispose();
  }
}
