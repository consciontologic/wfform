import 'dart:convert';

import '../models/model.dart';

enum ParameterKind {
  number,
  integer,
  boolean,
  enumeration,
  text,
  json,
  managed,
}

/// Human-readable metadata is reviewed separately from live capability names.
/// No definition carries a provider default: absence must remain absence.
class ParameterDefinition {
  const ParameterDefinition(
    this.key,
    this.description,
    this.kind, {
    this.minimum,
    this.maximum,
    this.choices = const [],
    this.unavailableReason,
    this.documentationUrl = RequestParameters.documentationUrl,
  });

  final String key;
  final String description;
  final ParameterKind kind;
  final num? minimum;
  final num? maximum;
  final List<String> choices;
  final String? unavailableReason;
  final String documentationUrl;
  String get reviewedAt => '2026-10-09';
  bool get editable => unavailableReason == null;
}

class ParameterValidation {
  const ParameterValidation({required this.errors, required this.values});
  final Map<String, String> errors;
  final Map<String, dynamic> values;
  bool get isValid => errors.isEmpty;
}

/// Allow-listed, capability-aware request overrides. This is a data validator,
/// not a tool executor. Unknown metadata never becomes an arbitrary request key.
abstract final class RequestParameters {
  static const documentationUrl =
      'https://openrouter.ai/docs/api_reference/parameters';
  static const chatDocumentationUrl =
      'https://openrouter.ai/docs/api/api-reference/chat/create-a-chat-completion';
  static const reasoningDocumentationUrl =
      'https://openrouter.ai/docs/guides/best-practices/reasoning-tokens';
  static const maxJsonCharacters = 32768;
  static const _efforts = [
    'none',
    'minimal',
    'low',
    'medium',
    'high',
    'xhigh',
    'max',
  ];
  static const _freePolicy =
      'Unavailable under the free-only policy: additional service charges cannot be guaranteed as zero.';
  static const definitions = <ParameterDefinition>[
    ParameterDefinition(
      'temperature',
      'Adjusts variation in generated text.',
      ParameterKind.number,
      minimum: 0,
      maximum: 2,
    ),
    ParameterDefinition(
      'top_p',
      'Limits cumulative probability of candidate tokens.',
      ParameterKind.number,
      minimum: 0,
      maximum: 1,
    ),
    ParameterDefinition(
      'top_k',
      'Limits the number of candidate tokens.',
      ParameterKind.integer,
      minimum: 0,
    ),
    ParameterDefinition(
      'min_p',
      'Filters relative to the likeliest token.',
      ParameterKind.number,
      minimum: 0,
      maximum: 1,
    ),
    ParameterDefinition(
      'top_a',
      'Filters candidates using the highest token probability.',
      ParameterKind.number,
      minimum: 0,
      maximum: 1,
    ),
    ParameterDefinition(
      'seed',
      'Requests repeatable sampling; results can still vary.',
      ParameterKind.integer,
    ),
    ParameterDefinition(
      'frequency_penalty',
      'Adjusts repetition according to token frequency.',
      ParameterKind.number,
      minimum: -2,
      maximum: 2,
    ),
    ParameterDefinition(
      'presence_penalty',
      'Adjusts repetition of previously used tokens.',
      ParameterKind.number,
      minimum: -2,
      maximum: 2,
    ),
    ParameterDefinition(
      'repetition_penalty',
      'Adjusts repetition relative to token probabilities.',
      ParameterKind.number,
      minimum: 0,
      maximum: 2,
    ),
    ParameterDefinition(
      'max_tokens',
      'Caps generated tokens, usually including reasoning.',
      ParameterKind.integer,
      minimum: 1,
    ),
    ParameterDefinition(
      'max_completion_tokens',
      'Alternative generated-token cap; choose only one cap.',
      ParameterKind.integer,
      minimum: 1,
    ),
    ParameterDefinition(
      'stop',
      'Ends generation when a stop sequence appears.',
      ParameterKind.json,
    ),
    ParameterDefinition(
      'response_format',
      'Requests text, JSON, or schema-constrained output.',
      ParameterKind.json,
    ),
    ParameterDefinition(
      'structured_outputs',
      'Advertises schema-constrained output support.',
      ParameterKind.managed,
      unavailableReason:
          'Capability only. Configure response_format with type json_schema; this name is not sent as a request field.',
    ),
    ParameterDefinition(
      'logit_bias',
      'Adjusts token likelihood using numeric token IDs.',
      ParameterKind.json,
    ),
    ParameterDefinition(
      'logprobs',
      'Requests output-token log probabilities.',
      ParameterKind.boolean,
    ),
    ParameterDefinition(
      'top_logprobs',
      'Requests alternative-token probabilities with logprobs enabled.',
      ParameterKind.integer,
      minimum: 0,
      maximum: 20,
    ),
    ParameterDefinition(
      'reasoning',
      'Configures reasoning effort, budget and returned information.',
      ParameterKind.json,
      documentationUrl: reasoningDocumentationUrl,
    ),
    ParameterDefinition(
      'reasoning_effort',
      'Shorthand for reasoning effort.',
      ParameterKind.enumeration,
      choices: _efforts,
    ),
    ParameterDefinition(
      'include_reasoning',
      'Deprecated control for returning reasoning.',
      ParameterKind.boolean,
    ),
    ParameterDefinition(
      'verbosity',
      'Adjusts response detail where supported.',
      ParameterKind.enumeration,
      choices: ['low', 'medium', 'high', 'xhigh', 'max'],
    ),
    ParameterDefinition(
      'tools',
      'Advertises tools the model may request.',
      ParameterKind.managed,
      unavailableReason:
          'Managed by approved tool connections. Enable tools in Connections; arbitrary tool definitions are not accepted here.',
    ),
    ParameterDefinition(
      'tool_choice',
      'Controls whether the model requests a tool.',
      ParameterKind.json,
    ),
    ParameterDefinition(
      'parallel_tool_calls',
      'Allows multiple tool requests in one response.',
      ParameterKind.boolean,
    ),
    ParameterDefinition(
      'web_search_options',
      'Configures provider-hosted web search.',
      ParameterKind.managed,
      unavailableReason: _freePolicy,
    ),
    ParameterDefinition(
      'prediction',
      'Supplies expected output to reduce generation latency.',
      ParameterKind.json,
      documentationUrl: chatDocumentationUrl,
    ),
    ParameterDefinition(
      'user',
      'Supplies a pseudonymous end-user identifier.',
      ParameterKind.text,
      documentationUrl: chatDocumentationUrl,
    ),
    ParameterDefinition(
      'session_id',
      'Groups requests and can influence provider affinity.',
      ParameterKind.text,
      documentationUrl: chatDocumentationUrl,
    ),
    ParameterDefinition(
      'metadata',
      'Adds request metadata; do not include secrets.',
      ParameterKind.json,
      documentationUrl: chatDocumentationUrl,
    ),
    ParameterDefinition(
      'plugins',
      'Enables additional request or response processing.',
      ParameterKind.managed,
      unavailableReason: _freePolicy,
      documentationUrl: chatDocumentationUrl,
    ),
    ParameterDefinition(
      'service_tier',
      'Selects a provider processing tier.',
      ParameterKind.managed,
      unavailableReason: _freePolicy,
      documentationUrl: chatDocumentationUrl,
    ),
    ParameterDefinition(
      'cache_control',
      'Requests prompt caching.',
      ParameterKind.managed,
      unavailableReason: _freePolicy,
      documentationUrl: chatDocumentationUrl,
    ),
    ParameterDefinition(
      'prompt_cache_key',
      'Identifies related cached prompts.',
      ParameterKind.managed,
      unavailableReason:
          'Needs verified prompt-cache capability and zero-charge policy.',
      documentationUrl: chatDocumentationUrl,
    ),
    ParameterDefinition(
      'prompt_cache_options',
      'Configures prompt caching.',
      ParameterKind.managed,
      unavailableReason: _freePolicy,
      documentationUrl: chatDocumentationUrl,
    ),
    ParameterDefinition(
      'image_config',
      'Configures generated images.',
      ParameterKind.managed,
      unavailableReason:
          'Needs image-output support and verified zero output charges. This app currently requests text responses.',
      documentationUrl: chatDocumentationUrl,
    ),
    ParameterDefinition(
      'modalities',
      'Selects output modalities.',
      ParameterKind.managed,
      unavailableReason: 'Managed by the text-only response policy.',
      documentationUrl: chatDocumentationUrl,
    ),
    ParameterDefinition(
      'provider',
      'Controls provider routing.',
      ParameterKind.managed,
      unavailableReason:
          'Managed by the fixed-model, zero-price routing policy.',
      documentationUrl: chatDocumentationUrl,
    ),
    ParameterDefinition(
      'models',
      'Provides alternative models.',
      ParameterKind.managed,
      unavailableReason:
          'Model substitution is disabled. Choose the model explicitly.',
      documentationUrl: chatDocumentationUrl,
    ),
    ParameterDefinition(
      'route',
      'Legacy provider-routing control.',
      ParameterKind.managed,
      unavailableReason:
          'Deprecated and managed by the fixed-model routing policy.',
      documentationUrl: chatDocumentationUrl,
    ),
    ParameterDefinition(
      'debug',
      'Requests upstream request inspection.',
      ParameterKind.managed,
      unavailableReason:
          'Disabled because upstream request echoes can expose conversation content.',
      documentationUrl: chatDocumentationUrl,
    ),
    ParameterDefinition(
      'trace',
      'Adds external observability metadata.',
      ParameterKind.managed,
      unavailableReason:
          'Needs an explicit observability integration; routine diagnostics omit conversation content.',
      documentationUrl: chatDocumentationUrl,
    ),
    ParameterDefinition(
      'stop_server_tools_when',
      'Limits hosted tool workflows.',
      ParameterKind.managed,
      unavailableReason: _freePolicy,
      documentationUrl: chatDocumentationUrl,
    ),
    ParameterDefinition(
      'max_tool_calls',
      'Limits hosted tool calls.',
      ParameterKind.managed,
      unavailableReason: _freePolicy,
      documentationUrl: chatDocumentationUrl,
    ),
  ];

