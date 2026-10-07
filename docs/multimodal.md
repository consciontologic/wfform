# Local attachments and multimodal input

wfform accepts local attachments when the selected model advertises the corresponding input capability and meets the app's free-routing checks. UTF-8 text/source files use the model's text capability and are submitted as named text content; they do not require native file input. Answers remain text and render through the [Markdown/source reader](file-rendering.md). The catalog describes possible input; it does not guarantee that the next provider accepts a particular file, duration, resolution or context size.

## Supported subset

| Input | Formats accepted by this app | Request representation |
| --- | --- | --- |
| Text/source | UTF-8 Markdown, code, configuration and plain text, up to 256 KiB | Named `text` content; see [format coverage](file-rendering.md) |
| Images | PNG, JPEG, WebP, GIF | `image_url` with a base64 data URL |
| Audio | WAV, MP3 | `input_audio` with raw base64 and `wav` or `mp3` format |
| Video | MP4 | `video_url` with a base64 data URL |
| Documents | PDF, only for native file input | `file` with filename and base64 data URL |

The media rows are the subset implemented and signature-checked by the app. Other media formats documented by OpenRouter are not advertised in the picker. A missing browser MIME type can use a recognized media filename extension. Conflicting recognized media types are rejected; unknown MIME types and recognized source extensions are candidates for strict text validation, including TypeScript files reported as `video/mp2t`. Common JPEG/WAV/MP3 MIME aliases are normalized. The domain checks media signatures before base64 encoding. Signature checks catch obvious type mismatches; they are not complete media decoders, and providers can reject a damaged or unsupported file. Text candidates must pass strict UTF-8 decoding and control-character rejection; the [rendering guide](file-rendering.md) describes MIME/extension fallback and source previews.

The shared limits are **4 files per message**, **8 MiB per file**, and **12 MiB total per message**, including existing draft attachments. Text/source files have the smaller **256 KiB** limit. Empty files are rejected. These local limits apply again to restored sessions and explicit retries. Sent attachment data is bounded to **24 MiB of base64 characters per conversation**. Base64 adds approximately one third to payload size; the full conversation record limit remains 32 MiB, so a long media conversation can reach its limit earlier. Files are not silently dropped to fit.

## Free routing and capability changes

Each request retains the exact selected model, disables provider fallbacks, and sends zero maximum prices for prompt, completion, request, image and audio. The catalog adapter validates applicable reported prices and overrides; missing optional prices remain unknown, rather than being converted to zero. Image/audio routes must satisfy the corresponding documented server-side maximum price. Video additionally requires a validated catalog `:free` variant because no separate video maximum-price field is documented. The app never appends that suffix to create an unlisted route.

PDF selection requires the catalog's native `file` input capability. A request containing any retained PDF turn explicitly selects `file-parser` with `pdf.engine: native`. That engine is charged through model input tokens, subject to the zero input-price guard. The default parser's paid OCR fallback is never selected. The public catalog observed during this implementation had no eligible native-file model; this observation is not a fixed catalog rule or a promise of future availability.

Retained user attachments are included in subsequent conversation context and explicit retries. **Context** lets the user explicitly choose a later starting turn for future requests; earlier messages and files remain in history but are no longer submitted. Files are never automatically discarded to fit a request. Capability and price checks apply to the included attachments before sending them, including when catalog data changes after selection. A provider error preserves the conversation and files for inspection or deliberate retry. No attachment probe is broadcast to the catalog; selected-model health probes remain small text requests and therefore do not establish media-specific responsiveness.

## Context, generation and responsiveness

The composer displays an input-token estimate and output reserve. Text uses a local heuristic; media adds a planning allowance, not an exact provider token count. Image resolution, audio duration, video frames and PDF decoding can change actual usage. Exceeding the advertised context limit according to the estimate blocks submission and leaves the draft/files intact. An estimate that fits does not guarantee provider acceptance. The Context dialog can exclude older turns explicitly and set a per-conversation response-token limit; the default reserve is 2048 tokens, reduced for smaller context windows and reported provider limits. `max_tokens` is sent only when advertised as supported, and response tokens can include model reasoning.

When the provider completes with `finish_reason: length`, **Continue answer** sends a new explicit continuation turn. It retains the earlier answer, follows the selected context range and leaves any separately composed draft untouched. It is not an automatic retry or a guarantee of seamless continuation.

