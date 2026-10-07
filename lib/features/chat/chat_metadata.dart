/// Optional server metadata never determines whether received text is retained.
class ChatUsage {
  const ChatUsage({
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
    this.reasoningTokens,
  });
  final int? promptTokens, completionTokens, totalTokens, reasoningTokens;
  static ChatUsage? fromJson(Object? value) {
    if (value is! Map) return null;
    int? count(Object? value) => value is int && value >= 0 ? value : null;
    final details = value['completion_tokens_details'];
    final usage = ChatUsage(
      promptTokens: count(value['prompt_tokens']),
      completionTokens: count(value['completion_tokens']),
      totalTokens: count(value['total_tokens']),
      reasoningTokens: details is Map
          ? count(details['reasoning_tokens'])
          : null,
    );
    return usage.promptTokens == null &&
            usage.completionTokens == null &&
            usage.totalTokens == null
        ? null
        : usage;
  }

  Map<String, dynamic> toJson() => {
    if (promptTokens != null) 'prompt_tokens': promptTokens,
    if (completionTokens != null) 'completion_tokens': completionTokens,
    if (totalTokens != null) 'total_tokens': totalTokens,
    if (reasoningTokens != null)
      'completion_tokens_details': {'reasoning_tokens': reasoningTokens},
  };
}

class ChatMetrics {
  const ChatMetrics({
    required this.preflightMs,
    required this.generationMs,
    this.firstTokenMs,
  });
  final int preflightMs, generationMs;

  /// Time from submitting the actual inference request to first text/reasoning.
  final int? firstTokenMs;
  Map<String, dynamic> toJson() => {
    'preflightMs': preflightMs,
    'generationMs': generationMs,
    'firstTokenMs': firstTokenMs,
  };
  static ChatMetrics? fromJson(Object? value) {
    if (value is! Map ||
        value['preflightMs'] is! int ||
        value['generationMs'] is! int ||
        (value['firstTokenMs'] != null && value['firstTokenMs'] is! int)) {
      return null;
    }
    if ((value['preflightMs'] as int) < 0 ||
        (value['generationMs'] as int) < 0 ||
        (value['firstTokenMs'] != null && (value['firstTokenMs'] as int) < 0)) {
      return null;
    }
    return ChatMetrics(
      preflightMs: value['preflightMs'] as int,
      generationMs: value['generationMs'] as int,
      firstTokenMs: value['firstTokenMs'] as int?,
    );
  }
}

class ContextBudget {
  const ContextBudget({
    required this.estimatedInputTokens,
    required this.outputTokens,
    required this.contextLimit,
    required this.startIndex,
    required this.hasAttachments,
  });
  final int estimatedInputTokens, outputTokens, startIndex;
  final int? contextLimit;
  final bool hasAttachments;
  int get estimatedTotalTokens => estimatedInputTokens + outputTokens;
  bool get fits =>
      contextLimit == null || estimatedTotalTokens <= contextLimit!;
  bool get nearLimit =>
      contextLimit != null && estimatedTotalTokens >= contextLimit! * .8;
  String get summary =>
      'Estimated input: $estimatedInputTokens tokens · output reserve: $outputTokens'
      '${contextLimit == null ? ' · context limit unknown' : ' · context limit: $contextLimit'}';
  String? get warning => !fits
      ? 'The estimated context exceeds this model’s limit. Shorten the draft or explicitly exclude older turns.'
      : hasAttachments
      ? 'Media token usage depends on provider decoding and cannot be estimated exactly. This is a planning estimate.'
      : nearLimit
      ? 'This conversation is approaching the model’s context limit.'
      : null;
}
