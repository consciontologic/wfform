# Readable files and responses

Assistant replies render selectable Markdown: headings, lists, tables, quotes and
highlighted code. Source/Raw keeps the original text. User prompts remain literal;
complete JSON objects/arrays can receive a readable preview. Copy shortcuts are kept
for full messages, fenced code, full-file source and complete diagnostic/cache reports.

The same viewer serves tool approvals/results, diagnostics, parameter previews and
file dialogs. JSON/JSON Lines indentation preserves exact number spelling, key order,
duplicate keys and escapes. YAML/source retains comments and indentation with syntax
highlighting. Decoded nested strings show labeled multiline source sections; display
formatting never changes requests, stored messages or exports.

## Files and limits

Add a nonempty strict UTF-8 file up to **256 KiB**, then click its filename to preview.
Known Markdown, source/config, JSON/YAML/TOML, logs, CSV, shell, HTML/XML/SVG and common
extensionless names get appropriate views. Unknown names remain plain text. Named
fence aliases select a registered grammar; there is no expensive language guessing.
The registry is [document_format.dart](../lib/features/documents/document_format.dart).

Text files use named ordinary text message parts, without a PDF parser or native-file
capability. Full source contributes to the context estimate. Shared attachment limits
and normalized history apply; [media](multimodal.md) has separate capability checks.

| Work | Bound/fallback |
|---|---|
| Rich Markdown | 24,000 UTF-16 units, then paged source |
| Syntax block | 12,000 units, then plain source |
| Source page | About 12,000 units, preserving surrogate pairs |
| Structured formatting | 64,000 characters, depth 32, 12 decoded sections |
| Stream previews | At most once per 180 ms; immediate terminal flush |

Malformed/over-budget input falls back to source. Preview limits never truncate saved
output or full copying. Page labels remain accessible and source selectable.

## Safety and fonts

Markdown images show alt text/address without fetching. Links show a copyable address
dialog. HTML, SVG, scripts, LaTeX and generated code are never executed; there is no
WebView or renderer-based code runner. Tool execution uses the separate approved
[tools flow](tools.md).

Roboto Mono supplies code/source text and Roboto supplies the interface/public pages;
retain their files and licenses in [assets/fonts](../assets/fonts/). Arbitrary Unicode
may still require Flutter's remote fallback font and is not guaranteed offline.

Run `flutter test test/documents test/presentation/document_rendering_test.dart`.
Release-browser checks cover source/copy, compact layouts at 200% text, file reload
and no network fetch for embedded images. These checks do not send live inference.
