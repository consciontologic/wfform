import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'selectable_surface.dart';
import '../app/studio_state.dart';

Future<void> openContextControls(BuildContext context, StudioState state) =>
    showSelectableDialog<void>(
      context: context,
      builder: (_) => _ContextDialog(state: state),
    );

class _ContextDialog extends StatefulWidget {
  const _ContextDialog({required this.state});
  final StudioState state;
  @override
  State<_ContextDialog> createState() => _ContextDialogState();
}

class _ContextDialogState extends State<_ContextDialog> {
  late int start = widget.state.chat.contextStartIndex;
  late final output = TextEditingController(
    text: '${widget.state.chat.outputTokenLimit}',
  );
  String? error;
  @override
  void dispose() {
    output.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final model = state.catalog.selected;
    final messages = state.chat.messages;
    final budget = model == null
        ? null
        : state.chat.contextBudget(
            model,
            draft: state.draft,
            attachments: state.draftAttachments,
          );
    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.all(12),
      title: const Text('Conversation context'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Choose what future requests include. Earlier messages remain in your saved history; nothing is removed automatically.',
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: start,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Include context from',
                ),
                items: [
                  const DropdownMenuItem(
                    value: 0,
                    child: _CopyableOption('Entire conversation'),
                  ),
                  for (var i = 1; i < messages.length; i++)
                    if (messages[i].role == 'user')
                      DropdownMenuItem(
                        value: i,
                        child: _CopyableOption(
                          'Message ${i + 1}: ${messages[i].content.isEmpty ? 'Attachment' : messages[i].content}',
                        ),
                      ),
                  if (messages.isNotEmpty)
                    DropdownMenuItem(
                      value: messages.length,
                      child: const _CopyableOption('Next message only'),
                    ),
                ],
                onChanged: state.chat.busy
                    ? null
                    : (value) => setState(() => start = value ?? 0),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: output,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Maximum response tokens',
                  helperText: '16–32768; applied when supported by the model.',
                ),
              ),
              const SizedBox(height: 12),
              if (budget != null) Text('Current request: ${budget.summary}'),
              if (budget?.warning != null) Text(budget!.warning!),
              const SizedBox(height: 8),
              const Text(
                'Token counts are estimates. Media token use varies by provider. Response tokens can include model reasoning.',
                style: TextStyle(fontSize: 12),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: state.chat.busy
              ? null
              : () async {
                  if (await state.newConversation() && context.mounted) {
                    Navigator.pop(context);
                  }
                },
          child: const Text('New conversation'),
        ),
        FilledButton(
          onPressed: state.chat.busy
              ? null
              : () {
                  final count = int.tryParse(output.text);
                  if (count == null || count < 16 || count > 32768) {
                    setState(
                      () => error =
                          'Enter a response limit between 16 and 32768.',
                    );
                    return;
                  }
                  if (!state.chat.setContextStartIndex(start)) {
                    setState(
                      () => error =
                          'The conversation changed. Reopen context settings.',
                    );
                    return;
                  }
                  state.chat.setOutputTokenLimit(count);
                  state.flushHistory();
                  Navigator.pop(context);
                },
          child: const Text('Apply to next request'),
        ),
      ],
    );
  }
}

/// Dropdown popup entries own their tap gesture; an inner SelectionArea would
/// consume it and prevent choosing an option. Keep the usual selection action
/// and expose an independent copy action for its complete (possibly clipped) text.
class _CopyableOption extends StatelessWidget {
  const _CopyableOption(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis)),
      SelectableIconButton(
        tooltip:
            'Copy option: ${text.length > 80 ? '${text.substring(0, 80)}…' : text}',
        onPressed: () => Clipboard.setData(ClipboardData(text: text)),
        icon: const Icon(Icons.copy, size: 16),
      ),
    ],
  );
}