  static ParameterDefinition? definition(String key) {
    for (final value in definitions) {
      if (value.key == key) return value;
    }
    return null;
  }

  static bool supported(FreeModel model, String key) =>
      model.supportedParameters.contains(key) ||
      (key == 'response_format' &&
          model.supportedParameters.contains('structured_outputs'));

  static List<ParameterDefinition> available(FreeModel model) => [
    for (final value in definitions)
      if (supported(model, value.key)) value,
  ];

  /// Preserve the catalog's order. Missing metadata permits legacy catalogs;
  /// within a reasoning object, omitted efforts means no effort selection,
  /// while an explicit null list permits all gateway effort values.
  static List<String> reasoningEfforts(FreeModel model) {
    final metadata = model.reasoning;
    if (metadata != null && !metadata.containsKey('supported_efforts')) {
      return const [];
    }
    final advertised = metadata?['supported_efforts'];
    final candidates = advertised is List
        ? advertised.whereType<String>()
        : _efforts;
    return candidates
        .where(
          (effort) =>
              _efforts.contains(effort) &&
              !(model.reasoningMandatory && effort == 'none'),
        )
        .toList(growable: false);
  }

  static String? availabilityReason(FreeModel model, String key) =>
      key == 'reasoning_effort' && reasoningEfforts(model).isEmpty
      ? 'This model does not advertise configurable reasoning effort. Leave the field unset.'
      : null;

