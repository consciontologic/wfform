# Performance measurement and release updates

This application separates measured artifact sizes, deterministic workload timings, and actual browser observations. None alone is evidence of frame-rate or end-to-end startup improvements. The performance changes recorded here used the existing Flutter/Dart stack and minimal JavaScript bootstrap/service worker without adding an application dependency. Later scaffold and rendering additions are described in the [architecture](code/ARCHITECTURE.md) and [file-rendering guide](file-rendering.md); the historical measurements below do not measure those later changes.

## Highlight work during content updates

Version 0.2.2 retains one highlighted `TextSpan` per mounted code block. Source,
language and light/dark brightness invalidate it; unrelated rebuilds reuse it.
The existing 180 ms document preview cadence therefore avoids tokenizing the
same visible source for every content update. Copy still uses the latest full
source, and the final preview flush shows the latest content. The cache lives
with its widget and does not retain every prior message or source revision.

A deterministic fixture supplied 20 updates 32 ms apart over 640 ms. Generated
highlight-tree identities fell from 21 before the change to four afterward
(initial plus three updated previews), with final content also asserted. This
measures avoided parsing/span allocation in the controlled workload, not phone
FPS, browser frame time or perceived smoothness. See the
[0.2.2 report](reports/mobile-keyboard-verification.md) for executed checks and
the separate installed-PWA keyboard issue.

## Repeatable measurements

Capture a read-only baseline before rebuilding:

```sh
dart run tool/measure.dart --directory=build/web --output=outputs/performance-before.json
```

Build separately from the running release and compare:

```sh
dart run tool/build.dart --output=work/performance-release
dart run tool/measure.dart --directory=work/performance-release --compare=outputs/performance-before.json --output=outputs/performance-after.json
# Reassembling unchanged bytes must keep the same release ID:
dart run tool/build.dart --skip-build --output=work/performance-release
```

The measurement tool records every allowed shell asset's byte length, SHA-256 and offline gzip-level-6 estimate, along with the Dart/OS environment. Configuration, source maps, historical release directories and user data are excluded. Comparison reports changed bytes and potential cache reuse by exact path/content hash. It is not a network trace. The local host does not gzip responses, so gzip estimates must not be presented as actual transferred bytes.

A bounded SHA-256 workload uses a generated 1 MiB byte fixture, two warmups and seven timed samples. Its median/min/max measure Dart VM build-tool CPU work, not Flutter UI, rendering, attachment decoding or browser WebCrypto speed. Run on the same machine/runtime and close unrelated heavy work when comparing timings; do not infer improvement from small noisy changes.

For browser startup, inspect the app's offline-cache diagnostics immediately after a normal reload and save the release ID, controller/cache state, resource-request summary and JS transfer/body sizes. Compare the same viewport, cache condition and interaction sequence. Browser resource buffers and service-worker/HTTP caches affect these observations; a zero transfer size is not proof of zero work. Record cold and warm observations separately. Do not infer a frame-rate result from widget tests.

## Content-derived build identity

`tool/build.dart` compiles Flutter into a temporary directory. It hashes the package version, sorted path/content manifest and worker policy, then stamps an internal build ID into the host and bootstrap. Timestamps, local credentials and generated metadata are excluded. Unchanged inputs produce the same ID and worker; configuration-only changes do not invalidate the shell. Public release names and tags use SemVer, such as `1.0.0`. The hash is an integrity/cache identity, not the release or package name.

The bootstrap uses documented `entrypointBaseUrl`, `assetBase` and `canvasKitBaseUrl` settings. Main JavaScript, Flutter assets, fonts and CanvasKit use flat physical paths. The bootstrap URL includes `?build=<sha256>`, and the worker stores verified files under the same build query in separate cache generations. A bootstrap message identifies the build for that tab's unversioned lazy asset requests. The visible app identity, manifest ID/start URL/scope and original `free-model-studio-` cache namespace remain unchanged. `--base-href=/studio/` supports a full build for a static-host subdirectory; host that directory at the matching trailing-slash URL. Deterministic tests check relative resolution. The standard local Dart host serves its chosen directory at `/`, so use the default base there.

The local builder assembles a complete flat site beside the target, then replaces the target directory. If the replacement rename fails, it restores the previous directory. Compilation or preparation failures leave the serving directory unchanged. No historical release directory is shipped. The website publisher validates all incoming assets and destination ownership before updating managed files; it removes owned legacy `__releases` files and leaves unrelated files alone. GitHub Releases holds versioned downloadable packages, while installed clients retain older verified shells in browser storage.

```sh
# Publish the final coordinated build, then serve it:
dart run tool/build.dart
dart run tool/serve.dart --port=8765
# Optional full build for deployment at a static-host subpath:
dart run tool/build.dart --output=work/subpath-release --base-href=/studio/
```

## Verified incremental precaching

The installer reads an explicit asset manifest. At most three assets are prepared concurrently. For each one it looks for the same path in recent release caches, including the preceding legacy layout, and verifies byte length and SHA-256 before reuse. Only unavailable or changed content goes through Fetch; the worker verifies returned bytes before storing them. A failed size/hash/status check allows one bounded cache-bypass refetch, so an explicit later update check can recover a repaired server asset even if an HTTP cache contains the corrupt response. A completion marker is written after all verified assets are stored. An incomplete or hash-mismatched install aborts, removes its incomplete generation and reports an actionable PWA error; it never becomes active.

