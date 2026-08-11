#!/usr/bin/env python3
"""Bump compileSdk/targetSdk in the generated Android project.

Several plugins (flutter_plugin_android_lifecycle, package_info_plus,
url_launcher_android, wakelock_plus, and desktop_drop's transitive
androidx.fragment/window/lifecycle/core dependencies) require compiling
against a recent API level. That required level has already moved once
during this project's life (33 -> 35 -> 36), so this value is kept as a
single constant that is easy to bump again later without touching the
regex logic below.

Flutter's own default template value can lag behind that requirement, which
fails the release build during Gradle's AAR-metadata check, e.g.:

    Dependency 'androidx.fragment:fragment:1.7.1' requires libraries and
    applications that depend on it to compile against version 36 or later.

This script is intentionally defensive: it tries both the Groovy
(`build.gradle`) and Kotlin DSL (`build.gradle.kts`) forms the Flutter
template may generate, and only warns (never fails the build) if neither
file matches the patterns it knows about, since the exact template text can
change between Flutter releases.
"""
from __future__ import annotations

import pathlib
import re
import sys

TARGET_SDK = 36


def patch(path: pathlib.Path) -> bool:
    if not path.exists():
        return False
    text = path.read_text()
    original = text

    # `compileSdk flutter.compileSdkVersion` (Groovy) or
    # `compileSdk = flutter.compileSdkVersion` (Kotlin DSL / newer Groovy).
    text = re.sub(r"compileSdk(\s*=?\s*)flutter\.compileSdkVersion", rf"compileSdk\g<1>{TARGET_SDK}", text)
    text = re.sub(
        r"compileSdkVersion(\s*=?\s*)flutter\.compileSdkVersion", rf"compileSdkVersion\g<1>{TARGET_SDK}", text
    )
    # Already-numeric but too-low values written by older Flutter templates
    # or by a previous run of this script targeting an older SDK level.
    text = re.sub(r"compileSdk(\s*=?\s*)\d{2}\b", rf"compileSdk\g<1>{TARGET_SDK}", text)
    text = re.sub(r"compileSdkVersion(\s*=?\s*)\d{2}\b", rf"compileSdkVersion\g<1>{TARGET_SDK}", text)

    text = re.sub(r"targetSdk(\s*=?\s*)flutter\.targetSdkVersion", rf"targetSdk\g<1>{TARGET_SDK}", text)
    text = re.sub(
        r"targetSdkVersion(\s*=?\s*)flutter\.targetSdkVersion", rf"targetSdkVersion\g<1>{TARGET_SDK}", text
    )

    if text != original:
        path.write_text(text)
        print(f"Patched {path}: compileSdk/targetSdk set to {TARGET_SDK}")
        return True
    print(f"No matching compileSdk/targetSdk pattern found in {path} (already OK or template changed)")
    return False


def main() -> None:
    candidates = [
        pathlib.Path("android/app/build.gradle.kts"),
        pathlib.Path("android/app/build.gradle"),
    ]
    patched_any = False
    for candidate in candidates:
        if patch(candidate):
            patched_any = True
    if not patched_any:
        print(
            "WARNING: could not find/patch a build.gradle(.kts) file for compileSdk/targetSdk. "
            "The generated Android project template may have changed; an AAR-metadata build "
            "failure about compileSdk may recur.",
            file=sys.stderr,
        )


if __name__ == "__main__":
    main()
