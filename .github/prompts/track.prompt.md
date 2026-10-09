---
agent: agent
description: Append a tracking row to docs/tracking/tracking.csv for the work just completed.
---

# Track work

Append exactly one row to [`docs/tracking/tracking.csv`](../../docs/tracking/tracking.csv)
via [`xops/agent/tracking_append.sh`](../../xops/agent/tracking_append.sh)
describing the work you just completed.

Default field choices (override if the work is different):
- `--action=commit` if a real diff is staged
- `--action=note` if no diff (informational / exploration)
- `--status=completed`
- `--commit-sha=pending` (only on `action=commit`)
- `--summary` must follow Conventional Commits: `type(scope): description`
- `--refs` semi-colon-separated file paths and any issue / PR / ADR links

After appending, run `git add -A` if there are unstaged changes. Once the full
implementation, review and verification gates pass, the coordinating parent
inspects `make git.dry`, publishes the validated Gitflow work branch with
`make git`, and opens/updates its PR under AGENTS.md §2. This tracking command
alone does not establish passing gates. Never commit/push directly to
`main`/`develop` or bypass protection.

Report:
- `run_id` and the row contents (one line).
- The list of staged files (or "no diff to stage" if none).
- Any tests run with `passed / failed` counts.
- The published commit/PR, when publication has completed.
