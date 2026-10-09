import 'dart:async';
import 'dart:convert';

import '../../shared/diagnostics.dart';
import '../../shared/transport.dart';
import '../chat/sse.dart';

/// Connection secrets are deliberately omitted from serialization and diagnostics.
class McpConnection {
  McpConnection({
    required this.id,
    required this.name,
    required String url,
    this.bearerToken = '',
  }) : uri = _endpoint(url) {
    if (id.isEmpty ||
        id.length > 128 ||
        name.isEmpty ||
        name.length > 128 ||
        bearerToken.contains(RegExp(r'[\r\n]'))) {
      throw const AppFailure(
        FailureKind.configuration,
        'Invalid MCP connection settings.',
      );
    }
  }
  final String id;
  final String name;
  final Uri uri;
  final String bearerToken;
  String get url => uri.toString();
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'url': url};

  static Uri _endpoint(String value) {
    final uri = Uri.tryParse(value);
    final host = uri?.host.toLowerCase();
    final loopback = host == 'localhost' || host == '127.0.0.1';
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.hasQuery ||
        !(uri.scheme == 'https' || (uri.scheme == 'http' && loopback))) {
      throw const AppFailure(
        FailureKind.configuration,
        'Use an HTTPS MCP endpoint, or HTTP on localhost or 127.0.0.1. Credentials belong in the token field, not the URL.',
      );
    }
    return uri;
  }
}

class McpTool {
  const McpTool({
    required this.name,
    required this.description,
    required this.inputSchema,
  });
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;
  factory McpTool.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['name'] is! String ||
        (value['name'] as String).isEmpty ||
        (value['name'] as String).length > 256 ||
        value['inputSchema'] is! Map<String, dynamic> ||
        value['inputSchema']['type'] != 'object' ||
        (value['description'] != null && value['description'] is! String)) {
      throw const AppFailure(
        FailureKind.schema,
        'The MCP server returned an invalid tool definition.',
      );
    }
    return McpTool(
      name: value['name'] as String,
      description: value['description'] as String? ?? '',
      inputSchema: Map.unmodifiable(
        value['inputSchema'] as Map<String, dynamic>,
      ),
    );
  }
}

/// Browser-compatible Streamable HTTP. Never retries an action after dispatch.
/// Unsupported sampling, elicitation and legacy SSE are not silently enabled.
class McpClient {
  McpClient(
    this.transport,
    this.connection, {
    this.timeout = const Duration(seconds: 45),
    this.maxResponseBytes = 1024 * 1024,
  });
  final ApiTransport transport;
  final McpConnection connection;
  final Duration timeout;
  final int maxResponseBytes;
  static const supportedVersions = {'2025-11-25', '2025-06-18', '2025-03-26'};
  String? _sessionId;
  String? _version;
  bool _ready = false;
  int _sequence = 0;
  bool get initialized => _ready;
  String? get protocolVersion => _version;

  Future<void> initialize({required CancelToken cancel}) async {
    _ready = false;
    _sessionId = null;
    _version = null;
    final result = await _request('initialize', {
      'protocolVersion': '2025-11-25',
      'capabilities': <String, dynamic>{},
      'clientInfo': {'name': 'wfform', 'version': '1'},
    }, cancel: cancel);
    final version = result['protocolVersion'];
    if (version is! String || !supportedVersions.contains(version)) {
      throw const AppFailure(
        FailureKind.configuration,
        'This MCP protocol version is unsupported. Use a Streamable HTTP server supporting 2025-11-25, 2025-06-18 or 2025-03-26.',
      );
    }
    if (result['capabilities'] is! Map ||
        result['capabilities']['tools'] is! Map) {
      throw const AppFailure(
        FailureKind.configuration,
        'This MCP server does not advertise tools.',
      );
    }
    _version = version;
    await _notify('notifications/initialized', const {}, cancel: cancel);
    _ready = true;
  }

