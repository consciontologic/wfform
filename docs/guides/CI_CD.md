# 🚀 CI/CD, packages and wfform.com

The source is **consciontologic/wfform**. The generated website is
**consciontologic/wfform.com**, served at **https://wfform.com/**.
Development follows [Gitflow](GITFLOW.md). The workflows automate delivery after
the setup below. Their presence in a work branch, local checks and a queued task
do not prove that automation is active or that a remote release has published.

## What happens automatically

| Workflow | When | What it does |
|---|---|---|
| 🌐 [Web quality](../../.github/workflows/web.yml) | PRs into `develop`; hotfix PRs into `main` | Format, analyzer, tests, coverage, repository hygiene, real Chrome history storage and public build validation |
| 🛡️ [Free security and package reports](../../.github/workflows/security.yml) | The same eligible PRs, once per PR update | Gitleaks, OSV, license inventory, CycloneDX SBOM and zizmor |
| 📦 [Packages and release](../../.github/workflows/companion.yml) | The same eligible PRs | Test/build Linux and Windows; keep downloadable CI artifacts |
| 🤖 [Routine delivery](../../.github/workflows/delivery.yml) | Authorized issue labels, completed checks, hourly reconciliation, manual run | Submit bounded Copilot tasks, follow PR gates, open promotion/back-merge PRs and request approved releases |
| 📦 Packages and release | Publication requested on `main` for a merged PR and exact source commit | Validate source/version/checks, build verified downloads, then wait for the owner's `production` approval before tagging and publishing |

Quality, security and native tests run **only** on PRs into `develop`, plus
hotfix PRs directly into `main`. Other PR destinations and branch/tag pushes do
not run them. GitHub filters PR triggers by destination, so non-hotfix PRs into
`main` show skipped quality jobs without allocating their runners. Routine delivery
checks prior validation metadata before auto-merge; there is no separate promotion
PR workflow and no repeated analysis, tests or scans.

Release dispatches on `main` build and package already-validated source; they do
not repeat quality or security checks. An ordinary manual package run creates
artifacts only, and publication inputs are validated against the merged PR.
Flutter is pinned to **3.38.10**, lockfiles are enforced, and third-party Actions
are pinned to reviewed commit SHAs. There is no live OpenRouter inference in CI.
PRs receive no website deployment token. Job groups, emoji summaries and ANSI
colors make failures easier to find; full logs and machine-readable reports
remain available.

Native branch protection accepts skipped contexts. That alone does **not**
prove a promotion was tested: the delivery controller enforces prior exact-tree
validation before automatic merging, and the release authorizer independently
rejects untested source before publication. A maintainer manually merging an
untested PR into main cannot use that merge as release authorization.

## Cache policy

Cache the pinned Flutter SDK, downloaded Dart/pub dependencies and pinned scanner
binaries using the OS, tool version and relevant lockfile hashes. Every restored
scanner still passes its pinned checksum check. Cache hits avoid downloads; they
do not skip tests, dependency lock enforcement or fresh vulnerability results.
PR caches never supply release artifacts or credentials. Release jobs build new
artifacts from the approved source. Keep local configuration, tokens, reports
and compiled application outputs out of shared dependency caches.

## One version, three downloads

Root `pubspec.yaml` is authoritative: **MAJOR.MINOR.PATCH**, with no `v` prefix.
Release titles and tags are exactly `1.0.0`; package names include platform:

- `wfform-1.0.0-web.tar.gz`
- `wfformcomp-1.0.0-linux-x64.tar.gz`
- `wfformcomp-1.0.0-windows-x64.zip`

