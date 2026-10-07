# wfform shared context pack

## Identity and current location

- Product: **wfform — Wrapper for Free Open Router Models**.
- Purpose: discover free OpenRouter models and continue browser-local conversations.
- Application: Flutter/Dart, verified release target web/PWA; Dart package is `wfform`. Android namespace/application ID and iOS Runner bundle ID are `com.wfform`. Native hosts are configured but native builds and adapter parity remain unverified; PWA/storage identities remain stable.
- Canonical workspace: /home/serhatakbak/code/projects/wfform.
- Git origin: https://github.com/consciontologic/wfform.git. On 2026-10-07 the user explicitly authorized migration to this account without prior Git history, source push and pipeline launch. The old local Git metadata is preserved under ignored `.local/git-history-backup/`. Future history replacement still requires an explicit request.
- Original chat workspace: /home/serhatakbak/Documents/Codex/2026-10-05/you-are-astra-implement-and-verify. Its historical outputs remain there.
- Scaffold source/revision: /home/serhatakbak/code/projects/agentic-workspace at a93e0d95e665748c700faa677cc5e8cfdb6c3ca8, full preset with --no-mcp and no --force on 2026-10-06. No Dart language preset existed.

## Latest completed work

The [roadmap](../planning/ROADMAP.md) records the completed six-part migration/scaffold/ignored-key/documentation/container/rendering request. The [current report](../reports/workspace-rendering-verification.md) records 321 deterministic tests, six real IndexedDB checks, seven framework operations tests, release builds and actual Docker/browser checks with explicit limitations. The coordinating parent owns final tracking/staging. Subagents return evidence and preserve concurrent edits; no agent commits or pushes.

The subsequent [workflow and identity follow-up](../reports/workflow-identity-verification.md) consolidated the Makefile, enabled and verified CodeGraph, changed Settings to a gear emoji and renamed the Dart package to `com_wfform`. Its final gates passed 321 Flutter tests, six real IndexedDB checks and 13 repository-operation tests, plus real MCP queries and release/browser/header checks. Earlier reports remain dated evidence.

The user's [native identifier clarification](../reports/native-identity-verification.md) supersedes that package interpretation: Dart is `wfform`, actual Android/iOS host IDs are `com.wfform`. Native configuration was checked; web regression and release gates passed. Native binary builds and adapter parity remain outside verified scope. See [native setup](../native-platforms.md).

On 2026-10-07 the [public-web follow-up](../reports/public-web-verification.md) added SEO metadata/static product documentation, a bracketed conversation logo and GitHub CI/CD to `metaphy6/wfform.com`. The workflow needs source Actions secret `WFFORM_DEPLOY_TOKEN` (target Contents read/write) and destination Pages/DNS setup. Public builds exclude local configuration; local gates and browser checks passed, while remote publication and Google indexing remain unverified. See [CI/CD](../guides/CI_CD.md) and [SEO](../seo.md).

## Read first

| Concern | Source |
|---|---|
| Operating policy | [AGENTS.md](../../AGENTS.md) |
| Run/build/test and configuration | [README.md](../../README.md) |
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

Keep health separate from catalog presence and media capability. Avoid startup probe/allowance polling. Preserve conversation/model/draft/focus across resize; changing models starts a new conversation. Preserve accepted turns/partial output on failure and use explicit retry/edit/continue actions.

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
