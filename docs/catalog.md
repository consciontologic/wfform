# Catalog and free-price policy

Discovery uses public `GET /api/v1/models?output_modalities=all`, without
Authorization or website scraping. [OpenRouter's model API](https://openrouter.ai/docs/api/api-reference/models/list-all-models-and-their-properties)
and [pricing schema](https://openrouter.ai/docs/guides/overview/models) are the source
contracts; `model.dart` validates them and `catalog.dart` handles refresh/cache.

## Eligibility

- Required prompt/completion prices must be valid decimals representing **exactly
  zero**. Missing/malformed prices and tiny positive values never become free;
  the `:free` suffix alone is insufficient.
- The exact observed `-1` marker is treated as unresolved/variable pricing. This is
  an inference from router data, not a documented numeric convention. Applicable
  unresolved prices exclude a model; genuine malformed fields still quarantine it.
- Reported request, reasoning, cache, unknown applicable fees and conditional
  overrides must also be zero. Optional absent prices remain **unreported**.
- Media charges are checked for the attached modality. Unresolved media charges can
  disable that input while preserving otherwise free text chat.
- Chat selection requires text input and **only text output**. Native non-text or
  mixed outputs and routers remain inspect-only; no silent routing substitution.
- Requests enforce server-side zero-price caps and disable provider fallbacks.
  Catalog eligibility does not guarantee provider availability or account access.

## Refresh and recovery

Load a validated source-specific cache immediately, then deduplicate one online
refresh. Offline startup defers networking. Failed refreshes preserve the last valid
catalog/timestamp; valid empty data differs from wholly malformed data.

Follow only same-origin model-list pagination, bounding pages, entries and bytes and
rejecting loops/inconsistent totals. Keep valid entries when individual entries fail;
retain at most 100 detailed quarantine issues. Unresolved exclusions are aggregated
information, not schema errors. Diagnostics contain bounded structural details only.

Pricing/capability changes invalidate selection with an explanation. Removed, paid or
incompatible models never cause an automatic replacement.

## Checks

```sh
flutter test test/models/catalog_test.dart
# Opt-in public API check; no key or chat content:
flutter test --dart-define=RUN_LIVE_CATALOG=true test/models/catalog_test.dart --plain-name 'opt-in live public catalog adapter check'
```

Keep changing live counts out of fixtures. Add deterministic DTO regressions before
adapting a schema. See [chat](chat.md) and [media](multimodal.md) for request guards.
