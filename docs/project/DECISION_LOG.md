# Project decision log

Decisions are recorded from the user's requests and the resulting implementation. This is a scope/provenance log; architectural alternatives live in [ADRs](../design/README.md). Add later decisions rather than rewriting an accepted historical one.

| Date | Decision | Basis and consequence |
|---|---|---|
| 2026-10-05 | Build a Flutter/Dart browser-first OpenRouter free-model demo | User-specified technology and API scope; direct browser access, no application backend or proxy. |
| 2026-10-06 | Name the product wfform | User rename; existing package and browser-storage identifiers remain stable to preserve imports/history. |
| 2026-10-06 | Keep conversations in browser-local history with archive/restore/delete | User requested continuation of old conversations. IndexedDB holds durable normalized records; export/import provides portability. |
| 2026-10-06 | Require a new conversation when changing models | User requested separate model conversations; no silent history reuse with another model. |
| 2026-10-06 | Add explicit edit/resend, attachments, adaptive appearance and diagnostics refinements | Earlier messages and received output remain preserved; advertised capability and zero-price policy constrain inference. |
| 2026-10-06 | Treat observed -1 router prices as unresolved exclusions | Public API evidence and router documentation support conservative exclusion; this is not an explicitly documented numeric convention. Genuine malformed metadata still fails validation. |
| 2026-10-06 | Move application sources into the wfform repository | User supplied the destination checkout. Its existing empty main branch and origin git@github.com:metaphy6/wfform.git were preserved; the move is not a commit or push. |
| 2026-10-06 | Adopt the full agentic-workspace scaffold without MCP | Source: the local `agentic-workspace` checkout at a93e0d95e665748c700faa677cc5e8cfdb6c3ca8. Invocation used `--target <repository> --preset full --no-mcp`, without --force. Existing application files were preserved; no language preset was selected because Dart was not offered. |
| 2026-10-06 | Keep MCP installation optional and explicit | The full operating workflow is useful independently of CodeGraph. --no-mcp avoids an unsolicited Node/MCP/index dependency and global changes. Local reads/searches remain the documented fallback. |
| 2026-10-06 | Add static Docker/nginx operations and broad local file/rendering support | User-requested next work; acceptance status is maintained in the roadmap, not inferred from this decision row. Python remains operations tooling only. |

## Follow-up: workflow and identity

On 2026-10-06 the user required one Makefile, an enabled CodeGraph integration, a gear emoji for Settings and the identifier `com.wfform`.

- All app/deploy/repository targets now share the root Makefile. The former `Makefile.app.mk` was removed without changing target behavior.
- CodeGraph is required for this repository, superseding the initial MCP opt-out above. Its pinned Node-based runner is repository tooling only; the app and container retain Flutter/Dart and static nginx boundaries.
- Settings uses an offline-bundled gear graphic, with light/dark and 200% text coverage.
- Dart's identifier rules require `com_wfform` as the package name. `com.wfform` is recorded as the requested future native application ID; this web-only repository has no native platform configuration. The installed PWA identity and storage/cache keys remain unchanged.

## Clarification: native application identifiers

On 2026-10-06 the user clarified that `com.wfform` means the Android/iOS application identifier. This supersedes the Dart-package interpretation above. The Dart package is now `wfform`; generated Flutter Android and iOS hosts configure Android namespace/application ID and iOS Runner bundle ID as `com.wfform`. The PWA manifest and browser storage identity remain unchanged. Native adapters and store release preparation remain separate work; see [native setup](../native-platforms.md).

## Public website follow-up — 2026-10-07

The user requested search metadata, CI/CD publishing web builds to `metaphy6/wfform.com`, and a meaningful header logo. The implementation uses `https://wfform.com/` as the intended canonical origin, with a small static About document for crawler-readable product information while all app UI/logic remains Flutter. A bracketed conversation mark replaces the arrow and matches the web icons. The authorized GitHub workflow publishes validated, credential-free artifacts on source `main` pushes; local agents still do not commit or push. Token/Pages/DNS configuration and indexing remain explicit external steps, documented in the [publishing guide](../guides/CI_CD.md).

## Migration provenance and retained evidence

Application sources moved from the original local chat workspace into the project repository on 2026-10-06. Historical generated outputs remain in that original workspace's outputs directory. Existing detailed feature and verification documents moved with the application and retain their dates and measured counts. Machine-local paths are omitted from published documentation.

Framework origin observed during adaptation: git@github.com:metaphy6/agentic-workspace.git. The recorded revision identifies the source checkout inspected during scaffolding; it does not claim that every framework file was unmodified. Project-specific corrections belong in this repository and should be reviewed before a future scaffold update. Re-running with --force is not part of the documented normal workflow.

## Fresh GitHub account migration — 2026-10-07

At the user's explicit request, active development moves to
[consciontologic/wfform](https://github.com/consciontologic/wfform) with a fresh
Git history. The old local Git metadata is backed up under ignored
`.local/git-history-backup/`, and existing tracking rows remain as documentation.
The publishing workflow now targets
[consciontologic/wfform.com](https://github.com/consciontologic/wfform.com)
using the same `WFFORM_DEPLOY_TOKEN` secret name. This is a source/account
migration; the canonical website origin, PWA identity, stored conversations
and application behavior remain unchanged. The user authorized the source push
and API-triggered pipeline for this migration.

## Free GitHub Pages address — 2026-10-07

After Pages was enabled, DNS checks found `wfform.com` undelegated. The user
confirmed they do not own it and chose the free project address
`https://consciontologic.github.io/wfform.com/`. Use that canonical URL, build
public releases under `/wfform.com/`, and remove the custom-domain setting and
legacy owned `CNAME`. The publication repository remains `consciontologic/wfform.com`.
No domain purchase or DNS administration is needed.

## Purchased custom domain — 2026-10-07

The user subsequently purchased `wfform.com`, configured Namecheap A/CNAME
records, and explicitly requested GitHub setup. This supersedes the free-URL
decision above: public builds use `/`, SEO uses `https://wfform.com/`, and the
publisher manages `CNAME` with `wfform.com`. GitHub Pages remains the static
host and supplies managed HTTPS; no separate certificate or backend is added.
The source/publication repositories and Actions secret remain unchanged.
Browser history stays on its original origin; export/import is the supported
transfer between the former GitHub URL and the custom domain.
