---
name: 'wfform Flutter application'
description: 'Application boundaries and preserved behavior'
applyTo: 'lib/**,test/**,pubspec.yaml,web/**'
---

# Flutter application

- UI and application logic are Flutter/Dart. Keep transport, DTO parsing,
  domain controllers and widgets separate; use small existing interfaces.
- Model eligibility uses validated prices, never suffix-only or missing-as-zero
  inference. Unresolved charges exclude affected routes or capabilities.
- Render Markdown and source as selectable content, never execute code or HTML.
  Bound parsing/highlighting and preserve original text for copying.
- Preserve history IDs, archives, attachments, drafts and partial responses.
  Changes to stored formats need backward-compatible reads and tests.
- Responsive breakpoints must preserve focus, draft, selection and in-flight
  requests. Keep narrow screens and 200% text usable.
- PWA release identity is content-derived. Never manually patch compiled output;
  rebuild via `make build` and use the safe update flow.
