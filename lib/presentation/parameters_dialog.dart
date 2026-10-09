import 'dart:convert';

import 'package:flutter/material.dart';

import '../features/models/model.dart';
import '../features/parameters/request_parameters.dart';
import '../features/documents/document_view.dart';
import 'selectable_surface.dart';

Future<void> openParameters(
  BuildContext context, {
  required FreeModel model,
  required Map<String, dynamic> overrides,
  required ValueChanged<Map<String, dynamic>> onApply,
  Set<String> toolNames = const {},
  bool toolsAvailable = true,
  ValueChanged<Uri>? onOpenDocumentation,
}) => showSelectableDialog<void>(
  context: context,
  builder: (context) => ParametersDialog(
    model: model,
    overrides: overrides,
    onApply: onApply,
    toolNames: toolNames,
    toolsAvailable: toolsAvailable,
    onOpenDocumentation: onOpenDocumentation,
  ),
);

/// Edits a private draft. Only Apply returns explicit, typed overrides; the
/// request boundary separately normalizes legacy aliases before serialization.
class ParametersDialog extends StatefulWidget {
  const ParametersDialog({
    super.key,
    required this.model,
    required this.overrides,
    required this.onApply,
    this.toolNames = const {},
    this.toolsAvailable = true,
    this.onOpenDocumentation,
  });

  final FreeModel model;
  final Map<String, dynamic> overrides;
  final ValueChanged<Map<String, dynamic>> onApply;
  final Set<String> toolNames;
  final bool toolsAvailable;
  final ValueChanged<Uri>? onOpenDocumentation;

  @override
  State<ParametersDialog> createState() => _ParametersDialogState();
}

class _ParametersDialogState extends State<ParametersDialog> {
  late final Map<String, dynamic> _draft;
  final _controllers = <String, TextEditingController>{};
  final _parseErrors = <String, String>{};
  Map<String, String> _errors = {};
  bool _attemptedApply = false;

