# wfform shared context pack

## Identity and current location

- Product: **wfform — Wrapper for Free Open Router Models**.
- Purpose: discover free OpenRouter models and continue browser-local conversations.
- Application: Flutter/Dart, verified release target web/PWA; Dart package is `wfform`. Android namespace/application ID and iOS Runner bundle ID are `com.wfform`. Native hosts are configured but native builds and adapter parity remain unverified; PWA/storage identities remain stable.
- Canonical workspace: this repository's root.
- Git origin: https://github.com/consciontologic/wfform.git. On 2026-10-07 the user explicitly authorized migration to this account without prior Git history, source push and pipeline launch. The old local Git metadata is preserved under ignored `.local/git-history-backup/`. Future history replacement still requires an explicit request.
- Historical chat outputs remain in their original local workspace; machine-specific paths are not published.
- Scaffold source/revision: the local `agentic-workspace` checkout at a93e0d95e665748c700faa677cc5e8cfdb6c3ca8, full preset with --no-mcp and no --force on 2026-10-06. No Dart language preset existed.

## Latest completed work

The [roadmap](../planning/ROADMAP.md) records the completed six-part migration/scaffold/ignored-key/documentation/container/rendering request. The [current report](../reports/workspace-rendering-verification.md) records 321 deterministic tests, six real IndexedDB checks, seven framework operations tests, release builds and actual Docker/browser checks with explicit limitations. The coordinating parent owns final tracking/staging and now publishes validated Gitflow work branches through `make git` under AGENTS.md §2. Subagents return evidence and preserve concurrent edits; `main`/`develop` change only through reviewed PRs.

The subsequent [workflow and identity follow-up](../reports/workflow-identity-verification.md) consolidated the Makefile, enabled and verified CodeGraph, changed Settings to a gear emoji and renamed the Dart package to `com_wfform`. Its final gates passed 321 Flutter tests, six real IndexedDB checks and 13 repository-operation tests, plus real MCP queries and release/browser/header checks. Earlier reports remain dated evidence.

The user's [native identifier clarification](../reports/native-identity-verification.md) supersedes that package interpretation: Dart is `wfform`, actual Android/iOS host IDs are `com.wfform`. Native configuration was checked; web regression and release gates passed. Native binary builds and adapter parity remain outside verified scope. See [native setup](../native-platforms.md).

On 2026-10-07 the [public-web follow-up](../reports/public-web-verification.md) added SEO metadata/static product documentation, a bracketed conversation logo and GitHub CI/CD to `metaphy6/wfform.com`. The workflow needs source Actions secret `WFFORM_DEPLOY_TOKEN` (target Contents read/write) and destination Pages/DNS setup. Public builds exclude local configuration; local gates and browser checks passed, while remote publication and Google indexing remain unverified. See [CI/CD](../guides/CI_CD.md) and [SEO](../seo.md).

## Read first

| Concern | Source |
|---|---|
| Operating policy | [AGENTS.md](../../AGENTS.md) |
| Run/build/test and configuration | [Quick start](../../README.md), [setup and configuration](../guides/README.md) |
| Product invariants | [Charter](../project/CHARTER.md) |
| Code boundaries | [Architecture](../code/ARCHITECTURE.md), [modules](../code/MODULES.md), [API contracts](../code/API.md) |
| Decisions and migration | [Decision log](../project/DECISION_LOG.md), [ADRs](../design/README.md) |
| Container/static hosting | [Docker guide](../guides/DOCKER.md) |
| Files/Markdown/code | [Rendering guide](../file-rendering.md) |
| Tracking schema | [tracking.schema.md](tracking.schema.md) |
| Agent-client translation | [Codex guide](../guides/CODEX_SETUP.md) |
| Recovery tools | [xops](../../xops/README.md), local ignored state directory |

## Application invariants

Flutter/Dart owns UI and domain logic. Minimal web host/PWA glue and static nginx serving are permitted. Python stdlib and Bash in xops are operations tools only: do not add a Python/Node backend, API proxy or another frontend stack.

