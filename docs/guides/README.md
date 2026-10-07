# Setup and engineering guides

| Guide | Scope |
|---|---|
| [DOCKER.md](DOCKER.md) | wfform container/nginx setup, make commands, runtime config, TLS and header verification |
| [CI_CD.md](CI_CD.md) | Source checks and automated web publishing to consciontologic/wfform.com; required token and Pages/DNS setup |
| [AGENT_OPERATING_MODEL.md](AGENT_OPERATING_MODEL.md) | Reusable framework workflow and recovery rationale |
| [CODEX_SETUP.md](CODEX_SETUP.md) | Codex role/skill translation and client setup |
| [MODEL_PROFILES.md](MODEL_PROFILES.md) | Framework guidance on assistant behavior; not OpenRouter catalog model documentation |
| [MCP_SETUP.md](MCP_SETUP.md) | Enabled CodeGraph integration, local runtime/index setup and real MCP verification |

The [project context](../tracking/context.md) and [AGENTS.md](../../AGENTS.md) govern this repository. Generic framework setup examples do not authorize installing MCP, changing global settings or replacing the Flutter application stack. End-user application behavior is indexed in [docs/README.md](../README.md).

## Local release setup

Run these commands from the repository root with **Flutter 3.38.5 / Dart 3.10.4**:

```sh
flutter pub get
# For a fresh checkout only; do not overwrite an existing local configuration:
cp -n config/example.json config/local.json
# Edit config/local.json and set apiKey, or paste a session key in Settings.
dart run tool/build.dart
dart run tool/serve.dart --port=8765
```

Open **http://localhost:8765**. Use the same origin to retain access to local history; changing the port opens a separate browser store. Keep the development credential in ignored `config/local.json` or enter a session key in Settings; never put it in source fixtures. Do not publish that file or a release config copy with a shared credential. Credentials delivered to a browser are accessible to that browser's user. This is a development demo, not a production secret-management design.

The helper runs exactly:

```sh
flutter build web --release --no-web-resources-cdn --pwa-strategy=none
```

It then generates the versioned shell worker. Use the helper for a complete PWA; the raw Flutter build alone does not populate the worker's release asset list. The Dart loopback host serves static files only, with appropriate WASM/font MIME types. It never forwards OpenRouter requests.

Development UI iteration:

```sh
flutter run -d chrome --web-port=8080
```

Flutter's development server does not map the ignored runtime configuration. Paste a key in Settings for that session. Test PWA behavior on the release build.

## Checks

Run `make verify` for formatting, analysis, deterministic tests and repository hygiene. The individual commands and opt-in checks are:

```sh
dart format --output=none --set-exit-if-changed lib test tool deploy
flutter analyze
flutter test --reporter=expanded
dart run tool/build.dart
```

Optional bounded **live public catalog** check:

```sh
flutter test --dart-define=RUN_LIVE_CATALOG=true test/models/catalog_test.dart --plain-name 'opt-in live public catalog adapter check'
```

Optional **real browser storage** checks and synthetic **history checkpoint benchmark**:

```sh
CHROME_EXECUTABLE=/path/to/chrome flutter test --platform chrome \
  test/history/browser/indexeddb_checks.dart --reporter expanded
flutter test tool/history_benchmark.dart --reporter expanded
```

The six Chromium storage checks passed against isolated generated databases. They exercise real IndexedDB migration, binary media, incremental rows, rollback, competing repository revisions, `BroadcastChannel`, reads with suppressed transaction-completion delivery, and pending-read aborts; they do not send API requests or establish Safari/Firefox behavior. The benchmark uses two synthetic decoder-validated PNG files totaling 12 MiB and ten response checkpoints. It writes `outputs/history-performance.json`: VM codec preparation and modeled write-payload sizes, **not** browser frame time, disk throughput or IndexedDB latency. See [history](../history.md) for results and scope.

The ordinary API/widget tests use fixtures, controlled clients or fake clocks. No automated test silently sends user content or embeds a credential. For live chat, select a current text-compatible model in the running app and send a short message; stale selected-model health triggers a small probe before the conversation is submitted. The [reports index](../reports/README.md) preserves dated release evidence; it does not certify every later build.

