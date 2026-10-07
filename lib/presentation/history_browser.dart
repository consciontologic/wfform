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
  const ConversationHistory({
    super.key,
    required this.state,
    this.onOpened,
    this.onInteracted,
  });
  final StudioState state;
  final VoidCallback? onOpened;
  final VoidCallback? onInteracted;
  @override
  State<ConversationHistory> createState() => _ConversationHistoryState();
}

class _ConversationHistoryState extends State<ConversationHistory> {
  final search = TextEditingController();
  final searchFocus = FocusNode();
  bool archived = false;
  StudioState get state => widget.state;
  @override
  void initState() {
    super.initState();
    searchFocus.addListener(_searchFocusChanged);
  }

  void _searchFocusChanged() {
    if (searchFocus.hasFocus) widget.onInteracted?.call();
  }

  @override
  void dispose() {
    search.dispose();
    searchFocus.dispose();
    super.dispose();
  }

  Future<void> _delete(String id, String title) async {
    widget.onInteracted?.call();
    final deleted = await state.deleteConversation(id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          deleted
              ? 'Deleted “$title” from this browser.'
              : 'Could not delete “$title”. ${state.historyError?.message ?? 'Try again after the current conversation operation finishes.'}',
        ),
      ),
    );
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
              focusNode: searchFocus,
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
                  onSelected: (_) {
                    widget.onInteracted?.call();
                    setState(() => archived = false);
                  },
                ),
                ChoiceChip(
                  label: const Text('Archived'),
                  selected: archived,
                  onSelected: (_) {
                    widget.onInteracted?.call();
                    setState(() => archived = true);
                  },
                ),
                TextButton.icon(
                  onPressed: busy
                      ? null
                      : () {
                          widget.onInteracted?.call();
                          state.importConversation();
                        },
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
                      final deleting = state.isDeletingConversation(entry.id);
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
                            // Keep opening the conversation in its own semantic
                            // boundary. Otherwise IndexedSemantics can absorb
                            // its tap action and nest Export/Archive/Delete
                            // buttons inside a larger button on Flutter web.
                            Semantics(
                              container: true,
                              child: ListTile(
                                selected: active,
                                selectedColor: colors.ink,
                                enabled: !busy && !deleting,
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
                                  widget.onInteracted?.call();
                                  if (await state.openConversation(entry.id) &&
                                      mounted) {
                                    widget.onOpened?.call();
                                  }
                                },
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Wrap(
                                children: [
                                  SelectableIconButton(
                                    tooltip: 'Export ${entry.title}',
                                    onPressed: busy || deleting
                                        ? null
                                        : () {
                                            widget.onInteracted?.call();
                                            state.exportConversation(entry.id);
                                          },
                                    icon: const Icon(
                                      Icons.file_download_outlined,
                                      size: 19,
                                    ),
                                  ),
                                  if (entry.archived) ...[
                                    SelectableIconButton(
                                      tooltip: 'Restore ${entry.title}',
                                      onPressed: busy || deleting
                                          ? null
                                          : () {
                                              widget.onInteracted?.call();
                                              state.restoreConversation(
                                                entry.id,
                                              );
                                            },
                                      icon: const Icon(
                                        Icons.unarchive_outlined,
                                        size: 19,
                                      ),
                                    ),
                                    SelectableIconButton(
                                      tooltip: 'Delete ${entry.title}',
                                      onPressed:
                                          state.historyBusy ||
                                              deleting ||
                                              (active &&
                                                  (state.chat.busy ||
                                                      state.attachmentPicking))
                                          ? null
                                          : () =>
                                                _delete(entry.id, entry.title),
                                      icon: deleting
                                          ? const SizedBox.square(
                                              dimension: 19,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                semanticsLabel:
                                                    'Deleting conversation',
                                              ),
                                            )
                                          : const Icon(
                                              Icons.delete_outline,
                                              size: 19,
                                            ),
                                    ),
                                  ] else
                                    SelectableIconButton(
                                      tooltip: 'Archive ${entry.title}',
                                      onPressed: busy || deleting
                                          ? null
                                          : () {
                                              widget.onInteracted?.call();
                                              state.archiveConversation(
                                                entry.id,
                                              );
                                            },
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
              onPressed: state.historySaving
                  ? null
                  : () {
                      widget.onInteracted?.call();
                      state.flushHistory();
                    },
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
