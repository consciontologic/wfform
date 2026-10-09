import 'dart:convert';
import 'dart:async';
import '../../shared/diagnostics.dart';
import '../../shared/platform.dart' show desktopToolsExplanation;
import '../../shared/transport.dart';
import 'mcp_client.dart';

class ToolCall {
  const ToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });
  final String id;
  final String name;

  /// Raw JSON is preserved for exact assistant history replay, never evaluated.
  final String arguments;
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'function',
    'function': {'name': name, 'arguments': arguments},
  };
  factory ToolCall.fromJson(Object? value) {
    if (value is! Map ||
        value['id'] is! String ||
        (value['id'] as String).isEmpty ||
        (value['id'] as String).length > 256 ||
        value['type'] != 'function' ||
        value['function'] is! Map ||
        value['function']['name'] is! String ||
        !RegExp(
          r'^[A-Za-z0-9_-]{1,64}$',
        ).hasMatch(value['function']['name'] as String) ||
        value['function']['arguments'] is! String ||
        (value['function']['arguments'] as String).length > 65536) {
      throw const FormatException('Invalid function tool call.');
    }
    return ToolCall(
      id: value['id'] as String,
      name: value['function']['name'] as String,
      arguments: value['function']['arguments'] as String,
    );
  }
}

/// Accumulates partial function names/arguments by index without executing them.
class ToolCallAccumulator {
  final _calls = <int, Map<String, dynamic>>{};
  int _size = 0;
  void add(Object? value) {
    if (value == null) return;
    if (value is! List) {
      throw const FormatException('tool_calls must be an array.');
    }
    for (final fragment in value) {
      if (fragment is! Map ||
          fragment['index'] is! int ||
          (fragment['index'] as int) < 0 ||
          (fragment['index'] as int) >= 16) {
        throw const FormatException('Invalid tool call index.');
      }
      final index = fragment['index'] as int;
      final current = _calls.putIfAbsent(
        index,
        () => {
          'id': '',
          'type': 'function',
          'function': <String, dynamic>{'name': '', 'arguments': ''},
        },
      );
      if (fragment['type'] != null && fragment['type'] != 'function') {
        throw const FormatException('Unsupported tool type.');
      }
      if (fragment['id'] != null) {
        if (fragment['id'] is! String) {
          throw const FormatException('Invalid tool call ID.');
        }
        // Providers may repeat the same complete identifier in later deltas.
        if (current['id'] == '') {
          current['id'] = fragment['id'];
        } else if (current['id'] != fragment['id']) {
          throw const FormatException('Tool call ID changed during streaming.');
        }
      }
      final function = fragment['function'];
      if (function != null) {
        if (function is! Map) {
          throw const FormatException('Invalid tool function.');
        }
        for (final key in ['name', 'arguments']) {
          final part = function[key];
          if (part != null && part is! String) {
            throw const FormatException('Invalid tool function fragment.');
          }
          if (part != null) {
            current['function'][key] += part;
            _size += (part as String).length;
          }
        }
      }
      if (_size > 131072) {
        throw const FormatException(
          'Tool requests exceed the local size limit.',
        );
      }
    }
  }

  bool get isNotEmpty => _calls.isNotEmpty;
  List<ToolCall> finish() {
    final keys = _calls.keys.toList()..sort();
    final calls = keys
        .map((key) => ToolCall.fromJson(_calls[key]))
        .toList(growable: false);
    if (calls.map((call) => call.id).toSet().length != calls.length) {
      throw const FormatException('Duplicate tool call IDs.');
    }
    return calls;
  }
}

class ConnectedTool {
  const ConnectedTool({
    required this.name,
    required this.serverName,
    required this.connectionId,
    required this.originalName,
    required this.description,
    required this.inputSchema,
  });
  final String name;
  final String serverName;
  final String connectionId;
  final String originalName;
  final String description;
  final Map<String, dynamic> inputSchema;
  Map<String, dynamic> toApi() => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': inputSchema,
    },
  };
}

