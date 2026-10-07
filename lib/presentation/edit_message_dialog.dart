import 'package:flutter/material.dart';

import '../features/chat/attachment.dart';
import '../features/chat/chat_controller.dart';
import 'attachment_widgets.dart';

/// Edits are append-only new turns. The composer draft remains untouched.
class EditMessageDialog extends StatefulWidget {
  const EditMessageDialog({
    super.key,
    required this.original,
    required this.submit,
  });
  final ChatMessage original;
  final String? Function(String, List<ChatAttachment>) submit;
  @override
  State<EditMessageDialog> createState() => _EditMessageDialogState();
}

class _EditMessageDialogState extends State<EditMessageDialog> {
  late final text = TextEditingController(text: widget.original.content);
  late List<ChatAttachment> files = [...widget.original.attachments];
  String? error;
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  void send() {
    if (text.text.trim().isEmpty && files.isEmpty) {
      setState(() => error = 'Write a message or keep an attachment.');
      return;
    }
    final failure = widget.submit(text.text, List.unmodifiable(files));
    if (failure == null) {
      Navigator.pop(context);
    } else {
      setState(() => error = failure);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit and resend'),
    content: SizedBox(
      width: 600,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sends an updated copy as a new message. Earlier messages stay in this conversation.',
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('edit-message'),
              controller: text,
              autofocus: true,
              minLines: 3,
              maxLines: 10,
              maxLength: 32000,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(labelText: 'Edited message'),
            ),
            if (files.isNotEmpty)
              AttachmentList(
                files: files,
                onRemove: (id) =>
                    setState(() => files.removeWhere((file) => file.id == id)),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
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
        child: const Text('Cancel edit'),
      ),
      FilledButton.icon(
        onPressed: send,
        icon: const Icon(Icons.send, size: 18),
        label: const Text('Send as new message'),
      ),
    ],
  );
}
