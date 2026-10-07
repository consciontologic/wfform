---
name: 'CodeGraph-first code exploration'
description: 'Use CodeGraph as the first tool for code questions in this repo'
applyTo: '**/*.{dart,go,py,js,ts}'
---

# CodeGraph-first exploration

CodeGraph 1.6.2 is enabled for this repository, including Dart. Use the
project's pinned launcher and ignored local index. Do not install globally
or modify user-wide client settings. See [MCP setup](../../docs/guides/MCP_SETUP.md).

For any question about source code in an enabled and healthy graph —
how a symbol works, where it is defined, what calls it, or what it affects —
use an appropriate CodeGraph tool advertised in the current session first.
The names below are examples; tool availability varies by server and client:

| Intent | Tool |
|---|---|
| "How does X work?" / surveying an area | `mcp_codegraph_explore` |
| "Where is the symbol named X?" | `mcp_codegraph_search` |
| "What calls this?" / blast radius | `mcp_codegraph_callers` |
| "What is this symbol — source + caller/callee trail?" | `mcp_codegraph_node` |
| Reading an indexed source file | `mcp_codegraph_node` with `file=...` |

Do **not** start with `read_file` or `grep_search` for symbol lookup,
call-graph questions, or understanding how code works. Fall back to raw
reads/searches only for files CodeGraph does not index (configs, docs, build
scripts), when results are stale or inconsistent, or when the server/index is
unavailable. If the client has not loaded MCP yet, use
`xops/agent/codegraph.sh explore "question or symbol"` for real graph access.
Report unavailable graph access and continue locally if that also fails.

Use graph results as evidence, verifying against source when necessary. For an
enabled integration, re-index via
`make codeg` when the index is stale or missing; use
`xops/agent/codegraph.sh index .` after a large refactor. Record the re-index as a
tracking note. Full procedure: [codegraph-management skill](../../.agents/skills/codegraph-management/SKILL.md).
