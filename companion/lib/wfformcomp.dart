import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'stdio_mcp.dart';
import 'static_host.dart';
import 'process_group.dart';

const companionVersion = '1.0.0';
const supportedProtocols = ['2025-11-25', '2025-06-18', '2025-03-26'];
const _maxBodyBytes = 256 * 1024;

Map<String, Object?> object(Object? value, String label) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$label must be an object.');
  }
  return value;
}

String textValue(Object? value, String label) {
  if (value is! String || value.isEmpty || value.contains('\u0000')) {
    throw FormatException('$label must be a nonempty string without NUL.');
  }
  return value;
}

List<String> strings(Object? value, String label) {
  if (value is! List) throw FormatException('$label must be an array.');
  return value.map((v) => textValue(v, label)).toList();
}

int boundedInt(Object? value, int fallback, int min, int max, String label) {
  if (value == null) return fallback;
  if (value is! int || value < min || value > max) {
    throw FormatException('$label is outside its limits.');
  }
  return value;
}

class CompanionConfig {
  CompanionConfig.fromJson(Map<String, Object?> json)
    : port = boundedInt(json['port'], 8765, 0, 65535, 'port'),
      allowedOrigins = strings(
        json['allowedOrigins'],
        'allowedOrigins',
      ).toSet(),
      tools = (json['tools'] as List? ?? [])
          .map((v) => CommandTool.fromJson(object(v, 'tool')))
          .toList(),
      mcpServers = (json['mcpServers'] as List? ?? [])
          .map((v) => StdioServerConfig.fromJson(object(v, 'MCP server')))
          .toList() {
    if (allowedOrigins.isEmpty) {
      throw const FormatException(
        'At least one explicit allowed origin is required.',
      );
    }
    for (final origin in allowedOrigins) {
      final uri = Uri.tryParse(origin);
      if (uri == null ||
          !['https', 'http'].contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment ||
          uri.path.isNotEmpty ||
          uri.origin != origin ||
          (uri.scheme == 'http' &&
              !['localhost', '127.0.0.1', '[::1]', '::1'].contains(uri.host))) {
        throw const FormatException(
          'Origins must be exact HTTPS origins or HTTP loopback origins.',
        );
      }
    }
    if (mcpServers.length > 8 ||
        mcpServers.map((server) => server.name).toSet().length !=
            mcpServers.length) {
      throw const FormatException('Use up to eight unique MCP servers.');
    }
    if (tools.length > 64 ||
        tools.map((t) => t.name).toSet().length != tools.length) {
      throw const FormatException('Use up to 64 unique tool names.');
    }
  }
  final int port;
  final Set<String> allowedOrigins;
  final List<CommandTool> tools;
  final List<StdioServerConfig> mcpServers;
}