Use the official structured OpenRouter API, never website scraping. Missing/malformed prices never become zero. The observed -1 sentinel is unresolved; applicable unresolved charges are excluded as informational eligibility results. Explicit zero-price guards, exact selected ID, no paid fallback and no automatic content resend remain mandatory.

Keep health separate from catalog presence and media capability. Avoid startup probe/allowance polling. Preserve conversation/model/draft/focus across resize; changing models resumes that model's unsent draft or opens a fresh workspace. Preserve accepted turns/partial output on failure and use explicit retry/edit/continue actions.

Browser-local history is origin-scoped. IndexedDB stores normalized messages/media and uses atomic revision-checked writes. Preserve recovered conflicts, legacy migration data and archived histories; do not silently discard data to make a test pass. PWA Cache Storage is shell-only, without keys/config/API responses/chat/media.

## Configuration and integrations

Use the checked-in [example](../../config/example.json); runtime local configuration is ignored. Never print its key or copy it into fixtures, logs, docs, images or container layers. The browser receives the configured key by design; this remains a development demo.

OpenRouter base URL and all timeouts/bounds are typed in AppConfig. Catalog GET is public; health/chat/allowance use the configured key. Direct browser networking errors must not be labeled definitely CORS without evidence.

CodeGraph is now required and enabled at the user's explicit request, superseding the initial scaffold's `--no-mcp` setting. See [MCP setup](../guides/MCP_SETUP.md) for the pinned local runner, client configuration and verification commands. Use graph-first exploration when the tool is connected and the relevant files are indexed. Configuration does not prove current-session connectivity; report unavailable access and use local reads when necessary. Refresh the local index through `make codeg` after substantial source changes.

## Verification and operations

Use the README/Makefile's exact commands from the canonical workspace. Wrap risky commands with safe-run and inspect saved output after failures. Read local current/checkpoint/last_failure state at session start. Existing logs/screenshots are dated evidence only; preserve them rather than rewriting history. Native platforms, untested browsers and external header grades remain unverified unless a new report establishes them.

## GitHub account migration — 2026-10-07

The active source and publication targets are now `consciontologic/wfform` and
`consciontologic/wfform.com`. The user explicitly authorized a fresh source
history and publication using the new account; this supersedes the old targets
in dated reports above. Current guides, package metadata, public source links
and the publishing workflow use the new account. Tracking rows retain the
implementation audit trail without carrying old Git commits to the new repository.
The source Actions secret remains `WFFORM_DEPLOY_TOKEN`; only built web files
are published. The previous account's manually dispatched run stopped before
jobs with `startup_failure`; that is not a successful release or a result for
the new account. The new account's API-triggered run completed successfully and
published compiled files. See the [migration report](../reports/account-migration-verification.md)
for root commit, workflow run, destination commit and integrity evidence. Pages/DNS
serving remains separate.

## Free public hosting — 2026-10-07

Historical intermediate deployment; superseded by the purchased-domain decision below.

The user clarified they do not own `wfform.com` and requested the free URL
`https://consciontologic.github.io/wfform.com/`. This supersedes custom-domain
assumptions in dated reports. Publish with base `/wfform.com/`, leave Pages'
custom domain empty and do not generate `CNAME`. Public SEO metadata uses the
GitHub URL. Localhost/Docker remain rooted at `/`; history stays origin-scoped.
The user authorized hosting and the associated source/publication updates.

Pages is now live over HTTPS, with no custom domain. The source pipeline and
destination Pages deployment completed successfully. The actual public browser
loaded the live catalog, model details and Settings; the service worker is active
under `/wfform.com/` and cached all 37 shell assets without policy violations.
See [hosting verification](../reports/github-pages-verification.md) for release,
workflow evidence, test counts and limits. No new authenticated chat or actual
network-offline reload was tested during this hosting change.

## Purchased custom domain — 2026-10-07

