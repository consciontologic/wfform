# Sidebar and model passport patch 0.1.1 — 2026-10-07

## Changes

The resize grip is replaced by a straight draggable divider. Drag to the left
edge to collapse; hover the outermost four pixels to preview navigation. The
preview overlays chat rather than moving it. Choosing a sidebar action both
executes it and restores the default 290-pixel width. Touch has a 24-pixel
edge target; keyboard users can focus the edge and press Enter/Space. Escape
collapses/dismisses, arrows resize, Home/End set bounds, and Enter on the
divider resets. Saved collapse/width preferences survive reloads. Compact
drawers and medium rails retain their existing roles.

Model passports show a literal first-sentence preview capped at 180 Unicode
code points, readable context counts and capability chips. Full descriptions
and exact availability, pricing, parameters, file limits and provider metadata
remain selectable through explicit expansion controls. Upstream ellipses are
still attributed to OpenRouter. No model text is invented or website scraped.

Archived-row trash deletes directly, without first opening/selecting the row
or asking for confirmation. Row actions have independent accessibility targets;
real browser testing exposed and fixed a nested target that could open the row
instead of performing its action. Pending deletes are deduplicated. Failed
deletions retain records and report the error. Deleting a different archived
record leaves the active draft, files, save operation and response alone.
Deletion is permanent; export first when a backup is needed.

The package is `0.1.1+2`; app and static footers display 0.1.1. Public return
buttons now read **Open app**. Earlier analytics/information-page behavior
remains covered by tests.

## Executed checks

| Command / check | Result |
|---|---|
| `make verify` | Formatting and analysis clean; 411 app/tool tests passed; one opt-in live API test skipped; repository check passed |
| `CHROME_EXECUTABLE=/path/to/chromium flutter test --platform chrome test/history/browser/indexeddb_checks.dart --reporter expanded` | Six real Chromium storage checks passed against generated test databases |
| `python3 -m unittest discover -s xops/makefile -p 'test_*.py' -v` | 14 repository-operation tests passed |
| `make codeg codeg.check` | Real MCP/Dart queries passed; 144 files, 1,944 nodes, 7,968 edges |
| `make build.public` | Release web/PWA build passed |
| Allowlisted Docker packaging and image build | Passed; local configuration excluded |
| `dart run deploy/check.dart http://127.0.0.1:8767` | Actual nginx headers, health/error/method behavior, WASM MIME and all 41 immutable asset hashes passed |

Final local release: `be34cdecbbf8cb0f1e0053c6ec7f6e17002afef13c834a4ea61acddbddf98208`,
**41 shell assets / 18,260,732 bytes**. The pre-existing nonfatal Cupertino
font-family build warning remains. Logs are ignored under `outputs/patch-*.txt`
and the safe-run evidence directory.

## Browser verification

The release ran in a disposable nginx container on a separate loopback origin,
with no configured API key and only generated test conversations. Live catalog
discovery succeeded. Screenshots and accessibility trees checked the plain
divider, drag collapse, left-edge preview and first Settings activation.
Desktop, medium and compact layouts were exercised by live resizing; a measured
320-by-800 viewport at 200% app text kept the draft, composer, footer and
scrollable drawer utilities reachable. Light and dark modes and 125% text
were also inspected.

Deterministic tests additionally cover hover exit, keyboard/touch first-action
restoration, search focus, description/pricing copying, failure retention,
semantic archive/restore/delete, and an active mocked response across layout
changes. These are distinct from a real authenticated inference request.

On the final release, the exact browser `getByRole(...).click()` archive
action worked on an unselected row; its trash action then deleted it on the
first click while the different active draft remained visible. The safe PWA
update banner detected the rebuilt shell and **Save & update** restored the
test draft after reload. Existing personal conversations were never deleted.

No authenticated inference, Safari/Firefox/native build, fresh installation
prompt or fresh network-disconnected reload is claimed for this patch. Remote
publishing is verified separately through the source and Pages Actions runs.

The final Gemma passport at 125% showed its 116-character first sentence,
**Show full description** exposed the original 211-character catalog text,
and Pricing expanded the zero prompt/completion values. The browser console
had no captured warnings/errors. Current live counts were observed only, not
asserted as fixtures or a permanent catalog guarantee.

## Published release

Source commit `4984e207c3b928c13c7d93b5fdc1d93bb20caa13` passed
[GitHub CI run 37647775708](https://github.com/consciontologic/wfform/actions/runs/37647775708):
411 app/tool tests, 14 repository tests, six real Chrome storage checks,
release build and artifact validation. It published web files in destination
commit `c19956b70a8042da81acd1a5dfddced73f9e676d`;
[Pages run 37648127689](https://github.com/consciontologic/wfform.com/actions/runs/37648127689)
also succeeded.

Live HTTPS served the same release hash, all four public documents returned
200 with version 0.1.1 and one Google loader each, and the three return buttons
used Open app. The local and GitHub builds had identical release hashes and
asset byte totals. Installed clients may retain their earlier shell until
they accept the app's safe update action.

A temporary public browser tab rendered the Flutter **Version 0.1.1** footer
with no captured console warnings/errors. A query bypass avoided pinning to an
older shell during this read-only check; existing public tabs and conversations
were left untouched. Temporary QA tabs and the local test container were closed.
