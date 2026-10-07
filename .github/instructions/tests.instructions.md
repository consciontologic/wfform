---
name: 'wfform tests'
description: 'Deterministic Flutter, Dart and deployment regression checks'
applyTo: 'test/**,tool/**,xops/test/**'
---

# Test authoring

- Write a failing regression before new behavior; preserve existing assertions.
- Flutter tests live under `test/`, using `flutter_test`, fake transport,
  deterministic clocks and fake storage. Run `make test` and `make analyze`.
- Test parsing, request construction, cancellation, limits and migration paths
  at their owning layer. Widget tests must exercise controls and clipboard
  behavior rather than merely count wrapper widgets.
- Keep real OpenRouter requests opt-in and bounded; do not put secrets or
  live model counts in fixtures. Never automatically retry user content.
- Real Chromium storage tests are separate from the default VM suite. State
  exactly which browser and platform were exercised.
- Docker checks must inspect real HTTP headers and container behavior when
  Docker is available. Do not claim a scanner grade without a scanner result.
- Repository/tool tests use Dart or the existing scaffold test tooling. Do not
  add a second application stack.
- Use `xops/agent/safe-run.sh` for long commands and diagnose a failed log before
  retrying. Only the parent updates tracking and stages combined work.

Full procedure and tracking rows: [test-driven-development skill](../../.agents/skills/test-driven-development/SKILL.md).
