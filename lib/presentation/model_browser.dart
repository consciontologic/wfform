import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'selectable_surface.dart';
import '../app/studio_state.dart';
import '../app/theme.dart';
import '../features/models/model.dart';
import '../features/models/health.dart';

String timeLabel(DateTime? date) {
  if (date == null) return 'Not checked yet';
  final local = date.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}';
}

String healthLabel(HealthStatus status) => switch (status) {
  HealthStatus.unknown => 'Unknown',
  HealthStatus.checking => 'Checking',
  HealthStatus.responsive => 'Recently responsive',
  HealthStatus.degraded => 'Degraded',
  HealthStatus.unavailable => 'Unavailable',
  HealthStatus.rateLimited => 'Rate-limited',
};

class PaperPanel extends StatelessWidget {
  const PaperPanel({
    super.key,
    required this.child,
    this.color,
    this.padding = const EdgeInsets.all(16),
    this.shadow = false,
  });
  final Widget child;
  final Color? color;
  final EdgeInsets padding;
  final bool shadow;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color ?? StudioPalette.of(context).surface,
      border: Border.all(color: StudioPalette.of(context).border, width: 1.5),
      borderRadius: BorderRadius.circular(6),
      boxShadow: shadow
          ? [
              BoxShadow(
                color: StudioPalette.of(context).shadow,
                offset: const Offset(4, 4),
              ),
            ]
          : [],
    ),
    child: child,
  );
}

/// A colored, readable identity for each popup; its emoji is decorative while
/// the heading and close button retain stable screen-reader names.
class StudioDialogHeader extends StatelessWidget {
  const StudioDialogHeader({
    super.key,
    required this.title,
    required this.emoji,
    required this.color,
    required this.closeTooltip,
    required this.onClose,
  });
  final String title, emoji, closeTooltip;
  final Color color;
  final VoidCallback onClose;

  // Bundled color graphics avoid browser/font-dependent missing emoji glyphs.
  // Twemoji v14.0.2 attribution and CC-BY-4.0 license ship beside these assets.
  static const _emojiAssets = {
    '🧭': 'assets/emoji/1f9ed.png',
    '🔎': 'assets/emoji/1f50e.png',
    '🩺': 'assets/emoji/1fa7a.png',
    '🎨': 'assets/emoji/1f3a8.png',
    '⚙️': 'assets/emoji/2699.png',
    '⚙': 'assets/emoji/2699.png',
    '🗂️': 'assets/emoji/1f5c2.png',
    '🗂': 'assets/emoji/1f5c2.png',
  };

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final compact = box.maxWidth < 380;
      final palette = StudioPalette.of(context);
      return Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(compact ? 12 : 20, 16, 8, 16),
        decoration: BoxDecoration(
          color: color,
          border: Border(bottom: BorderSide(color: palette.border, width: 1.5)),
        ),
        child: Row(
          children: [
            ExcludeSemantics(
              child: Container(
                width: compact ? 36 : 44,
                height: compact ? 36 : 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: palette.surface,
                  border: Border.all(color: palette.border),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: _emojiAssets.containsKey(emoji)
                    ? Image.asset(
                        _emojiAssets[emoji]!,
                        width: compact ? 24 : 30,
                        height: compact ? 24 : 30,
                        filterQuality: FilterQuality.medium,
                        excludeFromSemantics: true,
                      )
                    : Icon(
                        Icons.auto_awesome,
                        color: palette.ink,
                        size: compact ? 24 : 30,
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  style: TextStyle(
                    color: palette.ink,
                    fontSize: compact ? 18 : 22,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
              ),
            ),
            SelectableIconButton(
              tooltip: closeTooltip,
              onPressed: onClose,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      );
    },
  );
}

Future<void> openModels(BuildContext context, StudioState state) =>
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
                title: 'Choose a free model',
                emoji: '🧭',
                color: StudioPalette.of(context).modelChooser,
                closeTooltip: 'Close model browser',
                onClose: () => Navigator.pop(context),
              ),
              Expanded(
                child: ModelBrowser(
                  state: state,
                  onSelected: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );

Future<void> openDetails(
  BuildContext context,
  StudioState state,
  FreeModel model,
) => showSelectableDialog<void>(
  context: context,
  builder: (context) => Dialog(
    clipBehavior: Clip.antiAlias,
    insetPadding: const EdgeInsets.all(12),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StudioDialogHeader(
            title: 'Model details',
            emoji: '🔎',
            color: StudioPalette.of(context).modelDetails,
            closeTooltip: 'Close model details',
            onClose: () => Navigator.pop(context),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ModelDetails(state: state, model: model),
            ),
          ),
        ],
      ),
    ),
  ),
);

class ModelBrowser extends StatefulWidget {
  const ModelBrowser({super.key, required this.state, this.onSelected});
  final StudioState state;
  final VoidCallback? onSelected;
  @override
  State<ModelBrowser> createState() => _ModelBrowserState();
}

