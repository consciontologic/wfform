# PWA and platform behavior

The visible application name is **wfform**. The manifest's existing `id`, `start_url` and `scope`, and the internal `free-model-studio-*` service-worker cache namespace are intentionally preserved. A rename therefore does not create a second installed-app identity or discard the previous release's offline shell. Existing local storage keys likewise remain available for recovery.

The Flutter/Dart package is **`wfform`**, including all `package:` imports. **`com.wfform`** is Android's namespace/application ID and iOS's Runner bundle identifier in the native host projects; see [native setup and verification limits](native-platforms.md). The manifest `id` stays `./`: replacing it with `com.wfform` would identify a different installed web app. This change preserves origin-scoped conversations, drafts, settings and existing PWA installation identity.

Naming rules checked on 2026-10-06 against the [Dart pubspec name specification](https://dart.dev/tools/pub/pubspec#name), [Flutter Android application ID guidance](https://docs.flutter.dev/deployment/android#application-id), and [Web Application Manifest identity specification](https://www.w3.org/TR/appmanifest/#id-member).

Verified documentation on 2026-10-05. Flutter 3.38.5 / Dart 3.10.4 is the tested SDK. Flutter's current documentation does not promise a generated production service worker; this app owns the small worker and verifies the release output. The SDK's older generated worker is explicitly disabled.

## Build and serve

```sh
flutter pub get
dart run tool/build.dart
dart run tool/serve.dart --port=8765
```

Open `http://localhost:8765`. The Dart host serves static files on loopback only. It is a development convenience, not an API server or proxy; OpenRouter requests go directly from the browser. It supplies WASM/font MIME types, immutable HTTP caching for content-addressed release paths, and `Cache-Control: no-store` for root aliases, the worker and configuration. It maps the single `/config/local.json` URL to the ignored project-local file when present; otherwise the release copy is served. No secret is printed. For deployment, use any HTTPS static host with correct MIME types and no-cache/no-store headers on the worker and network-only configuration.

`tool/build.dart` invokes `flutter build web --release --no-web-resources-cdn --pwa-strategy=none` with a temporary output directory, then publishes a complete immutable release and its root launch pointers. SHA-256 hashes of the shell and worker policy determine the version; unchanged builds retain their identity. An explicit manifest lists shell files and local CanvasKit assets. Ignored runtime configuration is copied separately into `build/web/config/local.json` and is excluded from hashes and caches. The builder refuses assets containing an OpenRouter API-key pattern. Do not pass API keys using `--dart-define` or add configuration to Flutter assets. Browser-delivered credentials remain visible to that browser's user.

`dart run tool/build.dart --skip-build` reassembles existing compiled output and copies runtime configuration. Unchanged content produces the same worker; this is a stability check, not a forced update. It is not a substitute for rebuilding changed Dart/host code. A full build is required when first migrating from the earlier unversioned bootstrap. `--output=work/performance-release` produces a separate release without modifying the running output; `--base-href=/studio/` supports a full static-host subpath build. `flutter run -d chrome` remains useful for UI development; custom offline behavior is enabled only in release mode.

## Cache strategy

The install transaction precaches only an explicit build-time allowlist: HTML, Flutter JS/bootstrap, locally shipped CanvasKit, icons, manifest and Flutter assets. Each file's length and SHA-256 are verified; unchanged files can be reused from an earlier shell cache. A completion marker is written last, and failed installs remove their incomplete generation. The worker's fetch handler accepts only same-origin GETs in a known release manifest and bypasses authorization-bearing requests, query strings and all `/config/` paths. There is **no runtime response-cache population**, API cache or chat cache. Small internal completion/client-release metadata is separate from responses and contains no application content. OpenRouter and runtime configuration always require the network.

The catalog feature separately stores its normalized last successful public catalog, timestamp and selection in local storage. Small preferences also use local storage; draft-recovery checkpoints are tab-local, and durable conversation history uses IndexedDB. These are application-managed records and are not service-worker cached. New safe updates await the durable history save and retire the older unscoped session/draft snapshots instead of creating new legacy snapshots. Archive, restore and deletion are described in `history.md`. Offline availability depends on the browser retaining site storage and on at least one completed online release load. Clearing storage, eviction and private browsing can remove cached data. An offline indicator reflects the browser connectivity hint; a browser reporting online cannot guarantee that OpenRouter is reachable.

The explicit Work offline setting persists across reloads, suppresses catalog/probe/chat requests and cancels active remote work. On reconnection the app refreshes the catalog and reloads network-only local configuration if an offline startup could not obtain it; it never automatically resends a chat message.

Shell assets are cache-first and pinned to immutable `__releases/<hash>/` URLs. A new release installs in the background and waits. Update detection is available on launch and through the explicit update-check control; there is no polling. The app saves history/drafts before applying an update and prevents refresh during an active chat request or file selection. Only user-triggered activation sends `APPLY_UPDATE` and reloads; other tabs are not automatically reloaded. Cleanup retains current, previous and any releases still used by open tabs; an unidentified legacy/sleeping tab defers deletion. Build publication places complete immutable assets before replacing launch pointers. See [performance.md](performance.md) for exact reuse, cleanup, measurement and deployment-retention rules.

## Installation and browser differences

A valid manifest supplies application identity, start URL, standalone display and original 192/512 pixel icons, including maskable variants. `tool/icons.dart` generates the bracketed conversation mark with standard Dart PNG encoding; it adds no runtime dependency. The host HTML supplies search/sharing metadata, readable product/startup text and a link to a small static About document. Flutter removes the startup surface when ready; all application UI and behavior remain Dart/Flutter. Minimal worker JavaScript supports the web platform. See [SEO metadata](seo.md) for the static document boundary and indexing limits.

For publication use `make build.public`, which excludes local configuration even if `config/local.json` exists. The GitHub [CI/CD workflow](guides/CI_CD.md) validates the public release and preserves prior immutable assets in the destination repository. `about.html`, `robots.txt` and `sitemap.xml` are also content-hashed shell assets. They contain public product information only.

Service workers require HTTPS or a trusted localhost origin. Plain LAN HTTP generally does not qualify. Chromium can expose an Install button via `beforeinstallprompt`; availability also depends on existing installation and browser policy. Safari uses its Share / Add to Home Screen or Add to Dock flow and does not expose the Chromium install event. Firefox installation UI varies by platform. A hidden Install button is not sufficient evidence that a manifest is invalid. Offline chat is explicitly unavailable; cached catalog information remains inspectable.

## Verification procedure

1. Build and serve the release. Load it online and wait for `navigator.serviceWorker.ready` in browser developer tools. Check that the manifest and icons load and the app's install control is offered where supported.
2. Inspect Cache Storage: the `free-model-studio-*` cache must contain only static shell URLs; no `/config/`, OpenRouter URL, authorization, prompt or chat response belongs there.
3. Choose a model and type a draft. Set the browser offline, then reload normally (not bypass-cache force reload). The shell and cached catalog must render, the draft must survive, the catalog must be marked stale/offline, and remote chat must be disabled.
4. Reconnect. Refresh the catalog and verify current API data replaces the stale view.
5. Keep the page open with a draft, make a real shell change and run a full release build, then Check for update. A waiting update must appear without automatically reloading. Apply it; verify draft, selection, session and attachments survive. While chat or file selection is pending, the UI must prevent applying it. Reassemble unchanged content separately: it must retain its hash and produce no false update.
6. Test install metadata separately from an actual browser/OS installation. Record which were performed; do not infer installation from an offline-cache pass.

The verification report records the actual browsers and outcomes. Manifest/unit tests alone do not prove installation, offline reload or update behavior.

## Sources

- [Flutter web initialization](https://docs.flutter.dev/platform-integration/web/initialization): custom bootstrap and web startup.
- [Flutter web FAQ](https://docs.flutter.dev/platform-integration/web/faq): current web deployment/service-worker behavior.
- [Flutter service-worker removal announcement](https://groups.google.com/g/flutter-announce/c/0Vv-j_TyrdI): custom release asset traversal and worker ownership.
- [MDN service worker lifecycle](https://developer.mozilla.org/en-US/docs/Web/API/Service_Worker_API/Using_Service_Workers): installation, waiting and activation.
- [MDN PWA installability](https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps/Guides/Making_PWAs_installable): manifest requirements and browser differences.
- [MDN skipWaiting](https://developer.mozilla.org/en-US/docs/Web/API/ServiceWorkerGlobalScope/skipWaiting): explicit waiting-worker activation.

## In-app offline-cache inspection

Settings offers an explicit offline-cache inspection. The browser adapter reads service-worker registration/controller states and counts request keys in this application's cache generations. It reports counts of configuration paths, API paths, authorization-bearing requests, query-bearing requests and cross-origin requests as possible cache-policy violations. It does not read cached response content, header values, API credentials or URL queries. Only application-owned generations are inspected, with bounds on exceptionally large damaged storage.

The same snapshot aggregates the browser's Resource Timing entries since the current navigation: same-origin/configuration request counts, OpenRouter catalog/endpoint/chat counts and loaded same-origin JavaScript transfer/body sizes. These are observations from the browser's bounded timing buffer, not an assertion that every request since startup was retained. Service-worker installation requests are not included in the page's resource buffer, and cached delivery or timing restrictions may report zero bytes. Inspect immediately after launch for startup observations; later inspections include subsequent interactions. The snapshot can be recorded in the normal sanitized diagnostics surface and exported without conversation content.