  Future<List<McpTool>> listTools({required CancelToken cancel}) async {
    _requireReady();
    final tools = <McpTool>[];
    final cursors = <String>{};
    String? cursor;
    do {
      final result = await _request('tools/list', {
        'cursor': ?cursor,
      }, cancel: cancel);
      final list = result['tools'];
      if (list is! List) {
        throw const AppFailure(
          FailureKind.schema,
          'The MCP server returned an invalid tools list.',
        );
      }
      tools.addAll(list.map(McpTool.fromJson));
      if (tools.length > 128 || cursors.length > 20) {
        throw const AppFailure(
          FailureKind.configuration,
          'The MCP server exceeds the limit of 128 tools or 20 pages.',
        );
      }
      final next = result['nextCursor'];
      if (next != null &&
          (next is! String || next.isEmpty || !cursors.add(next))) {
        throw const AppFailure(
          FailureKind.schema,
          'The MCP server returned invalid pagination.',
        );
      }
      cursor = next as String?;
    } while (cursor != null);
    if (tools.map((tool) => tool.name).toSet().length != tools.length) {
      throw const AppFailure(
        FailureKind.schema,
        'The MCP server returned duplicate tool names.',
      );
    }
    return List.unmodifiable(tools);
  }

  Future<Map<String, dynamic>> callTool(
    String name,
    Map<String, dynamic> arguments, {
    required CancelToken cancel,
  }) async {
    _requireReady();
    return _request('tools/call', {
      'name': name,
      'arguments': arguments,
    }, cancel: cancel);
  }

  /// Session deletion is best effort: unsupported DELETE never replays a call.
  Future<void> close() async {
    _ready = false;
    if (_sessionId == null) return;
    final headers = _headers;
    _sessionId = null;
    final cancel = CancelToken();
    final timer = Timer(const Duration(seconds: 2), cancel.cancel);
    try {
      final response = await transport.send(
        'DELETE',
        connection.uri,
        headers: headers,
        timeout: const Duration(seconds: 2),
        cancel: cancel,
      );
      await response.readText(maxBytes: 4096);
    } catch (_) {
      // A server may not support DELETE or may already have expired the session.
    } finally {
      timer.cancel();
      cancel.cancel();
    }
  }

  void _requireReady() {
    if (!_ready) {
      throw const AppFailure(
        FailureKind.configuration,
        'Connect this MCP server before using its tools.',
      );
    }
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json, text/event-stream',
    if (connection.bearerToken.isNotEmpty)
      'Authorization': 'Bearer ${connection.bearerToken}',
    'MCP-Session-Id': ?_sessionId,
    'MCP-Protocol-Version': ?_version,
  };

  Future<void> _notify(
    String method,
    Map<String, dynamic> params, {
    required CancelToken cancel,
    Duration? timeoutOverride,
  }) async {
    final response = await transport.send(
      'POST',
      connection.uri,
      headers: _headers,
      body: jsonEncode({'jsonrpc': '2.0', 'method': method, 'params': params}),
      timeout: timeoutOverride ?? timeout,
      cancel: cancel,
    );
    await response.readText(maxBytes: maxResponseBytes);
    if (response.status != 202 && response.status != 204) {
      throw _httpFailure(response.status);
    }
  }

