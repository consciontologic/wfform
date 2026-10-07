import 'dart:convert';

import '../../shared/diagnostics.dart';

/// A normalized free-price catalog candidate. Omitted optional prices remain
/// absent: only the server's zero-price routing guard can authorize such routes.
class FreeModel {
  const FreeModel({
    required this.id,
    required this.name,
    this.description = '',
    this.contextLength,
    this.pricing = const {'prompt': '0', 'completion': '0', 'request': '0'},
    this.inputModalities = const ['text'],
    this.outputModalities = const ['text'],
    this.supportedParameters = const [],
    this.topProvider = const {},
    this.architectureTokenizer,
    this.pricingOverrides = const [],
  });

  final String id;
  final String name;
  final String description;
  final int? contextLength;
  final Map<String, String> pricing;
  final List<String> inputModalities;
  final List<String> outputModalities;
  final List<String> supportedParameters;
  final Map<String, dynamic> topProvider;
  final String? architectureTokenizer;
  final List<Map<String, dynamic>> pricingOverrides;

  bool get chatCompatible => incompatibilityReason == null;
  String? get incompatibilityReason {
    if (architectureTokenizer == 'Router' ||
        const {
          'openrouter/auto',
          'openrouter/free',
          'openrouter/bodybuilder',
        }.contains(id)) {
      return 'Dynamic model router. Choose a fixed model to keep your selection explicit.';
    }
    if (!inputModalities.contains('text')) {
      return inputModalities.isEmpty
          ? 'Text input capability is not reported.'
          : 'This model does not accept text input.';
    }
    if (!outputModalities.contains('text')) {
      return outputModalities.isEmpty
          ? 'Text output capability is not reported.'
          : 'This model produces ${outputModalities.join(', ')} rather than chat text.';
    }
    if (outputModalities.length != 1) {
      return 'This model can produce ${outputModalities.join(', ')}. Native output charging cannot be guaranteed by the text/request price limits; this version only supports text-only output.';
    }
    return null;
  }

  bool get supportsReasoning =>
      supportedParameters.contains('reasoning') ||
      supportedParameters.contains('include_reasoning');

  /// Upload support is narrower than advertised input modalities: the selected
  /// route must also remain compatible with text output and zero-price guards.
  /// Missing optional prices remain unreported, never normalized to zero.
  bool get acceptsImages => attachmentUnavailableReason('image') == null;
  bool get acceptsAudio => attachmentUnavailableReason('audio') == null;
  bool get acceptsVideo => attachmentUnavailableReason('video') == null;
  bool get acceptsPdf => attachmentUnavailableReason('file') == null;
  bool get acceptsTextFiles => attachmentUnavailableReason('text') == null;

  Set<String> get allowedAttachmentMimeTypes => {
    if (acceptsTextFiles) 'text/plain',
    if (acceptsImages) ...{
      'image/png',
      'image/jpeg',
      'image/webp',
      'image/gif',
    },
    if (acceptsAudio) ...{'audio/wav', 'audio/mpeg'},
    if (acceptsVideo) 'video/mp4',
    if (acceptsPdf) 'application/pdf',
  };

  String get attachmentSummary {
    final enabled = [
      if (acceptsTextFiles) 'Text & source files',
      if (acceptsImages) 'Images',
      if (acceptsAudio) 'Audio',
      if (acceptsVideo) 'Video',
      if (acceptsPdf) 'PDFs (native)',
    ];
    return enabled.isEmpty ? 'No file uploads' : enabled.join(' · ');
  }

  String get attachmentNotice => [
    if (acceptsTextFiles)
      'UTF-8 text and source files: Markdown, JSON, YAML, JavaScript, C and other languages; up to 256 KiB each. Sent as text in the message, counting toward model context.',
    if (acceptsImages) 'Images: PNG, JPEG, WebP and GIF.',
    if (acceptsAudio) 'Audio: WAV and MP3.',
    if (acceptsVideo) 'Video: MP4.',
    if (acceptsPdf)
      'PDFs use native file input only. Paid OCR and parser fallbacks are disabled.',
    for (final modality in ['image', 'audio', 'video', 'file'])
      if (inputModalities.contains(modality) &&
          attachmentUnavailableReason(modality) != null)
        '${modality == 'file' ? 'PDF' : modality[0].toUpperCase() + modality.substring(1)} uploads: ${attachmentUnavailableReason(modality)}',
    if (!inputModalities.contains('file'))
      'PDF uploads are unavailable because native file input is not advertised. No document-conversion plugin is used.',
    'Input capabilities describe the catalog. Individual providers may impose stricter format, size or duration limits. Responses remain text only.',
  ].join('\n');