  static String? _effortError(FreeModel model, dynamic value) {
    if (model.reasoningMandatory && value == 'none') {
      return 'Reasoning is mandatory for this model and cannot be disabled.';
    }
    final choices = reasoningEfforts(model);
    if (choices.isEmpty) return availabilityReason(model, 'reasoning_effort');
    if (!choices.contains(value)) {
      return 'Choose a reasoning effort supported by this model: ${choices.join(', ')}.';
    }
    return null;
  }

  static Map<String, dynamic> toRequest(
    FreeModel model,
    Map<String, dynamic> overrides, {
    Set<String> toolNames = const {},
  }) {
    final result = validate(model, overrides, toolNames: toolNames);
    if (!result.isValid) throw FormatException(result.errors.values.join(' '));
    return result.values;
  }

  static ParameterValidation validate(
    FreeModel model,
    Map<String, dynamic> overrides, {
    Set<String> toolNames = const {},
  }) {
    final errors = <String, String>{};
    final values = <String, dynamic>{};
    if (overrides.length > 64) {
      return const ParameterValidation(
        errors: {'parameters': 'Too many parameter overrides (maximum 64).'},
        values: {},
      );
    }
    for (final entry in overrides.entries) {
      final key = entry.key;
      final value = entry.value;
      final spec = definition(key);
      if (spec == null) {
        errors[key] = 'Not yet mapped: $key. No request field is sent.';
        continue;
      }
      if (!spec.editable) {
        errors[key] = spec.unavailableReason!;
        continue;
      }
      if (!supported(model, key)) {
        errors[key] = 'The selected model does not advertise $key.';
        continue;
      }
      final error = _validateValue(spec, value, model, toolNames);
      if (error != null) {
        errors[key] = error;
      } else {
        // Clone only accepted JSON; never preserve caller-owned nested values.
        values[key] = jsonDecode(jsonEncode(value));
      }
    }

    void conflict(String a, String b, String message) {
      errors[a] = message;
      errors[b] = message;
    }

    if (overrides.containsKey('max_tokens') &&
        overrides.containsKey('max_completion_tokens')) {
      conflict(
        'max_tokens',
        'max_completion_tokens',
        'Choose max_tokens or max_completion_tokens, not both.',
      );
    }
    if (overrides.containsKey('top_logprobs') &&
        overrides['logprobs'] != true) {
      errors['top_logprobs'] =
          'top_logprobs requires an explicit logprobs: true.';
    }
    final reasoning = values['reasoning'] as Map<String, dynamic>?;
    final effort = values['reasoning_effort'];
    if (reasoning != null && effort != null) {
      if (reasoning.containsKey('max_tokens') ||
          (reasoning.containsKey('effort') && reasoning['effort'] != effort) ||
          (reasoning['enabled'] == false && effort != 'none')) {
        conflict(
          'reasoning',
          'reasoning_effort',
          'Reasoning effort conflicts with the reasoning object. Use one effort or budget setting.',
        );
      }
    }
    if (values.containsKey('include_reasoning')) {
      final exclude = values['include_reasoning'] == false;
      if (reasoning?.containsKey('exclude') == true &&
          reasoning!['exclude'] != exclude) {
        conflict(
          'reasoning',
          'include_reasoning',
          'include_reasoning conflicts with reasoning.exclude.',
        );
      } else {
        values['reasoning'] = {...?reasoning, if (exclude) 'exclude': true};
        values.remove('include_reasoning');
      }
    }
    final generatedBudget =
        values['max_tokens'] ?? values['max_completion_tokens'];
    if (generatedBudget is int &&
        reasoning?['max_tokens'] is int &&
        (reasoning!['max_tokens'] as int) >= generatedBudget) {
      errors['reasoning'] =
          'The reasoning budget must be smaller than the total output-token cap.';
    }
    if (errors.isEmpty && utf8.encode(jsonEncode(overrides)).length > 65536) {
      errors['parameters'] =
          'The combined parameter overrides exceed the 64 KiB local settings limit. Shorten JSON values or reset parameters.';
    }
    return ParameterValidation(
      errors: Map.unmodifiable(errors),
      values: errors.isEmpty ? Map.unmodifiable(values) : const {},
    );
  }

