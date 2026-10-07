# wfform application design

Status: implemented baseline with public metadata, publishing and branding follow-up verified locally. Updated 2026-10-07. The [roadmap](../planning/ROADMAP.md) distinguishes completed deliverables from external setup.

## Problem and goals

Free-model discovery is useful only if price eligibility, capability and recent responsiveness are distinct. A user needs to inspect models, explicitly choose one, send a conversation without surprise paid routing, and recover their work when the network or provider fails. The interface must remain usable across narrow and wide layouts, pointer/keyboard/touch input and 200% text.

The design combines a live normalized catalog, bounded health observations, one active conversation controller and durable local history. A static PWA shell supplies offline startup; no backend stores conversations or credentials. [Architecture](../code/ARCHITECTURE.md) describes the implemented boundaries.

## Interaction model

| Available layout | Arrangement and interaction |
|---|---|
| Compact, below 600 logical pixels | Focused chat with drawer history/utilities, model chooser dialog and tap-accessible details. |
| Medium, 600–1099 | Navigation rail; history, selection and details open as overlays. |
| Expanded, 1100 and above with enough space at the current text size | Resizable history sidebar with utilities at its bottom; optional model panel from 1420 when enough chat width remains. |

Text scaling can select a less dense arrangement. Controllers and focus nodes survive layout transitions. New conversation, model changes and history switches are guarded while a response/history transition is active. Model details use text labels, focus/pointer previews and explicit information actions; no essential information depends solely on hover.

The sidebar divider supports pointer/touch dragging and keyboard adjustment.
The plain line has no grip icon. Arrow keys adjust in 16-pixel steps; Home/End select limits, Enter resets, and Escape collapses. Dragging to the left edge also collapses it. Hover the outermost left edge to preview navigation; moving away hides the preview. A keyboard-focusable edge target and tap access provide the same action without hover. Activating any sidebar item restores its default width and performs that action.
Its preferred width is saved locally on release, rather than writing storage
on each pointer move. Width is bounded by the viewport and text size so the
conversation retains usable space; switching to a drawer or navigation rail
does not discard the preference. The default is 290 logical pixels, with a
240–440 preferred range and tighter effective bounds when needed. The inspector
is omitted when it would crowd the conversation. Short sidebars/drawers scroll
to keep utilities reachable. Settings offers 100%, 125%, 150% and 200% text.

Model details and the inspector start with a literal, concise description preview.
Show full description expands the complete API text without a line limit.
Context and input/output capabilities are visible at a glance; availability,
pricing, parameters, file limits and provider details expand on demand. Some upstream descriptions already end in an
ellipsis; these receive a source notice and a copyable OpenRouter model-page
link. Missing paragraphs are not reconstructed, and additional API requests
are not made to fetch identical descriptions. The repetitive instruction to
open details is omitted from model-row hover previews; their explicit details
buttons remain accessible.

The composer grows over several lines and clears when a valid send is accepted. A next draft can be written while the answer streams. Explicit retry reuses the failed user turn; edit/resend appends a revised copy. Returned reasoning is separate and collapsible. Context exclusions and continuation are explicit actions, preserving earlier records.

Clicking or tapping outside the composer releases its editing focus and input
connection, so its caret stops blinking. Keyboard focus transfer and browser
view blur also stop editing without erasing the draft. Dragging the sidebar
divider is an intentional exception: resizing preserves the typing target.

History offers current and archived views, search, restore, export/import and direct permanent deletion of archived records. Conflicting tabs preserve separate recovered copies. The interface reports save status and keeps in-memory work if storage fails.

## Visual and content design

The visual system uses low-saturation neutral/pastel surfaces, strong readable borders, restrained offset shadows and local typography. System/Light/Dark modes keep the same hierarchy. Diagnostics, model information and model selection have distinct colored headings and local emoji graphics with textual labels. There is one Diagnostics navigation action and Settings directly beneath it in persistent navigation.

Readable application text is selectable. Bounded local preview and Markdown/code rendering extend this principle; their precise formats and fallbacks are specified in [file-rendering.md](../file-rendering.md). Rendering content never executes source code or expands model upload capabilities implicitly.

The product mark encloses a conversation bubble in brackets, representing a wrapper around model conversations. It is decorative next to the selectable wfform name, uses theme colors, and is shared conceptually with the generated PWA/favicon artwork. The small static About document uses the same palette to provide readable product information before launching Flutter and to search crawlers.

The footer groups the version and a plain GitHub text link on the left.
Information links remain on the right, using an Info menu when space is limited.
No GitHub logo or doodle is shipped on app or information pages.

## Resilience and trade-offs

- Exact price validation and zero-price routing guards favor safe exclusion when an applicable charge is unconfirmed. This may omit a router that could sometimes choose a free model.
- Recent health is useful admission information, but an additional selected-model probe consumes a request and cannot guarantee the subsequent request.
- Browser-local IndexedDB avoids a backend and enables offline history; it does not synchronize devices, and site-data clearing can remove history. Export/import provides an explicit portable copy.
- Normalized history storage reduces unchanged-media serialization. It adds a versioned codec and transactional migration path that require dedicated tests.
- A custom content-addressed PWA worker supports verified offline shells and stable updates. Minimal JavaScript glue must be tested alongside the Dart release assembler.

## Active extension and acceptance

The current follow-up adds search/sharing metadata, a static product document, GitHub web publishing and the wrapper/conversation logo. Earlier workspace, CodeGraph, container, rendering and native-identity phases remain recorded in the roadmap. See [SEO](../seo.md), [CI/CD](../guides/CI_CD.md) and the [Docker guide](../guides/DOCKER.md) for hosting boundaries.

