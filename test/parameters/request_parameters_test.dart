import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/features/models/model.dart';
import 'package:wfform/features/parameters/request_parameters.dart';

FreeModel modelWith(List<String> keys) => FreeModel(
  id: 'fixture/model:free',
  name: 'Parameter fixture',
  contextLength: 8192,
  topProvider: const {'max_completion_tokens': 4096},
  supportedParameters: keys,
);

void main() {
  test(
    'mandatory reasoning cannot be disabled through either effort field',
    () {
      final model = FreeModel.fromJson({
        ...modelWith([
          'reasoning',
          'reasoning_effort',
          'include_reasoning',
        ]).toJson(),
        'reasoning': {'mandatory': true, 'supported_efforts': null},
      });
      for (final overrides in [
        {
          'reasoning': {'enabled': false},
        },
        {
          'reasoning': {'effort': 'none'},
        },
        {'reasoning_effort': 'none'},
      ]) {
        expect(RequestParameters.validate(model, overrides).isValid, false);
      }
      expect(RequestParameters.toRequest(model, {'include_reasoning': false}), {
        'reasoning': {'exclude': true},
      });
      expect(RequestParameters.toRequest(model, {}), isEmpty);
    },
  );

  test(
    'reasoning effort and budget honor per-model advertised capabilities',
    () {
      FreeModel restricted(Map<String, dynamic> reasoning) =>
          FreeModel.fromJson({
            ...modelWith(['reasoning', 'reasoning_effort']).toJson(),
            'reasoning': reasoning,
          });
      final model = restricted({
        'mandatory': false,
        'supported_efforts': ['high', 'medium'],
        'supports_max_tokens': true,
      });
      for (final overrides in [
        {
          'reasoning': {'effort': 'low'},
        },
        {'reasoning_effort': 'xhigh'},
      ]) {
        expect(RequestParameters.validate(model, overrides).isValid, false);
      }
      expect(
        RequestParameters.toRequest(model, {'reasoning_effort': 'medium'}),
        {'reasoning_effort': 'medium'},
      );
      expect(
        RequestParameters.toRequest(model, {
          'reasoning': {'max_tokens': 100},
        }),
        {
          'reasoning': {'max_tokens': 100},
        },
      );
      final noEffort = restricted({'mandatory': true});
      expect(
        RequestParameters.validate(noEffort, {
          'reasoning': {'effort': 'high'},
        }).isValid,
        false,
      );
      expect(
        RequestParameters.validate(noEffort, {
          'reasoning_effort': 'high',
        }).isValid,
        false,
      );
      expect(
        RequestParameters.validate(noEffort, {
          'reasoning': {'max_tokens': 100},
        }).isValid,
        false,
      );
      final allEfforts = restricted({'supported_efforts': null});
      expect(
        RequestParameters.validate(allEfforts, {
          'reasoning_effort': 'low',
        }).isValid,
        true,
      );
    },
  );

  test('omission preserves provider defaults while zero and false survive', () {
    final model = modelWith(['temperature', 'logprobs', 'reasoning']);
    expect(RequestParameters.toRequest(model, {}), isEmpty);
    expect(
      RequestParameters.toRequest(model, {'temperature': 0, 'logprobs': false}),
      {'temperature': 0, 'logprobs': false},
    );
  });

  test('unsupported fields, reserved routing and null values are rejected', () {
    final model = modelWith(['temperature', 'vendor_new', 'provider']);
    for (final input in [
      {'top_p': 0.5},
      {'temperature': null},
      {'vendor_new': 4},
      {
        'provider': {'allow_fallbacks': true},
      },
      {'model': 'paid/model'},
    ]) {
      final result = RequestParameters.validate(model, input);
      expect(result.isValid, false, reason: input.keys.join());
      expect(result.values, isEmpty);
    }
    expect(RequestParameters.definition('vendor_new'), isNull);
  });

  test('numeric values obey types, finite values and documented ranges', () {
    final model = modelWith([
      'temperature',
      'top_p',
      'top_k',
      'frequency_penalty',
      'presence_penalty',
      'repetition_penalty',
      'min_p',
      'top_a',
      'seed',
      'max_tokens',
    ]);
    for (final input in [
      {'temperature': 2.1},
      {'temperature': double.nan},
      {'top_p': -0.1},
      {'top_k': 0.5},
      {'frequency_penalty': -3},
      {'presence_penalty': 3},
      {'repetition_penalty': 3},
      {'min_p': 2},
      {'top_a': -1},
      {'seed': '1'},
      {'max_tokens': 0},
      {'max_tokens': 4097},
    ]) {
      expect(
        RequestParameters.validate(model, input).isValid,
        false,
        reason: input.keys.join(),
      );
    }
    expect(RequestParameters.toRequest(model, {'seed': 0, 'top_k': 0}), {
      'seed': 0,
      'top_k': 0,
    });
  });

  test('output aliases cannot silently override each other', () {
    final result = RequestParameters.validate(
      modelWith(['max_tokens', 'max_completion_tokens']),
      {'max_tokens': 10, 'max_completion_tokens': 20},
    );
    expect(
      result.errors.keys,
      containsAll(['max_tokens', 'max_completion_tokens']),
    );
  });

  test('top logprobs requires explicit true logprobs', () {
    final model = modelWith(['logprobs', 'top_logprobs']);
    expect(
      RequestParameters.validate(model, {'top_logprobs': 0}).isValid,
      false,
    );
    expect(
      RequestParameters.validate(model, {
        'top_logprobs': 21,
        'logprobs': true,
      }).isValid,
      false,
    );
    expect(
      RequestParameters.toRequest(model, {'top_logprobs': 0, 'logprobs': true}),
      {'top_logprobs': 0, 'logprobs': true},
    );
  });

  test('reasoning aliases normalize without mutating the supplied map', () {
    final model = modelWith(['reasoning', 'include_reasoning']);
    final input = <String, dynamic>{
      'reasoning': {'enabled': true},
      'include_reasoning': false,
    };
    final request = RequestParameters.toRequest(model, input);
    expect(request, {
      'reasoning': {'enabled': true, 'exclude': true},
    });
    expect(input['reasoning'], {'enabled': true});
    expect(input['include_reasoning'], false);
    expect(RequestParameters.toRequest(model, {'include_reasoning': true}), {
      'reasoning': <String, dynamic>{},
    });
    expect(
      RequestParameters.toRequest(model, {'reasoning': <String, dynamic>{}}),
      {'reasoning': <String, dynamic>{}},
    );
  });

  test('reasoning conflicts and paid mode are refused', () {
    final model = modelWith([
      'reasoning',
      'reasoning_effort',
      'include_reasoning',
    ]);
    for (final input in [
      {
        'reasoning': {'effort': 'high', 'max_tokens': 100},
      },
      {
        'reasoning': {'effort': 'wrong'},
      },
      {
        'reasoning': {'exclude': true},
        'include_reasoning': true,
      },
      {
        'reasoning': {'effort': 'high'},
        'reasoning_effort': 'low',
      },
      {
        'reasoning': {'mode': 'pro'},
      },
      {
        'reasoning': {'surprise': true},
      },
      {
        'reasoning': {'enabled': false, 'effort': 'high'},
      },
    ]) {
      expect(
        RequestParameters.validate(model, input).isValid,
        false,
        reason: input.toString(),
      );
    }
  });

  test('structured_outputs is a capability mapped to response_format', () {
    final model = modelWith(['structured_outputs']);
    expect(
      RequestParameters.available(model).map((p) => p.key),
      containsAll(['structured_outputs', 'response_format']),
    );
    expect(
      RequestParameters.validate(model, {'structured_outputs': true}).isValid,
      false,
    );
    expect(
      RequestParameters.toRequest(model, {
        'response_format': {
          'type': 'json_schema',
          'json_schema': {
            'name': 'answer',
            'strict': true,
            'schema': {'type': 'object', 'properties': <String, dynamic>{}},
          },
        },
      }).containsKey('structured_outputs'),
      false,
    );
    expect(
      RequestParameters.validate(model, {
        'response_format': {'type': 'json_schema'},
      }).isValid,
      false,
    );
  });

  test('JSON parameter shapes and bounds are validated', () {
    final model = modelWith([
      'stop',
      'logit_bias',
      'response_format',
      'prediction',
    ]);
    for (final input in [
      {
        'stop': ['a', 'b', 'c', 'd', 'e'],
      },
      {
        'stop': [1],
      },
      {
        'logit_bias': {'12': 101},
      },
      {
        'logit_bias': {'not-token': 1},
      },
      {
        'response_format': {'type': 'execute'},
      },
      {
        'prediction': {'type': 'content', 'content': 12},
      },
    ]) {
      expect(RequestParameters.validate(model, input).isValid, false);
    }
    expect(
      RequestParameters.toRequest(model, {
        'stop': ['END'],
      }),
      {
        'stop': ['END'],
      },
    );
    expect(
      RequestParameters.toRequest(model, {
        'logit_bias': {'12': -100},
      }),
      {
        'logit_bias': {'12': -100},
      },
    );
  });

  test('tools are registry managed and tool choices use registered names', () {
    final model = modelWith(['tools', 'tool_choice', 'parallel_tool_calls']);
    expect(RequestParameters.validate(model, {'tools': []}).isValid, false);
    expect(
      RequestParameters.validate(model, {'tool_choice': 'required'}).isValid,
      false,
    );
    expect(
      RequestParameters.validate(model, {'parallel_tool_calls': false}).isValid,
      false,
    );
    expect(RequestParameters.toRequest(model, {'tool_choice': 'none'}), {
      'tool_choice': 'none',
    });
    final choice = {
      'type': 'function',
      'function': {'name': 'approved_tool'},
    };
    expect(
      RequestParameters.toRequest(
        model,
        {'tool_choice': choice},
        toolNames: {'approved_tool'},
      ),
      {'tool_choice': choice},
    );
    expect(
      RequestParameters.validate(
        model,
        {'tool_choice': choice},
        toolNames: {'other_tool'},
      ).isValid,
      false,
    );
  });

  test('hosted tools, plugins and search cannot bypass free-only policy', () {
    final model = modelWith([
      'web_search_options',
      'plugins',
      'service_tier',
      'tools',
    ]);
    for (final input in [
      {'web_search_options': <String, dynamic>{}},
      {
        'plugins': [
          {'id': 'web'},
        ],
      },
      {'service_tier': 'priority'},
      {
        'tools': [
          {'type': 'openrouter:web_search'},
        ],
      },
    ]) {
      expect(RequestParameters.validate(model, input).isValid, false);
    }
  });

  test(
    'combined overrides fit the conversation settings persistence limit',
    () {
      final model = modelWith([
        'response_format',
        'structured_outputs',
        'prediction',
        'metadata',
      ]);
      final result = RequestParameters.validate(model, {
        'response_format': {
          'type': 'json_schema',
          'json_schema': {
            'name': 'answer',
            'schema': {'description': 'a' * 32000},
          },
        },
        'prediction': {'type': 'content', 'content': 'b' * 32000},
        'metadata': {for (var i = 0; i < 8; i++) '$i': 'c' * 500},
      });
      expect(result.isValid, false);
      expect(result.errors['parameters'], contains('combined'));
    },
  );

  test(
    'all documented sampling entries have reviewed official information',
    () {
      for (final key in [
        'temperature',
        'top_p',
        'top_k',
        'min_p',
        'top_a',
        'seed',
        'frequency_penalty',
        'presence_penalty',
        'repetition_penalty',
        'max_tokens',
        'max_completion_tokens',
        'stop',
        'response_format',
        'structured_outputs',
        'logit_bias',
        'logprobs',
        'top_logprobs',
        'reasoning',
        'reasoning_effort',
        'include_reasoning',
        'verbosity',
        'tools',
        'tool_choice',
        'parallel_tool_calls',
        'web_search_options',
      ]) {
        final definition = RequestParameters.definition(key);
        expect(definition, isNotNull, reason: key);
        expect(definition!.description, isNotEmpty);
        expect(Uri.parse(definition.documentationUrl).host, 'openrouter.ai');
        expect(definition.reviewedAt, '2026-10-09');
      }
    },
  );
}