class CommandTool {
  CommandTool.fromJson(Map<String, Object?> json)
    : name = textValue(json['name'], 'name'),
      description = textValue(json['description'], 'description'),
      executable = textValue(json['executable'], 'executable'),
      arguments = strings(json['arguments'] ?? [], 'arguments'),
      workingDirectory = json['workingDirectory'] as String?,
      environment =
          object(json['environment'] ?? <String, Object?>{}, 'environment').map(
            (key, value) =>
                MapEntry(key, textValue(value, 'environment value')),
          ),
      timeout = Duration(
        milliseconds: boundedInt(
          json['timeoutMs'],
          15000,
          50,
          120000,
          'timeoutMs',
        ),
      ),
      maxOutputBytes = boundedInt(
        json['maxOutputBytes'],
        65536,
        128,
        262144,
        'maxOutputBytes',
      ),
      inputSchema = object(
        json['inputSchema'] ??
            {
              'type': 'object',
              'properties': <String, Object?>{},
              'additionalProperties': false,
            },
        'inputSchema',
      ) {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,64}$').hasMatch(name)) {
      throw const FormatException('Invalid tool name.');
    }
    if (!File(executable).isAbsolute) {
      throw const FormatException('Tool executable must be an absolute path.');
    }
    validateSchema(inputSchema);
    if (inputSchema['type'] != 'object' ||
        inputSchema['additionalProperties'] != false) {
      throw const FormatException(
        'Command inputSchema must be an object with additionalProperties: false.',
      );
    }
    final properties = object(
      inputSchema['properties'] ?? <String, Object?>{},
      'properties',
    );
    for (final argument in arguments) {
      if (argument.startsWith('{') && argument.endsWith('}')) {
        final key = argument.substring(1, argument.length - 1);
        if (!properties.containsKey(key)) {
          throw const FormatException(
            'Argument placeholder has no schema property.',
          );
        }
        final type = object(properties[key], 'property')['type'];
        if (!['string', 'number', 'integer', 'boolean'].contains(type)) {
          throw const FormatException('Command placeholders must be scalar.');
        }
      }
    }
  }
  final String name;
  final String description;
  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String> environment;
  final Duration timeout;
  final int maxOutputBytes;
  final Map<String, Object?> inputSchema;
  Map<String, Object?> get definition => {
    'name': name,
    'description': description,
    'inputSchema': inputSchema,
  };

  Future<Map<String, Object?>> call(
    Map<String, Object?> input,
    Execution execution,
  ) async {
    final invalid = validateValue(inputSchema, input);
    if (invalid != null) return toolError(invalid);
    final argv = <String>[];
    for (final arg in arguments) {
      if (arg.startsWith('{') && arg.endsWith('}')) {
        final key = arg.substring(1, arg.length - 1);
        if (!input.containsKey(key)) {
          return toolError('Missing command argument: $key.');
        }
        argv.add(input[key].toString());
      } else {
        argv.add(arg);
      }
    }
    if (execution.cancelled) return toolError('Tool execution cancelled.');
    Process process;
    try {
      process = await startProgram(
        executable,
        argv,
        workingDirectory: workingDirectory,
        environment: environment,
      );
    } on ProcessException {
      return toolError(
        'The configured program could not be started. Check its path and permissions.',
      );
    }
    execution.process = process;
    if (execution.cancelled) execution.cancel();
    await process.stdin.close();
    var limited = false;
    var timedOut = false;
    var captured = 0;
    final output = <int>[];
    final errors = <int>[];
    void collect(List<int> chunk, List<int> target) {
      final available = max(0, maxOutputBytes - captured);
      target.addAll(chunk.take(available));
      captured += min(available, chunk.length);
      if (chunk.length > available) {
        limited = true;
        stopProgram(process);
      }
    }

    final stdoutDone = process.stdout.forEach((part) => collect(part, output));
    final stderrDone = process.stderr.forEach((part) => collect(part, errors));
    final timer = Timer(timeout, () {
      timedOut = true;
      stopProgram(process);
    });
    try {
      final code = await process.exitCode;
      await Future.wait([
        stdoutDone,
        stderrDone,
      ]).timeout(const Duration(seconds: 2));
      final result = <String, Object?>{
        'exitCode': code,
        'stdout': utf8.decode(output, allowMalformed: true),
        'stderr': utf8.decode(errors, allowMalformed: true),
        if (limited) 'outputLimitExceeded': true,
        if (timedOut) 'timedOut': true,
        if (execution.cancelled) 'cancelled': true,
      };
      return {
        'content': [
          {'type': 'text', 'text': jsonEncode(result)},
        ],
        'isError': code != 0 || limited || timedOut || execution.cancelled,
        if (limited || timedOut || execution.cancelled)
          '_meta': {'wfform.com/outcome': 'uncertain'},
      };
    } on TimeoutException {
      return toolError(
        'The program left output streams open; execution was stopped.',
        uncertain: true,
      );
    } finally {
      timer.cancel();
      stopProgram(process);
      execution.process = null;
    }
  }
}

class Execution {
  Process? process;
  bool cancelled = false;
  void Function()? onCancel;
  void cancel() {
    cancelled = true;
    if (process case final process?) stopProgram(process);
    onCancel?.call();
  }
}

Map<String, Object?> toolError(String message, {bool uncertain = false}) => {
  'content': [
    {'type': 'text', 'text': message},
  ],
  'isError': true,
  if (uncertain) '_meta': {'wfform.com/outcome': 'uncertain'},
};

