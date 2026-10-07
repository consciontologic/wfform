# wfform project charter

Recorded 2026-10-06 from the user's application scope and implemented behavior.

## Purpose and users

wfform means **Wrapper for Free Open Router Models**. It is a development/demo application for discovering OpenRouter's free offerings, understanding capabilities and recent availability, and continuing browser-local conversations across sessions. The primary user is an individual exploring models with their own development credential.

## Product commitments

- Use Flutter/Dart for all application UI and logic. Web is the initial supported release target; replaceable browser adapters leave room for later Flutter platforms.
- Discover the current structured API catalog on each online launch and preserve a labeled cache for startup/offline inspection.
- Never infer zero pricing from missing/malformed metadata or the :free suffix alone. Never use paid fallbacks, duplicate automatic sends or silent model switching.
- Make model details available by pointer, keyboard and touch. Distinguish presence, capability and recent inference health.
- Preserve drafts, received output, archived histories and explicit recovery choices. A changed model starts another conversation.
- Offer meaningful compact, medium and expanded layouts, selectable readable content, keyboard/touch access and large-text support.
- Provide an installable release PWA with an offline shell, cached catalog, explicit remote-chat unavailability offline and a draft-preserving update flow.
- Make failures inspectable through bounded, readable diagnostics. Verification claims must identify mocked, real API and real browser evidence separately.

## Scope boundaries

There is no application backend, API proxy, React/Node/Python application runtime, cloud history sync or production authentication service. Minimal browser-host/PWA glue and a static nginx container are deployment infrastructure. Python stdlib and shell under xops support repository operations only.

Development configuration and a local ignored key are intentional. Credentials delivered to a browser are visible to its user. Config files, generated builds and browser artifacts need explicit ownership; local secrets must stay out of version control and container images. Requested HTTP-header policies are verified as configured behavior, not represented as an unsupported scanner grade.

Model-advertised modalities do not guarantee every provider accepts every format. Context estimation is approximate. Browser-local storage can fail or be cleared; users can export portable backups. Native platforms and untested browsers are not implied by web success.

## Success criteria

The current user scope is complete only when runnable files, documentation and matching tests exist; formatting, analysis, relevant automated tests and a release build pass; and the changed release behavior is checked in a browser where the environment permits. External blockers must identify the exact unverified check. The [roadmap](../planning/ROADMAP.md) owns current acceptance work; historical [verification reports](../reports/README.md) remain dated.

## Source of truth

Use [AGENTS.md](../../AGENTS.md) for operating rules, [the architecture](../code/ARCHITECTURE.md) for implemented boundaries, [DESIGN.md](../design/DESIGN.md) and accepted ADRs for rationale, and the feature guides indexed in [docs/README.md](../README.md) for exact behavior. The [decision log](DECISION_LOG.md) records scope and workspace provenance without rewriting prior evidence.
