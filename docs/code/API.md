# API and local contracts

All OpenRouter calls originate in the browser. The configurable base defaults to
`https://openrouter.ai/api/v1`; there is no hosted wfform application API.

| Operation | Method/path | Trigger |
|---|---|---|
| Catalog | `GET /models?output_modalities=all` | Launch, refresh or reconnect; no Authorization |
| Endpoint metadata | `GET /models/{author}/{slug}/endpoints` | Selected-model health when metadata is stale |
| Probe/chat | `POST /chat/completions` | Selected-model preflight or explicit user send/retry/continue |
| Allowance | `GET /key` | Explicit Check allowance |

[Catalog](../catalog.md) defines eligibility. [Chat](../chat.md) defines streaming,
errors, deadlines and routing. [Media](../multimodal.md) defines content parts.
[Tools](../tools.md) defines MCP compatibility and parameter omission.

Every inference names the chosen model, disables provider fallback and limits prompt,
completion, request, image and audio prices to zero. Unsupported overrides are rejected;
generation settings remain omitted until explicitly supplied. No automatic content
retry, paid fallback or silent context trimming is permitted.

SSE parsing handles split UTF-8, CRLF and events, including errors after HTTP 200.
A truncated stream is not success; preserve partial output. Routine diagnostics may
include bounded structural errors, status, timing and correlation IDs, never message
content, credentials or raw upstream bodies.

| Replaceable interface | Contract |
|---|---|
| `ApiTransport` | Bounded cancellable HTTP with status, headers and bytes |
| `LocalStore` | Small synchronous metadata read/write/remove |
| `PlatformBridge` | Connectivity hints, PWA state, import/export and lifecycle |
| `AttachmentPicker` | Bounded selection, validation and cancellation |
| `HistoryRepository` | Lazy summaries, atomic record saves/deletion, revisions and notifications |

Durable database versioning differs from export-document versioning. Imports create
separate records; legacy data is retired only after a successful transaction.
A network error is not proof of CORS; diagnose it in an actual browser.
