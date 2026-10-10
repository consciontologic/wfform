# Development setup

Use Flutter **3.38.10 / Dart 3.10.9**. Make targets prefer ignored
`.local/flutter-sdk`; for direct commands, add that SDK's `bin` to your process PATH.
Run `make help` for project commands.

```sh
make deps
# Fresh checkout only; preserve an existing config:
cp -n config/example.json config/local.json
# Set your own key locally, or save it in Settings.
dart run tool/build.dart
dart run tool/serve.dart --port=8765
```

Open **http://localhost:8765**. Keep the same origin to retain browser history.
For UI iteration use `flutter run -d chrome --web-port=8080`; save the key in Settings
because Flutter's development server does not serve ignored runtime configuration.
Test offline/update behavior on a release build, not the development server.

## Checks

```sh
make verify
make repository.check
# Real Chromium storage checks, using isolated databases:
CHROME_EXECUTABLE=/path/to/chrome flutter test --platform chrome test/history/browser/indexeddb_checks.dart
# Optional public catalog request, no credentials or inference:
flutter test --dart-define=RUN_LIVE_CATALOG=true test/models/catalog_test.dart --plain-name 'opt-in live public catalog adapter check'
```

`make verify` includes format, analyzer, deterministic app/companion/PWA tests and
repository hygiene. Wrap long/risky commands in `xops/agent/safe-run.sh TAG -- COMMAND`;
read its log before retrying failure. Live keyed inference, real browser behavior,
native Windows execution and public publication are separate evidence.

## Configuration

[config/example.json](../../config/example.json) lists defaults and
[AppConfig](../../lib/config/app_config.dart) owns validation. `config/local.json`
is ignored/network-only and must not enter public packages, images or PWA caches.
Credentials served to a browser are visible to its user.

An explicitly saved Settings key overrides runtime config; clearing it stores an empty
override. Failed persistence is visible, and failed reads keep the connection disabled
until the key can be saved. MCP bearer tokens are session-only. Browser preferences,
catalog and bounded health metadata use localStorage; [history](../history.md) owns
IndexedDB and tab-local draft recovery.

| Setting group | Defaults |
|---|---|
| API | `https://openrouter.ai/api/v1`, empty key; HTTPS except loopback HTTP |
| Ordinary/probe deadlines | 90 / 25 seconds |
| Chat first/idle/overall deadlines | 90 / 45 / 300 seconds |
| Health/endpoint/allowance TTL | 300 / 1800 / 300 seconds |
| Cooldown/backoff | 15 / 300 seconds; longer server waits win |
| Catalog TTL/size | 86400 seconds / 8,000,000 bytes |
| Context reserve | 2048 tokens; local estimate until explicitly overridden |
| Content bounds | 80 messages, 120,000 response characters |
| Diagnostics | 100 records, 2,000 characters per detail field |

Durations must be 1 second–30 days; overall stream timeout covers first/idle limits.
Output reserve is 16–32768; other ranges are in `AppConfig.validate()`. No automatic
content retries. Refreshes/probes deduplicate; health concurrency is two.

## Other guides

[Gitflow](GITFLOW.md) · [CI/CD](CI_CD.md) · [Docker](DOCKER.md) ·
[CodeGraph](MCP_SETUP.md) · [Codex](CODEX_SETUP.md) ·
[Agent workflow](AGENT_OPERATING_MODEL.md) · [Client notes](MODEL_PROFILES.md)

For network failure, inspect the browser before asserting CORS. No proxy is added.
Storage failures preserve in-memory work but do not claim durable recovery; see
[PWA](../pwa.md), [catalog](../catalog.md) and [chat](../chat.md).
