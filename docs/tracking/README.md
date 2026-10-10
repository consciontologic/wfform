# Tracking and recovery

[AGENTS.md](../../AGENTS.md) owns policy; [context](context.md) owns current facts;
[roadmap](../planning/ROADMAP.md) owns active work; [schema](tracking.schema.md) defines
append-only [tracking.csv](tracking.csv).

Ignored `state/` contains `current.json`, `checkpoint.json`, `last_failure.json`,
`log.jsonl` and notes. Read available state before work. Checkpoint interrupted steps,
scope, last command and next action. Read safe-run's captured failure log before retry;
mark resolved only after the cause is fixed.

The coordinating parent validates/reviews the combined diff, updates completed
roadmap items, appends a completion row, stages, inspects `make git.dry`, publishes via
`make git` on a Gitflow work branch and opens its PR. Delegates return evidence without
duplicate tracking/staging. Main/develop are PR-only; local-only staging needs an
explicit user request.

```sh
xops/agent/tracking_append.sh \
  --agent=codex --scope=docs \
  --action=commit --status=completed --commit-sha=pending \
  --summary="docs(project): simplify maintained guides" \
  --refs="docs/README.md;docs/tracking/context.md"
```

Append corrections as notes referencing earlier run IDs; never edit past rows.
A pending row is not a commit, and a published PR is not a merged release.
Keep test/runtime/publication evidence distinct. Use PR/CI and ignored local logs for
per-change detail instead of permanent reports. Preserve work during recovery;
a failed gate never authorizes blanket reset/restore.
