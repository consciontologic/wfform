# ADR-0004: Repository operations stay outside the application

- Status: accepted, with current operating-policy amendments below.
- Date: 2026-10-06; delivery amendments 2026-10-09/10.

## Decision

Adopt agentic-workspace rules, skills, roles and tracking in the existing repository,
preserving application code and local adaptations. Flutter/Dart remains the app;
Python/Bash and CodeGraph's Node runtime are development operations only.

## Consequences and amendments

- The initial scaffold used `--no-mcp` without force-overwriting files. The user's
  later explicit CodeGraph request supersedes that opt-out; use the pinned
  [project-local launcher](../guides/MCP_SETUP.md), not a global installation.
- Current [AGENTS.md](../../AGENTS.md) supersedes original publication restrictions:
  coordinating agents publish validated Gitflow work branches through `make git`;
  delegates return evidence and protected branches change only through PRs.
- Routine delivery automation is removed. Task/PR/release coordination is explicit;
  final production approval belongs to the owner and cannot be supplied by an agent.
- Preserve dirty work, browser data, credentials and repository history. Scaffold
  upgrades require review; `--force` is not a normal update mechanism.
- Current guides hold contracts; PR/CI/local output holds per-change evidence.

## Alternatives

A minimal scaffold omitted requested workflow support. Replacing the repository or
force-updating the scaffold risked existing work. Adding operations dependencies to
the app would violate its stack boundary. See [provenance](../project/DECISION_LOG.md).