typedef ToolApproval =
    Future<bool> Function(ConnectedTool tool, Map<String, dynamic> arguments);

class ToolExecution {
  const ToolExecution(
    this.content, {
    this.isError = false,
    this.dispatched = false,
    this.uncertain = false,
  });
  final String content;
  final bool isError;
  final bool dispatched;
  final bool uncertain;
}

class ToolRegistry {
  ToolRegistry(this.transport, {this.available = true});
  final bool available;
  final ApiTransport transport;
  final _clients = <String, McpClient>{};
  final _tools = <String, ConnectedTool>{};
  List<ConnectedTool> get tools => List.unmodifiable(_tools.values);
  List<McpConnection> get connections =>
      List.unmodifiable(_clients.values.map((c) => c.connection));
  Future<void> connect(
    McpConnection connection, {
    required CancelToken cancel,
  }) async {
    if (!available) {
      throw const AppFailure(
        FailureKind.configuration,
        desktopToolsExplanation,
      );
    }
    final client = McpClient(transport, connection);
    List<McpTool> discovered;
    try {
      await client.initialize(cancel: cancel);
      discovered = await client.listTools(cancel: cancel);
    } catch (_) {
      unawaited(client.close());
      rethrow;
    }
    cancel.throwIfCancelled();
    final added = <String, ConnectedTool>{};
    for (final tool in discovered) {
      final name = _qualifiedName(connection.id, tool.name);
      if (added.containsKey(name) ||
          (_tools.containsKey(name) &&
              _tools[name]!.connectionId != connection.id)) {
        throw const AppFailure(
          FailureKind.configuration,
          'Tool naming collision. Rename this connection.',
        );
      }
      added[name] = ConnectedTool(
        name: name,
        serverName: connection.name,
        connectionId: connection.id,
        originalName: tool.name,
        description: tool.description,
        inputSchema: tool.inputSchema,
      );
    }
    disconnect(connection.id);
    _clients[connection.id] = client;
    _tools.addAll(added);
  }

  void disconnect(String connectionId) {
    final client = _clients.remove(connectionId);
    if (client != null) unawaited(client.close());
    _tools.removeWhere((_, tool) => tool.connectionId == connectionId);
  }

  List<Map<String, dynamic>> definitions(Set<String> enabledNames) => [
    if (available)
      for (final name in enabledNames)
        if (_tools[name] case final tool?) tool.toApi(),
  ];

  Future<ToolExecution> execute(
    ToolCall call, {
    required Set<String> enabledNames,
    required CancelToken cancel,
    ToolApproval? confirm,
    int maxResultChars = 120000,
  }) async {
    cancel.throwIfCancelled();
    if (!available) {
      return const ToolExecution(desktopToolsExplanation, isError: true);
    }
    final tool = _tools[call.name];
    if (tool == null || !enabledNames.contains(call.name)) {
      return const ToolExecution(
        'Tool is unavailable or not enabled for this conversation.',
        isError: true,
      );
    }
    Map<String, dynamic> arguments;
    try {
      final parsed = jsonDecode(call.arguments);
      if (parsed is! Map<String, dynamic>) {
        throw const FormatException('Arguments must be an object.');
      }
      validateToolArguments(parsed, tool.inputSchema);
      arguments = parsed;
    } on FormatException catch (error) {
      return ToolExecution(
        'Invalid tool arguments: ${error.message}',
        isError: true,
      );
    }
    if (confirm == null || !await confirm(tool, arguments)) {
      return const ToolExecution(
        'The user did not approve this tool call. Do not repeat it without a new user request.',
        isError: true,
      );
    }
    cancel.throwIfCancelled();
    try {
      final result = await _clients[tool.connectionId]!.callTool(
        tool.originalName,
        arguments,
        cancel: cancel,
      );
      if (result['content'] is! List ||
          (result['isError'] != null && result['isError'] is! bool)) {
        throw const AppFailure(FailureKind.schema, 'Invalid MCP tool result.');
      }
      final encoded = jsonEncode(result);
      if (encoded.length > maxResultChars) {
        return const ToolExecution(
          'Tool output exceeded the conversation size limit. Execution may have completed; inspect its external state before requesting another action.',
          isError: true,
          dispatched: true,
          uncertain: true,
        );
      }
      final metadata = result['_meta'];
      final uncertain =
          metadata is Map && metadata['wfform.com/outcome'] == 'uncertain';
      return ToolExecution(
        encoded,
        isError: result['isError'] == true || uncertain,
        dispatched: true,
        uncertain: uncertain,
      );
    } catch (_) {
      // Even a network error may arrive after the tool took effect. Never replay.
      return const ToolExecution(
        'Tool outcome is unknown because the connection failed or was cancelled. It may have completed. Check the external state before any new action; this call will not be retried.',
        isError: true,
        dispatched: true,
        uncertain: true,
      );
    }
  }

