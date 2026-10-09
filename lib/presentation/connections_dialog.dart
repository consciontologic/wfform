import 'dart:convert';
import 'package:flutter/material.dart';
import '../app/studio_state.dart';
import '../app/theme.dart';
import '../features/chat/chat_controller.dart';
import '../features/documents/document_view.dart';
import '../features/tools/mcp_client.dart';
import '../features/tools/tools.dart';
import '../shared/diagnostics.dart';
import '../shared/platform.dart' show desktopToolsExplanation;
import 'brand_mark.dart';
import 'model_browser.dart';
import 'selectable_surface.dart';

Future<void> openTools(BuildContext context, StudioState state) =>
    showSelectableDialog<void>(
      context: context,
      builder: (context) => state.platform.toolsAvailable
          ? _ToolsDialog(state: state)
          : AlertDialog(
              title: const Text('Tools need a desktop computer'),
              content: const SelectableText(desktopToolsExplanation),
              scrollable: true,
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Got it'),
                ),
              ],
            ),
    );

class _ToolsDialog extends StatefulWidget {
  const _ToolsDialog({required this.state});
  final StudioState state;
  @override
  State<_ToolsDialog> createState() => _ToolsDialogState();
}

class _ToolsDialogState extends State<_ToolsDialog> {
  final name = TextEditingController(),
      endpoint = TextEditingController(),
      token = TextEditingController();
  String? editingId, error;
  StudioState get state => widget.state;
  bool get locked =>
      state.chat.busy || state.historyBusy || state.activeConversationArchived;
  @override
  void dispose() {
    state.toolConnections.cancel();
    name.dispose();
    endpoint.dispose();
    token.dispose();
    super.dispose();
  }

