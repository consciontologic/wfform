# GitHub account migration verification — 2026-10-07

The user explicitly authorized migration without prior Git history, source push
and pipeline dispatch using the new GitHub account. The active source is
[consciontologic/wfform](https://github.com/consciontologic/wfform), and compiled
website files publish to
[consciontologic/wfform.com](https://github.com/consciontologic/wfform.com).

## Fresh source history

The initial source snapshot is
[`72a1531`](https://github.com/consciontologic/wfform/commit/72a15313d1ae82da2cdbac6d5435fa6e1163e225).
The GitHub API confirmed zero parents and the new `consciontologic` author.
No prior Git commits were imported. Later documentation or maintenance commits
belong to this new history. The old local Git metadata remains recoverable in
ignored `.local/git-history-backup/`; the old remote repository was not deleted.
Existing tracking CSV records remain as an implementation audit trail.

Active workflow, publisher, package repository/issue links, public About link,
agent deployment instructions and guides use the new account. Dated reports and
scaffold provenance retain their original account references intentionally.
Two pre-existing broken skill links in the model profiles guide were corrected.
The new source tree contains 355 files and no local configuration, build output,
credentials or Git backup. Temporary API credentials were never staged.

## Checks executed

| Check | Observed result |
|---|---|
| `make verify` locally and on GitHub | Formatting and analysis passed; 346 deterministic tests passed; one opt-in live test skipped; repository configuration/key checks passed |
| `python3 -m unittest discover -s xops/makefile -p 'test_*.py' -v` locally and on GitHub | 14 tests passed, including alternate-checkout CodeGraph configuration |
| Focused publisher tests | 18 tests passed, using fake Git/CLI commands; exact new destination, source guard and provenance covered |
| Actionlint 1.7.12 and `bash -n deploy/scripts/publish-website.sh` | Passed |
| GitHub Chrome IndexedDB tests | Six real browser storage checks passed |
| `make build.public` locally and public release build on GitHub | Both produced the identical release below |
| Real destination tree inspection | 80 files; compiled HTML/JS/WASM/assets/PWA/SEO files and deployment metadata; no Flutter source, tests or configuration |
| Remote immutable-commit integrity check | Downloaded and verified SHA-256 for all 79 files listed in the ownership manifest; 36,350,582 bytes, including root aliases and immutable copies |

The real manually dispatched
[GitHub workflow run](https://github.com/consciontologic/wfform/actions/runs/37615404976)
finished **successfully**, including authenticated destination commit/push.
The redundant push-triggered run for that exact source SHA was canceled before
its job executed. No unrelated run was canceled.

Destination commit:
[`f52b948`](https://github.com/consciontologic/wfform.com/commit/f52b9483ca755258f24bd29ba7d69790617cb5b9),
with deployment provenance pointing to source `72a1531`.

Release: `1aa7a2d3709bf4a17fc156f76d99d629e041088df7ca79b178d7bae204d5989e`.
Its 37 shell assets total **18,163,879 bytes**. The same content hash was obtained
locally and on the GitHub runner; no performance improvement is claimed.

Raw local evidence is ignored under `outputs/migration-*.txt` and
`outputs/migration-published-integrity.json`. GitHub run logs are the remote
execution evidence. Mocked publisher tests alone are not publication proof.

## Remaining hosting scope

The required source Actions repository secret is still `WFFORM_DEPLOY_TOKEN`;
its presence and successful use were verified. No OpenRouter API key is needed
or included in the public release.

The destination Pages API returned HTTP 404; Pages serving, custom-domain DNS,
HTTPS and Google indexing were not configured or verified by this migration.
Follow the [CI/CD guide](../guides/CI_CD.md) to enable Pages from `main` / root
and configure `wfform.com`, or serve the published root from another static host.
Publishing files to GitHub is complete; public domain serving is separate.
No new authenticated OpenRouter inference, native build or full PWA/browser UI
matrix was run for this account-only migration.
