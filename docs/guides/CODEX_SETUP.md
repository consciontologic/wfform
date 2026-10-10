# Codex setup

Open this checkout as a trusted Codex project after reviewing its configuration.
The scaffold is already installed; do not rerun an upstream installer or change
global trust/configuration to start normal work.

| Surface | Use |
|---|---|
| `AGENTS.md`, `CONVENTIONS.md` | Repository rules |
| `docs/tracking/context.md` | Current project context |
| `.github/instructions/` | Read relevant `applyTo` scopes explicitly |
| `.agents/skills/` | Task procedures; Copilot prompt adapters when installed |
| `.codex/agents/` | Native planner, implementer, reviewer, verifier roles |
| `.codex/config.toml` | Project runtime guidance and CodeGraph MCP |

Use native Codex editing, shell, search and delegation tools. Copilot YAML tool names,
handoffs and slash commands are not Codex APIs. Roles/model effort inherit the user's
choices unless explicitly overridden. The parent owns combined tracking/staging and
`make git` publication; children return evidence and preserve concurrent edits.
Review the complete current diff, then staged contents and tracking before publishing.

CodeGraph resolves the current Git root through the pinned launcher. Run `make codeg`
and inspect the actual advertised tools; configuration alone does not prove connection.
Reopen/restart MCP after configuration changes. [MCP setup](MCP_SETUP.md) provides
commands and fallbacks. Do not add unrelated/global integrations.

A quick read-only client check: list loaded instructions, skills, roles and CodeGraph
tools, then resolve `ChatController` and `send`. Report unavailable dependencies.
Run `make help`/`make verify` for real project commands.

Keep checked-in native role files aligned with current [Gitflow](GITFLOW.md): only
coordinating agents publish validated work branches via `make git`; main/develop are
PR-only and production approval belongs to the owner. Scaffold imports must preserve
local adaptations, data and disabled integrations. Client permissions still apply;
repository prose does not authorize bypassing them.
