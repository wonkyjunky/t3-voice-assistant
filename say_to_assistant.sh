#!/bin/bash
# Send what Siri or a shortcut heard to the assistant's thread in T3 Code, then wait for the spoken reply.
#
# Called by the Shortcuts "Run Shell Script" action with the dictated text on standard input
# (stdin keeps the text out of the shell, so nothing the user says can run as a command).
# The reply is read aloud by the assistant instance's Stop hook (speak.py). This script waits
# until that speech has finished, so a shortcut that repeats Dictate Text and this script
# takes turns instead of hearing the assistant's own voice.
#
# Output on standard output: the word STOP when the conversation should end (an end word,
# nothing heard, or an error), and nothing at all otherwise. The shortcut leaves its repeat
# loop when the shell script result "has any value", because Shortcuts offers no text
# comparison for this result.
#
# The target thread id is kept in voice-thread-id. This script never creates a thread: if the
# id is missing or the send fails, it says so out loud and stops, so the words always go to
# the one thread the user chose or nowhere.
#
# Test overrides: T3_BIN (a stand-in for the t3 command), VOICE_DIR (where the id file and log
# live), SPEAK_LOG (speak.py's log), REPLY_START_WAIT and REPLY_END_WAIT (seconds), and
# ASSISTANT_QUIET=1 (do not speak anything).

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
# This install's settings (names, the t3 command, the greeting). See assistant.conf.example.
# shellcheck source=/dev/null
[ -f "$HERE/assistant.conf" ] && source "$HERE/assistant.conf"
VOICE_DIR="${VOICE_DIR:-$HERE}"
T3="${T3_BIN:-$HOME/.local/bin/t3}"
ID_FILE="$VOICE_DIR/voice-thread-id"
# Each assistant (persona.py, picked in the avatar's menu) talks in its own thread. A VOICE_DIR
# given from outside (the tests) keeps its own voice-thread-id.
if [ "$VOICE_DIR" = "$HERE" ]; then
  PERSONA_ID_FILE="$(/opt/homebrew/bin/python3 -I "$HERE/persona.py" get thread_file 2>/dev/null || true)"
  [ -n "$PERSONA_ID_FILE" ] && ID_FILE="$PERSONA_ID_FILE"
fi
LOG="$VOICE_DIR/voice.log"
SPEAK_LOG="${SPEAK_LOG:-$HERE/speak.log}"

REPLY_START_WAIT="${REPLY_START_WAIT:-90}"
REPLY_END_WAIT="${REPLY_END_WAIT:-90}"
POLL_SECONDS=0.1
POLLS_PER_SECOND=10
END_WORDS='^(끝|종료|그만|그만해|대화 종료|대화 끝|잘 가|잘가|안녕히 계세요)$'
# Natural ways to end the talk, matched anywhere in a short utterance. Each one names the talk
# itself (얘기, 이야기, 대화, 말) or is a plain goodbye, so a message like "그 작업 그만하자고 전해 줘"
# still goes to the assistant. Anything subtler is left to the assistant, who closes with [end_conversation].
END_PHRASES='그만 ?(얘기|이야기|말)|대화 ?(그만|끝|종료)|(나중에|이따가?|다음에) ?(얘기|이야기|말)(하자|해요|할게)|이제 됐어(요)?$|수고했어(요)?|잘 ?자(요)?$'
END_PHRASE_MAX_CHARS=25
# The same in English (the listener also understands English), as the whole utterance, any case.
END_WORDS_EN="^(bye|bye bye|goodbye|good bye|stop|that's all|that is all|see you|see you later|good night)$"
# speak.py writes the time here when the assistant ends its reply with [end_conversation].
END_FLAG="$HERE/conversation-end"
# Dictate Text can hand back the previous words again when nothing new was said. The same words
# arriving again inside this window count as silence. Only a hash and a time are kept on disk.
REPEAT_WINDOW_SECONDS="${REPEAT_WINDOW_SECONDS:-90}"
LAST_FILE="$VOICE_DIR/last-sent"
# What the user said, for the caption bubble next to the avatar. Only the user can read it, and it is removed
# when this turn is over (the avatar keeps the words on screen a few seconds from memory).
CAPTION_FILE="$VOICE_DIR/caption-user.txt"

log() {
  printf '%s %s\n' "$(date +%FT%T)" "$1" >> "$LOG"
}

# Fixed phrases in the assistant's voice, made once and kept by voice.py (Yuna if that is impossible).
say_phrase() {
  printf '%s' "$1" | /opt/homebrew/bin/python3 -I "$HERE/voice.py" phrase >/dev/null 2>&1
}

speak_now() {
  [ "${ASSISTANT_QUIET:-0}" = "1" ] && return 0
  say_phrase "$1"
}

speak_error() {
  [ "${ASSISTANT_QUIET:-0}" = "1" ] && return 0
  say_phrase "$1" &
}