  static String? _validateValue(
    ParameterDefinition spec,
    dynamic value,
    FreeModel model,
    Set<String> toolNames,
  ) {
    if (value == null) {
      return 'Choose a value, or reset this parameter to omit it.';
    }
    if (!_boundedJson(value)) {
      return 'Use finite JSON within the 32 KiB and nesting limits.';
    }
    switch (spec.kind) {
      case ParameterKind.number:
      case ParameterKind.integer:
        if (value is! num ||
            !value.isFinite ||
            (spec.kind == ParameterKind.integer && value is! int)) {
          return spec.kind == ParameterKind.integer
              ? 'Enter an integer.'
              : 'Enter a finite number.';
        }
        if (value.abs() > 9007199254740991) {
          return 'Number exceeds the exact browser integer range.';
        }
        if ((spec.minimum != null && value < spec.minimum!) ||
            (spec.maximum != null && value > spec.maximum!)) {
          return 'Enter a value from ${spec.minimum ?? '−∞'} to ${spec.maximum ?? '∞'}.';
        }
        if (spec.key == 'max_tokens' || spec.key == 'max_completion_tokens') {
          final maximum = model.topProvider['max_completion_tokens'];
          if (maximum is int && maximum > 0 && value > maximum) {
            return 'The reported provider maximum is $maximum tokens.';
          }
          if (model.contextLength != null && value > model.contextLength!) {
            return 'The output cap exceeds the reported context length.';
          }
        }
      case ParameterKind.boolean:
        if (value is! bool) return 'Choose true or false.';
        if (spec.key == 'parallel_tool_calls' && toolNames.isEmpty) {
          return 'Enable an approved tool connection first.';
        }
      case ParameterKind.enumeration:
        if (value is! String || !spec.choices.contains(value)) {
          return 'Choose one of: ${spec.choices.join(', ')}.';
        }
        if (spec.key == 'reasoning_effort') return _effortError(model, value);
      case ParameterKind.text:
        if (value is! String || value.isEmpty || value.length > 256) {
          return 'Enter text from 1 to 256 characters.';
        }
      case ParameterKind.managed:
        return spec.unavailableReason;
      case ParameterKind.json:
        return _validateObject(spec.key, value, model, toolNames);
    }
    return null;
  }