Archives have SHA-256 files and release metadata. Companion archives include
the executable, public web UI, setup instructions and the simple `TOOLS.md`
guide. macOS, graphical installers, signing and automatic upgrades remain
[planned](../planning/ROADMAP.md#phase-22--companion-platform-downloads-and-easy-installation).
A Linux test does not establish Windows runtime support; check the native
**Windows package** job and its extracted-executable tests before claiming it.

Prepare locally:

```bash
make version.sync
make verify
make release.package
```

`make version.check` catches inconsistent app, companion and website identities.
`make release.package` produces current-host artifacts under `build/companion/`
and `build/release/`. Native Windows instructions do not require Make; see
[wfformcomp](../wfformcomp.md#build-and-checks).

GitHub merges routine PRs when protection is satisfied; the owner approves the
final **production deployment** before the tag, release and website publish. Local
coordinating agents publish validated work branches through `make git.dry` then
`make git` and open PRs; direct `main`/`develop` writes are forbidden. Copilot's
managed PR authoring and reviewer eligibility are explained in [Gitflow](GITFLOW.md).

## Publication and recovery

Publication runs from trusted `main`, using a merged release/hotfix PR and its
exact source commit. The publisher validates the PR and its source tree against successful eligible
PR checks; Linux and Windows jobs build the artifacts without repeating tests
or security scans. The combined publication
job then waits for **consciontologic** to approve the `production` environment.
A dispatch input, PR comment or agent action cannot replace that approval.
The controller dispatches
publication explicitly; it does not rely on a tag created by `GITHUB_TOKEN`
triggering another workflow.

The dispatch targets **`main`** and supplies `version` (for example `1.0.0`),
`release_sha` (the exact current `main` commit) and `release_pr` (the merged
same-repository release or hotfix PR number). Copilot hotfix PRs can target
`main` directly; their task receipt/work-kind label identifies the hotfix, and
the merged root `pubspec.yaml` supplies its release version.
Tag pushes trigger no quality or package jobs and cannot publish a release or website.

Tags must match the root version and the validated source commit.
The single **Approve and publish release** job waits for Linux and Windows
packages and the human approval. It creates the tag and GitHub Release from that version's
emoji changelog and verified packages, then deploys the website. Use GitHub's
**Re-run failed jobs** on the **original dispatched run** after fixing a failure.
GitHub may require a new environment approval for the retry. Publication
resumes a draft using that run's exact artifacts; byte-identical existing assets
are reused. A different tag target or asset stops the run. Re-running every job
can rebuild archives with different bytes and correctly fail this check. It
never force-moves a tag or replaces a download to hide a conflict. Inspect the
run summary and release before retrying an uncertain result.

Only the **current `main` commit** can replace the website. The script checks
this before publication and again before committing. If `main` advances after
downloads publish but before website deployment, the site step reports
**skipped** to avoid rolling back a newer website. Prepare the next release from
the current main commit. A new publication request for an old commit is rejected.
The job summary records the actual status.

The website publisher commits only generated files to the dedicated website
repository and pushes normally. It never force-pushes. A competing destination
edit fails visibly. Publication to that repository and GitHub Pages deployment
are separate events: inspect both, then test the real installed PWA update path.

## Free security and quality reports

No paid scanner, dashboard or license token is required:

- 🕵️ **Gitleaks CLI** checks source history for secrets and uploads redacted SARIF.
- 📦 **OSV** checks locked public package names/versions for known vulnerabilities.
- 📋 A **CycloneDX SBOM**, dependency inventory and cached package license texts
  accompany the report. Missing license evidence is reported, not invented.
- 🌈 **zizmor** audits Actions configuration without GitHub Advanced Security.
- 🧪 Flutter/Dart analyze and test checks produce **LCOV coverage**.
- 🔄 **Dependabot** proposes weekly Dart and Actions updates into `develop`.

Run `make security.report` to create package reports under `build/reports/`.
The command contacts the public OSV API with dependency names and versions;
it never sends prompts, conversations or credentials. Vulnerabilities and scan
failures fail the job. Empty findings mean no known matches at scan time, not a
security guarantee. These open-source tools can run locally; GitHub-hosted
runner usage follows GitHub's account limits. Copilot billing is separate.

## One-time automation setup

Do this in the **source repository**, `consciontologic/wfform`. Use environment
secrets, not repository-wide secrets: **Settings → Environments**. Create
`automation` and `production`; for each select **Selected branches and tags**
and add exactly one **Branch** rule, `main`. Do not allow PR refs, work branches
or tags. Leave `automation` without a required reviewer. In `production`, add
**consciontologic** under **Required reviewers**, disable administrator bypass,
and leave **Prevent self-review** off. This intentionally lets the sole owner
approve a run they dispatched; it does not let an agent approve it. This is the
one human release gate. See [GitHub's environment
setup](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments).

The native administrator-bypass checkbox may still be available until it is
disabled in GitHub's UI. The publisher independently verifies this run's actual
approval by the configured human before release writes and again before website
deployment; a bypassed job without that receipt stops. Agents never submit an
approval or use the bypass.

| Where | Name | Value and minimum access |
|---|---|---|
| `automation` → Environment secrets | `WFFORM_AUTOMATION_TOKEN` | A dedicated, renewable fine-grained **user** token for only `consciontologic/wfform`: **Agent tasks: Read and write**, **Contents: Read and write**, **Pull requests: Read and write** |
| `automation` → Environment variables | `WFFORM_DELIVERY_APP_ID` | Optional delivery GitHub App's ID, installed only on `wfform` |
| `automation` → Environment secrets | `WFFORM_DELIVERY_APP_PRIVATE_KEY` | That App's private key; grant the App **Contents: Read and write**, **Pull requests: Read and write** |
| `production` → Environment secrets | `WFFORM_DEPLOY_TOKEN` | Website token for only `consciontologic/wfform.com`, **Contents: Read and write** |

The Copilot token belongs to an account with Copilot access and permission to
start tasks. Its owner is the task requester for GitHub's review rules. The
[Agent tasks API](https://docs.github.com/en/rest/agent-tasks/agent-tasks) accepts
user credentials; an App installation token and built-in `GITHUB_TOKEN` cannot
replace it. Set an expiration you can maintain and renew it in the environment.
Do not reuse the temporary testing token as the permanent automation credential.

The user token starts Copilot tasks, creates work branches and ordinary PRs,
updates unprotected work branches, and arms native auto-merge. Its pull-request permission lets their checks start without the extra
workflow approval associated with `GITHUB_TOKEN`-created PRs. The optional App
can author those PRs instead; it does not approve deployments or start paid
Copilot tasks. Without either credential, `GITHUB_TOKEN` is the fallback and
GitHub may require **Approve workflows to run**. The built-in token still
handles permitted source metadata and release assets.
See [GitHub's workflow trigger rules](https://docs.github.com/en/actions/concepts/security/github_token)
and [creating an App](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/registering-a-github-app).

Finish in this order:

1. Add the secrets above. Verify their **names and environment restrictions**;
   never print their values. Add `WFFORM_DEPLOY_TOKEN` to `production`, verify
   that environment's copy, then remove the old repository-level copy of the
   same secret **before enabling automatic workflow runs**. Leaving both copies
   makes the token available outside the protected environment. Keep the
   domain/Pages settings unchanged.
2. Enable **Settings → General → Pull Requests → Allow auto-merge**. On `main`
   and `develop`, require PRs, the four checks with strict updates and resolved
   conversations; set required human PR approvals to **0**. Apply the same gates
   to eligible integration/hotfix PRs. Quality jobs are skipped on normal main
   promotions; the delivery controller verifies prior successful develop evidence
   for the exact source tree before auto-merge, and publication verifies it again. Release preparation
   targets `develop`, never a release branch with no validation workflow.
   Keep force-push,
   deletion and protection bypass disabled. Final human approval is enforced
   by `production`, so PR authorship does not disqualify the owner from release
   approval.
   If using the built-in token to create PRs, also enable **Settings → Actions →
   General → Allow GitHub Actions to create and approve pull requests**. The
   workflow only creates PRs; it never submits an approval.
3. Once credentials are isolated and the trusted workflow is merged, open
   **Settings → Copilot → Cloud agent → Actions workflow approval** and turn off
   **Require approval for workflow runs**. This allows eligible routine Copilot checks;
   it does not waive any native platform constraint or deployment approval.
   Keep existing validation/review tools enabled.
   [GitHub documents this setting](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/cloud-agent/configuring-agent-settings).
4. On `main`, run **🤖 Routine delivery** with action `reconcile`, inspect its
   summary, then try one small labeled issue. Confirm the actual Copilot model,
   task result, PR checks and the waiting `production` approval before calling
   the setup operational. The release workflow must first reach `main` through
   a PR with successful checks.

Missing secrets, native platform requirements or checks remain visible gates.
The cost budget is one accepted initial Copilot task plus at most one managed CI
repair per issue, with the same selected model. The primary is MAI-Code-1.1-Flash;
[model policy](../../.github/copilot-model-policy.json) lists the owner's ordered
alternatives. Only a definitive HTTP 422 response containing exclusively
`model`/`invalid` validation errors advances to the next candidate. Each model is
reserved before POST and tried at most once. Uncertain, authentication,
rate-limit or asynchronous task failures never advance the chain. The task API
does not promise this model-specific error shape; the conditional adapter stays
inactive for opaque errors. The repair
requires a completed first task and failing CI on its current head, and continues
the existing branch.
The controller reserves and records each submission before proceeding; it never
repeats uncertain submissions or loops through paid repairs. Exhausted attempts
remain visible for inspection. It marks a managed draft ready only after the
verified task finishes and all four checks pass. Unmanaged drafts stay drafts;
new promotion/back-merge PRs are created ready. PR checks are read-only
and have no automation/website credential. No OpenRouter key is needed for CI;
visitors supply their own. Public builds exclude local configuration and reject
recognizable keys. See [GitHub's token instructions](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens).

## Custom domain on GitHub Pages

The public URL is **https://wfform.com/**. The user purchased this domain
through Namecheap and configured DNS on 2026-10-07, superseding the earlier
[free project URL deployment](../reports/github-pages-verification.md).
GitHub Pages provides the TLS certificate automatically; a paid certificate
from the registrar is unnecessary.

This configuration is live and verified on 2026-10-07. See the
[custom-domain report](../reports/custom-domain-verification.md) for successful
CI/Pages runs, HTTPS redirects and actual browser/catalog/cache evidence.

1. In `consciontologic/wfform.com` **Settings → Pages**, use
   **Deploy from a branch**, branch **main**, folder **/(root)**, and set
   **Custom domain** to `wfform.com`.
2. At the domain's DNS provider, configure these records (TTL Automatic is fine):

   | Type | Host | Value |
   |---|---|---|
   | A | `@` | `185.199.108.153` |
   | A | `@` | `185.199.109.153` |
   | A | `@` | `185.199.110.153` |
   | A | `@` | `185.199.111.153` |
   | CNAME | `www` | `consciontologic.github.io` |

   The CNAME DNS target has no protocol or repository path. Remove conflicting
   parking/redirect records for these hosts, preserving unrelated DNS records.
3. After GitHub provisions its certificate, select **Enforce HTTPS**. GitHub
   redirects `www` to the configured apex domain. DNS/certificate propagation
   can take up to 24 hours. See [GitHub's HTTPS guide](https://docs.github.com/en/pages/getting-started-with-github-pages/securing-your-github-pages-site-with-https).
4. After the release PR's protected merge into `main`, routine delivery requests
   publication of the matching plain SemVer version (for example `1.0.0`).
   Approve its waiting **production deployment**. **📦 Packages and release** publishes verified files
   after native Linux and Windows checks; the destination
   **pages build and deployment** run serves them.

`make build.public` and CI use **`--base-href=/`**. Flutter bootstrap, manifest,
service worker, fonts and CanvasKit resolve at the custom-domain root. Public
builds exclude local configuration; local/Docker builds retain their existing
configuration policy. The publisher writes `.nojekyll` and a managed `CNAME`
containing `wfform.com`. A matching file generated by GitHub can be adopted;
conflicting content is rejected. Version 1.0.0 publishes flat files. Previously cached clients have an explicit
update path; old physical `__releases` directories are retired.
See [Pages publishing settings](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site).

This uses a personal token because destination commits made using the built-in
`GITHUB_TOKEN` do not trigger branch-based Pages builds. The source workflow
publishes files; the destination's Pages deployment is a separate status check.

Moving to `wfform.com` changes the browser origin. Conversations and Settings
from the old GitHub URL or localhost do not transfer automatically; export and
import history. GitHub's old project URL redirects to the configured domain.

## Flat assets, ownership and old clients

[`prepare_website.dart`](../../tool/prepare_website.dart) validates format-3
release manifests, byte sizes and SHA-256 hashes. There is no published
`__releases`/`__Releases` directory. Files live at the website root and normal
asset paths; content hashes remain internal cache/integrity identities.

`.wfform-deployment.json` records exactly which files the publisher owns.
Unrelated files, `.git`, documentation and history are preserved. Conflicting
unowned files, symlinks or manual edits to managed files stop publication.
The migration removes only previously owned legacy assets and empty legacy
directories; it does not delete unrelated files to make a deployment pass.

Old assets already cached on a device can still be served during the update.
An uncached retired asset asks the client to update explicitly instead of mixing
old code with new files. The app saves drafts/history before applying updates.
See [PWA behavior](../pwa.md) for integrity, cache retention and update details.

## Check locally without publishing

```bash
make verify
python3 -m unittest discover -s xops/makefile -p 'test_*.py' -v
make build.public
dart run tool/prepare_website.dart build/publish-web .local/website-preview
make pwa.verify
bash -n deploy/scripts/publish-website.sh
```

The preparer does not call Git. Publication tests use fake executables and
never commit or push. Browser, native Windows, authenticated live inference and
remote release evidence must be reported separately from these local gates.
