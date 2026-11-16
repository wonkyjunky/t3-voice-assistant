#!/bin/bash
# Removes what install.sh set up outside this folder: the LaunchAgents and the running avatar.
#   ./uninstall.sh            LaunchAgents and avatar only
#   ./uninstall.sh --all      also the ElevenLabs key and the signing keychain
# Your files in this folder (assistant.conf, memory notes, videos) stay. Delete the folder yourself.

set -uo pipefail

for label in local.voice-assistant.morning local.voice-assistant.credit local.voice-assistant.avatar; do
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null
  rm -f "$HOME/Library/LaunchAgents/$label.plist"
  echo "removed $label"
done
pkill -x assistant_avatar 2>/dev/null

if [ "${1:-}" = "--all" ]; then
  security delete-generic-password -s voice-assistant-elevenlabs >/dev/null 2>&1 && echo "removed the ElevenLabs key from the Keychain"
  security delete-keychain "$HOME/Library/Keychains/voice-assistant-signing.keychain-db" 2>/dev/null && echo "removed the signing keychain"
  security delete-generic-password -s voice-assistant-signing-keychain >/dev/null 2>&1 && echo "removed the signing keychain password"
fi
echo "T3 Code의 비서 공급자 인스턴스와 단축어는 직접 지우세요."
