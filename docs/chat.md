# Chat and selected-model availability

Official API documentation rechecked on **2026-10-06**:

- [Streaming and errors](https://openrouter.ai/docs/api_reference/streaming)
- [Provider routing, including max_price and allow_fallbacks](https://openrouter.ai/docs/guides/routing/provider-selection)
- [Reasoning parameters and response fields](https://openrouter.ai/docs/guides/best-practices/reasoning-tokens)
- [Model endpoint metadata](https://openrouter.ai/docs/api/api-reference/endpoints/list-all-endpoints-for-a-model)
- [Chat response format, final usage and finish reasons](https://openrouter.ai/docs/api_reference/overview)
- [Key counters and rate-limit response headers](https://openrouter.ai/docs/api_reference/limits)

## Ownership

`lib/features/chat/chat_api.dart` is the replaceable OpenRouter adapter. `sse.dart` owns UTF-8 and SSE framing, `chat_metadata.dart` owns usage/timing/context values, and `chat_controller.dart` owns turns, attempts and cancellation. `lib/features/models/health.dart` owns observations, probing and quota. Network access and parsing do not run in widgets.

Every chat and probe names exactly the selected model and supplies:

```json
{"provider":{"allow_fallbacks":false,"max_price":{"prompt":"0","completion":"0","request":"0","image":"0","audio":"0"}}}
```

There is no model fallback list, retry loop or paid recovery route. Missing optional prices remain unknown; server routing must satisfy the zero-price constraints. Account restrictions can still prevent free inference. Responses identifying an unrelated model are stopped; a free variant's canonical base ID is accepted.

## Availability and caching

Catalog presence is not responsiveness. Explicit recheck or stale/unknown selected-model preflight fetches `/models/{author}/{slug}/endpoints` if its separate metadata cache has expired, then sends only `Reply OK.` in a tiny inference request. Metadata defaults to a 30-minute TTL; responsiveness defaults to five minutes. Names, status and uptime are supplementary metadata; undocumented status numbers are not interpreted.

The probe sends `max_tokens:16` only when advertised, leaves reasoning at the model's default, and closes its subscription after the first text/reasoning output. Otherwise its timeout still applies. It never forces reasoning off: some endpoints require it, as documented in [per-model reasoning options](https://openrouter.ai/docs/guides/best-practices/reasoning-tokens#discovering-per-model-reasoning-options), rechecked on **2026-10-07**. Reasoning and visible output share the token budget on most providers; a small probe need not produce a complete visible answer. Normal chat still enables reasoning when advertised. Local cancellation does not promise that the provider stops all upstream computation. No startup bulk probes occur.

At most two checks run concurrently, each model's in-flight check is deduplicated, and observations are bounded to 200 models. Forced rechecks still respect cooldown. Failures use capped exponential cooldown. `Retry-After` and recognized absolute `X-RateLimit-Reset` timestamps are minimum waits and may exceed the local cap. A platform rate-limit cooldown also blocks models with fresh observations. Admission happens before reserving an attempt: cooldown-blocked Retry adds neither messages nor requests. No background timers retry or resend content.

Authentication/account/network failures leave health **unknown**; provider failures, unavailable endpoints, truncated streams and timeouts have distinct observations. Recently responsive means a recent inference observation, never a guarantee.

Small metadata is persisted through `LocalStore` under `wfform.health.v2`: observations, cooldowns, endpoint summaries and optional quota counters. The cache is bounded to 200 models / 500,000 characters and scoped to API source, key discriminator and relevant health policies. Capability/pricing fingerprint changes invalidate that model's old observations. Backward clock changes do not make future observations fresh. Chat/file payloads are not stored here. Restored stale health still requires a selected-model probe.

Actual chat requests record outcomes separately for text, image, audio, video and PDF inputs in the outbound context. A text probe never claims to verify media input. Media account/network failures stay unknown and rate limits stay rate-limited. No extra media probes populate these observations.

## Optional quota check

The explicit quota action fetches authenticated `GET /key`, deduplicates requests and caches the result for five minutes. It reads optional `data.free_model_daily_requests.used`, `limit` and `remaining`. Missing counters stay unknown; malformed refreshes retain the last valid snapshot and report the field path. Daily snapshots expire at the next UTC day boundary. Quota-check 429 cooldowns survive reload and also apply to forced checks.

Counters are advisory: OpenRouter documents that exempt accounts/routes and BYOK requests may report a tier-policy count without being gated by it. A zero counter alone therefore does not fabricate an account-wide block. Actual `X-RateLimit-*` headers describe their reported rate-limit window, which may be a minute or another limit rather than the daily allowance. Successful responses need not include these headers. Browser CORS may hide individual headers; unknown reset formats are not guessed.

## Streaming, termination and timing

The decoder has one byte subscription and incremental UTF-8/SSE framing. It retains split Unicode, CRLF and multiline `data:` across chunks, ignores comments/harmless fields, bounds line/event size, and reports invalid JSON or essential field changes. A `[DONE]` marker is required. Torn streams preserve received output with an error. HTTP-200 error envelopes and in-stream provider errors are failures even when the server leaves its socket open.

Content/reasoning deltas are published at most once per 32 ms interval, with an immediate terminal flush on completion/error/cancel. A separate status notifier avoids rebuilding controls for each text update. This is an update policy, not a measured frame-rate claim.

`finish_reason: length` displays a token-limit stop, `content_filter` displays a provider filter stop, and other nonempty reasons retain a provider-stop label. A length-stopped answer can be explicitly continued by appending a new user instruction with the existing answer in context. The app never automatically resends or tries to bypass filters. Optional final token usage is retained separately from estimates. Message metadata records preflight duration, first useful text/reasoning latency from the actual inference request, and generation duration; diagnostics include these numbers without message content.

Inference uses separate clocks: first useful output (90 s), useful-output idle (45 s), and overall inference (300 s). Heartbeats/metadata do not postpone first-output or idle deadlines. The overall cap bounds a continuously active stream. Tiny probes keep their separate 25-second limit. Ordinary GETs retain `requestTimeoutSeconds`. Terminal paths release phase timers and cancel owned transport work.

Reasoning is enabled only when advertised. Returned plain reasoning or text/summary `reasoning_details` is shown separately. Encrypted reasoning is not reconstructed or replayed. Responses remain text; this app does not execute tool calls.

## Context and output budget

Context controls explicitly begin outgoing context at a chosen user turn while preserving earlier visible/stored history, or start a separate conversation. The default includes all eligible history. The chosen boundary and output reserve persist per conversation. Retry refuses a boundary that excludes its original user turn. Failed/partial assistant attempts remain visible but are omitted from requests. No automatic trimming or summarization occurs.

Text estimates use approximately one token per three UTF-8 bytes plus message overhead; image input reserves 1,024 estimated tokens per file and other media 4,096. These are local planning heuristics, **not tokenizer measurements or guaranteed media costs**. Resolution, duration, pages, provider preprocessing and tokenizer can change actual usage substantially. Media uncertainty and unknown context limits remain visible. An estimated over-budget request is refused before acceptance/probing: shorten the draft, explicitly exclude older context, adjust the reserve or start anew.

The default output reserve is 2,048 tokens (reduced to a quarter of a smaller reported context limit). Users may choose 16–32,768 tokens per conversation, constrained by a reported provider maximum. `max_tokens` is sent only when the model advertises support. Without that support the reserve is a planning estimate only; local response/phase limits remain active. Server usage never silently changes the user's context choice.

New typed configuration keys in `config/example.json`:

| Key | Default | Purpose |
| --- | --- | --- |
| `firstResponseTimeoutSeconds` | 90 | Wait for first useful inference output |
| `streamIdleTimeoutSeconds` | 45 | Wait between useful output deltas |
| `streamOverallTimeoutSeconds` | 300 | Maximum total inference duration |
| `endpointTtlSeconds` | 1800 | Provider-metadata freshness |
| `quotaTtlSeconds` | 300 | On-demand quota freshness |
| `maxOutputTokens` | 2048 | Default response reserve/cap when supported |

The overall timeout must cover both phase timeouts. Existing local configurations may omit these keys and receive defaults; API keys are untouched. Changing credentials via `copyWith` retains every timing/budget policy.

## Acceptance, retry, editing and history

Send validates the turn and admission, reserves user/assistant entries, and invokes `onAccepted` synchronously before probing/inference. Only an accepted send clears composer text/files. Refused submissions stay in the composer. Failure preserves the accepted turn, files and partial answer; a newer draft remains untouched.

Retry reuses the original user turn/files/model and keeps old failed attempts visible. Editing uses a separate editor and appends a user turn with `editedFrom`; it does not delete history or replace the main composer draft. Cancellation leaves received output intact. Active response work must finish or be explicitly cancelled before model/history navigation.

Attachment formats, size/signature checks and capability validation are described in [multimodal.md](multimodal.md). Attachment-only messages are supported. Retained outbound PDFs force native file parsing, preventing a paid OCR fallback. Conversation/message/response/session limits remain bounded; at the message count limit start a new conversation rather than silently deleting turns.

`exportSessionData()` exposes a structured session; `exportSession()`/`restoreSession()` retain JSON compatibility. `lib/features/history/` owns record validation/IndexedDB; `StudioState` coordinates checkpoints and navigation. Reloaded unfinished attempts are interrupted and never resume automatically. Another model starts another saved conversation. Archived histories are read-only until restored. See [history.md](history.md).

Diagnostics omit prompts, answers, reasoning, attachments and raw upstream bodies. Structural codes, field paths, HTTP status, provider/correlation metadata, and aggregate timing/usage remain available.

## Deterministic verification

```sh
flutter test test/chat test/models/health_test.dart test/models/health_cache_test.dart test/shared/core_test.dart test/shared/phase_timeout_test.dart
flutter analyze
```

These tests use controlled transports/clocks; they do not establish live provider or browser behavior. Regression coverage includes blocked-retry immutability, explicit context exclusion, output caps, usage/finish metadata, burst notification batching, first/idle/overall timeout cleanup, persisted health/cooldowns/quota, and provider errors that leave connections open. Main verification reports distinguish live and browser checks.
