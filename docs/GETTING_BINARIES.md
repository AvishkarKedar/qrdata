# How to get the actual .apk and Windows app

This assistant edits and commits the Flutter/Dart source code straight into this
repository, but the chat sandbox it runs in does not have the Flutter SDK,
Android SDK, or Windows build tools installed — so it cannot compile a real
`.apk` or `.exe` itself, and it has no way to trigger or download GitHub
Actions run artifacts on your behalf either. Use one of the two options below
to get the compiled binaries.

## Option A — Let GitHub Actions build it (recommended, zero local setup)

1. Every push to `main` runs `.github/workflows/flutter-ci.yml` automatically.
2. It first runs `flutter analyze` and `flutter test` (the `verify` job).
3. If that passes, two more jobs build real binaries on GitHub-hosted machines:
   - `build-android` → produces `qrdata-android-release-apk`
   - `build-windows` → produces `qrdata-windows-release`
4. On GitHub: open the repo → **Actions** tab → open the latest run for your
   commit → scroll to **Artifacts** at the bottom → download both zip files.
   - Unzip `qrdata-android-release-apk` and install the `.apk` on an Android
     phone (enable "Install unknown apps" for your file manager/browser).
   - Unzip `qrdata-windows-release` and run the `.exe` inside (Windows may
     show a SmartScreen warning for unsigned apps — choose "More info" →
     "Run anyway").
5. If a run shows a red X, open it and read the failing step's log — that
   tells you exactly what to fix (or ask this assistant to fix it).

## Option B — Build locally

```bash
git clone https://github.com/AvishkarKedar/qrdata.git
cd qrdata
flutter pub get
flutter build apk --release        # -> build/app/outputs/flutter-apk/app-release.apk
flutter build windows --release    # -> build/windows/x64/runner/Release/
```

Requirements: Flutter SDK, an Android SDK with an accepted license
(`ANDROID_HOME` set) for the APK, and Visual Studio Build Tools with the
"Desktop development with C++" workload for the Windows build.

## Note on signing

Both builds currently use Flutter's default debug signing config, which is
fine for installing/testing on your own devices but is not suitable for Play
Store submission or wide distribution. Ask the assistant to wire up a real
Android keystore (`key.properties` + `signingConfigs`) when you are ready to
distribute more broadly — you will need to generate and privately keep that
keystore yourself since it must never be committed to the repo.
