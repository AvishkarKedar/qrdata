#!/usr/bin/env python3
"""Bump compileSdk/targetSdk for the whole generated Android project.

This fixes two DIFFERENT failure modes that both show up as a Gradle
"checkReleaseAarMetadata" error, because they need two different fixes:

1. `:app:checkReleaseAarMetadata` fails because plugins ship precompiled
   AARs (flutter_plugin_android_lifecycle, package_info_plus,
   url_launcher_android, wakelock_plus, ...) whose metadata declares a
   minimum compileSdk our *app* module must also use. Fixed by
   `patch_app_module()` below, which edits android/app/build.gradle(.kts).

2. `:desktop_drop:checkReleaseAarMetadata` (or any other *source* plugin
   module) fails on its OWN compilation, independent of whatever the app
   module is set to. Some plugins (desktop_drop is a known case) hardcode
   their own, older `compileSdkVersion` directly in their own
   android/build.gradle instead of inheriting the app's value, so bumping
   only the app module does nothing for them. The only fix that reaches a
   plugin's own build file (which lives in the pub cache, not this repo)
   is to force every Gradle subproject's compileSdk from the *root*
   android/build.gradle(.kts). That is what `append_root_override()` does.

   Flutter's own generated root build file contains a line like
   `subprojects { project.evaluationDependsOn(":app") }`, which forces the
   ":app" subproject to fully evaluate immediately, before the rest of the
   root script (including our appended override, which runs later in the
   same file) finishes running. That means by the time our override's
   `subprojects { ... }` block reaches ":app", it may already be evaluated,
   and calling `afterEvaluate` on an already-evaluated project throws
   "Cannot run Project.afterEvaluate(Action) when the project is already
   evaluated." The override below checks each subproject's evaluation
   state and applies the compileSdk override immediately when it's already
   evaluated, or via afterEvaluate otherwise, so it is safe regardless of
   evaluation order.

Both patchers are defensive: they only warn (never fail the build) if the
files/patterns they expect are not found, since the exact template text can
change between Flutter releases.
"""
from __future__ import annotations

import pathlib
import re
import sys

TARGET_SDK = 36

MARKER = "patch_android_sdk_versions.py"

KOTLIN_ROOT_OVERRIDE = f"""

// --- Added by .github/scripts/{MARKER} ---
// Some third-party plugins (e.g. desktop_drop) hardcode their own, lower
// compileSdk in their own android/build.gradle instead of inheriting the
// app's setting, so Gradle's AAR-metadata check can fail for that plugin's
// own module even though our app module is configured correctly. Forcing
// every subproject to compile against the same SDK level here overrides any
// outdated value a plugin author left behind. Some subprojects (notably
// ":app", via this file's own `evaluationDependsOn(":app")` line above) may
// already be evaluated by the time this runs, so apply immediately in that
// case instead of scheduling afterEvaluate (which would throw).
subprojects {{
    val applyOverride: () -> Unit = {{
        extensions.findByName("android")?.let {{ ext ->
            (ext as? com.android.build.gradle.BaseExtension)?.compileSdkVersion({TARGET_SDK})
        }}
    }}
    if (state.executed) {{
        applyOverride()
    }} else {{
        afterEvaluate {{ applyOverride() }}
    }}
}}
"""

GROOVY_ROOT_OVERRIDE = f"""

// --- Added by .github/scripts/{MARKER} ---
// See the Kotlin DSL branch of this script for the full explanation: some
// plugins hardcode their own outdated compileSdk, and some subprojects
// (notably ":app") may already be evaluated by the time this runs, so this
// applies immediately in that case instead of scheduling afterEvaluate
// (which would throw "already evaluated").
subprojects {{ proj ->
    def applyOverride = {{
        if (proj.hasProperty('android')) {{
            proj.android {{
                compileSdkVersion {TARGET_SDK}
            }}
        }}
    }}
    if (proj.state.executed) {{
        applyOverride()
    }} else {{
        proj.afterEvaluate {{ applyOverride() }}
    }}
}}
"""


def patch_app_module(path: pathlib.Path) -> bool:
    if not path.exists():
        return False
    text = path.read_text()
    original = text

    text = re.sub(r"compileSdk(\s*=?\s*)flutter\.compileSdkVersion", rf"compileSdk\g<1>{TARGET_SDK}", text)
    text = re.sub(
        r"compileSdkVersion(\s*=?\s*)flutter\.compileSdkVersion", rf"compileSdkVersion\g<1>{TARGET_SDK}", text
    )
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


def append_root_override(path: pathlib.Path, snippet: str) -> bool:
    if not path.exists():
        return False
    text = path.read_text()
    if MARKER in text:
        print(f"{path} already has the subprojects compileSdk override; skipping")
        return True
    path.write_text(text + snippet)
    print(f"Appended subprojects compileSdk={TARGET_SDK} override to {path}")
    return True


def main() -> None:
    app_candidates = [
        pathlib.Path("android/app/build.gradle.kts"),
        pathlib.Path("android/app/build.gradle"),
    ]
    patched_app = False
    for candidate in app_candidates:
        if patch_app_module(candidate):
            patched_app = True
    if not patched_app:
        print(
            "WARNING: could not find/patch android/app/build.gradle(.kts) for compileSdk/targetSdk.",
            file=sys.stderr,
        )

    root_kts = pathlib.Path("android/build.gradle.kts")
    root_groovy = pathlib.Path("android/build.gradle")
    patched_root = False
    if root_kts.exists():
        patched_root = append_root_override(root_kts, KOTLIN_ROOT_OVERRIDE)
    elif root_groovy.exists():
        patched_root = append_root_override(root_groovy, GROOVY_ROOT_OVERRIDE)
    if not patched_root:
        print(
            "WARNING: could not find android/build.gradle(.kts) to add the subprojects compileSdk "
            "override; plugins with their own hardcoded compileSdk may still fail their own AAR "
            "metadata check.",
            file=sys.stderr,
        )


if __name__ == "__main__":
    main()
