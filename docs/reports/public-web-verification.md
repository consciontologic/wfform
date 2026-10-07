# Public web metadata, publishing and logo verification

Date: **2026-10-07**. Workspace: `/home/serhatakbak/code/projects/wfform`. Flutter **3.38.5**, Dart **3.10.4**. This report covers the three requested additions; earlier reports retain their original verification scope. Existing staged files were preserved. No source or remote deployment commit/push was executed.

## Implemented

- Descriptive page/runtime titles, descriptions, canonical links, Open Graph/Twitter metadata, truthful WebSite/WebApplication JSON-LD, PWA categories and pubspec project metadata. A small static `about.html` explains current features without JavaScript; robots and sitemap list only public pages. See [SEO](../seo.md).
- One GitHub workflow for PR/main/manual checks and latest-main-only publication to `metaphy6/wfform.com`. Public builds exclude local credentials. The preparer validates manifests/hashes, manages only owned files, preserves unrelated files and prior immutable releases, and reports unchanged content as a no-op. Git orchestration makes a normal commit/push only in CI. See [CI/CD setup](../guides/CI_CD.md).
- A theme-aware bracketed conversation mark replaces the header arrow. Generated favicon/PWA icons use the same mark. Product text and existing PWA/storage identities remain stable.

## Executed checks

Run from the project root; raw logs are ignored under `outputs/public-web-*.txt` and the safe-run logs in `/tmp/agent-runs/`.

| Command/check | Result and scope |
|---|---|
| `make verify` | **345 tests passed**, one explicitly opt-in live test skipped; Dart formatting, Flutter analysis and repository checks passed against final source |
| `flutter test test/deploy/website_publication_test.dart test/deploy/website_workflow_test.dart --reporter expanded` | **17 tests passed**: real temporary-file publication/integrity tests plus fake Git/gh orchestration; no real commit/push |
| `CHROME_EXECUTABLE=/home/serhatakbak/.cache/ms-playwright/chromium-1243/chrome-linux64/chrome flutter test --platform chrome test/history/browser/indexeddb_checks.dart --reporter expanded` | **6 real Chrome IndexedDB tests passed** with disposable fixture databases |
| `python3 -m unittest discover -s xops/makefile -p 'test_*.py' -v` | **13 repository-operation tests passed** |
| `make build.public` | Release build passed: **37 assets, 18,163,872 bytes**; existing local config excluded |
| `dart run tool/prepare_website.dart build/publish-web work/website-preview` twice | Real compiled release: first preparation **80 files changed**; second **0 files changed**, no Git operations |
| Empty local bare Git repository experiment | Real clone, orphan `main`, preparer and staging of 80 owned files passed; staged index/worker bytes match the build. No commit/push |
| `bash -n deploy/scripts/publish-website.sh` and actionlint **1.7.12** | Passed; official actionlint release checksum verified; workflow action pins resolved against official upstream tags |
| `make image`, `TLS=1 make restart`, `make tls.check` | Passed nginx configuration, HTTP/HTTPS health/headers, no-store configuration and all 37 immutable asset hashes |
| HTTP SEO checks | `/`, `/about.html`, `/robots.txt`, `/sitemap.xml` and icon return 200 with appropriate MIME types; sitemap XML parses; unknown route returns 404 |
| `make codeg`, `make codeg.check` | Index refreshed; real MCP initialization/search/exploration/caller checks passed; ignored config/build/scratch files excluded |
| Impeccable detector on changed UI/HTML | No findings; no suppressions added |

Expected red tests preceded the public-build and metadata behavior. A formatting gate first requested one line wrap, then passed after formatting. A scratch source-style whitespace check on generated deployment output flagged upstream license/CanvasKit whitespace; these vendor bytes were preserved, and the Git experiment instead verified exact staged artifact bytes. The actual source `git diff --cached --check` remains part of staging verification. The release compiler still prints the prior optional CupertinoIcons-family warning, while compilation succeeds; no new runtime dependency was added.

Public release: `a21aadfbd6a27168f4b09828395d353361b40b6d2dd30292d5eb9961975cf68f`.
nginx release: `416c7de9d6ddb76915e44f1c6bbb60d8423b1515bea7363e08c85fa9f03ba392`.

## Actual browser evidence

At `http://localhost:8080/`, Settings detected the new release. **Save & update** loaded the matching nginx release ID and descriptive browser title. Existing history and the selected LiquidAI model remained available; no message was sent. The app rendered the new mark in expanded/compact layouts and light/dark appearances. With the user's existing browser zoom, emulated viewports reported **1108×692** and **300×649** CSS pixels. Normal viewport sizing and the original System appearance preference were restored. Widget tests separately cover the named breakpoints, 320px/200% text and active-stream/draft preservation.

The static About page rendered as ordinary headings, paragraphs, links and a getting-started list. It contains no Flutter bootstrap or executable app logic. Browser screenshots live in the original chat workspace's outputs directory: `public-web-logo.png`, `public-web-desktop.png`, `public-web-compact-dark.png`, `public-web-about.png`.

## External setup and unverified scope

Add **`WFFORM_DEPLOY_TOKEN`** as an Actions **repository secret in the source `metaphy6/wfform` repository**, using a fine-grained token restricted to `wfform.com` with **Contents: Read and write**. No custom plain environment variable or OpenRouter CI key is required. After the first publication, configure destination Pages from `main` / root, the `wfform.com` custom domain, DNS and HTTPS. Source edits trigger CI only after being pushed.

Actual GitHub authentication, remote commit/push, destination Pages serving, DNS/certificate setup and public Google indexing were not executed here. No ranking or indexing guarantee is made. Search Console verification/submission requires the public domain. GitHub Pages does not apply this project's nginx headers. Native binaries, authenticated live inference and a new full browser offline/install matrix were not exercised for this metadata/publishing/logo change.
