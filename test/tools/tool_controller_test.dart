import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/config/app_config.dart';
import 'package:wfform/features/chat/chat_controller.dart';
import 'package:wfform/features/models/health.dart';
import 'package:wfform/features/tools/mcp_client.dart';
import 'package:wfform/features/tools/tools.dart';
import 'package:wfform/shared/diagnostics.dart';
import 'package:wfform/shared/transport.dart';
import '../chat/fakes.dart';
import 'tool_protocol_test.dart' show toolModel, toolDelta;

void main() {
  late ChatController chat;
  late HealthController health;
  late Diagnostics diagnostics;
  late FakeTransport transport;
  late ToolRegistry registry;
  var executions = 0;
  late String name;

  Future<void> create(
    FutureOr<ApiResponse> Function(SentRequest) responder, {
    bool failTool = false,
    bool toolsAvailable = true,
    bool uncertainTool = false,
    int maxMessages = 80,
  }) async {
    executions = 0;
    registry = ToolRegistry(
      FakeTransport((r) {
        final request = r.json;
        switch (request['method']) {
          case 'initialize':
            return jsonResponse({
              'jsonrpc': '2.0',
              'id': request['id'],
              'result': {
                'protocolVersion': '2025-11-25',
                'capabilities': {'tools': {}},
              },
            });
          case 'notifications/initialized':
            return ApiResponse(202, const {}, const Stream.empty());
          case 'tools/list':
            return jsonResponse({
              'jsonrpc': '2.0',
              'id': request['id'],
              'result': {
                'tools': [
                  {
                    'name': 'multiply',
                    'description': 'Multiply two numbers.',
                    'inputSchema': {
                      'type': 'object',
                      'properties': {
                        'a': {'type': 'number'},
                        'b': {'type': 'number'},
                      },
                      'required': ['a', 'b'],
                      'additionalProperties': false,
                    },
                  },
                ],
              },
            });
          case 'tools/call':
            executions++;
            if (failTool) {
              throw const AppFailure(
                FailureKind.network,
                'fixture interrupted after dispatch',
              );
            }
            return jsonResponse({
              'jsonrpc': '2.0',
              'id': request['id'],
              'result': {
                if (uncertainTool) '_meta': {'wfform.com/outcome': 'uncertain'},
                if (uncertainTool) 'isError': true,
                'content': [
                  {'type': 'text', 'text': '432'},
                ],
              },
            });
          default:
            throw StateError('unexpected');
        }
      }),
    );
    await registry.connect(
      McpConnection(
        id: 'fixture',
        name: 'Fixture',
        url: 'https://example.org/mcp',
      ),
      cancel: CancelToken(),
    );
    name = registry.tools.single.name;
    final config = AppConfig(apiKey: 'test', maxMessages: maxMessages);
    diagnostics = Diagnostics(config);
    transport = FakeTransport(responder);
    health = HealthController(
      config: config,
      transport: transport,
      diagnostics: diagnostics,
    )..recordSuccess(toolModel.id);
    chat =
        ChatController(
            config: config,
            transport: transport,
            diagnostics: diagnostics,
            health: health,
            toolsAvailable: toolsAvailable,
          )
          ..tools = registry
          ..approveTool = ((_, _) async => true);
    chat.setEnabledTools({name});
  }

  tearDown(() {
    chat.dispose();
    health.dispose();
    diagnostics.dispose();
  });
  String call({String args = '{"a":18,"b":24}', String id = 'call1'}) =>
      '${toolDelta({
        'tool_calls': [
          {
            'index': 0,
            'id': id,
            'type': 'function',
            'function': {'name': name, 'arguments': args},
          },
        ],
      }, finish: 'tool_calls')}data: [DONE]\n\n';

  test(
    'mobile refuses unsolicited tool calls even with a live registry and approval handler',
    () async {
      var approvals = 0;
      await create((_) => streamResponse(call()), toolsAvailable: false);
      chat.approveTool = (_, _) async {
        approvals++;
        return true;
      };
      await chat.send(toolModel, 'Plain chat');
      expect(transport.requests.single.json, isNot(contains('tools')));
      expect(chat.error?.kind, FailureKind.schema);
      expect(chat.error?.message, contains('Nothing was executed.'));
      expect(executions, 0);
      expect(approvals, 0);
    },
  );

  test(
    'runs approved tool, returns result, persists complete exchange without replay on restore',
    () async {
      var turns = 0;
      await create(
        (r) => streamResponse(
          ++turns == 1 ? call() : '${delta('432')}data: [DONE]\n\n',
        ),
      );
      await chat.send(toolModel, 'Multiply 18 by 24');
      expect(chat.error, isNull);
      expect(executions, 1);
      expect(chat.messages.map((m) => m.role), [
        'user',
        'assistant',
        'tool',
        'assistant',
      ]);
      expect(chat.messages[1].toolCalls.single.id, 'call1');
      expect(chat.messages[2].toolCallId, 'call1');
      expect(chat.messages.last.content, '432');
      final history = transport.requests.last.json['messages'] as List;
      expect(history[1]['tool_calls'][0]['function']['name'], name);
      expect(history[2]['tool_call_id'], 'call1');
      final saved = chat.exportSession();
      chat.clear();
      expect(chat.restoreSession(saved), isTrue);
      expect(chat.enabledTools, {name});
      expect(chat.messages[1].toolCalls.single.arguments, '{"a":18,"b":24}');
      expect(executions, 1);
      expect(chat.canRetry, isFalse);
    },
  );

  test(
    'denied and malformed arguments never invoke MCP and become tool errors',
    () async {
      var turns = 0;
      var malformed = true;
      await create(
        (r) => streamResponse(
          ++turns == 1
              ? call(
                  args: malformed
                      ? '{"a":"invalid","b":24}'
                      : '{"a":18,"b":24}',
                )
              : '${delta('invalid')}data: [DONE]\n\n',
        ),
      );
      await chat.send(toolModel, 'calculate');
      expect(executions, 0);
      expect(chat.messages[2].content, contains('Invalid tool arguments'));
      turns = 0;
      chat.clear();
      chat.setEnabledTools({name});
      chat.approveTool = (_, _) async => false;
      malformed = false;
      await chat.send(toolModel, 'calculate');
      expect(executions, 0);
      expect(chat.messages[2].content, contains('did not approve'));
    },
  );

  test(
    'failed final model round cannot retry and duplicate an executed tool',
    () async {
      var turns = 0;
      await create(
        (r) => streamResponse(++turns == 1 ? call() : delta('partial')),
      );
      await chat.send(toolModel, 'calculate');
      expect(chat.error, isNotNull);
      expect(executions, 1);
      expect(chat.messages[2].role, 'tool');
      expect(chat.canRetry, isFalse);
      final saved = chat.exportSession();
      chat.clear();
      expect(chat.restoreSession(saved), isTrue);
      expect(chat.canRetry, isFalse);
      await chat.retry(toolModel);
      expect(executions, 1);
    },
  );

  test('loops stop at bound without another dispatch', () async {
    var turns = 0;
    await create((r) => streamResponse(call(id: 'call${++turns}')));
    await chat.send(toolModel, 'calculate');
    expect(turns, lessThanOrEqualTo(5));
    expect(executions, lessThanOrEqualTo(4));
    expect(chat.error, isNotNull);
    expect(chat.canRetry, isFalse);
  });

  test(
    'cancelling pending approval preserves a closed tool group and never executes',
    () async {
      await create((r) => streamResponse(call()));
      final pending = Completer<bool>();
      final asked = Completer<void>();
      chat.approveTool = (_, _) {
        asked.complete();
        return pending.future;
      };
      final work = chat.send(toolModel, 'calculate');
      await asked.future;
      expect(chat.activeModelId, toolModel.id);
      chat.cancel();
      await work;
      expect(executions, 0);
      expect(chat.busy, isFalse);
      expect(chat.canRetry, isFalse);
      validateToolTranscript(chat.messages.map((m) => m.toJson()).toList());
      pending.complete(true);
      await Future<void>.delayed(Duration.zero);
      expect(executions, 0);
    },
  );

  test(
    'reloading a pending tool snapshot closes its outcome without replay',
    () async {
      await create((r) => streamResponse(call()));
      final pending = Completer<bool>();
      final asked = Completer<void>();
      chat.approveTool = (_, _) {
        asked.complete();
        return pending.future;
      };
      final work = chat.send(toolModel, 'calculate');
      await asked.future;
      final snapshot = chat.exportSession();
      chat.cancel();
      await work;
      pending.complete(false);
      chat.clear();
      expect(chat.restoreSession(snapshot), isTrue);
      expect(chat.messages.last.role, 'tool');
      expect(chat.messages.last.content, contains('No tool was resumed'));
      expect(chat.canRetry, isFalse);
      expect(executions, 0);
      validateToolTranscript(chat.messages.map((m) => m.toJson()).toList());
    },
  );

  test('repeated call ID is rejected before a second execution', () async {
    await create((r) => streamResponse(call()));
    await chat.send(toolModel, 'calculate');
    expect(executions, 1);
    expect(chat.error, isNotNull);
    validateToolTranscript(chat.messages.map((m) => m.toJson()).toList());
  });

  test(
    'lost tool response records unknown outcome and stops without model or tool retry',
    () async {
      await create((r) => streamResponse(call()), failTool: true);
      await chat.send(toolModel, 'calculate');
      expect(executions, 1);
      expect(transport.requests.length, 1);
      expect(chat.messages[2].content, contains('outcome is unknown'));
      expect(chat.canRetry, isFalse);
      expect(chat.error, isNotNull);
      validateToolTranscript(chat.messages.map((m) => m.toJson()).toList());
    },
  );

  test(
    'identically named tools from different connections have stable distinct names',
    () async {
      await create((r) => streamResponse(call()));
      final firstName = registry.tools.single.name;
      await registry.connect(
        McpConnection(
          id: 'second',
          name: 'Second',
          url: 'https://example.org/mcp',
        ),
        cancel: CancelToken(),
      );
      expect(registry.tools.map((tool) => tool.name).toSet().length, 2);
      expect(registry.tools.first.name, firstName);
      await registry.connect(
        McpConnection(
          id: 'fixture',
          name: 'Fixture',
          url: 'https://example.org/mcp',
        ),
        cancel: CancelToken(),
      );
      expect(
        registry.tools
            .singleWhere((tool) => tool.connectionId == 'fixture')
            .name,
        firstName,
      );
    },
  );

  test(
    'near-limit parallel tool group closes within maxMessages and restores',
    () async {
      var turns = 0;
      await create((r) {
        turns++;
        return streamResponse(
          '${toolDelta({
            'tool_calls': [
              for (var i = 0; i < 16; i++) {
                  'index': i,
                  'id': 'round${turns}_$i',
                  'type': 'function',
                  'function': {'name': name, 'arguments': '{"a":18,"b":24}'},
                },
            ],
          }, finish: 'tool_calls')}data: [DONE]\n\n',
        );
      }, maxMessages: 200);
      expect(
        chat.restoreSession(
          jsonEncode({
            'version': 1,
            'messages': [
              for (var i = 0; i < 180; i++)
                {
                  'role': i.isEven ? 'user' : 'assistant',
                  'content': 'turn $i',
                  'reasoning': '',
                  'complete': true,
                  'modelId': toolModel.id,
                },
            ],
          }),
        ),
        isTrue,
      );
      chat.setEnabledTools({name});
      await chat.send(toolModel, 'calculate');
      expect(
        executions,
        16,
        reason:
            'A reserved, approved group must execute completely before capacity stops further inference.',
      );
      expect(
        turns,
        1,
        reason:
            'Do not start another inference without room to close a maximum-size group.',
      );
      expect(chat.messages.length, lessThanOrEqualTo(200));
      validateToolTranscript(chat.messages.map((m) => m.toJson()).toList());
      final saved = chat.exportSession();
      chat.clear();
      expect(chat.restoreSession(saved), isTrue);
      expect(executions, 16);
      expect(chat.canRetry, isFalse);
    },
  );

  test(
    'structured uncertain outcome stops queued calls and further inference',
    () async {
      await create(
        (r) => streamResponse(
          '${toolDelta({
            'tool_calls': [
              for (var i = 0; i < 2; i++) {
                  'index': i,
                  'id': 'uncertain_$i',
                  'type': 'function',
                  'function': {'name': name, 'arguments': '{"a":18,"b":24}'},
                },
            ],
          }, finish: 'tool_calls')}data: [DONE]\n\n',
        ),
        uncertainTool: true,
      );
      await chat.send(toolModel, 'calculate');
      expect(executions, 1);
      expect(transport.requests.length, 1);
      expect(chat.error, isNotNull);
      expect(chat.messages[2].content, contains('wfform.com/outcome'));
      expect(chat.messages[3].content, contains('not executed'));
      expect(chat.canRetry, isFalse);
      validateToolTranscript(chat.messages.map((m) => m.toJson()).toList());
      final saved = chat.exportSession();
      chat.clear();
      expect(chat.restoreSession(saved), isTrue);
      expect(chat.canRetry, isFalse);
      expect(executions, 1);
    },
  );

  test(
    'unsolicited tools at ordinary-chat message limit are rejected without growing history',
    () async {
      await create(
        (r) => streamResponse(
          '${toolDelta({
            'tool_calls': [
              for (var i = 0; i < 16; i++) {
                  'index': i,
                  'id': 'unexpected_$i',
                  'type': 'function',
                  'function': {'name': name, 'arguments': '{"a":18,"b":24}'},
                },
            ],
          }, finish: 'tool_calls')}data: [DONE]\n\n',
        ),
        maxMessages: 200,
      );
      expect(
        chat.restoreSession(
          jsonEncode({
            'version': 1,
            'messages': [
              for (var i = 0; i < 198; i++)
                {
                  'role': i.isEven ? 'user' : 'assistant',
                  'content': 'turn $i',
                  'reasoning': '',
                  'complete': true,
                  'modelId': toolModel.id,
                },
            ],
          }),
        ),
        isTrue,
      );
      expect(chat.enabledTools, isEmpty);
      await chat.send(toolModel, 'ordinary chat');
      expect(chat.error, isNotNull);
      expect(executions, 0);
      expect(transport.requests.length, 1);
      expect(transport.requests.single.json.containsKey('tools'), isFalse);
      expect(chat.messages.length, 200);
      expect(
        chat.messages.any(
          (message) => message.toolCalls.isNotEmpty || message.role == 'tool',
        ),
        isFalse,
      );
      final saved = chat.exportSession();
      chat.clear();
      expect(chat.restoreSession(saved), isTrue);
      expect(executions, 0);
    },
  );

  test('restore refuses orphan tool results', () async {
    await create((r) => streamResponse('${delta('ok')}data: [DONE]\n\n'));
    expect(
      chat.restoreSession(
        jsonEncode({
          'version': 1,
          'messages': [
            {
              'role': 'tool',
              'toolCallId': 'missing',
              'content': 'private',
              'reasoning': '',
              'complete': true,
            },
          ],
        }),
      ),
      isFalse,
    );
  });
}
