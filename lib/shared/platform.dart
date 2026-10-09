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
  /// Device capability, not viewport width. Compact desktop windows keep tools.
  bool get toolsAvailable => true;
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

  /// Open a user-activated link without replacing the current conversation.
  /// New platform adapters must provide their own external URL integration.
  void openUrl(Uri url) {
    throw UnsupportedError('Opening links requires a platform adapter.');
  }

  /// Leave for an information page in this browser tab, preserving tab-local
  /// recovery metadata. Caller must finish pending work and save drafts first.
  void navigateTo(Uri url) {
    throw UnsupportedError('Page navigation requires a platform adapter.');
  }

  /// A user-selected local text export; no network operation is performed.
  Future<String?> importText({int maxBytes = 64 * 1024 * 1024}) async => null;
}

PlatformBridge createPlatformBridge() => implementation.createBridge();

const desktopToolsExplanation =
    'Tools work on a desktop computer, where wfform can connect to MCP servers '
    'and wfformcomp. They are unavailable on phones and tablets. '
    'Chatting works as usual, and your saved tool settings stay ready for your next desktop session.';

/// iPadOS can advertise a Macintosh user agent in desktop browsing mode.
/// Chrome's desktop-mode Android tablets may advertise Linux instead. Touch-only
/// coarse input catches those; a touch laptop with a mouse/trackpad stays enabled.
bool browserSupportsTools({
  required String userAgent,
  required String platform,
  required int maxTouchPoints,
  bool primaryPointerCoarse = false,
  bool anyFinePointer = true,
}) {
  if (RegExp(
    r'Android|iPhone|iPad|iPod|Mobile|Tablet|Silk|Kindle|PlayBook',
    caseSensitive: false,
  ).hasMatch(userAgent)) {
    return false;
  }
  final mac =
      platform.toLowerCase().startsWith('mac') ||
      userAgent.contains('Macintosh');
  if (mac && maxTouchPoints > 1) return false;
  return !(maxTouchPoints > 0 && primaryPointerCoarse && !anyFinePointer);
}
