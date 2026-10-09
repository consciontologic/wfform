import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'wfformcomp.dart';
import 'process_group.dart';

/// An explicitly configured local stdio MCP server. The browser/model cannot
/// alter its executable, arguments, working directory, environment or allowlist.
class StdioServerConfig {
  StdioServerConfig.fromJson(Map<String, Object?> json)
    : name = textValue(json['name'], 'MCP server name'),
      executable = textValue(json['executable'], 'MCP executable'),
      arguments = strings(json['arguments'] ?? [], 'MCP arguments'),
      workingDirectory = json['workingDirectory'] as String?,
      environment =
          object(
            json['environment'] ?? <String, Object?>{},
            'MCP environment',
          ).map(
            (key, value) =>
                MapEntry(key, textValue(value, 'environment value')),
          ),
      allowedTools = strings(json['allowedTools'], 'allowedTools').toSet(),
      timeout = Duration(
        milliseconds: boundedInt(
          json['timeoutMs'],
          30000,
          100,
          120000,
          'MCP timeoutMs',
        ),
      ) {
    if (!RegExp(r'^[A-Za-z0-9_]{1,24}$').hasMatch(name)) {
      throw const FormatException('Invalid MCP server name.');
    }
    if (!File(executable).isAbsolute) {
      throw const FormatException('MCP executable must be an absolute path.');
    }
    if (allowedTools.isEmpty || allowedTools.length > 64) {
      throw const FormatException('Allow 1–64 explicit MCP tool names.');
    }
  }
  final String name;
  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String> environment;
  final Set<String> allowedTools;
  final Duration timeout;
}

class StdioMcp {
  StdioMcp._(this.config, this._process);
  final StdioServerConfig config;
  final Process _process;
  final _pending = <int, Completer<Map<String, Object?>>>{};
  final _tools = <String, Map<String, Object?>>{};
  final _subscriptions = <StreamSubscription<List<int>>>[];
  var _nextId = 0;
  var _closed = false;
  var _callActive = false;
  static Future<StdioMcp> start(StdioServerConfig config) async {
    final process = await startProgram(
      config.executable,
      config.arguments,
      workingDirectory: config.workingDirectory,
      environment: config.environment,
    );
    final bridge = StdioMcp._(config, process);
    bridge._listen();
    try {
      final initialized = await bridge._request('initialize', {
        'protocolVersion': supportedProtocols.first,
        'capabilities': <String, Object?>{},
        'clientInfo': {'name': 'wfformcomp', 'version': companionVersion},
      });
      if (![
            ...supportedProtocols,
            '2024-11-05',
          ].contains(initialized['protocolVersion']) ||
          object(initialized['capabilities'], 'MCP capabilities')['tools']
              is! Map) {
        throw const FormatException(
          'Local MCP server does not support the negotiated tools protocol.',
        );
      }
      bridge._notify('notifications/initialized', {});
      String? cursor;
      final seen = <String>{};
      final cursors = <String>{};
      var pages = 0;
      var total = 0;
      do {
        if (++pages > 20) {
          throw const FormatException('Too many MCP tool pages.');
        }
        final result = await bridge._request('tools/list', {'cursor': ?cursor});
        final tools = result['tools'];
        if (tools is! List || total + tools.length > 256) {
          throw const FormatException('Invalid or oversized MCP tools list.');
        }
        total += tools.length;
        for (final raw in tools) {
          final tool = object(raw, 'MCP tool');
          final name = textValue(tool['name'], 'MCP tool name');
          if (!seen.add(name)) {
            throw const FormatException('Duplicate MCP tool name.');
          }
          if (!config.allowedTools.contains(name)) continue;
          final qualified = '${config.name}__$name';
          if (!RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(qualified)) {
            throw const FormatException(
              'MCP tool name cannot be represented as an OpenRouter function.',
            );
          }
          object(tool['inputSchema'], 'MCP input schema');
          bridge._tools[qualified] = {...tool, 'name': qualified};
        }
        final next = result['nextCursor'];
        if (next != null &&
            (next is! String || !cursors.add(next) || total >= 256)) {
          throw const FormatException('Invalid MCP tools pagination.');
        }
        cursor = next as String?;
      } while (cursor != null);
      if (bridge._tools.length != config.allowedTools.length) {
        throw const FormatException(
          'A configured MCP tool was not advertised by its server.',
        );
      }
      return bridge;
    } on Object {
      await bridge.close();
      rethrow;
    }
  }

