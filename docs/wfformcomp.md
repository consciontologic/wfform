# wfformcomp

Optional local companion for configured CLI tools and stdio MCP servers. It exposes
an authenticated loopback MCP endpoint and can serve a trusted public wfform web build.
Browser inference still goes directly to OpenRouter. Start with [Tools](tools.md).

## Packages and setup

[Releases](https://github.com/consciontologic/wfform/releases) provide Linux x64
`.tar.gz` and Windows x64 `.zip` portable packages with checksums. No Dart/Flutter is
needed to run them. Graphical installers, automatic setup/updates, signing and macOS
are [planned](https://github.com/consciontologic/wfform/blob/develop/docs/planning/ROADMAP.md#phase-22--companion-platform-downloads-and-easy-installation).

Extract into a folder you own, verify the adjacent SHA-256 checksum, then initialize:

```sh
# Linux
./wfformcomp init --config ./private/config.json --token-file ./private/pairing-token
```

```powershell
# Windows PowerShell
.\wfformcomp.exe init --config .\private\config.json --token-file .\private\pairing-token
```

This creates an empty tool allowlist and private random 256-bit token (owner-only
POSIX permissions or protected current-user Windows ACL, checked again on startup).
Edit `private/config.json`, adding only intended tools and exact `allowedOrigins`,
e.g. `https://wfform.com`. Origins have no path/trailing slash; wildcards, `null` and
non-loopback plain HTTP are refused.

```sh
# Linux, with bundled UI
./wfformcomp serve --config ./private/config.json --token-file ./private/pairing-token --web-root ./web
```

```powershell
# Windows, with bundled UI
.\wfformcomp.exe serve --config .\private\config.json --token-file .\private\pairing-token --web-root .\web
```

Open the printed web URL, then Tools: use the printed `http://127.0.0.1:PORT/mcp`
endpoint and token-file contents. The companion never prints/embeds its token.
Its own web origin is allowed automatically but still requires pairing. To use the
hosted site, omit `--web-root` and allow that site's origin. Keep a stable port to
retain connections/history; port `0` selects a temporary port for tests.

Ctrl+C stops the process. Restart after config/token changes; replacement revokes the
old token only after restart. Remove the saved browser token too. Serve only trusted
public web builds; arbitrary web applications are not sandboxed. Config/dotfiles and
symlinks escaping the web root are never served. Local/hosted histories are separate.

## Fixed local program tools

Add this object to `tools`, replacing paths with your actual Git binary/project:

```json
{
  "name": "repository_status",
  "description": "Read the approved project's working-tree status.",
  "executable": "/absolute/path/to/git",
  "arguments": ["status", "--short"],
  "workingDirectory": "/absolute/path/to/project",
  "timeoutMs": 15000,
  "maxOutputBytes": 65536,
  "inputSchema": {"type": "object", "properties": {}, "additionalProperties": false}
}
```

Find Git with `command -v git` or PowerShell `(Get-Command git).Source`. Windows JSON
paths double backslashes, e.g. `"C:\\Program Files\\Git\\cmd\\git.exe"`.
Restart/reconnect, enable **repository_status**, then ask the model to use it.

Program, argv, folder and environment are fixed by config. A whole `"{query}"`
argument substitutes one schema-validated scalar argv value without shell parsing.
Only configured environment values reach children; Windows may add the non-secret
`WFFORMCOMP_CHILD=1` marker to avoid a runtime empty-environment bug.
Use native `.exe` paths on Windows; `.bat`/`.cmd` wrappers are rejected. Node servers
use `node.exe` plus a fixed JS entrypoint, not `npm.cmd`/`npx.cmd`.

This is an allowlist, **not an OS sandbox**. Avoid arbitrary shell/eval/code, filenames
or dangerous CLI flags as model input. Use narrow schemas and `--` where appropriate.
Supported schema keywords: `type`, `properties`, `required`, boolean
`additionalProperties`, `items`, `enum`, `minimum`, `maximum`, `minLength`, `maxLength`,
`title`, `description`. Roots require objects with `additionalProperties: false`;
unsupported keywords fail. Default string bound: 8,192 characters. Results contain
stdout/stderr/exitCode and applicable timeout/cancel/output-limit flags.

## Existing stdio MCP servers

Add this Linux example under `mcpServers` after `make codeg`; replace checkout/PATH:

```json
{
  "name": "codegraph",
  "executable": "/absolute/checkout/xops/agent/codegraph.sh",
  "arguments": ["serve", "--mcp", "--path", "/absolute/checkout"],
  "environment": {"PATH": "/usr/bin:/bin"},
  "allowedTools": ["codegraph_explore"],
  "timeoutMs": 30000
}
```

Enable **codegraph__codegraph_explore** in wfform and ask a source question. The
companion starts its own server process using the existing index; another app's
CodeGraph session can remain open. The `.sh` example needs Bash; Windows must use
that server's installed native executable/arguments. The companion installs no servers.

Only discovered `allowedTools` are exposed; missing names fail startup. Stdio supports
protocol `2024-11-05` as well as the HTTP versions below. Each stdio server admits one
call across browser sessions; another receives a definite busy error. Timeout/cancel
stops that shared server and reports uncertainty when effects cannot be known, with
`_meta: {"wfform.com/outcome":"uncertain"}`. Never automatically restart/replay;
inspect effects and restart explicitly. Returned source/data goes to the model through
OpenRouter. Use trusted servers only.

## Bounds and protocol

Bind IPv4 loopback only; validate Host, exact Origin and bearer auth for every RPC.
`/health` is metadata only; OPTIONS supports allowed-origin CORS/private-network
preflight. `/mcp` supports initialize, ping, tools list/call and cancellation, JSON or
single-message SSE responses, protocols `2025-11-25`, `2025-06-18`, `2025-03-26`.
No standalone GET stream or automatic resumption.

Random session IDs isolate cancellation across tabs; up to 64 sessions, one-hour idle
expiry, DELETE to close, unknown sessions require reconnect. Native sessionless users
must coordinate IDs within their origin. Limits: four concurrent calls, 128 advertised
tools, 64 configured commands, eight stdio servers, 256 KiB request, 4 MiB stdio message,
120-second maximum timeout. Combined command output defaults to 64 KiB, max 256 KiB.

Linux process groups and Windows Job Objects contain descendants for shutdown/cancel;
Windows gates startup until assignment. Avoid tools that deliberately escape groups.
Native Windows tests remain a release gate. Routine logs omit arguments, results,
tokens and MCP stderr.

## Build and checks

Use the pinned repository SDK, on the target operating system:

```sh
make companion.verify
make companion.build
# Direct target-OS build (also usable on Windows without Make):
dart run tool/build_companion.dart --web-root build/publish-web
```

The helper writes binary/archive/checksum/metadata under `build/companion/`; it does
not cross-compile or publish. Windows CI receives the same verified public web build
from Linux. Archives contain these instructions, `TOOLS.md`, empty config and web
assets, never credentials. Checksums detect corruption, not publisher signing.
Report native process checks, browser permissions, live model loops and actual
publication separately. Try the [developer playground](https://github.com/consciontologic/wfform/tree/develop/examples/tools_playground).
