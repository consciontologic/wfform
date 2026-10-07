# Free GitHub Pages verification — 2026-10-07

The user clarified they do not own `wfform.com` and requested free GitHub
hosting. The live application is
[https://consciontologic.github.io/wfform.com/](https://consciontologic.github.io/wfform.com/).
GitHub Pages serves publication `main` / root with `cname: null` and HTTPS
enforced. No DNS change or domain purchase is required.

## Published revision

Source commit:
[`e9eff02`](https://github.com/consciontologic/wfform/commit/e9eff0234a90a5b6ee892cea52afa529781c8c22).
The [source workflow](https://github.com/consciontologic/wfform/actions/runs/37619543479)
completed successfully, including the real authenticated publication.
Destination commit:
[`0e28054`](https://github.com/consciontologic/wfform.com/commit/0e280549d2aef6ab6803a2f286557324123c7b2c).
Its [Pages deployment](https://github.com/consciontologic/wfform.com/actions/runs/37619868926)
also completed successfully. GitHub's Pages API reports `built`.

Release: `709ebb5d75a455cbdc94514a30ffbcf9a92961a60a3c9bb6df7bbf87b14d79fc`.
The release contains 37 shell assets totaling **18,164,471 bytes**. Local and CI
builds produced the same release hash. This is an artifact measurement, not a
claim of improved startup performance.

Public builds use `/wfform.com/`; root local/Docker builds retain `/`.
Canonical, sharing, sitemap and public information URLs use the free Pages URL.
The publisher safely retires an unchanged previously owned `CNAME`, including
the case where GitHub already removed it. Unowned or modified files remain
conflicts. Existing immutable release assets remain available to older clients.

## Executed checks

| Check | Result |
|---|---|
| `make verify`, local and GitHub | Formatting, analysis and repository checks passed; 352 tests passed; one opt-in live test skipped |
| `python3 -m unittest discover -s xops/makefile -p 'test_*.py' -v`, local and GitHub | 14 passed |
| GitHub Chrome IndexedDB checks | Six real browser storage tests passed |
| Focused publishing/PWA tests | 39 passed; fixtures and fake CLI commands, not live deployment proof |
| Focused SEO/PWA identity tests | Eight passed |
| Actionlint 1.7.12 and Bash syntax | Passed |
| `make codeg` and `make codeg.check` | Passed |
| `make build.public` | Real release built with the hash above |
| Prepare actual release into a clone of the destination | 46 changes; immediate second preparation made zero changes |
| Public HTTPS GET | HTTP 200; correct release and `<base href="/wfform.com/">`; no custom-domain redirect |

New regressions cover dotted base-path segments, invalid base paths, retiring
owned/missing-owned CNAME files, rejecting unowned or edited CNAME files, and
subpath SEO/manifest identity. Two analyzer interpolation-style findings in the
new tests were fixed before the passing full gate.

## Actual public-browser evidence

The Codex in-app Chromium browser opened the public HTTPS origin and rendered
the Flutter application. The model browser showed **Live catalog** and, at
15:18:32 Europe/Istanbul, 17 chat models / 68 listings. These are observations,
not fixed expected catalog counts. Model details and Settings opened correctly;
the public API key field was empty.

The app's PWA inspection at `2026-10-07T12:19:45.926Z` reported:

- Secure context and an activated controller/registration at
  `/wfform.com/service_worker.js`.
- All 37 release shell assets fetched: 18,164,471 bytes. The release cache had
  38 entries including its marker; the client-generation cache had one entry.
- Zero cache-policy violations and zero cached configuration, API,
  authorization, query or cross-origin entries.
- One live OpenRouter catalog request, HTTP 200, 303 ms; zero endpoint,
  inference or other OpenRouter requests.
- No waiting or installing worker. Install prompt availability was false in
  this embedded browser.

Raw local command evidence is in ignored `outputs/pages-*.txt` and
`outputs/migration-job-112786035908.txt`. The public UI and its inspection were
read directly; a diagnostic export download did not return a confirmed path
through browser automation, so no saved inspection JSON is claimed.

## Verification limits

No authenticated OpenRouter inference was sent during this hosting change.
Actual network-offline reload, native PWA installation, update activation,
other browser engines and a new complete responsive matrix were not rerun.
Existing deterministic PWA tests passed; successful caching alone does not
prove those additional browser scenarios. Google indexing is unverified.
GitHub Pages does not apply the Docker nginx response-header configuration.

Future source `main` pushes rerun verification and publish changed compiled
artifacts automatically; unchanged artifacts produce no destination commit.
The public site stores conversations/settings on its new origin, separately
from localhost. Visitors supply their own OpenRouter key in Settings.
