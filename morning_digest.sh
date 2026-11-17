#!/bin/bash
# Morning briefing: hands what the assistant kept quietly overnight (night-digest.txt, written by
# speak.py during quiet hours) to the voice thread of the assistant picked in the avatar's menu
# (persona.py), so the one whose voice and face are in use greets and sums it up aloud.
#
# Run every hour by the LaunchAgent local.voice-assistant.morning (if the Mac was asleep, launchd
# runs it at the next wake). Does nothing during quiet hours (quiet_hours.py, set in the avatar's
# menu), so the news goes out in the first hour after they end, and nothing when there is no news.
# Logs only the number of lines handed over, never the news itself.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
# This install's settings (names, the t3 command, the greeting). See assistant.conf.example.
# shellcheck source=/dev/null
[ -f "$HERE/assistant.conf" ] && source "$HERE/assistant.conf"
DIGEST="$HERE/night-digest.txt"
ID_FILE="$(/opt/homebrew/bin/python3 -I "$HERE/persona.py" get thread_file 2>/dev/null || true)"
[ -n "$ID_FILE" ] || ID_FILE="$HERE/voice-thread-id"
# The assistant in use may call the user differently (USER_CALL_KO in its persona.conf).
PERSONA_CALL="$(/opt/homebrew/bin/python3 -I "$HERE/persona.py" get USER_CALL_KO 2>/dev/null || true)"
[ -n "$PERSONA_CALL" ] && USER_CALL_KO="$PERSONA_CALL"
LOG="$HERE/voice.log"
T3="${T3_BIN:-$HOME/.local/bin/t3}"
HEADER="[아침 브리핑] 밤사이 조용히 받아 둔 소식이야. ${USER_CALL_KO:-사용자}한테 아침 인사와 함께 두세 문장으로 정리해서 알려 줘."

log() {
  printf '%s %s\n' "$(date +%FT%T)" "$1" >> "$LOG"
}

[ -s "$DIGEST" ] || exit 0
/opt/homebrew/bin/python3 -I "$HERE/quiet_hours.py" now && exit 0

thread_id="$(tr -d '[:space:]' < "$ID_FILE" 2>/dev/null)"
if [ -z "$thread_id" ]; then
  log "morning briefing skipped: no voice thread id"
  exit 1
fi

# Take the digest first, so news arriving meanwhile starts a fresh file.
pending="$DIGEST.sending"
mv "$DIGEST" "$pending"
lines="$(wc -l < "$pending" | tr -d ' ')"

if { printf '%s\n' "$HEADER"; cat "$pending"; } | "$T3" thread send "$thread_id" - >/dev/null 2>>"$LOG"; then
  rm -f "$pending"
  log "morning briefing sent with $lines lines"
  exit 0
fi

# Put the news back so tomorrow's briefing still has it.
cat "$pending" >> "$DIGEST"
rm -f "$pending"
log "morning briefing could not be sent, kept for next time"
exit 1
