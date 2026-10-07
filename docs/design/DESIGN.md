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
| Expanded, 1100 and above | Persistent history sidebar with utilities at its bottom; optional model panel from 1420. |

Text scaling can select a less dense arrangement. Controllers and focus nodes survive layout transitions. New conversation, model changes and history switches are guarded while a response/history transition is active. Model details use text labels, focus/pointer previews and explicit information actions; no essential information depends solely on hover.

The composer grows over several lines and clears when a valid send is accepted. A next draft can be written while the answer streams. Explicit retry reuses the failed user turn; edit/resend appends a revised copy. Returned reasoning is separate and collapsible. Context exclusions and continuation are explicit actions, preserving earlier records.

History offers current and archived views, search, restore, export/import and confirmed permanent deletion of archived records. Conflicting tabs preserve separate recovered copies. The interface reports save status and keeps in-memory work if storage fails.

## Visual and content design

The visual system uses low-saturation neutral/pastel surfaces, strong readable borders, restrained offset shadows and local typography. System/Light/Dark modes keep the same hierarchy. Diagnostics, model information and model selection have distinct colored headings and local emoji graphics with textual labels. There is one Diagnostics navigation action and Settings directly beneath it in persistent navigation.

Readable application text is selectable. Bounded local preview and Markdown/code rendering extend this principle; their precise formats and fallbacks are specified in [file-rendering.md](../file-rendering.md). Rendering content never executes source code or expands model upload capabilities implicitly.

The product mark encloses a conversation bubble in brackets, representing a wrapper around model conversations. It is decorative next to the selectable wfform name, uses theme colors, and is shared conceptually with the generated PWA/favicon artwork. The small static About document uses the same palette to provide readable product information before launching Flutter and to search crawlers.

## Resilience and trade-offs

- Exact price validation and zero-price routing guards favor safe exclusion when an applicable charge is unconfirmed. This may omit a router that could sometimes choose a free model.
- Recent health is useful admission information, but an additional selected-model probe consumes a request and cannot guarantee the subsequent request.
- Browser-local IndexedDB avoids a backend and enables offline history; it does not synchronize devices, and site-data clearing can remove history. Export/import provides an explicit portable copy.
- Normalized history storage reduces unchanged-media serialization. It adds a versioned codec and transactional migration path that require dedicated tests.
- A custom content-addressed PWA worker supports verified offline shells and stable updates. Minimal JavaScript glue must be tested alongside the Dart release assembler.

## Active extension and acceptance

The current follow-up adds search/sharing metadata, a static product document, GitHub web publishing and the wrapper/conversation logo. Earlier workspace, CodeGraph, container, rendering and native-identity phases remain recorded in the roadmap. See [SEO](../seo.md), [CI/CD](../guides/CI_CD.md) and the [Docker guide](../guides/DOCKER.md) for hosting boundaries.

Acceptance requires changed behavior tests, formatting/analysis, a release PWA build and real browser checks for the changed path. Header configuration can be verified directly; external scanner ratings must not be invented. Existing verification records retain their dates and cannot certify a newer release automatically.
