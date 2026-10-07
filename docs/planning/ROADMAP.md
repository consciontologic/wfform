# wfform roadmap

Updated 2026-10-07. This is the authoritative current user scope, not a scaffold example or a promise of unrelated future work. Application baseline behavior is documented below; only the requested extension has checkboxes.

## Status snapshot

| Phase | Deliverables | Done | Status |
|---|---:|---:|---|
| Workspace, documentation, deployment and rendering | 7 | 7 | Complete; verified evidence and limits in the current report |
| Repository workflow and application identity | 4 | 4 | Complete; current report records live MCP and browser verification |
| Native application identifier clarification | 1 | 1 | Complete; native configuration and web regression checks passed; native binaries unverified |
| Search metadata, web publishing and brand mark | 3 | 3 | Complete locally; public hosting and search indexing remain separate |
| GitHub account migration | 3 | 3 | Complete; fresh history and real compiled-artifact publication verified |
| Free GitHub Pages hosting | 2 | 1 | Public subpath build verified; live publication and browser checks in progress |

## Established application baseline

The app already provides Flutter web/PWA discovery and chat; validated free pricing; cached catalog and scoped health; streaming/cancellation/retry; local normalized history, archive/restore/delete and export/import; edit/resend and model-aware media; explicit context/output control; adaptive selectable UI with Light/Dark/System modes; and bounded diagnostics. Previous verification is preserved with its date in the [reports index](../reports/README.md). These are context, not newly completed items in this phase.

## Phase 1 — Workspace, documentation, deployment and rendering

Scope ID: workspace-adaptation. The following six groups correspond to the user's current six bullets. All application work remains Flutter/Dart; Python/shell xops are operations only.

### 1. Move the project

- [x] Move application files to /home/serhatakbak/code/projects/wfform, preserve existing destination main/origin and unrelated files, retain historical outputs at their documented original location, and verify commands from the new working directory.

### 2. Apply the agentic-workspace scaffold

- [x] Apply /home/serhatakbak/code/projects/agentic-workspace using the full preset without forced replacement or automatic MCP setup; verify installed operating surfaces and the preserved application.

### 3. Ignore the local API key

- [x] Verify local credential configuration and generated copies remain ignored, absent from the staged set, and excluded from Docker context/image; keep the checked-in example credential-free.

### 4. Fill documentation and adapt agent configuration

- [x] Populate actual project/architecture/module/API/design/ADR/context documents and correct their indexes/links while preserving detailed and dated application documentation.
- [x] Adapt agent instructions, client configurations and repository automation to Flutter, the moved paths, the real test gates, the unborn main branch and the explicit no-MCP choice.

### 5. Containerized nginx workflow

- [x] Provide documented make/xops commands for a containerized static Flutter PWA with nginx, runtime configuration handling, TLS/header checks and meaningful tests; report actual observed headers and any unverified external grade instead of claiming an unsupported A+++ rating.

### 6. Common file and content rendering

- [x] Implement and verify broad reasonable local file-extension handling, including Markdown, JSON, YAML, JavaScript and C/source text, with built-in readable rendering/previews and corresponding input/history behavior; preserve model capability and zero-price request guards.

## Acceptance gates for the whole phase

Run commands that exist in the final Makefile and document their exact results. Required evidence includes formatting/analysis, relevant deterministic regression tests, release PWA build, repository/scaffold/config checks, container/header checks where Docker is available, and release-browser verification of the changed rendering/deployment path. Tests using fake transports or generated storage databases must remain distinguished from live service/browser checks. External blockers identify the specific skipped check, not a blanket success.

Documentation-only work requires current source review and local link/placeholder checks; it does not manufacture a new live API or security-grade result. The parent coordinates the final full gate, updates this snapshot/checklist, appends tracking and applies the repository's staging policy. Agents never commit or push.

Completed evidence: [workspace, nginx and rendering verification](../reports/workspace-rendering-verification.md). This records the final release identities, deterministic/real-browser distinction, current Docker header checks and unverified external/native scope.

