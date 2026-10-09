# Tracking and recovery

The [schema](tracking.schema.md) defines the append-only CSV contract. [AGENTS.md](../../AGENTS.md) defines operating policy. The [context pack](context.md) holds concise wfform facts and links; the [roadmap](../planning/ROADMAP.md) holds the authoritative active checklist.

## Files

| Path | Purpose | Version control |
|---|---|---|
| [tracking.csv](tracking.csv) | Timestamped action/evidence log, appended through the validated tool | Tracked |
| [tracking.schema.md](tracking.schema.md) | Row format and invariants | Tracked |
| [context.md](context.md) | Product/workspace/configuration conventions | Tracked |
| state/current.json | Active task metadata | Ignored local recovery |
| state/checkpoint.json | Interrupted step, scope, last command, completed work and next action | Ignored local recovery |
| state/last_failure.json | Failure breadcrumb from safe-run; inspect its referenced log before retrying | Ignored local recovery |
| state/log.jsonl and state/notes/ | Local event/recovery context | Ignored local recovery |

The initial moved repository can have an unborn main branch. Absence of an initial commit is not absence of the repository, its origin or the application files. Do not invent a commit or replace Git metadata to satisfy an operating script.

## Coordinated workflow

1. Read the request, roadmap and local recovery state. Preserve existing/concurrent work.
2. Implement the authorized slice with its matching tests and docs. Delegated agents return evidence; they do not append duplicate completion rows or stage the combined work.
3. Run checks from the actual repository. Use [safe-run.sh](../../xops/agent/safe-run.sh) for long/risky commands; inspect the saved log on failure, diagnose, repair and rerun the affected gate.
4. The parent reviews the complete changed set for scope and local secrets, updates completed roadmap items, appends the completion row, and stages according to AGENTS.md. Do not discard work simply because a gate failed.
5. The coordinating parent inspects `make git.dry`, then uses `make git` to
   commit/push the validated Gitflow work branch and opens/updates its PR.
   Never write directly to `main`/`develop`; respect review and required checks.
   Stop at staging only when the user explicitly requested a local-only handoff.

Example parent completion command, only after this slice's gates have actually passed:

```sh
xops/agent/tracking_append.sh \
  --agent=codex --scope=workspace-adaptation \
  --action=commit --status=completed --commit-sha=pending \
  --summary="docs(project): populate wfform architecture and operating context" \
  --refs="docs/README.md;docs/code/ARCHITECTURE.md;docs/tracking/context.md"
```

The appender generates a run ID unless one is supplied. A pending tracking row is not a Git commit; `make git.dry` previews the guarded work-branch commit without writing. Read recent rows with `make track.list` or tail the CSV. Report the commit and PR separately from later merge/release outcomes.

## Corrections and evidence

Never hand-edit prior CSV rows. Append a corrective note referencing the earlier run ID. Keep test results explicit: deterministic fake API tests, real browser database tests, public live catalog checks, authenticated live chat and release-browser/PWA behavior are distinct.

A real blocker or interruption gets a checkpoint with a concrete next action. Inability to run one external check does not erase completed independent work or justify a fabricated success. Do not use a generic framework example as evidence that a wfform gate exists or passed.
