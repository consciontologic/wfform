# 🌿 Gitflow, without the ceremony

**Describe the work → Copilot opens a PR → checks and auto-merge → you approve deployment.**
Use this one repository, with an isolated checkout for each task. Never create
a second GitHub repository for a feature.

Once [automation setup](CI_CD.md#one-time-automation-setup) is complete and the
workflows are on `main`, routine delivery follows tasks, checks and PRs for you.
The owner makes the final release decision in GitHub's `production` deployment
approval. Routine PRs need no configured human approval; checks and any native
GitHub/Copilot restrictions still apply.

## 1. Pick the right lane

| Work | Start from | Branch | PR goes into |
|---|---|---|---|
| ✨ New feature | `develop` | `feature/short-name` | `develop` |
| 🐛 Normal bug | `develop` | `bugfix/short-name` | `develop` |
| 🚑 Urgent production fix | `main` | `hotfix/short-name` | `main`, then back to `develop` |
| 📦 Release | `develop` | `release/1.0.0` | `main`, then back to `develop` |

`main` holds production source; `develop` integrates accepted work. Codex and
Claude use `codex/feature/...` or `claude/bugfix/...` when their client requires
an agent prefix. GitHub Copilot cloud owns `copilot/*` branches; use the right
PR base and work-kind label instead of renaming its branch. For releases, first
publish `release/1.0.0` from `develop`: Copilot prepares a PR into that release
branch, then a separate promotion PR takes `release/1.0.0` into `main`.

Preview an isolated worktree, then create it:

```bash
python3 xops/agent/gitflow.py feature clearer-tools --agent codex
python3 xops/agent/gitflow.py feature clearer-tools --agent codex --apply
```

The helper fetches `origin`, requires the real base branch, and keeps the current
checkout's unsaved changes in place. It never copies private config, resets
changes, commits or pushes. It stops if `develop` has not been created yet.
Reuse a suitable active worktree when one already exists. For this initial
migration, the pre-existing staged work stays together on a release work branch;
do not rewrite that history or pretend it was already reviewed in separate PRs.

## 2. Give Copilot one concrete task

Copilot is the preferred PR author. Describe the change, acceptance tests,
allowed files and target branch. It handles implementation, tests, fixes and
the PR description. Use a separate review pass before merging.

1. Enable Copilot cloud agent for your account and repository.
2. Choose the lowest-cost supported model shown for your account.
3. Start a task from GitHub's **Agents** tab, or assign an issue to Copilot.
4. Select `develop` for features/bugs, `main` for hotfixes.
5. For release preparation, select the already-published `release/1.0.0` branch.
   Routine delivery opens its promotion PR into `main` after preparation is
   merged and later opens the back-merge PR. The API uses one `base_ref` for both
   the agent branch and its PR; a prompt does not override that routing.

For the unattended route, write a GitHub issue with the change, tests and allowed
scope, then apply **one** label: `ai:feature`, `ai:bugfix`, `ai:hotfix` or
`ai:release`. For example, “Explain a failed MCP connection” with `ai:bugfix`
delegates a bugfix against `develop`. A release issue uses the title
**`Release 1.0.0`** and label `ai:release`. Only a repository writer may authorize
this task; issue text from a stranger is not authorization.

You can also use **Actions → 🤖 Routine delivery → Run workflow** on `main`:
choose `delegate`, the issue number, work kind and release version when needed.
The controller allows one initial task and at most **one managed CI repair**
per issue, using the same explicit model. A repair starts only after the first
task finishes and CI fails on its current PR head; it continues the same branch.
The controller records receipts and never repeats an uncertain submission.
After that budget is used, a failure needs
inspection rather than another automatic purchase. Read the issue/task links
and workflow summary before requesting a follow-up.

The repository's [model policy](../../.github/copilot-model-policy.json) selects
**GPT-5.3-Codex** explicitly. On 2026-10-09 it had the lowest published rates
among active models listed by the [REST task API](https://docs.github.com/en/rest/agent-tasks/agent-tasks):
$1.75 input, $0.175 cached input and $14 output per million tokens. Check the
[current pricing](https://docs.github.com/en/copilot/reference/copilot-billing/models-and-pricing)
before changing the policy; total cost depends on task usage. No Auto or
automatic pricier fallback is allowed. UI availability and API support can differ.

For a repeatable API handoff, put the task in a local text file and preview:

```bash
python3 xops/agent/copilot_task.py feature \
  --prompt-file .local/my-task.md --model gpt-5.3-codex
```

For release preparation add `--release-version 1.0.0`; the helper requires the
explicit version and targets `release/1.0.0`, never `develop` by accident.

Adding `--submit` sends it once, after a Copilot capability check, using
`WFFORM_GITHUB_TOKEN` from your process environment. It never stores the token.
The task helper does not commit local files or upload staged changes: first
publish validated source through `make git` on a Gitflow work branch.
Inspect GitHub before retrying an uncertain submission.

**Live verification (2026-10-09):** an explicit `gpt-5.3-codex` read-only task
[completed successfully](https://github.com/consciontologic/wfform/tasks/72913e53-5a2c-46f9-9239-24744f015df9).
Its session reports `sweagent-capi:gpt-5.3-codex` with no error. An earlier
`gpt-6-luna` request failed; that model is no longer allowed by the API policy.
The [verification report](../reports/release-100-verification.md#copilot-and-remaining-release-gates)
retains both results. For each new task, check actual session model and outcome;
a queued receipt alone does not establish execution or cost. Copilot billing
is separate from the free security and quality tools.

## 3. Review and merge

Every PR needs a clear change description, matching tests and a changelog entry.
**Web checks**, **Security checks**, **Linux package** and **Windows package**
are the required checks on `main` and `develop`. No direct push to
`main`/`develop`, no force push, no silent skip on failure.

**Policy configured on 2026-10-09:** `main`, `develop` and the initial
`release/1.0.0` branch require a PR, the four
named checks on up-to-date source and resolved conversations. Required human PR
approvals are **zero**. Force-push, deletion and protection bypass are forbidden.
This moves the user's release decision to one protected deployment approval.
The generated website repository is exempt from source PR rules so its
dedicated publisher can update it normally.

**Your one release decision:** open the waiting **📦 Packages and release** run,
inspect its version, source commit, changes and successful package checks, then
choose **Review deployments → production → Approve and deploy**. The configured
reviewer is **consciontologic**. The tag, public downloads and website remain
unpublished until that approval. You can approve even if you authored the PR
or dispatched the run; the environment intentionally allows this for the sole
maintainer. Agents never click approval or call its API.
The publisher also checks the run's actual human approval receipt; using
GitHub's administrator bypass without that receipt cannot publish a release.

Copilot itself cannot approve or merge its PR. The controller uses native
auto-merge only when GitHub allows it. It marks its own managed draft PR ready
only after the verified task finishes and all four checks pass; unrelated drafts
stay drafts. A remaining platform restriction or blocked check is reported
rather than bypassed. If GitHub still requires an
independent PR review in a particular case, a Copilot task requester cannot
supply that review; deployment approval does not override that platform rule.
The built-in Copilot review product chooses its own model; its existing settings
are preserved. Our submitted tasks use the explicit model policy. These are
separate from free CI reports. See [GitHub's review rules](https://docs.github.com/en/copilot/concepts/security-governance-and-network-settings/risks-and-mitigations).

Local coordinating agents append tracking, stage and inspect `make git.dry`,
then run `make git` on validated Gitflow work branches and open/update a PR.
The wrapper rejects `main`/`develop` and publishes only the explicit same-name
work branch, ignoring upstream push mappings. GitHub Copilot may publish its
assigned branch through its managed platform. Neither route bypasses required
review or checks.

If a commit succeeds but its push fails, inspect the captured failure and remote
state, then explicitly run `make git` again. On a clean tracked branch it checks
the live same-name destination, resumes only a safe publication and creates no
duplicate commit; an already-published commit is a no-op. Divergence, missing
ancestry or mismatched fetch/push destinations must be resolved first.

## 4. Release one version

Use **MAJOR.MINOR.PATCH**, such as `1.0.0`, consistently. No `v` prefix, date or
hash in release/tag names. Root `pubspec.yaml` is authoritative. Build IDs may
still be hashes internally for integrity/cache isolation; they are not releases
or public folders. Package filenames include product, SemVer and platform so
Linux and Windows downloads remain distinguishable.

1. Update the version and synchronize derived values with the release tool.
2. Curate the emoji changelog under that version and run the gates.
3. GitHub merges the release PR into `main` after required checks, conversations
   and native platform constraints are satisfied.
4. Routine delivery requests publication for that merged PR and exact source
   commit. CI validates it and builds/tests web, Linux and Windows artifacts.
5. **consciontologic** approves the waiting `production` deployment. One gated
   job creates the matching tag and GitHub Release, then deploys the same web
   build to `wfform.com`. It rechecks source identity before publication.
6. Routine delivery opens the back-merge PR into `develop`; its normal check
   and conversation requirements still apply.

Do not manually move a tag or replace a released download. If publication stops,
inspect the failed job, fix its cause and use the documented recovery flow. A
conflicting existing tag or asset is a failure, not something automation deletes.
Missing setup, absent reviews and failed checks are reported as remaining gates;
having the workflow files in a branch does not mean delivery is active.

Read [CI/CD](CI_CD.md) for exact commands, free reports and publication gates.
macOS and graphical installers are tracked separately; do not advertise them
as available because the version number reached 1.0.0.

Sources: [cloud agent API](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/cloud-agent/use-cloud-agent-via-the-api),
[GitHub's agent guardrails](https://docs.github.com/en/enterprise-cloud%40latest/copilot/concepts/security-governance-and-network-settings/risks-and-mitigations).
