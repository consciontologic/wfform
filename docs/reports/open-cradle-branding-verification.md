# Open Cradle branding verification

Date: 2026-10-09. Scope: apply the user-approved Open Cradle logo and replace the prior ten companion glyphs and exported logos with a coherent transparent light/dark family.

The no-background clarification below supersedes the initial opaque-platform exceptions recorded in this first pass.

## Design and asset coverage

The [approved concept](../design/open-cradle-concept.png) is rebuilt as deterministic vector geometry: two filled folded-band shapes around connected lavender nodes, with an open upper-right gap. Flutter and the Dart PNG generator share the same geometry. This avoids the generated concept raster's edge artifacts. Existing labels, app identity and installation/storage keys remain intact.

All 40 active PNG exports were regenerated: six 16/32/48 favicons, eight 192/512 PWA assets, ten Android default/night launchers and sixteen iOS images used by 21 catalog entries. Standard app artwork, favicons, PWA logos, Android icons and the iOS dark source retain transparent exteriors/interiors. The fifteen default iOS images and four maskable PWA images retain non-white tinted opaque surfaces for their existing platform formats. Native builds/device appearance and OS icon-cache refresh are not established by these source files.

All four public pages continue to select the correct light/dark favicon files. Their sharing descriptions now identify Open Cradle; information-page logos, Apple touch and social previews already use the regenerated asset paths. The optional companion packages inherit these validated web assets and have no separate logo resource. Native blank splash defaults and historical concept/report assets are outside the active logo family.

## Completed export and metadata checks

- Fourteen focused artwork/platform tests passed; generator analysis and diff checks passed. Coverage includes linked node centers at 16/32/48px, the solid band, transparent center/open gap/fold seam, both appearance palettes and deterministic exports.
- Independent PNG review passed all 40 signatures, chunk CRCs, decoded scanlines, dimensions, RGB/RGBA modes and clean unmatted alpha edges. All 21 iOS slots match their referenced image dimensions and modes.
- Maskable artwork stays within the central 0.4-radius safe circle in both palettes at 192/512px; maximum measured radii were 0.358373 and 0.357974 respectively.
- All fourteen SEO/public-page tests passed, including exact Open Cradle sharing descriptions and retained appearance-specific favicon declarations.

Logs: `/tmp/agent-runs/open-cradle-export-final--20261009T114624Z-249126.log`, `open-cradle-export-final-lint--20261009T114728Z-249897.log`, `open-cradle-review-pngs--20261009T114736Z-250155.log` and `open-cradle-seo--20261009T114230Z-244156.log`. Ignored export inventory and preview are under `.local/open-cradle-20261009/`.

## Completion gates

- `make verify` passed: 616 Flutter tests, four existing opt-in live skips, 162 Dart files with no format changes, Flutter and companion analyzers, repository checks and all ten companion suites. Log: `/tmp/agent-runs/open-cradle-full-verify--20261009T115121Z-253595.log`.
- Six focused transparency tests passed, covering all ten glyphs, preserved host surfaces, inherited foregrounds, connected AI nodes at 16px and Flutter/export parity at 16/32/100px in both themes. Log: `/tmp/agent-runs/open-cradle-transparency-final--20261009T115023Z-252671.log`.
- Independent artwork/source review found no issues. The rendered Flutter contact sheet at 100/32/24/16px was inspected in both appearances; all ten functional symbols remain recognizable.
- `make codeg` confirmed the existing index was current. The smoke check initially truncated eight callers to five, excluding the expected `continueResponse` relationship. Raising its bounded query limit to 100 fixes the check without changing either assertion, the timeout or response bound. `make codeg.check` and all nine existing CodeGraph operations/configuration tests pass. Logs: `/tmp/agent-runs/open-cradle-codegraph-repaired--20261009T115343Z-257801.log` and `open-cradle-codegraph-operations--20261009T115343Z-257802.log`. The failure breadcrumb is resolved; no reindex was needed.
- `make build.public` passed for release `fb8bcd7a7bfca069fd1a8ac9ad1264d51862023164085f5d14c749890a3553d6`, with 51 shell assets / 18,442,429 bytes. Log: `/tmp/agent-runs/open-cradle-public-build--20261009T114947Z-252111.log`.
- The existing local PWA used **Save & update** and loaded that exact release's `main.dart.js` and bootstrap. This is actual updated-app evidence, beyond build success. Desktop light/dark and a measured 390×844 viewport at 200% text show the new main mark and companion controls. Labels remain available in compact navigation. Screenshots and the rendered contact sheet are under ignored `.local/open-cradle-20261009/`; the in-app browser's retained zoom affects screenshot framing. Browser theme/text preferences and the temporary viewport override were restored after checks; offline mode and stored content were preserved.
- HTTP integrity passed all 30 requests: root/immutable release manifests and both URLs for all 14 branding PNGs. Each PNG exactly matches source, built copy and manifest SHA256. Log: `/tmp/agent-runs/open-cradle-local-http-integrity--20261009T115651Z-261041.log`.

