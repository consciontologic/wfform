import 'dart:async';
import 'package:flutter/material.dart';
import 'selectable_surface.dart';
import 'package:flutter/services.dart';
import '../app/studio_state.dart';
import '../app/theme.dart';
import '../features/chat/chat_controller.dart';
import '../features/chat/attachment.dart';
import '../features/documents/document_view.dart';
import 'attachment_widgets.dart';
import 'brand_mark.dart';
import 'edit_message_dialog.dart';
import 'history_browser.dart';
import 'model_browser.dart';
import 'utilities.dart';
import 'retry_control.dart';
import 'context_dialog.dart';

class StudioApp extends StatelessWidget {
  const StudioApp({super.key, required this.state});
  final StudioState state;
  static final _lightTheme = studioTheme();
  static final _darkTheme = studioTheme(brightness: Brightness.dark);
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state.appearance,
    builder: (context, _) => MaterialApp(
      title: 'wfform — Discover and Chat with Free OpenRouter Models',
      debugShowCheckedModeBanner: false,
      theme: _lightTheme,
      darkTheme: _darkTheme,
      themeMode: state.themeMode,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear(
              media.textScaler.scale(1) * state.textScale,
            ),
          ),
          child: child!,
        );
      },
      home: SelectionArea(child: StudioScreen(state: state)),
    ),
  );
}

