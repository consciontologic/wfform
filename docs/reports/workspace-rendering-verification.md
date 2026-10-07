# Workspace, nginx and file-rendering verification

Verified 2026-10-06 with Flutter 3.38.5 and Dart 3.10.4 on Linux. This report covers the six-part workspace/scaffold/credentials/documentation/container/rendering request. It does not relabel earlier live-chat or offline-browser results as new evidence.

## Delivered scope

- Canonical source moved to `<repository>`. The destination's existing unborn `main` and `git@github.com:metaphy6/wfform.git` origin were preserved. The original chat workspace retains historical outputs and a relocation README, not a second source tree.
- Applied `<scaffold-checkout>/xops/init/scaffold.sh --target <repository> --preset full --no-mcp` without forced replacement. Framework revision: `a93e0d95e665748c700faa677cc5e8cfdb6c3ca8`. No Dart preset existed, so actual Flutter rules, commands and editor/agent configuration were adapted locally.
- Populated project, architecture, API, module, design, decision, roadmap and context documentation. Shared framework material is identified as reusable guidance. No CodeGraph server/index or Node application dependency was introduced.
- Kept the development key in ignored, mode-600 `config/local.json`. Private configuration, build output, `.local/`, scratch work and screenshots are excluded from Git. The repository checker scans both prospective files and the Git index without printing credentials. The image uses an allowlisted, key-checked context and excludes local configuration.
- Added static nginx Docker deployment, Make/xops lifecycle commands, optional read-only runtime configuration, local TLS, header/integrity checks and the [Docker guide](../guides/DOCKER.md).
- Added built-in Markdown replies and file previews, explicit source/copy controls, 30 syntax grammars with extension aliases, and safe plain-text fallback for unknown UTF-8 files. Text files are bounded at 256 KiB each. Existing media capability checks remain. See [file rendering](../file-rendering.md) and [multimodal input](../multimodal.md).

## Commands and results

All commands ran from the canonical project directory. Long commands were wrapped with `xops/agent/safe-run.sh`; full logs are in the ignored project `outputs/` directory.

| Executed command | Result |
|---|---|
| `make verify` | Formatting clean; analysis clean; **321 deterministic tests passed**, **1 opt-in live test skipped**; repository key/ignore check passed |
| `make build` | Release PWA built successfully; 33 shell assets, **18,150,057 uncompressed bytes** |
| `make image` | Credential-free allowlisted context and pinned official nginx image built successfully |
| `TLS=1 make restart` | Project container recreated and healthy, preserving the TLS overlay |
| `make tls.check` | Actual HTTP and HTTPS health/config/security/cache/MIME checks passed; all 33 versioned assets matched SHA-256 |
| `CHROME_EXECUTABLE=/path/to/chrome flutter test --platform chrome test/history/browser/indexeddb_checks.dart --reporter expanded` | **6 tests passed using actual Chromium IndexedDB**, covering migration, binary deduplication, incremental writes, conflicts and rollback |
| Agent/editor configuration validation | Five Codex TOMLs and VS Code JSON parsed; Flutter/deploy scopes present and MCP absent |
| `python3 -m unittest discover -s xops/makefile -p 'test_*.py'` | **7 scaffold operations tests passed**; Python is repository tooling only |
| Local documentation-link validation | 31 populated project documents, 208 local links/anchors checked; no broken targets or unresolved scaffold placeholders |

The deterministic suite covers old and new model parsing, pricing, health, error/SSE handling, history, attachments, adaptive widgets, rendering limits, source selection/copy, stream coalescing, 320px/200% text, repository secret guards and deployment tooling. It uses fake transports where appropriate; it is not live model inference. The new deployment tooling has nine tests and repository tooling has five tests.

Final release identities:

- Dart host: `130688bba825e04ca5361c3cb648e2957d57be4c9d06502f0c002593c340b7f7`.
- Container: `242957f40d458e184fcc6f037753a0924362e708122280d255dd17668be153d4`.

Container policy stamps intentionally produce a distinct release identity, including a new bootstrap URL when nginx policy changes. The byte count is a complete offline-shell total, not a compressed transfer size or a performance improvement claim. Roboto and Roboto Mono font licenses are included in both builds.

## Actual browser evidence

Verified in the Codex Chromium-based browser at `http://localhost:8080/`, using the final container release:

