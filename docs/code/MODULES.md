# Module maintenance

Use [architecture](ARCHITECTURE.md) for ownership. Change the narrow adapter/controller
that owns behavior, with a regression in its corresponding test area.

| Change | Contract | Tests |
|---|---|---|
| Catalog pricing/schema/cache | [Catalog](../catalog.md) | `test/models/catalog_test.dart` |
| Health, streaming, context/retry | [Chat](../chat.md) | `test/chat/`, `test/models/health*_test.dart` |
| Parameters and MCP | [Tools](../tools.md) | `test/parameters/`, `test/tools/`, `test/chat/` |
| Local process/MCP lifecycle | [Companion](../wfformcomp.md) | `companion/test/` |
| Text/source previews | [Rendering](../file-rendering.md) | `test/documents/`, `test/presentation/document_rendering_test.dart` |
| History | [History](../history.md) | `test/history/` and real Chromium checks |
| Layout/focus/accessibility | [Design](../design/DESIGN.md) | `test/presentation/` |
| PWA/assets/release | [PWA](../pwa.md), [CI/CD](../guides/CI_CD.md) | `test/shared/pwa_*`, `test/deploy/`, `xops/makefile/test_*.py` |

## History

Keep atomic migrations, binary-media reuse and optimistic revision checks together.
A read-only snapshot may finish once validated data arrives; writes/deletes wait for
transaction commit. A conflict creates a recovered copy instead of overwriting data.

Maintain explicit price guards and input bounds at domain boundaries, independent of
UI disabling. Refresh CodeGraph after structural changes. Deterministic tests cannot
establish browser storage, native process cleanup or live provider compatibility.
