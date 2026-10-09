import 'dart:convert';
import 'dart:io';

const _versions = ['2025-11-25', '2025-06-18', '2025-03-26', '2024-11-05'];
const _samples = {
  'fruit': ('fruit.json', 'application/json'),
  'notes': ('notes.yaml', 'application/yaml'),
};
const _tools = [
  {
    'name': 'add_numbers',
    'description': 'Add two integers, each between -1000000 and 1000000.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'a': {'type': 'integer', 'minimum': -1000000, 'maximum': 1000000},
        'b': {'type': 'integer', 'minimum': -1000000, 'maximum': 1000000},
      },
      'required': ['a', 'b'],
      'additionalProperties': false,
    },
    'annotations': {'readOnlyHint': true, 'destructiveHint': false},
  },
  {
    'name': 'read_sample',
    'description':
        'Read the fixed fruit JSON or notes YAML example. '
        'No arbitrary file paths are accepted.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'sample': {
          'type': 'string',
          'enum': ['fruit', 'notes'],
        },
      },
      'required': ['sample'],
      'additionalProperties': false,
    },
    'annotations': {'readOnlyHint': true, 'destructiveHint': false},
  },
];

Map<String, Object?> _error(Object? id, int code, String message) => {
  'jsonrpc': '2.0',
  'id': id,
  'error': {'code': code, 'message': message},
};

Map<String, Object?> _text(String value, {bool error = false}) => {
  'content': [
    {'type': 'text', 'text': value},
  ],
  'isError': error,
};

String _readSample(String name) {
  final filename = _samples[name]?.$1;
  if (filename == null) throw const FormatException('Unknown sample.');
  final root = Directory.fromUri(Platform.script.resolve('fixtures/'));
  final file = File.fromUri(root.uri.resolve(filename));
  // Both the names and directory are fixed by this example. Reject symlink
  // replacement and unexpectedly large fixtures rather than reading elsewhere.
  if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
          FileSystemEntityType.file ||
      file.lengthSync() > 4096) {
    throw const FormatException('Sample must be an ordinary file up to 4 KiB.');
  }
  return file.readAsStringSync();
}

Map<String, Object?>? _handle(String line) {
  Object? decoded;
  try {
    decoded = jsonDecode(line);
  } on FormatException {
    return _error(null, -32700, 'Invalid JSON.');
  }
  if (decoded is! Map<String, dynamic> ||
      decoded['jsonrpc'] != '2.0' ||
      decoded['method'] is! String ||
      (decoded['id'] != null &&
          decoded['id'] is! String &&
          decoded['id'] is! int)) {
    return _error(null, -32600, 'Expected a JSON-RPC request.');
  }
  if (!decoded.containsKey('id')) {
    return null; // Notifications have no response.
  }
  final id = decoded['id'];
  final params = decoded['params'] ?? <String, dynamic>{};
  if (params is! Map<String, dynamic>) {
    return _error(id, -32602, 'Parameters must be an object.');
  }
  Object result;
  try {
    switch (decoded['method']) {
      case 'initialize':
        result = {
          'protocolVersion': _versions.contains(params['protocolVersion'])
              ? params['protocolVersion']
              : _versions.first,
          'capabilities': {'tools': {}, 'resources': {}},
          'serverInfo': {'name': 'wfform-tools-playground', 'version': '1.0.0'},
        };
      case 'ping':
        result = <String, Object?>{};
      case 'tools/list':
        result = {'tools': _tools};
      case 'tools/call':
        final arguments = params['arguments'] ?? <String, dynamic>{};
        if (arguments is! Map<String, dynamic>) {
          return _error(id, -32602, 'Tool arguments must be an object.');
        }
        switch (params['name']) {
          case 'add_numbers':
            final a = arguments['a'];
            final b = arguments['b'];
            result =
                a is int &&
                    b is int &&
                    arguments.length == 2 &&
                    a.abs() <= 1000000 &&
                    b.abs() <= 1000000
                ? _text(jsonEncode({'a': a, 'b': b, 'sum': a + b}))
                : _text(
                    'Provide only a and b, both integers from -1000000 '
                    'to 1000000.',
                    error: true,
                  );
          case 'read_sample':
            final name = arguments['sample'];
            result =
                name is String &&
                    arguments.length == 1 &&
                    _samples.containsKey(name)
                ? _text(_readSample(name))
                : _text('Provide only sample: fruit or notes.', error: true);
          default:
            return _error(id, -32602, 'Unknown tool.');
        }
      case 'resources/list':
        result = {
          'resources': [
            for (final entry in _samples.entries)
              {
                'uri': 'playground://samples/${entry.key}',
                'name': entry.value.$1,
                'mimeType': entry.value.$2,
              },
          ],
        };
      case 'resources/read':
        final name = _samples.keys
            .where((name) => params['uri'] == 'playground://samples/$name')
            .firstOrNull;
        if (name == null) return _error(id, -32602, 'Unknown sample resource.');
        result = {
          'contents': [
            {
              'uri': params['uri'],
              'mimeType': _samples[name]!.$2,
              'text': _readSample(name),
            },
          ],
        };
      default:
        return _error(id, -32601, 'Method not found.');
    }
  } on Object {
    if (decoded['method'] != 'tools/call') {
      return _error(id, -32603, 'The bundled sample could not be read.');
    }
    result = _text('The bundled sample could not be read.', error: true);
  }
  return {'jsonrpc': '2.0', 'id': id, 'result': result};
}

Future<void> main() async {
  // MCP stdout is protocol-only. Bound bytes before decoding so a client cannot
  // accumulate an unbounded unterminated line; recover at the next newline.
  final buffer = <int>[];
  var overflow = false;
  await for (final chunk in stdin) {
    for (final byte in chunk) {
      if (byte == 10) {
        Map<String, Object?>? response;
        if (overflow) {
          response = _error(null, -32600, 'Request exceeds 8 KiB.');
        } else {
          try {
            response = _handle(utf8.decode(buffer));
          } on FormatException {
            response = _error(null, -32700, 'Invalid UTF-8.');
          }
        }
        buffer.clear();
        overflow = false;
        if (response != null) stdout.writeln(jsonEncode(response));
      } else if (!overflow) {
        if (buffer.length == 8192) {
          buffer.clear();
          overflow = true;
        } else {
          buffer.add(byte);
        }
      }
    }
  }
}
