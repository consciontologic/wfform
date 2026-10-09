import 'dart:io';
import 'platform.dart';

LocalStore createStore() => MemoryStore();
LocalStore createSessionStore() => MemoryStore();
PlatformBridge createBridge() => StubPlatformBridge();

class StubPlatformBridge extends PlatformBridge {
  @override
  bool get toolsAvailable =>
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;
  @override
  bool get online => true;
  @override
  bool get updateAvailable => false;
  @override
  bool get installAvailable => false;
  @override
  String? get pwaError => null;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> checkForUpdate() async {}
  @override
  Future<void> applyUpdate() async {}
  @override
  Future<void> install() async {}
  @override
  void exportText(String filename, String content) {
    throw UnsupportedError('File export requires a platform adapter.');
  }
}
