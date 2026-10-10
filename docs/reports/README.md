# Research and analysis

Use this folder for reusable research, comparisons, benchmarks and decisions that
need more evidence than an ordinary guide. State the question, method, findings,
limitations and sources; keep the conclusion brief.

Per-change test reports belong in PRs, CI artifacts and ignored local output, not
new permanent documents. [CHANGELOG.md](../../CHANGELOG.md) summarizes releases and
[tracking.csv](../tracking/tracking.csv) preserves the append-only work log.
Historical verification reports remain recoverable through Git history.

For repeatable performance work, start with [measurement methods](../performance.md).
For current tests and release gates, use [setup](../guides/README.md#checks) and
[CI/CD](../guides/CI_CD.md).
