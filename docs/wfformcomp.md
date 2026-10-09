# wfformcomp

`wfformcomp` is the optional local Dart companion for wfform. Ordinary chat and
compatible remote MCP connections do not require it. It exposes approved local
programs and existing stdio MCP servers through an authenticated loopback MCP
endpoint. It can also serve a trusted public Flutter web build locally.
OpenRouter requests still go directly from the browser to OpenRouter.

New to tools? Start with the [simple tools guide](tools.md) (**TOOLS.md** in a downloaded archive). It shows what to click and what to ask the model.

## Choose your package

| Computer | Package | Status |
|---|---|---|
| Linux x64 | `wfformcomp-1.0.0-linux-x64.tar.gz` | Native build and local checks available. |
| Windows x64 | `wfformcomp-1.0.0-windows-x64.zip` | Build/package support added. Native Windows execution remains pending; no verified Windows download is claimed here. |
| macOS | Planned | Deferred until native building, testing and signing/notarization are available. |

These are **portable developer previews**, not graphical installers. Extract the package into a folder you own; Dart/Flutter is not needed to run the compiled program. A maintainer must publish a successful companion release before its downloads are available. This repository’s support for building Windows does not mean a Windows download has already been published or tested on this Linux workstation.

The planned everyday flow is **download → install/open → launch wfform**, with automatic private setup, browser launch, pairing approval and tool configuration in the UI. Graphical Linux/Windows installers and this simplified setup remain in [roadmap Phase 22](planning/ROADMAP.md#phase-22--companion-platform-downloads-and-easy-installation). The manual preview below is the current setup.

## Current setup: create settings, add tools, start, connect

Download the package for your computer once a maintainer has published it, check its adjacent SHA-256 checksum, and extract it. Open a terminal in the extracted folder. Create its private settings once:

**Linux**

```bash
./wfformcomp init --config ./private/config.json --token-file ./private/pairing-token
```

**Windows PowerShell**

```powershell
.\wfformcomp.exe init --config .\private\config.json --token-file .\private\pairing-token
```

This creates an empty tool allowlist and a random 256-bit token. On POSIX the
token file is restricted to its owner; on Windows it uses a protected access
list for the current user, checked again when the companion starts. Edit `private/config.json` to add tools
and the exact website origin permitted to connect. An origin has no trailing
slash or path, for example `https://wfform.com` or `http://localhost:8080`.
Wildcards, opaque `null` origins and non-loopback plain-HTTP origins are refused.

For the bundled web app, start the companion with its `web` folder:

**Linux**

```bash
./wfformcomp serve --config ./private/config.json --token-file ./private/pairing-token --web-root ./web
```

**Windows PowerShell**

```powershell
.\wfformcomp.exe serve --config .\private\config.json --token-file .\private\pairing-token --web-root .\web
```

Open the local web address printed in the terminal. If you prefer the website at `https://wfform.com`, omit `--web-root` and ensure that origin appears in `allowedOrigins`.

In wfform's tool connection settings, use the printed `http://127.0.0.1:PORT/mcp`
URL and the token file contents as the bearer token. The companion never prints
or embeds a token in the binary. Keep the terminal running; Ctrl+C stops it.
Browser local-network permission may be required. Host/CORS validation and the
bearer check remain mandatory even after the browser grants that permission.
Use a stable configured port to keep a saved connection valid; port `0` chooses
an available port for tests.

When `--web-root` is enabled, the local web origin is automatically permitted.
Pairing is still required. Local web history and credentials belong to that
local address, separately from `wfform.com`.
Only serve a trusted wfform public build: the companion does not sandbox arbitrary
web applications. It never serves `config/`, dotfiles or symlinks outside the web
root, and never acts as an inference/API proxy. Stop and restart explicitly to
load configuration changes. Deleting/replacing the token revokes future use
only after restart; remove the saved token from wfform as well.

## Fixed local program tools

Each entry in `tools` fixes a program's absolute path, arguments, working folder
and optional environment. The browser/model cannot change those settings.
Add this entry inside the `tools` array in `private/config.json`. Replace the two paths with your installed Git program and your project folder:

```json
{
  "name": "repository_status",
  "description": "Read the working-tree status of the approved project.",
  "executable": "/absolute/path/to/git",
  "arguments": ["status", "--short"],
  "workingDirectory": "/absolute/path/to/project",
  "timeoutMs": 15000,
  "maxOutputBytes": 65536,
  "inputSchema": {
    "type": "object",
    "properties": {},
    "additionalProperties": false
  }
}
```

On Windows, the equivalent paths in JSON might be `"C:\\Program Files\\Git\\cmd\\git.exe"` and `"C:\\Users\\YourName\\Projects\\my-project"`; use your actual installation and double each backslash. PowerShell’s `(Get-Command git).Source` shows the installed Git path. On Linux, `command -v git` shows it. Restart the companion after saving the configuration, connect in wfform, check **repository_status**, and ask: **“Use repository_status to list the changed files.”**

An entire argument such as `"{query}"` can substitute a schema-validated scalar
property. It remains one argv element; no shell parsing/interpolation occurs.
Children receive only explicitly configured environment values. On Windows, an
empty configuration adds the fixed, non-secret `WFFORMCOMP_CHILD=1` marker to
avoid a Dart runtime empty-environment bug; no parent variables are copied.
Windows tools must point to a native `.exe`. Batch wrappers (`.bat`/`.cmd`)
are rejected because Windows can interpret their arguments through a shell.
For a Node MCP server, use the actual installed `node.exe` with its fixed
server JavaScript entrypoint in `arguments`, rather than `npm.cmd` or `npx.cmd`.
Add required environment such as `PATH` for wrappers that launch other programs.
The operating-system user's privileges still apply: this is an allowlist, not
an OS sandbox. Do not expose an interpreter's code/eval argument, arbitrary
shell commands, unrestricted filenames, or dangerous CLI flags as model inputs.
Use a narrow schema and a CLI's `--` argument separator where appropriate.

Command schemas support `type`, `properties`, `required`, boolean
`additionalProperties`, `items`, `enum`, `minimum`, `maximum`, `minLength`,
`maxLength`, `title` and `description`. Unsupported keywords are rejected rather
than ignored. Command roots must be objects with `additionalProperties: false`.
Default empty-object schemas accept no model arguments. Numbers, strings,
booleans, arrays and nested objects are validated; command placeholders accept
only scalars. String input defaults to at most 8,192 characters. The command
result contains JSON text with `stdout`, `stderr`, `exitCode` and applicable
`timedOut`, `cancelled` or `outputLimitExceeded` flags.

## Existing stdio MCP servers

Add explicit entries under `mcpServers`. The companion initializes the approved
local server, discovers its tools, and exposes only `allowedTools`. Names are
prefixed with the connection name to avoid collisions. Add this object inside the `mcpServers` array in `private/config.json`. If that array is missing, add `"mcpServers": []` alongside the existing `"tools": []` property, separating the properties with a comma. This Linux example uses this repository’s pinned CodeGraph launcher:

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

This example’s `.sh` launcher needs Bash. For a Windows MCP server, use the actual installed executable and arguments from that server’s Windows setup instructions; a Unix `.sh` path is not a Windows executable. JSON paths need doubled backslashes. The companion does not install MCP servers for you.

Initialize the project's CodeGraph index with `make codeg` first. Match `PATH`
to the installed Node/npm paths. The browser sees
`codegraph__codegraph_explore`; normal user prompts can request source searches.
The currently tested pinned CodeGraph process advertises `codegraph_explore` and
negotiates stdio protocol `2024-11-05`. Other explicitly listed tools must actually
be advertised by their server; startup fails if one is missing. The HTTP side
supports `2025-11-25`, `2025-06-18` and `2025-03-26`; the stdio bridge additionally
accepts `2024-11-05`. MCP server input schemas/results remain server-owned.

A local MCP timeout/cancellation stops its child server and marks the outcome
uncertain when appropriate. It never restarts or repeats a call automatically.
The result includes `_meta: {"wfform.com/outcome":"uncertain"}` so wfform stops
the model/tool loop and preserves the result for review. A known command exit or
explicit MCP error remains a definite error.
Each stdio server admits only one tool call at a time across all browser sessions;
a second call gets a definite busy error before reaching the child. Cancelling
or timing out that call stops the shared server for every connected session.
Restart the companion explicitly after resolving that interruption. The server
can observe the user's files and credentials according to its own capabilities;
only connect servers you trust. Tool output sent back to the model leaves the
computer through the ordinary OpenRouter request, including returned source text.

## Bounds and protocol

The companion binds only IPv4 loopback and validates Host and exact Origin.
`GET /health` exposes only name/version/protocol metadata. Every MCP RPC requires
bearer authentication. `OPTIONS` handles allowed-origin CORS/private-network
preflight without credentials. `POST /mcp` supports initialize, ping,
notifications/initialized, tools/list, tools/call and notifications/cancelled.
Initialization returns a browser-readable random MCP session ID. Clients echo it
on later calls so two tabs with the same RPC ID cannot cancel each other. Up to
64 sessions remain valid for one hour of inactivity; DELETE closes a session.
Unknown/expired sessions return 404 and require explicit reconnection. Native
sessionless callers are supported, but must coordinate request IDs within the
same origin. There are no reconnect/resume streams or automatic replay.
Responses are JSON, or a single SSE message when the client accepts only SSE;
standalone GET streaming is not supported (405). Normal clients may advertise
both JSON and SSE. See the official
[MCP transport specification](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports).

At most four tool calls execute concurrently, with 128 combined advertised tools,
64 configured command tools, eight stdio servers, a 256 KiB request limit,
4 MiB stdio message limit and a 120-second maximum configurable timeout. Command
output defaults to 64 KiB and may be configured up to 256 KiB (stdout and stderr
combined). Linux uses a separate process group to terminate child programs on
cancellation/shutdown/output exhaustion. The Windows implementation uses Job
Objects to keep child programs in a process tree that closes with the job; a
gated runner waits for job assignment before starting the configured command.
Native Windows cleanup checks must pass before its package is released. macOS
is deferred and is not claimed as a verified release. Avoid commands
that daemonize or escape process groups. No routine logs include arguments,
results, tokens or MCP stderr; authentication failures produce a fixed message.

## Build and checks

Run from the repository root, using its pinned Flutter/Dart SDK:

```bash
dart pub get --offline -C companion
dart analyze companion
dart run companion/test/server_test.dart
dart run companion/test/stdio_test.dart
dart run companion/test/static_host_test.dart
dart run companion/test/session_test.dart
dart run companion/test/stdio_sessions_test.dart
dart run companion/test/uncertainty_test.dart
dart run companion/test/process_group_test.dart  # Native descendant cleanup
dart run companion/test/cli_test.dart
dart run companion/test/codegraph_smoke.dart  # opt-in real local CodeGraph

dart run tool/build_companion.dart
# To include a separately built public web release:
make build.public
dart run tool/build_companion.dart --web-root build/publish-web
```

The build helper writes the native binary, archive, SHA-256 checksum and release metadata under ignored `build/companion/`. Run it on the target operating system: Linux produces a `.tar.gz`, Windows produces a `.zip` containing `wfformcomp.exe`. It does not cross-compile or publish anything. On Windows, use PowerShell with the pinned SDK available: `dart run tool/build_companion.dart` builds the companion alone. To include the web app, obtain a verified public build from the Linux build job and use `dart run tool/build_companion.dart --web-root build/publish-web`. The workflow transfers that same verified public build to the native Windows job; Make is not required there.

For `1.0.0`, the Windows outputs are `wfformcomp-1.0.0-windows-x64.exe`, `wfformcomp-1.0.0-windows-x64.zip`, `wfformcomp-1.0.0-windows-x64.zip.sha256` and `wfformcomp-1.0.0-windows-x64.json`. The executable inside the extracted package is still named `wfformcomp.exe`; Linux uses `wfformcomp`. Release and tag names are plain `1.0.0`, with product/platform added only to distinguish downloadable files. The release workflow builds and tests Linux and Windows on separate native runners before publication. Native Windows runtime evidence must come from that runner or a Windows machine; Linux checks cannot substitute for it.

The archive contains the binary, these setup instructions, `TOOLS.md` with the simple user guide, an empty configuration example and optionally the current public web build. Web files use ordinary paths inside `web/`; no `__releases` folder is included. `release.json` keeps the SemVer package version and internal content hash for integrity and offline caching. It contains no pairing token, local
config, OpenRouter credential or GitHub credential. Checksums detect download
corruption; signing/notarization and automatic updates are not implemented.
Browser permission checks, actual OpenRouter tool loops and download publication
must be reported separately from the local protocol/process tests.
