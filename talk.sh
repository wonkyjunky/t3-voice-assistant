#!/bin/bash
# Hands-free conversation with the assistant, with no window on screen.
#
# Started by the voice shortcut (Run Shell Script, one line: this file). The first turn
# opens with a short spoken greeting, later turns with a short cue sound. Each turn listens
# once with AssistantListen.app and hands the words to say_to_assistant.sh, which sends them to
# The assistant's thread and waits until the spoken reply has finished. The conversation ends on an
# end word, on silence, after MAX_TURNS, or when the shortcut is run again during a conversation.
#
# The listener runs as its own app through `open`, because macOS kills it for missing permission
# texts when it is started directly from the shortcut's shell (see assistant_listen.swift).
#
# Logs only turn counts, statuses and why listening ended to voice.log, never the words.
# Test overrides: VOICE_DIR, LISTEN_BIN (run a listener directly instead of the app),
# SEND_SCRIPT, ASSISTANT_GREETING, ASSISTANT_QUIET=1 (no greeting, cue or spoken errors).

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
# This install's settings (names, the t3 command, the greeting). See assistant.conf.example.
# shellcheck source=/dev/null
[ -f "$HERE/assistant.conf" ] && source "$HERE/assistant.conf"
# The assistant picked in the avatar's menu (persona.py) may change some of them, and keeps its
# own voice cache.
PERSONA_DIR="$(/opt/homebrew/bin/python3 -I "$HERE/persona.py" get dir 2>/dev/null || true)"
PERSONA_DIR="${PERSONA_DIR:-$HERE}"
# shellcheck source=/dev/null
[ -f "$PERSONA_DIR/persona.conf" ] && source "$PERSONA_DIR/persona.conf"
VOICE_DIR="${VOICE_DIR:-$HERE}"
LISTEN_APP="$HERE/AssistantListen.app"
SEND="${SEND_SCRIPT:-$HERE/say_to_assistant.sh}"
LOG="$VOICE_DIR/voice.log"
LOCK_DIR="$VOICE_DIR/talk.lock"
AVATAR_APP="$HERE/AssistantAvatar.app"
STATE_FILE="$VOICE_DIR/talk.state"

MAX_TURNS=30
GREETING="${ASSISTANT_GREETING:-${USER_CALL_KO:+$USER_CALL_KO, }${GREETING:-불렀어?}}"
VOICE_SCRIPT="$HERE/voice.py"
PYTHON=/opt/homebrew/bin/python3
# The greeting is made once in the assistant's voice and kept, so it costs nothing after the first time.
GREETING_AUDIO="$PERSONA_DIR/voice_cache/greeting.mp3"
GREETING_TEXT_FILE="$PERSONA_DIR/voice_cache/greeting.txt"
# Voice tag for the greeting audio (ElevenLabs acts it out; the Yuna fallback never sees it).
GREETING_TAG="${ASSISTANT_GREETING_TAG-[cheerfully]}"
GREETING_SPOKEN="${GREETING_TAG:+$GREETING_TAG }$GREETING"
# Siri's listening tone, chosen by the user. It lives in a private framework and may vanish in a
# macOS update, so the plain system sound is the fallback.
SIRI_BEGIN_SOUND=/System/Library/PrivateFrameworks/AssistantServices.framework/Versions/A/Resources/siri-begin-improved.caf
FALLBACK_CUE_SOUND=/System/Library/Sounds/Tink.aiff
# The assistant's own cue: an ElevenLabs sound effect ("futuristic AI assistant waking up to listen"),
# chosen by the user. Replace this file to change it; no rebuild needed.
ASSISTANT_CUE="$HERE/sounds/cue.caf"
CUE_SOUND="${ASSISTANT_CUE_SOUND:-$ASSISTANT_CUE}"
[ -f "$CUE_SOUND" ] || CUE_SOUND="$SIRI_BEGIN_SOUND"
[ -f "$CUE_SOUND" ] || CUE_SOUND="$FALLBACK_CUE_SOUND"
FOLLOW_UP_SAY="${ASSISTANT_FOLLOW_UP_SAY:-}"
PERMISSION_DENIED_STATUS=2
# The listener's last line reads like "assistant_listen: +1234ms status=0".
STATUS_PATTERN='^assistant_listen: \+[0-9]+ms status='