  Future<Map<String, dynamic>> _request(
    String method,
    Map<String, dynamic> params, {
    required CancelToken cancel,
  }) async {
    cancel.throwIfCancelled();
    final id = ++_sequence;
    final local = CancelToken();
    var dispatched = false;
    var finished = false;
    var cancellationSent = false;
    void stop() {
      local.cancel();
      if (method != 'tools/call' ||
          !dispatched ||
          finished ||
          cancellationSent) {
        return;
      }
      cancellationSent = true;
      // Aborting HTTP alone is not an MCP cancellation. This independent,
      // bounded notification is best effort and never reissues tools/call.
      unawaited(
        _notify(
          'notifications/cancelled',
          {'requestId': id},
          cancel: CancelToken(),
          timeoutOverride: const Duration(seconds: 2),
        ).catchError((Object _) {}),
      );
    }

    final unlink = cancel.listen(stop);
    final timer = Timer(timeout, stop);
    try {
      dispatched = true;
      final response = await transport.send(
        'POST',
        connection.uri,
        headers: _headers,
        body: jsonEncode({
          'jsonrpc': '2.0',
          'id': id,
          'method': method,
          'params': params,
        }),
        timeout: timeout,
        cancel: local,
      );
      if (response.status < 200 || response.status >= 300) {
        await response.readText(maxBytes: maxResponseBytes);
        if (response.status == 404) _ready = false;
        throw _httpFailure(response.status);
      }
      if (method == 'initialize') {
        final session = response.headers['mcp-session-id'];
        if (session != null &&
            (!RegExp(r'^[\x21-\x7e]{1,1024}$').hasMatch(session))) {
          throw const AppFailure(
            FailureKind.schema,
            'Invalid MCP session header.',
          );
        }
        _sessionId = session;
      }
      final type = response.headers['content-type']?.toLowerCase() ?? '';
      if (type.contains('application/json')) {
        return _result(
          _decode(await response.readText(maxBytes: maxResponseBytes)),
          id,
        );
      }
      if (!type.contains('text/event-stream')) {
        throw const AppFailure(
          FailureKind.schema,
          'MCP requires JSON or Streamable HTTP event-stream responses.',
        );
      }
      var bytes = 0;
      final bounded = response.body.map((chunk) {
        bytes += chunk.length;
        if (bytes > maxResponseBytes) {
          throw const AppFailure(
            FailureKind.schema,
            'MCP response exceeds the local size limit.',
          );
        }
        return chunk;
      });
      await for (final event in decodeSse(
        bounded,
        cancel: local,
        maxEventChars: maxResponseBytes,
      )) {
        if (event.isEmpty) continue;
        final object = _decode(event);
        if (object.containsKey('id') && object['method'] == null) {
          return _result(object, id);
        }
        if (object['method'] is String && !object.containsKey('id')) continue;
        // We advertise no client capabilities. Never execute server-supplied requests.
        throw const AppFailure(
          FailureKind.configuration,
          'The MCP server requested an unsupported client capability.',
        );
      }
      throw const AppFailure(
        FailureKind.stream,
        'The MCP connection ended before its result. Execution may have completed; it will not be retried automatically.',
      );
    } on FormatException {
      throw const AppFailure(
        FailureKind.parsing,
        'The MCP server returned malformed JSON.',
      );
    } finally {
      finished = true;
      timer.cancel();
      unlink();
      local.cancel();
    }
  }

  static Map<String, dynamic> _decode(String value) {
    final object = jsonDecode(value);
    if (object is! Map<String, dynamic> || object['jsonrpc'] != '2.0') {
      throw const AppFailure(
        FailureKind.schema,
        'The MCP server returned an invalid JSON-RPC response.',
      );
    }
    return object;
  }

  static Map<String, dynamic> _result(Map<String, dynamic> object, int id) {
    if (object['id'] != id) {
      throw const AppFailure(
        FailureKind.schema,
        'The MCP response did not match the requested operation.',
      );
    }
    if (object['error'] != null) {
      throw const AppFailure(
        FailureKind.provider,
        'The MCP server rejected the operation. Check the server configuration and permissions.',
      );
    }
    if (object['result'] is! Map<String, dynamic>) {
      throw const AppFailure(
        FailureKind.schema,
        'The MCP response has no valid result.',
      );
    }
    return object['result'] as Map<String, dynamic>;
  }

  static AppFailure _httpFailure(int status) => AppFailure(
    status == 401 || status == 403
        ? FailureKind.authentication
        : FailureKind.provider,
    status == 401 || status == 403
        ? 'MCP authentication or access failed. Check this connection’s token and allowed browser origin.'
        : status == 404
        ? 'The MCP endpoint or session expired. Reconnect explicitly; a dispatched tool will not be retried.'
        : 'The MCP server rejected the request (HTTP $status).',
    status: status,
  );
}