The user now owns `wfform.com`, configured Namecheap DNS, and explicitly
authorized GitHub configuration and the required deployment updates. Active
public builds use `/`, canonical metadata uses `https://wfform.com/`, and the
publisher manages the `CNAME` file. GitHub provides managed HTTPS. This replaces
the no-custom-domain configuration above without changing repository names or
`WFFORM_DEPLOY_TOKEN`. Existing histories remain on their original browser
origin; use export/import to transfer them. See Phase 7 of the roadmap for
current deployment and verification acceptance.

Deployment completed successfully: custom-domain HTTPS and redirects were
verified, the actual browser loaded the live catalog, and the root worker cached
all 37 shell assets without policy violations. CI passed 358 app/tool tests,
14 repository tests and six Chrome storage checks. See the
[custom-domain report](../reports/custom-domain-verification.md) for exact runs,
revision, release and verification limits.

## Sidebar and model readability — 2026-10-07

Expanded layouts now have a keyboard/pointer/touch resizable sidebar. Its saved
240–440 logical-pixel preference is temporarily constrained by text scale and
available chat space; medium rails and compact drawers remain adaptive. Settings
now include 125% text. Drag previews do not write storage until release.

Model descriptions preserve the complete API value. Some upstream descriptions,
including Cohere North Mini Code, themselves end in an ellipsis; the inspector
and details dialog explain this and provide a selectable/copyable model-page
URL. Do not invent missing paragraphs or scrape the website. The repeated model
hover instruction was removed. See the [verification report](../reports/sidebar-readability-verification.md).

## Public information and version — 2026-10-07

The app/package version starts at 0.1.0. About, Terms and Liability are static
companion documents linked by the responsive Flutter footer and each other.
Each HTML page contains the user-supplied Google tag once immediately after
head; nginx allows the hashed bootstrap and specified Google origins. No
custom conversation analytics were added. Keep version constants/static
footers in sync, and update the CSP hash if the inline snippet changes.
Machine-specific paths have been removed from tracked documentation; retain
portable commands and relative repository references. See the
[verification report](../reports/site-pages-verification.md).

## Sidebar and passport patch — 2026-10-07

Version 0.1.1 replaces the sidebar grip with a plain divider and supports a
persisted collapsed state, left-edge preview, and default-width restoration
when a sidebar action is activated. Compact drawers and medium rails retain
their existing interaction models. Model passports show a concise literal
preview with complete descriptions and grouped technical details available
on demand. Archived-row deletion is direct, independent of row selection,
and does not disturb an unrelated active conversation. See Phase 10 of the
roadmap for verification acceptance.

## Conversation drafts and saved connection 0.2.0 — 2026-10-07

Unsent work is separate from Chats and Archived. Empty workspaces are not
indexed; actual user-content transport dispatch promotes a draft to chat
history. Model changes and New conversation resume a matching unsent draft
when available. Drafts preserve text and attachments across navigation/reload
and offer no archive/delete controls. Archiving the active sent chat opens a
writable draft. Response activity appears on the corresponding row, with a
static accessible alternative for reduced motion. One request at a time remains
the supported behavior.

Settings explicitly saves/replaces or clears the browser-local key. An explicit
empty saved override prevents runtime configuration from restoring a cleared
key. Read-back validation and late-configuration race regressions preserve the
user's saved choice. Browser storage failures are visible and do not falsely
report success. Site-data removal can still remove local preferences/history;
native persistent adapter parity remains unverified.

