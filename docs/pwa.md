# PWA, offline use and updates

The installed app keeps manifest `id: ./`, relative start/scope and existing
`free-model-studio-*` cache namespaces. Renaming the product must not discard installed
identity or stored work. A new scheme/host/port is a separate origin: export/import
history when moving from localhost or the former GitHub URL to **wfform.com**.

## Build and serve

```sh
dart run tool/build.dart
dart run tool/serve.dart --port=8765
```

Use Flutter **3.38.10 / Dart 3.10.9**. The builder disables Flutter's generated worker
and assembles this app's explicit verified shell. A raw Flutter build alone does not
provide the release cache/update contract. The Dart host serves static files only.
HTTPS or localhost is needed for service workers; first load must complete online.
Browser install prompts and OS installation vary and require device verification.

## Cache contract

The builder hashes the package version, sorted asset paths/content and worker policy.
Public releases/tags use SemVer; hashes are internal cache/integrity identities.
Published files use flat paths, while `?build=<sha256>` cache keys identify generations.
Config-only changes do not invalidate the shell.

The worker verifies byte size and SHA-256 for every allowed static asset, reuses
verified unchanged bytes and marks completion only after the whole shell succeeds.
Incomplete/corrupt generations cannot activate. A bounded bypass refetch can recover a
bad response; it is not an inference retry. Cache only static shell files, never API,
authenticated requests, runtime config, keys, prompts, responses or user attachments.

Keep current/preceding generations and those needed by open tabs. Unknown sleeping
clients defer cleanup. Legacy cached URLs remain readable during migration; missing
old bytes require an explicit update rather than mixing old code with new assets.
Browser eviction can still remove offline data.

## User behavior

Offline mode keeps the installed shell, validated cached catalog and local history;
remote chat/tools are unavailable. A browser online hint does not prove API reachability.
Reconnect refreshes the catalog without resending content.

A waiting update stays pending until **Save & update**. Wait for file selection,
active requests and history transitions, then require a successful durable checkpoint
before activation/reload. Restore the same draft/conversation identity. No automatic
reload or tool/inference replay. Use Flutter's standard keyboard avoidance; installed
phone keyboard behavior needs real-device testing, not viewport emulation alone.

Settings' cache inspection reads bounded cache keys/completion counters and runtime
metadata, never cached private bodies or credential values. Fetch counters and
Resource Timing are observations, not proof of wire transfer size or startup speed.

## Checks

Run `make pwa.verify` and relevant `test/shared/pwa_*` tests. In a release browser:
load A online, reload offline, install changed B while A remains open, apply B
explicitly, verify drafts/history and old-tab lazy assets, then inspect cache cleanup.
Test install/keyboard on actual target devices. See [performance](performance.md) and
[CI/CD](guides/CI_CD.md) for measurement and public deployment boundaries.