log() {
  printf '%s %s\n' "$(date +%FT%T)" "$1" >> "$LOG"
}

quiet() {
  [ "${ASSISTANT_QUIET:-0}" = "1" ]
}

# Fixed phrases in the assistant's voice, made once and kept by voice.py (Yuna if that is impossible).
speak_error() {
  quiet && return 0
  printf '%s' "$1" | "$PYTHON" -I "$VOICE_SCRIPT" phrase >/dev/null 2>&1 &
}

# Whose turn it is, for the floating avatar: "listening" or "replying". One word, never the words said.
set_state() {
  printf '%s\n' "$1" > "$STATE_FILE"
}

# The avatar stays on screen after the conversation. Opening it while it runs does nothing.
start_avatar() {
  quiet && return 0
  [ -d "$AVATAR_APP" ] || return 0
  /usr/bin/open -g -a "$AVATAR_APP" 2>>"$LOG"
}

# Without a state file the avatar shows its idle look.
clear_state() {
  rm -f "$STATE_FILE"
}

# The greeting as a caption bubble next to the avatar while it plays (voice.py writes the same
# file for its replies). Only the user can read it; it is removed once listening starts.
BOT_CAPTION="$VOICE_DIR/caption-bot.txt"
show_greeting_caption() {
  quiet && return 0
  ( umask 077 && printf '%s' "$GREETING" > "$BOT_CAPTION.tmp" && mv -f "$BOT_CAPTION.tmp" "$BOT_CAPTION" )
}

clear_greeting_caption() {
  [ "$(cat "$BOT_CAPTION" 2>/dev/null)" = "$GREETING" ] && rm -f "$BOT_CAPTION"
  return 0
}

# Words the listener showed while the user talked, and how loud the voice was, for the sound bars.
clear_listen_files() {
  rm -f "$VOICE_DIR/caption-user.txt" "$VOICE_DIR/level-user.txt"
}

# Music playing in the Music app or in a YouTube tab in Chrome is turned down while the
# conversation runs, so the microphone hears the user and the user hears the assistant, and turned back up when it
# ends. Only the player's own volume changes, never the system volume. Does nothing when nothing
# plays. YouTube is lowered in the background: asking Chrome can take seconds (or show a
# permission prompt) and must not delay the greeting. Restoring YouTube touches Chrome only when
# a tab was actually lowered.
MAC_CONTROL="$HERE/mac_control.py"
lower_music() {
  quiet && return 0
  "$PYTHON" -I "$MAC_CONTROL" music duck >/dev/null 2>>"$LOG"
  "$PYTHON" -I "$MAC_CONTROL" youtube duck >/dev/null 2>>"$LOG" &
}

restore_music() {
  quiet && return 0
  "$PYTHON" -I "$MAC_CONTROL" music unduck >/dev/null 2>>"$LOG"
  "$PYTHON" -I "$MAC_CONTROL" youtube unduck >/dev/null 2>>"$LOG"
}

# The listener plays the cue itself once the microphone is open, so the speaker can talk the
# moment it ends: the spoken greeting on the first turn, then a short phrase or sound.
# Sets the global array cue_args.
greeting_audio_ready() {
  [ -s "$GREETING_AUDIO" ] && [ "$(cat "$GREETING_TEXT_FILE" 2>/dev/null)" = "$GREETING_SPOKEN" ]
}

