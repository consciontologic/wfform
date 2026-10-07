# Catalog adapter and free-price policy

Official API documentation and public catalog verified on **2026-10-06**:

- [List models API](https://openrouter.ai/docs/api/api-reference/models/list-all-models-and-their-properties): omitting `offset` and `limit` requests the complete catalog. `output_modalities=all` includes every output type; the default is text only. Pagination exposes `links.next` and `total_count`. The linked page’s downloadable OpenAPI schema requires `pricing.prompt` and `pricing.completion`; other pricing fields, including `request`, are optional.
- [Model schema and pricing guide](https://openrouter.ai/docs/guides/overview/models): prices are USD per token/request/unit. Conditional `pricing.overrides` may change charges with time or context length. The catalog also reports input/output modalities, supported parameters, and top-provider configuration. Supported parameters explicitly advertise reasoning support.
- [Auto Router pricing](https://openrouter.ai/docs/guides/routing/routers/auto-router#pricing): the charge depends on the model the router selects. This does not establish a free route.

The application only requests the official JSON API. Website HTML, CSS, JavaScript, and `variant=free` are never used. Catalog fetching is public and sends no authorization header.

## Eligibility

`lib/features/models/model.dart` owns DTO validation and normalization. Both required token prices must be valid, finite, nonnegative decimal values representing exactly zero. Decimal strings and JSON numbers are accepted. Missing required fields, booleans, blank strings, unrecognized negative prices, nonfinite values, and malformed structures are quarantined. Exact mantissa checking prevents a tiny positive price from underflowing into zero. A `:free` suffix alone never qualifies a model.

The [public catalog](https://openrouter.ai/api/v1/models?output_modalities=all) returned the exact string `"-1"` for both token prices on seven routing entries during verification: `typesafe/jev-router`, `nvidia/switchyard`, `openrouter/auto-beta`, `openrouter/fusion`, `openrouter/pareto-code`, `openrouter/bodybuilder`, and `openrouter/auto`. Treating this as an **unresolved/variable-price sentinel is an inference from observed API data and router pricing documentation**, not an explicitly documented numeric convention. The adapter recognizes only that exact string (after whitespace trimming) or numeric `-1`; it never converts it to zero. Applicable unresolved charges exclude an entry from free selection and are counted once per entry in the successful refresh summary, rather than reported as schema errors. Other malformed fields on the same entry still trigger quarantine. No model-ID allowlist is involved.

Present request, reasoning, cache, and unknown potentially applicable charges must also be zero. Conditional nonzero charges disqualify the model regardless of when their condition currently applies. Image/audio/search charges do not apply to text-only turns; their reported prices remain visible. Attachments undergo the separate capability and applicable-price checks described in the [multimodal guide](multimodal.md). For models without text input and output, every reported unit price must be zero, and the model stays unselectable.

An unresolved non-text media charge preserves otherwise valid zero-price text chat, but disables attachments to which that charge applies, including conditional overrides. Its value remains unresolved in model details. Malformed media-price values still trigger the existing schema validation; they are not silently ignored.

**An absent optional price is unreported, not zero.** Live catalog and endpoint responses observed on the verification date omit `request`, including for the supplied example model. Details preserve this absence. Inference enforces server-side zero-price limits for prompt, completion, and request pricing, disables provider fallbacks, and sends exactly the selected model. Unknown optional fee metadata therefore does not authorize a paid route.

The list consists of **free-price candidates**, not a claim that every media model has complete unit pricing or usable text chat. Chat selection requires text input and **only text output**. Models advertising text plus audio/image or other native output remain inspectable but unselectable: this version has no documented text-only output negotiation, and prompt/completion/request price limits do not guarantee zero native-output charges. Additional input capabilities do not disqualify otherwise free text chat; using those capabilities requires separate attachment validation. Non-text models also remain inspectable with an incompatibility explanation. Routers with validated zero prices remain inspectable but unselectable so the app never silently changes the chosen model; routers with unresolved token prices are excluded from this free-price candidate list. Catalog presence is independent of observed health.

## Refresh, cache, and failures

`catalog.dart` owns refresh deduplication, pagination validation, selection invalidation, change detection, and persistence. Every launch loads a validated source-specific cache; every online launch starts one refresh. Offline initialization loads only the cache, deferring the request until reconnection or explicit refresh. A stale cache can still be inspected. Failed refreshes keep the last valid catalog and timestamp. A valid empty array is distinct from an unrecognized schema or wholly invalid entries.

Pagination follows only the same origin and model-list path, preserves all-modalities discovery, detects loops/inconsistent totals, and bounds pages, entries, and response bytes. Valid entries survive individual quarantines. Quarantine counts are exact; stored issue details are limited to 100 and shared diagnostics are separately bounded.

Unresolved-price exclusions are informational and aggregated in `catalog.refresh`. Genuine pricing failures retain their field, expected type/format, actual type, and a bounded rejected scalar in technical details. Objects and arrays are represented by type/count, never copied wholesale. The diagnostics service applies redaction before display or export. A catalog made entirely of valid unresolved-price entries is a successful empty free catalog; an entirely malformed catalog remains a failed refresh that retains the last valid cache.

Pricing/capability changes require explicit reselection. A removed, paid, malformed, or newly incompatible selection is cleared with an explanation. There is no default or substitute model.

## Tests and maintenance

Deterministic tests:

```sh
flutter test test/models/catalog_test.dart
```

Explicit bounded public-network verification (does not send chat or require a key):

```sh
flutter test --dart-define=RUN_LIVE_CATALOG=true test/models/catalog_test.dart --plain-name 'opt-in live public catalog adapter check'
```

The live test accepts changing counts and a genuinely empty free catalog. It prints its observation and never embeds a live fixture. Localize schema adaptations to `model.dart` / `parseCatalog`, add a deterministic regression case, and review price semantics before changing eligibility. Arbitrary API changes are not automatically repairable.