class StudioScreen extends StatefulWidget {
  const StudioScreen({super.key, required this.state});
  final StudioState state;
  @override
  State<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends State<StudioScreen> {
  late final composer = TextEditingController(text: widget.state.draft);
  final composerFocus = FocusNode(debugLabel: 'Message composer');
  final chatKey = GlobalKey(debugLabel: 'Stable chat across layouts');
  final scaffoldKey = GlobalKey<ScaffoldState>();
  bool inspector = true;
  bool syncingDraft = false;
  StudioState get state => widget.state;
  @override
  void initState() {
    super.initState();
    composer.addListener(_saveDraft);
    state.addListener(_restoreDraft);
  }

  void _saveDraft() {
    if (!syncingDraft) state.setDraft(composer.text);
  }

  void _restoreDraft() {
    if (composer.text == state.draft) return;
    syncingDraft = true;
    composer.value = TextEditingValue(
      text: state.draft,
      selection: TextSelection.collapsed(offset: state.draft.length),
    );
    syncingDraft = false;
  }

  @override
  void dispose() {
    state.removeListener(_restoreDraft);
    composer.removeListener(_saveDraft);
    composer.dispose();
    composerFocus.dispose();
    super.dispose();
  }

  Future<void> _send({bool retry = false}) async {
    final model = state.catalog.selected;
    if (!state.online ||
        state.chat.busy ||
        state.attachmentPicking ||
        state.activeConversationArchived ||
        state.historyBusy) {
      return;
    }
    if (model == null) {
      await openModels(context, state);
      return;
    }
    if (!model.chatCompatible) return;
    final draft = composer.text;
    final conversationId = state.activeConversationId;
    if (!retry && draft.trim().isEmpty && state.draftAttachments.isEmpty) {
      return;
    }
    if (retry) {
      await state.chat.retry(model);
    } else {
      await state.chat.send(
        model,
        draft,
        attachments: state.draftAttachments,
        onAccepted: () {
          if (mounted && state.activeConversationId == conversationId) {
            if (composer.text == draft) composer.clear();
            state.clearDraftAttachments();
          }
        },
      );
    }
    await state.flushHistory();
  }

  Future<void> _editMessage(int index) async {
    final model = state.catalog.selected;
    if (model == null ||
        state.chat.busy ||
        state.historyBusy ||
        state.activeConversationArchived ||
        !state.online ||
        state.attachmentPicking) {
      return;
    }
    final original = state.chat.messages[index];
    final conversationId = state.activeConversationId;
    await showSelectableDialog<void>(
      context: context,
      builder: (context) => EditMessageDialog(
        original: original,
        submit: (String text, List<ChatAttachment> files) {
          final currentModel = state.catalog.selected;
          if (state.activeConversationId != conversationId || !state.online) {
            return 'This conversation is no longer available to send. Close the editor and reopen it.';
          }
          if (currentModel == null || currentModel.id != model.id) {
            return 'The original model is no longer selected or available. Close this editor and choose a valid model.';
          }
          var accepted = false;
          final sending = state.chat.send(
            currentModel,
            text,
            attachments: files,
            editedFrom: index,
            onAccepted: () => accepted = true,
          );
          unawaited(sending.whenComplete(state.flushHistory));
          return accepted
              ? null
              : state.chat.error?.message ??
                    'The message could not be accepted. Try again when the current operation finishes.';
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([state, state.catalog]),
    builder: (context, _) => LayoutBuilder(
      builder: (context, box) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final compact =
            box.maxWidth < 600 || (scale >= 1.8 && box.maxWidth < 800);
        final expanded = box.maxWidth >= 1100 && scale < 1.8;
        final wideDetails = expanded && box.maxWidth >= 1420 && inspector;
        final palette = StudioPalette.of(context);
        return Scaffold(
          key: scaffoldKey,
          resizeToAvoidBottomInset: true,
          drawer: compact
              ? Drawer(
                  width: (box.maxWidth - 24).clamp(260.0, 340.0),
                  child: SafeArea(
                    child: _SidePanel(state: state, drawer: true),
                  ),
                )
              : null,
          body: SafeArea(
            child: Column(
              children: [
                _Header(
                  compact: compact,
                  onMenu: () => scaffoldKey.currentState?.openDrawer(),
                ),
                if (state.platform.updateAvailable) _UpdateNotice(state: state),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (expanded)
                        Container(
                          key: const ValueKey('expanded-sidebar'),
                          width: 290,
                          decoration: BoxDecoration(
                            color: palette.cream,
                            border: Border(
                              right: BorderSide(
                                color: palette.border,
                                width: 1.5,
                              ),
                            ),
                          ),
                          child: _SidePanel(state: state),
                        ),
                      if (!expanded && !compact)
                        Container(
                          key: const ValueKey('medium-rail'),
                          width: 72,
                          decoration: BoxDecoration(
                            color: palette.cream,
                            border: Border(
                              right: BorderSide(color: palette.border),
                            ),
                          ),
                          child: Column(
                            children: [
                              const SizedBox(height: 16),
                              ListenableBuilder(
                                listenable: state.chat,
                                builder: (context, _) => SelectableIconButton(
                                  tooltip: 'New conversation',
                                  onPressed:
                                      state.chat.busy || state.historyBusy
                                      ? null
                                      : state.newConversation,
                                  icon: const Icon(Icons.edit_square),
                                ),
                              ),
                              SelectableIconButton(
                                tooltip: 'Conversation history',
                                onPressed: () => openHistory(context, state),
                                icon: const Icon(Icons.history),
                              ),
                              const Spacer(),
                              _UtilityActions(state: state),
                              const SizedBox(height: 12),
                            ],
                          ),
                        ),
                      Expanded(
                        child: LayoutBuilder(
                          key: chatKey,
                          builder: (context, chatBox) => Column(
                            children: [
                              _SelectionBar(
                                state: state,
                                compact: compact,
                                expanded: expanded,
                                onToggleDetails:
                                    box.maxWidth >= 1420 && scale < 1.8
                                    ? () =>
                                          setState(() => inspector = !inspector)
                                    : null,
                              ),
                              if (!state.online)
                                _Notice(
                                  text:
                                      'Offline · remote chat is unavailable. Your saved conversations and draft are here.',
                                  color: palette.peach,
                                ),
                              if (state.catalog.selectionNotice != null)
                                _Notice(
                                  text: state.catalog.selectionNotice!,
                                  color: palette.peach,
                                ),
                              if (state.conversationNotice != null &&
                                  !state.activeConversationArchived)
                                _Notice(
                                  text: state.conversationNotice!,
                                  color: palette.peach,
                                ),
                              if (state.historyError != null)
                                _Notice(
                                  text: state.historyError!.message,
                                  color: palette.peach,
                                ),
                              if (state.catalog.error != null && !expanded)
                                _Notice(
                                  text: state.catalog.error!.message,
                                  color: palette.peach,
                                ),
                              if (state.activeConversationArchived)
                                Container(
                                  color: palette.lilac,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 6,
                                  ),
                                  child: Row(
                                    children: [
                                      const Expanded(
                                        child: Text(
                                          'Archived conversation · restore to continue.',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            state.restoreConversation(
                                              state.activeConversationId!,
                                            ),
                                        child: const Text('Restore'),
                                      ),
                                    ],
                                  ),
                                ),
                              Expanded(
                                child: _Conversation(
                                  state: state,
                                  compact: compact,
                                  onSuggestion: (text) {
                                    if (!state.activeConversationArchived) {
                                      composer.text = text;
                                      composerFocus.requestFocus();
                                    }
                                  },
                                  onChoose: () => openModels(context, state),
                                  onEdit: _editMessage,
                                ),
                              ),
                              _Composer(
                                state: state,
                                maxHeight: chatBox.maxHeight * .5,
                                controller: composer,
                                focus: composerFocus,
                                compact: compact,
                                onSend: () => _send(),
                                onRetry: () => _send(retry: true),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (wideDetails)
                        Container(
                          width: 310,
                          decoration: BoxDecoration(
                            color: palette.cream,
                            border: Border(
                              left: BorderSide(
                                color: palette.border,
                                width: 1.5,
                              ),
                            ),
                          ),
                          child: state.catalog.selected == null
                              ? const Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text(
                                    'Choose a model to inspect its capabilities and availability.',
                                  ),
                                )
                              : SingleChildScrollView(
                                  padding: const EdgeInsets.all(22),
                                  child: ModelDetails(
                                    state: state,
                                    model: state.catalog.selected!,
                                  ),
                                ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _SidePanel extends StatelessWidget {
  const _SidePanel({required this.state, this.drawer = false});
  final StudioState state;
  final bool drawer;
  void _close(BuildContext context) {
    if (drawer) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: ListenableBuilder(
          listenable: state.chat,
          builder: (context, _) => FilledButton.icon(
            onPressed: state.chat.busy || state.historyBusy
                ? null
                : () async {
                    if (await state.newConversation() && context.mounted) {
                      _close(context);
                    }
                  },
            icon: const Icon(Icons.edit_square, size: 18),
            label: const Text('New conversation'),
          ),
        ),
      ),
      Expanded(
        child: ConversationHistory(
          state: state,
          onOpened: () => _close(context),
        ),
      ),
      const Divider(),
      _UtilityActions(
        state: state,
        labels: true,
        beforeOpen: () => _close(context),
      ),
      const SizedBox(height: 12),
    ],
  );
}

class _UtilityActions extends StatelessWidget {
  const _UtilityActions({
    required this.state,
    this.labels = false,
    this.beforeOpen,
  });
  final StudioState state;
  final bool labels;
  final VoidCallback? beforeOpen;
  @override
  Widget build(BuildContext context) {
    Widget action(String label, IconData icon, VoidCallback open) {
      void invoke() {
        beforeOpen?.call();
        open();
      }

      return labels
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SelectableTooltip(
                message: label,
                child: ListTile(
                  dense: true,
                  minVerticalPadding: 8,
                  leading: Icon(icon),
                  title: Text(label),
                  onTap: invoke,
                ),
              ),
            )
          : SelectableIconButton(
              tooltip: label,
              onPressed: invoke,
              icon: Icon(icon),
            );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        action(
          'Diagnostics',
          Icons.monitor_heart_outlined,
          () => openDiagnostics(context, state),
        ),
        action(
          'Settings',
          Icons.settings_outlined,
          () => openSettings(context, state),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.compact, required this.onMenu});
  final bool compact;
  final VoidCallback onMenu;
  @override
  Widget build(BuildContext context) {
    final colors = StudioPalette.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 24, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border, width: 1.5)),
      ),
      child: Row(
        children: [
          if (compact)
            SelectableIconButton(
              tooltip: 'Open sidebar',
              onPressed: onMenu,
              icon: const Icon(Icons.menu),
            ),
          const WfformMark(),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'wfform',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 22 : 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                  ),
                ),
                if (!compact)
                  Text(
                    'Wrapper for Free Open Router Models',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.muted,
                      letterSpacing: .3,
                    ),
                  ),
              ],
            ),
          ),
          if (!compact)
            const Text(
              'OPENROUTER / FREE ONLY',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
        ],
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.state,
    required this.compact,
    required this.expanded,
    this.onToggleDetails,
  });
  final StudioState state;
  final bool compact, expanded;
  final VoidCallback? onToggleDetails;
  @override
  Widget build(BuildContext context) {
    final model = state.catalog.selected;
    final colors = StudioPalette.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 24,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.border.withValues(alpha: .3)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('model-selector'),
                  onPressed: () => openModels(context, state),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: colors.surface,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.bubble_chart_outlined, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          model?.name ?? 'Choose a free model',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.expand_more, size: 20),
                    ],
                  ),
                ),
              ),
              if (onToggleDetails != null)
                SelectableIconButton(
                  tooltip: 'Toggle model inspector',
                  onPressed: onToggleDetails,
                  icon: const Icon(Icons.view_sidebar_outlined),
                ),
            ],
          ),
          if (model != null)
            ListenableBuilder(
              listenable: state.health,
              builder: (context, _) => Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Text(
                  '${healthLabel(state.health.forModel(model.id).status)} · ${state.catalog.fromCache || state.catalog.stale ? 'cached catalog' : 'live catalog'}',
                  style: TextStyle(fontSize: 12, color: colors.muted),
                ),
              ),
            )
          else if (!expanded)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                state.catalog.refreshing
                    ? 'Fetching free models…'
                    : '${state.catalog.models.length} listings · ${state.catalog.fromCache || state.catalog.stale ? 'cached' : 'live'} catalog',
                style: TextStyle(fontSize: 12, color: colors.muted),
              ),
            ),
        ],
      ),
    );
  }
}