The final local gate passed 476 tests with one opt-in live test skipped,
14 repository-operation tests and seven actual Chromium storage tests.
CodeGraph queries verified 151 files, 2,048 nodes, 8,579 edges and eight tools.
The bounded real catalog check observed 663 entries, 68 free-price candidates,
17 chat-compatible models, seven unresolved-price exclusions and no quarantine.
The final release has 40 assets / 18,270,168 bytes and passed actual nginx
headers and immutable-asset integrity checks. Local browser evidence includes
an explicit successful authenticated LiquidAI stream after a mandatory-reasoning
probe fix, responsive/200% layouts, imported archive fixtures and two PWA
updates preserving drafts. Offline shell reload with nginx stopped, reconnect,
saved history reopening and persisted explicit key clearing also passed.
CI run 37666068066 and Pages run 37666482966 passed. The public release matches
the local build, including checked JavaScript/page/manifest hashes. See the
[0.2.0 verification report](../reports/conversation-drafts-verification.md) and
Phase 13 for scope and remaining platform limits.

## Composer continuity 0.2.1 — 2026-10-07

Model changes now carry unsent text and attachments instead of replacing the
composer with a target model's draft. Unsent workspaces retain their identity;
message-bearing conversations keep their history in a separate record. Existing
destination drafts remain recoverable, and incompatible files stay visible.
About, Terms and Liability checkpoint the draft before same-tab navigation;
failed saves or active work prevent departure. GitHub still opens separately.

The 0.2.1 local gate passed 488 tests (one opt-in skip), seven Chromium storage
checks, 14 operation tests, formatting, analyzer and repository checks. CodeGraph
was refreshed and its eight tools verified. Actual release-browser fixtures kept
text and Markdown/PNG files through model changes, About → Open app, browser
Back, reload, PWA update and compact/medium/expanded resizing. File previews
reopened after reload. No new inference POST was needed for this patch. See the
[0.2.1 report](../reports/composer-continuity-verification.md) for the exact build
identity and publication status.

Source `2c755b5` passed CI 37675339117; website `94b24a2` passed Pages
37675720016. The public release manifest and checked JavaScript, HTML and web
manifest hashes match the locally verified 0.2.1 build.

## Mobile keyboard recovery 0.2.2 — 2026-10-08

Flutter is pinned to 3.38.10 / Dart 3.10.9, including the upstream Android web
keyboard-dismissal engine correction. An optional ignored project-local SDK
is preferred by Makefile without modifying shared SDKs. Composer lines and
attachment space are bounded while the keyboard is visible, including at 200%
text. Code previews reuse highlighted spans between their existing update ticks.

The full local gate passed 493 tests with one opt-in live skip, formatting,
analyzer and repository checks; seven actual Chromium storage tests and 14
operation tests passed. CodeGraph and a public release build passed. Focused
release-browser checks preserved text and source/image files through viewport
shrink/restore, landscape-sized layout and reload. No physical Samsung IME or
phone frame-rate measurement was available. See the
[0.2.2 report](../reports/mobile-keyboard-verification.md) for evidence and
publication status.

Source `76db986` passed CI 37737229068; website `0d3956f` passed Pages
37737509800. The public release and checked JS/HTML/manifest hashes match the
local build. A public 0.2.1 → 0.2.2 Save & update preserved draft text, a source
file and model selection. Local push initially lacked its temporary credential;
the authorized credential was used only for publication and removed afterward.

## Compact controls and draft deletion 0.2.3 — 2026-10-08

Phone/tablet layouts share drawer navigation and a minimized header model
control. The composer retains Context/Add files and actionable recovery, with
routine helper text and root footer removed. Drawer information links now use
aligned rows. Draft rows offer direct deletion; active deletion drains pending
saves, blocks replacement checkpoints, removes attached files and recovery text,
and leaves a writable workspace. Pending deletions cannot be resumed by model
selection. Failed deletion retains work for explicit retry.

The combined gate passed 504 tests (one opt-in live skip), formatting of 117 Dart
files, analysis and repository checks. CodeGraph indexed 155 files with 2,107 nodes,
8,926 edges and eight verified tools. The final release build contains 40 assets /
18,274,300 bytes. Release-browser checks exercised direct draft deletion,
writable replacement and reload, drawer alignment and compact controls.
See the [0.2.3 report](../reports/compact-controls-verification.md) for exact
browser dimensions and evidence limits. Source `ae55eed` passed CI 37742631235;
website `8beb24e` passed Pages 37742940817. Public release and selected asset
hashes match the locally verified build.