  static String _qualifiedName(String id, String name) {
    // Stable 64-bit pair of FNV hashes; collision checked before registration.
    int hash(String value, int seed) {
      var hash = seed;
      for (final byte in utf8.encode(value)) {
        hash = ((hash ^ byte) * 16777619) & 0xffffffff;
      }
      return hash;
    }

    final identity = '$id\u0000$name';
    final suffix =
        '${hash(identity, 2166136261).toRadixString(16).padLeft(8, '0')}${hash(identity, 3335557771).toRadixString(16).padLeft(8, '0')}';
    final label = name.replaceAll(RegExp('[^A-Za-z0-9_-]'), '_');
    return 'mcp_${label.substring(0, label.length > 42 ? 42 : label.length)}_$suffix';
  }
}

/// Validate bounded JSON against common MCP input-schema constraints locally.
/// External references are forbidden; the tool server remains authoritative.
void validateToolArguments(
  Map<String, dynamic> arguments,
  Map<String, dynamic> schema,
) {
  if (jsonEncode(arguments).length > 65536) {
    throw const FormatException('Arguments exceed 64 KiB.');
  }
  var visited = 0;
  void check(Object? value, Object? raw, String path, int depth) {
    if (++visited > 4096) throw const _SchemaLimit();
    if (depth > 32) {
      throw const FormatException('Schema nesting exceeds the local limit.');
    }
    if (raw == true) return;
    if (raw == false) throw FormatException('$path is forbidden.');
    if (raw is! Map) throw const FormatException('Unsupported input schema.');
    if (raw[r'$ref'] case final String reference) {
      if (!reference.startsWith('#/')) {
        throw const FormatException(
          'External schema references are unsupported.',
        );
      }
      Object? target = schema;
      for (final part in reference.substring(2).split('/')) {
        if (target is! Map) {
          throw const FormatException('Unresolved schema reference.');
        }
        target = target[part.replaceAll('~1', '/').replaceAll('~0', '~')];
      }
      check(value, target, path, depth + 1);
    }
    for (final name in ['allOf', 'anyOf', 'oneOf']) {
      if (raw[name] case final List alternatives) {
        var passed = 0;
        for (final option in alternatives) {
          try {
            check(value, option, path, depth + 1);
            passed++;
          } on FormatException {
            /* This branch did not match. */
          }
        }
        if ((name == 'allOf' && passed != alternatives.length) ||
            (name == 'anyOf' && passed == 0) ||
            (name == 'oneOf' && passed != 1)) {
          throw FormatException('$path does not match $name.');
        }
      }
    }
    bool matches(Object? type) => switch (type) {
      'object' => value is Map,
      'array' => value is List,
      'string' => value is String,
      'number' => value is num && value.isFinite,
      'integer' =>
        value is num && value.isFinite && value == value.roundToDouble(),
      'boolean' => value is bool,
      'null' => value == null,
      null => true,
      _ => false,
    };
    final type = raw['type'];
    if (type is List ? !type.any(matches) : !matches(type)) {
      throw FormatException('$path has the wrong type.');
    }
    if (raw['enum'] case final List choices) {
      if (!choices.any(
        (candidate) => jsonEncode(candidate) == jsonEncode(value),
      )) {
        throw FormatException('$path is not an allowed value.');
      }
    }
    if (raw.containsKey('const') &&
        jsonEncode(raw['const']) != jsonEncode(value)) {
      throw FormatException('$path must equal its constant.');
    }
    if (value is Map) {
      final properties = raw['properties'] is Map
          ? raw['properties'] as Map
          : const {};
      final required = raw['required'] is List
          ? raw['required'] as List
          : const [];
      for (final name in required) {
        if (!value.containsKey(name)) {
          throw FormatException('$path is missing required field $name.');
        }
      }
      for (final entry in value.entries) {
        if (properties.containsKey(entry.key)) {
          check(
            entry.value,
            properties[entry.key],
            '$path.${entry.key}',
            depth + 1,
          );
        } else if (raw['additionalProperties'] == false) {
          throw FormatException('$path contains an unexpected field.');
        } else if (raw['additionalProperties'] is Map) {
          check(entry.value, raw['additionalProperties'], path, depth + 1);
        }
      }
    }
    if (value is List) {
      if (raw['minItems'] is num && value.length < raw['minItems'] ||
          raw['maxItems'] is num && value.length > raw['maxItems']) {
        throw FormatException('$path has an invalid item count.');
      }
      for (final item in value) {
        if (raw.containsKey('items')) {
          check(item, raw['items'], '$path[]', depth + 1);
        }
      }
    }
    if (value is String) {
      if (raw['minLength'] is num && value.length < raw['minLength'] ||
          raw['maxLength'] is num && value.length > raw['maxLength']) {
        throw FormatException('$path has an invalid length.');
      }
      // Server-supplied regexes are not run on the UI isolate (ReDoS risk).
    }
    if (value is num) {
      if (raw['minimum'] is num && value < raw['minimum'] ||
          raw['maximum'] is num && value > raw['maximum'] ||
          raw['exclusiveMinimum'] is num && value <= raw['exclusiveMinimum'] ||
          raw['exclusiveMaximum'] is num && value >= raw['exclusiveMaximum']) {
        throw FormatException('$path is outside the permitted range.');
      }
    }
  }

  try {
    check(arguments, schema, r'$', 0);
  } on _SchemaLimit {
    throw const FormatException(
      'Schema validation exceeded the local complexity limit.',
    );
  }
}