Acceptance requires changed behavior tests, formatting/analysis, a release PWA build and real browser checks for the changed path. Header configuration can be verified directly; external scanner ratings must not be invented. Existing verification records retain their dates and cannot certify a newer release automatically.

## Application behavior reference

Search or open the model selector, inspect capabilities, and explicitly choose a compatible model. Incompatible listings remain inspectable. The supplied Nemotron example is not a default or hardcoded catalog. Chat uses the actual selection with zero prompt/completion/request/image/audio price caps and provider fallback disabled.

The composer starts at three lines, or two when viewport height or 200% text needs more room. It grows to five lines in compact layouts and eight in wider layouts, then scrolls internally. It supports multiline text, Ctrl/Command+Enter to send, cancel, explicit retry, copy, and a new conversation. Once a valid turn is accepted, its text and files move into the conversation and the composer clears immediately, so the next draft can be written while a response arrives. A refused send leaves the draft intact. A later failure preserves the sent message, attachments and partial answer; explicit retry reuses that user turn without duplicating it or overwriting the next draft.

**Edit and resend** opens a separate editor for a previous user message. Sending appends an updated copy with its retained attachments and an origin label; the original messages and any existing composer draft remain intact. Cancelling the editor changes neither. Reasoning returned by the model is separate and collapsible. Answers render selectable Markdown with headings, lists, tables and highlighted code blocks. **Source** and copy controls preserve access to the original text; large documents use bounded source pages.

**Context** shows an estimated input-token budget and lets you explicitly choose the first user turn included in future requests. Earlier messages and files remain in saved history; they are not silently discarded or summarized. It also sets **Maximum response tokens** (16–32768), applied when the model advertises `max_tokens` support and capped by a reported provider output limit. The default reserve is 2048 tokens, reduced for smaller context windows. An estimate exceeding the advertised context limit blocks submission; media estimates are approximate and cannot predict every provider's decoding cost. These settings persist with the conversation. **Continue answer** appears when a completed response reports `finish_reason: length`; it sends a new explicit continuation turn while preserving the existing answer and current composer draft.

**Add files** accepts UTF-8 text/source files up to 256 KiB on text-compatible models, including Markdown, JSON, YAML, JavaScript and C. Text files have local readable previews and are sent as named text content, without requiring a provider's native file capability. Where supported, the picker also accepts PNG/JPEG/WebP/GIF images, WAV/MP3 audio, MP4 video, and PDF with native file input. Shared limits are 4 files, 8 MiB each and 12 MiB total per message, with the smaller text-file limit applied separately. Text in the composer is optional for an attachment-only message. Draft and sent files persist as binary IndexedDB records with references from their conversation; streamed checkpoints do not rewrite unchanged files. File payloads never enter localStorage/sessionStorage recovery markers, diagnostics or the PWA cache. PDF requests explicitly disable paid parser fallback. See [the rendering guide](../file-rendering.md) for extensions, preview limits and source copying, and [the multimodal guide](../multimodal.md) for media price guards and provider limitations.

The navigation sidebar contains **New conversation**, searchable history, Diagnostics and Settings. History separates **Chats** from **Archived**. Archive keeps a conversation available to inspect and restore; permanent deletion is offered directly on archived rows without first selecting them or opening a confirmation dialog. Archived conversations are read-only until restored. History identifies each conversation by title, model, update time and message count. The composer shows **Unsaved changes**, **Saving…**, **Saved** or **Save failed**. **Export** saves a conversation and its attachments as a versioned JSON backup; **Import** opens a separate copy. Multiple tabs retain independent active conversations. Conflicting edits preserve both versions by saving a **Recovered copy**, with no automatic merge or overwrite. History remains browser-local, with no cloud sync. See [history.md](../history.md) for persistence, migration, capacity and recovery details.

Settings provides **System**, **Light** and **Dark** appearance choices, a session key, 100/125/150/200% text, deliberate offline mode, install where offered, and update checks. **Check allowance** explicitly retrieves the key's free-request allowance when the API reports it; no quota request is made at startup. Counts are advisory, stale observations are labeled, and health probes also consume inference requests. System is the initial appearance choice; an explicit preference persists locally. Both color schemes retain the muted neo-brutalist palette, readable borders and pastel popup headers. The model chooser, model details and diagnostics have distinct colored headings with small emoji cues and readable text labels.

The popup graphics are bundled [Twemoji v14.0.2](https://github.com/twitter/twemoji/tree/v14.0.2/assets/72x72) PNGs, credited to Twitter, Inc and contributors under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). They total 4,354 bytes and render offline without an emoji font or JavaScript library. Full attribution and the upstream license are in [the asset attribution](../../assets/emoji/ATTRIBUTION.md) and [upstream license](../../assets/emoji/LICENSE-GRAPHICS).

Diagnostics separates recorded errors from ordinary activity. Catalog entries reporting the observed `-1` unresolved-price marker are excluded from free selection rather than reported as broken schema entries; malformed prices still produce actionable errors. PWA inspections have a short summary with bounded expandable metadata; the inspection dialog retains its full Copy/Export report. Nothing in diagnostics is uploaded. API keys are redacted and prompts, answers, reasoning and upstream error bodies are omitted.

Readable application text is selectable across screens, dialogs, model information, history and tooltips. Drag to select with a pointer, or long-press text on touch screens, then use Copy or Ctrl/Command+C. Dialogs have their own selection scope, keeping Select all within the open dialog. Composer and other editable fields retain their usual selection, paste and keyboard shortcuts. The header subtitle is **Wrapper for Free Open Router Models**.
