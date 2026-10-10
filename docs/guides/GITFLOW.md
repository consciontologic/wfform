# 🌿 Gitflow

**Work branch → PR → required checks → merge → explicit release dispatch → owner approval.**
[AGENTS.md](../../AGENTS.md) is authoritative. Routine delivery automation is removed;
labels/completed checks do not create tasks, merge PRs or start releases.

## 1. Pick the right lane

| Work | Base | Branch | PR target |
|---|---|---|---|
| Feature | `develop` | `feature/name` | `develop` |
| Bugfix | `develop` | `bugfix/name` | `develop` |
| Hotfix | `main` | `hotfix/name` | `main`, then back-merge to `develop` |
| Release preparation | `develop` | `release/MAJOR.MINOR.PATCH` | `develop`, then promotion to `main` |

Codex/Claude may prefix work kinds, e.g. `codex/bugfix/name`. Copilot uses its managed
`copilot/*` branch with the correct target/work label. Reuse a suitable checkout and
preserve dirty work. The helper previews by default:

```sh
python3 xops/agent/gitflow.py feature clearer-tools --agent codex
python3 xops/agent/gitflow.py feature clearer-tools --agent codex --apply
```

## 2. Give Copilot one concrete task

State allowed files, behavior, tests and PR target. Enable cloud-agent access and
select the explicit [.github/copilot-model-policy.json](../../.github/copilot-model-policy.json)
model: **MAI-Code-1.1-Flash**, with owner-authorized alternatives **Claude Haiku 4.5 →
Kimi K3 → GPT-5.4 mini → Gemini 3.8 Flash**. No Auto or unlisted fallback.
The task API takes one model/base per request; release preparation targets `develop`.

```sh
python3 xops/agent/copilot_task.py feature --prompt-file .local/my-task.md --model mai-code-1.1-flash
```

`--submit` performs a capability check and one submission using process-scoped
`WFFORM_GITHUB_TOKEN`; release preparation also needs `--release-version`.
The helper does not upload local changes. Inspect definitive model rejection before
considering the next permitted model; never retry an uncertain submission or switch
models after asynchronous failure. No scheduled controller purchases tasks/repairs.
Copilot billing is separate from free quality tools. See the
[official task API](https://docs.github.com/en/rest/agent-tasks/agent-tasks).

## 3. Review and merge

Local coordinating agents validate, append a completed pending tracking row, inspect
all staged changes, run **`make git.dry` then `make git`**, and open/update a PR.
Delegates return evidence without staging/publishing. Direct source commit/push is
not a substitute for the wrapper; `main`/`develop` change only through protected PRs.
Never force-push, rewrite published history or bypass checks/protection.

**Web checks, Security checks, Linux package and Windows package** run only for
PRs into `develop` and hotfix PRs into `main`. Other promotions into `main` preserve
the exact tree previously validated on develop; their quality jobs skip. The release
authorizer independently checks that evidence. Require resolved conversations and
zero configured human PR approvals, while respecting native GitHub/Copilot restrictions.
An author cannot approve their own PR; Copilot may impose independent-review rules.

## 4. Publish a release

1. Prepare plain `MAJOR.MINOR.PATCH` version/changelog changes in a PR to `develop`.
   Run `make version.sync`, `make verify` and the required native checks.
2. Promote the validated tree to `main` through a PR. A conflict resolution changing
   that tree needs fresh validation through `develop`.
3. Dispatch **Packages and release** on `main` with matching `version`, current full
   `release_sha` and merged `release_pr` number. Empty inputs build artifacts only.
4. **consciontologic** approves `production`. No agent may approve by API/UI or bypass
   this gate. CI validates the real approval receipt and source before publishing.
5. Verify tag, downloads, container and website/PWA, then back-merge main into develop
   through a suitable work branch and protected PR.

Never move a published tag or replace assets. Recovery uses failed-job reruns on the
original run after diagnosis; ambiguous results require inspection first.
[CI/CD](CI_CD.md) owns exact inputs, credentials and recovery. macOS/graphical installers
remain planned separately from portable companion packages.
