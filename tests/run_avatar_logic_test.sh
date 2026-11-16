#!/bin/bash
# Builds tests/avatar_logic_test.swift with the avatar's caption and sound-bar files and runs it.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT
# swiftc runs top-level code only from a file named main.swift.
ln -s "$HERE/tests/avatar_logic_test.swift" "$BUILD_DIR/main.swift"
swiftc -swift-version 5 "$BUILD_DIR/main.swift" "$HERE/avatar_captions.swift" "$HERE/avatar_meter.swift" "$HERE/avatar_nowplaying.swift" "$HERE/avatar_persona.swift" \
  -o "$BUILD_DIR/avatar_logic_test"
"$BUILD_DIR/avatar_logic_test"
