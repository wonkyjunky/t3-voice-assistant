#!/bin/bash
# Build AssistantAvatar.app from assistant_avatar.swift. The app has no Dock icon (LSUIElement).
# talk.sh starts it during a conversation with avatar.png.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

APP="$HERE/AssistantAvatar.app"
BIN_NAME="assistant_avatar"
IDENTIFIER="local.voice-assistant.avatar"

mkdir -p "$APP/Contents/MacOS"
# The caption bubbles, sound bars, menu, keyboard shortcut and now-playing card live in their own files. swiftc runs top-level code only from
# a file named main.swift, so assistant_avatar.swift is linked in under that name.
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT
ln -s "$HERE/assistant_avatar.swift" "$BUILD_DIR/main.swift"
swiftc -O -swift-version 5 "$BUILD_DIR/main.swift" avatar_captions.swift avatar_meter.swift avatar_menu.swift avatar_hotkey.swift avatar_nowplaying.swift avatar_nowplaying_card.swift avatar_marquee.swift \
  -o "$APP/Contents/MacOS/$BIN_NAME"
cp assistant_avatar-Info.plist "$APP/Contents/Info.plist"
"$HERE/sign_app.sh" "$APP" "$IDENTIFIER"

echo "built $APP"
