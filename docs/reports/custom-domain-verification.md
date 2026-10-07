# Custom-domain verification — 2026-10-07

The user purchased `wfform.com`, configured Namecheap DNS and explicitly
authorized GitHub setup and the required deployment changes. The intended
canonical URL is [https://wfform.com/](https://wfform.com/), now live and verified.

## Configuration and local checks

Source revision:
[`4690268`](https://github.com/consciontologic/wfform/commit/46902686358da1d718e7e9159855944b5c69cc88).
Public builds now use `--base-href=/`; canonical, sharing, JSON-LD, sitemap,
robots and package homepage metadata use the custom-domain root. The publisher
manages `CNAME` as `wfform.com`, adopts an identical GitHub-generated file and
rejects conflicting unowned/manual changes before mutation. It preserves older
immutable releases. Application UI, networking and storage behavior are unchanged.

| Executed local check | Result |
|---|---|
| `make verify` | Formatting, analysis and repository checks passed; 358 app/tool tests passed; one opt-in live test skipped |
| Focused publication/workflow tests | 28 passed; six expected failures reproduced before implementation |
| Focused SEO/PWA identity tests | Eight passed |
| `python3 -m unittest discover -s xops/makefile -p 'test_*.py' -v` | 14 passed |
| `make codeg` and `make codeg.check` | Passed, including actual MCP protocol checks |
| `make build.public` | Release built successfully |
| Prepare release against clone of current publication repository | Nine files changed; immediate second run zero changes |
| Changed-document local links and `git diff --check` | 63 links checked; no whitespace errors |

Release: `1aa7a2d3709bf4a17fc156f76d99d629e041088df7ca79b178d7bae204d5989e`.
Its 37 shell assets total **18,163,879 bytes**. This equals the earlier root
release because metadata and base paths return to that configuration; no
performance improvement is claimed. Flutter emitted its existing Cupertino
font-family warning while completing the build successfully.

Local raw evidence is ignored under `outputs/domain-*.txt`. Fixture publisher
tests use fake commands and are distinct from real GitHub deployment evidence.

## Real GitHub and DNS operations

System DNS returned all four documented GitHub Pages IPv4 addresses for
`wfform.com` and `consciontologic.github.io` for the `www` CNAME. No DNS records
were changed by the agent.

The GitHub API accepted custom domain `wfform.com` and then `https_enforced:
true`, each with HTTP 204. Pages remains branch-based on publication `main`,
root directory. GitHub reports an approved certificate covering `wfform.com`
and `www.wfform.com`, expiring 2027-01-05. Certificate management is GitHub's
responsibility; no registrar certificate was purchased or installed.

The source push started
[workflow 37632424699](https://github.com/consciontologic/wfform/actions/runs/37632424699),
which completed successfully: 358 tests, 14 repository tests, six real Chrome
IndexedDB checks, release build, validation and authenticated publication.
Destination commit
[`1b2bbea`](https://github.com/consciontologic/wfform.com/commit/1b2bbeac59733b24dca1fc1a4bfc1564822a435e)
was served by successful
[Pages deployment 37632761767](https://github.com/consciontologic/wfform.com/actions/runs/37632761767).
Raw sanitized job evidence is in `outputs/migration-job-112829838733.txt`.

Normal certificate-validated HTTPS requests returned HTTP 200 for the homepage,
About, manifest, robots, sitemap, service worker and release manifest. The served
homepage has base `/`, canonical `https://wfform.com/` and the expected release
hash. HTTP, HTTPS `www` and the old GitHub project URL each redirected to the
HTTPS apex and returned 200. See ignored `outputs/domain-http.json` for resource
statuses; no certificate validation was bypassed.

## Actual public browser

The in-app Chromium browser rendered the Flutter app at `https://wfform.com/`.
The model browser showed Live catalog, with 17 chat models / 68 listings at
16:59:30 Europe/Istanbul. These are live observations, not fixed test counts.
Model details displayed supported inputs, attachments, context, parameters and
pricing; Settings opened with an empty API-key field.

PWA inspection at `2026-10-07T14:00:40.101Z` showed a secure context and activated
controller/registration at `/service_worker.js`. All 37 shell assets were fetched
and cached (18,163,879 bytes); the release cache had 38 entries including its
marker and the clients cache one entry. There were zero cache-policy violations
and zero cached configuration, API, authorization, query or cross-origin entries.
No worker was waiting or installing.

Resource Timing showed one real catalog GET, HTTP 200, 226 ms, and zero endpoint,
chat or other OpenRouter requests. No user prompt or authenticated inference was
sent. The embedded browser's install prompt was unavailable; successful caching
does not establish actual installation or a network-offline reload.

## Verification limits

No authenticated inference, native installation, actual network-offline reload,
update activation, full responsive matrix or Google indexing check is claimed
for this deployment change. Browser storage is origin-scoped; history on the
old GitHub URL or localhost requires export/import to appear on the new domain.
