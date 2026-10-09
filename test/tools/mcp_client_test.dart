import 'dart:convert';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/features/tools/mcp_client.dart';
import 'package:wfform/shared/diagnostics.dart';
import 'package:wfform/shared/transport.dart';

import '../chat/fakes.dart';

void main() {
  test(
    'negotiates MCP session, isolates authorization, follows tool pagination',
    () async {
      final transport = FakeTransport((r) {
        final request = r.json;
        switch (request['method']) {
          case 'initialize':
            expect(request['params']['protocolVersion'], '2025-11-25');
            return jsonResponse(
              {
                'jsonrpc': '2.0',
                'id': request['id'],
                'result': {
                  'protocolVersion': '2025-06-18',
                  'capabilities': {'tools': {}},
                  'serverInfo': {'name': 'fixture', 'version': '1'},
                },
              },
              headers: {'mcp-session-id': 'session-fixture'},
            );
          case 'notifications/initialized':
            return ApiResponse(202, const {}, const Stream.empty());
          case 'tools/list':
            final second = request['params']?['cursor'] == 'next';
            return jsonResponse({
              'jsonrpc': '2.0',
              'id': request['id'],
              'result': {
                'tools': [
                  {
                    'name': second ? 'second' : 'first',
                    'inputSchema': {'type': 'object'},
                  },
                ],
                if (!second) 'nextCursor': 'next',
              },
            });
          case 'tools/call':
            return streamResponse(
              'data: ${jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/progress', 'params': {}})}\n\ndata: ${jsonEncode({
                'jsonrpc': '2.0',
                'id': request['id'],
                'result': {
                  'content': [
                    {'type': 'text', 'text': '432'},
                  ],
                },
              })}\n\n',
            );
          default:
            throw StateError('Unexpected method');
        }
      });
      final client = McpClient(
        transport,
        McpConnection(
          id: 'local',
          name: 'Local',
          url: 'http://127.0.0.1:8766/mcp',
          bearerToken: 'mcp-only',
        ),
      );
      await client.initialize(cancel: CancelToken());
      expect(
        (await client.listTools(cancel: CancelToken())).map((t) => t.name),
        ['first', 'second'],
      );
      expect(await client.callTool('first', {'a': 18}, cancel: CancelToken()), {
        'content': [
          {'type': 'text', 'text': '432'},
        ],
      });
      expect(
        transport.requests.every(
          (r) => r.headers['Authorization'] == 'Bearer mcp-only',
        ),
        isTrue,
      );
      for (final r in transport.requests.skip(1)) {
        expect(r.headers['MCP-Session-Id'], 'session-fixture');
        expect(r.headers['MCP-Protocol-Version'], '2025-06-18');
      }
    },
  );

  test('rejects unsafe endpoint URLs and credential URLs before dispatch', () {
    for (final url in [
      'http://example.org/mcp',
      'http://[::1]:8765/mcp',
      'file:///tmp/mcp',
      'https://user:secret@example.org/mcp',
      'https://example.org/mcp#token',
    ]) {
      expect(
        () => McpConnection(id: 'x', name: 'X', url: url),
        throwsA(isA<AppFailure>()),
      );
    }
  });

  test(
    'unsupported negotiated version does not proceed to list or call',
    () async {
      final transport = FakeTransport(
        (r) => jsonResponse({
          'jsonrpc': '2.0',
          'id': r.json['id'],
          'result': {
            'protocolVersion': '2099-01-01',
            'capabilities': {'tools': {}},
          },
        }),
      );
      final client = McpClient(
        transport,
        McpConnection(
          id: 'remote',
          name: 'Remote',
          url: 'https://example.org/mcp',
        ),
      );
      await expectLater(
        client.initialize(cancel: CancelToken()),
        throwsA(isA<AppFailure>()),
      );
      expect(transport.requests.length, 1);
    },
  );

  test('rejects mismatched RPC IDs and never retries a tool call', () async {
    var calls = 0;
    final transport = FakeTransport((r) {
      if (r.json['method'] == 'initialize') {
        return jsonResponse({
          'jsonrpc': '2.0',
          'id': r.json['id'],
          'result': {
            'protocolVersion': '2025-11-25',
            'capabilities': {'tools': {}},
          },
        });
      }
      if (r.json['method'] == 'notifications/initialized') {
        return ApiResponse(202, const {}, const Stream.empty());
      }
      calls++;
      return jsonResponse({
        'jsonrpc': '2.0',
        'id': -1,
        'result': {'content': []},
      });
    });
    final client = McpClient(
      transport,
      McpConnection(id: 'x', name: 'X', url: 'https://example.org/mcp'),
    );
    await client.initialize(cancel: CancelToken());
    await expectLater(
      client.callTool('run', {}, cancel: CancelToken()),
      throwsA(isA<AppFailure>()),
    );
    expect(calls, 1);
  });
  test(
    'cancelling a dispatched tool sends a bounded cancellation notification without retry',
    () async {
      final started = Completer<void>();
      final cancelled = Completer<void>();
      final transport = FakeTransport((r) async {
        final request = r.json;
        if (request['method'] == 'initialize') {
          return jsonResponse({
            'jsonrpc': '2.0',
            'id': request['id'],
            'result': {
              'protocolVersion': '2025-11-25',
              'capabilities': {'tools': {}},
            },
          });
        }
        if (request['method'] == 'notifications/initialized') {
          return ApiResponse(202, const {}, const Stream.empty());
        }
        if (request['method'] == 'notifications/cancelled') {
          cancelled.complete();
          return ApiResponse(202, const {}, const Stream.empty());
        }
        started.complete();
        await r.cancel!.whenCancelled;
        throw const AppFailure(FailureKind.cancelled, 'cancelled fixture');
      });
      final client = McpClient(
        transport,
        McpConnection(id: 'x', name: 'X', url: 'https://example.org/mcp'),
      );
      final token = CancelToken();
      await client.initialize(cancel: token);
      final pending = client.callTool('run', {}, cancel: token);
      final failed = expectLater(pending, throwsA(isA<AppFailure>()));
      await started.future;
      token.cancel();
      await failed;
      await cancelled.future.timeout(const Duration(seconds: 1));
      final call = transport.requests.singleWhere(
        (r) => r.json['method'] == 'tools/call',
      );
      final notification = transport.requests.singleWhere(
        (r) => r.json['method'] == 'notifications/cancelled',
      );
      expect(notification.json['params']['requestId'], call.json['id']);
      expect(notification.cancel?.isCancelled, isFalse);
    },
  );
  test(
    'explicit close releases the negotiated session without replaying any action',
    () async {
      final transport = FakeTransport((r) {
        if (r.method == 'DELETE') {
          return ApiResponse(204, const {}, const Stream.empty());
        }
        if (r.json['method'] == 'notifications/initialized') {
          return ApiResponse(202, const {}, const Stream.empty());
        }
        return jsonResponse(
          {
            'jsonrpc': '2.0',
            'id': r.json['id'],
            'result': {
              'protocolVersion': '2025-11-25',
              'capabilities': {'tools': {}},
            },
          },
          headers: {'mcp-session-id': 'owned-session'},
        );
      });
      final client = McpClient(
        transport,
        McpConnection(
          id: 'x',
          name: 'X',
          url: 'https://example.org/mcp',
          bearerToken: 'connection-only',
        ),
      );
      await client.initialize(cancel: CancelToken());
      await client.close();
      expect(client.initialized, isFalse);
      expect(transport.requests.last.method, 'DELETE');
      expect(
        transport.requests.last.headers['MCP-Session-Id'],
        'owned-session',
      );
      expect(
        transport.requests.last.headers['Authorization'],
        'Bearer connection-only',
      );
      expect(transport.requests.where((r) => r.method == 'DELETE').length, 1);
      await client.close();
      expect(transport.requests.where((r) => r.method == 'DELETE').length, 1);
    },
  );
}
