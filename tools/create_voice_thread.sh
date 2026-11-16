#!/bin/bash
# tools/create_voice_thread.sh PROJECT
#
# Starts the assistant's voice thread in T3 Code (on ASSISTANT_INSTANCE and ASSISTANT_MODEL from
# assistant.conf) inside the T3 project PROJECT (a project id or a folder of a project you opened
# in T3), and saves its id in voice-thread-id. An existing id is kept in voice-thread-id.previous.
# T3 Code must be running.

set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "$HERE/assistant.conf"
ID_FILE="$HERE/voice-thread-id"
UUID='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'

if [ $# -ne 1 ]; then
  sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
fi

output="$("$T3_BIN" thread start --provider "$ASSISTANT_INSTANCE" --model "$ASSISTANT_MODEL" \
  --title "$ASSISTANT_NAME_KO" "$1" "처음 인사해 줘.")"
thread_id="$(printf '%s\n' "$output" | grep -Eo "$UUID" | head -1 || true)"
if [ -z "$thread_id" ]; then
  echo "create_voice_thread: T3 did not print a thread id:" >&2
  printf '%s\n' "$output" >&2
  exit 1
fi
[ -f "$ID_FILE" ] && cp "$ID_FILE" "$ID_FILE.previous"
printf '%s\n' "$thread_id" > "$ID_FILE"
echo "voice thread $thread_id saved in $ID_FILE"
