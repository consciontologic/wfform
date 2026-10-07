# wfform follow-up verification

This record covers the **6 October 2026** rename, conversation history, theme choices and navigation follow-up. Browser checks used the release at `http://localhost:8765`. Initial implementation evidence remains unchanged in `docs/verification.md` and the original `outputs/` files. Earlier measurements are not presented as measurements of this revision.

## Implemented changes

The browser title, Apple application title, startup messages and manifest name/short name use **wfform**. The existing PWA identity, scope and cache/storage namespaces remain stable. Expanded layouts have a conversation sidebar, medium layouts a navigation rail, and compact layouts a drawer. New conversation and searchable Chats/Archived history are primary navigation; Diagnostics and Settings sit at the bottom. The model chooser remains above the conversation without an adjacent information button. The larger composer adapts its line count to available space and text scaling.

System/Light/Dark appearance preferences persist locally. Popup headers have distinct pastel colors and five local Twemoji graphics. Conversation history uses transactional IndexedDB with a small summary index, lazy conversation bodies, checkpointed drafts/messages, guarded switching, archive/restore/delete, record limits and explicit storage errors. Details are in `history.md`.

## Automated checks executed

- Full formatting check: **41 files, 0 changes**.
- `flutter analyze`: **no issues**.
- Final integrated deterministic test run: **151 tests passed, 1 opt-in live catalog test skipped**.
- `dart run tool/build.dart`: release and PWA assembly succeeded as **hmy9ne1fa6**, including the local emoji correction.
- The release contains **30 precached shell assets, 17,432,380 uncompressed bytes**. `main.dart.js` is **2,720,210 bytes**. These are file sizes, not transfer sizes or a performance-improvement claim.

The two new PWA identity tests check visible names and preservation of install identity, scope and cache namespace. History tests cover persistence and restore, archive/delete rules, model separation, storage failure, bounded records, theme preference, newer-draft recovery and legacy update migration. Lifecycle tests cover busy updates and offline/preflight cancellation. Widget tests cover adaptive navigation, exact viewport dimensions, 200% text, composer/focus continuity and popup assets. These are deterministic tests, not browser IndexedDB or OS-install evidence.

The command transcripts are saved separately as `outputs/wfform-format.txt`, `outputs/wfform-analysis.txt`, `outputs/wfform-tests.txt` and `outputs/wfform-build.txt`. The opt-in automated live catalog test was not rerun; the browser did refresh the real catalog successfully.

## Browser history, themes and PWA update

The browser restored an actual IndexedDB-backed draft across ordinary reload and an explicit PWA update. Changing from Liquid to Nvidia opened a separate empty conversation while preserving the failed Liquid turn. Reopening Liquid restored its original selected model, HTTP 400 failure and unsent draft.

Archive moved that conversation into **Archived**; Restore returned it to **Chats**. An agent-created verification record was rearchived and removed through the explicit **Delete permanently** confirmation. Returning to Chats and reopening the successful Nvidia conversation restored its two messages and retained draft.

Final release **hmy9ne1fa6** appeared as a waiting update without automatic activation. The explicit safe update preserved the selected Nvidia model, two messages, next draft and **Light** preference. Continuing that restored conversation then succeeded, producing four messages. There was no automatic inference resend on restoration.

The final in-app offline-cache inspection, saved as `outputs/wfform-pwa-inspection.json`, reported an **activated** controlling `service_worker.js`, the current **hmy9ne1fa6** cache with **30 entries**, and a retained previous generation with **23 entries**. Cache-policy violations were **zero**, including no cached API, configuration, authorization-bearing or cross-origin requests. `installPromptAvailable` was **false**; no OS installation is inferred from shell readiness. After testing Light and Dark, appearance was returned to **System**.

Browser inspection initially found missing glyphs in Unicode popup decorations. These were replaced with five bundled 72×72 Twemoji PNGs totaling **4,354 bytes**, with attribution and license included. The final screenshots visibly show the diagnostics stethoscope, chooser compass, model-details magnifier and history folder. `outputs/wfform-light.jpg` captures the continued conversation in Light appearance; `outputs/wfform-dark.jpg` captures Dark appearance. Popup/history evidence is in `wfform-diagnostics.jpg`, `wfform-chooser-dark.jpg`, `wfform-details-dark.jpg` and `wfform-history.jpg` under `outputs/`. The history capture shows the saved four-message conversation.

Final native browser rendering was inspected at **871×923**. Diagnostics appeared once in navigation with Settings beneath it, and the model dropdown had no adjacent information button. No further source changes followed the final checks.

## Real API continuation

The Liquid probe's **HTTP 400** was surfaced as a failure; it did not trigger a silent model switch. After explicit Nvidia selection, an initial real request streamed successfully. After the final safe update, the restored conversation was continued with a short question asking how many user messages it contained. The model replied **2**, demonstrating that the restored earlier user turn was included in the continued context.

`outputs/wfform-live-diagnostics.json` records the final `nvidia/nemotron-3-super-120b-a12b:free` endpoint metadata, selected-model probe and chat request with **HTTP 200**. The probe completed at **2026-10-06T06:47:38.773Z** and chat at **2026-10-06T06:47:40.663Z**. The file contains sanitized operational metadata, not credentials or conversation content. These follow-up observations are separate from the initial release's strawberry test.

## Verification scope and remaining limits

The browser-control surface temporarily introduced device-pixel-ratio/canvas scaling artifacts during viewport emulation. Resetting to the native viewport and reloading restored normal rendering. This is a verification-tool limitation, not an unresolved application-defect claim. Deterministic widget tests cover exact adaptive dimensions and text-scaling constraints.

No OS-level PWA installation, additional browser engine, physical touch device or screen-reader listening session is claimed for this follow-up. The original report retains the exact scope of its previously executed offline-shell tests; those tests were not relabeled as new evidence here.

History is origin-local, including the port, and has no cloud sync. Same-conversation edits in multiple tabs are not merged; the last committed write wins. Browser site-data clearing or eviction can remove history. Abrupt tab closure can lose streamed output since the last roughly 800 ms checkpoint; current drafts have scoped synchronous recovery. Messages remain selectable plain text rather than rendered Markdown. A model's successful recent response does not guarantee its next request.

## Later startup-palette alignment

A subsequent change only aligns the minimal web host with the implemented Flutter palette. The old beige startup background/text were replaced with Light **#f8f5fc / #29243b** and system Dark **#191722 / #f4edff**, including matching theme-color metadata. The manifest colors were aligned; its identity, launch URL, scope and cache namespace remain unchanged. System media queries govern the initial host; an explicit app appearance preference takes effect when Flutter starts.

The focused design detector reported **no findings (`[]`)**, and the existing **2 PWA identity tests passed**. The separate full release rebuild succeeded as **hmy9ymluee**, with **30 precached shell assets totaling 17,432,677 uncompressed bytes**. The browser accepted the safe update and preserved the selected model and four-message conversation. Its actual DOM background was `rgb(25, 23, 34)` (**#191722**) and foreground was `rgb(244, 237, 255)` (**#f4edff**); Light/Dark theme-color metadata also matched. `outputs/wfform-palette.jpg` was visually inspected. No live inference was repeated for this color-only adjustment. Review outcome: **1 fixed, 0 suppressed, 0 left standing**.

The focused test/build transcripts are `outputs/wfform-palette-tests.txt` and `outputs/wfform-palette-build.txt`. The preceding 151-test result, release measurements and browser evidence remain records of release **hmy9ne1fa6** and have not been overwritten. **hmy9ymluee** is the later startup-palette build.