## Compact navigation refinement 0.2.4 — 2026-10-08

Small layouts always show Models beside its header icon. The drawer now ends
with one compact version/GitHub/Info row, with smaller text and no separate
surface. Info contains About, Terms and conditions, and Liability. The drawer
minimum height reflects the reduced footer, returning space to history. Desktop
navigation and draft checkpoint behavior remain unchanged.

The local gate passed 509 tests with one opt-in live skip, 117-file formatting,
analysis and repository checks. CodeGraph verified 155 files, 2,109 nodes, 8,935 edges
and eight tools. The release has 40 assets / 18,273,628 bytes. Actual 390×844 and
820×1180 browser views verified Models, the compact row, menu entries and
Info→About→Open app with saved draft/model restoration. See the
[0.2.4 report](../reports/compact-navigation-verification.md). Source `a152a3f`
passed CI 37746395818; website `97eb321` passed Pages 37746729176. Seven
published release/JS/HTML/manifest files match the verified local build. Public
Save & update moved 0.2.3 to 0.2.4, with the selected model retained; the phone
viewport shows Models and the bottom version/GitHub/Info row.

## Parameters, MCP and wfformcomp — 2026-10-09

Phase 21 adds model-aware parameter controls with omitted remote defaults,
optional HTTP MCP connections and the optional Dart companion **wfformcomp**.
The companion runs explicitly configured commands and allowlisted stdio MCP
servers, and can host the same public Flutter build. Browser inference remains
direct; ordinary chat needs no companion. Tokens are memory-only for MCP,
connections never reconnect automatically, every call requires approval, and
uncertain actions are never replayed. Complete tool/reasoning exchanges and
per-conversation overrides survive history/export/restore. Parameter/tool-only
unsent work is saved as a draft, without promoting it to a sent chat.

Actual Liquid and Cohere free routes each passed ordinary chat, independent
HTTP MCP and compiled CLI companion loops. Real CodeGraph reuse, browser
approval/nonce/history checks and nginx PWA update passed. Final gates passed
596 tests (four opt-in live skips), eight companion suites, seven actual Chromium
storage tests and 14 operation tests. The Linux x64 archive contains the current
web build and is 16.3 MB; Windows/macOS, OAuth/legacy MCP and public publication
are not claimed. Temporary test credentials were removed; GitHub credentials
were never used. No source commit/push or public release was performed. See the
[dated report](../reports/connected-tools-verification.md), [tool guide](../tools.md)
and [companion guide](../wfformcomp.md) for exact evidence and operating limits.

## Planned companion installation — 2026-10-09