  /// A null result means the documented request representation and price guards
  /// are supported by this app. It is not a guarantee of provider availability.
  String? attachmentUnavailableReason(String modality) {
    if (!const {'text', 'image', 'audio', 'video', 'file'}.contains(modality)) {
      return 'This attachment type is not supported by this app.';
    }
    if (!chatCompatible) return 'This model is unavailable for text chat.';
    if (!inputModalities.contains(modality)) {
      return 'The catalog does not advertise ${modality == 'file' ? 'native file' : modality} input.';
    }
    final mediaPrices = switch (modality) {
      'image' => const {'image', 'image_token'},
      'audio' => const {'audio', 'input_audio_cache'},
      'video' => const {
        'image',
        'image_token',
        'audio',
        'input_audio_cache',
        'video',
      },
      'file' => const {'image', 'image_token', 'file'},
      _ => const <String>{},
    };
    bool applies(String key) =>
        !_nonTextPriceKeys.contains(key) || mediaPrices.contains(key);
    for (final required in ['prompt', 'completion']) {
      if (!pricing.containsKey(required) || !isZeroPrice(pricing[required]!)) {
        return 'The $required price is not confirmed as zero.';
      }
    }
    for (final entry in pricing.entries) {
      if (applies(entry.key) && !isZeroPrice(entry.value)) {
        if (isUnresolvedPrice(entry.value)) {
          return 'The ${entry.key} price is unresolved; a free attachment request cannot be confirmed.';
        }
        return 'The ${entry.key} price is not zero; this app only sends free requests.';
      }
    }
    for (final override in pricingOverrides) {
      for (final entry in override.entries) {
        if (!_conditionKeys.contains(entry.key) &&
            applies(entry.key) &&
            !isZeroPrice(entry.value.toString())) {
          if (isUnresolvedPrice(entry.value.toString())) {
            return 'A ${entry.key} price override is unresolved; a free attachment request cannot be confirmed.';
          }
          return 'A ${entry.key} price override is not zero.';
        }
      }
    }
    // Chat's documented maximum-price schema has image/audio caps but no video
    // cap. Require the separately documented free catalog variant, in addition
    // to the validated zero prices above, for video input. Never append :free.
    if (modality == 'video' && !id.endsWith(':free')) {
      return 'Video uploads require a verified free catalog variant because no separate video-price routing limit is documented.';
    }
    return null;
  }

  String get pricingNotice => pricing.containsKey('request')
      ? 'Reported prompt, completion and request prices are zero. Routing is restricted to zero-price providers.'
      : 'Prompt and completion prices are zero. The optional request price is not reported; a zero request-price routing limit is enforced before inference.';

