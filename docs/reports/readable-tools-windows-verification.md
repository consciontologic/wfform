# Readable data, tools guide and Windows companion build

Verified locally on 2026-10-09, on Linux x64. Source changes are staged for the
human to commit; no source push, remote workflow run or release publication was
performed. This report covers roadmap Phase 23 and preserves the earlier
[live tool demonstration evidence](connected-tools-verification.md).

## Implemented behavior

- Shared readable previews cover tool approval arguments, saved requests/results,
  diagnostics, cache reports, JSON parameter previews, message JSON, response
  code fences and file popups. JSON/JSONL indentation preserves numeric spelling,
  duplicate keys and escapes. YAML and other source formats retain comments and
  indentation with named highlighting. Nested code/stdout/MCP text receives an
  additional decoded view with real line breaks. Original copy/export/storage
  and requests are unchanged; malformed, unknown and oversized content falls
  back to source. This is not a formatter for every binary file type.
- **Tools → How to use tools** opens a bundled beginner guide with ordinary
  chat, remote MCP, CodeGraph and local CLI examples. **Companion setup** opens
  the detailed setup guide. Both guides are also included in companion archives.
- Windows x64 packaging emits an `.exe`, `.zip`, checksum and platform-specific
  release metadata. A native Windows CI job tests the runtime and extracted
  executable, using the same verified web assets as Linux. Windows process
  trees use a gated runner and Job Object; tokens use protected current-user
  ACLs; `.bat`/`.cmd` execution is rejected. Repeated archive builds are tested.

## Local gates and artifacts

`make verify` passed in a fresh process: **613 Flutter tests passed**, four
opt-in live tests skipped, formatting checked 162 Dart files without changes,
Flutter and companion analysis passed, repository secret/config checks passed,
and all **10 companion suites / 19 groups** passed. Independent review and
workflow YAML/whitespace checks passed. Accessibility regression tests first
failed, then passed with explicit labels restored on highlighted content;
existing diagnostic/cache assertions were preserved. Guide lifecycle tests
isolate their asset cache between fake-async test zones.

- Full gate: `/tmp/agent-runs/readable-tools-windows-verify-final--20261009T113319Z-230858.log`
- Final `make companion.build`: `/tmp/agent-runs/readable-tools-final-package--20261009T113410Z-233934.log`
- Archive/hash checks: `/tmp/agent-runs/readable-tools-final-archive--20261009T113523Z-235804.log`
- Extracted compiled CLI acceptance: `/tmp/agent-runs/readable-tools-final-extracted-cli--20261009T113528Z-235915.log`

Final public web build (local only):
`2625e134a3a3fd0fe1843382fd41140cf2aa99190c950b07c293b62d89f4888e`,
51 shell assets / 18,441,828 bytes. Final Linux archive:
`build/companion/wfformcomp-linux-x64.tar.gz`, 16,295,739 bytes / 109 regular
files, SHA-256
`3e19e3d00a2d90e147f937c6e50f80efadb9858f22871d10338e22bf38d94576`.
Its sidecar and metadata match; the archive contains only the current immutable
web release, both current guides and no private configuration. Extraction and
actual executable initialization, token permissions, overwrite refusal,
authenticated tool serving, web hosting and shutdown passed.

CodeGraph 1.6.2 sync reported up to date: 202 files, 2,741 nodes and 11,427 edges,
with no pending changes. A real `ReadableDataView` query returned the new
renderer and its presentation callers.

## Actual browser checks

The existing in-app Chromium tab at `http://localhost:8765/` used **Save &
update** to reach the final release above, confirmed by its loaded script URL.
The existing 16-message demo, six saved conversations, selected model and tool
selections survived. No conversation was submitted or tool rerun in this phase.

Browser checks on the preceding preview verified JSON, YAML and Python file
popups, decoded Python tool arguments, JSON diagnostics, guide navigation and
compact 390×844 controls. Temporary unsent attachments were removed and the
viewport override reset. The final build was checked again for two complete
guide → companion → back → close cycles and formatted diagnostic JSON with
accessible text. Final diagnostics reported **No errors recorded**, with two
successful startup/catalog activities; captured console warnings/errors were
empty. The preview remains open for the user.

An earlier preview recorded one scheduler null-check error at
2026-10-09T11:24:45.289Z. It did not reproduce in the new hover/semantics widget
regression or the two final browser cycles. Its root cause is unconfirmed;
this report does not claim a production fix for that isolated event. No
diagnostic-clear action was used to hide it; updating naturally started a new
in-memory log.

## Evidence limits and remaining work

- **Native Windows was not built or run on this Linux workstation.** Windows
  build support and a native CI acceptance job are implemented; a Windows
  runner must pass before a supported download is published. Linux tests and
  workflow parsing are not substitutes for that run.
- Graphical installation, automatic first launch/pairing and UI configuration
  remain roadmap Phase 22. Current packages are manually configured portable
  previews. macOS remains deferred, as requested.
- No new live OpenRouter inference, remote GitHub Actions run, public release,
  physical-device or native Windows/macOS test is claimed here.
- Task-owned test failures were repaired and their resolution saved in ignored
  scratch evidence. The unrelated pre-existing
  `release030-public-integrity--20261009T105037Z-186156` failure breadcrumb was
  restored unchanged; this task does not resolve that separate publication check.
