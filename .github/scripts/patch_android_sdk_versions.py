#!/usr/bin/env python3
"""Bump compileSdk/targetSdk in the generated Android project.

Several plugins (e.g. desktop_drop's transitive androidx.fragment/window/
lifecycle dependencies) now require compiling against API level 34+.
Flutter's own default template value can lag behind that requirement, which
fails the release build during Gradle's AAR-metadata check:

    Dependency 'androidx.fragment:fragment:1.7.1' requires libraries and
    applications that depend on it to compile against version 34 or later.

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

TARGET_SDK = 35


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
    # Already-numeric but too-low values written by older Flutter templates.
    text = re.sub(r"compileSdk(\s*=?\s*)3[0-3]\b", rf"compileSdk\g<1>{TARGET_SDK}", text)
    text = re.sub(r"compileSdkVersion(\s*=?\s*)3[0-3]\b", rf"compileSdkVersion\g<1>{TARGET_SDK}", text)

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
