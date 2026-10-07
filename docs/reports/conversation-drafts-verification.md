# Conversation drafts and saved connection 0.2.0 — 2026-10-07

## Changes

Unsent work has a separate Drafts view. Empty workspaces and selecting a model
do not create chat history. A transport-dispatch marker distinguishes sending
user content from accepting a turn or probing model health. Existing history,
archive access, attachment storage and conflict recovery remain supported.
Drafts resume per model and across navigation/reload. Archiving the active chat
opens a writable draft. The active row shows response progress, with a static
accessible alternative for reduced motion. The existing one-request-at-a-time
policy remains; this release does not introduce parallel background requests.

Settings explicitly saves/replaces or clears a browser-local key. A saved empty
override prevents runtime configuration from restoring a cleared key. Writes
are read back before success is reported; failures leave the current connection
unchanged and expose content-free diagnostics. Browser site-data clearing and
private-browsing policies can remove local data. Native persistent storage is
still unimplemented. Package version is `0.2.0+5`; visible footers show 0.2.0.

## Executed checks

| Check | Result |
|---|---|
| `make verify` | 476 tests passed; one opt-in live test skipped; formatting, analysis and repository checks passed |
| `python3 -m unittest discover -s xops/makefile -p 'test_*.py' -v` | 14 repository-operation tests passed |
| `flutter test test/presentation/app_footer_test.dart --reporter expanded` | Six version/footer tests passed |
| `flutter test --platform chrome test/history/browser/indexeddb_checks.dart --reporter expanded` | Seven real Chromium storage tests passed, including saved-key restoration and explicit clearing |
| `make codeg codeg.check` | Real MCP/Dart queries passed; 151 files, 2,048 nodes, 8,579 edges and eight advertised tools verified |
| `make build.public` | Final credential-free release PWA build passed |
| Docker packaging/build | Allowlisted nginx image built; local runtime configuration mounted separately |
| `dart run deploy/check.dart http://127.0.0.1:8771` | Actual headers, method/error policy, configuration no-store, WASM MIME and all 40 immutable asset hashes passed |

The final gate includes late-runtime-configuration and saved-key race
regressions. Deterministic transport tests exercise draft promotion, navigation,
archive recovery, cancellation, partial/error streams, reduced motion and narrow
layouts; their successful responses are fixtures, not live inference. The seven
storage tests use actual browser storage with controlled test data.

The bounded opt-in public API check also passed:
`flutter test test/models/catalog_test.dart --dart-define=RUN_LIVE_CATALOG=true --plain-name live --reporter expanded`.
At 17:42 UTC it inspected 663 entries, found 68 free-price candidates,
17 chat-compatible models, seven unresolved-price exclusions and zero
quarantined entries. These are observations, not fixture expectations.

Final release:
`42ce0063e29497f521e6adfe27b07c4e131e1740ea6a1dbe5e0d77ede33800b9`.
The shell has **40 assets / 18,270,168 bytes**. The nonfatal Cupertino
font-family warning remains. Raw verification logs are ignored in
`outputs/020-*.txt`; credentials and conversation content are not included in
this report.

## Browser evidence

Local release-browser checks covered 390 × 844, 820 × 1180 and 1440 × 900
viewports, including 200% text on the compact layout. Draft navigation retained
unsent text. An imported conversation fixture exercised archive switching and
the writable composer after archiving; that imported history is not evidence
of live model output.

The first selected-model health probe returned HTTP 400 for a model requiring
reasoning. Removing the incompatible probe override allowed an explicit Retry
to complete a real authenticated LiquidAI streaming request. The draft entered
Chats only when user content was dispatched, and the separate unsent draft was
preserved. This was one bounded successful observation, not a guarantee of
future model availability. A second bounded live request on the final build
showed the sidebar Responding indicator and cleared composer while streaming,
then completed. No automatic content resend was introduced.

The browser detected two successive local PWA updates. The safe update flow
preserved the draft across both reloads. The final build's nginx headers and
asset integrity were checked separately after the late configuration-race fix.

With Work offline enabled and the local nginx container stopped, an actual
reload loaded the cached shell and saved history, marked the catalog cached,
and disabled remote chat. Saving and clearing the connection were exercised
through Settings. After closing and reopening the QA tab, the cleared field
stayed empty despite a runtime configuration key. Exact nonempty key restoration
is covered by the seven real Chromium storage tests; browser automation masks
password values. The browser process itself was not restarted.

## Pending publication and limits

Publication of 0.2.0, its GitHub workflow and the
resulting public deployment have not yet been verified. These remain open in
Phase 13 of the [roadmap](../planning/ROADMAP.md). No new Safari, Firefox,
native-platform or physical-device evidence is claimed.
