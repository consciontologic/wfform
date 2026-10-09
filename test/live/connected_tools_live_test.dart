// Explicitly opt-in. Keys are read from ignored files, never command arguments.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/config/app_config.dart';
import 'package:wfform/features/chat/chat_controller.dart';
import 'package:wfform/features/models/health.dart';
import 'package:wfform/features/models/model.dart';
import 'package:wfform/features/tools/mcp_client.dart';
import 'package:wfform/features/tools/tools.dart';
import 'package:wfform/shared/diagnostics.dart';
import 'package:wfform/shared/transport.dart';

void main() {
  final env = Platform.environment;
  final enabled = env['WFFORM_LIVE_TOOLS'] == '1';
  String setting(String key) {
    final value = env[key];
    if (value == null || value.isEmpty) {
      throw StateError('Missing $key for explicit live proof.');
    }
    return value;
  }

  final report = <String, dynamic>{};
  late FreeModel model;
  late AppConfig config;
  late Diagnostics diagnostics;
  late HealthController health;
  late _CountingTransport transport;

  setUpAll(() async {
    if (!enabled) return;
    final apiKey = File(
      setting('WFFORM_LIVE_KEY_FILE'),
    ).readAsStringSync().trim();
    final catalog =
        jsonDecode(File(setting('WFFORM_LIVE_CATALOG_FILE')).readAsStringSync())
            as Map;
    final models = catalog['data'] as List;
    final id = setting('WFFORM_LIVE_MODEL');
    final entry = models.whereType<Map<String, dynamic>>().singleWhere(
      (entry) => entry['id'] == id,
    );
    model = FreeModel.fromJson(entry);
    expect(
      model.supportedParameters.contains('tools'),
      isTrue,
      reason:
          'The current catalog must advertise tools for this exact free model.',
    );
    config = AppConfig(
      apiKey: apiKey,
      firstResponseTimeout: const Duration(seconds: 45),
      streamIdleTimeout: const Duration(seconds: 30),
      streamOverallTimeout: const Duration(seconds: 90),
    );
    transport = _CountingTransport(HttpApiTransport());
    diagnostics = Diagnostics(config);
    health = HealthController(
      config: config,
      transport: transport,
      diagnostics: diagnostics,
    );
    final observation = await health.check(model);
    expect(
      observation.failure == null,
      isTrue,
      reason:
          'One real preflight must succeed; failure is never retried automatically.',
    );
    report['model'] = model.id;
    report['preflight'] = observation.failure == null;
  });
  tearDownAll(() async {
    if (!enabled) return;
    report['apiRequests'] = transport.apiRequests;
    report['mcpRequests'] = transport.mcpRequests;
    report['zeroPriceGuards'] = transport.zeroPriceGuards;
    report['automaticRetries'] = 0;
    report['diagnostics'] = diagnostics.events
        .map((event) => event.toJson())
        .toList();
    final path = env['WFFORM_LIVE_REPORT_FILE'];
    if (path != null) {
      File(
        path,
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    }
    health.dispose();
    diagnostics.dispose();
  });
  ChatController controller() => ChatController(
    config: config,
    transport: transport,
    diagnostics: diagnostics,
    health: health,
  );

  test(
    'LIVE ordinary chat through actual ChatController and direct transport',
    () async {
      final chat = controller();
      addTearDown(chat.dispose);
      await chat.send(model, 'Reply with exactly WFFORM_CHAT_OK.');
      expect(
        chat.error == null,
        isTrue,
        reason: 'Actual ordinary inference must complete successfully.',
      );
      expect(chat.messages.last.complete, isTrue);
      expect(chat.messages.last.content.contains('WFFORM_CHAT_OK'), isTrue);
      expect(
        chat.messages.any((message) => message.toolCalls.isNotEmpty),
        isFalse,
      );
      report['ordinaryChat'] = {
        'passed': true,
        'usage': chat.messages.last.usage?.toJson(),
      };
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  Future<void> exercise(
    McpConnection connection,
    String originalName,
    Map<String, dynamic> arguments,
    String expected,
    String key,
  ) async {
    final registry = ToolRegistry(transport);
    await registry.connect(connection, cancel: CancelToken());
    final selected = registry.tools.singleWhere(
      (tool) => tool.originalName == originalName,
    );
    var approvals = 0;
    final chat = controller()
      ..tools = registry
      ..approveTool = (tool, args) async {
        approvals++;
        // Proof authorizes only the specified read-only fixture operation.
        return tool.name == selected.name &&
            jsonEncode(args) == jsonEncode(arguments) &&
            approvals == 1;
      };
    addTearDown(chat.dispose);
    chat.setEnabledTools({selected.name});
    if (model.supportedParameters.contains('max_tokens')) {
      chat.setRequestParameters({'max_tokens': 2048});
    }
    await chat.send(
      model,
      'Call the enabled tool ${selected.name} exactly once with these arguments: ${jsonEncode(arguments)}. Its result contains a proof value unknown to you. Then respond with the exact proof value from the tool result. Do not invent a value and do not call any tool again.',
    );
    expect(
      chat.error == null,
      isTrue,
      reason: '$key should finish its real model/tool/model exchange.',
    );
    final requested = chat.messages
        .expand((message) => message.toolCalls)
        .toList();
    expect(
      requested.length,
      1,
      reason: 'The actual model must request exactly one approved tool call.',
    );
    expect(approvals, 1);
    expect(chat.messages.where((message) => message.role == 'tool').length, 1);
    expect(
      chat.messages.last.content.contains(expected),
      isTrue,
      reason:
          'The final model answer must contain the fresh value only returned by the tool.',
    );
    validateToolTranscript(
      chat.messages.map((message) => message.toJson()).toList(),
    );
    final saved = chat.exportSession();
    final apiBefore = transport.apiRequests;
    final mcpBefore = transport.mcpRequests;
    chat.clear();
    expect(chat.restoreSession(saved), isTrue);
    expect(transport.apiRequests, apiBefore);
    expect(transport.mcpRequests, mcpBefore);
    expect(chat.canRetry, isFalse);
    report[key] = {
      'passed': true,
      'toolCalls': requested.length,
      'approvals': approvals,
      'restoredWithoutExecution': true,
      'usage': [
        for (final message in chat.messages)
          if (message.usage != null) message.usage!.toJson(),
      ],
    };
  }

  test(
    'LIVE user supplied Streamable HTTP MCP through the actual client',
    () async {
      final random = Random.secure();
      final nonce = List.generate(
        18,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final pairing = List.generate(
        24,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var toolCalls = 0;
      server.listen((request) async {
        if (request.headers.value(HttpHeaders.authorizationHeader) !=
            'Bearer $pairing') {
          request.response.statusCode = 401;
          await request.response.close();
          return;
        }
        final rpc = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        if (rpc['method'] == 'notifications/initialized') {
          request.response.statusCode = 202;
          await request.response.close();
          return;
        }
        final result = switch (rpc['method']) {
          'initialize' => {
            'protocolVersion': '2025-11-25',
            'capabilities': {'tools': {}},
            'serverInfo': {
              'name': 'wfform-independent-live-fixture',
              'version': '1',
            },
          },
          'tools/list' => {
            'tools': [
              {
                'name': 'read_proof',
                'description': 'Return a fresh proof value.',
                'inputSchema': {
                  'type': 'object',
                  'properties': <String, dynamic>{},
                  'additionalProperties': false,
                },
              },
            ],
          },
          'tools/call' => {
            'content': [
              {'type': 'text', 'text': nonce},
            ],
          },
          _ => throw StateError(
            'Unexpected MCP method in bounded live fixture',
          ),
        };
        if (rpc['method'] == 'tools/call') toolCalls++;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({'jsonrpc': '2.0', 'id': rpc['id'], 'result': result}),
        );
        await request.response.close();
      });
      await exercise(
        McpConnection(
          id: 'independent-live-proof',
          name: 'Independent MCP fixture',
          url: 'http://127.0.0.1:${server.port}/mcp',
          bearerToken: pairing,
        ),
        'read_proof',
        {},
        nonce,
        'userSuppliedMcp',
      );
      expect(toolCalls, 1);
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'LIVE compiled wfformcomp through the actual client',
    () async {
      final token = File(
        setting('WFFORM_LIVE_PAIRING_FILE'),
      ).readAsStringSync().trim();
      final arguments =
          jsonDecode(setting('WFFORM_LIVE_TOOL_ARGS')) as Map<String, dynamic>;
      final expected = File(
        setting('WFFORM_LIVE_EXPECT_FILE'),
      ).readAsStringSync().trim();
      await exercise(
        McpConnection(
          id: 'wfformcomp-live-proof',
          name: 'wfformcomp',
          url: setting('WFFORM_LIVE_MCP_URL'),
          bearerToken: token,
        ),
        setting('WFFORM_LIVE_TOOL'),
        arguments,
        expected,
        'compiledCompanion',
      );
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

/// Counts boundaries and guards only. Never records headers, requests or output.
class _CountingTransport implements ApiTransport {
  _CountingTransport(this.inner);
  final ApiTransport inner;
  int apiRequests = 0;
  int mcpRequests = 0;
  bool zeroPriceGuards = true;
  @override
  Future<ApiResponse> send(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    Object? body,
    required Duration timeout,
    CancelToken? cancel,
  }) {
    if (uri.host == 'openrouter.ai') {
      if (method == 'POST') {
        apiRequests++;
        final request = jsonDecode(body as String) as Map;
        final provider = request['provider'] as Map;
        zeroPriceGuards &=
            provider['allow_fallbacks'] == false &&
            (provider['max_price'] as Map).values.every(
              (value) => value == '0',
            );
      }
    } else {
      mcpRequests++;
    }
    return inner.send(
      method,
      uri,
      headers: headers,
      body: body,
      timeout: timeout,
      cancel: cancel,
    );
  }
}
