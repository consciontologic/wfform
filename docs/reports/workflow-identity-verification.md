# Workflow and identity verification

Verified 2026-10-06 in `/home/serhatakbak/code/projects/wfform` with Flutter 3.38.5 / Dart 3.10.4. This report covers the single Makefile, CodeGraph, Settings gear and package-name follow-up. The existing staged project baseline was preserved; no commit or push was performed.

## Changes

1. **One root Makefile.** Merged `Makefile.app.mk` into `Makefile` and removed the duplicate. Existing help, default target and dry-run output across all 26 existing non-help targets matched before/after. The new `make codeg.check` target adds reproducible live verification.
2. **CodeGraph enabled.** Pinned `@colbymchenry/codegraph@1.6.2` through the repository-local launcher. npm packages stay under ignored `.local/codegraph/npm-cache/`; the graph stays under ignored `.codegraph/`. No global installation or user configuration change. Native Codex and portable MCP definitions target the same repository and enable the same eight tools; the VS Code server map is empty to avoid duplicate definitions. Active instructions and guides supersede the earlier MCP opt-out. See [MCP setup](../guides/MCP_SETUP.md).
3. **Settings gear.** Replaced the palette header emoji with ⚙️ using a bundled Twemoji gear PNG for reliable color/offline rendering. Attribution was updated. Existing Settings controls and theme preferences were preserved.
4. **Dart package `com_wfform`.** Renamed the pubspec package and all 33 importing test/tool files. Dart forbids dots in package names, so literal `com.wfform` cannot be used there. It is documented as the requested native application identifier if native targets are later added; this web-only repository has no Android/Apple identifier field. PWA identity, origin and storage/cache keys are unchanged. See [identity explanation and official sources](../pwa.md).

## Executed verification

| Check | Result |
|---|---|
| `flutter pub get` | Passed; renamed package resolves in generated package configuration; lockfile unchanged |
| `make verify` | Formatting and analysis clean; **321 deterministic Flutter tests passed**, **1 opt-in live API test skipped**; repository key scan passed |
| Settings regression coverage | Expected red failures before implementation; green in full suite afterward. Bundled gear decoding/mapping, light/dark popups at 320px/200% text and existing theme/draft behavior are covered |
| `python3 -m unittest discover -s xops/makefile -p 'test_*.py' -v` | **13 tests passed**: 8 CodeGraph launcher/config/dispatcher checks and 5 existing Git-operation tests |
| `make codeg` and full CodeGraph reindex | Completed; **112 files, 88 Dart files, 1,684 nodes, 6,797 edges**, zero pending changes at final inspection |
| `make codeg.check` | Real MCP initialization, eight-tool discovery, status/search/explore/callers/files succeeded; Dart `ChatController` and `send` relationships resolved; ignored configuration/cache/build/scratch paths absent |
| Actual Chromium IndexedDB suite | **6 passed**, including migration, retained binary data, incremental writes, conflict recovery and rollback |
| `make build` and `make image` | Both release builds passed; **34 shell assets, 18,150,861 uncompressed bytes** |
| `TLS=1 make restart` then `make tls.check` | Container healthy; HTTP/HTTPS header, cache, MIME and SHA-256 checks passed for all 34 assets |
| Config/whitespace/docs checks | Bash syntax, five Codex TOMLs, two MCP JSON files, local documentation links and diff whitespace passed |

The actual Chromium command was:

```bash
CHROME_EXECUTABLE=/home/serhatakbak/.cache/ms-playwright/chromium-1243/chrome-linux64/chrome \
  flutter test --platform chrome test/history/browser/indexeddb_checks.dart --reporter expanded
```

The tests use disposable databases; the deterministic Flutter suite uses fake network transports where appropriate. CodeGraph checks launched a real local server through the committed configuration rather than mocking the protocol.

## Release-browser evidence

The existing `http://localhost:8080/` tab received the new release through **Save & update**. It reopened with the same selected model, local fixture conversation and four draft attachments. Settings visibly renders the gear in its header, with no warning/error console entries observed after activation. The screenshot `wfform-settings-gear.png` is saved in the original chat's outputs directory. No prompt or attachment was sent to OpenRouter during this follow-up.

- Dart-host release: `751ec580ccd2db26211a426d0796226a748cd3db9ef59ebe51475e4b773b1280`.
- nginx release: `d1abc923fe0f584f0f5e7517b4553e11146261cae21c90d03e0a3aa8b4cb7de7`.

The differing hashes include the container's policy stamp. The pre-existing Flutter build warning about an optional Cupertino font remains; the build completed and the actual Settings graphic uses its bundled PNG. No rendering failure was observed in the changed surface.

## Commands and client boundary

```bash
cd /home/serhatakbak/code/projects/wfform
make help
make codeg
make codeg.check
make verify
make image
make up
```

For this already-running TLS configuration, use `TLS=1 make restart` after building a new image. `make tls.check` validates HTTP and the local-certificate HTTPS endpoint.

This chat did not gain newly injected native MCP tools merely because configuration changed. **Reopen the canonical repository/session or restart its MCP server** to load the new client configuration. Real stdio MCP and CLI graph access were verified independently and are working now. The graph supports source navigation but cannot guarantee complete dynamic call resolution.

`com.wfform` remains a requested future native ID, not an implemented Android/iOS package. There are no new native targets. No fresh live inference, public TLS grade, OS-level PWA installation or offline-disconnection test is claimed in this follow-up; previous dated reports retain their scope.

Raw logs are in ignored `outputs/workflow-*.txt` and `outputs/codegraph-*.txt`. User-facing report, Settings screenshot and selected verification logs are also copied to the original chat's outputs directory. The development key remains ignored and excluded from staged files and the image.
