# Soft wrapper branding verification

Date: 2026-10-09. Scope: replace the old branding with the user-approved rounded W-wrapper and companion icon family. This is a local implementation and release-build verification; source publication was not performed.

## Initial implementation — superseded by the transparent follow-up below

- The selectable product name is accompanied by a rounded W enclosing a muted lavender module. The approved reference is [the concept board](../design/soft-wrapper-concept.png).
- Models, Chat, History and Documents use matching scalable Flutter artwork in the model controls/dialogs, New conversation, empty conversation/history views, Add files and document previews. Labels, tooltips, disabled states, callbacks and media-specific icons remain intact.
- The W geometry is shared by Flutter and the deterministic Dart PNG generator. Neutral fills adapt to the resolved icon foreground, including filled buttons, while preserving the lavender accent and disabled opacity.
- Regenerated 192/512 PWA icons and maskable variants, all five Android launcher files and all fifteen unique iOS launcher files. Native application IDs and installed PWA identity are unchanged.
- Replaced `favicon.png` (48px) and added dedicated 16px and 32px favicons. All four public pages declare the three sizes. The release allowlist includes both new files, so publication and offline shell hashing retain them.

## Gates and recovery

- `make verify`: passed; 120 Dart files needed no formatting changes, analysis found no issues, **520 tests passed**, and repository hygiene passed. One existing live-catalog test remains opt-in and skipped; no live inference was run.
- `make codeg` and `make codeg.check`: passed with CodeGraph 1.6.2, eight MCP tools, 158 files, 2,172 nodes and 9,135 edges. Real Dart queries and ignored-file exclusions were verified.
- `make build.public`: passed. Final release: `5e016f4094af03a0b02f93a2fd73be30fc5e5cf75aa94095872b378fa619063a`, 42 shell assets, 18,294,269 bytes. Local configuration is excluded.
- Independent review found no outstanding actionable findings. All native PNG dimensions and opaque RGB encoding were checked. Maskable artwork stays within the central safe circle (maximum radius below 0.391 of the image width).
- Post-completion design-hook review confirmed that About, Terms and Liability retain the existing bundled Roboto shared with the Flutter theme. The icon-only scope preserves this typography. A value-specific `overused-font=roboto` exception is restricted to these three pages in `.impeccable/config.json`; no other font, file or rule is suppressed. The detector returned no remaining findings, and repository hygiene passed after the configuration change.
- Regression tests failed before the changes for missing component artwork, missing favicon declarations and omitted favicon release assets. A responsive test caught empty-history overflow at enlarged text; its content now scrolls. Browser inspection caught white outlines merging into a filled button's light icon fill; a rendered light/dark filled-button regression now covers the corrected contrast.

Final logs are under `/tmp/agent-runs/`: `brand-final-verify-v2--20261009T090205Z-56587.log`, `brand-codegraph-sync-v2--20261009T090206Z-56694.log`, `brand-codegraph-check-v2--20261009T090211Z-57459.log`, and `brand-release-verified--20261009T090123Z-56100.log`.

## Browser and served-asset evidence

The local public build was served on `http://localhost:8766/` with `--isolated-config`. The in-app browser initially had an older cached app on that origin; the normal Save & update path loaded the new release. The actual bootstrap URL was checked against the final release hash instead of assuming a reload selected the newest build.

Phone layout at 390×844 was inspected in light and dark modes, including 200% text and the scrollable navigation drawer. Main branding, Models, Chat, History and the disabled Add files icon remained readable and reachable. The original System theme and 100% text settings were restored afterward. Expanded layout was inspected at 1440×1000. Temporary viewport overrides were reset after verification.

All seven favicon/PWA PNG paths returned HTTP 200 with image/png. Served bytes, checked-in source assets, built files and release-manifest SHA-256 hashes matched. The loaded page declared the correct 16/32/48 favicon links. Browser screenshot evidence is retained in ignored `.local/branding-20261009/`.

No authenticated OpenRouter submission, remote deployment, native binary build, physical-device installation or OS-level icon-cache refresh was tested. Browser and OS installations may retain an old icon until they refresh their installation metadata; the new assets and declarations are present in the verified release.

## Transparent icon follow-up — 2026-10-09

The user extended the family to Settings, Diagnostics, Context, Chats, Drafts and Archived, and requested that existing and new icons have no white background and support light/dark aesthetics. All ten companion symbols and the main W now use transparent interiors, with charcoal/light outlines and a restrained lavender accent selected for the actual foreground. Overlapping front shapes clear only their isolated artwork layer; they do not erase the host surface. Dialog icon tiles were removed. Selected filter checkmarks, labels, disabled states, draft preservation and callbacks remain intact.

