# Compact conversation controls patch 0.2.3 — 2026-10-08

Status: initial compact-layout implementation passed its local gates and build.
Direct draft deletion and phone/tablet footer alignment are also implemented,
and the final combined regression gate and release build passed. Browser
verification passed; publication remains pending. Baseline source commit is
`1fa24db`. Package version is
`0.2.3+8`; app and static information-page versions are 0.2.3. The
[roadmap](../planning/ROADMAP.md#phase-16--compact-conversation-controls-patch-023)
tracks acceptance. Earlier evidence remains in the
[0.2.2 report](mobile-keyboard-verification.md).

## Requested behavior

Phone and tablet layouts should leave more room for conversation by keeping
the prompt, Context and Add files at the bottom, with the necessary send/cancel
and recovery controls. Routine explanatory and status text should no longer
occupy that area. Version, GitHub, About, Terms and conditions, and Liability
move into left navigation. Model selection becomes a small recognizable control
that opens the existing searchable picker.

The follow-up request adds direct deletion of an unsent draft and improved
alignment of version/source/information links on phone and tablet layouts.
Draft deletion must work from its row without selecting or archiving it first;
the active editor must remain usable after deletion. Footer alignment must keep
all links readable and reachable at narrow widths and enlarged text. These
changes remain part of version 0.2.3.

These changes follow the app's current width/text-scale layout decisions:
compact below 600 logical pixels (or below 800 at 180% text and above), medium
when the expanded layout cannot fit, and expanded from 1100 when text scale and
sidebar/chat width allow it. They do not inspect phone or tablet model names.

## Implementation and invariants

The app retains its existing conversation controller, durable drafts and
attachment storage. Collapsing model selection only changes presentation;
the selected model, searchable catalog and explicit details action remain
available. Information-page navigation still checkpoints the composition before
leaving the app. Expanded layouts retain their model/status strip and footer.

Compact and medium layouts use the same header sidebar action rather than
reserving a permanent rail. The Models control shows an icon and text when it
fits; at narrow widths or enlarged text it uses an accessible icon with the
selected model in its semantics and tooltip. Every variant opens the existing
picker. Context retains the full request estimate behind its explicit action.

Attachment previews, active request/file progress, actionable input failures
and storage recovery remain reachable. Removing routine composer status text
does not remove the shared failure notices or actions.

Unsent draft rows now expose deletion directly. Active-draft deletion waits for
an in-flight save and prevents new saves for that record until deletion commits;
it then clears the composition and recovery marker and opens a writable
workspace. Failure retains text/files for retry. Repeated clicks deduplicate,
and a draft with deletion pending cannot be resumed by model selection.
Unrelated drafts retain their normal saving behavior.

The drawer footer aligns version and GitHub on one row, with an aligned vertical
fallback when enlarged text cannot fit. Information links use full-width,
left-aligned rows rather than irregularly wrapped buttons.

## Final combined local checks

| Check | Result |
|---|---|
| `make verify` | **504 tests passed**, one opt-in live test skipped; **117 Dart files** passed formatting; analyzer and repository checks clean; log: `outputs/023-combined-verify.txt` |
| `make codeg codeg.check` | Passed; **155 files, 2,107 nodes, 8,926 edges and eight tools**; log: `outputs/023-codegraph-final.txt` |
| Scoped Markdown link check | **50 local link targets across five changed documents** resolve |

The final `make build.public` passed (`outputs/023-combined-build.txt`).
Release `d480adf04ff52f68c09e9cb91e698cce7daaa255f24297f79f7d513e76361728`
contains 40 shell assets / 18,274,300 uncompressed bytes. This combined gate and
build include draft deletion and the aligned footer. Browser/publication checks
are being finalized.

### Focused draft regressions

`flutter test test/history/draft_delete_test.dart test/history/draft_lifecycle_test.dart test/presentation/draft_history_ui_test.dart test/history/archived_delete_test.dart --reporter expanded`
passed **34 focused tests**. The deterministic fixtures cover active deletion
with text/files, reload without recovery of deliberately deleted work, writable
replacement, save/delete races, deduplicated deletion, failure preservation,
pending-delete exclusion from model resume, direct row deletion and existing
archive behavior. Log: `outputs/023-draft-green.txt`.

The focused result is also included in the combined gate above. It does not
replace browser checks.

## Coverage and review

The deterministic layout regressions cover 390×844, 820×1180 and 1024×768,
asserting that routine status/footer/rail is absent and Context, Add files,
the header model control and searchable picker remain available. Further tests
retain editor controller, text, caret, selected model and attachment through
compact → medium → expanded → narrow transitions and open the picker at 200%.
Footer tests cover aligned direct links, large-text wrapping, semantics and
durable draft checkpoints before About navigation. These are widget fixtures,
not physical-device results. Independent source review found two draft-delete
edge cases (pending-draft resume and stale attachment error); both were fixed
and re-reviewed without further actionable findings. Impeccable's detector
reported no UI findings and no suppressions were added.

## Browser verification and publication

Actual release-browser checks used an isolated local configuration and a fresh
browser origin. A test-only draft appeared under Drafts and its trash action
removed it immediately without opening the row. The empty prompt remained
writable; a replacement draft was saved, survived reload, and retained its text.
The aligned footer showed the version/source row and three left-aligned
information rows. Context/Add files remained at the composer, and the compact
header control opened model selection. No browser console errors were captured.

The browser's viewport overrides were 390×844 and 820×1180. Its retained 130%
page zoom yielded final observed CSS viewports of 300×649 and 631×908; exact
390/820/1024/1440 logical-pixel coverage is established by widget tests and the
initial layout browser pass. These browser checks are not a physical phone or
tablet test. Enlarged-text links were also checked through keyboard focus and
scrolling. Screenshots are local artifacts under `outputs/023-*.jpg`.
The initial layout browser pass additionally retained a draft, PNG attachment
and selected model through About → Open app and expanded/medium/compact resizing.

No inference POST was required for this UI patch. Real catalog retrieval was
observed, but a live authenticated chat is not claimed. Physical Samsung IME
behavior and phone frame rate were not measured. CI and public deployment
results will be recorded after publication.
