# Mobile keyboard recovery and efficiency patch 0.2.2 — 2026-10-08

Status: implementation, local regression gates, release build, focused browser
checks, public PWA update and publication passed; physical Samsung verification
remains a device follow-up. Baseline
source commit is `6c506d5`. Package version is `0.2.2+7`; app and static page
footers show 0.2.2. The [roadmap](../planning/ROADMAP.md) tracks acceptance.
Earlier release evidence remains in the
[0.2.1 report](composer-continuity-verification.md).

## Reported behavior and scope

The user reports that the installed Android PWA on a Samsung Note 10+ Lite
keeps the software keyboard's reserved space after the keyboard is dismissed,
leaving roughly half the page available until the app is closed and reopened.
The user also reports mild sluggishness on that phone.

The report is evidence of the observed problem; source findings below identify
a matching upstream cause without reproducing the user's physical device.
The patch must retain unsent text and attachments,
normal keyboard typing and dismissal, adaptive layouts, and existing chat and
history behavior.

## Engine investigation and implementation

The baseline uses Flutter 3.38.5. Flutter's upstream
[Android PWA viewport issue](https://github.com/flutter/flutter/issues/175074)
and [engine fix 179581](https://github.com/flutter/flutter/pull/179581) describe
stale keyboard-inset behavior in installed web apps. Source comparison confirms
that the old framework-resize path recalculates physical height while mobile
editing is active, replacing full height with the keyboard-reduced height.
Subsequent inset calculations can therefore retain the shortened viewport.
The fix preserves physical height during mobile editing; browser resize handling
still handles rotation. The fix is included from
3.38.6 onward; see Flutter's
[3.38 branch changelog](https://github.com/flutter/flutter/blob/3.38.10/CHANGELOG.md).
The release moves to the final 3.38 branch patch, **Flutter 3.38.10 / Dart
3.10.9**, keeping the existing application stack. Current setup and CI guides
use that version. Dated evidence retains its original SDK version.

Flutter also supplies an
[upstream regression test](https://github.com/flutter/flutter/blob/3.38.6/engine/src/flutter/lib/web_ui/test/engine/window_test.dart#L739)
for Android editing followed by a framework half-height resize. The app retains
Flutter's normal `resizeToAvoidBottomInset` handling; it adds no viewport shim or
second keyboard-height subtraction.

This is a matching upstream defect and a targeted SDK correction, not proof
that every symptom on the user's phone has been reproduced. The updated engine
built successfully and local regression gates passed. No physical-device fix or
frame-rate improvement is claimed by those checks.

## Mobile UI work

Each mounted `CodeBlock` now retains one highlighted `TextSpan`, invalidated
when source, language or light/dark brightness changes. It does not hold an
unbounded global cache. The existing 180 ms preview cadence reuses that tree
between preview updates; copying still uses the latest complete source.

A deterministic fixture supplies 20 source updates, one every 32 ms over 640 ms.
Identity-distinct generated highlight trees decreased from **21 to four**
(initial tree plus three preview updates), with the final latest-source flush
also asserted. These are synthetic parser-work counts; they do not measure
the Samsung phone's frame time, perceived smoothness or end-to-end inference
speed. The rendering/document/chat efficiency tests passed on the existing SDK
and in the complete upgraded-SDK gate.

## Executed checks

| Check | Result |
|---|---|
| `make verify` | **493 tests passed**, one opt-in live test skipped; **115 files** passed formatting; analyzer and repository checks clean; patched Flutter 3.38.10 / Dart 3.10.9; log: `outputs/022-verify.txt` |
| `flutter test test/presentation/keyboard_lifecycle_test.dart --reporter expanded` | **Three regressions passed** on the patched SDK at 100%, 125% and 200% text scale; injected Flutter view metrics, not a physical IME; log: `outputs/022-keyboard.txt` |
| `flutter test --platform chrome test/history/browser/indexeddb_checks.dart --reporter expanded` | **Seven real Chromium storage checks passed** with isolated fixture data; log: `outputs/022-browser-storage.txt` |
| `python3 -m unittest discover -s xops/makefile -p 'test_*.py' -v` | **14 repository-operation tests passed**; log: `outputs/022-ops.txt` |
| `make codeg codeg.check` | Passed; **153 files, 2,085 nodes, 8,822 edges and eight tools**; log: `outputs/022-codegraph.txt` |
| `make build.public` | Credential-free release PWA build passed; log: `outputs/022-build.txt` |
| `flutter test test/shared/seo_metadata_test.dart test/shared/pwa_identity_test.dart --reporter expanded` | **15 passed** on the existing Flutter 3.38.5 SDK before the upgraded SDK gate; version/footer consistency and retained PWA identity, not keyboard recovery |
| `flutter test --no-pub test/presentation/document_rendering_test.dart test/documents test/chat/efficiency_test.dart --reporter expanded` | **26 passed** on existing Flutter 3.38.5; source, grammar, brightness, latest-source copy and repeated-update highlight work were checked |
| Isolated project SDK initialization | `flutter --version` reports **3.38.10**, framework `c6f67dede3`, engine `cafcda5721`, Dart **3.10.9**; log: `outputs/022-sdk-init.txt` |
| Scoped documentation link check | **83 local Markdown links across nine changed documents** resolve |
| `git diff --check` | Passed after the metadata and documentation edits |

Final release:
`63ffaedf4ba462be8eceeb241c0a0f6afc406c620e35967ea80d82b03cffaadf`.
The shell contains **40 assets / 18,274,364 bytes**. These are uncompressed
artifact sizes, not measured mobile network transfer or startup latency.

Metadata/version checks alone do not establish keyboard recovery or runtime
performance. Metadata test log: `outputs/022-metadata.txt`.

The three passing application geometry regressions exercise keyboard show → hide → show
cycles at **100%, 125% and 200% text scale**, asserting full-height restoration
and retention of composer text, files, caret and focus. The 200% case first
failed because long enlarged input plus a file pushed the editor below the
visible area. While the keyboard is visible, the editor now shows two lines
(one with enlarged text) and bounds the attachment strip more tightly. The same
controller scrolls longer input internally and expands on dismissal. All three
tests passed on the patched SDK. These tests inject Flutter view metrics; they
verify application layout and state continuity, not the underlying browser
engine or a physical IME. Log: `outputs/022-keyboard.txt`.

## Release-browser observations

The actual public release build was served with isolated configuration at
localhost:8773 and checked in Chromium. The live catalog showed 17 compatible
chat models and 68 listings. A typed draft with JavaScript and PNG attachments
survived 412×846 → 412×536 → 412×846 resizing, a landscape-sized 846×412 view,
return to portrait, and an ordinary reload. The full-height footer returned;
both file chips and the exact draft remained visible. The source preview opened
and Copy code returned the exact fixture, including its latest source. The
browser error log was empty. Screenshot: `outputs/022-mobile-restored.jpg`.

These desktop viewport operations exercise release rendering and persistence;
they do not raise or dismiss an Android software keyboard. The 100%, 125% and
200% keyboard-inset coverage above comes from deterministic Flutter tests.

On the public HTTPS origin, an existing 0.2.1 tab was kept open with an unsent
fixture and a JavaScript attachment. Settings → Check for update offered
Save & update after publication. Applying it loaded version 0.2.2 and retained
the exact composition, selected model and file chip. The version and retained
composition are captured in `outputs/022-live-update.jpg`. No chat was sent.

## Publication and verification limits

Source commit `76db986` passed
[CI run 37737229068](https://github.com/consciontologic/wfform/actions/runs/37737229068).
Website commit `0d3956f` passed
[Pages run 37737509800](https://github.com/consciontologic/wfform.com/actions/runs/37737509800).
The HTTPS public release manifest, compiled JavaScript, index, About, Terms,
Liability and web manifest match the local artifacts byte for byte. Integrity
evidence is in `outputs/022-published-integrity.json`.

No Android device is
available through ADB for this check. Desktop browser viewport resizing does not
reproduce the installed Samsung PWA's software keyboard. No new live inference,
physical Samsung device, native application or mobile frame-time measurements
have been performed for this patch. Prior release results are historical.

A physical-device follow-up should open the installed PWA, enter an unsent
composition with an attachment, repeatedly show and dismiss the keyboard using
Android Back and outside taps, and confirm full-height recovery without losing
the composition. Repeat after app background/resume and portrait/landscape
rotation; record the actual Android and browser versions with any remaining
failure.
