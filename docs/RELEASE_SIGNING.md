# Real release signing (Android)

By default the Android APK is signed with Flutter's debug key, which is fine
for installing on your own devices but not for distributing widely or
publishing to the Play Store. This repo cannot generate or hold your signing
keystore for you -- a release keystore is a long-lived secret only you should
control. Set it up once, yourself, as follows.

## 1. Generate a keystore (one time, on your own machine)

```bash
keytool -genkey -v -keystore release-keystore.jks -keyalg RSA -keysize 2048 \
  -validity 10000 -alias qrdata
```

This asks for a store password, a key password, and identity details, then
writes `release-keystore.jks`. Keep this file and both passwords private and
backed up -- if you lose them you cannot publish updates to an app already
installed under the same signature.

## 2. Add it to GitHub Actions as encrypted secrets

In the repo: **Settings -> Secrets and variables -> Actions -> New repository
secret**, add each of:

| Secret name | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | output of `base64 -w0 release-keystore.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | the store password you chose |
| `ANDROID_KEY_PASSWORD` | the key password you chose |
| `ANDROID_KEY_ALIAS` | `qrdata` (or whatever alias you used) |

## 3. What happens automatically after that

The `build-android` CI job already contains a signing step
(`.github/workflows/flutter-ci.yml` + `.github/scripts/patch_android_signing.py`)
that is a no-op until these secrets exist. Once they exist, every CI build:

1. Decodes the keystore secret back into a `.jks` file inside the (ephemeral,
   never committed) `android/app/` folder.
2. Writes a matching `android/key.properties` (also ephemeral, git-ignored).
3. Patches the freshly generated `android/app/build.gradle` to add a
   `signingConfigs.release` block and use it for release builds.
4. Builds the APK, now signed with your real key instead of the debug key.

No source changes are needed from you beyond adding the four secrets above.

## Caveat

This patch step targets Flutter's current Groovy `build.gradle` template. It
has not been run against a live `flutter create` output in this environment
(no Flutter SDK is available here to verify it). If a CI run shows the patch
step printing a `::warning::` and the APK ends up unsigned, or the Android
build.gradle format has changed to Kotlin DSL, tell the assistant the exact
CI log output and it will adjust the script.
