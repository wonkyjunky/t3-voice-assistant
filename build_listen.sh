#!/bin/bash
# Build AssistantListen.app from assistant_listen.swift. For a status check run:
#   open -W -a AssistantListen.app --stdout /dev/stdout --args --check
#
# The app has no Dock icon (LSUIElement). talk.sh starts it with `open`, so macOS treats
# it as its own app and asks for microphone and speech permission by its name.
# sign_app.sh signs it with the local identity from make_signing_identity.sh, so macOS keeps those
# permissions across rebuilds (without that identity it signs ad hoc and macOS asks again).

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

APP="$HERE/AssistantListen.app"
BIN_NAME="assistant_listen"
PLIST="assistant_listen-Info.plist"
IDENTIFIER="local.voice-assistant.listen"

mkdir -p "$APP/Contents/MacOS"
# What was heard across pauses is kept by listen_transcript.swift. swiftc runs top-level code only
# from a file named main.swift, so assistant_listen.swift is linked in under that name.
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT
ln -s "$HERE/assistant_listen.swift" "$BUILD_DIR/main.swift"
swiftc -O -swift-version 5 "$BUILD_DIR/main.swift" listen_transcript.swift listen_channel.swift -o "$APP/Contents/MacOS/$BIN_NAME" \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$PLIST"
cp "$PLIST" "$APP/Contents/Info.plist"
"$HERE/sign_app.sh" "$APP" "$IDENTIFIER"

echo "built $APP"
