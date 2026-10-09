# 🌊 Desktop tools and 1.0.0 delivery verification

Date: **2026-10-09**. Local work branch: `codex/release/1.0.0`.
This report describes local verification and separately identified GitHub
configuration changes. It does **not** claim a published 1.0.0 release.

## What changed

- Phones/tablets show a faded **Tools** control and explain desktop availability.
  The same policy blocks tool connections, request definitions and execution;
  saved settings/history remain intact and ordinary chat works. Android/iOS,
  desktop-mode iPad and touch-only desktop-mode Android tablet cases are tested.
  Narrow desktop windows and fine-pointer touch laptops retain tools. Browser
  device hints are a product policy, not tamper-proof device identification.
- Keep one whole-message/source copy where useful, code-block copy for chat,
  and whole diagnostic-report copy. Nested previews, guides and metadata no
  longer repeat copy controls. Selectable text and source views remain.
- [Tools playground](../../examples/tools_playground/README.md) provides real
  stdio MCP arithmetic/JSON/YAML/CSV examples and a fixed sales-report program
  through the companion. Missing/oversized resource failures use JSON-RPC
  errors. Tests launch actual processes and use the HTTP-to-stdio bridge.
- Root **1.0.0** synchronizes app/companion/public page versions. Release titles
  and tags use plain SemVer; downloads include product/version/platform.
- Flat deployment removes physical `__releases` folders while preserving
  internal hash verification, cached legacy clients and explicit reload when
  retired bytes are unavailable. Output/ownership/symlink checks protect
  unrelated files before publication mutates anything.
- Gitflow helpers/instructions, emoji changelog, colored pipeline summaries,
  Linux/Windows jobs, GitHub Releases and free quality/security reports are
  configured. Website publication is separately rerunnable after a failed
  deployment; a tag older than current main explicitly skips website replacement.

## Tests and reviews

**Final `make verify` passed**: 642 Flutter tests, four existing opt-in skips,
11 companion suites (20 pass groups), five Node worker tests, formatting of
176 files, both analyzers, version identity and repository checks.
Independent review passed the desktop capability and release safety changes.
Red-first evidence includes mobile dispatch/copy regressions, Android desktop
mode, resource errors, bootstrap stamping, unsafe output/symlink publication
and package-license root resolution. Stale version assertions were updated to
require exact plain SemVer, not loosened.

- 22 Python repository-operation tests passed for the release baseline; the
  Gitflow follow-up adds publication regression tests and records its final
  count separately below.
- 7 real Chromium IndexedDB tests passed (Chromium 155.0.8059.39, Linux x64).
- 90 independently rerun deployment/PWA tests passed before the final report-only
  security fix; its additional license regression passed independently.
- CodeGraph 1.6.2: 224 indexed files, zero pending changes; actual
  `browserSupportsTools` query returned its definition, caller and test reference.

Logs live under `/tmp/agent-runs/` and are not packaged or committed. Relevant
run identifiers:

| Check | Run identifier |
|---|---|
| Full final gate | `release100-final-complete-verify--20261009T123610Z-316016` |
| Python operations | `release100-final-ops--20261009T123213Z-307259` |
| Real Chromium storage | `release100-final-chromium--20261009T123305Z-309495` |
| Independent release safety review | `review-release-safety-fixed--20261009T123048Z-304839` |
| Actual packages | `final-100-release-packages--20261009T123206Z-307064` |
| Extracted Linux executable and archive hashes | `final-100-extracted-smoke--20261009T123317Z-310213` |
| Final OSV/license scan | `final-100-package-security--20261009T123530Z-315333` |
| Gitleaks history | `security-local-secrets--20261009T122149Z-293304` |
| Gitleaks prospective source inventory | `security-prospective-files--20261009T123030Z-304547` |
| zizmor workflow audit | `devops-final-workflow-audit--20261009T122613Z-299038` |

## Actual browser update

The existing `http://localhost:8765/` tab updated from **0.3.0** through
**Check for update → Save draft & update**. Browser storage was not cleared.
All six chats remained: message counts **16, 4, 2, 6, 3, 2**. The selected model,
tool selections and demo conversation survived. The sidebar displays **1.0.0**;
redundant source-copy buttons are absent.

The app's own metadata-only cache inspection reports active release
`43bd480cb0e92fbf4b77f19d9fe9fe0619d3c01e2239ff8329645da3e9ec1b42`,
52 cache entries, 27 reused assets and 24 fetched assets, with the preceding
cache retained. Cache violations, cached configuration, API responses and
authorization-bearing entries are all **zero**. No new inference was requested.
Physical phones/tablets and a native Windows machine were not available; those
claims are limited to the stated automated platform tests and configured CI.

