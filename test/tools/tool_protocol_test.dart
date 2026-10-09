import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/config/app_config.dart';
import 'package:wfform/features/chat/chat_api.dart';
import 'package:wfform/features/models/model.dart';
import 'package:wfform/features/tools/tools.dart';
import 'package:wfform/shared/transport.dart';
import 'package:wfform/shared/diagnostics.dart';
import '../chat/fakes.dart';

const toolModel = FreeModel(
  id: 'test/tools:free',
  name: 'Tools',
  supportedParameters: ['tools', 'tool_choice', 'max_tokens', 'temperature'],
);
String toolDelta(Map<String, dynamic> value, {String? finish}) =>
    'data: ${jsonEncode({
      'model': toolModel.id,
      'choices': [
        {'index': 0, 'delta': value, 'finish_reason': ?finish},
      ],
    })}\n\n';

void main() {
  test(
    'assembles interleaved tool fragments and preserves opaque reasoning',
    () async {
      final events = [
        toolDelta({
          'tool_calls': [
            {
              'index': 1,
              'id': 'second',
              'type': 'function',
              'function': {'name': 'lookup', 'arguments': '{"key":'},
            },
            {
              'index': 0,
              'id': 'first',
              'type': 'function',
              'function': {'name': 'multiply', 'arguments': '{"a":18,'},
            },
          ],
          'reasoning_details': [
            {
              'type': 'reasoning.encrypted',
              'data': 'opaque',
              'id': 'r',
              'format': 'vendor',
              'index': 0,
            },
          ],
        }),
        toolDelta({
          'tool_calls': [
            {
              'index': 0,
              'function': {'arguments': '"b":24}'},
            },
            {
              'index': 1,
              'function': {'arguments': '"x"}'},
            },
          ],
        }, finish: 'tool_calls'),
        'data: [DONE]\n\n',
      ].join();
      final api = ChatApi(
        const AppConfig(apiKey: 'test'),
        FakeTransport((_) => streamResponse(events, chunkSize: 1)),
      );
      final output = await api
          .stream(
            toolModel,
            const [
              {'role': 'user', 'content': 'calculate'},
            ],
            cancel: CancelToken(),
            tools: const [
              {
                'type': 'function',
                'function': {
                  'name': 'lookup',
                  'parameters': {'type': 'object'},
                },
              },
              {
                'type': 'function',
                'function': {
                  'name': 'multiply',
                  'parameters': {'type': 'object'},
                },
              },
            ],
          )
          .toList();
      expect(output.last.done, isTrue);
      expect(output.last.toolCalls.map((c) => c.id), ['first', 'second']);
      expect(output.last.toolCalls.first.arguments, '{"a":18,"b":24}');
      expect(output.last.reasoningDetails, [
        {
          'type': 'reasoning.encrypted',
          'data': 'opaque',
          'id': 'r',
          'format': 'vendor',
          'index': 0,
        },
      ]);
    },
  );

  test(
    'no overrides means upstream defaults; explicit zero preserved and tool routing required',
    () {
      final api = ChatApi(
        const AppConfig(apiKey: 'test'),
        FakeTransport((_) => endpoints()),
      );
      final ordinary = api.requestBody(toolModel, const []);
      expect(ordinary.containsKey('max_tokens'), isFalse);
      expect(ordinary.containsKey('reasoning'), isFalse);
      final request = api.requestBody(
        toolModel,
        const [],
        parameters: {'temperature': 0},
        tools: const [
          {
            'type': 'function',
            'function': {
              'name': 'multiply',
              'parameters': {'type': 'object'},
            },
          },
        ],
      );
      expect(request['temperature'], 0);
      expect(request['provider']['require_parameters'], isTrue);
      expect(request['provider']['max_price']['completion'], '0');
    },
  );

  test('local serialization round-trips raw tool arguments exactly', () {
    const call = ToolCall(
      id: 'call1',
      name: 'multiply',
      arguments: '{ "a":18 }',
    );
    expect(ToolCall.fromJson(call.toJson()).arguments, '{ "a":18 }');
  });
  test(
    'API rejects tool calls when no definitions were provided or tool_choice is none',
    () async {
      final api = ChatApi(
        const AppConfig(apiKey: 'test'),
        FakeTransport(
          (_) => streamResponse(
            '${toolDelta({
              'tool_calls': [
                {
                  'index': 0,
                  'id': 'unexpected',
                  'type': 'function',
                  'function': {'name': 'multiply', 'arguments': '{}'},
                },
              ],
            }, finish: 'tool_calls')}data: [DONE]\n\n',
          ),
        ),
      );
      await expectLater(
        api.stream(toolModel, const [
          {'role': 'user', 'content': 'ordinary'},
        ], cancel: CancelToken()),
        emitsError(isA<AppFailure>()),
      );
      await expectLater(
        api.stream(
          toolModel,
          const [
            {'role': 'user', 'content': 'ordinary'},
          ],
          cancel: CancelToken(),
          parameters: {'tool_choice': 'none'},
          tools: const [
            {
              'type': 'function',
              'function': {
                'name': 'multiply',
                'parameters': {'type': 'object'},
              },
            },
          ],
        ),
        emitsError(isA<AppFailure>()),
      );
    },
  );
}
