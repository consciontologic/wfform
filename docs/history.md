# History and drafts

History is browser-local IndexedDB data, scoped to scheme/host/port. There is no
cloud sync. Export a conversation for a portable backup; import creates a separate
copy including text, files and draft. Clearing/evicting site data can remove history.

## User behavior

- **Drafts** hold unsent text/files, parameter overrides and tool selections. Blank
  workspaces create no row. Only user-content dispatch promotes a draft to **Chats**;
  health probing alone does not. Drafts can be exported/deleted, not archived.
- **New conversation** resumes an unsent workspace for the selected model. Model
  changes preserve composer text/files and keep message-bearing histories separate.
  Incompatible retained files block sending until explicitly removed or compatible.
- **Archive** preserves read-only history; **Restore** permits continuation. Deletion
  on draft/archived rows is immediate and permanent. Failures retain the record.
- Switching history/model waits for active sends or history operations. Deleting a
  different draft/archived record does not disturb the active composition/response.
- About/Terms/Liability navigation waits for a successful checkpoint and returns to
  the same tab's conversation. File selection or unsaved failures block navigation.
- Accepted input clears its composer; failure retains the turn/partial output and
  newer drafts. Reload never resends inference or replays tools.

## Persistence contract

`freeform-conversations` database v2 contains `summaries`, `documents_v2`,
`messages_v2` and `attachments_v2`. Changes commit atomically; checkpoints write only
changed messages/metadata and new immutable binary files. Summaries load lazily.
Legacy `records`/`meta` survive until a successful migration checkpoint. Database
versioning is independent of export format; renaming the app does not rename stores.

Changes coalesce around 800 ms; important lifecycle boundaries checkpoint immediately.
Guarded navigation/updates await completed writes. The tab-local
`freeform-conversations.active.v2` and `freeform.pendingDraft.v1` recover selection and
newer unsent text for the matching record. Files never enter text recovery markers,
localStorage or PWA caches. Damaged/unsupported records remain intact; storage errors
stay visible, preserving in-memory work without pretending it was saved.

Every save/delete checks the last-read revision in the transaction. Conflicting writes
or deletion races create a **Recovered copy**, preserving both versions rather than
silently merging/overwriting. Capacity failure retains local work and reports failure.
`BroadcastChannel` refreshes IDs only; transactional safety does not depend on it.

Limits: **200 records**, **32 MiB encoded per record**, **24 MiB base64 characters of
sent attachment data** per conversation. Browser quota may be lower. No automatic
history deletion; archive does not free storage. Tool call/result IDs and opaque
reasoning details remain complete through save/export; reconnect tools explicitly.

## Checks

```sh
flutter test test/history
CHROME_EXECUTABLE=/path/to/chrome flutter test --platform chrome test/history/browser/indexeddb_checks.dart
```

Browser checks use isolated test databases. Manually test two-tab conflicts, reload,
export/import with files, storage failure and interrupted migration in each target
browser. [Performance](performance.md) describes the opt-in storage benchmark.
