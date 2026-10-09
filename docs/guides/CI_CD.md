# 🚀 CI/CD, packages and wfform.com

The source is **consciontologic/wfform**. The generated website is
**consciontologic/wfform.com**, served at **https://wfform.com/**.
Development follows [Gitflow](GITFLOW.md). PR checks run automatically in the
lanes below. Task assignment, PR promotion and release dispatch are explicit
maintainer actions; the Routine delivery workflow has been removed. A workflow
configuration or local build does not prove a remote release has published.

## Checks and publication

| Workflow | When | What it does |
|---|---|---|
| 🌐 [Web quality](../../.github/workflows/web.yml) | PRs into `develop`; hotfix PRs into `main` | Format, analyzer, tests, coverage, repository hygiene, real Chrome history storage and public build validation |
| 🛡️ [Free security and package reports](../../.github/workflows/security.yml) | The same eligible PRs, once per PR update | Gitleaks, OSV, license inventory, CycloneDX SBOM and zizmor |
| 📦 [Packages and release](../../.github/workflows/companion.yml) | The same eligible PRs | Test/build Linux and Windows; keep downloadable CI artifacts |
| 📦 Packages and release | Explicit manual dispatch on `main` for a merged PR and exact source commit | Validate source/version/checks, build verified downloads and container, then wait for the owner's `production` approval before tagging and publishing |

Quality, security and native tests run **only** on PRs into `develop`, plus
hotfix PRs directly into `main`. Other PR destinations and branch/tag pushes do
not run them. GitHub filters PR triggers by destination, so non-hotfix PRs into
`main` show skipped quality jobs without allocating their runners. Maintainers
must promote the exact previously tested develop tree; there is no separate
promotion PR workflow and no repeated analysis, tests or scans.

Release dispatches on `main` build and package already-validated source; they do
not repeat quality or security checks. An ordinary manual package run creates
artifacts only, and publication inputs are validated against the merged PR.
Flutter is pinned to **3.38.10**, lockfiles are enforced, and third-party Actions
are pinned to reviewed commit SHAs. There is no live OpenRouter inference in CI.
PRs receive no website deployment token. Job groups, emoji summaries and ANSI
colors make failures easier to find; full logs and machine-readable reports
remain available.

Native branch protection accepts skipped contexts. That alone does **not**
prove a promotion was tested: the release authorizer verifies prior exact-tree
validation and rejects untested source before publication. A maintainer manually
merging an untested PR into main cannot use that merge as release authorization.

## Cache policy

Cache the pinned Flutter SDK, downloaded Dart/pub dependencies and pinned scanner
binaries using the OS, tool version and relevant lockfile hashes. Every restored
scanner still passes its pinned checksum check. Cache hits avoid downloads; they
do not skip tests, dependency lock enforcement or fresh vulnerability results.
PR caches never supply release artifacts or credentials. Release jobs build new
artifacts from the approved source. Keep local configuration, tokens, reports
and compiled application outputs out of shared dependency caches.

## Container registry

The same **Packages and release** run builds a Linux amd64 nginx image from its
verified public web assets. It publishes `ghcr.io/consciontologic/wfform:<version>`
only after the existing `production` approval; there is no separate push-triggered
container pipeline. Tags use plain SemVer only, with no `latest` alias. A different
image under an existing version is rejected rather than overwritten.

