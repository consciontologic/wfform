# Project charter

**wfform — Wrapper for Free Open Router Models** lets individuals discover free
OpenRouter models, understand capabilities and maintain browser-local conversations
using their own key.

## Commitments

- Flutter/Dart application UI and logic; direct structured API access, no backend or
  inference proxy. Static web/PWA hosting and optional local companion stay separate.
- Exact free-price validation, explicit model choice, zero-price provider guards and
  no paid fallback or automatic resend.
- Preserve drafts, received output, local history and explicit recovery choices.
- Accessible selectable content and adaptive layouts, including large text.
- An installable offline shell with explicit saved-state updates; inference still
  requires connectivity.
- Optional desktop tools with connection selection and approval before execution.
- Bounded, useful diagnostics without credentials or conversation content.

Browser-local data may be cleared or evicted; export is the portable backup.
Advertised model capability is not proof a provider accepts every file. Web success
does not establish native builds, browser parity or graphical installers.

[AGENTS.md](../../AGENTS.md) owns operating policy, [architecture](../code/ARCHITECTURE.md)
owns implementation boundaries, and the [roadmap](../planning/ROADMAP.md) owns planned
work and acceptance. Keep runnable behavior, matching tests and current guides together;
report live/browser/native evidence separately from mocks.
