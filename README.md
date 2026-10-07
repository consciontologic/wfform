# wfform

A runnable Flutter web application for discovering OpenRouter's free models and chatting with text responses, including local attachments where the selected model supports them. It calls the official API directly from the browser. Application UI and logic remain Flutter/Dart; nginx serves static files, while the scaffold's shell/Python tools perform repository operations only. There is no application backend or API proxy.

Tested SDK: **Flutter 3.38.5 stable / Dart 3.10.4**. The lockfile pins resolved packages. `http` supplies streaming HTTP/cancellation and `web` supplies browser storage, file selection, connectivity, PWA and download adapters. Rendering-specific choices are documented in [the file-rendering guide](docs/file-rendering.md).

## Project workspace and documentation

The application now lives at **`/home/serhatakbak/code/projects/wfform`**. The source repository is [consciontologic/wfform](https://github.com/consciontologic/wfform). At the user's request, the 2026-10-07 account migration starts a new Git history; prior local Git metadata is retained only in an ignored backup. The full agentic-workspace scaffold supplies repository instructions, skills, tracking and make/xops operations through a single root **Makefile**. CodeGraph is enabled for this repository; use `make codeg` to refresh its local index and see [MCP setup](docs/guides/MCP_SETUP.md) for client configuration. This supersedes the initial scaffold's `--no-mcp` setting. Agents do not commit or push; the coordinating parent follows [AGENTS.md](AGENTS.md), and the human owns `make git`.

The Dart package is **`wfform`**. Android's namespace/application ID and iOS's Runner bundle identifier are **`com.wfform`**. Native host projects are configured, while web remains the verified release target; see [native platform setup and limits](docs/native-platforms.md). The installed PWA identity and browser history are unchanged.

Start with [the documentation index](docs/README.md), [architecture](docs/code/ARCHITECTURE.md), [project charter](docs/project/CHARTER.md), [current roadmap](docs/planning/ROADMAP.md) and [migration/scaffold provenance](docs/project/DECISION_LOG.md). Reusable `.template.md` files are clearly separated from populated project documents.

Public website releases target **https://consciontologic.github.io/wfform.com/** (free GitHub Pages; no custom domain required). GitHub Actions checks pull requests and publishes verified web artifacts to `consciontologic/wfform.com` after source `main` pushes. Add the source repository Actions secret **`WFFORM_DEPLOY_TOKEN`**, a fine-grained token with **Contents: read and write** on the destination repository; follow the [CI/CD guide](docs/guides/CI_CD.md) for GitHub Pages setup and the [SEO guide](docs/seo.md) for Search Console. `make build.public` creates a publishable release without local credentials. Website publication is separate from Google indexing, which requires a reachable public domain.

Historical generated reports/screenshots remain in the original chat workspace's `outputs/` directory, as recorded in [the reports index](docs/reports/README.md). Their dated results are preserved; they are not evidence of a newly built revision. Moving source files does not change browser history's origin boundary.

## Run the release PWA

From this directory (or first run `cd /home/serhatakbak/code/projects/wfform`):

```sh
flutter pub get
# For a fresh checkout only; do not overwrite an existing local configuration:
cp -n config/example.json config/local.json
# Edit config/local.json and set apiKey, or paste a session key in Settings.
dart run tool/build.dart
dart run tool/serve.dart --port=8765
```

Open **http://localhost:8765**. Keep this origin to see the history from the verified browser workflow; changing the port opens a separate browser store. Keep the development credential in ignored `config/local.json` or enter a session key in Settings; never put it in source fixtures. Do not publish that file or a release config copy with a shared credential. Credentials delivered to a browser are accessible to that browser's user. This is a development demo, not a production secret-management design.

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

## Container and make workflow

The [Docker/nginx guide](docs/guides/DOCKER.md) owns the complete container, TLS, local configuration and header-check instructions. It serves the same Flutter PWA as static assets; browser API calls still go directly to OpenRouter. The Docker origin on port 8080 has its own browser history, separate from the Dart host on port 8765.

Use `make help` for the installed targets. The application aliases cover `deps`, `format`, `analyze`, `test`, `verify`, `repository.check`, `build` and `serve`. Container operations use `make image`, `make up`, `make down`, `make restart`, `make logs` and `make check`; local TLS uses `make tls.cert`, `make tls.up`, `make tls.check` and `make tls.down`. The Docker guide states prerequisites and measured checks; configured headers do not by themselves establish an external scanner grade.

## Checks

```sh
dart format --output=none --set-exit-if-changed lib test tool
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

The six Chromium storage checks passed against isolated generated databases. They exercise real IndexedDB migration, binary media, incremental rows, rollback, competing repository revisions, `BroadcastChannel`, reads with suppressed transaction-completion delivery, and pending-read aborts; they do not send API requests or establish Safari/Firefox behavior. The benchmark uses two synthetic decoder-validated PNG files totaling 12 MiB and ten response checkpoints. It writes `outputs/history-performance.json`: VM codec preparation and modeled write-payload sizes, **not** browser frame time, disk throughput or IndexedDB latency. See [history.md](docs/history.md) for results and scope.

The ordinary API/widget tests use fixtures, controlled clients or fake clocks. No automated test silently sends user content or embeds a credential. For live chat, select a current text-compatible model in the running app and send a short message; stale selected-model health triggers a small probe before the conversation is submitted. The previous `outputs/wfform-multimodal-report.md`, `docs/follow-up-verification.md` and `docs/verification.md` preserve earlier release evidence, rather than claiming those measurements describe every later build.

## Use

Search or open the model selector, inspect capabilities, and explicitly choose a compatible model. Incompatible listings remain inspectable. The supplied Nemotron example is not a default or hardcoded catalog. Chat uses the actual selection with zero prompt/completion/request/image/audio price caps and provider fallback disabled.

The composer starts at three lines, or two when viewport height or 200% text needs more room. It grows to five lines in compact layouts and eight in wider layouts, then scrolls internally. It supports multiline text, Ctrl/Command+Enter to send, cancel, explicit retry, copy, and a new conversation. Once a valid turn is accepted, its text and files move into the conversation and the composer clears immediately, so the next draft can be written while a response arrives. A refused send leaves the draft intact. A later failure preserves the sent message, attachments and partial answer; explicit retry reuses that user turn without duplicating it or overwriting the next draft.

**Edit and resend** opens a separate editor for a previous user message. Sending appends an updated copy with its retained attachments and an origin label; the original messages and any existing composer draft remain intact. Cancelling the editor changes neither. Reasoning returned by the model is separate and collapsible. Answers render selectable Markdown with headings, lists, tables and highlighted code blocks. **Source** and copy controls preserve access to the original text; large documents use bounded source pages.

**Context** shows an estimated input-token budget and lets you explicitly choose the first user turn included in future requests. Earlier messages and files remain in saved history; they are not silently discarded or summarized. It also sets **Maximum response tokens** (16–32768), applied when the model advertises `max_tokens` support and capped by a reported provider output limit. The default reserve is 2048 tokens, reduced for smaller context windows. An estimate exceeding the advertised context limit blocks submission; media estimates are approximate and cannot predict every provider's decoding cost. These settings persist with the conversation. **Continue answer** appears when a completed response reports `finish_reason: length`; it sends a new explicit continuation turn while preserving the existing answer and current composer draft.

**Add files** accepts UTF-8 text/source files up to 256 KiB on text-compatible models, including Markdown, JSON, YAML, JavaScript and C. Text files have local readable previews and are sent as named text content, without requiring a provider's native file capability. Where supported, the picker also accepts PNG/JPEG/WebP/GIF images, WAV/MP3 audio, MP4 video, and PDF with native file input. Shared limits are 4 files, 8 MiB each and 12 MiB total per message, with the smaller text-file limit applied separately. Text in the composer is optional for an attachment-only message. Draft and sent files persist as binary IndexedDB records with references from their conversation; streamed checkpoints do not rewrite unchanged files. File payloads never enter localStorage/sessionStorage recovery markers, diagnostics or the PWA cache. PDF requests explicitly disable paid parser fallback. See [the rendering guide](docs/file-rendering.md) for extensions, preview limits and source copying, and [the multimodal guide](docs/multimodal.md) for media price guards and provider limitations.

The navigation sidebar contains **New conversation**, searchable history, Diagnostics and Settings. History separates **Chats** from **Archived**. Archive keeps a conversation available to inspect and restore; permanent deletion is offered for archived conversations and requires confirmation. Archived conversations are read-only until restored. History identifies each conversation by title, model, update time and message count. The composer shows **Unsaved changes**, **Saving…**, **Saved** or **Save failed**. **Export** saves a conversation and its attachments as a versioned JSON backup; **Import** opens a separate copy. Multiple tabs retain independent active conversations. Conflicting edits preserve both versions by saving a **Recovered copy**, with no automatic merge or overwrite. History remains browser-local, with no cloud sync. See [history.md](docs/history.md) for persistence, migration, capacity and recovery details.

Settings provides **System**, **Light** and **Dark** appearance choices, a session key, 100/150/200% text, deliberate offline mode, install where offered, and update checks. **Check allowance** explicitly retrieves the key's free-request allowance when the API reports it; no quota request is made at startup. Counts are advisory, stale observations are labeled, and health probes also consume inference requests. System is the initial appearance choice; an explicit preference persists locally. Both color schemes retain the muted neo-brutalist palette, readable borders and pastel popup headers. The model chooser, model details and diagnostics have distinct colored headings with small emoji cues and readable text labels.

The five popup graphics are bundled [Twemoji v14.0.2](https://github.com/twitter/twemoji/tree/v14.0.2/assets/72x72) PNGs, credited to Twitter, Inc and contributors under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). They total 4,354 bytes and render offline without an emoji font or JavaScript library. Full attribution and the upstream license are in `assets/emoji/ATTRIBUTION.md` and `assets/emoji/LICENSE-GRAPHICS`.

Diagnostics separates recorded errors from ordinary activity. Catalog entries reporting the observed `-1` unresolved-price marker are excluded from free selection rather than reported as broken schema entries; malformed prices still produce actionable errors. PWA inspections have a short summary with bounded expandable metadata; the inspection dialog retains its full Copy/Export report. Nothing in diagnostics is uploaded. API keys are redacted and prompts, answers, reasoning and upstream error bodies are omitted.

Readable application text is selectable across screens, dialogs, model information, history and tooltips. Drag to select with a pointer, or long-press text on touch screens, then use Copy or Ctrl/Command+C. Dialogs have their own selection scope, keeping Select all within the open dialog. Composer and other editable fields retain their usual selection, paste and keyboard shortcuts. The header subtitle is **Wrapper for Free Open Router Models**.

## Adaptive behavior

The layout uses available width and text scaling, with no device-name detection:

- **Compact (<600 logical pixels):** focused chat with a menu drawer containing history and utility actions, a model chooser dialog, tap-accessible details and a compact composer.
- **Medium (600–1099):** navigation rail with New conversation, History, Diagnostics and Settings; history, model selection and details open in overlays.
- **Expanded (≥1100):** persistent conversation-history sidebar with utility actions at the bottom; at ≥1420 an optional model-details panel.

The model selector above the conversation opens the model chooser without an adjacent information button. Details remain accessible inside the chooser and through the optional wide-screen model-details panel. The sidebar is dedicated to conversations and navigation; Diagnostics and Settings live at its bottom rather than in the app header. Switching conversation, starting another conversation and changing the selected model are guarded during an active response or history transition.

At 200% text, narrow medium widths use the compact arrangement and expanded sidebars collapse. Content, controllers, selection, draft and focus outlive layout branches. Long model lists are lazy; large dialog content scrolls. Details have pointer tooltips, keyboard focus previews and explicit information buttons. Controls expose Flutter semantics from startup. No decorative motion is used; platform reduced-motion behavior is respected by Flutter's standard controls. Resizing for the software keyboard keeps the composer in view.

## Architecture and ownership

```text
lib/main.dart                  runtime config, app startup, global error hooks
lib/app/                       app lifecycle/state and shared theme
lib/config/app_config.dart     typed policy, defaults and validation
lib/shared/transport.dart       replaceable HTTP interface, timeout, cancellation
lib/shared/diagnostics.dart     categorized errors, bounded sanitized log
lib/shared/platform*.dart      storage, connectivity, install/update/download ports
lib/shared/attachment*.dart    bounded file selection and platform adapters
lib/features/models/model.dart API DTO adapter and price/capability validation
lib/features/models/catalog.dart refresh, pagination, cache, selection changes
lib/features/models/health.dart  bounded observations, metadata, probes, backoff
lib/features/chat/             SSE, request/response adapter, conversation lifecycle
lib/features/documents/        UTF-8 formats, bounded Markdown/source views, syntax colors
lib/features/history/          versioned IndexedDB, incremental codec, conflict recovery
lib/presentation/              adaptive screen, chooser, details, utilities
assets/fonts/                  local Roboto files and upstream license
assets/emoji/                  five local Twemoji header graphics and attribution
web/                           minimal Flutter host, manifest, icons and PWA glue
tool/                          Dart-only release assembly, static serving, icons
test/                          deterministic model/chat/shared/widget tests
docs/                          detailed contracts, policy and verification
xops/                          shell/Python repository and make operations only
.agents/, .codex/, .github/    shared skills and client-specific agent adapters
```

No network or JSON parsing is performed in widgets. Configuration, transport, storage, diagnostics and platform interfaces are injectable. Adding another Flutter platform requires replacing the browser adapters; current non-web stubs support deterministic tests, not a native release claim.

## Configuration

`config/example.json` documents every option; `config/local.json` is ignored. The runtime file is network-only and excluded from service-worker caching. The session key is kept only in memory. Catalog, small preferences and bounded health/endpoint observations use localStorage. The immediate text recovery draft and active-conversation ID use tab-local sessionStorage; earlier localStorage recovery values are read only as migration sources. Conversation metadata and individual messages use IndexedDB, with immutable attachment bytes stored separately and referenced by ID. These are application-managed data, never service-worker cached. An explicit update waits for a durable history save under the existing conversation ID; it does not create a separate legacy localStorage session snapshot. Clearing browser site data can remove both history and offline assets.

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

Durations must be 1 second–30 days, backoff must be at least the cooldown, and the overall stream timeout must cover both its first-response and idle timeouts. `maxOutputTokens` must be 16–32768. Other validation ranges are explicit in `AppConfig.validate()`. Probes use their shorter probe deadline. Automatic content retries remain **zero**; health concurrency is capped at **two**. Catalog refreshes, endpoint checks and health probes are deduplicated. Cached health observations are scoped to API/key/policy and invalidated when meaningful model metadata changes. Catalog pagination, saved entries, message input and SSE frames also have bounds. Extra harmless configuration fields are ignored; wrong types produce a visible configuration diagnostic.

## API, PWA and troubleshooting

Official API and Flutter sources were verified on 5–6 October 2026. See:

- `docs/catalog.md`: pricing fields, pagination, quarantine and selection policy.
- `docs/chat.md`: endpoint metadata, observed health, probes, streaming and errors.
- `docs/multimodal.md`: supported local files, price guards, picker behavior and limits.
- `docs/pwa.md`: installation, browser differences, exact cache/update strategy.
- `docs/history.md`: local conversation persistence, archive, restore and deletion.
- `docs/follow-up-verification.md`: checks for the wfform/history/theme/navigation follow-up.
- `docs/verification.md`: preserved initial implementation evidence and measurements.

An omitted required token price never means zero. The API currently omits optional request prices; the app preserves that fact and enforces a zero request-price cap on the server. Non-text listings with incomplete native-unit metadata are inspect-only candidates, not a promise of free media generation.

On authentication or account errors, update the key or account settings. Rate limits show cooldown/retry information; use explicit retry after it expires. A provider failure does not switch models. A failed catalog refresh retains the last valid catalog and time. Schema diagnostics name the field, expected type and observed type; adapter changes stay localized. Arbitrary API changes cannot be repaired automatically.

A browser reporting online does not prove API reachability. Opaque fetch failures are labeled network failures, not automatically blamed on CORS. Check the browser network panel for the actual cause. The app adds no proxy. HTTPS or localhost and a successfully cached first release load are required for offline startup. If storage is blocked/full, the app continues in memory and reports reduced reload recovery.
