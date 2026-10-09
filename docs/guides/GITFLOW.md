# 🌿 Gitflow, without the ceremony

**Assign a task → review and merge its PR → dispatch a release → approve deployment.**
Use this one repository, with an isolated checkout for each task. Never create
a second GitHub repository for a feature.

The **Routine delivery** workflow has been removed. Maintainers or explicitly
authorized agents assign Copilot tasks, follow checks, merge eligible PRs and
open promotion/back-merge PRs. Labels and completed checks do not start those
actions. The owner makes the final release decision in GitHub's `production`
deployment approval. Routine PRs need no configured human approval; required
checks and any native GitHub/Copilot restrictions still apply.

## 1. Pick the right lane

| Work | Start from | Branch | PR goes into |
|---|---|---|---|
| ✨ New feature | `develop` | `feature/short-name` | `develop` |
| 🐛 Normal bug | `develop` | `bugfix/short-name` | `develop` |
| 🚑 Urgent production fix | `main` | `hotfix/short-name` | `main`, then back to `develop` |
| 📦 Release preparation | `develop` | `release/1.0.0` | `develop`, then promote validated `develop` to `main` |

`main` holds production source; `develop` integrates accepted work. Codex and
Claude use `codex/feature/...` or `claude/bugfix/...` when their client requires
an agent prefix. GitHub Copilot cloud owns `copilot/*` branches; use the right
PR base and work-kind label instead of renaming its branch. For releases, first
prepare version/changelog changes in a PR into `develop`. A separate promotion
PR takes the validated `develop` tree into `main`. Release branches may still be
used as work branches, but their preparation PR targets `develop`.

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
2. Select MAI-Code-1.1-Flash under the explicit model policy below.
3. Start a task from GitHub's **Agents** tab, or assign an issue to Copilot.
4. Select `develop` for features/bugs, `main` for hotfixes.
5. For release preparation, select `develop` and state the exact release version.
   After that PR passes and merges, open a separate promotion from `develop`
   into `main`. Open the back-merge PR after publication. The task API uses one
   `base_ref` for both the agent branch and its PR; a prompt does not override
   that routing.

The repository's [model policy](../../.github/copilot-model-policy.json) selects
**MAI-Code-1.1-Flash**. The owner's ordered alternatives are **Claude Haiku 4.5 →
Kimi K3 → GPT-5.4 mini → Gemini 3.8 Flash**. GitHub's
[task API](https://docs.github.com/en/rest/agent-tasks/agent-tasks) accepts one
model per request. Select the model explicitly for each manual task; Auto and
models outside this list are prohibited. Availability and usage costs can change.
Fallback models are configured alternatives, not separately live-tested claims.
Inspect a model rejection before considering the next permitted model. A timeout,
uncertain submission or asynchronous task failure is not permission to submit
the task again or switch models. There is no scheduled task or repair controller.

For a repeatable API handoff, put the task in a local text file and preview:

```bash
python3 xops/agent/copilot_task.py feature \
  --prompt-file .local/my-task.md --model mai-code-1.1-flash
```

For release preparation add `--release-version 1.0.0`; the helper requires the
explicit version and targets `develop`, where the requested quality checks run.

Adding `--submit` sends it once, after a Copilot capability check, using
`WFFORM_GITHUB_TOKEN` from your process environment. It never stores the token.
The task helper does not commit local files or upload staged changes: first
publish validated source through `make git` on a Gitflow work branch.
Inspect GitHub before retrying an uncertain submission.

**Live verification (2026-10-09):** an explicit `mai-code-1.1-flash` read-only
[task completed successfully](https://github.com/consciontologic/wfform/tasks/93a244f2-a853-4898-b485-08b2237e2a44).
Its session reports `sweagent-capi:mai-code-1.1-flash` with no error. It changed
no files and created no PR. Earlier GPT-5.3-Codex success and GPT-6 Luna failure
remain historical evidence in the [release report](../reports/release-100-verification.md#copilot-and-remaining-release-gates).
For every task, check its actual model and outcome; a queued receipt alone does
not establish execution or cost. Copilot billing is separate from the free
security and quality tools.

## 3. Review and merge

Every PR needs a clear change description, matching tests and a changelog entry.
**Web checks**, **Security checks**, **Linux package** and **Windows package**
run only on PRs into `develop` and hotfix PRs into `main`. Promotions to `main`
reuse successful develop validation for the exact same Git tree. Their quality
jobs are skipped. Before merging, compare the promotion tree with its successful
develop validation; the release authorizer independently checks this evidence
before publication. There is no separate promotion PR workflow. No direct push to
`main`/`develop`, no force push, no silent skip on failure.

**Policy:** `develop` requires the four successful checks on current source.
`main` retains their contexts, skipped for normal promotions. The publisher
enforces prior exact-tree validation; skipped
contexts alone do not prove the promoted source was tested. Hotfixes must pass
all four real quality jobs. Both branches require PRs and resolved conversations;
no untested merge-conflict resolution may be promoted. Required human PR
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

Copilot itself cannot approve or merge its PR. A maintainer or explicitly
authorized coordinating agent follows required checks, marks a completed draft
ready and merges through normal branch protection. Native auto-merge may be
selected explicitly where GitHub allows it; no controller enables it for you.
A remaining platform restriction or blocked check must be resolved rather than
bypassed. If GitHub requires an independent PR review in a particular case, a
Copilot task requester cannot supply it; deployment approval does not override
that platform rule.
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
3. Merge release preparation into `develop` after quality checks. Open and merge
   a promotion PR into `main` containing that exact tested tree. A merge
   resolution that changes the tree needs new validation through `develop`.
4. Open **Actions → 📦 Packages and release → Run workflow**. Select `main` and
   supply `version`, `release_sha` (the exact current main SHA) and `release_pr`
   (the merged promotion or hotfix PR number). CI verifies prior PR evidence and
   builds web, Linux, Windows and the Linux container without repeating quality
   checks. See [publication inputs](CI_CD.md#publication-and-recovery).
5. **consciontologic** approves the waiting `production` deployment. One gated
   job creates the matching tag and GitHub Release, publishes the container and
   deploys the same web build to `wfform.com`. It rechecks source identity before
   publication.
6. Open a back-merge PR from a suitable work branch based on `main` into `develop`;
   its normal checks and conversation requirements still apply.

Do not manually move a tag or replace a released download. If publication stops,
inspect the failed job, fix its cause and use the documented recovery flow. A
conflicting existing tag or asset is a failure, not something automation deletes.
Missing setup, absent reviews and failed checks are reported as remaining gates;
having workflow files in a branch does not prove a release has published.

Read [CI/CD](CI_CD.md) for exact commands, free reports and publication gates.
macOS and graphical installers are tracked separately; do not advertise them
as available because the version number reached 1.0.0.

Sources: [cloud agent API](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/cloud-agent/use-cloud-agent-via-the-api),
[GitHub's agent guardrails](https://docs.github.com/en/enterprise-cloud%40latest/copilot/concepts/security-governance-and-network-settings/risks-and-mitigations).