  static String? _validateObject(
    String key,
    dynamic value,
    FreeModel model,
    Set<String> toolNames,
  ) {
    switch (key) {
      case 'stop':
        final stops = value is String ? [value] : value;
        if (stops is! List ||
            stops.isEmpty ||
            stops.length > 4 ||
            stops.any((s) => s is! String || s.isEmpty || s.length > 2048)) {
          return 'Use a JSON string or one to four nonempty strings (up to 2048 characters each).';
        }
      case 'logit_bias':
        if (value is! Map ||
            value.length > 512 ||
            value.entries.any(
              (e) =>
                  e.key is! String ||
                  !RegExp(r'^\d+$').hasMatch(e.key as String) ||
                  e.value is! num ||
                  !(e.value as num).isFinite ||
                  (e.value as num) < -100 ||
                  (e.value as num) > 100,
            )) {
          return 'Use a JSON object with up to 512 numeric token IDs and biases from -100 to 100.';
        }
      case 'response_format':
        if (value is! Map ||
            !const [
              'text',
              'json_object',
              'json_schema',
            ].contains(value['type'])) {
          return 'Use an object with type text, json_object, or json_schema.';
        }
        if (value.keys.any((k) => !const ['type', 'json_schema'].contains(k))) {
          return 'Unmapped response_format field. Only type and json_schema are supported.';
        }
        if (value['type'] != 'json_schema' &&
            value.containsKey('json_schema')) {
          return 'json_schema requires type json_schema.';
        }
        if (value['type'] == 'json_schema') {
          if (!model.supportedParameters.contains('structured_outputs')) {
            return 'The model does not advertise structured_outputs capability.';
          }
          final schema = value['json_schema'];
          if (schema is! Map ||
              schema['name'] is! String ||
              !RegExp(
                r'^[A-Za-z0-9_-]{1,64}$',
              ).hasMatch(schema['name'] as String) ||
              schema['schema'] is! Map ||
              (schema.containsKey('strict') && schema['strict'] is! bool) ||
              (schema.containsKey('description') &&
                  schema['description'] is! String) ||
              schema.keys.any(
                (k) => !const [
                  'name',
                  'schema',
                  'strict',
                  'description',
                ].contains(k),
              )) {
            return 'json_schema needs a name (1–64 letters, digits, _ or -), a schema object, and optional boolean strict / text description.';
          }
        }
      case 'reasoning':
        return _validateReasoning(value, model);
      case 'prediction':
        if (value is! Map ||
            value['type'] != 'content' ||
            value.keys.any((k) => !const ['type', 'content'].contains(k))) {
          return 'Use an object with type content and predicted content.';
        }
        final content = value['content'];
        if (content is String && content.isNotEmpty) return null;
        if (content is! List ||
            content.isEmpty ||
            content.any(
              (item) =>
                  item is! Map ||
                  item['type'] != 'text' ||
                  item['text'] is! String ||
                  item.keys.any((k) => !const ['type', 'text'].contains(k)),
            )) {
          return 'Predicted content must be text or an array of text parts.';
        }
      case 'tool_choice':
        if (value == 'none') return null;
        if (toolNames.isEmpty) {
          return 'Enable an approved tool connection first.';
        }
        if (value == 'auto' || value == 'required') return null;
        if (value is! Map ||
            value['type'] != 'function' ||
            value.keys.any((k) => !const ['type', 'function'].contains(k)) ||
            value['function'] is! Map) {
          return 'Use "auto", "none", "required", or a registered function selection.';
        }
        final function = value['function'] as Map;
        if (function.length != 1 || !toolNames.contains(function['name'])) {
          return 'The chosen function is not in the enabled tool connections.';
        }
      case 'metadata':
        if (value is! Map ||
            value.length > 16 ||
            value.entries.any(
              (e) =>
                  e.key is! String ||
                  (e.key as String).isEmpty ||
                  (e.key as String).length > 64 ||
                  e.value is! String ||
                  (e.value as String).length > 512,
            )) {
          return 'Use up to 16 string pairs: keys up to 64 and values up to 512 characters.';
        }
    }
    return null;
  }

