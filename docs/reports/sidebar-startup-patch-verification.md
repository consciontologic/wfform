# Sidebar surface and quiet startup patch 0.1.3 — 2026-10-07

## Changes

The sidebar now fills the leading half of its 24-pixel resize target up to the
visible divider; the other half matches the conversation surface. Previously,
that transparent half exposed a 12-pixel light gutter. The hit target, divider,
drag/collapse behavior and composer focus grouping are unchanged. Directional
layout mirrors the fill for RTL and both theme palettes are supported.

The homepage no longer displays a brief product introduction, icon or footer
before Flutter starts. A quiet theme-matched background remains until Flutter
renders. About, Terms and Liability stay available, and search/sharing metadata,
JSON-LD and the Google tag remain unchanged. The app/package version is
`0.1.3+4`; app and companion-page footers show 0.1.3.

Startup recovery remains available. A narrow host error listener reveals reload
and setup guidance if the bootstrap script itself cannot download. Its exact
CSP hash is separate from the unchanged Google tag hash; unrestricted inline
script execution is not enabled. Loader/engine failures retain bounded technical
details, and a noscript message links to About when JavaScript is disabled.

## Executed checks

| Check | Result |
|---|---|
| `make verify` | 438 tests passed; one opt-in live test skipped; formatting, analysis and repository checks passed |
| Pixel regression tests | Reproduced the gap before the fix, then passed top/middle/bottom checks in light/dark and LTR/RTL |
| Startup/header regressions | Quiet normal body, failure paths, exact CSP hashes and immutable bootstrap URL stamping passed |
| `make codeg codeg.check` | Real MCP/Dart queries passed; 146 files, 1,959 nodes, 8,092 edges |
| `make build.public` | Final release PWA build passed |
| Docker packaging/build | Credential-free allowlisted context and nginx image built |
| `dart run deploy/check.dart http://127.0.0.1:8769` | Actual headers, method/error policy, WASM MIME and all 40 immutable asset hashes passed |

Release: `c8e72bed4c0b17da8d236ffe55df7104e4bed861f3ab18ecdf157e6683078a10`.
The shell has **40 assets / 18,258,945 bytes**. The existing nonfatal Cupertino
font-family warning remains. Raw verification logs are ignored in
`outputs/013-*.txt`.

## Browser evidence

The actual release ran in disposable nginx containers on separate loopback
origins without API credentials. On the clean normal origin, the initial
accessibility tree had no introductory content; Flutter then rendered version
0.1.3. The sidebar color reached the divider at default and dragged widths.
Dark mode also showed a continuous sidebar surface. The generated test draft
survived sidebar resizing.

Live layout checks covered expanded desktop, a measured 1000 × 1332 medium
viewport, and 320 × 800 compact viewport. The compact document had no horizontal
overflow and kept its composer, navigation and footer controls in the semantics
tree. The normal browser captured no console warnings or errors; live catalog
discovery succeeded. Existing user tabs and conversations were not edited.

A second container deliberately returned HTTP 503 only for the immutable
Flutter bootstrap URL. The browser displayed **wfform could not start**, reload
and setup links, and expandable **The application startup file could not be
loaded** details under the actual nginx CSP. This was an intentional failure
fixture, not an upstream outage. No CSP warning was captured.

Deterministic tests cover keyboard/touch resize, collapse, draft/focus retention,
RTL and large text; they are not physical-device evidence. No authenticated
inference, Safari/Firefox/native build, fresh install prompt or disconnected
offline reload is claimed for this patch. The no-JavaScript fallback was checked
as an HTML contract, not with JavaScript disabled in a browser.

## Published release

Source commit `a6baa715609a5a4c06516e0474f7c3d81c2c591b` passed
[CI run 37656283785](https://github.com/consciontologic/wfform/actions/runs/37656283785),
including app tests, repository-operation tests, real Chromium storage checks,
release build and artifact validation. It published destination commit
`b496b4f76e99bc85427cc4abc0c09e339eaf2969` through the existing pipeline.
[Pages run 37656759609](https://github.com/consciontologic/wfform.com/actions/runs/37656759609)
completed successfully and serves the resulting release.

Live HTTPS returned the same release hash as the locally tested build. The
homepage no longer contains the old loading introduction; About, Terms and
Liability display version 0.1.3. Each of the four public HTML pages retains one
Google loader. Existing clients can use **Save & update** to adopt the release.

A separate live browser tab first exposed no introductory content, then rendered
Flutter version 0.1.3 with the sidebar filled to its divider. No console warnings
or errors were captured. The query used for verification bypassed an older cached
shell; user tabs were left open. Temporary browser tabs and local containers were
closed after verification.