## Actual packages and free reports

The public build contains 51 assets (18,442,886 bytes), manifest format 3,
packageVersion 1.0.0 and no physical legacy release directory. Both archives
contain no credentials or legacy release directories. The extracted Linux
executable passed initialization, private credentials, no-overwrite handling,
authenticated tools/static web and clean shutdown checks.

| Archive | Bytes | SHA-256 |
|---|---:|---|
| `wfformcomp-1.0.0-linux-x64.tar.gz` | 9,664,644 | `18fcc6ac1c1f372ff0a4c2004de6ac67821b040a89d87decd2c9697df349df18` |
| `wfform-1.0.0-web.tar.gz` | 6,632,067 | `6730a0debc02f6186d4becd10d1bde586a67f3b9f0c77802989b2fbf4da7c0a0` |

OSV matched **31 public packages and zero known vulnerabilities** at scan time.
All 31 license texts are included in the inventory. Gitleaks found zero secrets
in 26 commits and the prospective source inventory; zizmor passed. Reports,
CycloneDX SBOM, package freshness and license evidence are under ignored
`build/reports/`. No paid scanner or dashboard was introduced.

## GitHub configuration actually applied

Authenticated read-back confirmed new emoji descriptions, topics and the
canonical homepage for **consciontologic/wfform** and **consciontologic/wfform.com**.
The source repository's `develop` branch was created at the existing main SHA
`c5028a5998afaf34290a8591954715b77cabe2d3`. Both source branches now require PRs,
one approval and resolved conversations; stale approvals are dismissed and
force-push/deletion disabled. Administrators retain bootstrap/recovery bypass.
Website main remains a generated-artifact publication branch.

Required CI contexts remain a **manual merge gate** until these unpushed
workflows run remotely; then configure their real names as required checks.
At that configuration checkpoint, no source commit/push, PR, release tag or
public package had been created. The following release-initiation follow-up
records subsequent work separately.
The live website's physical legacy assets change only when the new publisher runs.

## Copilot and remaining release gates

Initial checks after enabling reviews omitted Copilot from assignable actors.
After the user enabled **cloud agent** and permissions, the 2026-10-09 recheck
returned `copilot-swe-agent`; task listing and remote `develop` reads succeeded.
Exactly one read-only access audit was submitted at **15:41:33 Europe/Istanbul**
(12:41:33 UTC), using the existing helper with an explicit audit body:
`model: gpt-6-luna`, `base_ref: develop`, `create_pull_request: false`.
No ignored/local source, credentials or staged changes were sent to the agent.

