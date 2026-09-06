#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/openlaunchpad-interactions.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT

mkdir -p "$test_dir/home" "$test_dir/module-cache"
developer_dir="${DEVELOPER_DIR:-$(xcode-select -p)}"
if [[ ! -d "$developer_dir/Platforms/MacOSX.platform" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    developer_dir=/Applications/Xcode.app/Contents/Developer
fi
if [[ ! -d "$developer_dir/Platforms/MacOSX.platform" ]]; then
    echo "Full Xcode is required. Set DEVELOPER_DIR to its Contents/Developer directory." >&2
    exit 1
fi
plugin_dir="$developer_dir/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins"
plugin_server="$developer_dir/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-plugin-server"
sources=()
for source in "$project_dir"/Launchpad/*.swift; do
    [[ "$(basename "$source")" == "LaunchpadApp.swift" ]] && continue
    sources+=("$source")
done

# Compile the production implementation with the app target's concurrency defaults.
# The scrollbar regression renders the real folder offscreen; no app is launched.
DEVELOPER_DIR="$developer_dir" xcrun swiftc \
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
