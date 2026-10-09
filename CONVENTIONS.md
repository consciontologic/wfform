<!--
CONVENTIONS.md — vendor entry point that delegates to AGENTS.md.
-->

# 📐 CONVENTIONS.md

The authoritative rulebook for every AI coding assistant in this repository
is [`AGENTS.md`](AGENTS.md). Please read it first.

Project-specific context is in [docs/tracking/context.md](docs/tracking/context.md).
The app is Flutter/Dart; start with `make help`, `make verify`, and
[the architecture](docs/code/ARCHITECTURE.md). CodeGraph is enabled via
[project-local MCP configuration](docs/guides/MCP_SETUP.md), including Dart.

## ⚡ Critical conventions (mirrored from AGENTS.md)

1. **Coordinating agents publish validated work branches through `make git`.** Append a row to
   [`docs/tracking/tracking.csv`](docs/tracking/tracking.csv) via
   [`xops/agent/tracking_append.sh`](xops/agent/tracking_append.sh) with
   `action=commit, status=completed, commit_sha=pending`, then `git add -A`,
   inspect `make git.dry`, then run `make git`. Never commit or push directly to
   `main`/`develop`; those branches change only through reviewed PRs.

2. **Conventional Commits** in every tracking-row `summary`:
   `type(scope): description`. Valid types: `feat, fix, docs, style,
   refactor, perf, test, chore, ci, build, revert`.

3. **Tests move with code** in the same commit. No `@Skip` / `skip:` /
   `xit(` / deleted assertions to make a gate green.

4. **System-level changes** (`apt`, `systemctl`, global git config, …)
   require explicit per-occurrence confirmation. Inside the workspace, act
   freely.

5. **Read session state** before starting work:
   [`xops/agent/session-bootstrap.sh`](xops/agent/session-bootstrap.sh) →
   surfaces any unresolved `last_failure.json` from a prior session.

6. **Project plan** lives at [`docs/planning/ROADMAP.md`](docs/planning/ROADMAP.md).
   Do not silently re-plan.

7. **Curated skills** at [`.agents/skills/`](.agents/skills/). Load the relevant
   skill before the matching work.

For the full ruleset (security, communication, model-specific notes), read
[`AGENTS.md`](AGENTS.md).

## 🌿 Gitflow delivery

Read [the delivery workflow](docs/guides/GITFLOW.md) before starting a feature, bugfix,
hotfix or release. Use the appropriate isolated work branch; keep main/develop
free of direct implementation. Local coordinating agents publish validated work
branches through `make git`; delegated agents return evidence without publishing.
GitHub Copilot cloud may commit/push its assigned platform branch under AGENTS.md §2, with an explicit
low-cost model; human review/merge and CI release gates still apply.