The user requires separate Linux, Windows and macOS downloads and easy
installation, with macOS explicitly deferred. [Phase 22](../planning/ROADMAP.md#phase-22--companion-platform-downloads-and-easy-installation)
records future work: graphical Linux/Windows installation and launch, automatic
private setup/browser opening, explicit pairing without manual tokens/ports,
and UI tool configuration. Users must not need a terminal, JSON editing or a
developer SDK. Native platform tests, process-tree cleanup, protected settings,
upgrade/uninstall and signing evidence gate availability. This is a plan only;
the existing Linux archive remains a manually configured developer preview.

## Readable data, tools guide and Windows build — 2026-10-09

Phase 23 adds shared JSON/JSONL formatting, syntax-highlighted source and decoded
nested tool text across previews, approvals, saved tool messages and diagnostics.
Exact original content remains available for copy/export and stored requests.
Tools now opens a bundled beginner guide with CodeGraph and CLI examples and a
companion setup page. Windows x64 executable/ZIP packaging, Job Object cleanup,
private token ACLs and native CI acceptance are implemented. Native Windows
execution still needs its runner; macOS and graphical installation remain planned.

The final local gate passed 613 Flutter tests (four opt-in live skips), ten
companion suites, formatting, analyzers and repository checks. The final Linux
archive and extracted executable passed authentication/web-hosting/cleanup
checks. The preview updated to release
`2625e134a3a3fd0fe1843382fd41140cf2aa99190c950b07c293b62d89f4888e`,
preserving the 16-message demo and other chats. Final guide/diagnostic browser
checks passed; one earlier unreproduced scheduler event and the unrelated
publication-failure breadcrumb remain explicitly distinguished in the
[verification report](../reports/readable-tools-windows-verification.md).


## Open Cradle identity — 2026-10-09

Phase 24 applies the approved open folded band with linked lavender AI nodes to
the app, ten companion glyphs, public pages, browser tabs and all 40 platform
exports. The artwork uses transparent exterior/interior space in both themes;
opaque platform formats retain non-white tinted surfaces. Shared deterministic
geometry keeps Flutter and exported PNGs consistent down to 16px.

The local gate passed 616 Flutter tests (four existing opt-in live skips), ten
companion suites, formatting, analyzers and repository checks. The public build
and actual local PWA Save & update flow loaded release
`fb8bcd7a7bfca069fd1a8ac9ad1264d51862023164085f5d14c749890a3553d6`.
Light/dark and 390×844 at 200% text were checked; all 14 web branding files matched
source/build/manifest through root and immutable HTTP URLs. CodeGraph's smoke
query limit was increased from five to 100 to include all existing callers;
both relationship assertions and all nine tooling checks pass. Prior staged
tools work is preserved. Publication and native binaries are not included.
See the [branding report](../reports/open-cradle-branding-verification.md).


The same-day no-background clarification supersedes opaque platform exceptions:
all 40 exported icons now have alpha-zero exterior/interior space, including
iOS and legacy maskable files. The manifest selects only transparent general-purpose
icons; all ten in-app glyphs already had transparent backgrounds. The revised
local release is `a66200a09fec3b0b664820538db4cc06c303d12850e8937e0c90768864fb314c`.
See the report's clarification section for independent alpha and update evidence.

## Desktop tools and 1.0.0 delivery (2026-10-09)

Current version is plain 1.0.0 on codex/release/1.0.0. Phones/tablets keep ordinary
chat but cannot connect/dispatch tools; narrow desktop windows retain them.
Copy controls are limited to essential message/source/report actions. The
runnable examples/tools_playground includes stdio MCP and a fixed CLI program.
Flat PWA assets replace physical release directories while internal hashes and
legacy browser-cache recovery remain. See [the verification report](../reports/release-100-verification.md)
and [Gitflow](../guides/GITFLOW.md) for exact tests, local packages, remote branch
protection/metadata and outstanding Copilot/native Windows/publication gates.
The local coordinating parent now publishes validated Gitflow work branches
through `make git`; assigned Copilot cloud tasks use their managed platform
branches. `main` and `develop` change only through reviewed PRs. An eligible
independent reviewer supplies required approval, then plain SemVer-tag CI
publishes after merge; a Copilot PR requester cannot supply its approving review.

## Routine delivery approval policy (2026-10-09)

The user's later choice supersedes the PR-review requirement above: routine PRs
use required CI and conversation resolution, with zero configured human PR
approvals. The final release requires the owner's production deployment approval.
Source main/develop still change only through protected PRs, and administrators
are now subject to the required checks. See [delivery verification](../reports/delivery-automation-verification.md)
for actual live settings, test results and bootstrap status. A completed AI task
or green mocked test must not be reported as a live release.

The subsequent CI policy narrows expensive validation to PRs into `develop` and
hotfix PRs directly into `main`. Release preparation now targets `develop`;
promotions into main use controller metadata validation linking the exact source
tree to successful develop validation. Release dispatch builds packages without
repeating tests/scans. Cache pinned SDKs, locked dependencies and scanner binaries;
keep credentials, application artifacts and fresh vulnerability results uncached.
