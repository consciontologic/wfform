# Model parameters, MCP and wfformcomp verification

Date: 2026-10-09. Scope: Phase 21, `parameters-connected-tools`.
Application source is based on 0.3.0+10; companion version is 0.1.0.
This report distinguishes actual model execution, local protocol tests, browser
checks and publication. Source and release artifacts are prepared locally;
no source commit, source push or public companion release was made in this task.

## Live acceptance gate

The user authorized bounded tests with a temporary OpenRouter credential.
The current catalog contained 469 entries and 16 tools-capable, all-zero-price
candidates. Every inference selected an exact eligible model, required zero-price
routing and prohibited fallback. No failed request was automatically retried.

| Model / observed provider | Ordinary chat | Independent HTTP MCP | Compiled companion CLI |
|---|---|---|---|
| `liquid/lfm-2.5-2.6b:free` / Liquid | PASS | PASS | PASS |
| `cohere/north-mini-code:free` / Cohere | PASS | PASS | PASS |

Both models passed all three opt-in tests in
`test/live/connected_tools_live_test.dart`, using the production ChatController,
HttpApiTransport and McpClient. Each run made six inference requests, including
one health probe, and eight MCP requests. Each tool case required exactly one
approval and one execution, returned a freshly generated witness unavailable
in the prompt, and produced a final answer containing that witness. The complete
assistant/tool exchange survived export and restore with no network or tool replay.
The independent MCP endpoint was a real local HTTP server, not a transport mock.
The companion was a compiled Linux executable invoking a fixed local command.

Metadata-only logs:

- Liquid: `/tmp/agent-runs/tools-app-live-liquid--20261009T095537Z-129044.log`.
- Cohere: `/tmp/agent-runs/tools-app-live-cohere--20261009T095628Z-130262.log`.

Observed request receipts:

| Case | OpenRouter request ID |
|---|---|
| Liquid ordinary feasibility request | `gen-1791539093-nEI5uE6F8wWAcXW45Mce` |
| Liquid compiled CLI tool request | `gen-1791539422-Ar61GSHjYG0fvr41xbBi` |
| Liquid answer after CLI result | `gen-1791539422-9KtkYsVxxQ8Vm1H1QUQ3` |
| Cohere production ordinary chat | `gen-1791539790-MjjXxFRi8t3p3xlkDbi7` |
| Cohere production answer after HTTP MCP | `gen-1791539792-BIpsqvF9FdhnWCyo0nhI` |
| Cohere production answer after companion | `gen-1791539796-YmngEuSaDGZVFC9e2ncS` |

The three raw Liquid receipts explicitly reported cost 0. The production adapter
tests verified zero-price guards and token usage; their saved metadata does not
independently establish billed account totals. These observations prove these
routes worked at test time, not that every model advertising tools will work.
`google/gemma-4-31b-it:free` returned HTTP 429 in the first bounded check and was
not retried. A later Liquid browser preflight also returned 429 before tool
dispatch; that check remained rate-limited and was not counted as a successful
tool round trip.

## Actual browser checks

The real Chromium-backed browser loaded a public Flutter build on a separate
test origin. Runtime test configuration was mounted separately from public
assets; it was never included in the public build or container image.

- Ordinary Cohere chat returned the requested acknowledgement.
- The Tools dialog connected to the independent HTTP fixture, discovered and
  selected its tool, requested **Allow once**, and displayed the correct fresh
  witness. The server execution counter was exactly one.
- The dialog paired with the compiled companion using a memory-only bearer
  token. One approved fixed CLI call returned the expected file witness and the
  model included it in its final answer.
- Reload restored all ten messages, including both complete tool exchanges.
  Both saved connections were disconnected, selected tools were explicitly
  unavailable until reconnect, and the fixture execution count remained one.
- The connection dialog was readable at 390×844. Deterministic widget checks
  separately covered 320×740 at 200% text for connections and parameters.
- An actual nginx container allowed authenticated companion discovery through
  its CSP and cross-origin CORS. The extra inference attempt then hit the 429
  recorded above; nginx tool execution is not claimed from that attempt.
- The final nginx release passed all 49 asset SHA-256 checks, enforced headers,
  error/method policy, config no-store and WASM MIME checks. Its release identity
  is `7cd843657a1ca0a4d2c7aa3c049d1229a6de780e6afee2fd7a590cc5e80fe073`.
  Actual **Save & update** preserved the selected model, tool selection and
  incomplete rate-limited conversation without another inference request.
  Log: `/tmp/agent-runs/tools-final-nginx-check--20261009T102728Z-165656.log`.
- The compiled companion's `--web-root` host loaded the full Flutter chat UI
  directly on its own loopback origin, including Parameters, Tools and Context.

Browser operations used the actual UI. No browser automation bypassed approval
or dispatched a tool invisibly. The successful model tests used explicit test
output limits; production fields remain omitted until users configure them.

## Companion and local MCP evidence

