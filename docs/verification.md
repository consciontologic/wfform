# Verification record

Executed on **5–6 October 2026**, Europe/Istanbul, in the requested workspace. Flutter 3.38.5 stable, Dart 3.10.4; browser verification used the Codex in-app Chromium browser at `http://localhost:8765`. No backend or API proxy was used.

## Automated checks

- `dart format --output=none --set-exit-if-changed lib test tool`: clean.
- `flutter analyze`: no issues.
- `flutter test --reporter=expanded`: **124 tests passed, 1 skipped**; the public-network catalog test is opt-in and skipped by default. The final command transcript is saved alongside this report.
- `flutter test --dart-define=RUN_LIVE_CATALOG=true test/models/catalog_test.dart --plain-name 'opt-in live public catalog adapter check'`: executed separately; **1 test passed** against the real public API using the final adapter.
- `dart run tool/build.dart`: release build and PWA assembly succeeded. This runs `flutter build web --release --no-web-resources-cdn --pwa-strategy=none` and assembles the explicit shell cache.

Unit tests cover exact free-price eligibility (including decimal underflow), absent/malformed/unknown/conditional prices, added/removed/renamed/wrong-type fields, pagination and quarantine, cache freshness, selection invalidation, health TTL/deduplication/concurrency/cooldowns/Retry-After, error categories, redaction and bounds, UTF-8/SSE boundaries, cancellation, truncated/error streams and explicit retry. Lifecycle tests cover blocked storage during updates, offline cancellation, and catalog invalidation during a pending preflight.

Actual StudioApp widget tests cover compact/medium/expanded navigation, chooser search, incompatible disabled entries, keyboard selection, accessible model and diagnostic technical details, accessible PWA inspection reports, loading/empty/error/stale/offline/reconnect states, persisted offline preference, 320px at 200% text, reduced-motion settings, simulated software-keyboard insets, and preserved draft, selection, focused composer and single active request across 390→768→1440→390 resizing. These are deterministic controlled-transport checks, not live-service evidence.

The Flutter build emits an SDK font tree-shaking warning mentioning `packages/cupertino_icons/CupertinoIcons`; this app uses Material icons and locally bundled Roboto, which rendered correctly in the browser. The release build succeeds. No native, Wasm, or store release is claimed.

## Real API and browser observations

The browser fetched the public catalog directly with `GET /api/v1/models?output_modalities=all`. The final live adapter check observed 648 entries, 67 inspectable zero-token-price candidate listings, 17 chat-compatible models and 7 quarantined negative/variable-price router entries at 2026-10-05T21:21:10Z. Counts are dated observations, never test assertions. After the final safety refinement, only text-only output models can be selected; models advertising text plus audio/image remain inspect-only because native output fees cannot be guaranteed. Required missing/malformed token prices are never treated as zero; omitted optional request prices remain unreported and requests carry a zero request-price routing cap.

The example `nvidia/nemotron-3-super-120b-a12b:free` was found in the live catalog, selected through the UI, and checked using endpoint metadata plus a tiny probe. The supplied local development token authenticated successfully. The app streamed a real response to the strawberry question, with returned reasoning available separately; the answer stated **3** occurrences. Initial sanitized observations:

| Operation | HTTP status | Observed duration |
|---|---:|---:|
| Catalog refresh | 200 | 310 ms |
| Endpoint metadata | 200 | 256 ms |
| Selected-model probe | 200 | 1,102 ms |
| Full chat operation, including preflight | 200 | 4,286 ms |

Provider was reported as `Nvidia`; correlation IDs are in `live-diagnostics.json`. A second successful live request after the offline/reconnection check exercised keyboard submission and credential recovery (12,587 ms including an 842 ms probe). Only two live user-content attempts and their selected-model probes were made by the UI verification; no startup mass probing or paid fallback was used.

Direct browser catalog, endpoint and authenticated streaming requests succeeded. Therefore no CORS blocker was observed for these requests in this browser/origin. This does not establish that every browser, endpoint, model or account will always succeed. Opaque failures are still classified as network failures unless evidence identifies CORS.

