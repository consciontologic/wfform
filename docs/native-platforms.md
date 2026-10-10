# Native platform status

Web/PWA is the application release target. Android/iOS host projects are configured,
but native adapters, signed builds and device acceptance remain pending.

| Identity | Value |
|---|---|
| Dart package/imports | `wfform` / `package:wfform/…` |
| Android namespace/application ID | `com.wfform` |
| Android activity package | `com.wfform` |
| iOS Runner bundle ID | `com.wfform` |
| iOS tests | `com.wfform.RunnerTests` |
| PWA manifest ID | `./` (preserved) |

Configuration lives in [Android Gradle](../android/app/build.gradle.kts),
[Xcode project](../ios/Runner.xcodeproj/project.pbxproj) and [manifest](../web/manifest.json).
Do not regenerate hosts for ordinary development.

## Remaining work

- Replace non-web in-memory history/preferences with durable native adapters.
- Add native file picking/export and durable credential/config storage. Browser
  `config/local.json` loading and PWA operations are not native implementations.
- Complete Android toolchain/license/signing and iOS macOS/Xcode/signing setup.
- Validate launcher artwork, transparent appearance variants and store acceptance;
  generated icons alone do not establish native support.
- Run the app on actual devices and verify storage, files, networking and lifecycle.

After those prerequisites, use `flutter doctor -v`, `flutter devices` and
`flutter run -d <device-id>`; Android packaging uses `flutter build apk`, iOS simulator
builds use `flutter build ios --simulator` on macOS. These are future checks, not
claims of completed native releases.

## Desktop companion versus a native Flutter app

[wfformcomp](wfformcomp.md) is a separate Linux/Windows executable serving the existing
web UI and configured local tools. Its native process tests do not prove Flutter
Windows/Linux UI parity. Graphical installers and the macOS companion remain planned.
