# 🚀 CI/CD and publication

Source: **consciontologic/wfform**. Static destination: **consciontologic/wfform.com**,
served at **https://wfform.com/**. [Gitflow](GITFLOW.md) governs source changes.
Tasks, promotions and release dispatch are explicit; Routine delivery is removed.

## Checks and publication

| Workflow | Trigger and responsibility |
|---|---|
| [🌐 Web quality](../../.github/workflows/web.yml) | PR to develop or hotfix PR to main: format, analysis, tests, coverage, browser storage and public build |
| [🛡️ Security](../../.github/workflows/security.yml) | Same lanes: Gitleaks, OSV, licenses/SBOM and zizmor |
| [📦 Packages and release](../../.github/workflows/companion.yml) | Same lanes: native Linux/Windows tests and packages; explicit main dispatch: validate prior evidence, build, wait for human approval and publish |

Other PR destinations and ordinary/tag pushes run no quality/security pipelines.
Normal main promotions preserve the **exact tree validated on develop**. Skipped
native check contexts alone are not proof; publication revalidates prior PR evidence.
Release dispatch builds already-validated source without repeating quality/security.
Third-party Actions and Flutter **3.38.10** are pinned; enforce lockfiles. CI sends no
live OpenRouter inference and exposes no website token to PR jobs.

Cache SDKs, Dart dependencies and scanner tools by OS/version/lockfile. Verify scanner
checksums on restore. Never cache credentials, reports or compiled release artifacts;
cache hits do not skip tests or fresh vulnerability results. Container builds use the
bundled Docker driver and pinned base, with no shared exported web/image layer cache.

## Packages and container registry

Root `pubspec.yaml` owns plain SemVer. Example names:
`wfform-1.0.0-web.tar.gz`, `wfformcomp-1.0.0-linux-x64.tar.gz`,
`wfformcomp-1.0.0-windows-x64.zip`. Include SHA-256 files and release metadata.
Companion archives contain executable, public web UI, setup/tools guides and empty
configuration. [Graphical installers/macOS](../planning/ROADMAP.md#phase-22--companion-platform-downloads-and-easy-installation)
remain planned. Windows runtime evidence comes from Windows, not Linux compilation.

Future approved releases also publish a Linux amd64 static image:
`ghcr.io/consciontologic/wfform:<version>`, with no `latest` alias. The same run saves
and verifies its image, then publishes only after production approval. Existing
version identity must match; conflicting images/tags/assets fail rather than overwrite.
Publisher-only `GITHUB_TOKEN` has `packages: write`; no extra registry secret.
The existing 1.0.0 release has no GHCR image. Set the package Public after first
publication for anonymous pulls; see [Docker](DOCKER.md#use-a-published-ghcr-image).
[GHCR storage/bandwidth is currently free](https://docs.github.com/en/billing/concepts/product-billing/github-packages);
Actions/cache/artifact limits are separate.

## Publication and recovery

Finalize the numbered changelog heading as `## [MAJOR.MINOR.PATCH] - YYYY-MM-DD`
in the release preparation PR. The authorizer rejects missing, invalid or
`Unreleased` dates; it never rewrites the validated source during publication.

Dispatch **Actions → Packages and release → Run workflow** on `main`:

| Input | Required publication value |
|---|---|
| `version` | Plain SemVer matching root pubspec |
| `release_sha` | Full 40-character current-main SHA |
| `release_pr` | Merged same-repository promotion/hotfix PR number |

All empty means artifacts only; partially filled inputs fail. Copilot hotfixes use
`work:hotfix`. A tag push, PR comment or dispatch input cannot replace approval.

The **Approve and publish release** job waits for both native packages and
**consciontologic**'s `production` approval. It checks actual human receipt/current
source, creates the immutable tag/release, publishes the image and deploys that same
public web build. Agents cannot approve or use administrator bypass.

After failure, inspect the run/release, fix the cause and use **Re-run failed jobs on
the original dispatched run**. GitHub may request approval again. Resume its draft
using exact original artifacts; byte-identical assets can be reused, different bytes
or tag targets stop publication. Rebuilding every job may change archive bytes.
Inspect uncertain outcomes before retrying; never delete conflicting release data.

Only current main may replace the website. A main advance after downloads publish
can make the site step skip to avoid rollback; prepare a new release from current
main. The publisher pushes normally and preserves unrelated destination files.
Source publication and destination Pages deployment are separate statuses. Verify
both, public bytes and the **installed PWA update path** before declaring success.

## Free security and quality reports

Gitleaks detects secrets; OSV checks locked dependency vulnerabilities; license
inventory and CycloneDX SBOM record package evidence; zizmor audits workflows;
Flutter produces LCOV. Dependabot proposes updates into `develop`. No paid scanner
or license token is required. `make security.report` writes `build/reports/` and
sends only dependency names/versions to OSV. Failures/vulnerabilities fail the job;
no known match is not a security guarantee. Copilot costs are separate.

## One-time release setup

- `production`: selected **Branch `main` only**, required reviewer
  **consciontologic**, administrator bypass disabled, Prevent self-review off so the
  sole owner can approve their own dispatch. Publisher verifies the actual receipt.
- Environment secret **`WFFORM_DEPLOY_TOKEN`**: token scoped only to
  `consciontologic/wfform.com`, **Contents: Read and write**. Verify its name/restriction
  without printing it; remove repository duplicates after confirming the copy.
- `main`/`develop`: protected PRs, four strict checks, resolved conversations, **0**
  configured human approvals, no force push/deletion/bypass. Honor native restrictions.
- Old automation-environment credentials are no longer needed by these workflows;
  retire only after checking other integrations. Manual Copilot uses process-scoped
  credentials and the explicit model policy; never save temporary chat tokens.

See [GitHub environments](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments).

## Custom domain and destination ownership

Configure destination Pages: **Deploy from a branch → main → /(root)**, custom domain
`wfform.com`, Enforce HTTPS after GitHub provisions its certificate. DNS:

| Type | Host | Value |
|---|---|---|
| A | `@` | `185.199.108.153`, `185.199.109.153`, `185.199.110.153`, `185.199.111.153` (four records) |
| CNAME | `www` | `consciontologic.github.io` |

Preserve unrelated DNS records. Public builds use `--base-href=/`; publisher manages
matching `CNAME` and `.nojekyll`. Destination commits use its scoped token because
built-in `GITHUB_TOKEN` commits do not trigger branch-based Pages builds.

`prepare_website.dart` verifies format-3 manifests, sizes and SHA-256 before writing.
`.wfform-deployment.json` records managed files. Reject conflicting unowned files,
symlinks/manual managed edits; preserve unrelated files. Remove only owned legacy
release paths. Public files are flat; internal hashes remain cache identities.
Cross-origin moves require history export/import; redirects cannot transfer storage.

## Check locally without publishing

```sh
make verify
python3 -m unittest discover -s xops/makefile -p 'test_*.py' -v
make build.public
dart run tool/prepare_website.dart build/publish-web .local/website-preview
make pwa.verify
bash -n deploy/scripts/publish-website.sh
```

Local checks do not establish remote publication, native Windows execution or live
provider compatibility. Do not change existing tags/assets to manufacture success.