The cache marker contains content-free install counters: `reusedAssets`, `reusedBytes`, `fetchedAssets`, `fetchedBytes`. “Fetched” counts bytes obtained through Fetch, not necessarily network bytes, because the HTTP cache may satisfy the request. Compare those counters with the browser's resource/network observations when making transfer claims.

No API, authenticated request, configuration, chat response, prompt or attachment enters the worker's response cache. Fetch-time fallback is network-only and verifies the expected content when metadata is available; it never adds runtime responses to Cache Storage. Authorization-bearing requests and queries other than a single valid `build` hash bypass the worker. The local static host and repository nginx configuration use `no-store` for the flat files, worker and configuration; the service worker owns offline generation caching.

## Older tabs and cleanup

An active tab identifies its release through a bootstrap message. A separate `free-model-studio-clients-v2` cache holds only browser-client IDs and release hashes, not user/session content. Cleanup retains the current release, one preceding release and every release reported by a still-open tab. Closed clients' small metadata records are removed. A sleeping, unrecognized or pre-versioned tab defers cleanup until it identifies itself or closes. This deliberately trades temporary extra shell storage for keeping an older page intact.

After activation, the new worker recognizes both old `__releases/<hash>/` URLs and flat build-keyed cache entries. Existing tab metadata keeps unversioned lazy requests with that tab's cached generation. Legacy unversioned pages can read the preceding legacy cache until they reload. The server now contains only the current flat site. If an old generation has been evicted, or a missing old asset no longer matches the current server bytes, the worker reports the unavailable asset instead of mixing builds. Save work and explicitly reload or use **Save & update** to move to the current build. Browser storage can be evicted and is not a permanent offline guarantee.

## Deterministic and browser checks

```sh
flutter test test/shared/pwa_build_test.dart test/shared/pwa_fixture_test.dart test/shared/pwa_identity_test.dart test/shared/platform_test.dart --reporter expanded
flutter analyze tool test/shared/pwa_build_test.dart test/shared/pwa_fixture_test.dart test/shared/pwa_identity_test.dart test/shared/platform_test.dart
node --test test/shared/pwa_worker_test.mjs
```

These tests cover hash vectors, stable/revised identity, post-stamp manifest integrity, secret/config exclusion, flat publication, subpath URL resolution, comparison arithmetic, install/fetch policy and app identity. The Node test executes the worker script with in-memory browser API stand-ins: it checks verified installation, legacy-cache reuse and refusal to substitute an uncached old build. This is deterministic protocol coverage, not an actual browser worker or a quota-failure check.

Browser fault/update procedure:

1. Load release A fully online, type a draft, and inspect its complete shell/cache marker. Reload offline; verify startup, cached catalog labeling and disabled remote chat.
2. Keep that tab open, publish release B with a real shell change, and inspect B's waiting installation and reuse counters. A must remain usable before activation. Apply B deliberately and verify saved state, the new build ID and its flat cache keys.
3. Keep a second A tab alive during activation, then exercise its lazy icons/fonts and available UI offline. Verify that B activation did not substitute B assets into A. Close A and inspect pruning after the next release-identification event/reload.
4. Reassemble B without source changes. Check for update: release ID and worker bytes must stay unchanged, with no new waiting release.
5. On a separate test origin/output, publish a new release whose unique changed asset is missing or deliberately corrupted. Installation must fail, expose a diagnostic and preserve the complete active release. Restore the asset and explicitly check again. Test interrupted downloads similarly; do not damage the working origin to manufacture this check.
6. Where browser tooling allows it, deny storage or exhaust a disposable origin's quota. Verify a failed installation never activates an incomplete cache and existing draft/history recovery remains available. This cannot be established by manifest tests alone.

Record performed cases and unperformed limitations separately in `outputs/performance-report.md`. Existing successful text or image inference is not evidence of this worker's update behavior.

`tool/pwa_fault_fixture.dart` prepares a separate static-file origin for repeatable missing/corrupt-asset checks. It stages a harmless main-script comment change before breaking the new flat asset and supports exact-byte repair. Existing browser caches retain the previously loaded generation; the fixture host contains only its current revision. Its host must use `--isolated-config` so the project-local development key is never mapped into the fixture. The prepared port-8766 workflow, commands and expected UI observations are in `outputs/pwa-fault-browser-guide.md`. No fixture command modifies the active `build/web` or port-8765 browser history.

## Sources checked on 2026-10-06

[Flutter initialization](https://docs.flutter.dev/platform-integration/web/initialization) documents the bootstrap base-URL settings and passing configuration to `initializeEngine`. The installed Flutter 3.38.5 loader/engine source was also inspected. [MDN service-worker lifecycle](https://developer.mozilla.org/en-US/docs/Web/API/Service_Worker_API/Using_Service_Workers) and [explicit activation](https://developer.mozilla.org/en-US/docs/Web/API/ServiceWorkerGlobalScope/skipWaiting) describe install/wait/activation behavior. Build-keyed cache generations and per-tab build metadata keep cached resources tied to the running page during activation.