void validateSchema(Map<String, Object?> schema, [int depth = 0]) {
  if (depth > 8) throw const FormatException('Input schema is too deep.');
  const supported = {
    'type',
    'description',
    'title',
    'properties',
    'required',
    'additionalProperties',
    'items',
    'enum',
    'minimum',
    'maximum',
    'minLength',
    'maxLength',
  };
  if (schema.keys.any((key) => !supported.contains(key))) {
    throw const FormatException('Unsupported input schema keyword.');
  }
  if (![
    'object',
    'array',
    'string',
    'integer',
    'number',
    'boolean',
    'null',
  ].contains(schema['type'])) {
    throw const FormatException('Every schema needs a supported type.');
  }
  if (schema['type'] == 'object') {
    final props = object(
      schema['properties'] ?? <String, Object?>{},
      'properties',
    );
    for (final value in props.values) {
      validateSchema(object(value, 'property'), depth + 1);
    }
    final required = strings(schema['required'] ?? [], 'required');
    if (required.any((key) => !props.containsKey(key))) {
      throw const FormatException('Required property is not defined.');
    }
    if (schema['additionalProperties'] != null &&
        schema['additionalProperties'] is! bool) {
      throw const FormatException('additionalProperties must be boolean.');
    }
  }
  if (schema['type'] == 'array') {
    validateSchema(object(schema['items'], 'items'), depth + 1);
  }
  for (final key in ['minimum', 'maximum']) {
    if (schema[key] != null && schema[key] is! num) {
      throw FormatException('$key must be numeric.');
    }
  }
  for (final key in ['minLength', 'maxLength']) {
    if (schema[key] != null &&
        (schema[key] is! int || (schema[key] as int) < 0)) {
      throw FormatException('$key must be a nonnegative integer.');
    }
  }
  if (schema['enum'] != null &&
      (schema['enum'] is! List || (schema['enum'] as List).isEmpty)) {
    throw const FormatException('enum must be a nonempty array.');
  }
}

String? validateValue(
  Map<String, Object?> schema,
  Object? value, [
  String path = 'arguments',
]) {
  final matches = switch (schema['type']) {
    'object' => value is Map<String, Object?>,
    'array' => value is List,
    'string' => value is String && !value.contains('\u0000'),
    'integer' => value is int,
    'number' => value is num && value.isFinite,
    'boolean' => value is bool,
    'null' => value == null,
    _ => false,
  };
  if (!matches) return '$path has an invalid type.';
  if (schema['enum'] case final List values) {
    if (!values.contains(value)) return '$path is not an allowed value.';
  }
  if (value is num) {
    if (schema['minimum'] case final num minimum) {
      if (value < minimum) return '$path is below its minimum.';
    }
    if (schema['maximum'] case final num maximum) {
      if (value > maximum) return '$path exceeds its maximum.';
    }
  }
  if (value is String) {
    if (value.length > (schema['maxLength'] as int? ?? 8192) ||
        value.length < (schema['minLength'] as int? ?? 0)) {
      return '$path length is outside its limits.';
    }
  }
  if (value is Map<String, Object?>) {
    final props = object(
      schema['properties'] ?? <String, Object?>{},
      'properties',
    );
    for (final key in strings(schema['required'] ?? [], 'required')) {
      if (!value.containsKey(key)) return '$path is missing $key.';
    }
    for (final entry in value.entries) {
      if (!props.containsKey(entry.key)) {
        if (schema['additionalProperties'] == false) {
          return '$path has an unknown property.';
        }
      } else {
        final error = validateValue(
          object(props[entry.key], 'property'),
          entry.value,
          '$path.${entry.key}',
        );
        if (error != null) return error;
      }
    }
  }
  if (value is List) {
    if (value.length > 256) return '$path has too many items.';
    for (final entry in value) {
      final error = validateValue(
        object(schema['items'], 'items'),
        entry,
        path,
      );
      if (error != null) return error;
    }
  }
  return null;
}