Text/reasoning deltas are accumulated and published in short batches rather than rebuilding for every SSE event. Separate first-useful-output (90 seconds), useful-output idle (45 seconds) and absolute stream (300 seconds) defaults replace the ordinary request deadline for chat. Useful reasoning counts as progress; heartbeat comments and metadata do not indefinitely keep a stalled request alive. A timeout identifies its phase and retains received output and attached user turns. These policies can be configured through the keys in the [configuration reference](guides/README.md#configuration). They do not shorten a provider's actual media-processing time.

## Browser and persistence boundaries

`lib/shared/attachment_picker.dart` defines the small injectable picker contract; `attachment_picker_web.dart` owns the browser file dialog and reader. It uses the existing Dart `package:web` dependency. The platform adapter checks metadata for the entire chosen selection before reading bytes, reads files sequentially as ArrayBuffers, and bounds each read to 30 seconds. It does not read data URLs, create base64, upload files, or render their contents. The chat domain owns encoding and API mapping.

The native file dialog opens directly from the Attach action. Cancelling the dialog returns no additions. Explicit cancellation or disposal aborts pending reads and releases listeners and temporary input elements. Errors are actionable and contain no file payload. The browser adapter relies on the standard file-input `cancel` event, supported in current major browsers since 2023; legacy browsers without that event have not been validated. A non-web adapter reports that selection is unavailable until a native picker is implemented.

Sent and draft attachments use immutable binary rows in browser-local IndexedDB, with references in normalized conversation metadata and individual messages. Reusing one attachment in an edited turn or draft within the same conversation does not create another stored payload. Stream checkpoints write the changed response and small metadata instead of the entire base64-bearing history. The repository keeps one decoded checkpoint, and opening the history list loads summaries rather than every conversation's media. Older version-1 records migrate on a successful atomic checkpoint; a failed migration retains the original record.

Attachment payloads are excluded from localStorage/sessionStorage recovery markers, diagnostics, and the PWA service-worker cache. Immediate text draft recovery and the active-conversation ID are tab-local sessionStorage values. The save badge shows whether a durable checkpoint is pending, saving, saved or failed. Conflicting writes in different tabs preserve a separate recovered conversation instead of overwriting the other version; both retain their files. Explicit deletion removes the corresponding message and media rows. Export includes attachment data in the versioned JSON backup, and import creates a separate copy.

Selecting a file does not send it to OpenRouter; sending a message sends its files and included context through the direct authenticated API request. Browser storage is not a cloud backup. Clearing site data or browser storage eviction can remove files with their conversations; see [history.md](history.md).

## Official sources checked on 2026-10-06

- [OpenRouter multimodal overview](https://openrouter.ai/docs/guides/overview/multimodal/overview), [images](https://openrouter.ai/docs/guides/overview/multimodal/image-understanding), [audio](https://openrouter.ai/docs/guides/overview/multimodal/audio), and [video](https://openrouter.ai/docs/guides/overview/multimodal/videos) define the content-part representations. The app supports the format subset listed above.
- [OpenRouter PDF inputs](https://openrouter.ai/docs/guides/overview/multimodal/pdfs) documents native processing and the default parser fallback. [Create chat completion](https://openrouter.ai/docs/api/api-reference/chat/create-a-chat-completion) documents provider maximum-price fields, including audio.
- [MDN file input](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/input/file), [file-input cancel event](https://developer.mozilla.org/en-US/docs/Web/API/HTMLInputElement/cancel_event), [FileReader ArrayBuffer reads](https://developer.mozilla.org/en-US/docs/Web/API/FileReader/readAsArrayBuffer), and [FileReader abort event](https://developer.mozilla.org/en-US/docs/Web/API/FileReader/abort_event) define the browser adapter behavior.

## Verification

The picker has **16 deterministic tests** covering the model/picker format contract, metadata-first rejection, MIME normalization, file/count/total boundaries, existing selections, empty and truncated files, cancellation, immutable results, and the unsupported-platform adapter. These tests use fake file sources and do not exercise an operating-system file dialog or authenticate to OpenRouter.

```sh
flutter test test/shared/attachment_picker_test.dart --reporter expanded
flutter analyze lib/shared/attachment_limits.dart lib/shared/attachment_picker.dart lib/shared/attachment_picker_stub.dart lib/shared/attachment_picker_web.dart test/shared/attachment_picker_test.dart
```

Both commands passed during the attachment implementation. Its integrated suite passed **202 tests with 1 opt-in live test skipped**, clean formatting and clean full analysis; release `hmybhzutdo` built successfully. These are preserved results for that earlier attachment release, not the total test count or build identity of later performance changes.

On that release, an actual browser file dialog selected a PNG, its preview appeared, and the unsent file and prompt survived reload. NVIDIA Nemotron Omni passed a text health probe but failed the actual image request at its provider; the failure stayed visible. After an explicit model switch, the free Google Gemma 4 26B A4B model successfully described the PNG through a direct authenticated streaming request. The composer text and attached files visibly cleared as streaming began.

Browser edit/resend appended a changed question with the original PNG and an edit-origin label, preserving the original conversation and separate composer draft. The real edited request was rate-limited; its failed turn and explicit Retry remained available without automatic resending. Reload restored the four-message conversation, both user attachments, the edit origin and next draft without restarting inference.

Audio/video inference remains unverified live, and no eligible free native-PDF model was observed. These image results do not establish every format or provider. See `outputs/wfform-multimodal-report.md` for separate release measurements and screenshots; earlier text-chat and PWA screenshots are preserved as earlier evidence.

The storage follow-up added six passing real Chromium IndexedDB checks, using generated test databases and fixture media. They cover version-1 migration, binary readback, incremental message writes, deletion, conflict recovery, `BroadcastChannel`, transaction rollback, completed snapshot reads with suppressed completion-event delivery, and pending-read aborts. They do not make OpenRouter requests or establish audio/video acceptance:

```sh
CHROME_EXECUTABLE=/path/to/chrome flutter test --platform chrome \
  test/history/browser/indexeddb_checks.dart --reporter expanded
```

The opt-in benchmark below uses two synthetic PNG files, each 6 MiB, whose image content is validated by Flutter's decoder before timing. It compares the legacy whole-record encoder with normalized preparation over ten response checkpoints and writes `outputs/history-performance.json`. The observed VM medians were 105.5665 ms and 2.0725 ms respectively; modeled checkpoint payloads were 167,784,700 and 11,462 bytes after the initial 12,582,912 attachment bytes were stored. These are synthetic Dart VM preparation measurements and modeled write sizes; they do not measure browser rendering, actual IndexedDB latency, provider latency or every device's performance.

```sh
flutter test tool/history_benchmark.dart --reporter expanded
```