/// Tool call/result groups are atomic. Partial saved snapshots may have a final
/// pending group, which restore explicitly closes without executing anything.
void validateToolTranscript(
  List<Map<String, dynamic>> messages, {
  bool allowPending = false,
}) {
  final pending = <String>{};
  final seen = <String>{};
  for (final message in messages) {
    final role = message['role'];
    final raw = message['toolCalls'] ?? message['tool_calls'];
    final resultId = message['toolCallId'] ?? message['tool_call_id'];
    if (role == 'tool') {
      if (resultId is! String ||
          !pending.remove(resultId) ||
          (raw is List && raw.isNotEmpty)) {
        throw const FormatException('Orphan or duplicate tool result.');
      }
      continue;
    }
    if (resultId != null) {
      throw const FormatException(
        'Only tool messages can contain a tool call ID.',
      );
    }
    if (pending.isNotEmpty) {
      throw const FormatException(
        'Incomplete tool group in conversation history.',
      );
    }
    if (raw == null) continue;
    if (raw is! List ||
        (raw.isNotEmpty && role != 'assistant') ||
        raw.length > 16) {
      throw const FormatException('Invalid tool call group.');
    }
    for (final value in raw) {
      final call = ToolCall.fromJson(value);
      if (!seen.add(call.id)) {
        throw const FormatException(
          'Duplicate tool call ID in conversation history.',
        );
      }
      pending.add(call.id);
    }
  }
  if (!allowPending && pending.isNotEmpty) {
    throw const FormatException(
      'Missing tool results in conversation history.',
    );
  }
}

class _SchemaLimit implements Exception {
  const _SchemaLimit();
}
