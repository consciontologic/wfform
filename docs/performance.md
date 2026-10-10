# Performance measurement

Keep artifact size, deterministic CPU work, browser startup and rendering measurements
separate. A smaller fixture workload does not prove phone FPS or end-to-end speed.

## Repeatable commands

```sh
dart run tool/measure.dart --directory=build/web --output=outputs/performance-before.json
dart run tool/build.dart --output=work/performance-release
dart run tool/measure.dart --directory=work/performance-release --compare=outputs/performance-before.json --output=outputs/performance-after.json
flutter test tool/history_benchmark.dart --reporter expanded
```

The asset tool records path, size, SHA-256, offline gzip estimates and environment,
excluding config/source maps/private data. Its comparison estimates exact-byte reuse,
not network traffic. The local Dart host does not gzip, so do not call estimates actual
transferred bytes. Its bounded SHA workload measures Dart VM build-tool CPU only.

The history benchmark uses two decoder-validated synthetic 6 MiB PNGs and ten streamed
checkpoints, comparing legacy full-record encoding with normalized changed-row
preparation. It writes `outputs/history-performance.json`; measure on the same runtime
and machine, retain raw samples and distinguish modeled writes from real IndexedDB
latency. Historical one-run timings are not a current performance promise.

A historical 2026-10-06 VM experiment measured median checkpoint preparation at about
105.6 ms for whole-record encoding versus 2.1 ms for normalized updates; modeled ten-
checkpoint payloads fell from 167.8 MB to 11.5 KB after storing 12.6 MB of media once.
This supports avoiding unchanged-media rewrites in that fixture, not a current browser
speed claim. Re-run the command above when evaluating another workload/runtime.

## Implemented work reduction

Normalized history stores immutable attachment bytes once and changes individual rows.
The history list loads summaries, not every message/media body. Streaming content
notifications batch at 32 ms; document previews at 180 ms with terminal flush. A mounted
code block reuses its highlighted span until source/language/brightness changes.
These bound work and memory; verify real rendering before claiming perceived speed.

PWA assembly keeps stable content-derived identity for unchanged inputs and validates
asset size/hash before reuse. Install counters count reused/fetched bytes, where Fetch
may still be served by HTTP cache. [PWA](pwa.md) owns generation retention/update rules.

## Browser experiment

Fix browser/version, viewport, cache condition and interaction sequence. Record cold
and warm runs separately, build identity, worker/cache state, Resource Timing and
trace/frame evidence. Resource buffers may omit requests and zero transfer bytes are
ambiguous; worker install traffic is not the page's request ledger.

For an update comparison: keep release A open, publish changed B, inspect B's waiting
install/reuse counters, apply it explicitly and verify saved work; exercise A's lazy
assets from another still-open tab before cleanup. Do not substitute deterministic
worker mocks for this browser test. Store reusable research in [reports](reports/README.md)
and raw run outputs in ignored storage.
