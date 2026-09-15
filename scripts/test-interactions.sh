#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/openlaunchpad-interactions.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT

mkdir -p "$test_dir/home" "$test_dir/module-cache"
developer_dir="${DEVELOPER_DIR:-$(xcode-select -p)}"
if [[ ! -d "$developer_dir/Platforms/MacOSX.platform" && ! -d "$developer_dir/SDKs" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    developer_dir=/Applications/Xcode.app/Contents/Developer
fi
if ! DEVELOPER_DIR="$developer_dir" xcrun swiftc --version > "$test_dir/swift-version" 2>&1; then
    if [[ -d /Library/Developer/CommandLineTools && "$developer_dir" != /Library/Developer/CommandLineTools ]]; then
        developer_dir=/Library/Developer/CommandLineTools
    fi
fi
if ! DEVELOPER_DIR="$developer_dir" xcrun swiftc --version > "$test_dir/swift-version" 2>&1; then
    cat "$test_dir/swift-version" >&2
    echo "A working Xcode or Command Line Tools Swift toolchain is required." >&2
    exit 1
fi
if [[ -d "$developer_dir/Platforms/MacOSX.platform" ]]; then
    plugin_dir="$developer_dir/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins"
    plugin_server="$developer_dir/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-plugin-server"
else
    plugin_dir="$developer_dir/usr/lib/swift/host/plugins"
    plugin_server="$developer_dir/usr/bin/swift-plugin-server"
fi
sdk_path="${SDKROOT:-$(DEVELOPER_DIR="$developer_dir" xcrun --show-sdk-path)}"
# CLT's macOS 27 SDK requires SwiftUI macros only shipped with full Xcode.
# The app targets macOS 26; use its installed SDK when running with CLT alone.
if [[ ! -f "$plugin_dir/libSwiftUIMacros.dylib" && -z "${SDKROOT:-}" && -d "$developer_dir/SDKs/MacOSX26.5.sdk" ]]; then
    sdk_path="$developer_dir/SDKs/MacOSX26.5.sdk"
fi
sources=()
for source in "$project_dir"/Launchpad/*.swift; do
    [[ "$(basename "$source")" == "LaunchpadApp.swift" ]] && continue
    sources+=("$source")
done

# Compile the production implementation with the app target's concurrency defaults.
# The scrollbar regression renders the real folder offscreen; no app is launched.
DEVELOPER_DIR="$developer_dir" xcrun swiftc \
    -sdk "$sdk_path" \
    -parse-as-library \
    -swift-version 5 \
    -default-isolation MainActor \
    -enable-upcoming-feature NonisolatedNonsendingByDefault \
    -enable-upcoming-feature InferIsolatedConformances \
    -enable-upcoming-feature InferSendableFromCaptures \
    -module-cache-path "$test_dir/module-cache" \
    -external-plugin-path "$plugin_dir#$plugin_server" \
    "${sources[@]}" \
    "$project_dir"/Tests/*.swift \
    -o "$test_dir/interaction-tests"

# Isolate Foundation preferences and icon caches from the user's application data.
CFFIXED_USER_HOME="$test_dir/home" "$test_dir/interaction-tests" -AppleShowScrollBars Always