  static String? _validateReasoning(dynamic value, FreeModel model) {
    if (value is! Map) return 'Use a reasoning JSON object.';
    const fields = [
      'enabled',
      'exclude',
      'effort',
      'max_tokens',
      'summary',
      'context',
      'mode',
    ];
    if (value.keys.any((key) => !fields.contains(key))) {
      return 'Unmapped reasoning field. Use enabled, exclude, effort, max_tokens, summary, context, or mode.';
    }
    for (final key in ['enabled', 'exclude']) {
      if (value.containsKey(key) && value[key] is! bool) {
        return 'reasoning.$key must be a boolean.';
      }
    }
    if (model.reasoningMandatory && value['enabled'] == false) {
      return 'Reasoning is mandatory for this model and cannot be disabled.';
    }
    if (value.containsKey('effort')) {
      final error = _effortError(model, value['effort']);
      if (error != null) return error;
    }
    if (value.containsKey('max_tokens') &&
        model.reasoning != null &&
        model.reasoning!['supports_max_tokens'] != true) {
      return 'This model does not advertise a configurable reasoning token budget.';
    }
    if (value.containsKey('max_tokens') &&
        (value['max_tokens'] is! int ||
            (value['max_tokens'] as int) < 1 ||
            (value['max_tokens'] as int) > 9007199254740991)) {
      return 'reasoning.max_tokens must be a positive integer.';
    }
    if (value.containsKey('effort') && value.containsKey('max_tokens')) {
      return 'Choose reasoning.effort or reasoning.max_tokens, not both.';
    }
    if (value['enabled'] == false &&
        ((value.containsKey('effort') && value['effort'] != 'none') ||
            value.containsKey('max_tokens'))) {
      return 'Disabled reasoning cannot also request an effort or token budget.';
    }
    const enums = {
      'summary': ['auto', 'concise', 'detailed'],
      'context': ['auto', 'all_turns', 'current_turn'],
      'mode': ['standard'],
    };
    for (final entry in enums.entries) {
      if (value.containsKey(entry.key) &&
          !entry.value.contains(value[entry.key])) {
        return entry.key == 'mode'
            ? 'Reasoning pro mode can change the model route and is unavailable under the fixed-model free-only policy.'
            : 'reasoning.${entry.key} must be one of: ${entry.value.join(', ')}.';
      }
    }
    return null;
  }

  static bool _boundedJson(dynamic value) {
    var nodes = 0;
    bool walk(dynamic item, int depth) {
      nodes++;
      if (nodes > 4096 || depth > 12) return false;
      if (item == null || item is bool || item is String) return true;
      if (item is num) return item.isFinite;
      if (item is List) return item.every((child) => walk(child, depth + 1));
      if (item is Map) {
        return item.entries.every(
          (entry) => entry.key is String && walk(entry.value, depth + 1),
        );
      }
      return false;
    }

    if (!walk(value, 0)) return false;
    try {
      return utf8.encode(jsonEncode(value)).length <= maxJsonCharacters;
    } on Object {
      return false;
    }
  }
}
