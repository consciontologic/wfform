# Tracking CSV schema

[tracking.csv](tracking.csv) is append-only UTF-8 RFC 4180 CSV, LF/no BOM.
Use [tracking_append.sh](../../xops/agent/tracking_append.sh), which validates and writes
atomically under `flock`. Existing rows are immutable; corrections use `action=note`
and reference the prior `run_id`.

Header (exact order):

```text
ts_utc,run_id,agent,scope,action,status,summary,refs,commit_sha
```

| Column | Contract |
|---|---|
| `ts_utc` | UTC `YYYY-MM-DDTHH:MM:SSZ`, monotonically nondecreasing |
| `run_id` | `[a-z0-9-]{4,40}`, stable across one task's rows |
| `agent` | `copilot`, `claude`, `codex`, `local`, `human` |
| `scope` | Required, at most 40 characters |
| `action` | `plan`, `implement`, `test`, `review`, `commit`, `revert`, `note`, `block` |
| `status` | `started`, `in_progress`, `passed`, `failed`, `blocked`, `completed` |
| `summary` | Required, at most 200 characters; commit rows require Conventional Commits |
| `refs` | Optional semicolon-separated paths, links or earlier run IDs |
| `commit_sha` | Commit: `pending` or 7–40 hex; revert: 7–40 hex; other actions: empty |

Commit summary types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`,
`chore`, `ci`, `build`, `revert`; use `type(scope): description` per AGENTS.md.
The appender rejects malformed commit summaries with exit 65. All rows have nine
columns and valid enum values.

## Publication

The parent appends `action=commit,status=completed,commit_sha=pending` only after
gates pass, stages reviewed files and runs `make git.dry` then `make git` on the work
branch. [git_ops.py](../../xops/makefile/git_ops.py) selects pending completed rows whose
run IDs are absent from existing commit messages and batches them into **one commit**:
first summary is the subject, other summaries/refs enter the body and each run ID gets
a trailer. It pushes to the work-branch upstream. No direct main/develop writes.

Repeated invocation uses run-ID trailers for idempotency; the CSV itself stays
append-only. Empty commits are not created. Dirty work without a pending row is
refused. The dry command is read-only. Delegates do not stage or publish combined work.

A blocker uses `action=block,status=blocked` plus a recovery checkpoint. Reverts must
be scoped to owned changes under current AGENTS.md; this schema authorizes no reset,
history rewrite or protection bypass.
