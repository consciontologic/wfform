# Verification and reports

Reports must state their date, revision/release when known, commands, fixture/live/browser distinction and any unverified checks. A prior passing count is not a result for a changed build. Runtime logs and generated screenshots are evidence, not configuration or application source.

## Preserved baseline evidence

- [Public web verification](public-web-verification.md): 7 October 2026 metadata, logo, real release/PWA/browser checks and locally tested GitHub publishing; remote setup remains unverified.
- [Native identity clarification](native-identity-verification.md): 6 October 2026 actual Android/iOS identifiers, restored Dart package name, structural checks and web regression results; native binaries unverified.
- [Workflow and identity verification](workflow-identity-verification.md): 6 October 2026 single Makefile, real CodeGraph MCP queries, Settings gear and Dart package rename checks.
- [Workspace, nginx and rendering verification](workspace-rendering-verification.md): 6 October 2026 migration/scaffold, deterministic tests, actual nginx HTTP/TLS checks and release-browser rendering evidence, with explicit limitations.

- [Initial verification](../verification.md): 5–6 October 2026 initial Flutter/PWA/live API evidence.
- [History/theme/navigation follow-up](../follow-up-verification.md): dated 6 October 2026 follow-up checks.
- [History storage guide](../history.md): deterministic and real Chromium IndexedDB scope.
- [Performance guide](../performance.md): measurement methodology, what artifact/VM numbers do and do not establish.

Historical generated outputs remain under /home/serhatakbak/Documents/Codex/2026-10-05/you-are-astra-implement-and-verify/outputs after the source move. References to outputs in old reports point to that historical workspace. They were not regenerated or copied into the new repository as fresh evidence.

New raw verification logs belong in this project's ignored outputs directory; dated reports here record exact commands and limitations. The [roadmap](../planning/ROADMAP.md) is authoritative for acceptance status.
