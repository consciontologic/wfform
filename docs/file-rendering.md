# Text files and rendered responses

wfform renders assistant responses and local text attachments using Flutter widgets. Assistant replies support GitHub-flavored Markdown: headings, emphasis, lists, tables, block quotes, inline code and fenced code. A **Source** toggle preserves access to the original Markdown; **Copy source** copies the full response, and **Copy code** copies the contents of a code block. Reasoning remains a separate collapsible plain-text area. User prompts remain literal text.

Select **Add files** with a text-compatible free model, choose a UTF-8 file, then tap its filename chip to preview it. The dialog shows its original filename (including extension), detected format and size. Markdown files have rendered/source modes; code and configuration files show source with named syntax highlighting. Unknown extensions and extensionless UTF-8 files remain usable as plain text. Filename detection controls presentation, not content execution or API modality.

## Formats

The registry in `lib/features/documents/document_format.dart` recognizes:

- Markdown (`md`, `markdown`, `mdown`), text/log/CSV/TSV, reStructuredText.
- JSON/JSON Lines, YAML, TOML, INI/configuration, SQL, GraphQL, Protocol Buffers.
- JavaScript/JSX, TypeScript/TSX, C/C++/headers, C#, Dart, Python, Java, Kotlin, Swift, Go, Rust, Ruby, PHP, Lua and R.
- Shell/Bash/Zsh, PowerShell, HTML/XML/SVG source, CSS/SCSS, LaTeX source, diff/patch.
- `Dockerfile` (including suffixed names), `Makefile`/`GNUmakefile`, `.env` variants, `.gitignore`, `.dockerignore`, `README` and `LICENSE`.

The syntax highlighter registers 30 named grammars explicitly. Fence aliases such as `js`, `py`, `c`, `yml` and `sh` map to their grammar. Unknown or unsupported fence languages retain their label and display unchanged plain source. There is no expensive language auto-detection. Syntax colors do not constitute code validation.

## Validation, requests and history

Text/source files must be nonempty, strictly valid UTF-8 and at most **256 KiB each**. Binary/NUL and unsupported control data are rejected. Existing limits still apply: four attachments per message, 12 MiB total, and 8 MiB per supported media attachment. Metadata is checked before browser file reads; bytes are checked again at the domain boundary. The browser chooser permits arbitrary extensions because valid source files often lack a browser MIME type. The app validates its returned files rather than treating the chooser as validation.

Text content is sent using OpenRouter's ordinary `{ "type": "text", "text": "..." }` message part, preceded by the original filename and format. It does not require native file-input capability or a PDF parser plugin. Its full content counts toward the local context estimate, which remains an estimate rather than an exact provider tokenizer. Decoded source and its estimate are cached on the immutable attachment. Text support requires text-compatible output and the existing free-price checks and zero-price provider routing limits. Media support and its stricter per-modality pricing checks are unchanged.

Text attachments share the existing attachment ID, history/export format and normalized IndexedDB binary store. Each immutable file is stored once, with message/draft references. Existing media records remain readable. Source attachments persist through draft recovery, reload, editing/resending and export/import. No server or additional upload service was added.

## Rendering limits and boundaries

- Rich Markdown rendering is limited to 24,000 UTF-16 code units. Larger documents automatically use paged source; a page contains approximately 12,000 code units, preserving surrogate pairs.
- Syntax highlighting is limited to 12,000 code units per code block; longer blocks retain plain source. Full-source/code copying never copies just a truncated preview.
- Streaming Markdown previews update at most once per 180 ms; completion or failure flushes the final content immediately. Timers are cancelled on disposal. Persisted model output is never truncated by rendering limits.
- Images embedded in Markdown appear as selectable alt text and an address. They are not fetched. Links open a copyable address dialog; this version does not navigate to them. HTML, SVG, scripts and LaTeX source are never executed. There is no WebView, HTML injection, diagram execution, shell or code runner.
- Code uses bundled Roboto Mono (SIL Open Font License, supplied beside the font). The app does not promise offline glyph coverage for every language; Flutter may request fallback fonts for unbundled Unicode glyphs.

## Dependencies and verification

Package/API documentation was checked on **2026-10-06**: [flutter_markdown_plus 1.0.12](https://pub.dev/packages/flutter_markdown_plus), [MarkdownBody](https://pub.dev/documentation/flutter_markdown_plus/latest/flutter_markdown_plus/MarkdownBody-class.html), [markdown](https://pub.dev/packages/markdown), [highlight 0.7.0](https://pub.dev/packages/highlight), and [Google Fonts Roboto Mono](https://github.com/google/fonts/tree/main/ofl/robotomono). The Markdown dependency supplies its AST for custom fenced-code widgets. Highlight produces Dart spans, not rendered HTML. These packages replace a custom Markdown parser rather than introducing another application stack.

Deterministic tests are in `test/documents/` and `test/presentation/document_rendering_test.dart`. They cover format/MIME handling, binary/UTF-8/size rejection, unchanged free-price guards, context estimation, mocked request payloads, history round trips, edit/resend, exact clipboard contents, named highlighting/source fallback, streaming lifecycle, and a 320-pixel preview at 200% text scaling. Live API sends are not part of these tests.

```sh
pwd
xops/agent/safe-run.sh file-rendering -- flutter test test/documents test/presentation/document_rendering_test.dart
```

For release-browser verification, import a synthetic conversation containing Markdown and fenced code, verify preview/source/copy actions at compact, medium and expanded widths, attach a local Markdown/JSON/source file, reload and reopen its preview, and check that network inspection shows no request for embedded Markdown images. Keep live sending opt-in. Browser/release observations are recorded separately from deterministic widget results.
