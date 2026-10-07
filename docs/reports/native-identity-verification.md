# Native identity clarification verification

Date: 2026-10-06. Workspace: /home/serhatakbak/code/projects/wfform. Flutter 3.38.5 / Dart 3.10.4. This follows the user's clarification that `com.wfform` means Android/iOS application identity, superseding the prior Dart-package interpretation. Existing staged application/scaffold work was preserved. No commit or push was made.

## Implemented

- Dart package/imports: `wfform` / `package:wfform/…`.
- Actual Android host: namespace and application ID `com.wfform`, matching Kotlin activity package/path, main Internet permission.
- Actual iOS host: Runner `com.wfform` in Debug/Profile/Release; distinct `com.wfform.RunnerTests` test bundles. Display name `wfform`.
- Flutter metadata retains web, Android and iOS. PWA manifest/storage identity is unchanged. Existing tracked application files, except metadata, remained byte-identical during host generation; only missing platform files were generated without `--overwrite`.
- [Native platform guide](../native-platforms.md), active project context and architecture now distinguish host configuration from native feature parity.

## Executed checks

Commands below ran from the workspace. Build/test gates used `xops/agent/safe-run.sh`; logs are in the ignored `outputs/native-identity-*.txt` files.

| Check | Result |
|---|---|
| `flutter pub get` | Passed; locked dependency versions unchanged |
| `make verify` | Formatting and analysis passed; 321 deterministic Flutter tests passed, one opt-in live test skipped; repository key/ignore checks passed |
| `python3 work/check_native_identity.py` | Passed Android IDs/activity/permission, all three iOS Runner/test configurations, Dart imports, metadata/PWA identity, and XML parsing for 18 native host files |
| Independent read-only native configuration review | Identity and package/path checks passed; debug signing and native feature limits recorded |
| `CHROME_EXECUTABLE=/home/serhatakbak/.cache/ms-playwright/chromium-1243/chrome-linux64/chrome flutter test --platform chrome test/history/browser/indexeddb_checks.dart --reporter expanded` | Six real Chromium IndexedDB checks passed using disposable fixture databases |
| `make build` | Release web build passed; 34 shell assets, 18,150,857 bytes |
| `make image` and `TLS=1 make restart` | Container build and replacement passed |
| `make tls.check` | nginx config, HTTP/HTTPS health, enforced headers, no-store config, WASM MIME and SHA-256 verification of all 34 assets passed |
| `xops/agent/codegraph.sh index .` and `make codeg.check` | Fresh index: 124 files, 1,707 nodes, 6,810 edges. Real stdio initialization, eight tools, Dart search/exploration/caller relationships and ignored-file exclusions passed |
| `flutter doctor -v` | Toolchain inspected; Android licenses unaccepted; iOS build requires macOS/Xcode |

The release build prints an existing optional CupertinoIcons font-family warning; compilation completes successfully. No dependency was added to address an unused font family. The Wasm dry run succeeded; no Wasm browser acceptance is claimed.

Dart-host release: `d3801a35556ef386f98714b0cff3f11a804c06050ec37aebebc18fac74ba88e0`.
nginx release: `4b3d54e8402c9e12ddefd340d7a91d25935a1fe51aa29060dc72077e2507c23c`.

In the running browser at `http://localhost:8080/`, Settings detected the new release and **Save & update** loaded the matching nginx release ID. The existing fixture conversation, selected model and four unsent attachment records were retained, with storage shown as Saved. This was an actual PWA update check using an existing local fixture; no live inference was sent. Screenshot: `native-identity-browser.png` in the original chat workspace's outputs directory.

## Verification boundaries

Native APK/AAB/iOS compilation, signing and device tests were not executed. Android SDK license acceptance and macOS/Xcode are environmental prerequisites. Memory-based non-web storage, unsupported native file picking/export and generated development signing/artwork still require a separate native port. The Flutter-generated iOS example test is not an executed acceptance test.

No authenticated live chat was sent for this identifier change. Deterministic test results do not imply live provider availability. The real Chromium storage tests use fixtures, not user conversations. HTTPS checks trust the project's localhost certificate for the command-line check; no browser certificate warning was bypassed and no external header grade is claimed.
