# wfform documentation

Start with the [application README](../README.md) for a quick start and the [setup guide](guides/README.md) for configuration and optional checks. This index separates implemented project contracts, active work, historical evidence and reusable agent-framework references.

## Application contracts

| Document | Owns |
|---|---|
| [Catalog](catalog.md) | Structured discovery, free-price eligibility, unresolved prices, quarantine, refresh/cache and selection |
| [Chat and health](chat.md) | Request/streaming behavior, context/output budgets, health, allowance and failures |
| [Multimodal input](multimodal.md) | Supported media, capability/price guards, formats and provider limits |
| [File rendering](file-rendering.md) | Local document/source previews, Markdown/code rendering and text-file handling |
| [History](history.md) | Persistence, migration, archive/restore/delete, export/import and conflicts |
| [PWA](pwa.md) | Installability, offline operation and updates |
| [Search metadata](seo.md) | Crawlable product information, canonical URLs, sharing and Search Console setup |
| [CI/CD publishing](guides/CI_CD.md) | GitHub checks, web-artifact publication and required credentials/host settings |
| [Native platform setup](native-platforms.md) | Android/iOS identifiers, host projects and remaining native adapter/build work |
| [Performance/release measurement](performance.md) | Immutable release assembly, cache reuse and measurement limits |
| [Docker/nginx guide](guides/DOCKER.md) | Container setup, runtime config, TLS and observable header checks |

## Project and engineering map

| Location | Contents |
|---|---|
| [Project](project/README.md) | Charter, scope decisions, migration provenance and glossary |
| [Code](code/README.md) | Actual architecture, module maintenance and external/local contracts |
| [Design](design/README.md) | Implemented UX/system design and accepted architecture decisions |
| [Planning](planning/ROADMAP.md) | The authoritative active six-part scope and acceptance gates |
| [Tracking](tracking/README.md) | Context pack, append-only action log and local recovery workflow |
| [Guides](guides/README.md) | Deployment and agent-client operating references |
| [Reports](reports/README.md) | Verification evidence, dates and provenance |
| [Agent rules](../AGENTS.md) | Authoritative repository operating policy |
| [Skills](../.agents/skills/README.md) | Reusable operating skills, loaded when applicable |
| [xops](../xops/README.md) | Shell/Python repository operations, separate from Flutter runtime |

The documents above describe this project. Update the owning document when a contract changes. Historical verification counts retain their original date and scope; a new build needs new evidence.