# Makes the greeting audio when it is missing or the greeting text changed. Falls back to Yuna.
prepare_greeting_audio() {
  quiet && return 0
  greeting_audio_ready && return 0
  mkdir -p "$(dirname "$GREETING_AUDIO")"
  if printf '%s' "$GREETING_SPOKEN" | "$PYTHON" -I "$VOICE_SCRIPT" save "$GREETING_AUDIO.tmp" 2>>"$LOG"; then
    mv "$GREETING_AUDIO.tmp" "$GREETING_AUDIO"
    printf '%s' "$GREETING_SPOKEN" > "$GREETING_TEXT_FILE"
    log "greeting audio made in the assistant's voice"
  else
    rm -f "$GREETING_AUDIO.tmp"
    log "greeting audio could not be made, using the Yuna voice"
  fi
}

set_cue_args() {
  cue_args=()
  quiet && return 0
  if [ "$1" -eq 1 ] && [ "$FOLLOW_UP" -eq 1 ] && [ -f "$CUE_SOUND" ]; then
    cue_args=(--sound "$CUE_SOUND")
  elif [ "$1" -eq 1 ] && greeting_audio_ready; then
    cue_args=(--sound "$GREETING_AUDIO")
  elif [ "$1" -eq 1 ]; then
    cue_args=(--say "$GREETING")
  elif [ -n "$FOLLOW_UP_SAY" ]; then
    cue_args=(--say "$FOLLOW_UP_SAY")
  elif [ -f "$CUE_SOUND" ]; then
    cue_args=(--sound "$CUE_SOUND")
  fi
}

# Sets the globals heard and status.
listen_once() {
  if [ -n "${LISTEN_BIN:-}" ]; then
    heard="$("$LISTEN_BIN" ${cue_args[@]+"${cue_args[@]}"} 2>>"$LOG")"
    status=$?
    return
  fi
  local work
  if ! work="$(mktemp -d)"; then
    status=1
    return
  fi
  /usr/bin/open -W -n -g -a "$LISTEN_APP" --stdout "$work/out" --stderr "$work/err" \
    --args ${cue_args[@]+"${cue_args[@]}"} 2>>"$LOG"
  heard="$(cat "$work/out" 2>/dev/null)"
  status="$(sed -nE "s/${STATUS_PATTERN}//p" "$work/err" 2>/dev/null | tail -1)"
  grep -vE "${STATUS_PATTERN}" "$work/err" >> "$LOG" 2>/dev/null
  rm -rf "$work"
  [ -n "$status" ] || status=1
}

speech_playing() {
  local marker_pid
  marker_pid="$(cat "$HERE/speaking.pid" 2>/dev/null || true)"
  [ -n "$marker_pid" ] && kill -0 "$marker_pid" 2>/dev/null && return 0
  speech_queued
}

# voice.py lists each speech that plays or waits for its turn in speech-queue/ (files named
# "<pid>-..."); stopping the assistant then also drops what was waiting.
speech_queued() {
  local entry pid
  for entry in "$HERE"/speech-queue/*; do
    [ -e "$entry" ] || continue
    pid="${entry##*/}"
    pid="${pid%%-*}"
    kill -0 "$pid" 2>/dev/null && return 0
  done
  return 1
}