  List<Map<String, Object?>> get definitions => _tools.values.toList();
  bool contains(String name) => _tools.containsKey(name);
  Future<Map<String, Object?>> call(
    String name,
    Map<String, Object?> arguments,
    Execution execution,
  ) async {
    if (_closed) {
      return toolError(
        'Local MCP server disconnected. Restart the companion explicitly; this call was not retried.',
      );
    }
    if (execution.cancelled) return toolError('Tool execution cancelled.');
    if (_callActive) {
      return toolError(
        'Local MCP server is busy. No call was dispatched; wait for its active operation to finish.',
      );
    }

    final original = name.substring(config.name.length + 2);
    _callActive = true;
    try {
      final result = await _request('tools/call', {
        'name': original,
        'arguments': arguments,
      }, execution: execution);
      if (result['content'] is! List) {
        return toolError(
          'Local MCP server returned a malformed result.',
          uncertain: true,
        );
      }
      return result;
    } on Object {
      return toolError(
        execution.cancelled
            ? 'Tool execution cancelled.'
            : 'Local MCP request failed or timed out. Its outcome may be uncertain; it was not retried.',
        uncertain: true,
      );
    } finally {
      _callActive = false;
    }
  }

  Future<Map<String, Object?>> _request(
    String method,
    Map<String, Object?> params, {
    Execution? execution,
  }) async {
    if (_closed) throw StateError('MCP process is closed.');
    final id = ++_nextId;
    final completer = Completer<Map<String, Object?>>();
    _pending[id] = completer;
    final timer = Timer(config.timeout, () {
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException('MCP request deadline'));
      }
      _notify('notifications/cancelled', {'requestId': id});
      // Stop the child after an ambiguous timeout; never replay a tool call.
      unawaited(close());
    });
    execution?.onCancel = () {
      _notify('notifications/cancelled', {'requestId': id});
      if (!completer.isCompleted) {
        completer.completeError(StateError('MCP request cancelled'));
      }
      unawaited(close());
    };
    try {
      _process.stdin.writeln(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': id,
          'method': method,
          'params': params,
        }),
      );
      return await completer.future;
    } finally {
      timer.cancel();
      execution?.onCancel = null;
      _pending.remove(id);
    }
  }

  void _notify(String method, Map<String, Object?> params) {
    if (_closed) return;
    try {
      _process.stdin.writeln(
        jsonEncode({'jsonrpc': '2.0', 'method': method, 'params': params}),
      );
    } on Object {
      unawaited(close());
    }
  }

  void _listen() {
    var buffer = <int>[];
    _subscriptions.add(
      _process.stdout.listen(
        (chunk) {
          for (final byte in chunk) {
            if (byte == 10) {
              final line = buffer;
              buffer = [];
              if (line.isEmpty) continue;
              try {
                final message = object(
                  jsonDecode(utf8.decode(line)),
                  'MCP response',
                );
                final id = message['id'];
                final waiting = _pending[id];
                if (waiting == null || waiting.isCompleted) continue;
                if (message['jsonrpc'] != '2.0' || message['error'] != null) {
                  waiting.completeError(
                    const FormatException('Local MCP returned an error.'),
                  );
                } else {
                  waiting.complete(object(message['result'], 'MCP result'));
                }
              } on Object {
                unawaited(close());
                return;
              }
            } else {
              buffer.add(byte);
              if (buffer.length > 4 * 1024 * 1024) {
                unawaited(close());
                return;
              }
            }
          }
        },
        onError: (Object error) => unawaited(close()),
        onDone: () => unawaited(close()),
      ),
    );
    // stderr can contain private source paths or credentials. Drain it without
    // retaining or forwarding diagnostics to the browser or normal logs.
    _subscriptions.add(
      _process.stderr.listen(
        (_) {},
        onError: (Object error) => unawaited(close()),
      ),
    );
    unawaited(_process.exitCode.then((_) => close()));
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final pending in _pending.values) {
      if (!pending.isCompleted) {
        pending.completeError(StateError('Local MCP process closed.'));
      }
    }
    stopProgram(_process);
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    try {
      await _process.stdin.close();
    } on Object {
      /* Child may have already closed its pipe. */
    }
  }
}
