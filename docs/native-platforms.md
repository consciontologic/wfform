# Native platform setup

Updated 2026-10-06 with Flutter 3.38.5 / Dart 3.10.4. Web/PWA remains the verified release target. Android and iOS host projects now record the user's requested application identifier; their presence does not establish native feature parity or a signed native release.

## Identifiers

| Purpose | Value | Configuration |
|---|---|---|
| Dart package/imports | `wfform` / `package:wfform/…` | [pubspec.yaml](../pubspec.yaml) |
| Android namespace/application ID | `com.wfform` | [app/build.gradle.kts](../android/app/build.gradle.kts) |
| Android activity package | `com.wfform` | [MainActivity.kt](../android/app/src/main/kotlin/com/wfform/MainActivity.kt) |
| iOS Runner bundle identifier | `com.wfform`, Debug/Profile/Release | [project.pbxproj](../ios/Runner.xcodeproj/project.pbxproj) |
| iOS test bundle | `com.wfform.RunnerTests` | Same Xcode project |
| Installed PWA identity | `./`, unchanged | [manifest.json](../web/manifest.json) |

`Info.plist` resolves `CFBundleIdentifier` from `PRODUCT_BUNDLE_IDENTIFIER`. The iOS Flutter embedded framework keeps its own generated framework identifier; it is not the Runner application ID. Both native display names are `wfform`.

The hosts were generated without overwriting application files using Flutter's `create` command with `--platforms=android,ios,web --org=com --project-name=wfform --no-pub .`. Flutter metadata retains all three platforms. Android's main manifest includes Internet permission for release networking as well as development builds. Re-running generation is not needed for normal development.

## Remaining native work

- Non-web history and preference adapters currently use memory. They do not provide the browser's durable history/settings behavior.
- Native attachment selection and file export need adapters. PWA install/update operations are browser features; the native bridge is a stub.
- Loading `config/local.json` is web-only; it is not bundled into native assets. Non-web startup uses typed defaults and existing `API_BASE_URL`/`API_KEY` Dart defines; Settings can accept a key, but the native LocalStore is an in-memory stub; durable native credential/configuration storage still needs a platform implementation. Browser key persistence is verified separately.
- Native launcher PNGs use the approved soft W-wrapper artwork, generated alongside the PWA icons by `tool/icons.dart`. Android provides transparent default/night resources. The iOS catalog retains legacy sizes and includes universal Any/Dark entries: the default artwork uses an opaque lavender-tinted surface, while the dark variant has transparent interiors. These source variants have not been validated in Xcode or on an Android/iOS device. Splash assets and Android debug signing remain development defaults. iOS has no configured signing team. Matching launcher artwork does not establish native builds, store signing or device acceptance.

On this Linux workstation, `flutter doctor -v` reports unaccepted Android SDK licenses. No license acceptance or system changes were made. iOS requires macOS and Xcode. Neither APK/AAB nor iOS builds/device runs were executed; the native configuration was checked structurally and reviewed separately.

For future native validation, after the required toolchain and adapters are ready, start from this repository and use `flutter pub get`, `flutter doctor -v`, `flutter devices`, then `flutter run -d <device-id>`. Android packaging uses `flutter build apk`; an iOS simulator build uses `flutter build ios --simulator` on macOS. These are follow-up commands, not claims of checks executed here. The [README](../README.md) documents the verified web workflow.

Official references checked 2026-10-06: [Flutter Android deployment](https://docs.flutter.dev/deployment/android) and [Flutter iOS deployment](https://docs.flutter.dev/deployment/ios).