[Task ff2a234a-45f2-42ec-b9dd-b9972394baf8](https://github.com/consciontologic/wfform/tasks/ff2a234a-45f2-42ec-b9dd-b9972394baf8)
was accepted as queued, then reported **failed** at 15:42:05. Session
`6f2359b4-6cbb-44f4-bd10-9ffb381676eb` records:

> Execution failed: Error: Auto-mode unavailable and no fallback model could be resolved.

The session's model field is `sweagent-capi:gpt-5.3-codex`, which does not match
the requested model. This metadata does not prove that model performed inference
or establish billing. The sole reported artifact is a `copilot/develop` branch;
there is no PR artifact. No automatic retry or fallback was requested. At that checkpoint execution
and low-cost routing were still unverified. The subsequent explicit model trial
below resolves that execution gate; changing API versions was not used as a fix.

The temporary credential was passed through a non-echoing terminal prompt and
kept only in process memory. Ignored `.local/release-100/copilot-enabled-*`
receipts preserve request/status evidence without the credential.

### Explicit working model and guarded publication follow-up

The user requested a cheap working model and release initiation, then authorized
agents to use `make git` on Gitflow work branches while forbidding direct writes
to `main` and `develop`. Shared agent instructions now reflect that rule.
The wrapper uses an explicit same-name branch refspec with mirror/follow-tags
disabled, so upstream configuration cannot redirect publication to `main`.
Red-first tests reproduced the old implicit push and stale model policy.
The guarded wrapper also resumes a previously committed but failed push only
after inspecting the live remote branch and confirming tracked HEAD/ancestry;
it does not create a duplicate commit or retry automatically.

All **33 Python operation tests passed** after these changes, including protected
branch rejection, explicit destination, failed-push recovery and already-published
no-op cases. Evidence: `git-resume-all-ops--20261009T130313Z-343138`. Repository
hygiene and 1.0.0 version consistency passed in
`release-initiate-hygiene--20261009T130259Z-342353`.

[Task 72913e53-5a2c-46f9-9239-24744f015df9](https://github.com/consciontologic/wfform/tasks/72913e53-5a2c-46f9-9239-24744f015df9)
completed a read-only audit on remote `develop`. Session
`f9102a05-0880-4f0d-80aa-bfaf9a0699b8` is **completed**, reports
`sweagent-capi:gpt-5.3-codex` and has no error. No PR was requested. The task
reviewed only the old remote source; it did not claim to inspect staged 1.0.0.
The initial capability check for this trial failed before submission; a fresh
check succeeded and exactly one GPT-5.3-Codex task was submitted.

The checked-in policy now permits only `gpt-5.3-codex`, with Auto and automatic
pricier fallback disabled. Its published rates at review time are $1.75 input,
$0.175 cached input and $14 output per million tokens: lowest among the active
models listed for the REST task API, not a claim about all UI-only models or
final task cost. Sources: [API models](https://docs.github.com/en/rest/agent-tasks/agent-tasks),
[pricing](https://docs.github.com/en/copilot/reference/copilot-billing/models-and-pricing).

Use the [Gitflow guide](../guides/GITFLOW.md) for the preparation/promotion PR
sequence. GitHub cloud agents cannot approve/merge their own PRs; the human
requester also cannot provide the required approving review for a Copilot PR.
An eligible independent reviewer and passing checks precede merge/publication.
Source publication, native Windows CI, required check activation and a published
1.0.0 tag/download are recorded only once actually observed. macOS and graphical
installers remain future work; portable archives are not described as installers.

### Independent preparation audit (2026-10-09, Copilot PR #2)

This checkpoint is a fresh release-readiness audit for
[`copilot/release-100-preparation` → `release/1.0.0`](https://github.com/consciontologic/wfform/pull/2).
It does not replace the historical local evidence above.

- Checked-out app version remains `1.0.0` in root `pubspec.yaml`.
- Model policy remains explicit `gpt-5.3-codex` only (`allow_auto: false`,
  `allow_paid_fallback: false`).
- Release gating in `.github/workflows/companion.yml` remains strict:
  `linux` needs `security`, `windows` needs `linux`, and `publish` needs both
  native jobs and runs only on plain SemVer tag pushes.
- Fresh local run: `python3 -m unittest discover -s xops/makefile -p 'test_*.py' -v`
  passed all 33 tests in this session.
- Fresh local `make version.check` and `make repository.check` could not run in
  this sandbox because `dart` is unavailable (`make: dart: No such file or directory`).

GitHub Actions evidence available at this checkpoint:

- `🛡️ Free security and package reports` run `37934431905`: **success**.
- `📦 Packages and release` run `37934432076`: still in progress; `security`
  succeeded and `Linux package` started. `Windows package` has not completed yet.
- `🌐 Web quality` run `37934431743`: in progress.
- Preparation PR #2 follow-up runs `37934772462`, `37934772488`, and
  `37934772949` currently show **action_required** with zero jobs scheduled,
  so no fresh PR #2 job outcome exists yet.

Remaining gates before promotion from `release/1.0.0` to `main`:

1. Let PR #2 complete review and merge into `release/1.0.0`.
2. Observe green web/security/Linux/**native Windows** checks on the final
   release-branch revision (do not infer Windows from Linux).
3. Merge the release promotion PR (`release/1.0.0` → `main`) with eligible
   independent approval and required checks.
4. After reviewed main merge, publish plain tag `1.0.0`, then complete the
   required `develop` back-merge PR.

## Opinion: a VS Code extension

A small **desktop-first extension** is worthwhile after the 1.0.0 delivery path
is proven. Reuse the Flutter chat UI in a webview and the companion/tool protocol;
add workspace and selected-code context, command-palette entry, secret storage,
and a workspace-aware host adapter. This would reduce setup for developers
without maintaining a second chat implementation. It is a proposal, not built.

Require Workspace Trust and per-call approval. Be explicit about whether a tool
runs on the local PC or an SSH/container extension host. Browser-only VS Code
cannot directly spawn the user's local CLI, so it still needs a compatible
remote connection/companion. A host adapter needs extension glue in addition to
Flutter and should be agreed as a separate scoped feature.

Sources: [extension hosts](https://code.visualstudio.com/api/advanced-topics/extension-host),
[webviews](https://code.visualstudio.com/api/extension-guides/webview),
[Workspace Trust](https://code.visualstudio.com/api/extension-guides/workspace-trust).