  /// Order-independent fingerprint of capability/pricing fields affecting chat.
  String get signature => jsonEncode({
    'id': id,
    'context': contextLength,
    'input': [...inputModalities]..sort(),
    'output': [...outputModalities]..sort(),
    'parameters': [...supportedParameters]..sort(),
    'pricing': Map.fromEntries(
      pricing.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    ),
    'overrides': pricingOverrides,
    'tokenizer': architectureTokenizer,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'context_length': contextLength,
    'pricing': {
      ...pricing,
      if (pricingOverrides.isNotEmpty) 'overrides': pricingOverrides,
    },
    'architecture': {
      'input_modalities': inputModalities,
      'output_modalities': outputModalities,
      if (architectureTokenizer != null) 'tokenizer': architectureTokenizer,
    },
    'supported_parameters': supportedParameters,
    'top_provider': topProvider,
  };

  factory FreeModel.fromJson(Map<String, dynamic> value) {
    final parsed = parseModel(value, r'$.model');
    if (parsed.model == null) {
      throw AppFailure(
        FailureKind.schema,
        parsed.exclusionReason ?? 'The model does not have free prices.',
      );
    }
    return parsed.model!;
  }
}

class ModelParseResult {
  const ModelParseResult({
    required this.id,
    this.model,
    this.exclusionReason,
    this.unresolvedPricing = false,
  });
  final String id;
  final FreeModel? model;
  final String? exclusionReason;
  final bool unresolvedPricing;
}

AppFailure schemaFailure(
  String path,
  String expected,
  Object? value, {
  bool includePricingValue = false,
}) => AppFailure(
  FailureKind.schema,
  'The catalog field $path has an invalid or unsupported value.',
  field: path,
  expected: expected,
  actual: value == null ? 'null or missing' : value.runtimeType.toString(),
  details:
      '${includePricingValue ? 'Received pricing value: ${_pricingValueSummary(value)}. The entry was excluded; no free price was inferred. ' : ''}'
      'Review the localized catalog adapter in lib/features/models/model.dart.',
);

// Price diagnostics need the rejected scalar, not an entire API object. The
// diagnostics service applies its usual redaction before display or export.
String _pricingValueSummary(Object? value) {
  if (value == null) return 'null or missing';
  if (value is String) {
    return jsonEncode(value.length > 96 ? '${value.substring(0, 96)}…' : value);
  }
  if (value is num || value is bool) return '$value';
  if (value is List) return 'array (${value.length} items; content omitted)';
  if (value is Map) return 'object (${value.length} fields; content omitted)';
  return value.runtimeType.toString();
}

Map<String, dynamic> _object(Object? value, String path) {
  if (value is! Map<String, dynamic>) {
    throw schemaFailure(path, 'object', value);
  }
  return value;
}

String? _optionalString(Object? value, String path, {int max = 40000}) {
  if (value == null) return null;
  if (value is! String || value.length > max) {
    throw schemaFailure(path, 'string up to $max characters, or null', value);
  }
  return value;
}

List<String> _strings(Object? value, String path) {
  if (value == null) return const [];
  if (value is! List ||
      value.length > 100 ||
      value.any((e) => e is! String || e.isEmpty || e.length > 100)) {
    throw schemaFailure(path, 'array of nonempty strings', value);
  }
  return List<String>.unmodifiable(value.cast<String>().toSet());
}

int? _optionalPositiveInt(Object? value, String path) {
  if (value == null) return null;
  if (value is! int || value < 0) {
    throw schemaFailure(path, 'nonnegative integer or null', value);
  }
  return value;
}

// Numeric strings are the documented representation. Supporting finite JSON
// numbers is safe as well; booleans, blank strings, NaN and negative prices are
// never treated as free. Live router entries use "-1" for an unresolved price;
// recognize that exact sentinel as an exclusion, not a broken numeric schema.
// This is observed API behavior, not a claim that all negative values are valid.
// Exact mantissa inspection avoids underflow to zero.
final _decimal = RegExp(r'^\+?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$');
String _price(Object? value, String path) {
  if (value == -1 || value is String && isUnresolvedPrice(value)) return '-1';
  final String text;
  if (value is String) {
    text = value.trim();
  } else if (value is num && value.isFinite) {
    text = value.toString();
  } else {
    throw schemaFailure(
      path,
      'nonnegative decimal price string or number, or unresolved -1 sentinel',
      value,
      includePricingValue: true,
    );
  }
  if (text.length > 80 || !_decimal.hasMatch(text)) {
    throw schemaFailure(
      path,
      'nonnegative finite decimal price or the unresolved -1 sentinel',
      value,
      includePricingValue: true,
    );
  }
  // Parsing is validation only, never the free-price comparison.
  final number = num.tryParse(text);
  if (number == null || !number.isFinite || number < 0) {
    throw schemaFailure(
      path,
      'nonnegative finite decimal price or the unresolved -1 sentinel',
      value,
      includePricingValue: true,
    );
  }
  return text;
}

/// The exact unresolved-price sentinel observed in public router metadata.
/// Other negative values remain malformed and this value is never free.
bool isUnresolvedPrice(String value) => value.trim() == '-1';

bool isZeroPrice(String value) {
  if (!_decimal.hasMatch(value)) return false;
  final mantissa = value.split(RegExp('[eE]')).first;
  return !RegExp('[1-9]').hasMatch(mantissa);
}

const _nonTextPriceKeys = {
  'image',
  'image_output',
  'image_token',
  'audio',
  'audio_output',
  'input_audio_cache',
  'web_search',
};
const _conditionKeys = {
  'min_prompt_tokens',
  'utc_start',
  'utc_end',
  'utc_days',
};

/// Decodes one DTO. The caller quarantines individual schema failures. Unknown
/// top-level fields are harmless. Unknown price fields remain safety-relevant.
ModelParseResult parseModel(Object? value, String path) {
  final json = _object(value, path);
  final id = json['id'];
  if (id is! String ||
      id.isEmpty ||
      id.length > 512 ||
      !RegExp(r'^[A-Za-z0-9._~:/-]+$').hasMatch(id)) {
    throw schemaFailure('$path.id', 'nonempty model ID without whitespace', id);
  }
  final prices = _object(json['pricing'], '$path.pricing');
  final normalized = <String, String>{};
  // Only these two fields are required by PublicPricing in the official schema.
  for (final key in ['prompt', 'completion']) {
    normalized[key] = _price(prices[key], '$path.pricing.$key');
  }
  for (final entry in prices.entries) {
    if (entry.key == 'overrides' || entry.key == 'discount') continue;
    normalized[entry.key] = _price(entry.value, '$path.pricing.${entry.key}');
  }
  if (prices.containsKey('discount')) {
    final discount = prices['discount'];
    if (discount is! num ||
        !discount.isFinite ||
        discount < 0 ||
        discount > 1) {
      throw schemaFailure(
        '$path.pricing.discount',
        'number from 0 to 1',
        discount,
      );
    }
    // Discount is metadata, never assumed to make a paid model safely free.
  }
  final architecture = json['architecture'] == null
      ? <String, dynamic>{}
      : _object(json['architecture'], '$path.architecture');
  final inputs = _strings(
    architecture['input_modalities'],
    '$path.architecture.input_modalities',
  );
  final outputs = _strings(
    architecture['output_modalities'],
    '$path.architecture.output_modalities',
  );
  final hasText = inputs.contains('text') && outputs.contains('text');
  bool applicable(String key) => !hasText || !_nonTextPriceKeys.contains(key);
  String? reason;
  String? unresolvedPath;
  for (final entry in normalized.entries) {
    if (isUnresolvedPrice(entry.value) && applicable(entry.key)) {
      unresolvedPath ??= '$path.pricing.${entry.key}';
    } else if (applicable(entry.key) && !isZeroPrice(entry.value)) {
      reason ??= 'The ${entry.key} price is no longer zero.';
    }
  }
  final overrides = <Map<String, dynamic>>[];
  final rawOverrides = prices['overrides'];
  if (rawOverrides != null) {
    if (rawOverrides is! List || rawOverrides.length > 100) {
      throw schemaFailure(
        '$path.pricing.overrides',
        'array of at most 100 price overrides',
        rawOverrides,
      );
    }
    for (var i = 0; i < rawOverrides.length; i++) {
      final overridePath = '$path.pricing.overrides[$i]';
      final override = _object(rawOverrides[i], overridePath);
      final stored = <String, dynamic>{};
      for (final entry in override.entries) {
        if (_conditionKeys.contains(entry.key)) {
          // Conditions need not be evaluated: any nonzero potentially relevant
          // conditional charge excludes the model from this free-only demo.
          if (entry.key == 'utc_days') {
            stored[entry.key] = _strings(
              entry.value,
              '$overridePath.${entry.key}',
            );
          } else {
            stored[entry.key] = _optionalPositiveInt(
              entry.value,
              '$overridePath.${entry.key}',
            );
          }
          continue;
        }
        final price = _price(entry.value, '$overridePath.${entry.key}');
        stored[entry.key] = price;
        if (isUnresolvedPrice(price) && applicable(entry.key)) {
          unresolvedPath ??= '$overridePath.${entry.key}';
        } else if (applicable(entry.key) && !isZeroPrice(price)) {
          reason ??=
              'Conditional ${entry.key} pricing can charge for this model.';
        }
      }
      overrides.add(Map<String, dynamic>.unmodifiable(stored));
    }
  }
  final name = _optionalString(json['name'], '$path.name', max: 1000);
  final description = _optionalString(json['description'], '$path.description');
  final context = _optionalPositiveInt(
    json['context_length'],
    '$path.context_length',
  );
  final parameters = _strings(
    json['supported_parameters'],
    '$path.supported_parameters',
  );
  final provider = json['top_provider'] == null
      ? <String, dynamic>{}
      : _object(json['top_provider'], '$path.top_provider');
  final safeProvider = <String, dynamic>{};
  for (final key in ['context_length', 'max_completion_tokens']) {
    if (provider.containsKey(key)) {
      safeProvider[key] = _optionalPositiveInt(
        provider[key],
        '$path.top_provider.$key',
      );
    }
  }
  if (provider['is_moderated'] != null) {
    if (provider['is_moderated'] is! bool) {
      throw schemaFailure(
        '$path.top_provider.is_moderated',
        'boolean',
        provider['is_moderated'],
      );
    }
    safeProvider['is_moderated'] = provider['is_moderated'];
  }
  for (final key in ['name', 'provider_name']) {
    if (provider.containsKey(key)) {
      safeProvider[key] = _optionalString(
        provider[key],
        '$path.top_provider.$key',
        max: 1000,
      );
    }
  }
  final tokenizer = _optionalString(
    architecture['tokenizer'],
    '$path.architecture.tokenizer',
    max: 100,
  );
  if (unresolvedPath != null) {
    return ModelParseResult(
      id: id,
      unresolvedPricing: true,
      exclusionReason:
          'Pricing is unresolved ($unresolvedPath = -1), as observed on dynamic routers. A zero cost cannot be confirmed; choose a model with explicit zero prices.',
    );
  }
  if (reason != null) return ModelParseResult(id: id, exclusionReason: reason);
  return ModelParseResult(
    id: id,
    model: FreeModel(
      id: id,
      name: name?.isNotEmpty == true ? name! : id,
      description: description ?? '',
      contextLength: context,
      pricing: Map.unmodifiable(normalized),
      inputModalities: inputs,
      outputModalities: outputs,
      supportedParameters: parameters,
      topProvider: Map.unmodifiable(safeProvider),
      architectureTokenizer: tokenizer,
      pricingOverrides: List.unmodifiable(overrides),
    ),
  );
}
