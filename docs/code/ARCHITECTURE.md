# Architecture

wfform is a Flutter/Dart browser client. It calls OpenRouter directly; Dart/nginx
hosts serve static files, with no API proxy. Optional [wfformcomp](../wfformcomp.md)
runs explicitly configured local programs or stdio MCP servers and may serve the
same public web build. Python/Bash in `xops/` are repository tooling only.

## Ownership

| Area | Source and responsibility |
|---|---|
| Startup and state | [main.dart](../../lib/main.dart), [StudioState](../../lib/app/studio_state.dart): config, navigation, history checkpoints and platform transitions |
| Configuration | [AppConfig](../../lib/config/app_config.dart): typed defaults and bounds |
| Catalog/health | [models](../../lib/features/models/): exact free-price validation, cache, explicit selection and bounded selected-model probes |
| Chat | [chat](../../lib/features/chat/): admission, context, SSE, cancellation and explicit retry/edit/continue |
| Parameters/tools | [parameters](../../lib/features/parameters/), [tools](../../lib/features/tools/): advertised overrides, MCP discovery and approved dispatch |
| Documents/history | [documents](../../lib/features/documents/), [history](../../lib/features/history/): safe previews and revision-checked persistence |
| UI/ports | [presentation](../../lib/presentation/), [shared](../../lib/shared/): adaptive selectable UI and injectable browser/HTTP/storage adapters |
| Release | [tool](../../tool/), [deploy](../../deploy/): verified public assets, packaging and static serving |

Widgets use controllers/domain values; transport and DTO parsing stay in adapters.
Controllers and focus ownership survive responsive layout changes.

## Request flow

1. Render defaults; load configuration, local history and PWA state independently.
2. Display a validated cached catalog and deduplicate its online refresh. Failed
   refreshes retain valid data. Require explicit selection of a free compatible model.
3. Validate context, attachments and cooldown before accepting a turn. Probe only
   stale/unknown selected-model health; never bulk-probe at startup.
4. Accept text/files, clear the composer and send the exact model ID with zero-price
   routing caps and no provider fallback. Only user-content dispatch promotes a draft
   to chat. Keep partial answers and newer drafts on failure.
5. Assemble complete streamed tool calls, validate and ask approval for each call,
   dispatch, then return results to the same model. Preserve matching call/result IDs
   and opaque reasoning details. Stop after four rounds; never replay uncertain work.
6. Checkpoint changed messages and new attachment bytes. Retry/edit/continue remain
   explicit. Catalog removal never silently selects another model.

## Storage

| Store | Holds |
|---|---|
| Memory | Current controllers, runtime credentials and MCP bearer tokens |
| localStorage | Explicitly saved OpenRouter key, small preferences/catalog/health metadata and MCP names/URLs |
| sessionStorage | Tab-local active conversation and immediate text-draft recovery |
| IndexedDB | Summaries, conversation metadata, message rows and immutable binary attachments |
| Cache Storage | Hash-verified static shell generations only |

MCP credentials require reconnection after reload. An explicitly saved browser key
wins over runtime config; clearing it keeps an empty override. History belongs to
scheme/host/port and exports provide portable backups. Atomic revision checks preserve
conflicts as recovered copies. Never erase damaged data or silently fall back to a
temporary store after failure.

Public tags/packages use plain SemVer. Internal content hashes identify verified
PWA cache generations; published files use flat paths. Updates preserve drafts and
require explicit activation. API responses, keys, configuration and user files never
enter the worker cache.

See [feature contracts](../README.md), [accepted decisions](../design/README.md) and
[verification commands](../guides/README.md#checks). Mocked tests, real browser checks,
opt-in live requests and actual publication are separate evidence.