class CompanionServer {
  CompanionServer._(this.config, this._token, this._http, this._staticHost);
  final CompanionConfig config;
  final String _token;
  final HttpServer _http;
  final StaticHost? _staticHost;
  final _executions = <String, Execution>{};
  final _sessions = <String, DateTime>{};
  final _bridges = <StdioMcp>[];
  bool _closing = false;
  static Future<CompanionServer> start(
    CompanionConfig config,
    String token, {
    Directory? webRoot,
  }) async {
    if (token.length < 32 ||
        token.length > 512 ||
        token.contains(RegExp(r'\s'))) {
      throw const FormatException(
        'Pairing token must have 32–512 non-whitespace characters.',
      );
    }
    final staticHost = webRoot == null ? null : StaticHost(webRoot);
    final http = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      config.port,
    );
    final server = CompanionServer._(config, token, http, staticHost);
    try {
      for (final config in config.mcpServers) {
        server._bridges.add(await StdioMcp.start(config));
      }
      final definitions = server._definitions;
      if (definitions.length > 128 ||
          definitions.map((t) => t['name']).toSet().length !=
              definitions.length) {
        throw const FormatException(
          'Duplicate or excessive combined tool names.',
        );
      }
      http.listen(server._handle);
      return server;
    } on Object {
      await server.close();
      rethrow;
    }
  }

  List<Map<String, Object?>> get _definitions => [
    ...config.tools.map((tool) => tool.definition),
    for (final bridge in _bridges) ...bridge.definitions,
  ];
  int get toolCount => _definitions.length;
  Uri get endpoint => Uri.parse('http://127.0.0.1:${_http.port}/mcp');
  Future<void> close() async {
    _closing = true;
    for (final execution in _executions.values) {
      execution.cancel();
    }
    for (final bridge in _bridges) {
      await bridge.close();
    }
    await _http.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      await _serve(request);
    } on Object {
      // Never log request data, command output, configuration or credentials.
      try {
        request.response.statusCode = 500;
        request.response.write('Request failed.');
      } on Object {
        // Client cancellation can close the response before an error is sent.
      }
    } finally {
      try {
        await request.response.close();
      } on Object {
        // A closed browser socket must not terminate the companion process.
      }
    }
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    response.headers.set('Cache-Control', 'no-store');
    response.headers.set('X-Content-Type-Options', 'nosniff');
    final host = request.headers.value('host');
    if (!{
      '127.0.0.1:${_http.port}',
      'localhost:${_http.port}',
    }.contains(host)) {
      response.statusCode = 403;
      return;
    }
    final origin = request.headers.value('origin');
    if (origin != null &&
        !config.allowedOrigins.contains(origin) &&
        !(_staticHost != null && origin == endpoint.origin)) {
      response.statusCode = 403;
      return;
    }
    if (origin != null) {
      response.headers.set('Access-Control-Allow-Origin', origin);
      response.headers.set('Vary', 'Origin');
      response.headers.set(
        'Access-Control-Expose-Headers',
        'MCP-Protocol-Version, MCP-Session-Id',
      );
    }
    if (request.method == 'OPTIONS') {
      if (origin == null) {
        response.statusCode = 403;
        return;
      }
      response.headers.set(
        'Access-Control-Allow-Methods',
        'POST, GET, OPTIONS, DELETE',
      );
      response.headers.set(
        'Access-Control-Allow-Headers',
        'Authorization, Content-Type, Accept, MCP-Protocol-Version, MCP-Session-Id',
      );
      if (request.headers.value('access-control-request-private-network') ==
          'true') {
        response.headers.set('Access-Control-Allow-Private-Network', 'true');
      }
      response.statusCode = 204;
      return;
    }
    if (request.uri.path == '/health' && request.method == 'GET') {
      response.headers.contentType = ContentType.json;
      response.write(
        jsonEncode({
          'name': 'wfformcomp',
          'version': companionVersion,
          'protocolVersions': supportedProtocols,
        }),
      );
      return;
    }
    if (request.uri.path != '/mcp') {
      if (_staticHost != null) {
        await _staticHost.serve(request);
      } else {
        response.statusCode = 404;
      }
      return;
    }
    if (!_constantEqual(
      request.headers.value('authorization') ?? '',
      'Bearer $_token',
    )) {
      stderr.writeln('wfformcomp: rejected unauthenticated RPC');
      response.statusCode = 401;
      return;
    }
    _sessions.removeWhere(
      (_, touched) =>
          DateTime.now().difference(touched) > const Duration(hours: 1),
    );
    final session = request.headers.value('mcp-session-id');
    if (session != null && !_sessions.containsKey(session)) {
      response.statusCode = 404;
      return;
    }
    if (session != null) _sessions[session] = DateTime.now();
    final requestScope = session ?? 'stateless:${origin ?? 'native'}';
    String executionKey(Object? id) => '$requestScope:${jsonEncode(id)}';
    if (request.method == 'DELETE' && session != null) {
      _sessions.remove(session);
      for (final entry in _executions.entries) {
        if (entry.key.startsWith('$session:')) entry.value.cancel();
      }
      response.statusCode = 204;
      return;
    }
    if (request.method != 'POST') {
      response.statusCode = 405;
      response.headers.set('Allow', 'POST, OPTIONS');
      return;
    }
    final protocol =
        request.headers.value('mcp-protocol-version') ?? '2025-03-26';
    if (!supportedProtocols.contains(protocol)) {
      response.statusCode = 400;
      return;
    }
    if (request.headers.contentType?.mimeType != 'application/json') {
      response.statusCode = 415;
      return;
    }
    if (request.contentLength > _maxBodyBytes) {
      response.statusCode = 413;
      return;
    }
    final bytes = <int>[];
    await for (final part in request.timeout(const Duration(seconds: 10))) {
      if (bytes.length + part.length > _maxBodyBytes) {
        response.statusCode = 413;
        return;
      }
      bytes.addAll(part);
    }
    Object? parsed;
    try {
      parsed = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      _write(request, {
        'jsonrpc': '2.0',
        'id': null,
        'error': {'code': -32700, 'message': 'Parse error'},
      });
      return;
    }
    if (parsed is! Map<String, Object?> ||
        parsed['jsonrpc'] != '2.0' ||
        parsed['method'] is! String ||
        (parsed.containsKey('id') &&
            parsed['id'] is! String &&
            parsed['id'] is! int)) {
      _write(request, {
        'jsonrpc': '2.0',
        'id': null,
        'error': {'code': -32600, 'message': 'Invalid request'},
      });
      return;
    }
    final id = parsed['id'];
    final method = parsed['method'];
    final params = parsed['params'] ?? <String, Object?>{};
    if (params is! Map<String, Object?>) {
      _write(request, _error(id, -32602, 'Invalid parameters'));
      return;
    }
    if (id == null) {
      if (method == 'notifications/cancelled') {
        _executions[executionKey(params['requestId'])]?.cancel();
      }
      response.statusCode = 202;
      return;
    }
    Map<String, Object?>? result;
    switch (method) {
      case 'initialize':
        if (_sessions.length >= 64) {
          _write(request, _error(id, -32000, 'Session capacity reached'));
          return;
        }
        final created = generateToken();
        _sessions[created] = DateTime.now();
        response.headers.set('MCP-Session-Id', created);
        final requested = params['protocolVersion'];
        result = {
          'protocolVersion': supportedProtocols.contains(requested)
              ? requested
              : supportedProtocols.first,
          'capabilities': {
            'tools': {'listChanged': false},
          },
          'serverInfo': {'name': 'wfformcomp', 'version': companionVersion},
        };
      case 'ping':
        result = {};
      case 'tools/list':
        result = {'tools': _definitions};
      case 'tools/call':
        final matches = config.tools.where(
          (tool) => tool.name == params['name'],
        );
        final bridges = _bridges.where(
          (bridge) => bridge.contains(params['name'] as String? ?? ''),
        );
        if (matches.isEmpty && bridges.isEmpty) {
          _write(request, _error(id, -32602, 'Unknown tool'));
          return;
        }
        if (_executions.length >= 4 ||
            _executions.containsKey(executionKey(id)) ||
            _closing) {
          _write(
            request,
            _error(
              id,
              -32000,
              'Execution capacity reached or duplicate request',
            ),
          );
          return;
        }
        final input = params['arguments'] ?? <String, Object?>{};
        if (input is! Map<String, Object?>) {
          _write(request, _error(id, -32602, 'Arguments must be an object'));
          return;
        }
        final execution = Execution();
        _executions[executionKey(id)] = execution;
        try {
          result = matches.isNotEmpty
              ? await matches.first.call(input, execution)
              : await bridges.first.call(
                  params['name'] as String,
                  input,
                  execution,
                );
        } finally {
          _executions.remove(executionKey(id));
        }
      default:
        _write(request, _error(id, -32601, 'Method not found'));
        return;
    }
    _write(request, {'jsonrpc': '2.0', 'id': id, 'result': result});
  }

  void _write(HttpRequest request, Map<String, Object?> body) {
    final encoded = jsonEncode(body);
    final accept = request.headers.value('accept') ?? '';
    if (accept.contains('text/event-stream') &&
        !accept.contains('application/json')) {
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      );
      request.response.write('event: message\ndata: $encoded\n\n');
    } else {
      request.response.headers.contentType = ContentType.json;
      request.response.write(encoded);
    }
  }
}

Map<String, Object?> _error(Object? id, int code, String message) => {
  'jsonrpc': '2.0',
  'id': id,
  'error': {'code': code, 'message': message},
};
bool _constantEqual(String a, String b) {
  var difference = a.length ^ b.length;
  for (var i = 0; i < b.length; i++) {
    difference |= (i < a.length ? a.codeUnitAt(i) : 0) ^ b.codeUnitAt(i);
  }
  return difference == 0;
}

String generateToken() {
  final random = Random.secure();
  return base64Url
      .encode(List.generate(32, (_) => random.nextInt(256)))
      .replaceAll('=', '');
}
