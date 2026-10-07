# Public pages and version 0.1.0 — 2026-10-07

## Delivered

The supplied Google tag `G-P3K2ZN7YTL` appears exactly once immediately after
`<head>` in the app host, About, Terms and Liability documents. It adds no
custom chat, attachment, key or user-ID events. About/Terms describe Google
Analytics and browser storage; terms use conditional applicable-law language
and do not invent a legal entity, jurisdiction or legal compliance guarantee.

Public pages share responsive local styles, accessible section navigation,
source artwork and linked versioned footers. The Flutter footer shows
**v0.1.0**, direct information links on wide screens and an Info menu on narrow
screens. Links open separately, retaining the active chat. The footer yields
space to an open software keyboard. The package version is `0.1.0+1`; tests
check agreement with the app constant and static documents.

README is reduced to 48 visitor-oriented lines. Detailed setup/configuration
and usage remain in existing guides. Tracked documents and instructions use
portable paths; a test rejects literal personal home-directory paths in
prospective repository text files. Ignored local configuration and recovery
state remain local. Existing published Git history is unchanged.

## Executed local gates

| Check | Observed result |
|---|---|
| `make verify` | Formatting and analysis passed; 386 app/tool tests passed, one opt-in live test skipped; repository check passed |
| New regression coverage | Exact/unique tag placement, version/footer/page links, unique IDs/fragment targets, responsive footer/keyboard semantics, URL opening with preserved drafts, portable docs and CSP hash |
| `python3 -m unittest discover -s xops/makefile -p 'test_*.py' -v` | 14 passed |
| `make codeg` and `make codeg.check` | Passed; actual MCP protocol checks, 140 indexed files, 1,868 nodes, 7,622 edges at this run |
| `make build.public` | Successful Flutter release/PWA build |
| Docker image from `deploy/package.dart` output | Built successfully; configuration excluded |
| `dart run deploy/check.dart http://127.0.0.1:8766` | Real nginx HTTP headers, health, method/error policy, config absence, WASM MIME and all 41 immutable asset hashes passed |

Release `2203257bcd8156dbfb2a70436e52b513b7ee45f513c610006f2d57b4a2eb747b`
contains **41 shell assets / 18,243,394 bytes**. The existing nonfatal
Cupertino font-family warning remains. The tag is asynchronous; its external
Google resources are excluded from the PWA cache. Nginx permits the loader
and the exact inline SHA-256 hash, without unrestricted inline JavaScript.
Raw logs are local and ignored under `outputs/info-*.txt` and the safe-run logs.

## Actual browser observations

A disposable nginx container served the credential-free release at loopback
port 8766. This separate origin avoided existing personal conversations.

- The app rendered the new version/footer and the live free-model catalog.
- About opened in a separate browser tab; the original app retained the unsent
  test draft. Keyboard activation also worked.
- About, Terms and Liability rendered as readable HTML. At an observed
  320-pixel document width, scroll width also measured 320: no horizontal
  page overflow. Footer links, source doodle and keyboard focus stayed visible.
- The Terms content anchor scrolled to the uniquely identified section.
- Clicking the GitHub doodle reached the intended source repository.
- The DOM contained one Google loader on the inspected page. App/static-page
  console checks showed no warning/error or CSP-block messages.

Exact 320-pixel/200% app-text layout, software-keyboard behavior and opener
failure handling are covered by deterministic widget tests; this is separate
from the real-browser checks above. No authenticated chat content was sent.
Google Analytics Realtime/account ingestion, legal enforceability, native
builds and a fresh offline/install acceptance run are not asserted.