class _ModelBrowserState extends State<ModelBrowser> {
  final search = TextEditingController();
  String query = '';
  bool selecting = false;
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.state,
      widget.state.catalog,
      widget.state.chat,
    ]),
    builder: (context, _) {
      final catalog = widget.state.catalog;
      final models = catalog.models
          .where(
            (m) =>
                '${m.name} ${m.id}'.toLowerCase().contains(query.toLowerCase()),
          )
          .toList();
      models.sort((a, b) {
        if (a.chatCompatible != b.chatCompatible) {
          return a.chatCompatible ? -1 : 1;
        }
        return a.name.compareTo(b.name);
      });
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: search,
                    decoration: const InputDecoration(
                      labelText: 'Search free models',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) => setState(() => query = value),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${catalog.models.where((m) => m.chatCompatible).length} chat models · ${catalog.models.length} listings',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      SelectableIconButton(
                        tooltip: 'Refresh catalog',
                        onPressed: catalog.refreshing || !widget.state.online
                            ? null
                            : catalog.refresh,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  Text(
                    !widget.state.online
                        ? 'Offline · cached catalog'
                        : catalog.refreshing
                        ? 'Fetching current catalog…'
                        : catalog.fromCache || catalog.stale
                        ? 'Cached catalog · refresh pending'
                        : 'Live catalog',
                    style: TextStyle(color: StudioPalette.of(context).muted),
                  ),
                  Text(
                    'Refreshed ${timeLabel(catalog.lastSuccess)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: StudioPalette.of(context).muted,
                    ),
                  ),
                  if (catalog.issues.isNotEmpty)
                    Text(
                      '${catalog.issueCount} entries quarantined · see diagnostics',
                      style: const TextStyle(fontSize: 12),
                    ),
                  if (widget.state.chat.busy)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Finish or cancel the current response before choosing another model.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  if (widget.state.conversationNotice != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        widget.state.conversationNotice!,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  if (widget.state.historyError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        widget.state.historyError!.message,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (catalog.refreshing || selecting)
            const SliverToBoxAdapter(
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (catalog.error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(
                  catalog.error!.message,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          if (models.isEmpty)
            SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    catalog.refreshing
                        ? 'Loading models…'
                        : query.isNotEmpty
                        ? 'No models match your search.'
                        : catalog.error != null
                        ? 'Catalog unavailable. Refresh to try again.'
                        : 'No eligible free models are currently listed.',
                  ),
                ),
              ),
            )
          else
            SliverList.builder(
              itemCount: models.length,
              itemBuilder: (context, index) {
                final model = models[index];
                final selected = catalog.selectedId == model.id;
                return _ModelRow(
                  model: model,
                  selected: selected,
                  onDetails: () => openDetails(context, widget.state, model),
                  onSelect:
                      !model.chatCompatible ||
                          selecting ||
                          widget.state.chat.busy ||
                          widget.state.historyBusy ||
                          widget.state.historySaving
                      ? null
                      : () async {
                          setState(() => selecting = true);
                          try {
                            final success = await widget.state.selectModel(
                              model,
                            );
                            if (success && mounted) widget.onSelected?.call();
                          } finally {
                            if (mounted) setState(() => selecting = false);
                          }
                        },
                );
              },
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Zero-price routes only. Availability can change.',
                style: TextStyle(
                  fontSize: 12,
                  color: StudioPalette.of(context).muted,
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _ModelRow extends StatefulWidget {
  const _ModelRow({
    required this.model,
    required this.selected,
    required this.onDetails,
    required this.onSelect,
  });
  final FreeModel model;
  final bool selected;
  final VoidCallback onDetails;
  final VoidCallback? onSelect;
  @override
  State<_ModelRow> createState() => _ModelRowState();
}

class _ModelRowState extends State<_ModelRow> {
  bool focused = false;
  final tooltip = GlobalKey<TooltipState>();
  @override
  Widget build(BuildContext context) {
    final m = widget.model;
    final preview =
        '${m.name}\n${m.id}\n${m.contextLength ?? 'Unknown'} context tokens\n${m.inputModalities.join(', ')} → ${m.outputModalities.join(', ')}\n${m.chatCompatible ? 'Free text chat' : 'Unavailable for text chat'}\nUploads: ${m.attachmentSummary}';
    return SelectableTooltip(
      tooltipKey: tooltip,
      message: preview,
      waitDuration: const Duration(milliseconds: 550),
      child: Focus(
        onFocusChange: (value) {
          setState(() => focused = value);
          if (value) tooltip.currentState?.ensureTooltipVisible();
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: widget.selected
                ? StudioPalette.of(context).sage
                : Colors.transparent,
            border: Border.all(
              color: focused || widget.selected
                  ? StudioPalette.of(context).border
                  : Colors.transparent,
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextButton(
                  onPressed: widget.onSelect,
                  style: TextButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.all(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        m.id,
                        style: const TextStyle(fontSize: 11, height: 1.4),
                      ),
                      if (m.chatCompatible)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            m.attachmentSummary,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      if (!m.chatCompatible)
                        const Text(
                          'Inspect only · incompatible',
                          style: TextStyle(fontSize: 12),
                        ),
                      if (widget.selected)
                        const Text(
                          'Selected',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SelectableIconButton(
                tooltip: 'Model details: ${m.name}',
                onPressed: widget.onDetails,
                icon: const Icon(Icons.info_outline, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ModelDetails extends StatelessWidget {
  const ModelDetails({super.key, required this.state, required this.model});
  final StudioState state;
  final FreeModel model;
  @override
  Widget build(BuildContext context) => SelectionArea(child: _details(context));

  Widget _details(BuildContext context) => ListenableBuilder(
    listenable: state.health,
    builder: (context, _) {
      final observation = state.health.forModel(model.id);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'MODEL PASSPORT',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          SelectableText(
            model.name,
            semanticsLabel: model.name,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          SelectableText(
            model.id,
            semanticsLabel: model.id,
            style: TextStyle(
              fontSize: 13,
              color: StudioPalette.of(context).muted,
            ),
          ),
          const SizedBox(height: 20),
          PaperPanel(
            color: observation.status == HealthStatus.responsive
                ? StudioPalette.of(context).sage
                : observation.status == HealthStatus.degraded ||
                      observation.status == HealthStatus.unavailable
                ? StudioPalette.of(context).peach
                : StudioPalette.of(context).lilac,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  healthLabel(observation.status),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(observation.message),
                Text(
                  'Last check: ${timeLabel(observation.checkedAt)}',
                  style: const TextStyle(fontSize: 12),
                ),
                if (observation.retryAt != null)
                  Text(
                    'Retry after: ${timeLabel(observation.retryAt)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed:
                      !state.online ||
                          !model.chatCompatible ||
                          observation.status == HealthStatus.checking
                      ? null
                      : () => state.health.check(model, force: true),
                  icon: const Icon(Icons.sync, size: 18),
                  label: const Text('Recheck availability'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Catalog presence is not a health check. A recent response does not guarantee the next request.',
            style: TextStyle(
              fontSize: 12,
              color: StudioPalette.of(context).muted,
            ),
          ),
          for (final entry
              in state.health.modalityObservations(model.id).entries)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${entry.key}: ${entry.value.message}\n${timeLabel(entry.value.checkedAt)}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          const SizedBox(height: 24),
          Text(
            model.description.isEmpty
                ? 'No description supplied.'
                : model.description,
          ),
          if (model.description.trimRight().endsWith('...') ||
              model.description.trimRight().endsWith('…')) ...[
            const SizedBox(height: 12),
            Text(
              'This description ends with an ellipsis in OpenRouter’s catalog. '
              'More information may be available on its model page.',
              style: TextStyle(
                fontSize: 12,
                color: StudioPalette.of(context).muted,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SelectableText(
                    Uri.https('openrouter.ai', '/${model.id}').toString(),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                SelectableIconButton(
                  tooltip: 'Copy model page link',
                  onPressed: () => Clipboard.setData(
                    ClipboardData(
                      text: Uri.https(
                        'openrouter.ai',
                        '/${model.id}',
                      ).toString(),
                    ),
                  ),
                  icon: const Icon(Icons.copy_outlined, size: 18),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          _Detail(
            label: 'Context window',
            value: model.contextLength == null
                ? 'Not reported'
                : '${model.contextLength} tokens',
          ),
          _Detail(
            label: 'Input → output',
            value:
                '${model.inputModalities.join(', ')} → ${model.outputModalities.join(', ')}',
          ),
          _Detail(
            label: 'File uploads enabled in wfform',
            value: model.attachmentSummary,
          ),
          _Detail(
            label: 'Attachment formats and limits',
            value: model.attachmentNotice,
          ),
          if (!model.chatCompatible)
            _Detail(
              label: 'Chat compatibility',
              value: model.incompatibilityReason ?? 'Not supported',
            ),
          _Detail(
            label: 'Pricing · USD per native unit',
            value: model.pricing.entries
                .map(
                  (e) =>
                      '${e.key}: ${isUnresolvedPrice(e.value) ? 'Unresolved (reported: ${e.value})' : e.value}',
                )
                .join('\n'),
          ),
          if (!model.pricing.containsKey('request'))
            const _Detail(
              label: 'Request price',
              value:
                  'Not reported. Routing enforces a maximum request price of zero USD.',
            ),
          _Detail(
            label: 'Supported parameters',
            value: model.supportedParameters.isEmpty
                ? 'Not reported'
                : model.supportedParameters.join(', '),
          ),
          _Detail(
            label: 'Top provider metadata',
            value: model.topProvider.isEmpty
                ? 'Not reported'
                : model.topProvider.entries
                      .map((e) => '${e.key}: ${e.value}')
                      .join('\n'),
          ),
          if (observation.provider != null)
            _Detail(label: 'Observed provider', value: observation.provider!),
          if (observation.endpointSummary?.isNotEmpty ?? false)
            _Detail(
              label: 'Endpoint metadata',
              value: observation.endpointSummary!,
            ),
        ],
      );
    },
  );
}

class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            color: StudioPalette.of(context).muted,
          ),
        ),
        const SizedBox(height: 5),
        SelectableText(
          value.isEmpty ? 'Not reported' : value,
          semanticsLabel: value.isEmpty ? 'Not reported' : value,
        ),
      ],
    ),
  );
}
