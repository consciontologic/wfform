# Footer and composer focus patch 0.1.2 — 2026-10-07

## Changes

The app and all four public HTML pages use a plain GitHub text link beside the
version on the left. The custom drawing, SVG file, artwork styles and release
allowlist entry are removed. Compact app layouts keep information pages in an
Info menu; the version/source group can wrap when unusually wide fonts require
it. The package is `0.1.2+3`, and visible versions are 0.1.2.

Eight unfilled documentation templates were removed. Existing project documents,
reports and tracking remain, and four indexes plus ADR-writing instructions no
longer reference the deleted templates. A scoped audit checked 50 Markdown files
and 289 local link targets without missing targets.

The composer explicitly unfocuses on an outside pointer action, closing its
input connection and stopping its caret. Only the sidebar divider shares its
tap region, so dragging a layout boundary preserves typing focus. Drafts,
selection, keyboard shortcuts and active responses remain intact.

The deterministic failing case was touch activation of an outside action under
Flutter's Android-style touch policy. It passed after the fix. Ordinary desktop
outside taps and framework view blur already passed before the fix; no distinct
Chromium engine fault was established. Tests assert focus and input-connection
state, not merely a hidden cursor.

## Executed local checks

| Check | Result |
|---|---|
| `make verify` | Formatting and analysis clean; 421 tests passed; one opt-in live test skipped; repository check passed |
| `make codeg codeg.check` | MCP/Dart queries passed; 145 files, 1,947 nodes, 7,993 edges |
| `make build.public` | Release PWA built successfully |
| `dart run deploy/package.dart build/publish-web build/012-docker-context` and Docker image build | Credential-free allowlisted context and nginx image built |
| `dart run deploy/check.dart http://127.0.0.1:8768` | Real nginx headers, health/error/method policy, WASM MIME and all 40 immutable asset hashes passed |
| Integrated read-only review | No actionable findings in changed footer, focus, version or documentation code |

Release: `8111221d438ff71161cff598dc353a61ba97255c8ec418d738170cfffdb2b57a`.
The shell has **40 assets / 18,258,913 bytes**. The existing nonfatal Cupertino
font-family build warning remains. Raw logs are ignored under `outputs/012-*.txt`.

## Browser evidence and limits

A disposable nginx origin ran the actual release, with no API key. Updating
from 0.1.1 through **Check for update** and **Save & update** loaded 0.1.2 and
preserved the generated draft. Live catalog discovery succeeded.

At 1280 × 720, the plain source link appeared beside the left-aligned version.
Clicking Archived moved focus from the composer and removed its visible caret
while retaining the draft. Keyboard Tab also moved focus away. Live resizing to
768 × 1024 and then 320 × 800 retained the draft. At 200% app text, the measured
320-pixel viewport had no horizontal document overflow; GitHub, version, Info
and composer remained reachable.

Widget tests additionally exercise mouse and touch outside actions, input-client
closure, view blur, selection preservation, sidebar dragging, active mocked
streaming, shortcuts, large text, keyboard insets and layout transitions. These
are deterministic fixtures, not authenticated provider requests or physical
mobile-device evidence. No fresh offline reload, installation prompt, Safari,
Firefox, native build or authenticated inference is claimed for this patch.

Publication evidence is recorded after the GitHub workflow completes.
