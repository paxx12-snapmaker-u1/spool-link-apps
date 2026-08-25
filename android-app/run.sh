#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-PackageHomePage: https://github.com/paxx12-snapmaker-u1/spool-link
# SPDX-FileCopyrightText: Copyright (c) 2026 @paxx12

set -euo pipefail

PACKAGE_NAME="dev.pages.paxx12.spoollink"
MAIN_ACTIVITY="$PACKAGE_NAME/.MainActivity"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SDK_DIR=""
GRADLE_VERSION="8.10.2"
GRADLE_HOME="$ROOT_DIR/.gradle/gradle-$GRADLE_VERSION"
GRADLE_BIN="$GRADLE_HOME/bin/gradle"

for sdk_dir in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$HOME/Library/Android/sdk" "/opt/android-sdk"; do
    if [[ -n "$sdk_dir" && -d "$sdk_dir/platform-tools" ]]; then
        SDK_DIR="$sdk_dir"
        break
    fi
done

if [[ -z "$SDK_DIR" ]]; then
    echo "Android SDK not found. Set ANDROID_HOME or ANDROID_SDK_ROOT." >&2
    exit 1
fi

export PATH="$GRADLE_HOME/bin:$SDK_DIR/platform-tools:$PATH"

if [[ -x "/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/java" ]]; then
    export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
fi

if ! adb version >/dev/null 2>&1; then
    echo "adb not found in PATH. Set ANDROID_HOME/ANDROID_SDK_ROOT or install Android platform-tools." >&2
    exit 1
fi

if [[ ! -x "$GRADLE_BIN" ]]; then
    mkdir -p "$ROOT_DIR/.gradle"
    ZIP="$ROOT_DIR/.gradle/gradle-$GRADLE_VERSION-bin.zip"
    URL="https://services.gradle.org/distributions/gradle-$GRADLE_VERSION-bin.zip"
    echo "Downloading Gradle $GRADLE_VERSION..."
    curl -fL "$URL" -o "$ZIP"
    unzip -q "$ZIP" -d "$ROOT_DIR/.gradle"
fi

export ANDROID_HOME="$SDK_DIR"
export ANDROID_SDK_ROOT="$SDK_DIR"

# AGP's Maven-hosted aapt2 is x86_64-only; on non-x86_64 hosts (e.g. aarch64 Linux)
# fall back to the native aapt2 shipped in the local SDK's build-tools instead.
GRADLE_ARGS=()
if [[ "$(uname -m)" != "x86_64" ]]; then
    LOCAL_AAPT2="$(find "$SDK_DIR/build-tools" -maxdepth 2 -name aapt2 -type f 2>/dev/null | sort -V | tail -n1)"
    if [[ -x "$LOCAL_AAPT2" ]]; then
        GRADLE_ARGS+=("-Pandroid.aapt2FromMavenOverride=$LOCAL_AAPT2")
    fi
fi

"$GRADLE_BIN" -p "$ROOT_DIR" "${GRADLE_ARGS[@]}" :app:installDebug
adb shell am start -n "$MAIN_ACTIVITY"
sleep 1
adb shell pidof "$PACKAGE_NAME" >/dev/null

echo "Launched $PACKAGE_NAME."