  Future<void> connect() async {
    setState(() => error = null);
    try {
      final connection = McpConnection(
        id: editingId ?? 'connection-${DateTime.now().microsecondsSinceEpoch}',
        name: name.text.trim(),
        url: endpoint.text.trim(),
        bearerToken: token.text.trim(),
      );
      state.diagnostics.addSecret(connection.bearerToken);
      if (await state.toolConnections.connect(connection) && mounted) {
        setState(() {
          editingId = null;
          name.clear();
          endpoint.clear();
          token.clear();
        });
      }
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = failure is AppFailure
              ? failure.message
              : 'Check the connection settings.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      state.toolConnections,
      state.chat.statusChanges,
    ]),
    builder: (context, _) {
      final connections = state.toolConnections;
      final available = connections.registry.tools;
      final supported =
          state.catalog.selected?.supportedParameters.contains('tools') ??
          false;
      final unavailable = state.chat.enabledTools.difference(
        available.map((t) => t.name).toSet(),
      );
      return Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 680,
            maxHeight: MediaQuery.sizeOf(context).height * .9,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StudioDialogHeader(
                title: 'Tools & connections',
                glyph: BrandGlyph.context,
                color: StudioPalette.of(context).lilac,
                closeTooltip: 'Close tools',
                onClose: () => Navigator.pop(context),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(20),
                  children: [
                    const Text(
                      'Ordinary chat works without any connections. Connect an MCP server or wfformcomp to let a compatible model request your tools. You approve each call before it runs.',
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        onPressed: () => openToolsGuide(context),
                        icon: const Icon(Icons.help_outline),
                        label: const Text('How to use tools'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (!supported)
                      const Text(
                        'Select a model that supports tools to enable them for this conversation.',
                      ),
                    if (unavailable.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${unavailable.length} selected tool(s) are disconnected. Reconnect their server before sending, or remove them.',
                            ),
                            TextButton(
                              onPressed: locked
                                  ? null
                                  : () => state.chat.setEnabledTools(
                                      state.chat.enabledTools.difference(
                                        unavailable,
                                      ),
                                    ),
                              child: const Text('Remove unavailable tools'),
                            ),
                          ],
                        ),
                      ),
                    for (final connection in connections.saved)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                connection.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SelectableText(connection.url),
                              Text(
                                connections.isConnected(connection.id)
                                    ? 'Connected'
                                    : 'Disconnected · reconnect to use',
                              ),
                              Wrap(
                                spacing: 8,
                                children: [
                                  TextButton(
                                    onPressed: locked || connections.busy
                                        ? null
                                        : () => setState(() {
                                            editingId = connection.id;
                                            name.text = connection.name;
                                            endpoint.text = connection.url;
                                            token.clear();
                                          }),
                                    child: const Text('Edit / reconnect'),
                                  ),
                                  if (connections.isConnected(connection.id))
                                    TextButton(
                                      onPressed: locked || connections.busy
                                          ? null
                                          : () => connections.disconnect(
                                              connection.id,
                                            ),
                                      child: const Text('Disconnect'),
                                    ),
                                  TextButton(
                                    onPressed: locked || connections.busy
                                        ? null
                                        : () =>
                                              connections.forget(connection.id),
                                    child: const Text('Forget'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    for (final tool in available)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(tool.originalName),
                        subtitle: Text(
                          '${tool.serverName}${tool.description.isEmpty ? '' : ' · ${tool.description}'}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        value: state.chat.enabledTools.contains(tool.name),
                        onChanged: locked || !supported
                            ? null
                            : (checked) {
                                final selected = Set<String>.of(
                                  state.chat.enabledTools,
                                );
                                checked == true
                                    ? selected.add(tool.name)
                                    : selected.remove(tool.name);
                                state.chat.setEnabledTools(selected);
                              },
                      ),
                    const Divider(height: 32),
                    Text(
                      editingId == null ? 'Add a connection' : 'Reconnect',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: const ValueKey('mcp-name'),
                      controller: name,
                      enabled: !locked && !connections.busy,
                      maxLength: 128,
                      decoration: const InputDecoration(
                        labelText: 'Connection name',
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('mcp-url'),
                      controller: endpoint,
                      enabled: !locked && !connections.busy,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'MCP endpoint',
                        hintText: 'https://…/mcp or http://localhost:…/mcp',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('mcp-token'),
                      controller: token,
                      enabled: !locked && !connections.busy,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Bearer / pairing token (optional)',
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Tokens stay in memory for this session. Only the connection name and endpoint are saved. Reconnect after reloading. Tool descriptions, arguments and results are sent to your selected model when used.',
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'The server must support Streamable HTTP and permit this browser origin. For local commands or stdio MCP servers, start wfformcomp and use its displayed /mcp address and pairing token.',
                    ),
                    if (error ?? connections.error case final String message)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          message,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton(
                          onPressed: locked || connections.busy
                              ? null
                              : connect,
                          child: Text(
                            connections.busy ? 'Connecting…' : 'Connect',
                          ),
                        ),
                        if (connections.busy)
                          TextButton(
                            onPressed: connections.cancel,
                            child: const Text('Cancel connection'),
                          ),
                        if (editingId != null)
                          TextButton(
                            onPressed: connections.busy
                                ? null
                                : () => setState(() {
                                    editingId = null;
                                    name.clear();
                                    endpoint.clear();
                                    token.clear();
                                  }),
                            child: const Text('New connection'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<bool> approveTool(
  BuildContext context,
  ConnectedTool tool,
  Map<String, dynamic> arguments, {
  ChatController? chat,
}) async =>
    await showSelectableDialog<bool>(
      context: context,
      builder: (_) =>
          _ToolApproval(tool: tool, arguments: arguments, chat: chat),
    ) ??
    false;

class _ToolApproval extends StatefulWidget {
  const _ToolApproval({required this.tool, required this.arguments, this.chat});
  final ConnectedTool tool;
  final Map<String, dynamic> arguments;
  final ChatController? chat;
  @override
  State<_ToolApproval> createState() => _ToolApprovalState();
}

class _ToolApprovalState extends State<_ToolApproval> {
  @override
  void initState() {
    super.initState();
    widget.chat?.statusChanges.addListener(changed);
  }

  void changed() {
    if (widget.chat?.busy == false && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ModalRoute.of(context)?.isCurrent == true) {
          Navigator.pop(context, false);
        }
      });
    }
  }

  @override
  void dispose() {
    widget.chat?.statusChanges.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Run ${widget.tool.originalName}?'),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Server: ${widget.tool.serverName}'),
            const SizedBox(height: 12),
            const Text(
              'Review the arguments before allowing this action. The result will be sent to your selected model and saved in this conversation.',
            ),
            const SizedBox(height: 12),
            ReadableDataView(source: jsonEncode(widget.arguments)),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Deny'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: const Text('Allow once'),
      ),
    ],
  );
}

/// Bundled with the app so setup instructions remain available offline.
Future<void> openToolsGuide(
  BuildContext context, {
  bool companion = false,
}) async {
  final document = DefaultAssetBundle.of(
    context,
  ).loadString(companion ? 'docs/wfformcomp.md' : 'docs/tools.md');
  await showSelectableDialog<void>(
    context: context,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: SizedBox(
        width: 760,
        height: MediaQuery.sizeOf(context).height * .9,
        child: Column(
          children: [
            StudioDialogHeader(
              title: companion ? 'Companion setup' : 'How to use tools',
              glyph: BrandGlyph.context,
              color: StudioPalette.of(context).lilac,
              closeTooltip: companion
                  ? 'Back to tools guide'
                  : 'Close tools guide',
              onClose: () => Navigator.pop(context),
            ),
            if (!companion)
              TextButton.icon(
                onPressed: () => openToolsGuide(context, companion: true),
                icon: const Icon(Icons.computer),
                label: const Text('Companion setup'),
              ),
            Expanded(
              child: FutureBuilder<String>(
                future: document,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'The tools guide could not be loaded. Reopen it to try again.',
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: DocumentView(
                      source: snapshot.data!,
                      showCopy: false,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