# Running the shortcut again (or clicking the avatar) during a conversation: while the assistant is
# speaking it only cuts the speech off, and the conversation goes straight on to listening; otherwise
# it ends the conversation.
stop_running_conversation() {
  local old_pid
  old_pid="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
  [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null || return 1
  if speech_playing; then
    "$PYTHON" -I "$VOICE_SCRIPT" stop 2>>"$LOG"
    log "speech interrupted, conversation goes on"
    return 0
  fi
  if follow_up_still_waiting; then
    end_conversation "$old_pid"
    wait_for_exit "$old_pid"
    log "shortcut during follow-up listening: listening starts over"
    RESTART_FOLLOW_UP=1
    return 1
  fi
  end_conversation "$old_pid"
  "$PYTHON" -I "$VOICE_SCRIPT" stop 2>>"$LOG"
  log "conversation stopped by running the shortcut again"
  return 0
}

end_conversation() {
  pkill -P "$1" 2>/dev/null
  kill "$1" 2>/dev/null
  pkill -x assistant_listen 2>/dev/null
}

wait_for_exit() {
  local polls=0
  while kill -0 "$1" 2>/dev/null && [ "$polls" -lt "$OLD_EXIT_WAIT_POLLS" ]; do
    sleep 0.1
    polls=$((polls + 1))
  done
}

# A follow-up opens the microphone on its own after the assistant spoke. When the user presses the
# shortcut (or clicks the avatar) before saying anything, they want to talk, so listening starts
# over with the cue and a full wait instead of the conversation ending under them.
follow_up_still_waiting() {
  [ -f "$FOLLOW_UP_WAITING" ] && [ ! -s "$VOICE_DIR/caption-user.txt" ]
}

# --follow-up: started by voice.py after the assistant read out a reply on its own. No greeting, and it
# never touches a conversation that is already going on.
FOLLOW_UP=0
[ "${1:-}" = "--follow-up" ] && FOLLOW_UP=1
RESTART_FOLLOW_UP=0
FOLLOW_UP_WAITING="$LOCK_DIR/follow-up-waiting"
OLD_EXIT_WAIT_POLLS=30

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  running_pid="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
  if [ "$FOLLOW_UP" -eq 1 ] && [ -n "$running_pid" ] && kill -0 "$running_pid" 2>/dev/null; then
    exit 0
  fi
  stop_running_conversation && exit 0
  if [ "$RESTART_FOLLOW_UP" -eq 1 ]; then
    FOLLOW_UP=1
    mkdir "$LOCK_DIR" 2>/dev/null || true
  else
    log "removed a stale conversation lock"
  fi
fi
echo $$ > "$LOCK_DIR/pid"
[ "$FOLLOW_UP" -eq 1 ] && : > "$FOLLOW_UP_WAITING"
trap 'restore_music; clear_state; clear_greeting_caption; clear_listen_files; rm -f "$LOCK_DIR/pid" "$FOLLOW_UP_WAITING"; rmdir "$LOCK_DIR" 2>/dev/null' EXIT
trap 'exit 0' TERM INT

if [ "$FOLLOW_UP" -eq 1 ]; then log "follow-up conversation started"; else log "conversation started"; fi
set_state listening
start_avatar
lower_music
prepare_greeting_audio
for turn in $(seq 1 "$MAX_TURNS"); do
  set_cue_args "$turn"
  # First turn: "waking" until the listener starts the greeting sound, which it marks "greeting"
  # so the greeting video starts in step with the recorded voice; then it marks "listening".
  if [ "$turn" -eq 1 ] && [ "$FOLLOW_UP" -eq 0 ] && ! quiet; then set_state waking; else set_state listening; fi
  [ "$turn" -eq 1 ] && [ "$FOLLOW_UP" -eq 0 ] && show_greeting_caption
  listen_once
  rm -f "$FOLLOW_UP_WAITING"
  clear_greeting_caption
  set_state replying
  if [ "$status" -ne 0 ]; then
    log "listener failed with status $status on turn $turn"
    if [ "$status" -eq "$PERMISSION_DENIED_STATUS" ]; then
      speak_error "[apologetically] ${PHRASE_NO_PERMISSION:-마이크나 음성 인식 권한이 필요해요}"
    else
      speak_error "[apologetically] ${PHRASE_LISTEN_FAILED:-죄송해요, 듣기를 시작하지 못했어요}"
    fi
    exit 1
  fi
  result="$(printf '%s' "$heard" | "$SEND")"
  if [ -n "$result" ]; then
    log "conversation ended on turn $turn"
    exit 0
  fi
done
log "conversation ended after $MAX_TURNS turns"
