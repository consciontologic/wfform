# Files and multimodal input

Select files locally; only Send uploads them through the direct OpenRouter request.
The chosen model must advertise the input and satisfy its applicable free-price guards.
Advertised support and successful text health do not guarantee media acceptance.

| Input | Accepted formats | OpenRouter content |
|---|---|---|
| Text/source | Strict UTF-8, up to 256 KiB | Named `text` part |
| Image | PNG, JPEG, WebP, GIF | `image_url`, base64 data URL |
| Audio | WAV, MP3 | `input_audio`, raw base64 and format |
| Video | MP4 | `video_url`, base64 data URL |
| Native document | PDF | `file`, filename and base64 data URL |

Limits: **four files**, **8 MiB each**, **12 MiB total** per message; text has the
smaller 256 KiB limit. Empty files fail. Validate metadata before sequential bounded
reads, then bytes/signatures at the domain boundary and again on restore/retry.
MIME aliases are normalized; conflicting recognized media types fail. Signature
checks catch mismatches, not every damaged file. Text rejects invalid UTF-8/NUL/control
content and supports unknown/extensionless source; see [rendering](file-rendering.md).

Every request keeps the selected model, disables fallback and caps prompt, completion,
request, image and audio prices at zero. Video additionally requires a validated
catalog `:free` variant because no separate video price cap is documented; never
invent a suffixed ID. Native PDF requires advertised `file` input and explicit
`file-parser` with `pdf.engine: native`, preventing paid OCR fallback.

Retained files in included context are revalidated if capabilities/pricing change.
Context exclusion is explicit; files are never silently dropped to fit. Media token
estimates are approximate and provider resolution/duration/page limits still apply.
Provider errors preserve files and partial output for inspection or deliberate retry.

Files persist as immutable binary IndexedDB rows referenced from drafts/messages and
are included in exports. They never enter diagnostics, tab-local text recovery or
service-worker caches. Cancel/dispose aborts pending reads and releases listeners.
The native picker remains unimplemented; browser success does not establish native
platform support.

Run `flutter test test/shared/attachment_picker_test.dart` and relevant chat/history
tests. Actual image/audio/video/PDF provider acceptance must be verified separately
with an explicit key and bounded request.
Sources: [OpenRouter multimodal](https://openrouter.ai/docs/guides/overview/multimodal/overview),
[PDF processing](https://openrouter.ai/docs/guides/overview/multimodal/pdfs).
