import 'package:flutter/foundation.dart';

import 'platform_stub.dart'
    if (dart.library.js_interop) 'platform_web.dart'
    as implementation;

/// Synchronous small-value storage. Features own keys, formats and retention.
abstract class LocalStore {
  String? read(String key);
  void write(String key, String value);
  void remove(String key);
}

class MemoryStore implements LocalStore {
  final Map<String, String> _values = {};

  @override
  String? read(String key) => _values[key];
  @override
  void write(String key, String value) => _values[key] = value;
  @override
  void remove(String key) => _values.remove(key);
}

LocalStore createLocalStore() => implementation.createStore();
LocalStore createSessionStore() => implementation.createSessionStore();

/// Browser capabilities stay behind this interface for future platform ports.
abstract class PlatformBridge extends ChangeNotifier {
  bool get online;
  bool get updateAvailable;
  bool get installAvailable;
  String? get pwaError;
  Future<void> initialize();
  Future<void> checkForUpdate();

  /// Caller must persist drafts and finish/cancel requests before calling.
  Future<void> applyUpdate();
  Future<void> install();

  /// Metadata-only snapshot: never returns response content, credentials, or queries.
  Future<Map<String, Object?>> inspectPwa() async => {
    'supported': false,
    'reason': 'Browser cache inspection is unavailable on this platform.',
  };

  void exportText(String filename, String content);

  /// A user-selected local text export; no network operation is performed.
  Future<String?> importText({int maxBytes = 64 * 1024 * 1024}) async => null;
}

PlatformBridge createPlatformBridge() => implementation.createBridge();
