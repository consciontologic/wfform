import 'package:flutter/material.dart';
import 'selectable_surface.dart';

import '../app/studio_state.dart';
import '../app/theme.dart';
import 'model_browser.dart';

Future<void> openHistory(BuildContext context, StudioState state) =>
    showSelectableDialog<void>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.all(12),
        child: SizedBox(
          width: 620,
          height: MediaQuery.sizeOf(context).height * .85,
          child: Column(
            children: [
              StudioDialogHeader(
                title: 'Conversation history',
                emoji: '🗂️',
                color: StudioPalette.of(context).lilac,
                closeTooltip: 'Close history',
                onClose: () => Navigator.pop(context),
              ),
              Expanded(
                child: ConversationHistory(
                  state: state,
                  onOpened: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );

class ConversationHistory extends StatefulWidget {
  const ConversationHistory({super.key, required this.state, this.onOpened});
  final StudioState state;
  final VoidCallback? onOpened;
  @override
  State<ConversationHistory> createState() => _ConversationHistoryState();
}

class _ConversationHistoryState extends State<ConversationHistory> {
  final search = TextEditingController();
  bool archived = false;
  StudioState get state => widget.state;
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> _delete(String id, String title) async {
    final confirmed = await showSelectableDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: Text(
          '“$title” will be permanently removed from this browser. This cannot be undone.',
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep conversation'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await state.deleteConversation(id);
  }

  @override
  Widget build(BuildContext context) =>
      SelectionArea(child: _buildHistory(context));

  Widget _buildHistory(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      state,
      state.chat.statusChanges,
      state.historyIndexChanges,
      state.historyStatus,
    ]),
    builder: (context, _) {
      final colors = StudioPalette.of(context);
      final query = search.text.trim().toLowerCase();
      final entries = state.history
          .where(
            (entry) =>
                entry.archived == archived &&
                (query.isEmpty ||
                    '${entry.title} ${entry.modelName ?? ''} ${entry.modelId ?? ''}'
                        .toLowerCase()
                        .contains(query)),
          )
          .toList();
      final busy = state.chat.busy || state.historyBusy;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: TextField(
              controller: search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Search conversations',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ChoiceChip(
                  label: const Text('Chats'),
                  selected: !archived,
                  onSelected: (_) => setState(() => archived = false),
                ),
                ChoiceChip(
                  label: const Text('Archived'),
                  selected: archived,
                  onSelected: (_) => setState(() => archived = true),
                ),
                TextButton.icon(
                  onPressed: busy ? null : state.importConversation,
                  icon: const Icon(Icons.file_upload_outlined, size: 17),
                  label: const Text('Import'),
                ),
              ],
            ),
          ),
          if (state.historyLoading) const LinearProgressIndicator(),
          if (state.historyError != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                state.historyError!.message,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        state.historyLoading
                            ? 'Opening your history…'
                            : query.isNotEmpty
                            ? 'No matching conversations.'
                            : archived
                            ? 'No archived conversations.'
                            : 'Your conversations will appear here. Drafts are saved too.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.muted),
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final active = entry.id == state.activeConversationId;
                      return Container(
                        key: ValueKey('history-${entry.id}'),
                        margin: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: active ? colors.sage : null,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: active ? colors.border : Colors.transparent,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ListTile(
                              selected: active,
                              selectedColor: colors.ink,
                              enabled: !busy,
                              contentPadding: const EdgeInsets.fromLTRB(
                                12,
                                4,
                                12,
                                0,
                              ),
                              title: SelectableTooltip(
                                message: entry.title,
                                child: Text(
                                  entry.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 5),
                                child: Text(
                                  '${entry.modelName ?? entry.modelId ?? 'No model selected'}\n${timeLabel(entry.updatedAt)} · ${entry.messageCount} messages',
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colors.muted,
                                  ),
                                ),
                              ),
                              onTap: () async {
                                if (await state.openConversation(entry.id) &&
                                    mounted) {
                                  widget.onOpened?.call();
                                }
                              },
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Wrap(
                                children: [
                                  SelectableIconButton(
                                    tooltip: 'Export ${entry.title}',
                                    onPressed: busy
                                        ? null
                                        : () => state.exportConversation(
                                            entry.id,
                                          ),
                                    icon: const Icon(
                                      Icons.file_download_outlined,
                                      size: 19,
                                    ),
                                  ),
                                  if (entry.archived) ...[
                                    SelectableIconButton(
                                      tooltip: 'Restore ${entry.title}',
                                      onPressed: busy
                                          ? null
                                          : () => state.restoreConversation(
                                              entry.id,
                                            ),
                                      icon: const Icon(
                                        Icons.unarchive_outlined,
                                        size: 19,
                                      ),
                                    ),
                                    SelectableIconButton(
                                      tooltip: 'Delete ${entry.title}',
                                      onPressed: busy
                                          ? null
                                          : () =>
                                                _delete(entry.id, entry.title),
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        size: 19,
                                      ),
                                    ),
                                  ] else
                                    SelectableIconButton(
                                      tooltip: 'Archive ${entry.title}',
                                      onPressed: busy
                                          ? null
                                          : () => state.archiveConversation(
                                              entry.id,
                                            ),
                                      icon: const Icon(
                                        Icons.archive_outlined,
                                        size: 19,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          if (state.historyError != null && state.hasUnsavedHistoryChanges)
            TextButton.icon(
              onPressed: state.historySaving ? null : state.flushHistory,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Retry saving'),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text(
              '${state.historyStatus.value} on this browser · no cloud sync',
              style: TextStyle(fontSize: 11, color: colors.muted),
            ),
          ),
        ],
      );
    },
  );
}
