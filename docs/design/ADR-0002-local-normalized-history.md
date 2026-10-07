# ADR-0002: Normalized browser-local conversation history

- Status: accepted; records the implemented persistence design.
- Date: 2026-10-06.
- Decision basis: user request for continuing, archiving and later deleting conversations.

## Context

Conversations can contain large local media and incremental streamed responses. Re-encoding a complete base64 conversation on every checkpoint wastes work. Reload, storage failure and two tabs editing the same record require explicit recovery behavior.

## Decision

Use IndexedDB v2 for summaries/documents, individual message rows and immutable binary attachments, with revision-checked atomic writes, local export/import and a separate tab-local text recovery marker.

## Consequences

- The history list reads small summaries; only the selected conversation loads messages/media.
- Checkpoints write changed rows and newly introduced media. Unchanged attachment bytes are referenced rather than serialized repeatedly.
- Legacy records migrate only in a successful atomic checkpoint. Aborted migration retains the original.
- A stale write creates a recovered copy rather than overwriting another tab. Archive/restore and permanent deletion stay explicit.
- Writes wait for commit. Readonly snapshots resolve after all requested values are received/validated and retain bounded phase diagnostics for failures.
- Data is scoped to the browser origin and can be cleared or evicted. No cloud synchronization is promised; users can export backups.

## Considered options

- **Normalized IndexedDB, chosen:** supports asynchronous browser-local transactions and binary payloads without a backend.
- **One localStorage JSON record:** easy initially, but synchronous large base64 writes and whole-record checkpoints are inappropriate for attachments.
- **One unnormalized IndexedDB document:** removes the synchronous API but still duplicates large unchanged media in checkpoints.
- **Remote history service:** would enable device sync but introduces a backend/authentication scope the user did not request.

See [history contract and verification](../history.md) and [history module](../code/MODULES.md#history).
