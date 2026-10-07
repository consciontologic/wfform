# Composer continuity patch 0.2.1 — 2026-10-07

Status: implementation, local release gates, browser checks and publication
passed. The baseline is source
commit `3d92924`. Package version is `0.2.1+6`; app and static page footers show
0.2.1. Earlier release evidence remains in the
[0.2.0 report](conversation-drafts-verification.md).

## Confirmed causes

Source inspection identified two paths that replaced the visible composer:

- The Flutter footer opened About in a separate `noopener` tab. Its **Open app**
  link then launched a new app instance in that tab. Active conversation and
  immediate text recovery are tab-local; durable IndexedDB history remained,
  but the new instance did not inherit the original tab's active workspace.
- Model selection saved the source workspace, then restored the destination
  model's draft or a blank workspace. The text controller followed that state;
  no controller-disposal defect was found. Saved source content could still be
  reopened from Drafts, but was no longer visible in the composer.

These are navigation/state causes, not evidence of an API failure or a server
root/fallback-routing defect.

## Changed contract

Model changes retain unsent composer text and files. A workspace without
messages changes model in place. A message-bearing conversation keeps its
history while a separate target workspace carries the unsent input. Existing
target drafts are retained; an empty composer can resume one. Incompatible
files remain visible and must be removed or used with a compatible model before
sending.

Internal information links use the same tab after a successful checkpoint.
Pending requests, file picking, competing history transitions and failed saves
prevent navigation. About's Open app link therefore returns through the same
tab-local restoration identity. External GitHub links still open separately.

## Executed local checks

| Check | Result |
|---|---|
| `make verify` | **488 tests passed**, one opt-in live test skipped; 114 files passed formatting, analyzer and repository checks were clean; log: `outputs/021-verify.txt` |
| `flutter test --platform chrome test/history/browser/indexeddb_checks.dart --reporter expanded` | **Seven real Chromium storage checks passed**, using isolated fixture data |
| `python3 -m unittest discover -s xops/makefile -p 'test_*.py' -v` | **14 repository-operation tests passed** |
| `make codeg codeg.check` | Passed; **152 files, 2,068 nodes, 8,741 edges and eight tools** |
| `make build.public` | Final credential-free release PWA build passed |
| Scoped metadata/PWA tests | **15 tests passed**, including footer version consistency and retained PWA identity |
| Scoped documentation check | **73 local Markdown paths across eight documents** resolved; `git diff --check` passed |

The deterministic regressions cover composer text/files through model changes,
existing target drafts, incompatible files, message-history separation and save
failures. Navigation tests cover checkpoint completion, refusal while busy or
picking files, failed storage, same-tab information links and separate-tab source
links. Their controlled stores/transports are fixtures, not live inference.

Final release:
`04c2536a8a6887e7880fbe41a0ab46bfbb42239131eeb65310687726b11bab97`.
The shell contains **40 assets / 18,273,854 bytes**.

## Completed release-browser observations

At `http://localhost:8772`, the actual catalog loaded **17 chat-compatible models
and 68 listings**. These counts are dated observations, not test expectations.
The browser used typed fixture text and the real file picker to attach Markdown
and PNG files. Changing from Gemma 4 to text-only Apodex retained the text and both
files, and showed the incompatible-image message instead of discarding it.

About opened in the same browser tab. Its **Open app** link restored the
composition, including both files. **Save & update** applied the final release
above and retained the composition afterward.

Browser Back and ordinary reload also retained the exact text and both files.
Markdown source content and the PNG preview reopened after reload, checking more
than attachment names. The composition survived live resizing at 390×844,
820×1180 and 1440×900. The compact Info → About → Open app route also returned
to the same populated composer. Switching back to an image-capable Gemma model
retained both attachments. No browser console errors were observed. Screenshots
are retained in ignored `outputs/021-mobile-draft.jpg` and
`outputs/021-desktop-draft.jpg`.

## Publication and verification limits

Source commit `2c755b5` passed GitHub CI
[37675339117](https://github.com/consciontologic/wfform/actions/runs/37675339117),
including analysis/tests, repository operations, Chromium storage, release build,
artifact validation and publishing. Website commit `94b24a2` passed GitHub Pages
[37675720016](https://github.com/consciontologic/wfform.com/actions/runs/37675720016).
The website repository and `https://wfform.com/release.json` match the exact local
release above. Downloaded public JavaScript, index, About, Terms, Liability and
manifest SHA-256 hashes all match the local release manifest.
An isolated verification tab on the public origin offered **Save & update**
from cached 0.2.0 and displayed **Version 0.2.1** after applying it. The existing
user tab was left untouched. Public screenshot: `outputs/021-public-release.jpg`.

No new live chat POST was made for this patch. Saved-key continuity is covered
by the executed regression/storage tests, not a new manual key-entry test. No new
Safari, Firefox, native-platform or physical-device evidence is claimed. Earlier
0.2.0 results remain historical and do not certify this release.