  @override
  void initState() {
    super.initState();
    // Nested values are never mutated. The apply callback receives a deep copy.
    _draft = Map.of(widget.overrides);
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  List<String> get _keys => <String>{
    ...RequestParameters.available(widget.model).map((spec) => spec.key),
    ...widget.model.supportedParameters,
    ...widget.overrides.keys,
  }.toList();

  bool _desktopOnly(String key) =>
      !widget.toolsAvailable &&
      const {'tools', 'tool_choice', 'parallel_tool_calls'}.contains(key);

  void _validate() {
    final active = Map<String, dynamic>.of(_draft)
      ..removeWhere((key, _) => _desktopOnly(key));
    _errors = {
      ...RequestParameters.validate(
        widget.model,
        active,
        toolNames: widget.toolNames,
      ).errors,
      ..._parseErrors,
    };
  }

  void _reset(String key) {
    setState(() {
      _draft.remove(key);
      _parseErrors.remove(key);
      _controllers[key]?.clear();
      _validate();
    });
  }

  void _resetAll() {
    setState(() {
      _draft.clear();
      _parseErrors.clear();
      _errors.clear();
      _attemptedApply = false;
      for (final controller in _controllers.values) {
        controller.clear();
      }
    });
  }

  void _apply() {
    setState(() {
      _attemptedApply = true;
      _validate();
    });
    if (_errors.isNotEmpty) return;
    final copy = (jsonDecode(jsonEncode(_draft)) as Map)
        .cast<String, dynamic>();
    widget.onApply(copy);
    Navigator.of(context).pop();
  }

  void _changed(ParameterDefinition spec, String text) {
    dynamic value;
    String? error;
    switch (spec.kind) {
      case ParameterKind.number:
        value = num.tryParse(text.trim());
        if (value == null) error = 'Enter a finite number.';
      case ParameterKind.integer:
        value = int.tryParse(text.trim());
        if (value == null) error = 'Enter an integer.';
      case ParameterKind.json:
        if (text.length > RequestParameters.maxJsonCharacters) {
          error = 'JSON exceeds the 32 KiB limit.';
        } else {
          try {
            value = jsonDecode(text);
          } on FormatException {
            error = 'Enter valid JSON, or reset to omit this parameter.';
          }
        }
      case ParameterKind.text:
        value = text;
      case ParameterKind.boolean:
      case ParameterKind.enumeration:
      case ParameterKind.managed:
        return;
    }
    setState(() {
      _draft[spec.key] = value;
      if (error == null) {
        _parseErrors.remove(spec.key);
      } else {
        _parseErrors[spec.key] = error;
      }
      _validate();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 680,
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Parameters', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        widget.model.name,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Provider defaults apply when a parameter is unset. '
                        'Only explicit overrides are sent. Support comes from '
                        'the live model catalog; providers can impose further limits.',
                      ),
                      const SizedBox(height: 12),
                      if (_errors['parameters'] case final String message)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            message,
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                      if (_keys.isEmpty)
                        const Text(
                          'This model advertises no adjustable parameters.',
                        ),
                      for (final key in _keys) _card(key),
                    ],
                  ),
                ),
              ),
              if (_attemptedApply && _errors.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Review the marked parameters before applying.',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton(
                    onPressed: _resetAll,
                    child: const Text('Reset all'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(onPressed: _apply, child: const Text('Apply')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(String key) {
    final spec = RequestParameters.definition(key);
    final supported = RequestParameters.supported(widget.model, key);
    final restriction = _desktopOnly(key)
        ? 'Tools are available on desktop computers. Saved tool settings are kept, but are not sent from this device.'
        : RequestParameters.availabilityReason(widget.model, key);
    final editable =
        spec != null && spec.editable && supported && restriction == null;
    final enabled = _draft.containsKey(key);
    final error = _errors[key];
    final documentationUrl =
        spec?.documentationUrl ?? RequestParameters.documentationUrl;
    return Card(
      key: Key('parameter-card-$key'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(key, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              spec?.description ??
                  'Not yet mapped. This advertised capability needs a documented request mapping before it can be set.',
            ),
            if ((key == 'reasoning' || key == 'reasoning_effort') &&
                widget.model.reasoningMandatory)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Reasoning is mandatory for this model. Excluding returned reasoning does not disable it.',
                ),
              ),
            if (key == 'reasoning' && widget.model.reasoning != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Effort choices: ${RequestParameters.reasoningEfforts(widget.model).isEmpty ? 'not advertised' : RequestParameters.reasoningEfforts(widget.model).join(', ')}. '
                  'Token budget: ${widget.model.reasoning!['supports_max_tokens'] == true ? 'supported' : 'not advertised'}.',
                ),
              ),
            if (!editable) ...[
              const SizedBox(height: 8),
              Text(
                restriction ??
                    spec?.unavailableReason ??
                    (spec == null
                        ? 'No request field is sent for this capability.'
                        : 'The selected model does not advertise this saved override. Reset it to continue.'),
              ),
            ],
            if (editable) ...[
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                key: Key('parameter-enable-$key'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Override'),
                subtitle: Text(
                  enabled ? 'Explicit value' : 'Provider defaults',
                ),
                value: enabled,
                onChanged: (value) {
                  if (!value) {
                    _reset(key);
                  } else {
                    setState(() {
                      _draft[key] = null;
                      _validate();
                    });
                  }
                },
              ),
              if (enabled) _editor(spec),
            ],
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (enabled)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  key: Key('parameter-reset-$key'),
                  onPressed: () => _reset(key),
                  child: const Text('Reset to provider defaults'),
                ),
              ),
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: const Text('Official information'),
              children: [
                if (spec != null)
                  Text(
                    'Documentation reviewed ${spec.reviewedAt}. No provider default is stored by wfform.',
                  ),
                const SizedBox(height: 4),
                Text(documentationUrl),
                if (widget.onOpenDocumentation != null)
                  TextButton(
                    onPressed: () => widget.onOpenDocumentation!(
                      Uri.parse(documentationUrl),
                    ),
                    child: const Text('Open official documentation'),
                  )
                else
                  const Text(
                    'Copy this URL to open the official documentation.',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _editor(ParameterDefinition spec) {
    final key = spec.key;
    final value = _draft[key];
    if (spec.kind == ParameterKind.boolean ||
        spec.kind == ParameterKind.enumeration) {
      final choices = spec.kind == ParameterKind.boolean
          ? <dynamic>[true, false]
          : key == 'reasoning_effort'
          ? RequestParameters.reasoningEfforts(widget.model)
          : spec.choices;
      return DropdownButtonFormField<dynamic>(
        key: Key('parameter-value-$key'),
        initialValue: choices.contains(value) ? value : null,
        isExpanded: true,
        itemHeight: null,
        decoration: const InputDecoration(labelText: 'Explicit value'),
        hint: const Text('Choose a value'),
        items: [
          for (final choice in choices)
            DropdownMenuItem(value: choice, child: Text('$choice')),
        ],
        onChanged: (value) => setState(() {
          _draft[key] = value;
          _validate();
        }),
      );
    }
    final controller = _controllers.putIfAbsent(
      key,
      () => TextEditingController(
        text: value == null
            ? ''
            : spec.kind == ParameterKind.json
            ? const JsonEncoder.withIndent('  ').convert(value)
            : '$value',
      ),
    );
    final editor = TextField(
      key: Key('parameter-value-$key'),
      controller: controller,
      minLines: spec.kind == ParameterKind.json ? 2 : 1,
      maxLines: spec.kind == ParameterKind.json ? 8 : 1,
      keyboardType:
          spec.kind == ParameterKind.number ||
              spec.kind == ParameterKind.integer
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : TextInputType.multiline,
      decoration: InputDecoration(
        labelText: spec.kind == ParameterKind.json
            ? 'JSON value'
            : 'Explicit value',
        hintText: spec.kind == ParameterKind.json ? _jsonHint(key) : null,
        helperText: spec.minimum != null || spec.maximum != null
            ? 'Range: ${spec.minimum ?? 'unbounded'} to ${spec.maximum ?? 'unbounded'}'
            : null,
        helperMaxLines: 3,
      ),
      onChanged: (text) => _changed(spec, text),
    );
    if (spec.kind != ParameterKind.json) return editor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        editor,
        if (controller.text.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Readable preview'),
            children: [ReadableDataView(source: controller.text)],
          ),
      ],
    );
  }

  String? _jsonHint(String key) => switch (key) {
    'stop' => '["END"]',
    'reasoning' =>
      RequestParameters.reasoningEfforts(widget.model).isEmpty
          ? '{"exclude":true}'
          : jsonEncode({
              'effort': RequestParameters.reasoningEfforts(widget.model).first,
            }),
    'response_format' => '{"type":"json_object"}',
    'tool_choice' => '"auto"',
    'logit_bias' => '{"123":-1}',
    'prediction' => '{"type":"content","content":"expected text"}',
    'metadata' => '{"label":"value"}',
    _ => null,
  };
}
