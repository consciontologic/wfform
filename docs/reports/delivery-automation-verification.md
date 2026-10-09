# 🤖 Routine delivery and human release approval

Date: 2026-10-09. Version: 1.0.0. Bootstrap branch:
`codex/feature/delivery-automation`, based on published preparation commit
`f7966bc9b0bef2dc8c631ab1ef200f730b8ec9e8`. The user explicitly chose the
production deployment approval model after confirming this is a solo-maintained
repository. This supersedes the earlier independent human PR review policy.

## Intended delivery

A trusted request starts one explicitly selected Copilot task. Its managed PR
must pass the actual web, security, Linux and Windows checks. Routine work uses
native PR merging, with current-head validation and protected-branch checks.
One additional CI repair is permitted for a managed request; an uncertain task
submission is recorded and never blindly repeated. Release preparation and
develop back-merges use work branches and PRs.

After promotion to main, the package workflow validates the exact merged source
against prior eligible PR evidence and builds both native packages without
repeating tests or security scans. Its combined publication job waits for
the owner's **Approve deployment** action. Before any publication it also reads
GitHub's approval audit for this run, source SHA and production environment.
Agents never submit this approval. A bypassed environment job without a genuine
human approval receipt cannot publish through the checked publisher.

Tags and released assets are immutable. Interrupted draft uploads can resume
using matching artifacts; conflicting content fails closed. The website retains
its current-main guard. A public package and an updated website are distinct
outcomes if website publication fails after package publication.

## Live GitHub configuration

Authenticated API writes and read-backs confirmed:

- Repository auto-merge enabled.
- `main` and `develop` retain the four named contexts from GitHub Actions app
  15368, up-to-date branches, resolved conversations and PR integration. Under
  the later CI policy, normal main promotions skip quality and must satisfy
  controller/publisher source-provenance validation. Release-target rules now
  retain PR, conversation and administrator protections without impossible
  check requirements; new release preparation targets `develop`. Human PR approval count is zero by the
  user's explicit choice. Administrator enforcement is enabled; force pushes
  and deletions are disabled.
- `automation` permits only the main branch and contains
  `WFFORM_AUTOMATION_TOKEN`. Secret existence is observable; its value and scopes
  cannot be read back from GitHub's secret store.
- `production` permits only main and requires the human account
  `consciontologic`. Self-review prevention is off deliberately so the sole owner
  can approve a manually initiated recovery run. Its deployment token is now an
  environment secret, and the repository-wide copy was removed after verifying
  the environment copy exists.
- The native environment administrator-bypass flag remains enabled; its setting
  is not exposed by the documented update API used here. The publisher's actual
  human-approval audit is an additional mandatory guard, not a claim that the
  checkbox was disabled.
- Four `ai:*` intake labels and four matching `work:*` labels exist.

Ignored JSON receipts under `.local/release-100/` record the configuration,
before-state, secret names only, and read-backs. No token value is committed.

## Verification status

`make verify` passed with 643 Flutter tests (four existing opt-in skips), both
analyzers, 176 formatted Dart files, eleven companion suites, five Node PWA
tests, version agreement and repository secret/configuration checks. Evidence:
`/tmp/agent-runs/delivery-full-verify--20261009T134924Z-384996.log`.

Independent review reproduced and corrected GitHub task database-ID handling,
automation-token event propagation, isolated back-merge branches, stale branch
synchronization and release check provenance. Unit tests use fake GitHub
responses; they do not prove a live approval, release or website deployment.
Final verification passed all 78 Python ops tests (27 delivery, 18 publication,
33 existing), the offline strict workflow security audit, shell syntax, JSON/YAML
parsing, diff hygiene and repository/version checks. A redacted Gitleaks scan of
the prospective 499-file source snapshot found no leaks. Evidence:
`/tmp/agent-runs/delivery-final-python--20261009T135336Z-392132.log`,
`/tmp/agent-runs/delivery-final-zizmor--20261009T135336Z-392133.log`, and
`/tmp/agent-runs/delivery-final-secrets--20261009T135356Z-392367.log`.
The protected-head synchronization regression was tested red then green; the
controller refuses to update a protected work branch directly. CodeGraph sync
and a live symbol query confirmed the new publication helper is indexed.

