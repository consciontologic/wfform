# 🚀 CI/CD, packages and wfform.com

The source is **consciontologic/wfform**. The generated website is
**consciontologic/wfform.com**, served at **https://wfform.com/**.
Development follows [Gitflow](GITFLOW.md). This guide describes the **1.0.0
workflow prepared on 2026-10-09**; local checks do not prove a remote release.

## What happens automatically

| Workflow | When | What it does |
|---|---|---|
| 🌐 [Web quality](../../.github/workflows/web.yml) | PRs, branch pushes, manual run | Format, analyzer, tests, coverage, repository hygiene, real Chrome history storage and public build validation |
| 🛡️ [Free security and package reports](../../.github/workflows/security.yml) | PRs, main/develop, weekly, manual and release checks | Gitleaks, OSV, license inventory, CycloneDX SBOM and zizmor |
| 📦 [Packages and release](../../.github/workflows/companion.yml) | PRs, branch pushes, manual run | Test/build Linux and Windows; keep downloadable CI artifacts |
| 📦 Packages and release | Plain SemVer tag, such as `1.0.0` | After security and both native jobs pass, create the GitHub Release, then publish the verified website |

PRs and ordinary branch pushes **do not publish**. Manual runs build/check only.
Flutter is pinned to **3.38.10**, lockfiles are enforced, and third-party Actions
are pinned to reviewed commit SHAs. There is no live OpenRouter inference in CI.
PRs receive no website deployment token. Job groups, emoji summaries and ANSI
colors make failures easier to find; full logs and machine-readable reports
remain available.

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

A maintainer merges the release PR, publishes its matching tag, and back-merges
into `develop`. Local coordinating agents publish validated work branches through
`make git.dry` then `make git` and open PRs; direct `main`/`develop` writes are
forbidden. Tag publication follows the reviewed merge. Copilot's managed PR
authoring is described in [Gitflow](GITFLOW.md).

## Publication and recovery

Tags must match the root version and point to a commit contained in `main`.
**Publish release** waits for security, Linux and Windows. It creates the
GitHub Release from that version's emoji changelog and verified packages.
**Publish website** is a separate dependent job: use GitHub's **Re-run failed
jobs** to recover a website failure without trying to recreate the release.
Do not rerun every successful publication job blindly; inspect existing releases
and their assets first.

Only the **current `main` commit** can replace the website. The script checks
this before publication and again before committing. An older tag can publish
its downloads, but the site step explicitly reports **skipped** to avoid rolling
back a newer website. If `main` advances before deployment, prepare the next
release from the current main commit. The job summary records the actual status.

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

## One website credential

Keep **`WFFORM_DEPLOY_TOKEN`** as an Actions secret in the source repository.
Use a fine-grained token with access to **only `consciontologic/wfform.com`** and
**Contents: Read and write**. The built-in `GITHUB_TOKEN` handles source release
assets; it cannot write across repositories. Never put the website token in an
Actions variable, public build, local committed config or release archive.

The existing domain/Pages setup and token are preserved. Renew the secret if it
expires. No OpenRouter key is needed for CI; visitors supply their own key.
Public builds exclude `config/local.json` and reject recognizable key patterns.
See [GitHub's token instructions](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens).

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
4. Merge the reviewed release into `main`, then publish its plain SemVer tag
   (for example `1.0.0`). **📦 Packages and release** publishes verified files
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
