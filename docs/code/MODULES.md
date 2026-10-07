# Module maintenance guide

This guide identifies change ownership and invariants. Detailed behavior remains in the linked feature documents rather than being duplicated here.

## Application and presentation

[main.dart](../../lib/main.dart) installs diagnostics hooks and starts the UI with defaults while runtime configuration resolves. [StudioState](../../lib/app/studio_state.dart) owns configuration replacement, history navigation, draft recovery and platform transitions. It orchestrates feature controllers; it does not decode SSE or interpret remote model DTOs.

[studio_app.dart](../../lib/presentation/studio_app.dart) chooses compact, medium and expanded arrangements using constraints and text scale. [theme.dart](../../lib/app/theme.dart) supplies System/Light/Dark appearance. Dialogs and content-selection scopes are presentation concerns. Keep the same controllers and focus ownership across breakpoints. Changing a model or navigating history during an active send is explicitly guarded.

Regression areas: [presentation tests](../../test/presentation/), [lifecycle tests](../../test/shared/performance_lifecycle_test.dart) and [history state tests](../../test/history/history_state_test.dart). New file/Markdown rendering is specified in the [rendering guide](../file-rendering.md); provider-upload eligibility remains owned by model/chat adapters.

## Model discovery

[model.dart](../../lib/features/models/model.dart) normalizes a single DTO. Required token prices cannot be absent, malformed or inferred from a suffix. Exact mantissa inspection prevents tiny positive prices from underflowing to free. The observed -1 marker means unresolved pricing; it never becomes zero. Applicable unresolved charges exclude the entry, while unresolved non-text media prices disable that media without disqualifying otherwise free text chat.

[catalog.dart](../../lib/features/models/catalog.dart) fetches the structured catalog, validates pagination, retains valid entries while quarantining malformed ones and preserves the previous valid cache on a bad refresh. It aggregates unresolved-price exclusions into the refresh summary. A meaningful pricing/capability change invalidates an existing selection. Website presentation changes should have no effect on this adapter.

Contract: [catalog policy](../catalog.md). Tests: [catalog_test.dart](../../test/models/catalog_test.dart). Add a deterministic DTO fixture before adapting a genuinely changed API field.

## Health and allowance

[health.dart](../../lib/features/models/health.dart) distinguishes catalog presence from recent responsiveness. It maintains model and modality observations, separately cached endpoint metadata, selected-model probes, deduplicated checks and cooldowns. Only real inference establishes responsiveness. A successful text probe is not evidence that every advertised media input works.

Small cache records are scoped to API/key/policy and model signatures. Provisional empty-key controllers must not overwrite another configuration's durable snapshot. Allowance is fetched on demand, remains advisory and is not polled at startup. Honor longer server Retry-After/reset information rather than shortening it to a local backoff cap.

Contract: [chat and health](../chat.md). Tests: [health tests](../../test/models/health_test.dart), [cache tests](../../test/models/health_cache_test.dart).

## Chat and attachments

[chat_controller.dart](../../lib/features/chat/chat_controller.dart) owns message identity, turn admission, busy/error state, explicit retry/edit/continue, context boundaries and batched content updates. An admission failure must not append a duplicate attempt. A terminal failure must preserve the accepted user turn, any next composer draft and received assistant output.

[chat_api.dart](../../lib/features/chat/chat_api.dart) owns the OpenRouter request/response shape. [sse.dart](../../lib/features/chat/sse.dart) handles incremental UTF-8, line/event boundaries, malformed events, completion and cancellation. [chat_metadata.dart](../../lib/features/chat/chat_metadata.dart) holds usage, timing and approximate context-budget values.

[attachment.dart](../../lib/features/chat/attachment.dart) defines validated text/media and wire representations. [attachment_picker](../../lib/shared/attachment_picker.dart) is a replaceable port; its web implementation owns browser file selection. Broad local preview support does not imply arbitrary binary files are supported by an OpenRouter model.

Contracts: [chat](../chat.md), [multimodal](../multimodal.md), [rendering](../file-rendering.md). Tests: [chat tests](../../test/chat/), [picker tests](../../test/shared/attachment_picker_test.dart), [composer tests](../../test/presentation/composer_test.dart).

## Documents and reply rendering

[document_format.dart](../../lib/features/documents/document_format.dart) maps common extensions and extensionless filenames to display formats and strictly validates bounded UTF-8 content. [code_highlighter.dart](../../lib/features/documents/code_highlighter.dart) maps explicit language labels to syntax spans; it does not guess a language or execute source. [document_view.dart](../../lib/features/documents/document_view.dart) renders Markdown and source, coalesces streaming previews, bounds rich rendering and provides paged source/copy access. Chat attachments retain the original bytes; the request adapter submits text files as named text content with ordinary text-model price guards.

The rendering dependencies are `flutter_markdown_plus`, `markdown` and `highlight`; the bundled Roboto Mono font supports readable offline source views. Markdown links expose a copyable address, images have placeholders, and HTML/code is not executed. This is a reader, not an IDE or arbitrary binary document converter. Exact format and size limits are in the [rendering guide](../file-rendering.md).

## History

[conversation.dart](../../lib/features/history/conversation.dart) defines summaries and versioned records. [history_codec.dart](../../lib/features/history/history_codec.dart) packs small message/document JSON separately from immutable attachment bytes. [history_repository.dart](../../lib/features/history/history_repository.dart) exposes index/read/save/delete/active-selection/change operations and a deterministic memory implementation. [history_repository_web.dart](../../lib/features/history/history_repository_web.dart) implements IndexedDB and optional cross-tab notifications.

All writes wait for transaction commit. A read resolves only after every requested snapshot value is received and validated; it does not wait for a later readonly completion event. Failed or interrupted normalized migration leaves legacy data intact. Conflicting writes preserve a recovered copy instead of silently overwriting. Unsent records are drafts until the chat adapter dispatches user content; entirely blank workspaces do not create history rows. Archive preserves content and makes it read-only when reopened, while the active view moves to a writable draft; permanent deletion is an explicit later action. Avoid checkpoint work that serializes unchanged base64 media.

Contract: [history](../history.md). Tests: [history suite](../../test/history/) and [real Chromium checks](../../test/history/browser/indexeddb_checks.dart).

## Shared adapters and release operations

[transport.dart](../../lib/shared/transport.dart) defines cancellable requests, bounded body reading and phase deadlines. [diagnostics.dart](../../lib/shared/diagnostics.dart) categorizes failures, separates error/activity counts, redacts secrets and bounds technical details. [platform.dart](../../lib/shared/platform.dart) exposes storage, connectivity and PWA/export interfaces; conditional imports choose browser implementations or testing stubs.

[tool/build.dart](../../tool/build.dart) assembles immutable content-addressed releases. [service_worker.js](../../web/service_worker.js) installs only verified shell assets, reuses unchanged bytes and preserves releases needed by open tabs. [tool/serve.dart](../../tool/serve.dart) is the static local host. The [Docker guide](../guides/DOCKER.md) owns nginx/Compose commands and runtime configuration rules. [xops](../../xops/README.md) owns repository automation; it is not linked into the Flutter bundle.

Contracts: [PWA](../pwa.md), [release/performance measurement](../performance.md). Tests: [shared suite](../../test/shared/) and release-browser procedures in those guides.