Flutter/pub dependencies and the Buildx tool binary are cached; each image is
assembled from the pinned base and freshly verified public assets. Compiled
web/image layers are not exported to a shared BuildKit cache. Credentials and
packaged releases remain outside dependency/tool caches. Publication uses the
job-scoped `GITHUB_TOKEN` with `packages: write`; no additional registry secret
is required. See the [Docker guide](DOCKER.md#use-a-published-ghcr-image) for usage
and the one-time Public package visibility setting. The configured workflow alone
does not establish that an image is already available. This applies to future
approved releases; existing `1.0.0` downloads are unchanged and have no GHCR image.

GitHub currently provides Container Registry storage and bandwidth free of charge;
Actions runners, caches and retained artifacts follow their separate account
limits. See [GitHub's billing documentation](https://docs.github.com/en/billing/concepts/product-billing/github-packages).

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

Maintainers or explicitly authorized agents merge PRs through branch protection;
the owner approves the final **production deployment** before the tag, release,
container and website publish. Local coordinating agents publish validated work branches through `make git.dry` then
`make git` and open PRs; direct `main`/`develop` writes are forbidden. Copilot's
managed PR authoring and reviewer eligibility are explained in [Gitflow](GITFLOW.md).

## Publication and recovery

Publication runs from trusted `main`, using a merged release/hotfix PR and its
exact source commit. The publisher validates the PR and its source tree against successful eligible
PR checks; Linux and Windows jobs build the artifacts without repeating tests
or security scans. The combined publication
job then waits for **consciontologic** to approve the `production` environment.
A dispatch input, PR comment or agent action cannot replace that approval.
A maintainer explicitly dispatches publication; labels, completed checks and
tag pushes do not start it.

Open **Actions → 📦 Packages and release → Run workflow**, select **`main`**,
and enter all three inputs:

| Input | Value |
|---|---|
| `version` | Plain SemVer matching root `pubspec.yaml`, for example `1.0.0` |
| `release_sha` | Full 40-character SHA of the exact current `main` commit |
| `release_pr` | Number of the merged same-repository promotion or hotfix PR |

Leaving all three inputs empty builds downloadable artifacts only; it cannot
publish. A partially filled publication request fails validation.

Copilot hotfix PRs can target `main` directly; the `work:hotfix` label identifies
the hotfix, and
the merged root `pubspec.yaml` supplies its release version.
Tag pushes trigger no quality or package jobs and cannot publish a release or website.

Tags must match the root version and the validated source commit.
The single **Approve and publish release** job waits for Linux and Windows
packages and the human approval. It creates the tag and GitHub Release from that version's
emoji changelog and verified packages, publishes the container, then deploys the
website. Use GitHub's **Re-run failed jobs** on the **original dispatched run** after fixing a failure.
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

## One-time release setup

In **consciontologic/wfform → Settings → Environments**, restrict `production`
to exactly one **Branch** rule, `main`, under **Selected branches and tags**.
Do not permit PR refs, work branches or tags. Add **consciontologic** as the
required reviewer, disable administrator bypass and leave **Prevent self-review**
off so the sole owner can approve a run they dispatched. This is the final human
release gate. See [GitHub's environment setup](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments).

The publisher checks the run's actual human approval receipt before publication;
a bypassed job without that receipt stops. Agents must not approve deployments
or bypass this gate.

| Where | Name | Value and minimum access |
|---|---|---|
| `production` → Environment secrets | `WFFORM_DEPLOY_TOKEN` | Website token for only `consciontologic/wfform.com`, **Contents: Read and write** |

Verify the secret's name and environment restriction without printing its value.
Remove a repository-level duplicate after confirming the environment copy.
The removed Routine delivery workflow no longer uses the `automation` environment,
`WFFORM_AUTOMATION_TOKEN`, `WFFORM_DELIVERY_APP_ID` or
`WFFORM_DELIVERY_APP_PRIVATE_KEY`. They are not required for checks or releases;
retire unused credentials after confirming no other integration depends on them.
Manual Copilot API tasks use a process-scoped user token with Agent tasks access,
as described in [Gitflow](GITFLOW.md#2-give-copilot-one-concrete-task). Do not store
a temporary chat token as a permanent credential. The explicit MAI model policy
still applies; no workflow starts paid tasks or repairs automatically.

On `main` and `develop`, require PRs, the four checks with strict updates and
resolved conversations, with **0** configured human PR approvals. Keep force
pushes, deletion and protection bypass disabled. Normal main promotions skip
quality jobs; preserve the exact tested develop tree. Publication verifies that
evidence independently. Release preparation targets `develop`.

After merging a reviewed change, dispatch **Packages and release** with the
[three publication inputs](#publication-and-recovery). Inspect the package results,
then approve the waiting production deployment. Verify the tag, downloads,
container and destination Pages run before reporting publication complete.
PR jobs receive no website credential. No OpenRouter key is needed for CI;
public builds exclude local configuration and reject recognizable keys.

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
4. After the release PR's protected merge into `main`, manually dispatch
   **Packages and release** for the matching plain SemVer version (for example
   `1.0.0`), merged PR and current main SHA.
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