Transparent light/dark PNG exports replace the favicon and standard launcher artwork. All four pages declare dark favicon media variants; information-page logos use `picture` media selection. The release allowlist includes all six favicon files. PWA maskable and default iOS artwork use lavender-tinted opaque surfaces rather than white. Maskable alpha is intentionally avoided because the browser otherwise chooses its replacement fill ([W3C manifest specification](https://www.w3.org/TR/2026/WD-appmanifest-20261008/)). The installed PWA manifest uses the default launcher assets; its format does not provide automatic light/dark icon selection. Dark launcher source assets are also available.

Android night resources and paired iOS universal Any/Dark entries are supplied alongside the legacy sizes. The iOS dark appearance uses transparent artwork, following [Apple guidance](https://developer.apple.com/documentation/xcode/configuring-your-app-icon). Native resource variants are source preparation only: Xcode, Android builds, physical launchers and icon-cache refresh are unverified.

Regression coverage verifies transparent exterior/interior pixels, overlap compositing on multiple surfaces, exact ink/accent visibility at 16px and 24px, deterministic PNG generation, appearance declarations and publication hashes. Integration tests cover all six new controls and dialogs in both themes at 320px with 200% text, 390px and expanded desktop. The 320px test caught an overflowing chip label; labels now wrap without removing selected checkmarks. Tiny glyph accent geometry was adjusted to remain visible at 16px.

Final follow-up gates: `make verify` passed **532 tests**, one pre-existing opt-in live-catalog skip, formatting of 121 Dart files with no changes, analysis and repository hygiene. Independent review found no concrete defects and passed 64 focused tests. CodeGraph sync/check passed with 159 files, 2,201 nodes, 9,305 edges and eight tools. The design detector returned no findings with the existing narrow Roboto exceptions.

`make build.public` produced release `9a82b0e7cf05d7d48fda032d681702452bd2237f82a69fb8f23f7c81eef2e9aa` with 49 shell assets and 18,305,668 bytes. All 14 served PNG favicon/launcher assets returned image/png and matched the source, built files and manifest hashes. Local configuration is absent. PNG checks confirmed clean alpha edges, maskable safe-circle bounds and the correct RGB/RGBA formats and dimensions for all 21 iOS catalog slots.

The existing localhost browser applied the normal Save & update flow, and the actual DOM bootstrap selected the new release hash. At 1440×1000, light/dark navigation and Settings, Diagnostics and Context dialogs showed the new transparent artwork. At 390×844, Chats/Drafts/Archived selection worked and the dark 200% text drawer scrolled to both utility actions with readable labels. The original System theme, 100% text and Chats filter were restored; the temporary viewport override was reset. No remote model request or credential action was performed. Screenshots: `.local/branding-20261009/transparent-{light,dark}-desktop.jpg`, `transparent-light-phone.jpg`, and `transparent-dark-phone-200.jpg`.

Final logs under `/tmp/agent-runs/`: `brand-nav-final-verify--20261009T092139Z-77998.log`, `brand-nav-codegraph-sync--20261009T092212Z-81470.log`, `brand-nav-codegraph-check--20261009T092217Z-81856.log`, `brand-transparent-public--20261009T092139Z-78045.log`, and `brand-transparent-review--20261009T092142Z-78461.log`. Public deployment, native builds and device launcher appearance remain unverified.

## Version 0.3.0 release preflight — 2026-10-09

The user explicitly authorized versioning and pushing the accumulated branding work. Package version is `0.3.0+10`; the Flutter footer, public information pages and strict version tests agree. The new root changelog records the visible changes. Independent review found no blocking release defects.

The final versioned sources passed `make verify`: **532 tests**, one existing opt-in live-catalog skip, 121 Dart files requiring no formatting changes, clean analysis and repository hygiene. The CI-equivalent operations suite passed **14 tests**, and actual Chromium IndexedDB/localStorage checks passed **seven tests**. CodeGraph sync/check again passed with 159 files, 2,201 nodes, 9,305 edges and eight tools.

`make build.public` and the website-artifact validator passed. Release identity: `f06db063595a2a7c6ea540f186221dc6c6293de40368036b17586d9fec647129`, with 49 shell assets and 18,305,668 bytes. No local configuration is included. The existing CupertinoIcons tree-shaking warning did not prevent the successful build.

Logs under `/tmp/agent-runs/`: `release-030-final-verify--20261009T093103Z-98633.log`, `release030-repository-ops--20261009T093021Z-97442.log`, `release030-chromium-storage--20261009T093026Z-97771.log`, `release-030-codegraph-sync--20261009T093129Z-100855.log`, `release-030-codegraph-check--20261009T093130Z-100929.log`, `release030-public-build--20261009T093106Z-98859.log`, and `release030-artifact-validation--20261009T093202Z-101500.log`. Publication and the public PWA update are pending at this preflight checkpoint.
