import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  var initialized = false;
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    final request = jsonDecode(line) as Map;
    final id = request['id'];
    if (id == null) continue;
    Object result = {};
    switch (request['method']) {
      case 'initialize':
        result = {
          'protocolVersion': '2024-11-05',
          'capabilities': {'tools': {}},
          'serverInfo': {'name': 'fixture', 'version': '1'},
        };
        initialized = true;
      case 'tools/list':
        if (!initialized) exit(10);
        if (args.contains('cycling')) {
          result = {'tools': [], 'nextCursor': id.isEven ? 'A' : 'B'};
          break;
        }
        result = {
          'tools': [
            for (final name in ['echo', 'hidden'])
              {
                'name': name,
                'description': 'A fixture',
                'inputSchema': {
                  'type': 'object',
                  'properties': {
                    'text': {'type': 'string'},
                  },
                  'required': ['text'],
                },
              },
          ],
        };
      case 'tools/call':
        if (args.isNotEmpty && args.first == 'record') {
          File(args[1]).writeAsStringSync(
            '${request['params']['arguments']['text']}\n',
            mode: FileMode.append,
          );
          await Future<void>.delayed(const Duration(seconds: 3));
        }
        if (args.contains('delay')) {
          await Future<void>.delayed(const Duration(seconds: 3));
        }
        if (args.contains('disconnect')) exit(1);
        if (args.contains('malformed')) {
          result = {'content': 42};
          break;
        }
        if (args.contains('tool-error')) {
          result = {
            'content': [
              {'type': 'text', 'text': 'Explicit tool failure'},
            ],
            'isError': true,
          };
          break;
        }
        result = {
          'content': [
            {'type': 'text', 'text': request['params']['arguments']['text']},
          ],
          'isError': false,
        };
    }
    stdout.writeln(jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result}));
  }
}
