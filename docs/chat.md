# Chat, health and context

`ChatController` owns turn admission/lifecycle; `ChatApi` owns OpenRouter requests;
`sse.dart` decodes streaming; `HealthController` owns recent observations. Widgets do
not perform transport parsing.

## Request policy

Every chat/probe names the exact selected model and includes:

```json
{"provider":{"allow_fallbacks":false,"max_price":{"prompt":"0","completion":"0","request":"0","image":"0","audio":"0"}}}
```

No paid fallback, silent model switch or automatic content resend. Generation and
reasoning parameters are omitted until explicitly supplied. Normal chat sends
`max_tokens` only for a supported explicit output override. A health probe may use
its separate small limit. Responses naming an unrelated model are rejected; a free
variant's canonical base ID is accepted.

## Turn lifecycle

Validate model, files, context and cooldown before accepting a turn. Acceptance moves
text/files into a user message and clears the composer; refusal leaves it intact.
Only actual user-content dispatch promotes a draft to chat. Failures/cancellation keep
received output and files, without changing a newly composed draft.

Retry preserves the original turn and failed attempts. Edit and resend appends a copy
with `editedFrom`; Continue appends an explicit instruction after a length stop.
Active work guards model/history navigation. Reload marks unfinished requests
interrupted and never restarts them. Tool-call turns are not automatically replayable;
see [tools](tools.md).

## Streaming and context

Incremental UTF-8/SSE handles split codepoints, CRLF, multiline data and in-stream
errors after HTTP 200. Require `[DONE]`; truncation remains an error. Batch visible
deltas at most once per 32 ms and flush terminal state immediately. Reasoning stays
separate; opaque reasoning details survive complete tool exchanges.

Default deadlines: first useful text/reasoning **90 s**, idle **45 s**, overall
**300 s**. Heartbeats/metadata do not reset useful-output deadlines. Terminal paths
cancel owned timers/transport. Finish reasons distinguish length, filtering and other
provider stops; continuation never bypasses a filter.

Context starts at an explicitly chosen user turn, retaining earlier saved history and
whole tool exchanges. Failed/partial assistant attempts are omitted from new requests.
No automatic trimming/summarization. Estimates use about one token per three UTF-8
bytes plus overhead, 1,024/image and 4,096/other media; these are heuristics, not provider
tokenizer measurements. An estimated overflow blocks submission.

The default **2,048-token reserve** is local planning only, reduced for small contexts.
Explicit limits are 16–32,768 tokens, capped by known provider output limits. Returned
usage/timing remains distinct from estimates.

## Health and allowance

Catalog presence is not responsiveness. Only a selected-model unknown/stale preflight
or explicit recheck probes with `Reply OK.`; no startup bulk probes. Metadata TTL is
30 minutes, responsiveness five minutes, probe deadline 25 seconds. Two checks may
run concurrently; duplicate work is shared.

Cooldowns honor server waits even beyond the local backoff cap. Admission happens
before adding an attempt. Auth/account/network failures remain unknown; modality
observations come from actual requests, so text health does not prove media support.
Bounded persisted observations are scoped to API/key/policy/model metadata.

**Check allowance** explicitly reads `/key`; optional counters stay unknown when
absent and are advisory, not a fabricated hard account block. Cache TTL is five
minutes, daily counters expire at UTC midnight, and 429 cooldowns survive reload.

Diagnostics omit prompts, replies, reasoning, files, keys and raw upstream bodies.
Run `flutter test test/chat test/models/health_test.dart test/models/health_cache_test.dart`
and `make verify`; live provider behavior needs separate opt-in evidence.
Sources: [streaming](https://openrouter.ai/docs/api_reference/streaming),
[routing](https://openrouter.ai/docs/guides/routing/provider-selection),
[reasoning](https://openrouter.ai/docs/guides/best-practices/reasoning-tokens).
