#!/usr/bin/env python3
"""Injects a release signingConfig into a freshly `flutter create`-generated
android/app/build.gradle, reading credentials from android/key.properties.

This only runs in CI, only when ANDROID_KEYSTORE_BASE64 (and related) secrets
are configured on the repository -- see docs/GETTING_BINARIES.md. It has not
been run against a real Flutter-generated build.gradle in this environment
(no local Flutter SDK here); it targets the standard Groovy build.gradle
template Flutter has used for the last several stable releases. If a future
Flutter version switches the default template to Kotlin DSL
(android/app/build.gradle.kts) or changes this snippet, this script will
simply find nothing to patch -- tell the assistant the exact error/diff and it
will be updated.
"""
import sys

PROPS_LOADER = """
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

"""

SIGNING_BLOCK = """signingConfigs {
        release {
            if (keystorePropertiesFile.exists()) {
                keyAlias keystoreProperties['keyAlias']
                keyPassword keystoreProperties['keyPassword']
                storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
                storePassword keystoreProperties['storePassword']
            }
        }
    }
    buildTypes {"""


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "android/app/build.gradle"
    try:
        with open(path, "r", encoding="utf-8") as f:
            src = f.read()
    except FileNotFoundError:
        print(f"::warning::{path} not found; skipping release signing patch (Flutter template may have changed).")
        return

    if "keystoreProperties" in src:
        print("Signing config already present; skipping.")
        return

    if "android {" not in src or "buildTypes {" not in src or "signingConfig signingConfigs.debug" not in src:
        print("::warning::Expected build.gradle markers not found; skipping release signing patch (Flutter template may have changed).")
        return

    src = src.replace("android {", PROPS_LOADER + "\nandroid {", 1)
    src = src.replace("buildTypes {", SIGNING_BLOCK, 1)
    src = src.replace("signingConfig signingConfigs.debug", "signingConfig keystorePropertiesFile.exists() ? signingConfigs.release : signingConfigs.debug")

    with open(path, "w", encoding="utf-8") as f:
        f.write(src)
    print("Patched build.gradle with release signing config.")


if __name__ == "__main__":
    main()
