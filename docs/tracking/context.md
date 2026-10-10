# Project context

- **wfform** means Wrapper for Free Open Router Models. Flutter **3.38.10** / Dart
  **3.10.9**; package `wfform`; native host IDs `com.wfform`.
- Source: `consciontologic/wfform`. Static publication: `consciontologic/wfform.com`.
  Canonical site: **https://wfform.com/**. Work from this checkout's root.
- Web/PWA is the application release target. Linux/Windows **wfformcomp** is a
  separate local CLI/MCP companion, not a native Flutter desktop UI.
- [AGENTS.md](../../AGENTS.md) owns operating rules. Read [Gitflow](../guides/GITFLOW.md)
  before branching and [architecture](../code/ARCHITECTURE.md) before code changes.

## Preserve

Flutter owns application logic. Browser requests go directly to OpenRouter; static
hosts never proxy inference. Use validated explicit zero prices and the chosen model,
without paid routing, model substitution or automatic content resend. Health and media
capability remain separate observations.

Preserve composer text/files, selected model and focus across navigation/layout.
Only user-content dispatch promotes a draft to chat. Keep partial output, archived
history, recovery copies and legacy data until successful migration. IndexedDB owns
history/media; tab-local markers recover unsent text. The PWA cache holds verified
static assets only. Rendered/uploaded code is never executed by the document viewer.

Tools require desktop, a compatible model, an explicit connection/selection and
per-call approval. No uncertain call is replayed. Keep connection tokens in memory;
local programs require companion allowlists.

## Work and evidence

Use `make help`, `make verify` and `make repository.check`. Make prefers the ignored
`.local/flutter-sdk` when present. CodeGraph is enabled through the pinned project
launcher: `make codeg`, then use advertised graph tools or the CLI. Report unavailable
or stale graph results and use source reads as needed.

Read ignored recovery state before work; safe-run captures failures. Only the parent
tracks/stages/publishes combined work through `make git.dry` then `make git` on a
Gitflow work branch. `main`/`develop` are PR-only. Routine delivery automation is
removed; task assignment, promotion and release dispatch require explicit coordination.
The owner alone approves the production deployment; agents never approve or bypass it.

Current work lives in the [roadmap](../planning/ROADMAP.md). Keep concise release notes
in [CHANGELOG.md](../../CHANGELOG.md) and evidence in PR/CI logs or ignored local
output. Append-only [tracking.csv](tracking.csv) retains the audit trail; do not create
per-change reports. Distinguish deterministic tests, real browser/native checks,
authenticated live inference and public release verification.

Runtime config, `.local/`, builds and scratch evidence are ignored. Never stage,
print or bake credentials into packages. Public releases exclude local configuration.
