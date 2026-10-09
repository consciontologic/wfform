import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/app/tool_connections.dart';
import 'package:wfform/features/tools/mcp_client.dart';
import 'package:wfform/shared/platform.dart';
import 'package:wfform/shared/transport.dart';
import '../chat/fakes.dart';

void main() {
  test(
    'remembers endpoints without tokens and never reconnects on reload',
    () async {
      final store = MemoryStore();
      var requests = 0;
      final transport = FakeTransport((request) {
        requests++;
        final value = request.json;
        if (value['method'] == 'notifications/initialized') {
          return ApiResponse(202, const {}, const Stream.empty());
        }
        final result = switch (value['method']) {
          'initialize' => {
            'protocolVersion': '2025-11-25',
            'capabilities': {'tools': {}},
          },
          'tools/list' => {'tools': <Object>[]},
          _ => <String, dynamic>{},
        };
        return jsonResponse({
          'jsonrpc': '2.0',
          'id': value['id'],
          'result': result,
        });
      });
      final connections = ToolConnections(transport: transport, store: store);
      final connection = McpConnection(
        id: 'one',
        name: 'My tools',
        url: 'https://example.org/mcp',
        bearerToken: 'private-secret',
      );
      expect(await connections.connect(connection), true);
      expect(connections.isConnected('one'), true);
      expect(
        jsonEncode(connections.saved.map((c) => c.toJson()).toList()),
        isNot(contains('private-secret')),
      );
      expect(
        store.read(ToolConnections.storageKey),
        isNot(contains('private-secret')),
      );
      final before = requests;
      final restored = ToolConnections(transport: transport, store: store);
      expect(restored.saved.single.id, 'one');
      expect(restored.isConnected('one'), false);
      expect(requests, before);
      connections.disconnect('one');
      expect(connections.isConnected('one'), false);
      connections.forget('one');
      expect(connections.saved, isEmpty);
      connections.dispose();
      restored.dispose();
    },
  );
}
