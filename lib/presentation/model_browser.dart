import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'selectable_surface.dart';
import 'brand_mark.dart';
import '../app/studio_state.dart';
import '../app/theme.dart';
import '../features/models/model.dart';
import '../features/models/health.dart';
import '../shared/diagnostics.dart';

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

/// A colored, readable identity for each popup; its artwork is decorative while
/// the heading and close button retain stable screen-reader names.
class StudioDialogHeader extends StatelessWidget {
  const StudioDialogHeader({
    super.key,
    required this.title,
    this.emoji,
    this.glyph,
    required this.color,
    required this.closeTooltip,
    required this.onClose,
  }) : assert((emoji == null) != (glyph == null));
  final String title, closeTooltip;
  final String? emoji;
  final BrandGlyph? glyph;
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
                decoration: glyph == null
                    ? BoxDecoration(
                        color: palette.surface,
                        border: Border.all(color: palette.border),
                        borderRadius: BorderRadius.circular(10),
                      )
                    : null,
                child: glyph != null
                    ? BrandIcon(glyph!, size: compact ? 28 : 34)
                    : _emojiAssets.containsKey(emoji)
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
                glyph: BrandGlyph.models,
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
            glyph: BrandGlyph.models,
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

/// Rounded overview only; the exact context remains in Provider & context.
String modelContextLabel(int? tokens) {
  if (tokens == null) return 'Not reported';
  for (final unit in [(1000000000, 'B'), (1000000, 'M'), (1000, 'K')]) {
    if (tokens >= unit.$1) {
      final count = tokens / unit.$1;
      final number = count
          .toStringAsFixed(count < 10 ? 1 : 0)
          .replaceFirst(RegExp(r'\.0$'), '');
      return '$number${unit.$2} tokens';
    }
  }
  return '$tokens tokens';
}

/// A literal excerpt, never a generated summary. Full API text stays available.
String modelDescriptionPreview(String description) {
  final source = description.trim();
  const limit = 180;
  final firstEnd = RegExp(r'[.!?](?:\s+|$)|[。！？]').firstMatch(source);
  var candidate = firstEnd == null
      ? source
      : source.substring(0, firstEnd.end).trimRight();
  if (candidate.runes.length <= limit) return candidate;
  candidate = String.fromCharCodes(candidate.runes.take(limit));
  final boundary = candidate.lastIndexOf(RegExp(r'\s'));
  if (boundary >= candidate.length ~/ 2) {
    candidate = candidate.substring(0, boundary);
  }
  return candidate.trimRight();
}

class ModelDetails extends StatelessWidget {
  const ModelDetails({super.key, required this.state, required this.model});
  final StudioState state;
  final FreeModel model;

  @override
  Widget build(BuildContext context) => SelectionArea(
    child: ListenableBuilder(
      listenable: state.health,
      builder: (context, _) {
        final observation = state.health.forModel(model.id);
        final palette = StudioPalette.of(context);
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
            const SizedBox(height: 12),
            SelectableText(
              model.name,
              semanticsLabel: model.name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            SelectableText(
              model.id,
              semanticsLabel: model.id,
              style: TextStyle(fontSize: 12, color: palette.muted),
            ),
            const SizedBox(height: 14),
            _ModelDescription(
              key: ValueKey(model.id),
              state: state,
              model: model,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final input in model.inputModalities)
                  _ModalityChip(label: '${_modalityLabel(input)} input'),
                for (final output in model.outputModalities)
                  _ModalityChip(label: '${_modalityLabel(output)} output'),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Context window',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            Text(
              modelContextLabel(model.contextLength),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (!model.chatCompatible) ...[
              const SizedBox(height: 8),
              Text(model.incompatibilityReason ?? 'Unavailable for text chat.'),
            ],
            const SizedBox(height: 14),
            PaperPanel(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              color: observation.status == HealthStatus.responsive
                  ? palette.sage
                  : observation.status == HealthStatus.degraded ||
                        observation.status == HealthStatus.unavailable
                  ? palette.peach
                  : palette.lilac,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          healthLabel(observation.status),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          observation.checkedAt == null
                              ? 'Not checked yet'
                              : 'Checked ${timeLabel(observation.checkedAt)}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        if (observation.retryAt != null)
                          Text(
                            'Retry after ${timeLabel(observation.retryAt)}',
                            style: const TextStyle(fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                  SelectableIconButton(
                    tooltip: 'Recheck availability',
                    onPressed:
                        !state.online ||
                            !model.chatCompatible ||
                            observation.status == HealthStatus.checking
                        ? null
                        : () => state.health.check(model, force: true),
                    icon: const Icon(Icons.sync, size: 20),
                  ),
                ],
              ),
            ),
            _section('Availability details', [
              Text(observation.message),
              const SizedBox(height: 8),
              const Text(
                'A recent response is not a guarantee. Catalog presence alone does not verify availability.',
                style: TextStyle(fontSize: 12),
              ),
              for (final entry
                  in state.health.modalityObservations(model.id).entries)
                _Detail(
                  label: entry.key,
                  value:
                      '${entry.value.message}\n${timeLabel(entry.value.checkedAt)}',
                ),
            ]),
            _section('Pricing', [
              _Detail(
                label: 'USD per native unit',
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
              if (model.pricingOverrides.isNotEmpty)
                _Detail(
                  label: 'Conditional prices',
                  value: model.pricingOverrides
                      .map(
                        (override) => override.entries
                            .map((e) => '${e.key}: ${e.value}')
                            .join(', '),
                      )
                      .join('\n'),
                ),
              const Text(
                'Zero-price routing only; no paid fallback.',
                style: TextStyle(fontSize: 12),
              ),
            ]),
            _section('Parameters', [
              _Detail(
                label: 'Supported controls',
                value: model.supportedParameters.join(', '),
              ),
            ]),
            _section('Files', [
              _Detail(
                label: 'Uploads in wfform',
                value: model.attachmentSummary,
              ),
              _Detail(label: 'Formats & limits', value: model.attachmentNotice),
              _Detail(
                label: 'API input → output',
                value:
                    '${model.inputModalities.join(', ')} → ${model.outputModalities.join(', ')}',
              ),
            ]),
            _section('Provider & context', [
              _Detail(
                label: 'Exact context window',
                value: model.contextLength == null
                    ? 'Not reported'
                    : '${model.contextLength} tokens',
              ),
              if (model.architectureTokenizer != null)
                _Detail(
                  label: 'Tokenizer',
                  value: model.architectureTokenizer!,
                ),
              _Detail(
                label: 'Top provider',
                value: model.topProvider.entries
                    .map((e) => '${e.key}: ${e.value}')
                    .join('\n'),
              ),
              if (observation.provider != null)
                _Detail(
                  label: 'Observed provider',
                  value: observation.provider!,
                ),
              if (observation.endpointSummary?.isNotEmpty ?? false)
                _Detail(
                  label: 'Endpoints',
                  value: observation.endpointSummary!,
                ),
            ]),
          ],
        );
      },
    ),
  );