## Phase 2 — Repository workflow and application identity

Scope ID: workflow-identity. Requested 2026-10-06 after Phase 1.

- [x] Consolidate all repository and application targets into one root Makefile; preserve help, defaults and command behavior.
- [x] Enable CodeGraph for this repository, replace active no-MCP instructions, build the index and verify real graph queries; document supported languages and actual client-connection limits.
- [x] Use a bundled gear emoji in the Settings window; verify light/dark, narrow text scaling and the running release.
- [x] Replace the old Dart package identity with a valid form of the requested `com.wfform`, update imports and documentation, preserve installed PWA/storage identity, and verify dependency resolution, analysis, tests and release builds.

This phase initially interpreted the request as a Dart package rename to `com_wfform`, reserving `com.wfform` for future native setup. The user's subsequent clarification is implemented in Phase 3 below. Historical verification records remain unchanged.

Completed evidence: [workflow and identity verification](../reports/workflow-identity-verification.md).

## Phase 3 — Native application identifier clarification

Scope ID: native-identity. Requested 2026-10-06: `com.wfform` means the Android/iOS application identifier.

- [x] Configure actual Android/iOS host projects with `com.wfform`, use `wfform` for the Dart package/imports, preserve the web application and installed identity, verify native configuration and web regression gates, and document native build/adapter limitations.

Completed evidence: [native identity verification](../reports/native-identity-verification.md).

## Phase 4 — Search metadata, web publishing and brand mark

Scope ID: public-web. Requested 2026-10-07.

- [x] Add truthful project/search/sharing metadata, public crawlable product information, canonical URLs and sitemap; preserve Flutter UI ownership and PWA identity, and verify release assets and browser startup.
- [x] Add GitHub Actions CI and automatic verified web-artifact commits/pushes to `consciontologic/wfform.com` on source `main` pushes; document required token/host setup and test publishing without exposing local credentials or overwriting unrelated destination files.
- [x] Replace the header arrow with a wrapper/conversation brand mark and matching web icons; verify adaptive layouts and light/dark rendering.

Remote GitHub execution, custom-domain DNS and Google indexing require external setup and are reported separately from local checks. The workflow observes pushed commits, not unsaved local edits. No agent commits or pushes source changes.

Completed evidence: [public web verification](../reports/public-web-verification.md).

## Phase 5 — GitHub account migration

Scope ID: repository-migration. Requested 2026-10-07; the user explicitly
authorized a fresh Git history, source push and pipeline launch.

- [x] Update active repository metadata, publishing target, instructions and guides to `consciontologic/wfform` and `consciontologic/wfform.com`; retain dated evidence and tracking records.
- [x] Push the current application as a fresh history to the new source repository, retaining an ignored local backup of the old Git metadata.
- [x] Start the new account's workflow and verify the compiled web files reach the new publication repository; report any external blocker precisely.

Completed evidence: [account migration and real publication](../reports/account-migration-verification.md). Public Pages/DNS serving remains a separate hosting step.

## Phase 6 — Free GitHub Pages hosting

Scope ID: github-pages. Requested 2026-10-07; the user clarified that they do
not own `wfform.com` and chose the free GitHub project URL.

- [x] Adapt the public build, publishing ownership, metadata and guides for `https://consciontologic.github.io/wfform.com/`, keeping root local/Docker serving intact.
- [x] Enable Pages with no custom domain, publish the release and verify live HTTPS, browser startup, catalog and PWA scope.

Completed evidence: [live GitHub Pages verification](../reports/github-pages-verification.md).

## Phase 7 — Owned custom domain

Scope ID: custom-domain. Requested 2026-10-07 after the user purchased
`wfform.com` and configured Namecheap DNS.

- [x] Restore root public build paths, custom-domain publication and SEO metadata with regression coverage; update current guides.
- [x] Configure GitHub Pages for `wfform.com`, publish the verified release, enforce managed HTTPS and verify the public browser, live catalog and PWA scope.

Completed evidence: [custom-domain verification](../reports/custom-domain-verification.md).