This change is staged locally. Public publication, native binaries/physical-device checks and authenticated inference are separate; no such results are claimed.

## Preserved work and recovery

The checkout began with 87 separately staged tools/companion files. Those changes are preserved; the initial staged patch/status were saved under `.local/open-cradle-20261009/`. The earlier 0.3.0 public-integrity failure was resolved against its retained immutable build and documented in the [prior branding report](soft-wrapper-branding-verification.md); it is not fresh Open Cradle deployment evidence.


## No-background clarification — 2026-10-09

The user subsequently required **no background color in either appearance**, including platform exports. All 40 PNGs now use RGBA with transparent exterior/interior space. The 15 default iOS files and four legacy maskable files lost their tinted backplates; the other 21 PNGs remain byte-identical. Shapes, dimensions, foreground colors, filenames and iOS catalog slots remain intact. Flutter's main mark and all ten companion glyphs already met this requirement and keep their existing transparent geometry.

The PWA manifest now selects only the two transparent `purpose: any` icons at 192/512px. Legacy `Icon-maskable-*` files remain as transparent images for compatible existing references, but are not advertised for maskable compositing. The [Web App Manifest specification](https://www.w3.org/TR/appmanifest/#icon-masks) requires a solid fill when a maskable icon contains transparent pixels; removing that declaration avoids requesting this behavior. Actual installed-launcher presentation and native store acceptance remain unverified.

The new PNG regression failed first and identified all 19 opaque files. After regeneration, all 21 focused artwork/transparency/platform tests pass, plus the six manifest/platform checks. The new exterior test was corrected to preserve the existing antialiased 16px edge instead of shrinking the mark; a mistakenly supplied test path was corrected after reading its log. Both recovery breadcrumbs are resolved. Independent decoding validated all 40 files: transparent corners/openings/interiors, clean alpha, retained ink/accent, unchanged safe-circle bounds and no foreground loss. All 294,487 solid foreground pixels in the 19 changed files match their prior versions; recompositing over the previous tint reproduces the old image within one RGB level.

The new transparent contact sheet contains the main logo and ten companion icons in both appearances at 100/32/24/16px, with no panels. Its 1,130,112 alpha-zero pixels cover 94.08% of the image; all 22 glyph cells contain their correct ink and lavender. It is saved under `.local/open-cradle-20261009/flutter-contact-sheet-transparent.png`, with the independent alpha report beside it.

The public build passed for release `a66200a09fec3b0b664820538db4cc06c303d12850e8937e0c90768864fb314c`, 51 shell assets / 18,438,459 bytes. The existing local PWA completed Save & update and loaded that exact release's main/boot scripts; original offline mode, System appearance, normal text and empty composition remain. New public publication and native binaries are not part of this follow-up.

Logs under `/tmp/agent-runs/`: `transparent-all-assets-red--20261009T120357Z-267828.log`, `transparent-all-focused-final--20261009T120537Z-269479.log`, `icon-alpha-manifest-red--20261009T120329Z-267346.log`, `icon-alpha-manifest-green--20261009T120346Z-267632.log`, `transparent-all-icons-independent--20261009T120634Z-270325.log`, `transparent-followup-public-build--20261009T120505Z-268862.log`. CodeGraph confirmed its index current. Final `make verify` passed 617 Flutter tests (four existing opt-in live skips), both analyzers, formatting, repository checks and all ten companion suites. Log: `transparent-followup-verify--20261009T120635Z-270356.log`. Independent local HTTP validation passed 32 root/immutable URLs covering all 14 web PNGs, both web manifests and both release manifests, matching source/build/manifest bytes and media types; log: `transparent-local-build-integrity--20261009T120719Z-273462.log`. All pre-existing staged work remains preserved; this follow-up is staged locally.