## Activation and 1.0.0 limits

The validated bootstrap was published through `make git` as commit
`1da3522f30ada7db4e74ef397e41c5f858968fab` in
[PR #4](https://github.com/consciontologic/wfform/pull/4), targeting the existing
`release/1.0.0` branch. The public web, security and package workflows started
automatically on this PR. Their eventual results must be checked against its
current head; starting CI does not establish a passing release.

The user's later CI instruction superseded that initial routing. PR #4 was
retargeted to `develop`; the still-running package run on its previous target
was cancelled. Security and web checks on head `43b307b` passed before this
change, but no Windows success was claimed. Revised workflows restrict quality
to develop PRs and hotfix-to-main PRs, reuse exact-tree evidence for promotions,
and cache pinned tooling/dependencies. Verification of this revision is separate
from the earlier 78-test evidence above.

The revised implementation passed all 93 Python ops tests, 24 deployment
contracts, 507 parsed routing cases and the workflow security audit. Full
`make verify` passed 648 Flutter tests (four existing opt-in skips), companion
suites, analyzers, PWA tests and repository/version checks. Evidence:
`/tmp/agent-runs/delivery-policy-final--20261009T142746Z-430355.log`,
`/tmp/agent-runs/ci-head-proof-contracts--20261009T142600Z-426245.log`, and
`/tmp/agent-runs/ci-policy-full-verify--20261009T142702Z-427148.log`.

Main-target PRs merge only through an immediate native merge with the expected
head SHA after revalidating source evidence; they never retain an armed
auto-merge that could accept a later untested head. Develop PRs retain native
auto-merge because their quality jobs always run. Read-only CI checks out the
exact PR head, allowing source-tree comparisons independent of mutable PR base
metadata. The publisher independently rechecks the final merged source.

Default-branch workflows become active only after the bootstrap changes reach
main through passing PR checks. Durable credentials must have the documented
scopes. Native Copilot workflow auto-run is a separate repository setting; the
owner was given its exact location after secrets were isolated.

The earlier Windows retry at head `4391ae94be5c46e7bc3b45613aecd9f8ceb1ab6f`
still failed to launch the test program. A second explicitly selected
GPT-5.3-Codex task completed and produced head
`01eb553aa8fb57a59547b1faba2e6ae66035a230`; its CI initially required GitHub
workflow approval. Neither that task's completion nor this automation change
constitutes successful native Windows execution or a published 1.0.0 release.
Read-only review of that exact head also found two Dart compile errors in its
new diagnostic code: `ProcessException.osError` is not a getter (`errorCode` is
the supported property), and a local `pass()` function is called before its
declaration. The bootstrap carries a corrected, locally reviewed implementation
of the narrow Windows launch fix. Only the trusted inert helper inherits its
parent runtime environment; configured programs keep their explicit environment
and run without a shell. Regression coverage checks source-runtime selection,
actual child environment isolation and literal argument forwarding. Native
Windows CI on this combined PR is still required; the old Copilot head is not
accepted as passing evidence.

The corrected three-file slice passed the pinned Dart 3.10.9 analyzer, all
eleven companion suites (22 PASS groups) and all 19 affected Flutter deployment
tests. A separate review found no remaining blockers. Evidence:
`/tmp/agent-runs/windows-companion-gate--20261009T140134Z-399449.log` and
`/tmp/agent-runs/windows-deploy-regression--20261009T140157Z-400685.log`.

## MAI selection and PR consolidation

The owner's requested `mai-code-1.1-flash` completed a read-only live task on
2026-10-09: [task 93a244f2-a853-4898-b485-08b2237e2a44](https://github.com/consciontologic/wfform/tasks/93a244f2-a853-4898-b485-08b2237e2a44).
Both task and session completed; the actual session model is
`sweagent-capi:mai-code-1.1-flash`, with no reported error. No PR was created.
This establishes live availability of the primary, not full autonomous delivery
or live compatibility of the fallback choices.

The ordered alternatives are Claude Haiku 4.5, Kimi K3, GPT-5.4 mini and
Gemini 3.8 Flash. REST accepts one model per task. The controller advances only
on a definitive HTTP 422 model-field validation rejection, never after an
uncertain submission or a started task. Candidate reservations are durable;
accepted tasks and their single allowed CI repair keep the same model. Generic
unavailability responses stop safely rather than infer that no work started.
The current task endpoint schema does not promise a `model` error field. Thus
the adapter's narrow rejection handling is covered by synthetic tests, not a
claim of proven server-side fallback support; unknown response shapes stop.

The model change passed all 100 Python operations tests, including ordered
selection, durable reservations, exhaustion, no replay after uncertainty,
selected-model identity and a same-model repair budget. Evidence:
`/tmp/agent-runs/copilot-fallback-final--20261009T144138Z-438734.log`.
Repository checks passed; Gitleaks found no leaks in the combined 36-commit
history or the prospective source snapshot. The full 648-test application gate
above remains applicable: companion/application code is unchanged by this merge.

The single replacement [PR #5](https://github.com/consciontologic/wfform/pull/5)
targets `develop` from `codex/feature/delivery-automation`. Consolidation commit
`7430d08d820d6c84d02a9a89b57096932daef3a2` was published through `make git`;
remote identity and ancestry of `f7966bc`, `b3ba414` and `01eb553` were verified.
Superseded PRs #1, #2 and #4 were closed without deleting their branches.
The latest feature branch preserves the original 1.0.0 preparation, all delivery
and CI revisions, and the seven additional Copilot commits through a merge.
The reviewed companion code remains unchanged: it includes the useful Windows
fix and corrects two compile errors from that historical branch. The old audit
is retained with a supersession note; its obsolete review/model policies are
not reinstated.

## Windows release gate investigation

The owner requested completion through main and release 1.0.0 on 2026-10-09.
The checkout was first fast-forwarded to `83d02a6`, preserving the intervening
`8a3f5c8` delivery-routing fix and the fail-closed Linux process-group change.
[Windows job 113905549228](https://github.com/consciontologic/wfform/actions/runs/37955507918/job/113905549228)
passed analysis, then failed the direct `startProgram` test with exit 71. Web,
security and Linux checks passed on that revision; Windows packaging did not run.

Exit 71 is the helper's catch-all code. The pinned Dart Windows runtime creates
an overlapped pipe for a spawned process's stdin, while synchronous
`stdin.readByteSync` uses `ReadFile` without an OVERLAPPED structure. The helper
must consume its launch gate asynchronously and preserve all bytes following
that gate for the approved child. Its job assignment must still precede launch;
configured children must retain explicit environments and shell-free arguments.
Independent review also reproduced an inherited-pipe descendant delaying helper
exit, so the relay must bound its post-exit drain and release the owning job.
Regression coverage includes fragmented UTF-8 gates, queued MCP requests,
interactive binary transfer, open parent stdin and private-error redaction.

The full local gate passed 648 Flutter tests (four existing opt-in skips),
formatting, analysis, repository checks, companion tests and five PWA tests:
`/tmp/agent-runs/windows-release-full-verify--20261009T160910Z-492185.log`.
All 103 Python operation tests passed separately. The final affected gate passed
all 11 companion suites and fatal-info analysis after the lifecycle correction:
`/tmp/agent-runs/windows-stream-companion-final--20261009T161429Z-500620.log`.
The regression includes 256 KiB of unread input held by a descendant; a bounded
post-exit drain reports incomplete output instead of hanging or claiming success.
Independent security review approved the final source. Native Windows CI remains
the acceptance gate before merging this correction.

## References

- [GitHub task API and credential requirements](https://docs.github.com/en/rest/agent-tasks/agent-tasks)
- [Native Copilot workflow settings](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/cloud-agent/configuring-agent-settings)
- [Workflow review audit](https://docs.github.com/en/rest/actions/workflow-runs#get-the-review-history-for-a-workflow-run)
- [Environment restrictions](https://docs.github.com/en/rest/deployments/environments)
- [Routine setup and recovery](../guides/CI_CD.md)
