import 'dart:convert';

import 'package:flutter/material.dart';
import 'selectable_surface.dart';

import '../app/theme.dart';
import '../features/chat/attachment.dart';
import '../features/documents/document_view.dart';

/// File names and payloads are conversation content, never diagnostics.
class AttachmentList extends StatelessWidget {
  const AttachmentList({super.key, required this.files, this.onRemove});
  final List<ChatAttachment> files;
  final void Function(String id)? onRemove;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: files.map((file) {
      final icon = switch (file.kind) {
        AttachmentKind.image => Icons.image_outlined,
        AttachmentKind.audio => Icons.audio_file_outlined,
        AttachmentKind.video => Icons.video_file_outlined,
        AttachmentKind.pdf => Icons.picture_as_pdf_outlined,
        AttachmentKind.text => Icons.code,
      };
      final size = file.byteLength < 1024 * 1024
          ? '${(file.byteLength / 1024).ceil()} KB'
          : '${(file.byteLength / (1024 * 1024)).toStringAsFixed(1)} MB';
      return SelectableTooltip(
        message:
            '${file.name} · ${file.kind == AttachmentKind.text ? file.documentFormat.label : file.mimeType} · $size',
        child: InputChip(
          avatar: Icon(icon, size: 18),
          label: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 190),
            child: Text(
              '${file.name} · $size',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          onPressed: file.kind == AttachmentKind.text
              ? () => showSelectableDialog<void>(
                  context: context,
                  builder: (context) => Dialog(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                const Expanded(child: Text('File preview')),
                                SelectableIconButton(
                                  tooltip: 'Close file preview',
                                  onPressed: () => Navigator.pop(context),
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                            Flexible(
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      '${file.name}\n${file.documentFormat.label} · UTF-8 · $size',
                                    ),
                                    DocumentView(
                                      source: file.textContent!,
                                      format: file.documentFormat,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              : file.kind == AttachmentKind.image
              ? () => showSelectableDialog<void>(
                  context: context,
                  builder: (context) => Dialog(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  file.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              SelectableIconButton(
                                tooltip: 'Close image preview',
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                          Flexible(
                            child: Image.memory(
                              base64Decode(file.base64Data),
                              fit: BoxFit.contain,
                              semanticLabel: 'Attached image ${file.name}',
                              errorBuilder: (context, error, stack) =>
                                  const Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Text(
                                      'This image cannot be previewed by the browser. Remove it if the file is damaged.',
                                    ),
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : null,
          onDeleted: onRemove == null ? null : () => onRemove!(file.id),
          deleteButtonTooltipMessage: '',
          deleteIcon: SelectableTooltip(
            message: 'Remove ${file.name}',
            child: const Icon(Icons.cancel, size: 18),
          ),
          backgroundColor: StudioPalette.of(context).sage,
        ),
      );
    }).toList(),
  );
}