## Configuration

[`config/example.json`](../../config/example.json) documents every option; `config/local.json` is ignored. The runtime file is network-only and excluded from service-worker caching. The session key is kept only in memory. Catalog, small preferences and bounded health/endpoint observations use localStorage. The immediate text recovery draft and active-conversation ID use tab-local sessionStorage; earlier localStorage recovery values are read only as migration sources. Conversation metadata and individual messages use IndexedDB, with immutable attachment bytes stored separately and referenced by ID. These are application-managed data, never service-worker cached. An explicit update waits for a durable history save under the existing conversation ID; it does not create a separate legacy localStorage session snapshot. Clearing browser site data can remove both history and offline assets.

| Key | Default | Meaning |
|---|---:|---|
| `apiBaseUrl` | `https://openrouter.ai/api/v1` | HTTPS API base; HTTP permitted only on localhost |
| `apiKey` | empty | Bearer credential for endpoint checks and inference |
| `requestTimeoutSeconds` | 90 | Total deadline for ordinary requests such as catalog and allowance checks; chat uses the separate stream phase policy below |
| `probeTimeoutSeconds` | 25 | Deadline per metadata/probe request |
| `healthTtlSeconds` | 300 | Successful observation freshness |
| `endpointTtlSeconds` | 1800 | Provider/endpoint metadata freshness, independent of inference health |
| `quotaTtlSeconds` | 300 | Advisory allowance observation freshness |
| `firstResponseTimeoutSeconds` | 90 | Chat deadline until first useful text or reasoning, including response startup |
| `streamIdleTimeoutSeconds` | 45 | Chat deadline between useful text/reasoning events; heartbeat bytes do not reset it |
| `streamOverallTimeoutSeconds` | 300 | Absolute chat request/stream deadline |
| `maxOutputTokens` | 2048 | Default response-token reserve and supported `max_tokens` request limit; per-conversation Context settings can override it |
| `cooldownSeconds` | 15 | Minimum interval between checks |
| `maxBackoffSeconds` | 300 | Exponential local cap; longer Retry-After is honored |
| `cacheTtlSeconds` | 86400 | Catalog age considered stale |
| `maxDiagnostics` | 100 | Maximum retained records |
| `maxDetailChars` | 2000 | Per-field diagnostic truncation |
| `maxMessages` | 80 | Conversation count bound; explicit new chat at limit |
| `maxResponseChars` | 120000 | Answer + reasoning limit |
| `maxCatalogBytes` | 8000000 | Total catalog/cache byte limit |

Durations must be 1 second–30 days, backoff must be at least the cooldown, and the overall stream timeout must cover both its first-response and idle timeouts. `maxOutputTokens` must be 16–32768. Other validation ranges are explicit in [`AppConfig.validate()`](../../lib/config/app_config.dart). Probes use their shorter probe deadline. Automatic content retries remain **zero**; health concurrency is capped at **two**. Catalog refreshes, endpoint checks and health probes are deduplicated. Cached health observations are scoped to API/key/policy and invalidated when meaningful model metadata changes. Catalog pagination, saved entries, message input and SSE frames also have bounds. Extra harmless configuration fields are ignored; wrong types produce a visible configuration diagnostic.

## Troubleshooting

On authentication or account errors, update the key or account settings. Rate limits show cooldown/retry information; use explicit retry after it expires. A provider failure does not switch models. A failed catalog refresh retains the last valid catalog and refresh time. Schema diagnostics identify the field, expected type and observed type; adapter changes stay localized.

A browser reporting online does not prove API reachability. Opaque fetch failures remain network errors until the browser network panel identifies their cause. The app adds no proxy. HTTPS or localhost and a cached first release load are required for offline startup. If storage is blocked or full, the app continues in memory and reports reduced reload recovery. See [PWA behavior](../pwa.md), [catalog policy](../catalog.md) and [chat/health](../chat.md).
