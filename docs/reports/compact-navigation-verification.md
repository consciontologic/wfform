# Compact navigation refinement 0.2.4 — 2026-10-08

Status: implementation, final regression gate, source review and release build
passed; release-browser checks passed and publication is pending. Baseline source commit is
`e56767b`. Package version is `0.2.4+9`; app and static information-page versions
are 0.2.4. The [roadmap](../planning/ROADMAP.md#phase-17--compact-navigation-refinement-024)
tracks acceptance. Previous release evidence remains in the
[0.2.3 report](compact-controls-verification.md).

## Requested behavior

On phone and tablet layouts, the model selector should keep **Models** visible
beside its header icon, including narrow widths and enlarged text. It continues
to open the existing searchable model picker without changing the selected
model, composition or attachments.

The drawer should use a single compact bottom row for version, GitHub and an
**Info** menu. About, Terms and conditions, and Liability move into that menu.
Smaller typography and the inherited sidebar surface replace the previous
separate link panel. The drawer's minimum sizing should reflect the smaller
footer while keeping links, history and utilities reachable.

The existing width/text-scale layout decisions remain in force. The app uses
available layout constraints, not phone or tablet model identifiers. Draft-safe
information-page navigation and the desktop footer remain intact.

## Verification status

| Check | Result |
|---|---|
| `make verify` | **509 tests passed**, one opt-in live test skipped; **117 Dart files** passed formatting; analyzer and repository checks clean; log: `outputs/024-verify.txt` |
| `make codeg codeg.check` | Passed; **155 files, 2,109 nodes, 8,935 edges and eight tools**; log: `outputs/024-codegraph.txt` |
| Models label regressions | **Four passed** at 320×740 / 100%, 320×740 / 200%, 390×844 / 125% and 820×1180 / 200%; label hit testing, containment and picker access; log: `outputs/024-models-tests.txt` |
| Focused footer/draft regressions | **21 passed**; compact row, information-menu actions, draft checkpoints and history continuity; also included in the full gate |
| `flutter test test/shared/seo_metadata_test.dart test/shared/pwa_identity_test.dart --reporter expanded` | **15 passed** on the project SDK; static footer version consistency, metadata and installed identity; log: `outputs/024-metadata.txt` |
| Independent source review | No actionable findings in the reviewed changes |
| `make build.public` | Passed; `outputs/024-build.txt`; 40 shell assets / 18,273,628 uncompressed bytes |
| Impeccable detector | No findings on the two changed UI files; no suppressions added; `outputs/024-design-detect.json` |
| Scoped Markdown link check | **54 local link targets across five changed documents** resolve |
| `git diff --check` | Passed for the initial version and documentation changes |

The drawer footer's default fixture height decreased from **209 to 48 logical
pixels**. In the 390×844 phone-layout fixture, its bottom aligns with the
viewport's 844-pixel boundary and history receives more than 584 logical pixels
of height. The regression asserts a footer height at most 56 pixels, with the
same-row version, GitHub and Info controls, no decorated footer panel, and
accessible menu actions. Large-text tests use the shipped Roboto fonts rather
than the square-glyph Flutter test font. These measurements concern
deterministic widget geometry, not physical phone rendering or performance.

Release build and the browser checks recorded below passed. Publication remains
pending. Metadata tests and historical counts are not substitutes for these
checks.

Physical phone frame rate and Android software-keyboard behavior are outside
this refinement's measured scope. Deterministic Flutter fixtures, desktop
browser viewport checks and live service requests will be distinguished if run.

Release identity: `4fa05ab5e03553493ab0993f01e26e586f4f23936fc920df233bade4e6c58c45`.
No API transport, model eligibility, storage or conversation logic changed.

## Release-browser checks

The actual credential-free release was served at a fresh localhost origin.
Measured CSS viewports were 390×844 and 820×1180 at device-pixel ratio 1.0.
The visible Models control opened the searchable live catalog, and a free model
was selected. The drawer showed a single version/GitHub/Info row flush with its
bottom, inheriting the sidebar surface. Info exposed exactly About, Terms and
conditions, and Liability. After verifying a draft in the Drafts list, navigating
through Info → About → Open app restored its exact text and selected model.
Live resizing to the tablet viewport retained that composition. Local screenshots
are `outputs/024-phone-drawer.jpg`, `outputs/024-phone.jpg` and
`outputs/024-tablet.jpg`. No inference request was sent for this UI refinement.
