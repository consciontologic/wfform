---
name: codegraph-management
description: "Use, troubleshoot or refresh the enabled CodeGraph MCP integration, including Dart source exploration."
---

# CodeGraph management

Read this before first graph use or a major refactor. wfform enables the
pinned CodeGraph 1.6.2 runtime through
[`xops/agent/codegraph.sh`](../../../xops/agent/codegraph.sh). The user's
request to enable it supersedes the original scaffold's `--no-mcp` choice.
See [MCP setup](../../../docs/guides/MCP_SETUP.md) for exact client/runtime
configuration and verified limitations.

## Access and exploration

- Check the current tool inventory; configuration alone does not prove a
  client has connected. The server is registered in root `.mcp.json` for
  compatible Claude/Copilot clients and native `.codex/config.toml` for Codex.
- `.vscode/mcp.json` has no duplicate CodeGraph entry. Current VS Code reads
  the portable root configuration; client versions differ.
- Use advertised `codegraph_explore` for source questions, `search` for symbol
  locations, `node` for source/call trails, `callers`/`callees`/`impact` for
  relationships, and `status` when diagnosing freshness.
- Dart is supported and included in the scoped instructions. If an existing
  client has not loaded MCP, use the same graph through
  `xops/agent/codegraph.sh explore "question or symbol"`.
- Source remains authoritative. Read directly for unsupported files, stale or
  incomplete results, or if both MCP and the CLI are unavailable. State the
  limitation. Never invent a tool call or claim an unverified connection.

## Index maintenance

The ignored `.codegraph/` directory stores this project's graph. The MCP
watcher syncs while running; after changes outside an active server, run:

```bash
pwd
xops/agent/safe-run.sh codegraph-sync -- make codeg
```

`make codeg` initializes a missing index and otherwise runs incremental sync.
For major moves/renames, a version change, or persistent stale references:

```bash
pwd
xops/agent/safe-run.sh codegraph-reindex -- xops/agent/codegraph.sh index .
xops/agent/codegraph.sh status . --json
make codeg.check
xops/agent/codegraph.sh explore "ChatController send"
```

Use the pinned launcher; do not install globally, run the interactive installer,
or silently retry failures with a different runtime. It downloads the pinned
package into ignored `.local/codegraph/` on first use. Do not remove the index
to fix ordinary staleness, commit its contents, or force-index ignored secrets,
SDKs, build outputs or package caches. Follow the captured-log recovery
procedure on nonzero exit.

The coordinating parent records index initialization/rebuild in its completion
tracking row (or an `action=note, scope=codegraph` row for an index-only task).
Delegates return evidence and do not append competing tracking rows. Include
version, status and a real query; configuration parsing alone is insufficient.
