# Roadmap

This is the current checklist. Completed implementation detail lives in Git history,
[CHANGELOG.md](../../CHANGELOG.md) and the maintained [guides](../README.md), not
per-change reports. Do not infer native/browser/public-release success from mock tests.

## Current status

**1.0.0 is published** with web, Linux and Windows portable companion downloads.
The static app is at `https://wfform.com/`. Gitflow and the owner's final production
approval remain required. Routine delivery automation is removed. GHCR publication
is configured for the next approved release; no 1.0.0 image was published.

**1.0.1 is prepared** with compact, consistently ordered composer controls; publication
still follows the protected PR and human-approved release process.

## Phase 28 — PR review fixes, asset cleanup and concise docs

- [x] Fix every actionable open PR finding with appropriate regression coverage.
- [x] Remove unused emoji assets, code/docs references and tests of removed behavior;
  retain fonts and licenses because the interface/public pages/code still use them.
- [x] Replace per-change reports and repeated long docs with concise current contracts,
  examples, operations and research guidance; remove obsolete media and repair links.
- [x] Pass `make verify`, affected ops/docs/package checks and independent review;
  prepare the Gitflow bugfix branch for publication into `develop` through `make git`.

Acceptance: no lost prior work, no broken local documentation references, no credential
leak, preserved app/font behavior and unchanged production-approval policy.
The PR and tracking log record publication and remote CI; local checks do not imply merge.

## Phase 22 — Companion platform downloads and easy installation

Portable Linux/Windows packages already exist. The remaining goal is
**download → install/open → launch wfform**, without developer SDKs, terminal setup,
manual token copying or JSON editing. Ordinary chat stays usable without tools.

- [ ] Define supported Linux distributions/minimum OS/architectures and choose the
  graphical package format plus clean-machine acceptance environments.
- [ ] Add Linux graphical install, launcher and uninstall with bundled runtime/web UI.
- [ ] Add a per-user Windows graphical installer, Start-menu shortcut and uninstall;
  report signing status and test the actual downloaded installer.
- [ ] Verify native process-tree cancellation, private settings/token permissions and
  paths with spaces/Unicode in clean installed Linux/Windows environments.
- [ ] Add first-run private setup, stable loopback address, browser launch and explicit
  pairing approval without long-lived tokens in URLs/logs. Reuse an existing instance;
  an occupied port must not silently move users to a new history origin.
- [ ] Add graphical tool/MCP setup, dependency errors and status/quit. Keep autostart
  opt-in; preserve settings/history through upgrades; ask before removing user data.
- [ ] Validate graphical download/install/pair/CLI/MCP/upgrade/uninstall and bounded
  opt-in live tool loops per advertised OS/architecture, including no-SDK machines.
- [ ] **Deferred macOS:** obtain native build/test/signing/notarization access; produce
  and validate each advertised Apple Silicon/Intel variant through the same journey.

Keep exact-origin/bearer checks, per-tool approval, explicit reconnect and no replay.
Tools stay disabled until chosen; installation must not import credentials or grant
whole-PC access. Do not advise disabling OS protections to bypass signing warnings.
A successful build is not installer acceptance. Implementation belongs in companion,
existing setup UI, build helper and their native/browser/package tests.

## Other open acceptance work

- [ ] First future approved GHCR publication: verify pushed version/digest, configure
  Public visibility and test anonymous pulls. Never overwrite existing versions.
- [ ] Android/iOS durable adapters, file handling, credential storage, signed builds
  and actual device acceptance; see [native status](../native-platforms.md).
- [ ] Installed-PWA keyboard/install/update checks on physical target phones and
  additional browser engines; viewport emulation is not equivalent evidence.

## Completed milestones

| Scope | Result |
|---|---|
| Phases 1–7 | Existing Flutter app integrated with project operations, CodeGraph, safe file rendering, static containers, native host identity and custom-domain Pages. |
| Phases 8–17 | Responsive model/history controls, public information, durable drafts/keys, composer continuity and compact navigation through 0.2.4. |
| Phases 18–20, 24 | Transparent light/dark identity evolved into current Open Cradle artwork. Earlier publication tracking is superseded by published 1.0.0. |
| Phases 21, 23 | Advertised parameter overrides, approved MCP/CLI loops, readable structured data, simple guides and native Windows packaging. |
| Phase 25 | Desktop-only tools, example playground, SemVer/Gitflow and free quality/security gates. |
| Phase 26 | Final human production approval retained. Routine task/merge/release orchestration was subsequently removed. |
| Phase 27 | Explicit delivery plus guarded future GHCR publishing; native packages and container smoke validated. |

Operational tests and release claims remain tied to the source/run that produced them.
Future work does not retroactively extend prior verification to new platforms.