count_speech_starts() {
  [ -f "$SPEAK_LOG" ] || { echo 0; return; }
  grep -cE "say started|speech started" "$SPEAK_LOG"
}

# The assistant is speaking while voice.py's player (named in speaking.pid) or a say process runs.
speech_playing() {
  local marker_pid
  marker_pid="$(cat "$HERE/speaking.pid" 2>/dev/null || true)"
  if [ -n "$marker_pid" ] && kill -0 "$marker_pid" 2>/dev/null; then
    return 0
  fi
  speech_queued && return 0
  pgrep -x say >/dev/null 2>&1
}

# voice.py lists each speech that plays or waits for its turn in speech-queue/ (files named
# "<pid>-..."). A report from another thread arriving mid-answer waits there, so the assistant is still
# speaking until it has played too.
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

# Wait for the Stop hook to start speaking, then for the speech to end.
wait_for_reply_speech() {
  local before="$1" waited=0
  while [ "$(count_speech_starts)" -le "$before" ]; do
    sleep "$POLL_SECONDS"
    waited=$((waited + 1))
    [ "$waited" -ge $((REPLY_START_WAIT * POLLS_PER_SECOND)) ] && { log "no spoken reply within ${REPLY_START_WAIT}s"; return; }
  done
  waited=0
  while speech_playing; do
    sleep "$POLL_SECONDS"
    waited=$((waited + 1))
    [ "$waited" -ge $((REPLY_END_WAIT * POLLS_PER_SECOND)) ] && { log "reply speech still running after ${REPLY_END_WAIT}s"; return; }
  done
}

raw="$(cat)"
# Dictation can arrive in decomposed Hangul (NFD); compose it so end words and thread text match.
composed="$(printf '%s' "$raw" | iconv -f UTF-8-MAC -t UTF-8 2>/dev/null || printf '%s' "$raw")"
text="$(printf '%s' "$composed" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

if [ -z "$text" ]; then
  log "nothing heard, conversation ends"
  echo STOP
  exit 0
fi

( umask 077 && printf '%s' "$text" > "$CAPTION_FILE.tmp" && mv -f "$CAPTION_FILE.tmp" "$CAPTION_FILE" )
trap 'rm -f "$CAPTION_FILE"' EXIT

bare="$(printf '%s' "$text" | sed -e 's/[[:punct:]]*$//')"
if printf '%s' "$bare" | grep -Eiq "$END_WORDS_EN"; then
  log "end word heard, conversation ends"
  speak_now "[warmly] ${PHRASE_GOODBYE_EN:-Okay, talk to you later!}"
  echo STOP
  exit 0
fi
if printf '%s' "$bare" | grep -Eq "$END_WORDS" \
  || { [ "${#bare}" -le "$END_PHRASE_MAX_CHARS" ] && printf '%s' "$bare" | grep -Eq "$END_PHRASES"; }; then
  log "end word heard, conversation ends"
  speak_now "[warmly] ${PHRASE_GOODBYE:-알겠어요, 또 불러 주세요!}"
  echo STOP
  exit 0
fi

text_hash="$(printf '%s' "$text" | shasum -a 256 | cut -d' ' -f1)"
now="$(date +%s)"
if [ -s "$LAST_FILE" ]; then
  read -r last_time last_hash < "$LAST_FILE"
  if [ "${last_hash:-}" = "$text_hash" ] && [ $((now - ${last_time:-0})) -lt "$REPEAT_WINDOW_SECONDS" ]; then
    log "same words again within ${REPEAT_WINDOW_SECONDS}s, treated as silence, conversation ends"
    echo STOP
    exit 0
  fi
fi

thread_id=""
[ -s "$ID_FILE" ] && thread_id="$(tr -d '[:space:]' < "$ID_FILE")"
if [ -z "$thread_id" ]; then
  log "no thread id in $ID_FILE, nothing sent"
  speak_error "[apologetically] ${PHRASE_NO_THREAD:-죄송해요, 보낼 스레드가 정해져 있지 않아요}"
  echo STOP
  exit 1
fi

speech_starts_before="$(count_speech_starts)"
sent_at="$(date +%s)"
if ! printf '%s' "$text" | "$T3" thread send "$thread_id" - >/dev/null 2>>"$LOG"; then
  log "could not send to thread ${thread_id:0:8}"
  speak_error "[apologetically] ${PHRASE_SEND_FAILED:-죄송해요, 메시지를 전하지 못했어요}"
  echo STOP
  exit 1
fi

printf '%s %s\n' "$now" "$text_hash" > "$LAST_FILE"
log "sent ${#text} characters to thread ${thread_id:0:8}"
wait_for_reply_speech "$speech_starts_before"
if [ -f "$END_FLAG" ] && [ "$(cat "$END_FLAG" 2>/dev/null || echo 0)" -ge "$sent_at" ]; then
  rm -f "$END_FLAG"
  log "the assistant closed the conversation"
  echo STOP
fi
exit 0
