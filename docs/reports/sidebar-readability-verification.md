# Sidebar and model readability verification — 2026-10-07

## Implemented behavior

The expanded history sidebar supports pointer/touch dragging and keyboard
arrows, Home/End limits and Enter reset. Its 240–440 logical-pixel preference
is saved at drag end; the current viewport and text scale can constrain the
rendered width without overwriting that preference. The inspector yields space
when necessary. Medium rails and compact drawers retain their distinct layouts.
Short or large-text drawers scroll so bottom utilities remain reachable.

Settings now offer 100%, 125%, 150% and 200% text. Conversation, selected model,
composer controller, draft, focus and active request remain owned outside the
adaptive branches. The repeated model-row hover instruction was removed while
metadata previews and explicit accessible details actions remain available.

Descriptions have no presentation line limit and retain up to the existing
40,000-character parser limit. Real OpenRouter catalog, single-model and endpoint
metadata returned the same 177-character Cohere North Mini Code description
ending `it is optimized...`. The app cannot recover missing source paragraphs.
It now explains an upstream ellipsis and supplies a selectable/copyable model
page URL, without scraping or adding application network calls. Other complete
descriptions render and scroll in full.

## Executed checks

| Check | Result |
|---|---|
| `make verify` | Formatting, analysis and repository check passed; 375 app/tool tests passed, one opt-in live test skipped |
| New deterministic regression coverage | 17 tests covering width persistence/clamps/invalid values, pointer and touch resize, keyboard/semantics, interrupted drags, fake active streams, 125% persistence, narrow/200% controls, full descriptions and source notices |
| `python3 -m unittest discover -s xops/makefile -p 'test_*.py' -v` | 14 passed |
| `make codeg` and `make codeg.check` | Passed, including actual MCP protocol checks; 136 files, 1,822 nodes, 7,479 edges |
| `make build.public` | Successful Flutter release/PWA build |
| Independent combined-change review | No concrete blockers found |

Release `b81654ef0fbe2265ce446ffd8752def3d2fb0d21be3f655668eb12cab35a4743`
contains 37 shell assets totaling **18,173,116 bytes**. The existing Cupertino
font-family warning remains nonfatal. No performance improvement is claimed.
Raw evidence is in ignored `outputs/readability-*.txt` and
`outputs/preference-green.txt`.

## Actual local release browser

The public release was served with:

```sh
dart run tool/serve.dart --port=8765 --directory=build/publish-web --isolated-config
```

Checks used an isolated `http://127.0.0.1:8765/` origin, with no configured key
or authenticated prompt submission. The actual browser loaded the live catalog
(17 chat models / 68 listings during this observation; not a test invariant).

- Pointer drag widened the sidebar; ArrowRight and Home/End adjusted and bounded
  it. A 440-pixel preference and the unsent test draft survived reload.
- 125% appeared and remained selected when Settings reopened.
- Live resize crossed expanded, medium and compact layouts. At measured DOM
  1000×1000 the medium rail appeared; at 320×740 and 200% text the drawer and
  scrolled Settings/Diagnostics remained reachable. The test browser's emulated
  dimensions differed from requested dimensions, so requested sizes are not
  represented as exact CSS sizes. Widget tests use exact layout constraints.
- The model chooser retained accessible details and omitted the repeated hint.
  The Cohere details dialog wrapped and scrolled at 320-pixel width/200% text,
  showing the upstream-source notice and complete model-page URL.

Multi-paragraph descriptions, parser bounds, clipboard content, touch gestures and
resize during an active request are additionally covered by deterministic tests;
the active response is a fake stream, not an authenticated live inference.
This slice does not claim a new native, offline-install, cross-browser, or
authenticated-chat acceptance run.
