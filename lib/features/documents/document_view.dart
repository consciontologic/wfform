import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../../presentation/selectable_surface.dart';
import 'code_highlighter.dart';
import 'document_format.dart';

const maxRichDocumentCharacters = 24000;
const sourcePageCharacters = 12000;

/// A bounded Flutter-only renderer shared by replies and local UTF-8 files.
/// Streaming updates are coalesced; full source copying never uses the preview.
class DocumentView extends StatefulWidget {
  const DocumentView({
    super.key,
    required this.source,
    this.format = const DocumentFormat('Markdown', 'markdown', markdown: true),
    this.streaming = false,
  });
  final String source;
  final DocumentFormat format;
  final bool streaming;

  @override
  State<DocumentView> createState() => _DocumentViewState();
}

class _DocumentViewState extends State<DocumentView> {
  late String _displayed = widget.source;
  bool _sourceMode = false;
  int _page = 0;
  Timer? _pending;
  late MarkdownStyleSheet _markdownStyle;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _markdownStyle = MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: const TextStyle(fontSize: 16, height: 1.6),
      code: const TextStyle(fontFamily: 'RobotoMono', fontSize: 13),
    );
  }

  @override
  void didUpdateWidget(DocumentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.streaming) {
      _pending?.cancel();
      _pending = null;
      _displayed = widget.source;
    } else if (widget.source != _displayed && _pending == null) {
      _pending = Timer(const Duration(milliseconds: 180), () {
        _pending = null;
        if (mounted) setState(() => _displayed = widget.source);
      });
    }
  }

  @override
  void dispose() {
    _pending?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final large = _displayed.length > maxRichDocumentCharacters;
    final raw = _sourceMode || large || !widget.format.markdown;
    final pages = math.max(
      1,
      (_displayed.length / sourcePageCharacters).ceil(),
    );
    final page = math.min(_page, pages - 1);
    var start = page * sourcePageCharacters;
    var end = math.min(_displayed.length, start + sourcePageCharacters);
    // Never split a surrogate pair at a source page boundary.
    if (start > 0 && _isLowSurrogate(_displayed.codeUnitAt(start))) start--;
    if (end < _displayed.length &&
        _isLowSurrogate(_displayed.codeUnitAt(end))) {
      end--;
    }
    final sourcePage = _displayed.substring(start, end);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            if (large)
              const Text(
                'Large document · paged source view',
                style: TextStyle(fontSize: 12),
              ),
            if (widget.format.markdown && !large)
              TextButton(
                onPressed: () => setState(() {
                  _sourceMode = !_sourceMode;
                  _page = 0;
                }),
                child: Text(_sourceMode ? 'Preview' : 'Source'),
              ),
            SelectableIconButton(
              tooltip: 'Copy source',
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: widget.source)),
              icon: const Icon(Icons.copy_all_outlined, size: 18),
            ),
          ],
        ),
        if (raw) ...[
          CodeBlock(
            source: sourcePage,
            language: widget.format.language,
            copySource: widget.source,
          ),
          if (pages > 1)
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton(
                  onPressed: page == 0
                      ? null
                      : () => setState(() => _page = page - 1),
                  child: const Text('Previous page'),
                ),
                Text('Page ${page + 1} of $pages'),
                TextButton(
                  onPressed: page + 1 == pages
                      ? null
                      : () => setState(() => _page = page + 1),
                  child: const Text('Next page'),
                ),
              ],
            ),
        ] else
          SelectionArea(
            child: MarkdownBody(
              data: _displayed,
              // Text.rich exposes readable semantics labels; the local area
              // supplies cross-paragraph selection without editable text fields.
              selectable: false,
              extensionSet: md.ExtensionSet.gitHubFlavored,
              fitContent: false,
              styleSheet: _markdownStyle,
              builders: {'pre': _CodeBuilder()},
              // Never fetch remote image URLs or interpret local/HTML resources.
              imageBuilder: (uri, title, alt) =>
                  SelectableText('Image: ${alt ?? title ?? ''}\n$uri'),
              onTapLink: (text, href, title) {
                if (href == null) return;
                showSelectableDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Link address'),
                    content: SingleChildScrollView(child: SelectableText(href)),
                    actions: [
                      TextButton(
                        onPressed: () =>
                            Clipboard.setData(ClipboardData(text: href)),
                        child: const Text('Copy link'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

bool _isLowSurrogate(int value) => value >= 0xdc00 && value <= 0xdfff;

class _CodeBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => true;
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final code = element.children?.whereType<md.Element>().firstOrNull;
    final language =
        code?.attributes['class']?.replaceFirst('language-', '') ?? 'text';
    return CodeBlock(source: element.textContent, language: language);
  }
}

class CodeBlock extends StatefulWidget {
  const CodeBlock({
    super.key,
    required this.source,
    required this.language,
    this.copySource,
  });
  final String source, language;
  final String? copySource;

  @override
  State<CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<CodeBlock> {
  TextSpan? _highlighted;
  Brightness? _brightness;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    if (brightness != _brightness) {
      _brightness = brightness;
      _highlighted = null;
    }
  }

  @override
  void didUpdateWidget(CodeBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.source != oldWidget.source ||
        widget.language != oldWidget.language) {
      _highlighted = null;
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 6),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      border: Border.all(color: Theme.of(context).colorScheme.outline),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.language.isEmpty ? 'text' : widget.language,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            SelectableIconButton(
              tooltip: 'Copy code',
              onPressed: () => Clipboard.setData(
                ClipboardData(text: widget.copySource ?? widget.source),
              ),
              icon: const Icon(Icons.copy, size: 18),
            ),
          ],
        ),
        SelectableText.rich(
          // A stream may rebuild this block between coalesced preview updates.
          // Keep one span tree per mounted block, invalidated only when its
          // source, grammar or palette changes. Copy still uses the latest input.
          _highlighted ??= highlightedSource(
            widget.source,
            widget.language,
            _brightness!,
          ),
          style: const TextStyle(
            fontFamily: 'RobotoMono',
            fontSize: 13,
            height: 1.5,
          ),
        ),
      ],
    ),
  );
}
