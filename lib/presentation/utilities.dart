import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app/studio_state.dart';
import '../app/theme.dart';
import '../config/credential_preference.dart';
import '../shared/diagnostics.dart';
import 'model_browser.dart';
import 'selectable_surface.dart';

Future<void> openDiagnostics(
  BuildContext context,
  StudioState state,
) => showSelectableDialog<void>(
  context: context,
  builder: (context) => Dialog(
    clipBehavior: Clip.antiAlias,
    insetPadding: const EdgeInsets.all(12),
    child: SizedBox(
      width: 850,
      height: MediaQuery.sizeOf(context).height * .88,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StudioDialogHeader(
            title: 'Diagnostics',
            emoji: '🩺',
            color: StudioPalette.of(context).diagnostics,
            closeTooltip: 'Close diagnostics',
            onClose: () => Navigator.pop(context),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: state.diagnostics,
              builder: (context, _) {
                final events = state.diagnostics.events;
                return ListView.builder(
                  itemCount: events.isEmpty ? 2 : events.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) return _DiagnosticTools(state: state);
                    if (events.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No diagnostic events yet.'),
                      );
                    }
                    final diagnostic = events[index - 1];
                    final event = diagnostic.toJson();
                    return ExpansionTile(
                      key: ValueKey('${event['timestamp']}$index'),
                      collapsedBackgroundColor: StudioPalette.of(
                        context,
                      ).surface,
                      backgroundColor: StudioPalette.of(context).cream,
                      textColor: StudioPalette.of(context).ink,
                      collapsedTextColor: StudioPalette.of(context).ink,
                      leading: Icon(
                        diagnostic.isError
                            ? Icons.error_outline
                            : event['kind'] == 'success'
                            ? Icons.check_circle_outline
                            : Icons.info_outline,
                        color: diagnostic.isError
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.secondary,
                      ),
                      title: Text('${event['operation']} · ${event['kind']}'),
                      subtitle: Text(
                        '${event['summary']}\n${event['timestamp']}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SelectableText(
                              const JsonEncoder.withIndent('  ').convert(event),
                              semanticsLabel: const JsonEncoder.withIndent(
                                '  ',
                              ).convert(event),
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  ),
);

class _DiagnosticTools extends StatelessWidget {
  const _DiagnosticTools({required this.state});
  final StudioState state;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _diagnosticSummary(state.diagnostics.events),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        const Text(
          'Successful operations are activity, not errors. Error entries describe past failures; they do not necessarily mean the app is still failing.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => Clipboard.setData(
                ClipboardData(text: state.diagnostics.export()),
              ),
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy'),
            ),
            OutlinedButton.icon(
              onPressed: () => state.platform.exportText(
                'wfform-diagnostics.json',
                state.diagnostics.export(),
              ),
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Export'),
            ),
            TextButton(
              onPressed: state.diagnostics.clear,
              child: const Text('Clear log'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Bounded local log. Keys are redacted; prompts, responses and upstream error text are omitted. Nothing is uploaded.',
          style: TextStyle(color: StudioPalette.of(context).muted),
        ),
      ],
    ),
  );
}

String _diagnosticSummary(List<DiagnosticEvent> events) {
  final errors = events.where((event) => event.isError).length;
  final activity = events.length - errors;
  return '${errors == 0 ? 'No errors recorded' : '$errors ${errors == 1 ? 'error' : 'errors'} recorded'} · $activity activity ${activity == 1 ? 'event' : 'events'}';
}

Future<void> openSettings(BuildContext context, StudioState state) =>
    showSelectableDialog<void>(
      context: context,
      builder: (context) => _Settings(state: state),
    );

class _Settings extends StatefulWidget {
  const _Settings({required this.state});
  final StudioState state;
  @override
  State<_Settings> createState() => _SettingsState();
}

class _SettingsState extends State<_Settings> {
  late final keyInput = TextEditingController(text: widget.state.config.apiKey);
  String? error;
  bool saving = false;

  bool get connectionBusy =>
      saving ||
      widget.state.chat.busy ||
      widget.state.historyBusy ||
      widget.state.attachmentPicking;

  Future<void> saveKey(String value) async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.state.changeKey(value);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            value.trim().isEmpty
                ? 'API key cleared. Local configuration will not restore it.'
                : 'API key saved in this browser.',
          ),
        ),
      );
    } catch (failure) {
      if (mounted) {
        setState(() {
          error = AppFailure.from(failure).message;
          saving = false;
        });
      }
    }
  }

  @override
  void dispose() {
    keyInput.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    clipBehavior: Clip.antiAlias,
    insetPadding: const EdgeInsets.all(12),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 600),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StudioDialogHeader(
            title: 'Settings',
            emoji: '⚙️',
            color: StudioPalette.of(context).lilac,
            closeTooltip: 'Close settings',
            onClose: () => Navigator.pop(context),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Appearance',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final option in const [
                        (ThemeMode.light, Icons.light_mode_outlined, 'Light'),
                        (ThemeMode.dark, Icons.dark_mode_outlined, 'Dark'),
                        (
                          ThemeMode.system,
                          Icons.brightness_auto_outlined,
                          'System',
                        ),
                      ])
                        ChoiceChip(
                          avatar: Icon(option.$2, size: 18),
                          label: Text(option.$3),
                          selected: widget.state.themeMode == option.$1,
                          onSelected: (_) {
                            widget.state.setThemeMode(option.$1);
                            setState(() {});
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'System follows your device’s appearance. Your choice is saved in this browser.',
                    style: TextStyle(
                      fontSize: 12,
                      color: StudioPalette.of(context).muted,
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'YOUR OPENROUTER CONNECTION',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: keyInput,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    maxLength: CredentialPreference.maxKeyLength,
                    enabled: !saving,
                    decoration: const InputDecoration(
                      labelText: 'OpenRouter API key',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Save keeps this key in this browser after reloads and closing the app, until you replace or clear it. Clear also overrides a key in local configuration. Clearing browser site data removes this preference.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Endpoint: ${widget.state.config.apiBaseUrl}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This development app calls OpenRouter directly. A credential delivered to a browser is accessible to that browser’s user.',
                    style: TextStyle(
                      fontSize: 12,
                      color: StudioPalette.of(context).muted,
                    ),
                  ),
                  if (error ?? widget.state.credentialPreference.error?.message
                      case final String message)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          message,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        onPressed: connectionBusy
                            ? null
                            : () => saveKey(keyInput.text),
                        child: Text(saving ? 'Saving…' : 'Save key'),
                      ),
                      OutlinedButton(
                        onPressed: connectionBusy ? null : () => saveKey(''),
                        child: const Text('Clear saved key'),
                      ),
                    ],
                  ),
                  if (connectionBusy && !saving)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Finish or cancel the current request or conversation operation before changing the key.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 28),
                  const Text(
                    'Reading & connectivity',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  ListenableBuilder(
                    listenable: widget.state.health,
                    builder: (context, _) {
                      final health = widget.state.health;
                      final quota = health.quota;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Free request allowance',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            quota?.summary ??
                                'Not checked. No quota request is made at startup.',
                          ),
                          if (quota != null)
                            Text(
                              'Checked ${timeLabel(quota.checkedAt)}${health.quotaStale ? ' · stale' : ''}${quota.resetAt == null ? '' : '\nReset: ${timeLabel(quota.resetAt)}'}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          const Text(
                            'The counter is advisory; some accounts or routes are exempt. Health probes also use inference requests.',
                            style: TextStyle(fontSize: 12),
                          ),
                          if (health.quotaError != null)
                            Text(
                              health.quotaError!.message,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          TextButton.icon(
                            onPressed:
                                health.quotaLoading ||
                                    !widget.state.online ||
                                    widget.state.configurationLoading
                                ? null
                                : () => health.refreshQuota(force: true),
                            icon: const Icon(Icons.refresh, size: 18),
                            label: Text(
                              health.quotaLoading
                                  ? 'Checking allowance…'
                                  : 'Check allowance',
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final scale in [1.0, 1.25, 1.5, 2.0])
                        ChoiceChip(
                          label: Text('${(scale * 100).round()}% text'),
                          selected: widget.state.textScale == scale,
                          onSelected: (_) {
                            widget.state.setTextScale(scale);
                            setState(() {});
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Work offline'),
                    subtitle: const Text(
                      'Use cached models and drafts. Remote requests are disabled.',
                    ),
                    value: widget.state.workOffline,
                    onChanged: (value) {
                      widget.state.setOffline(value);
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Install & updates',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Install from your browser’s app menu when available. Offline launch needs one successful release load over HTTPS or localhost.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (widget.state.platform.installAvailable)
                        OutlinedButton.icon(
                          onPressed: widget.state.platform.install,
                          icon: const Icon(Icons.install_desktop),
                          label: const Text('Install app'),
                        ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await widget.state.platform.checkForUpdate();
                          if (mounted) setState(() {});
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Check for update'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final snapshot = await widget.state.platform
                              .inspectPwa();
                          final report = const JsonEncoder.withIndent(
                            '  ',
                          ).convert(snapshot);
                          widget.state.diagnostics.record(
                            'PWA inspection',
                            note:
                                'Offline cache inspection completed. Full metadata is available in the inspection report’s Copy and Export actions.',
                            details: report,
                          );
                          if (!context.mounted) return;
                          await showSelectableDialog<void>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Offline cache & startup'),
                              content: SingleChildScrollView(
                                child: SelectableText(
                                  report,
                                  semanticsLabel: report,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      widget.state.platform.exportText(
                                        'wfform-pwa-inspection.json',
                                        report,
                                      ),
                                  child: const Text('Export'),
                                ),
                                TextButton(
                                  onPressed: () => Clipboard.setData(
                                    ClipboardData(text: report),
                                  ),
                                  child: const Text('Copy'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Close'),
                                ),
                              ],
                            ),
                          );
                        },
                        icon: const Icon(Icons.offline_pin_outlined),
                        label: const Text('Inspect offline cache'),
                      ),
                      if (widget.state.platform.updateAvailable)
                        FilledButton(
                          onPressed: widget.state.chat.busy
                              ? null
                              : widget.state.applyUpdate,
                          child: const Text('Save draft & update'),
                        ),
                    ],
                  ),
                  if (widget.state.platform.pwaError != null)
                    Text(widget.state.platform.pwaError!),
                  const SizedBox(height: 24),
                  PaperPanel(
                    color: StudioPalette.of(context).cream,
                    child: Text(
                      'First response: ${widget.state.config.firstResponseTimeout.inSeconds}s\nStream idle: ${widget.state.config.streamIdleTimeout.inSeconds}s\nOverall stream: ${widget.state.config.streamOverallTimeout.inSeconds}s\nCatalog request: ${widget.state.config.requestTimeout.inSeconds}s\nProbe timeout: ${widget.state.config.probeTimeout.inSeconds}s\nHealth freshness: ${widget.state.config.healthTtl.inSeconds}s\nProvider metadata freshness: ${widget.state.config.endpointTtl.inSeconds}s\nCooldown: ${widget.state.config.cooldown.inSeconds}s\nAutomatic content retries: 0\n\nPolicy settings are centralized in config/local.json. Reload to apply them.',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