The compiled binary successfully performed authenticated CLI lifecycle tests.
The existing pinned CodeGraph process was started through the stdio bridge,
initialized, discovered and called as `codegraph__codegraph_explore`. It returned
real ChatController source references. This is actual companion-to-CodeGraph
evidence; the OpenRouter witness round trip used the narrower fixed CLI fixture
so no repository source needed to be sent to a provider.

- CodeGraph: `/tmp/agent-runs/companion-codegraph-final--20261009T100140Z-138243.log`.
- Compiled CLI: `/tmp/agent-runs/companion-reviewed-native-cli--20261009T101339Z-150275.log`.
- Companion suites: `/tmp/agent-runs/tools-final-repository-companion--20261009T102229Z-160791.log`.

All eight standalone companion suite programs passed, covering 16 named groups:
authentication/Host/Origin, literal argv, output/time bounds, cancellation,
stdio, guarded static hosting, session isolation, Linux process-group cleanup,
compiled CLI lifecycle, uncertain outcomes and shared-stdio admission.
Shared stdio admits one call at a time. Cancellation stops the shared child and
requires an explicit companion restart; a competing session is rejected before
dispatch. This limitation is documented rather than hidden by automatic restart.

## Regression and release checks

Final `make verify` passed: **596 Flutter/app/tool tests**, four explicitly
opt-in live skips, 155 Dart files unchanged by formatting, clean Flutter and
companion analyzers, repository hygiene and all eight companion suite programs
(16 named PASS groups). Log:
`/tmp/agent-runs/tools-final-complete--20261009T102915Z-167800.log`.
The live skips in this deterministic run are separate from the two successful
authenticated three-case runs above. Independent checks passed 14
repository-operation tests and seven actual Chromium IndexedDB tests. Logs:

- `/tmp/agent-runs/tools-final-ops--20261009T102050Z-157986.log`.
- `/tmp/agent-runs/tools-final-browser-storage--20261009T102108Z-158203.log`.

Review regressions include fragmented tool calls, opaque reasoning retention,
whole-exchange context selection, model-aware reasoning constraints, empty drafts
with parameter settings, near-capacity history, unsolicited tool calls, HTTP
redirect credential isolation, uncertain outcomes and no replay after restore.
The original full UI gate found ambiguous Parameters text finders and a test
that tapped Context below the compact composer's scroll viewport. The repairs
scope passport headings to ModelDetails and scroll Context into view, adding
uniqueness/hit-testability assertions while retaining every original action and
content assertion. All 14 focused tests then passed.

Final independent review found no actionable findings. Its last 19 scoped tests
passed, covering the package copier and repaired UI tests, after the broader
protocol/security review passed. The reviewed failure breadcrumb was marked
resolved only after the final aggregate gate passed.

`make companion.build` produced the credential-free public release
`26d919a298a13b45bc3213abbd79031611ce5ee43aaafb23a942d91341e4374a`
with 49 assets / 18,407,516 bytes. The companion archive is
`build/companion/wfformcomp-linux-x64.tar.gz`, **16,261,489 bytes**, containing
104 files and exactly one active web release. Its SHA-256 is
`762abebf9033068fb18728b653a3928dbcff4f7f5b0ce01c8503c2f148efd1b2`.
An adjacent `.sha256` and `companion-release.json` describe the artifact.
The archive excludes retained historical releases and private configuration;
every file was scanned for supplied credential patterns. Five new package
regressions cover retained history, unsafe paths, damaged assets, symlinks and
worker/version mismatch. The final compiled executable passed real CLI
init/authenticated serving/clean shutdown checks:
`/tmp/agent-runs/tools-final-compiled-cli--20261009T103015Z-171735.log`.
Build log:
`/tmp/agent-runs/tools-final-companion-bundle--20261009T102919Z-168040.log`.

## Boundaries

Linux x64 is the built and exercised companion target. Windows/macOS binaries,
signing/notarization, auto-update, OAuth discovery, legacy MCP HTTP+SSE,
sampling/elicitation and arbitrary third-party server CORS are not verified or
automatically supported. Compatible HTTPS remote endpoints use the same HTTP
client, but the live user-supplied endpoint in this run was local HTTP; no
third-party hosted MCP deployment is claimed.

The browser calls OpenRouter directly; nginx and the companion do not proxy it.
Only user-selected schemas are supplied in `tools`; each invocation requires
approval. Tool results sent to the model leave the computer. The companion's
fixed commands and allowlisted stdio servers run with the user's OS privileges,
not in an OS sandbox. Unknown post-dispatch outcomes stop the loop and are saved
for inspection instead of being retried.

The GitHub token supplied for testing was not needed and was never used or
stored. The temporary OpenRouter file, browser runtime test configuration and
both generated companion pairing-token files were deleted after testing.
A credential-pattern scan found no supplied keys in the owned scratch files.
All five owned test processes and the nginx container were stopped, and the
temporary browser tabs were closed. The user can revoke both supplied tokens.
Public release remains a separate maintainer action through the documented
tagged workflow.
