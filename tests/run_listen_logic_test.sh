#!/bin/bash
# Builds tests/listen_transcript_test.swift with the listener's transcript logic and runs it.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT
# swiftc runs top-level code only from a file named main.swift.
ln -s "$HERE/tests/listen_transcript_test.swift" "$BUILD_DIR/main.swift"
swiftc -swift-version 5 "$BUILD_DIR/main.swift" "$HERE/listen_transcript.swift" -o "$BUILD_DIR/listen_logic_test"
"$BUILD_DIR/listen_logic_test"
