# API and local contracts

The hosted wfform website has no application backend. Its external contracts are direct browser connections to OpenRouter and optional compatible MCP servers. The optional wfformcomp local process exposes authenticated MCP and can serve the same static web build. API facts below were checked against official documentation on 2026-10-06; detailed source links and edge cases remain in [catalog](../catalog.md), [chat](../chat.md) and [multimodal](../multimodal.md).

## OpenRouter operations

The configurable base defaults to https://openrouter.ai/api/v1. The runtime key is used for authenticated operations; catalog discovery is public and does not send Authorization.

| Operation | Method/path | Trigger | Contract owner |
|---|---|---|---|
| Discover models | GET /models?output_modalities=all | Launch, explicit refresh, reconnect | CatalogController |
| Endpoint/provider metadata | GET /models/{author}/{slug}/endpoints | Selected-model health validation when metadata is stale | HealthController |
| Small health inference | POST /chat/completions | Selected health is unknown/stale or explicit recheck | HealthController + ChatApi |
| User conversation | POST /chat/completions | Explicit Send, Retry, Edit and resend, Continue | ChatController + ChatApi |
| Key allowance | GET /key | Explicit Check allowance; cached until stale | HealthController |

Catalog pagination is optional upstream; without offset/limit the API currently returns the full list. The client still validates/follows same-origin models-page links if supplied and rejects loops, inconsistent totals or unrelated destinations. Harmless fields are ignored; required IDs/prices and known typed fields are validated. A nonempty wholly invalid response is a failure, not an empty free catalog.

## Chat request policy

The adapter sends the actual selected model ID and relevant conversation messages, with streaming enabled. Provider fallback is disabled and documented prompt/completion/request/image/audio price limits are zero. There is no paid fallback, default substitute model or automatic content resend.

Generation and reasoning parameters are omitted unless explicitly supplied. Supported overrides are validated against model metadata; output token limits respect the known provider cap. The default context reserve is a local estimate, not an implicit remote limit. The user explicitly chooses any earlier context exclusion; estimates never silently delete or summarize saved turns. Native PDF processing is requested explicitly when applicable, preventing an automatic paid parser fallback.

User content may be a string or documented multimodal parts. The media adapter owns image data URLs, audio data, video URLs and native-file representation. Local Markdown/code preview is a presentation feature, not an authorization to upload arbitrary files. Consult the [rendering guide](../file-rendering.md) for text-file conversion and supported previews.

## Streaming response contract

SSE parsing is incremental across byte, Unicode, CR/LF and event boundaries. Events can contain text, reasoning, provider/correlation metadata, usage, a finish reason or an error even after HTTP 200. The terminal marker ends a valid stream; a truncated connection is not fabricated as success.

ChatController keeps returned reasoning separate, batches content notifications, flushes terminal output, and retains partial output after failure. Unknown/length/filter finish reasons have explicit UI meaning. A length stop can offer Continue, which is a new user-authorized turn. First useful output, inter-output idle and total elapsed time have separate deadlines. Heartbeat bytes alone do not reset useful-output deadlines.

## Error and observation contract

AppFailure distinguishes authentication, account limits, temporary rate limits, provider/HTTP/network errors, timeouts, malformed JSON/schema, streaming, cancellation, offline state, configuration, storage, PWA and Flutter failures. Diagnostics can contain timestamps, operation/duration/status, model/provider/correlation IDs, retry information, field/type/value summaries and bounded technical detail. Routine diagnostics omit conversation content and keys.

Health is a recent observation, not a promise. Endpoint metadata and catalog presence do not prove inference success. Cooldown admission occurs before appending a new attempt, and explicit server waits are honored. Optional key counters remain unknown when absent; advisory counts do not replace actual response handling.

## Replaceable local interfaces

| Interface | Operations and semantics |
|---|---|
| ApiTransport | Send a bounded cancellable HTTP request; returns status/headers and body bytes. Fake implementations make unit tests deterministic. |
| LocalStore | Small synchronous text read/write/remove. Browser-backed preferences/cache and memory-backed tests share the contract. |
| PlatformBridge | Connectivity hint, PWA installation/update/error state, inspection, text import/export and lifecycle events. A connectivity hint is not API reachability proof. |
| AttachmentPicker | Bounded local file selection/cancellation; validates formats before creating domain attachments. |
| HistoryRepository | Lazy summary index, full selected record, atomic save, explicit delete, tab-active selection and optional change notifications. |

The browser repository keeps durable store versioning separate from export/session versions. IndexedDB v2 stores summaries, documents, messages and binary attachments; legacy records migrate on a successful atomic checkpoint. Export/import uses a versioned conversation document and creates a separate imported record. Record revisions detect stale writes across tabs and recover a new identity. These data formats are local contracts, not OpenRouter endpoints.

## Verification boundaries

DTO/SSE/transport/history tests are deterministic unless explicitly labeled live or browser. Real catalog testing is opt-in and unauthenticated; chat probes and messages require a configured key and available upstream service. CORS can be diagnosed only from actual browser evidence; an opaque network failure is not proof of CORS. See the [verification commands](../guides/README.md#checks) and [reports index](../reports/README.md).