class _Conversation extends StatefulWidget {
  const _Conversation({
    required this.state,
    required this.compact,
    required this.onSuggestion,
    required this.onChoose,
    required this.onEdit,
  });
  final StudioState state;
  final bool compact;
  final ValueChanged<String> onSuggestion;
  final VoidCallback onChoose;
  final ValueChanged<int> onEdit;
  @override
  State<_Conversation> createState() => _ConversationState();
}

class _ConversationState extends State<_Conversation> {
  final scroll = ScrollController();
  final Map<ChatMessage, Widget> _messageWidgets = {};
  bool? _canEdit;
  bool _scrollScheduled = false;
  late ChatController observedChat;
  @override
  void initState() {
    super.initState();
    observedChat = widget.state.chat;
    observedChat.addListener(_follow);
  }

  @override
  void didUpdateWidget(covariant _Conversation old) {
    super.didUpdateWidget(old);
    if (!identical(observedChat, widget.state.chat)) {
      observedChat.removeListener(_follow);
      observedChat = widget.state.chat;
      observedChat.addListener(_follow);
    }
  }

  void _follow() {
    if (!_scrollScheduled &&
        scroll.hasClients &&
        scroll.position.extentAfter < 150) {
      _scrollScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollScheduled = false;
        if (mounted && scroll.hasClients) {
          scroll.jumpTo(scroll.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  void dispose() {
    observedChat.removeListener(_follow);
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state.chat,
    builder: (context, _) {
      final messages = widget.state.chat.messages;
      final canEdit =
          widget.state.online &&
          !widget.state.chat.busy &&
          !widget.state.historyBusy &&
          !widget.state.activeConversationArchived &&
          !widget.state.attachmentPicking &&
          widget.state.catalog.selected != null;
      if (_canEdit != canEdit) _messageWidgets.clear();
      _canEdit = canEdit;
      final retained = messages.toSet();
      _messageWidgets.removeWhere((message, _) => !retained.contains(message));
      if (messages.isEmpty) {
        return SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 660),
              child: Padding(
                padding: EdgeInsets.all(widget.compact ? 24 : 48),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
                    Text(
                      'START A CONVERSATION',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w700,
                        color: StudioPalette.of(context).muted,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Choose a free model.\nAsk your first question.',
                      style: widget.compact
                          ? Theme.of(context).textTheme.headlineMedium
                          : Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Explore the free side of OpenRouter. Pick a model, check its capabilities, and start a conversation.',
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.6,
                        color: StudioPalette.of(context).muted,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      'OR START WITH A QUESTION',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.3,
                        fontWeight: FontWeight.bold,
                        color: StudioPalette.of(context).muted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _Suggestion(
                      text: 'How many r’s are in “strawberry”?',
                      onTap: () => widget.onSuggestion(
                        'How many r’s are in the word strawberry?',
                      ),
                    ),
                    _Suggestion(
                      text: 'Explain something complex, simply.',
                      onTap: () => widget.onSuggestion(
                        'Explain how a rainbow forms in simple terms.',
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Only free routes. No silent model switching.\nYour conversation stays in this browser until you send it.',
                      style: TextStyle(
                        fontSize: 12,
                        color: StudioPalette.of(context).muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
      return ListView.builder(
        controller: scroll,
        padding: EdgeInsets.symmetric(
          horizontal: widget.compact ? 16 : 32,
          vertical: 24,
        ),
        itemCount: messages.length,
        itemBuilder: (context, index) => _messageWidgets.putIfAbsent(
          messages[index],
          () => Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 850),
              child: _Message(
                message: messages[index],
                index: index,
                onEdit: canEdit ? () => widget.onEdit(index) : null,
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _Suggestion extends StatelessWidget {
  const _Suggestion({required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: StudioPalette.of(context).cream,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
      ),
      child: Row(
        children: [
          Expanded(child: Text(text)),
          const SizedBox(width: 12),
          const Icon(Icons.north_east, size: 16),
        ],
      ),
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({required this.message, required this.index, this.onEdit});
  final ChatMessage message;
  final int index;
  final VoidCallback? onEdit;
  @override
  Widget build(BuildContext context) {
    final user = message.role == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: PaperPanel(
        color: user
            ? StudioPalette.of(context).lilac
            : StudioPalette.of(context).surface,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    user ? 'YOU' : message.modelId ?? 'MODEL',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .5,
                    ),
                  ),
                ),
                if (message.content.isNotEmpty)
                  SelectableIconButton(
                    tooltip: 'Copy message ${index + 1}',
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: message.content)),
                    icon: const Icon(Icons.copy, size: 17),
                  ),
                if (user)
                  SelectableIconButton(
                    tooltip: 'Edit and resend message ${index + 1}',
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                  ),
              ],
            ),
            if (message.editedFrom != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Edited copy of message ${message.editedFrom! + 1}',
                  style: TextStyle(
                    fontSize: 12,
                    color: StudioPalette.of(context).muted,
                  ),
                ),
              ),
            if (message.attachments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AttachmentList(files: message.attachments),
              ),
            if (message.reasoning.isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('Model reasoning', style: TextStyle(fontSize: 13)),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Semantics(
                      container: true,
                      child: SelectableText(
                        message.reasoning,
                        semanticsLabel: message.reasoning,
                        style: TextStyle(
                          fontSize: 13,
                          color: StudioPalette.of(context).muted,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            if (!user && message.content.isNotEmpty)
              DocumentView(
                source: message.content,
                streaming: !message.complete,
              )
            else if (!user || message.content.isNotEmpty)
              SelectableText(
                message.content.isEmpty
                    ? (message.failure != null
                          ? 'No response text received.'
                          : message.complete
                          ? 'No text returned.'
                          : 'Waiting for response…')
                    : message.content,
                semanticsLabel: message.content.isEmpty
                    ? 'No response text yet'
                    : message.content,
                style: TextStyle(fontSize: 16, height: 1.6),
              ),
            if (message.failure != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'Incomplete · ${message.failure!.message}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            if (!user &&
                message.failure == null &&
                message.finishReason != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  message.terminationLabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: StudioPalette.of(context).muted,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.state,
    required this.controller,
    required this.focus,
    required this.compact,
    required this.onSend,
    required this.onRetry,
    required this.maxHeight,
  });
  final StudioState state;
  final TextEditingController controller;
  final FocusNode focus;
  final bool compact;
  final VoidCallback onSend, onRetry;
  final double maxHeight;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state.chat.statusChanges,
    builder: (context, _) {
      final chat = state.chat;
      final model = state.catalog.selected;
      final mimeTypes = model?.allowedAttachmentMimeTypes ?? <String>{};
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          child: Container(
            padding: EdgeInsets.fromLTRB(
              compact ? 12 : 28,
              12,
              compact ? 12 : 28,
              12,
            ),
            decoration: BoxDecoration(
              color: StudioPalette.of(context).paper,
              border: Border(
                top: BorderSide(
                  color: StudioPalette.of(context).border.withValues(alpha: .3),
                ),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (state.configurationLoading)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Loading connection settings… You can keep drafting.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                if (state.draftAttachments.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 90),
                    child: SingleChildScrollView(
                      child: AttachmentList(
                        files: state.draftAttachments,
                        onRemove:
                            state.activeConversationArchived ||
                                state.historyBusy ||
                                state.attachmentPicking
                            ? null
                            : state.removeDraftAttachment,
                      ),
                    ),
                  ),
                if (state.attachmentError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        state.attachmentError!.message,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                if (chat.error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            chat.error!.message,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (chat.canRetry || chat.retryAt != null)
                          RetryControl(
                            retryAt: chat.retryAt,
                            onRetry:
                                state.online &&
                                    state.catalog.selected != null &&
                                    !state.activeConversationArchived &&
                                    !state.historyBusy
                                ? onRetry
                                : null,
                          ),
                      ],
                    ),
                  ),
                if (chat.busy)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        chat.progress,
                        style: TextStyle(
                          fontSize: 12,
                          color: StudioPalette.of(context).muted,
                        ),
                      ),
                    ),
                  ),
                Shortcuts(
                  shortcuts: const {
                    SingleActivator(LogicalKeyboardKey.enter, control: true):
                        ActivateIntent(),
                    SingleActivator(LogicalKeyboardKey.enter, meta: true):
                        ActivateIntent(),
                  },
                  child: Actions(
                    actions: {
                      ActivateIntent: CallbackAction<ActivateIntent>(
                        onInvoke: (_) {
                          onSend();
                          return null;
                        },
                      ),
                    },
                    child: TextField(
                      key: const ValueKey('composer'),
                      controller: controller,
                      focusNode: focus,
                      readOnly:
                          state.activeConversationArchived || state.historyBusy,
                      minLines:
                          MediaQuery.sizeOf(context).height -
                                      MediaQuery.viewInsetsOf(context).bottom <
                                  500 ||
                              MediaQuery.textScalerOf(context).scale(1) >= 1.8
                          ? 2
                          : 3,
                      maxLines: compact ? 5 : 8,
                      maxLength: 32000,
                      decoration: InputDecoration(
                        labelText: 'Message',
                        hintText: state.online
                            ? 'What’s on your mind?'
                            : 'Draft a message for later…',
                        counterText: '',
                        suffixIcon: chat.busy
                            ? SelectableIconButton(
                                tooltip: 'Cancel response',
                                onPressed: chat.cancel,
                                icon: const Icon(Icons.stop_circle_outlined),
                              )
                            : SelectableIconButton(
                                tooltip: state.online
                                    ? 'Send message'
                                    : 'Chat unavailable offline',
                                onPressed:
                                    state.online &&
                                        !state.attachmentPicking &&
                                        !state.activeConversationArchived &&
                                        !state.historyBusy
                                    ? onSend
                                    : null,
                                icon: const Icon(Icons.arrow_upward),
                              ),
                      ),
                      style: TextStyle(fontSize: 16),
                      textCapitalization: TextCapitalization.sentences,
                      keyboardType: TextInputType.multiline,
                    ),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: chat.busy || state.historyBusy
                          ? null
                          : () => openContextControls(context, state),
                      icon: const Icon(Icons.tune, size: 17),
                      label: Text(
                        chat.contextStartIndex == 0
                            ? 'Context'
                            : 'Context from #${chat.contextStartIndex + 1}',
                      ),
                    ),
                    if (chat.messages.isNotEmpty &&
                        chat.messages.last.finishReason == 'length')
                      TextButton(
                        onPressed:
                            chat.busy ||
                                state.historyBusy ||
                                state.activeConversationArchived ||
                                state.configurationLoading ||
                                !state.online ||
                                model == null
                            ? null
                            : () async {
                                await chat.continueResponse(model);
                                await state.flushHistory();
                              },
                        child: const Text('Continue answer'),
                      ),
                    ValueListenableBuilder<String>(
                      valueListenable: state.historyStatus,
                      builder: (context, status, _) => Semantics(
                        label: 'Conversation storage: $status',
                        child: Text(
                          status,
                          style: TextStyle(
                            fontSize: 11,
                            color: status == 'Save failed'
                                ? Theme.of(context).colorScheme.error
                                : StudioPalette.of(context).muted,
                          ),
                        ),
                      ),
                    ),
                    if (state.attachmentPicking)
                      TextButton.icon(
                        onPressed: state.cancelAttachmentPick,
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Cancel adding files'),
                      )
                    else
                      SelectableTooltip(
                        message: mimeTypes.isEmpty
                            ? 'Choose a model with supported file inputs. Check Model details for capabilities.'
                            : 'Up to 4 files, 12 MiB total. UTF-8 text/source: 256 KiB each; supported media: 8 MiB each. Files are sent only when you send the message.',
                        child: TextButton.icon(
                          onPressed:
                              mimeTypes.isNotEmpty &&
                                  !chat.busy &&
                                  !state.historyBusy &&
                                  !state.activeConversationArchived
                              ? () => state.pickAttachments(mimeTypes)
                              : null,
                          icon: const Icon(Icons.attach_file, size: 18),
                          label: const Text('Add files'),
                        ),
                      ),
                    if (model != null)
                      Text(
                        state.attachmentPicking
                            ? 'Reading selected files…'
                            : model.attachmentSummary,
                        style: TextStyle(
                          fontSize: 11,
                          color: StudioPalette.of(context).muted,
                        ),
                      ),
                  ],
                ),
                if (!compact)
                  Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Ctrl / ⌘ + Enter to send · Enter for a new line · Responses can be mistaken.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: StudioPalette.of(context).muted,
                      ),
                    ),
                  ),
                if (model != null)
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, value, _) {
                      final budget = chat.contextBudget(
                        model,
                        draft: value.text,
                        attachments: state.draftAttachments,
                      );
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          budget.warning ?? budget.summary,
                          style: TextStyle(
                            fontSize: 11,
                            color: budget.fits
                                ? StudioPalette.of(context).muted
                                : Theme.of(context).colorScheme.error,
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.color});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: color,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Semantics(
      liveRegion: true,
      child: Text(
        text,
        style: TextStyle(fontSize: 12),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  );
}

class _UpdateNotice extends StatelessWidget {
  const _UpdateNotice({required this.state});
  final StudioState state;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state.chat,
    builder: (context, _) => Container(
      color: StudioPalette.of(context).sage,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              state.updateError ??
                  'An update is ready. Your draft and conversation will be saved.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: state.chat.busy ? null : state.applyUpdate,
            child: Text(
              state.chat.busy ? 'Finish request first' : 'Save & update',
            ),
          ),
        ],
      ),
    ),
  );
}
