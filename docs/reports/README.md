# Verification and reports

Reports must state their date, revision/release when known, commands, fixture/live/browser distinction and any unverified checks. A prior passing count is not a result for a changed build. Runtime logs and generated screenshots are evidence, not configuration or application source.

## Current application evidence

- [Soft wrapper branding](soft-wrapper-branding-verification.md): approved logo and ten companion icons, transparent light/dark variants, browser-tab/PWA/native launcher sources, 532 passing tests, public build and local browser checks; remote deployment and native builds remain separate.

- [Compact navigation refinement 0.2.4](compact-navigation-verification.md): persistent Models label and smaller drawer version/GitHub/Info row; regression gate, local browser checks, CI, Pages, public asset integrity and actual public PWA update passed.

- [Compact conversation controls patch 0.2.3](compact-controls-verification.md): compact composer/model controls, aligned drawer links and direct draft deletion; combined tests, release browser checks, CI, Pages and public asset integrity passed.

- [Mobile keyboard recovery and efficiency patch 0.2.2](mobile-keyboard-verification.md): patched Flutter engine, keyboard-height geometry regressions and bounded highlighting work; local gates, browser update, CI and public asset verification passed; physical device unverified.

- [Composer continuity patch 0.2.1](composer-continuity-verification.md): corrected information-page and model-switch continuity; local gates, browser draft/file return and reload checks, CI and public asset verification passed.

- [Conversation drafts and saved connection 0.2.0](conversation-drafts-verification.md): separate Drafts, response activity, writable archive recovery and saved-key behavior; final local gates, release/container and live API/browser evidence, with remaining browser checks and publication pending.

- [Sidebar surface and quiet startup patch 0.1.3](sidebar-startup-patch-verification.md): continuous sidebar fill, removal of the transient intro, bootstrap-download recovery and release/browser checks.

- [Footer and composer focus patch 0.1.2](footer-focus-patch-verification.md): plain source links, removed documentation templates, explicit outside focus handling and release/browser checks.

- [Sidebar and passport patch 0.1.1](sidebar-passport-patch-verification.md): collapse/edge reveal, concise model metadata, direct archived deletion, accessibility regression fixes and release checks.

- [Public pages and version 0.1.0](site-pages-verification.md): Google tag placement, linked information pages, responsive footer, portable repository docs and local/remote verification evidence.

- [Sidebar and model readability](sidebar-readability-verification.md): 7 October 2026 adaptive resizing, 125% text, truthful source descriptions and release/browser regression checks.

## Current migration evidence

- [Custom-domain hosting](custom-domain-verification.md): 7 October 2026 purchased `wfform.com`, managed HTTPS, root release, redirects and actual browser/catalog/cache verification.
- [Live GitHub Pages hosting](github-pages-verification.md): 7 October 2026 successful deployment at the free project URL, actual browser/catalog/PWA scope checks and exact verification limits.
- [GitHub account migration](account-migration-verification.md): 7 October 2026 fresh source history, successful real GitHub pipeline and authenticated compiled-artifact publication to the new account.

## Preserved baseline evidence

- [Public web verification](public-web-verification.md): 7 October 2026 metadata, logo, real release/PWA/browser checks and locally tested GitHub publishing; remote setup remains unverified.
- [Native identity clarification](native-identity-verification.md): 6 October 2026 actual Android/iOS identifiers, restored Dart package name, structural checks and web regression results; native binaries unverified.
- [Workflow and identity verification](workflow-identity-verification.md): 6 October 2026 single Makefile, real CodeGraph MCP queries, Settings gear and Dart package rename checks.
- [Workspace, nginx and rendering verification](workspace-rendering-verification.md): 6 October 2026 migration/scaffold, deterministic tests, actual nginx HTTP/TLS checks and release-browser rendering evidence, with explicit limitations.

- [Initial verification](../verification.md): 5–6 October 2026 initial Flutter/PWA/live API evidence.
- [History/theme/navigation follow-up](../follow-up-verification.md): dated 6 October 2026 follow-up checks.
- [History storage guide](../history.md): deterministic and real Chromium IndexedDB scope.
- [Performance guide](../performance.md): measurement methodology, what artifact/VM numbers do and do not establish.

Historical generated outputs remain under the original session's ignored outputs directory after the source move. References to outputs in old reports point to that historical workspace. They were not regenerated or copied into the new repository as fresh evidence.

New raw verification logs belong in this project's ignored outputs directory; dated reports here record exact commands and limitations. The [roadmap](../planning/ROADMAP.md) is authoritative for acceptance status.