  Widget _section(String title, List<Widget> children) => ExpansionTile(
    key: PageStorageKey('${model.id}:$title'),
    tilePadding: EdgeInsets.zero,
    childrenPadding: const EdgeInsets.only(top: 8, bottom: 12),
    expandedCrossAxisAlignment: CrossAxisAlignment.start,
    title: Text(
      title,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
    children: children,
  );
}

String _modalityLabel(String value) => switch (value) {
  'text' => 'Text',
  'image' => 'Image',
  'audio' => 'Audio',
  'video' => 'Video',
  'file' => 'File',
  'embeddings' => 'Embedding',
  _ => value,
};

class _ModalityChip extends StatelessWidget {
  const _ModalityChip({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: StudioPalette.of(context).paper,
      border: Border.all(color: StudioPalette.of(context).border),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(label, style: const TextStyle(fontSize: 11)),
  );
}

class _ModelDescription extends StatefulWidget {
  const _ModelDescription({
    super.key,
    required this.state,
    required this.model,
  });
  final StudioState state;
  final FreeModel model;
  @override
  State<_ModelDescription> createState() => _ModelDescriptionState();
}

class _ModelDescriptionState extends State<_ModelDescription> {
  bool expanded = false;

  void _openPage(Uri uri) {
    try {
      widget.state.platform.openUrl(uri);
    } catch (_) {
      widget.state.diagnostics.record(
        'model.link.open',
        failure: const AppFailure(
          FailureKind.configuration,
          'The model page could not be opened. Copy its link and open it in a browser.',
        ),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open the model page. Use Copy model page link.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final description = widget.model.description;
    final preview = modelDescriptionPreview(description);
    final modelPage = Uri.https('openrouter.ai', '/${widget.model.id}');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          description.isEmpty
              ? 'No description supplied.'
              : expanded
              ? description
              : preview,
        ),
        if (preview != description.trim())
          TextButton(
            onPressed: () => setState(() => expanded = !expanded),
            child: Text(expanded ? 'Show less' : 'Show full description'),
          ),
        if (description.trimRight().endsWith('...') ||
            description.trimRight().endsWith('…'))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Ellipsis supplied by OpenRouter.',
              style: TextStyle(
                fontSize: 11,
                color: StudioPalette.of(context).muted,
              ),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Semantics(
                  link: true,
                  hint: 'Opens in a new tab',
                  child: TextButton.icon(
                    onPressed: () => _openPage(modelPage),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text(
                      'Model page',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ),
            ),
            SelectableIconButton(
              tooltip: 'Copy model page link',
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: '$modelPage')),
              icon: const Icon(Icons.copy_outlined, size: 18),
            ),
          ],
        ),
      ],
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
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
        // The surrounding SelectionArea handles copying across fields. Keeping
        // this as text also avoids sharing a scroll-position PageStorage entry
        // with the enclosing ExpansionTile's boolean expansion state.
        Text(value.isEmpty ? 'Not reported' : value),
      ],
    ),
  );
}
