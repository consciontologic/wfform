# wfform architecture

Updated 2026-10-06. This describes the implemented Flutter application; active additions and their acceptance gates are tracked in the [roadmap](../planning/ROADMAP.md).

## System boundary

wfform is a browser-first Flutter/Dart client for discovering explicitly free OpenRouter models and maintaining local conversations. The browser calls OpenRouter directly. The Dart development host and the nginx container serve static release files; neither is an application backend or API proxy. The container workflow is documented in the [Docker guide](../guides/DOCKER.md).

Application logic and UI remain in Dart. The small HTML/manifest/bootstrap/service-worker files in [web](../../web/) integrate Flutter with browser installation and offline shell caching. Python and shell scripts under [xops](../../xops/) are repository/build operations, not deployed application logic. See [ADR-0001](../design/ADR-0001-flutter-browser-boundary.md) and [ADR-0004](../design/ADR-0004-agent-workspace-boundary.md).

## Components and ownership

| Component | Responsibility | Main source |
|---|---|---|
| Bootstrap | Render the application, load runtime configuration asynchronously, capture framework errors | [main.dart](../../lib/main.dart) |
| Application state | Conversation navigation, history persistence, config replacement, online/offline/update transitions | [StudioState](../../lib/app/studio_state.dart) |
| Configuration | Typed defaults, parsing, validation and policy limits | [AppConfig](../../lib/config/app_config.dart) |
| Catalog | API DTO validation, exact zero-price eligibility, pagination, cache and explicit selection | [models](../../lib/features/models/) |
| Health | Recent observations, selected-model probes, endpoint metadata, cooldowns and optional allowance lookup | [health.dart](../../lib/features/models/health.dart) |
| Chat | Turn admission, context boundary, retry/edit/continue semantics, request adaptation and SSE decoding | [chat](../../lib/features/chat/) |
| Documents | Strict UTF-8 format handling, bounded Markdown/source rendering and syntax highlighting | [documents](../../lib/features/documents/) |
| History | IndexedDB records, message rows, immutable media, revision conflict recovery | [history](../../lib/features/history/) |
| Presentation | Adaptive layout, controls, dialogs, accessible selectable content and local previews | [presentation](../../lib/presentation/) |
| Shared ports | HTTP, cancellation, diagnostics, connectivity, file selection and browser storage | [shared](../../lib/shared/) |
| Release tools | Compile, hash and publish complete immutable PWA releases; serve and measure artifacts | [tool](../../tool/) |
| Public discovery | Search/sharing metadata and a small static product document; no application logic | [SEO](../seo.md) |
| Website publishing | Verify releases and commit only managed static assets to the website repository in CI | [CI/CD](../guides/CI_CD.md) |
| Native hosts | Android/iOS launch projects with `com.wfform` application identity; native adapter parity is pending | [Native setup](../native-platforms.md) |

Widgets consume controllers and domain values. HTTP requests and response parsing belong to adapters, not widgets. Small injectable interfaces support deterministic tests and eventual platform ports without imposing another framework.

## Data and request flow

1. Bootstrap creates defaults and renders Flutter before waiting for network configuration. Local history loading, PWA registration and configuration loading have separate readiness. A failed local history operation does not erase its database.
2. A cached catalog is validated and displayed immediately where available. Once configuration is settled, one deduplicated public refresh discovers all output modalities. Bad refreshes retain the last valid catalog. Provisional empty-key configuration cannot overwrite durable real-key health observations.
3. The user explicitly selects a compatible free model. A different model starts another conversation. If selection disappears or relevant metadata changes, the application requires a valid selection instead of switching models.
4. Send validates the current model, context estimate, attachment compatibility and cooldown before accepting a turn. Stale selected-model health triggers a small bounded probe; there is no mass inference probing at startup.
5. Accepted draft text and attachments become a user message and the composer clears. The adapter sends the chosen ID with zero-price provider guards and no provider fallback. Incremental response text and optional returned reasoning are batched into the active assistant message.
6. Terminal success or failure preserves received output, usage and timing where supplied. Retrying, continuing or editing/resending is explicit. History checkpoints persist changes without rewriting unchanged attachment bytes.

## Persistence boundaries

| Store | Data | Important property |
|---|---|---|
| Memory | Active conversation, runtime key, current catalog/controllers | Reload recovery requires the stores below |
| localStorage | Catalog, appearance/preferences, bounded scoped health/endpoint/allowance observations | Synchronous small metadata only; runtime key is not stored as a preference |
| sessionStorage | Tab-local active conversation and immediate unsent-text recovery marker | Draft attachments are not copied into this marker |
| IndexedDB | Conversation summaries/documents, individual message rows and binary attachment records | Browser-local durability, transactional writes and revision checks |
| Cache Storage | Content-verified release shell and release/client metadata | No API, configuration, conversation or attachment response caching |

History belongs to an origin, including its port. Moving the source directory does not migrate browser data; opening the same origin preserves access to that origin's existing history. Export/import supplies a portable backup. See [history](../history.md) and [PWA behavior](../pwa.md).

## Lifetimes and bounded work

Controllers outlive responsive layout branches, preserving draft, selection, focus and pending work while resizing. Catalog refreshes, quota reads and health probes deduplicate in-flight work. Health concurrency is two. Chat has first-useful-output, idle and overall deadlines, with immediate cancellation and terminal flushing. Content retries are never automatic.

Conversation length, response text, catalog bytes/pages, attachment count/size, stored histories and diagnostics are bounded. The current defaults and validation constraints are listed in the [configuration reference](../guides/README.md#configuration). Long model/history lists build lazily. Narrow status notifications avoid treating every streamed character as an application-wide state change.

## Failure handling and verification

Network, authentication, account, rate-limit, provider, schema, stream, storage and PWA errors retain distinct categories and actionable diagnostics. Successful catalog refreshes also record informational counts. The observed unresolved-price sentinel is an eligibility exclusion, not a schema-error event; malformed companion fields still quarantine the entry.

Unit/widget tests use fake transports, clocks and stores. Opt-in public catalog checks use the real API; real Chromium IndexedDB checks use disposable databases. Release browser checks must separately establish layout, connectivity, offline reload and update behavior. Historical counts and screenshots remain dated evidence, not a substitute for rerunning changed behavior. See [verification index](../reports/README.md).