Browser layout checks used 390×844, 768×1024, 1440×900 and 320×740 with 200% app text. A live streaming request continued through desktop→phone resizing, then displayed its completed conversation at tablet width. Draft and focused composer survived subsequent resizing. Touch-equivalent click access, keyboard submission, model details, reasoning disclosure, settings and diagnostics were exercised. Accessibility-tree inspection is not a screen-reader listening test. A transient browser screenshot-tool timeout recovered on the next documented observation; it was not an application exception.

`desktop-final.jpg` captures the final release; `tablet-chat.jpg` captures the successful live strawberry response. Browser inspection caught missing accessibility labels on selectable technical JSON; those labels were added and covered by two widget regressions before the final build.

## PWA evidence

The release manifest and original PNG icons passed deterministic format/dimension checks. In-browser inspection reported a secure localhost context, an **activated** controlling `service_worker.js`, explicit shell-cache generations and **zero** cached configuration, API, authorization-bearing, query-string or cross-origin requests. `pwa-inspection.json` and `pwa-inspection-final.json` record that metadata; they contain no cache response bodies or secrets.

An actual release update was installed into the waiting state while the old UI stayed open. The explicit **Save draft & update** flow activated it and restored the chosen model, completed conversation and unsent draft. There was no automatic reload or inference resend. Update-blocking during a pending request and storage failure is separately covered by deterministic lifecycle tests.

For a real shell outage check, the Dart static host was stopped. `curl --max-time 3 -I http://localhost:8765/` returned connection refused. A normal browser reload still rendered the Flutter shell, local fonts, preserved selected model and draft, cached-catalog indicator, and disabled remote chat. The app's persisted **Work offline** control suppressed remote operations. `offline-shell.jpg` captures this state. The host was then restarted; turning Work offline off refreshed the catalog, recovered the network-only configuration and allowed the second successful live request.

This verifies shell retrieval without its origin server. **Whole-browser network emulation was unavailable through the installed browser-control surface**, so this was not a claim that the operating system's Internet connection was disabled. Actual browser connectivity events, stale refresh failure and reconnection behavior also have controlled widget/lifecycle coverage.

The embedded browser did not expose `beforeinstallprompt` (`installPromptAvailable: false`). Manifest and service-worker/offline readiness were verified; **an OS-level installation was not performed**. Chrome/Edge standalone install, Safari/Add to Home Screen, Firefox, physical touch devices and native software keyboards remain unverified. Instructions for those checks are in `docs/pwa.md`.

## Release observations and limits

The final release assembly contains **23 precached shell assets, 17,301,076 uncompressed bytes**. `main.dart.js` is **2,615,171 bytes**. The shell includes both browser-specific CanvasKit variants and local fonts to support offline startup across compatible browsers. These are uncompressed file sizes, not transfer-size or performance-improvement claims.

The catalog adapter reported **one page** for the observed live refresh. The browser Resource Timing snapshot recorded two catalog resource entries since navigation and no endpoint/chat entries before a user check; it can include browser accounting and is not a server request ledger. The deterministic controller tests verify refresh deduplication and no bulk startup probes. Cached JavaScript showed zero transfer bytes; the inspector explicitly identifies cache/timing ambiguity. No controlled cold-start benchmark or cross-device speed claim was made.

Conversation messages render as selectable plain text; Markdown is not rendered. Draft and selection persist across ordinary reloads. Conversation history stays in runtime memory except for an explicitly accepted update snapshot, so an ordinary reload starts a new conversation. Site storage eviction can remove offline data. Unsupported multimodal outputs and dynamic model routers are inspect-only. Provider health is a recent observation, not a guarantee.

Configuration, source architecture, exact setup commands, official API sources and all policy defaults are documented in README.md and docs/catalog.md, docs/chat.md, docs/pwa.md. The supplied key remains only in ignored local configuration and the ignored network-only release config copy.