1. A waiting worker was applied through **Save & update**. The loaded HTML release changed from the previous container build to `242957…`; the app reopened successfully.
2. The real public OpenRouter catalog refreshed in the browser. Diagnostics reported **648 inspected, 67 free-price candidates, 7 excluded with unresolved pricing (-1), 0 quarantined**, one page, and **no errors recorded** at 11:47:07 UTC. These are a dated observation, not fixed test expectations. Direct browser catalog access worked.
3. Imported a clearly labelled **local fixture**, containing a Markdown assistant reply with heading, emphasis, table, list and JavaScript fence. This was not a real model response.
4. Selected four generated local fixtures through the browser file chooser: `.md`, `.yml`, `.c` and `.json`. Each was accepted with its format label and opened in the built-in preview. Markdown rendered a table and highlighted code; Source switched to literal Markdown with Preview available to return. YAML, C and JSON displayed colored source and copy controls.
5. Entered an unsent draft through keyboard input, resized live across compact (390×844 CSS pixels), medium (820×1180) and expanded layouts, then reloaded. The selected model, two-message conversation, draft and all four attachments were retained. Reopened a persisted Markdown file successfully.
6. At **200% app text size and 390×844**, the preview remained scrollable and its Close, Source and Copy controls were reachable. Keyboard Enter closed the preview. Restored 100% text and the original viewport afterward.
7. Earlier browser testing exposed blocked Flutter fallback-font fetches. The final CSP permits only the required `https://fonts.gstatic.com/s/` font path in the relevant directives; no warning/error console entries were captured after final activation at 11:43 UTC during the checks above.

The original development app at `http://localhost:8765/` was also updated through **Save draft & update**, preserving its existing selection/history. The Docker origin holds the explicitly labelled verification fixture separately from the user's development origin. Browser history is origin-scoped; use the documented export/import flow to transfer it between ports or a production hostname.

Screenshots and accessibility snapshots are saved in the original chat's `outputs/` directory: `workspace-markdown-preview.png`, `workspace-json-preview.png`, `workspace-rendering-compact-200.png`, and `workspace-container-diagnostics.txt`. The report and final verification logs are copied there for the chat deliverable. Project logs remain in the new workspace's ignored `outputs/` directory.

## Nginx and TLS observations

The running image uses official digest-pinned nginx 1.30.5-alpine. It runs non-root with a read-only filesystem, dropped capabilities and project-scoped volumes/tmpfs. The image has no application backend or OpenRouter proxy. Its tested ports bind localhost only: HTTP 8080 and HTTPS 8443.

The verifier confirmed enforced CSP, `X-Content-Type-Options`, referrer, frame, Permissions Policy and same-origin isolation-related headers on success and error responses. HSTS is present only on HTTPS. Flutter requires inline styles and WebAssembly compilation support; CSP permits `wasm-unsafe-eval`, not general `unsafe-eval` or inline scripts. Clipboard permissions remain same-origin for the app's copy/paste features. HTML, service worker, manifest, runtime configuration and misses are not HTTP-cached; successful versioned assets are immutable. Missing assets return 404 rather than the app shell.

The optional blank runtime-config mount was tested as 200/no-store and its absence as 404/no-store. The final running container has **no runtime key mounted**. Local TLS was checked using a client that trusts only the generated project certificate; system trust was unchanged and no browser certificate warning was bypassed.

## Boundaries and remaining limitations

- **“A+++” is not a standard header grade.** The concrete policies and checks above passed; no public-domain SecurityHeaders/SSL Labs rating, publicly trusted certificate or externally reachable deployment is claimed. See the Docker guide for production TLS/HSTS choices.
- No new authenticated chat or live file-inference request was sent in this phase. New content-part mapping is covered by deterministic tests; real provider acceptance still depends on the selected model and account. The live test remains opt-in.
- Safe worker activation, reload and persistence were exercised on the new release. A fresh offline network-disconnection/reload and OS-level PWA installation were not repeated in this phase; earlier dated evidence remains in the baseline reports. The shell/cache worker and integrity contracts passed the current tests.
- Browser copy controls and selectable/source views were checked, and exact clipboard payloads are covered by widget tests. The tool's virtual clipboard did not establish an operating-system clipboard round trip; none is claimed.
- HTML/scripts/source are displayed, never executed. DOCX/XLSX/archive/binary rendering is outside this feature. Unknown files are accepted only when valid bounded UTF-8 text; unsupported binary content is rejected clearly. Rendering/highlighting is bounded, with paged literal source for large replies.
- This was Chromium/Linux web verification. Native Flutter platforms, Safari/Firefox and real mobile software keyboards were not newly verified.

## Run from the new workspace

```bash
cd /path/to/wfform
make deps
make verify
make image
make up
```

Open `http://localhost:8080/`. Enter a session key in Settings, or follow the Docker guide for the explicit ignored read-only config mount. `make down` stops only this project's container. For the Dart host use `make build` then `make serve` at `http://localhost:8765/`. Optional local TLS: `make tls.cert`, `make tls.up`, `make tls.check`.

Source is staged under the repository policy: **276 files**, completion run ID `wfform-workspace-20261006`. The post-stage credential/index scan and `git diff --cached --check` passed, and `make git.dry` completed without committing. Upstream emoji/font license text is retained verbatim with narrow trailing-whitespace attributes. No commit or push was performed.
