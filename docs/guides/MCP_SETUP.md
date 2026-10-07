# CodeGraph MCP setup

CodeGraph is enabled for wfform, including its Dart sources, at the user's
request. The earlier scaffold used `--no-mcp`; this configuration completes
that missing integration. The application and nginx image remain Flutter/Dart
and static hosting. CodeGraph is repository development tooling only.

## Runtime and index

`xops/agent/codegraph.sh` launches **`@colbymchenry/codegraph@1.6.2`** with its
bundled platform runtime. It uses the existing Node/npm installation (verified
with Node 22.22.1, npm 9.2.0), downloads into ignored
`.local/codegraph/npm-cache/`, and pins every invocation to the same version.
No global package installation or user-wide agent configuration is performed.
`CODEGRAPH_TELEMETRY=0` and `DO_NOT_TRACK=1` disable usage telemetry for these
processes. First use needs npm registry access; cached invocations prefer local
packages. The app's run/build/test commands do not depend on Node or CodeGraph.

From the project root:

```bash
make codeg                                      # init if absent, otherwise sync
make codeg.check                                # bounded live MCP/Dart smoke check
xops/agent/codegraph.sh version
xops/agent/codegraph.sh status . --json
xops/agent/codegraph.sh explore "ChatController send"
xops/agent/codegraph.sh callers send --json
xops/agent/codegraph.sh index .                  # full rebuild after large moves
```

The launcher anchors its working directory to this repository, including when
called from a subdirectory. The graph lives in ignored `.codegraph/` and honors
Git ignores, so local configuration, package caches, builds and scratch output
are excluded. CodeGraph recognizes `.dart` without custom language mappings.
Its MCP watcher maintains the index while the server is running. Run
`make codeg` when no server was watching, and `index .` after a major refactor
or CodeGraph version change. The command fails visibly rather than silently
switching runtimes after an indexing error.

## Client configuration

| File | Purpose |
| --- | --- |
| [`.mcp.json`](../../.mcp.json) | Portable server definition for compatible Claude and Copilot clients |
| [`.codex/config.toml`](../../.codex/config.toml) | Native Codex server definition, same launcher/arguments/environment |
| [`.vscode/mcp.json`](../../.vscode/mcp.json) | Empty server map; avoids registering CodeGraph twice |
| [CodeGraph instructions](../../.github/instructions/codegraph.instructions.md) | Graph-first source exploration, including Dart |
| [CodeGraph management skill](../../.agents/skills/codegraph-management/SKILL.md) | Index maintenance, evidence and fallback rules |

Both MCP definitions resolve `git rev-parse --show-toplevel` from the client's
working directory, then execute that checkout's `xops/agent/codegraph.sh` with
`serve --mcp --path` set to the resolved absolute root. This works from the
project root or a nested directory and follows clones and Git worktrees without
tracked workstation paths. Open the repository as the client's current project;
launching from outside any Git checkout fails visibly. No API key belongs in
these definitions. The wrapper is the single source for the pinned package version.

Eight documented tools are enabled: `explore`, `node`, `search`, `callers`,
`callees`, `impact`, `files`, and `status`. Tool names in clients may have an
MCP prefix. Use only what the client actually advertises.

`make codeg.check` launches the configured server, checks initialization and
tool discovery, verifies Dart symbol/source/caller queries, and confirms
ignored paths are absent from its file listing. Each protocol request has a
30-second timeout and a 4 MiB response bound. Its output contains metadata
only, not returned source or local credentials. Run `make codeg` first on a
fresh clone; the check does not silently create an index.

Open the canonical repository as a trusted project and start a new session or
restart its MCP server to load new settings. Existing sessions do not
necessarily reload server configuration. In Codex, inspect the MCP tool list;
in VS Code, use **MCP: List Servers**. Current VS Code supports portable root
`.mcp.json`. For older clients lacking that support, move the same server
entry to `.vscode/mcp.json` under `servers` for that client, avoiding two active
registrations. Do not change user-wide trust or MCP files as a workaround.

## Verification and limitations

On **2026-10-06**, a real stdio client launched the checked-in `.mcp.json`
command, completed MCP `initialize`, listed all eight tools, and successfully
called `codegraph_status`, `codegraph_search`, `codegraph_explore`,
`codegraph_callers` and `codegraph_files`. Search resolved `ChatController` to
`lib/features/chat/chat_controller.dart`; exploration returned Dart source and
call relationships, and `send` showed five callers including its regression
tests. The final index reported 112 files (88 Dart), 1,684 nodes and 6,797
edges with no pending changes. Counts change as source changes.

These are live CLI/MCP protocol results, not a claim that an already-open
Codex, Claude or VS Code session has reloaded its tool inventory. Reopen the
project/session when needed. The CLI graph query above is available immediately
and reaches the same index. Unit tests independently check version pinning,
argument preservation, anchored paths, aligned client configs and failure
propagation.

On **2026-10-07**, the configuration regression test launches both definitions
from the root and a nested directory of an alternate Git checkout whose path
contains a space. A fake npm executable captures the resulting runtime arguments
and working directory; the test makes no network request or commit. It verifies
that CI checkouts and local clones target their own graph instead of the original
workstation path. `make codeg.check` separately verifies the actual local server.

The graph is a source-navigation aid. Dynamic dispatch, generated code and
unsupported file types can leave incomplete relationships. Use direct source
reads for those cases and Flutter analysis/tests for correctness; a graph
answer is not proof that behavior is covered.

| Symptom | Action |
| --- | --- |
| No graph tools | Run `make codeg`, inspect server errors, restart/reopen the client |
| Wrong repository | Check the client's current Git checkout and `git rev-parse --show-toplevel`; restart MCP after switching projects |
| Stale/missing symbol | Run `make codeg`; after large changes use `index .`; compare source |
| Runtime/package unavailable | Check Node/npm and initial registry access; no global install is required |
| Duplicate server | Keep one portable definition for VS Code; inspect any user registration without modifying it automatically |
| Indexing fails | Read safe-run's captured log, fix the cause, then retry explicitly |

## Sources

Verified against the current official documentation and the installed 1.6.2
runtime on 2026-10-06:

- [CodeGraph supported languages](https://colbymchenry.github.io/codegraph/reference/languages/)
- [CLI reference](https://colbymchenry.github.io/codegraph/reference/cli/)
- [MCP server and tool selection](https://colbymchenry.github.io/codegraph/reference/mcp-server/)
- [Index configuration and exclusions](https://colbymchenry.github.io/codegraph/getting-started/configuration/)
- [Pinned package metadata](https://registry.npmjs.org/@colbymchenry/codegraph/1.6.2)
- [VS Code MCP configuration](https://code.visualstudio.com/docs/agents/reference/mcp-configuration)
