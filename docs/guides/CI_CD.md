# Web CI/CD and wfform.com

Verified against official GitHub documentation on **2026-10-07**. The source
repository is `consciontologic/wfform`; the static website repository is
[`consciontologic/wfform.com`](https://github.com/consciontologic/wfform.com). The destination
is dedicated to compiled web assets; Flutter sources stay in the source repository.
The 2026-10-07 account migration uses a fresh source history and the existing
`WFFORM_DEPLOY_TOKEN` repository secret in the new source repository. The first
real run and destination publication succeeded; see the
[migration verification](../reports/account-migration-verification.md).

## What runs automatically

[`web.yml`](../../.github/workflows/web.yml) checks pull requests, pushes to
`main`, and manual runs. It installs **Flutter 3.38.5**, resolves the checked-in
lockfile, runs formatting/analyzer/unit/widget/repository checks, repository
operation tests and real Chrome IndexedDB tests, then builds and validates a
public release. Live OpenRouter inference is not part of CI.

Only successful runs for the latest source `main` commit publish. They copy
validated static files into the destination repository's **`main` branch, root
directory**, create a deployment commit identifying the source repository and
SHA, and push normally. Unchanged artifacts create no commit. Pull requests
receive no deployment credential. Main runs are serialized; stale runs check
the latest source SHA again before committing. A competing destination edit
causes a normal rejected push, with no force push or automatic retry.

Editing files on your computer does not trigger GitHub Actions until you push
the source change. This repository's usual human command remains `make git`.
The remote workflow's deployment commits are intentional; agents still do not
commit or push the local source checkout.

## One required credential

Create a **fine-grained personal access token** owned by `consciontologic`:

| Setting | Value |
|---|---|
| Resource owner | `consciontologic` |
| Repository access | Only `wfform.com` |
| Repository permission | **Contents: Read and write** |
| Metadata | Read access, automatically included |
| Secret name | **`WFFORM_DEPLOY_TOKEN`** |

Add the token in the **source** `consciontologic/wfform` repository under **Settings →
Secrets and variables → Actions → Secrets → New repository secret**. Use a
secret, not a plain Actions variable. No additional custom environment variables
are required. The built-in `GITHUB_TOKEN` separately reads source metadata; it
does not grant cross-repository writes. Token expiration, organization approval
and destination branch rules must permit the requested push. Renew the same
secret if the token expires. See GitHub's
[token instructions](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens).

The workflow does not declare a GitHub Environment. If you prefer an
environment-scoped secret, add `environment: production` to the `web` job and
put `WFFORM_DEPLOY_TOKEN` in that environment instead. Any environment approval
policy then applies to that job.

An **OpenRouter key is not needed for CI** and is never published. Visitors
provide their own key in Settings. Local `config/local.json` is excluded by
`--public`; the publisher also refuses configuration directories and recognizable
credential-bearing output.

## Free GitHub Pages hosting

The public URL is **https://consciontologic.github.io/wfform.com/**. The user
does not own `wfform.com`; that name identifies the publication repository,
not a custom domain. No domain registration or DNS changes are needed.

1. In `consciontologic/wfform.com` **Settings → Pages**, select
   **Deploy from a branch**, branch **main**, folder **/(root)**.
2. Leave **Custom domain** empty and use HTTPS. The publisher must not create
   a `CNAME` file; GitHub supplies the `github.io` domain and certificate.
3. Push source changes to `consciontologic/wfform` main or manually dispatch
   **Web checks and publish**. The compiled files are committed to the website
   repository; its separate **pages build and deployment** run serves them.
4. Visit **https://consciontologic.github.io/wfform.com/** with the trailing
   slash. Verify the catalog, model chooser, Settings and offline shell.

`make build.public` and CI build with **`--base-href=/wfform.com/`**. Flutter
bootstrap, fonts, CanvasKit, manifest and service worker resolve under that
subpath. Local `make build`, `make serve` and Docker builds retain the `/` base.
Do not serve the public subpath build at an unrelated root URL.

The publisher writes `.nojekyll` so immutable `__releases/` assets are served.
During migration it retires an unchanged, previously owned `CNAME`; an unowned
or manually changed `CNAME` is a visible conflict. Prior immutable releases
remain available to old clients. See [Pages publishing settings](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site).

This uses a personal token because destination commits made using the built-in
`GITHUB_TOKEN` do not trigger branch-based Pages builds. The source workflow
publishes files; the destination's Pages deployment is a separate status check.

## Release ownership and updates

[`prepare_website.dart`](../../tool/prepare_website.dart) validates the format-2
release manifest, byte sizes and SHA-256 hashes for both root aliases and their
immutable counterparts. Only allowlisted release files, worker/manifest files,
`.nojekyll` and `.wfform-deployment.json` can be managed; a legacy owned `CNAME`
can be removed during migration. The latter
records owned paths and hashes and must stay in the destination repository.

Unrelated files, `.git`, documentation and existing history are preserved.
Conflicting unowned files or manual edits to managed files stop deployment with
the path named in the error. Resolve those changes deliberately; do not delete
the ownership manifest to bypass the check. Only formerly owned, obsolete root
aliases are deleted. All existing immutable release assets remain available for
old browser clients and safe PWA updates.

Retention grows the published directory and Git history. Monitor destination
size against [GitHub Pages limits](https://docs.github.com/en/pages/getting-started-with-github-pages/github-pages-limits).
No automatic retention cleanup is included because there is no reliable way
to know which old clients still need their release. A future planned retention
policy must update the ownership manifest and state its client support window.

GitHub Pages does not run the project's nginx configuration or custom response
headers. Use the [Docker deployment](DOCKER.md) when those nginx headers are
required. Both hosting choices serve static Flutter files directly; neither
proxies OpenRouter.

## Local checks without publishing

From the project root:

```bash
flutter pub get --enforce-lockfile
make verify
python3 -m unittest discover -s xops/makefile -p 'test_*.py' -v
dart run tool/build.dart --public --output=build/publish-web --base-href=/wfform.com/
dart run tool/prepare_website.dart build/publish-web work/website-preview
flutter test test/deploy/website_publication_test.dart test/deploy/website_workflow_test.dart --reporter expanded
bash -n deploy/scripts/publish-website.sh
```

The preparer only validates/copies files; it never calls Git. Its tests use
temporary files. Git orchestration tests use fake `git`, `gh` and `dart`
executables and do **not** make real commits or pushes. The publish shell script
is restricted to the GitHub main-branch workflow. Check its Actions run and
destination commit for actual remote publication evidence. Pages settings, DNS
and public serving are separate checks; passing local tests does not verify
those services.

Action versions are pinned to upstream commit SHAs in the workflow. The
[checkout](https://github.com/actions/checkout) and
[Flutter action](https://github.com/subosito/flutter-action) pins were resolved
from their official repositories on the date above. See GitHub's
[concurrency guidance](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency)
for serialized main runs and PR cancellation.
