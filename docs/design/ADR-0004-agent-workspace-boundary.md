# ADR-0004: Adopt agent operations without changing the application stack

- Status: accepted for the scaffold boundary; task completion remains in the roadmap.
- Date: 2026-10-06.
- Decision basis: explicit move/scaffold/documentation/container/rendering request.

## Amendment: CodeGraph explicitly required

Later on 2026-10-06, the user required CodeGraph for this repository. The original MCP opt-out below is superseded: enable the pinned project-local CodeGraph runner and client configuration, index Dart and supported operations sources, and verify real graph queries. CodeGraph's Node runtime is repository tooling, not part of the Flutter application or nginx image. See [MCP setup](../guides/MCP_SETUP.md). No global settings or software installation is required.

## Context

The application was developed in a generated chat workspace. The user requested a named Git project with the agentic-workspace operating framework, populated documentation and container commands. Application code, local data, credentials, existing Git metadata and prior verification evidence must remain distinguishable.

## Decision

Move application sources into the existing wfform repository and adopt the full agentic-workspace scaffold with --no-mcp and no --force, keeping repository operations separate from Flutter runtime code.

## Consequences

- AGENTS.md, vendor entry points, native roles/skills and tracking form the repository workflow; project context, architecture and roadmap replace template examples.
- The destination's existing empty main branch and origin remain intact. Agents do not commit/push; the coordinating parent owns tracking/staging, and the human owns make git.
- Python stdlib/shell operations are allowed in xops. They do not introduce Python/Node or a backend into the app.
- MCP/CodeGraph is not installed or initialized automatically. Local search/read tools work without that integration; a future explicit opt-in can be reviewed separately.
- Existing application docs retain dated evidence. Historical output files remain at the original chat workspace; new verification belongs to the project outputs directory.
- Scaffold upgrades require review of local adaptations. Re-running --force can overwrite project choices and is not a routine update path.

## Considered options

- **Full scaffold without MCP, chosen:** supplies requested operating conventions without an unsolicited tool-server/dependency setup.
- **Minimal scaffold:** would omit portions of the requested full agent workflow and documentation structure.
- **Full scaffold with automatic CodeGraph/MCP:** adds integration/runtime assumptions unnecessary for this Flutter project at adoption time.
- **Replace the destination repository or force overwrite:** risks its existing origin/branch and application customizations.

Exact paths, source revision and invocation are recorded in the [project decision log](../project/DECISION_LOG.md).
