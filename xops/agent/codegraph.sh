#!/usr/bin/env bash
# Repository tooling only: pinned CLI/runtime, cache inside ignored .local/.
set -euo pipefail
CG_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$CG_REPO_ROOT"
if ! command -v npm >/dev/null 2>&1; then
  echo 'CodeGraph needs npm to launch its pinned bundled runtime; see docs/guides/MCP_SETUP.md.' >&2
  exit 127
fi
export CODEGRAPH_TELEMETRY=0
export DO_NOT_TRACK=1
exec npm exec --cache "$CG_REPO_ROOT/.local/codegraph/npm-cache" \
  --prefer-offline --yes --loglevel=error \
  --package=@colbymchenry/codegraph@1.6.2 -- codegraph "$@"
