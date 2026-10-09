import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../features/tools/mcp_client.dart';
import '../features/tools/tools.dart';
import '../shared/diagnostics.dart';
import '../shared/platform.dart';
import '../shared/transport.dart';

/// Saved endpoints are inert. Tokens and initialized clients live in memory only.
class ToolConnections extends ChangeNotifier {
  ToolConnections({
    required ApiTransport transport,
    required this.store,
    this.available = true,
  }) : registry = ToolRegistry(transport, available: available) {
    final raw = store.read(storageKey);
    if (raw == null) return;
    try {
      final value = jsonDecode(raw);
      if (value is! List || value.length > 32) throw const FormatException();
      for (final item in value) {
        if (item is! Map ||
            item['id'] is! String ||
            item['name'] is! String ||
            item['url'] is! String) {
          throw const FormatException();
        }
        final connection = McpConnection(
          id: item['id'],
          name: item['name'],
          url: item['url'],
        );
        _saved[connection.id] = connection;
      }
    } catch (_) {
      _saved.clear();
      error =
          'Saved tool connection settings could not be read. They have been retained unchanged.';
    }
  }
  static const storageKey = 'mcp.connections.v1';
  final LocalStore store;
  final bool available;
  final ToolRegistry registry;
  final _saved = <String, McpConnection>{};
  CancelToken? _pending;
  bool _disposed = false;
  String? error;
  List<McpConnection> get saved => List.unmodifiable(_saved.values);
  bool get busy => _pending != null;
  bool isConnected(String id) => registry.connections.any((c) => c.id == id);

  Future<bool> connect(McpConnection connection) async {
    if (busy || _disposed) return false;
    if (!available) {
      error = desktopToolsExplanation;
      notifyListeners();
      return false;
    }
    if (!_saved.containsKey(connection.id) && _saved.length >= 32) {
      error = 'Remove an unused connection before adding another (32 maximum).';
      notifyListeners();
      return false;
    }
    final cancel = _pending = CancelToken();
    error = null;
    notifyListeners();
    try {
      await registry.connect(connection, cancel: cancel);
      if (_disposed || cancel.isCancelled) return false;
      _saved[connection.id] = McpConnection(
        id: connection.id,
        name: connection.name,
        url: connection.url,
      );
      _save();
      return true;
    } catch (failure) {
      if (!_disposed) {
        error = failure is AppFailure
            ? failure.message
            : 'Could not connect to this MCP server. Check the endpoint, token and browser access settings.';
      }
      return false;
    } finally {
      _pending = null;
      if (!_disposed) notifyListeners();
    }
  }

  void cancel() => _pending?.cancel();
  void disconnect(String id) {
    registry.disconnect(id);
    if (!_disposed) notifyListeners();
  }

  void forget(String id) {
    registry.disconnect(id);
    _saved.remove(id);
    _save();
    notifyListeners();
  }

  void _save() {
    try {
      store.write(
        storageKey,
        jsonEncode(_saved.values.map((c) => c.toJson()).toList()),
      );
    } catch (_) {
      error =
          'Connected for this session, but these settings could not be saved.';
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _pending?.cancel();
    for (final connection in registry.connections) {
      registry.disconnect(connection.id);
    }
    super.dispose();
  }
}
