# 🌿 Gitflow, without the ceremony

**Work on a branch → open a PR → pass checks → review → merge → release.**
Use this one repository, with an isolated checkout for each task. Never create
a second GitHub repository for a feature.

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
   After the preparation PR merges there, open the promotion PR from that branch
   into `main`, then plan its back-merge. The API uses one `base_ref` for both
   the agent branch and its PR; a prompt does not override that routing.

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
Use **Web checks**, **Security checks**, **Linux package** and **Windows package**
as required checks on `main` and `develop`, with strict/up-to-date checks
enabled. Keep one independent approving review and resolved conversations; no
direct push to `main`/`develop`, no force push, no silent skip on failure.

**Repository setup verified on 2026-10-09:** `develop` was created from the
existing `main`. Both branches require a PR, one approval and resolved
conversations; stale approvals are dismissed and force-push/deletion disabled.
Required contexts are now active on both branches with strict mode:
**Web checks**, **Security checks**, **Linux package**, **Windows package**.
Administrator bypass remains configured for human bootstrap/recovery; agents
must not use it. The person who requested a Copilot PR cannot supply its
required approving review; use another eligible reviewer. A PR author also
cannot approve their own PR. The generated website repository is exempt from PR
rules so its dedicated publisher can update it normally.

GitHub cloud Copilot cannot approve or merge its own PR. An eligible independent
reviewer approves, and a maintainer merges after checks pass; then CI performs deterministic packaging and
publication. This is a GitHub platform limit, not an extra permission loop
invented by wfform. The built-in Copilot review product chooses its own model;
it is not enabled automatically because that cannot honor the cheapest-model
requirement. Use the explicit low-cost review task plus the free CI reports.

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
3. Merge the release PR into `main` after review.
4. Publish a tag matching the version exactly on the reviewed main commit.
5. CI builds verified web/Linux/Windows artifacts and checksums, creates the
   GitHub Release. A separate job deploys the same approved web build to
   `wfform.com` only while its source is still the current `main`; older tags
   report the website step as skipped rather than rolling the site back.
6. Back-merge the release/hotfix into `develop` through a PR.

Read [CI/CD](CI_CD.md) for exact commands, free reports and publication gates.
macOS and graphical installers are tracked separately; do not advertise them
as available because the version number reached 1.0.0.

Sources: [cloud agent API](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/cloud-agent/use-cloud-agent-via-the-api),
[GitHub's agent guardrails](https://docs.github.com/en/enterprise-cloud%40latest/copilot/concepts/security-governance-and-network-settings/risks-and-mitigations).
