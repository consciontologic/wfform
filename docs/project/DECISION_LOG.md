# Accepted project decisions

This is a compact record of current decisions; Git history preserves superseded detail.
Architecture alternatives remain in [ADRs](../design/README.md).

| Date | Decision and consequence |
|---|---|
| 2026-10-05 | Flutter/Dart browser-first client; direct structured OpenRouter API, no backend/proxy or website scraping. |
| 2026-10-06 | Product name wfform; preserve existing PWA/browser-storage identity. Dart package `wfform`; Android/iOS IDs `com.wfform`. |
| 2026-10-06 | Browser-local normalized history, archive/restore, export/import and conflict recovery; separate message-bearing histories when changing models. |
| 2026-10-06 | Treat observed `-1` router pricing as unresolved, never free; preserve exact zero-price guards. |
| 2026-10-06 | Adopt agentic-workspace operations without replacing application code. Scaffold source revision: `a93e0d95e665748c700faa677cc5e8cfdb6c3ca8`; preserve local adaptations on upgrades. |
| 2026-10-06 | Enable project-local CodeGraph, superseding the initial MCP opt-out. Its Node runtime is repository tooling only. |
| 2026-10-07 | Move active source/publication to `consciontologic/wfform` and `consciontologic/wfform.com`; previous local Git metadata is retained in ignored backup. No future history replacement is implied. |
| 2026-10-07 | Use purchased `https://wfform.com/` and base `/`, with GitHub Pages HTTPS. This supersedes the free project URL; browser data transfers only by export/import. |
| 2026-10-09 | Optional desktop MCP/CLI tools and wfformcomp; ordinary chat requires neither. Linux/Windows portable packages precede graphical installers; macOS is deferred. |
| 2026-10-09 | Gitflow, plain SemVer, free quality/security checks and final human production approval. Preserve exact validated source and immutable published assets. |
| 2026-10-10 | Remove Routine delivery automation. Explicitly coordinate tasks/PRs/releases; approved future releases may publish GHCR containers. |
| 2026-10-10 | Keep concise current guides and research/analysis; retire per-change verification reports. Remove unused emoji assets while retaining fonts used by app/code rendering. |

Current delivery and approval details are authoritative in [Gitflow](../guides/GITFLOW.md)
and [CI/CD](../guides/CI_CD.md), under [AGENTS.md](../../AGENTS.md).
