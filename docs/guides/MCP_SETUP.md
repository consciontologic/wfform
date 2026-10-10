# CodeGraph setup

CodeGraph is repository development tooling, independent of the app and nginx.
The project launcher pins **`@colbymchenry/codegraph@1.6.2`**, uses existing Node/npm
and ignored `.local/codegraph/npm-cache/`, disables telemetry, and makes no global
install/configuration changes. First use needs registry access.

```sh
make codeg                              # initialize or sync ignored .codegraph/
make codeg.check                        # real bounded MCP/Dart smoke check
xops/agent/codegraph.sh status . --json
xops/agent/codegraph.sh explore "ChatController send"
xops/agent/codegraph.sh index .         # rebuild after large moves/version changes
```

[.mcp.json](../../.mcp.json) and [.codex/config.toml](../../.codex/config.toml) resolve
the current Git root and call the same launcher with `serve --mcp --path`.
[.vscode/mcp.json](../../.vscode/mcp.json) stays empty to avoid duplicate registration.
Open the correct trusted checkout and restart the server/session after changes.
No credentials or workstation-specific paths belong in these files.

Use tools actually advertised by the client: configured tools are `explore`, `node`,
`search`, `callers`, `callees`, `impact`, `files`, `status` (possibly prefixed).
The smoke check initializes the real server, queries Dart/source/callers and checks
ignored files stay excluded, with 30-second requests and 4 MiB response bounds.
It does not silently create a missing index.

| Problem | Action |
|---|---|
| Missing/stale graph | `make codeg`; full `index .` after structural changes |
| No client tools | Inspect server errors, restart/reopen trusted project |
| Wrong repository | Check current Git root, restart MCP in the intended checkout |
| Runtime unavailable | Check local Node/npm and first-use network access |
| Duplicate server | Keep one project registration; do not alter global settings automatically |
| Failed command | Read safe-run log, diagnose and fix before retry |

Graph relationships can miss dynamic/generated/unsupported code. State that limitation
and read sources directly; graph answers do not replace analyzer/tests. See the
[management skill](../../.agents/skills/codegraph-management/SKILL.md).

For models using CodeGraph through wfform itself, use the separate
[companion example](../wfformcomp.md#existing-stdio-mcp-servers).
References: [CLI](https://colbymchenry.github.io/codegraph/reference/cli/),
[MCP](https://colbymchenry.github.io/codegraph/reference/mcp-server/).
