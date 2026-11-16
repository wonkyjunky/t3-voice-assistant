#!/usr/bin/env python3
"""Speak the assistant's last reply aloud in the assistant's voice (voice.py: ElevenLabs, Yuna as fallback).

Runs as a Claude Code Stop hook, enabled only for the assistant instance through the
`--settings assistant-settings.json` launch argument, so other Claude threads stay silent.
Reads the hook payload from stdin, finds the last assistant text in the
transcript, cleans it for speech, and hands it to voice.py in the background.
Only replies to spoken messages (sent by say_to_assistant.sh) and automatic notices are spoken;
a reply to a message typed in the T3 chat stays in the chat.

Usage: speak.py [--dry]   (--dry prints the cleaned text instead of speaking)
"""
import hashlib
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime

RETRY_COUNT = 6
RETRY_DELAY_SECONDS = 0.5

# Claude Code writes each session's transcript under its config directory; refuse anything else.
ALLOWED_ROOT = os.path.realpath(os.path.expanduser("~/.claude/projects"))
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import assistant_config  # noqa: E402  (this install's settings in assistant.conf)
LOG_PATH = os.path.join(HERE, "speak.log")
VOICE_SCRIPT = os.path.join(HERE, "voice.py")
VOICE_THREAD_FILE = os.path.join(HERE, "voice-thread-id")
# say_to_assistant.sh writes "<time> <sha256>" here for each message it sends by voice. A reply to
# any other message the user wrote (typed in the T3 chat) is only shown there, not spoken.
VOICE_SENT_PATH = os.path.join(HERE, "voice-sent")
VOICE_SENT_MAX_AGE_SECONDS = 30 * 60
THREAD_SUFFIX_CHARS = 8
# The assistant ends a reply with this when the user wants to stop talking. It is not spoken; it tells
# the voice conversation (say_to_assistant.sh) to stop listening.
END_TAG = "[end_conversation]"
# Cleaning for speech drops underscores, so also accept [endconversation], any case or spacing.
END_TAG_PATTERN = re.compile(r"\[\s*end[\s_]*conversation\s*\]", re.IGNORECASE)
END_FLAG_PATH = os.path.join(HERE, "conversation-end")
# Quiet hours: outside a voice conversation, replies are not spoken but kept for the morning
# briefing (morning_digest.sh, run at 12:00 by the LaunchAgent local.voice-assistant.morning).
QUIET_START_HOUR = 23
QUIET_END_HOUR = 12
DIGEST_PATH = os.path.join(HERE, "night-digest.txt")
CONVERSATION_LOCK_PID = os.path.join(HERE, "talk.lock", "pid")
VOICE_TAG = re.compile(r"\[[^\[\]\n]{1,40}\]\s*")
MAX_CHARS = 700

EMOJI = re.compile("[\U0001F000-\U0001FAFF☀-➿️‍]")
CODE_FENCE = re.compile(r"```.*?```", re.DOTALL)
# Links such as [Blog - master](t3-thread://...) are clickable in the chat; aloud only the
# name is said. A bare thread address or id becomes the thread's title, looked up in T3, and
# any other address becomes "링크", so the sentence still reads naturally.
MARKDOWN_LINK = re.compile(r"\[([^\[\]\n]+)\]\([^)\s]+\)")
ID_PATTERN = r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
# The last id in a thread address is the thread (an environment id comes first).
THREAD_ADDRESS = re.compile(r"(?:스레드\s*)?t3-thread://\S*(" + ID_PATTERN + r")\S*", re.IGNORECASE)
ADDRESS = re.compile(r"\b[a-z][a-z0-9+.-]*://\S+", re.IGNORECASE)
LONG_ID = re.compile(r"(?:스레드\s*)?\b(?:thread_)?(" + ID_PATTERN + r")\b", re.IGNORECASE)
# After a replaced name the particle is joined on and fitted to a word ending in a vowel
# (스레드, 링크): "스레드 이야" becomes "스레드야", "링크 에" becomes "링크에".
LOOSE_PARTICLE = re.compile(r"(스레드|링크)\s+(에서|에게|에|으로|로|이야|야|이|가|은|는|을|를|과|와|도|의|만)(?=[\s.,!?~]|$)")
VOWEL_PARTICLE = {"으로": "로", "이야": "야", "이": "가", "은": "는", "을": "를", "과": "와"}
DOUBLE_THREAD_WORD = re.compile(r"(스레드)(\s+스레드)+")
T3_CLI = assistant_config.get("T3_BIN", os.path.expanduser("~/.local/bin/t3"))
TITLE_LOOKUP_SECONDS = 3
UNKNOWN_THREAD = "그"
MARKDOWN_MARKS = re.compile(r"[*_#`>~]+")
SPACES = re.compile(r"[ \t]+")
BLANK_LINES = re.compile(r"\n{2,}")


def log(message):
    """Append one line to the hook log so silent failures can be traced."""
    stamp = datetime.now().isoformat(timespec="seconds")
    with open(LOG_PATH, "a", encoding="utf-8") as handle:
        handle.write(f"{stamp} {message}\n")


def last_assistant_text(transcript_path):
    """Return the assistant text blocks written after the last real user prompt."""
    chunks = []
    with open(transcript_path, encoding="utf-8") as handle:
        for line in handle:
            try:
                entry = json.loads(line)
            except ValueError:
                continue
            message = entry.get("message")
            if not isinstance(message, dict):
                continue
            content = message.get("content")
            if entry.get("type") == "user" and isinstance(content, str):
                chunks = []
            elif entry.get("type") == "assistant" and isinstance(content, list):
                chunks.extend(
                    block.get("text", "")
                    for block in content
                    if block.get("type") == "text"
                )
    return "\n".join(chunk for chunk in chunks if chunk)


_records = {}


def thread_record(thread_id):
    """The thread as T3 describes it (title, worktreePath, ...), or {} when not found quickly."""
    if thread_id not in _records:
        record = {}
        try:
            result = subprocess.run([T3_CLI, "thread", "show", thread_id, "--json"],
                                    capture_output=True, text=True, timeout=TITLE_LOOKUP_SECONDS)
            record = json.loads(result.stdout).get("thread") or {}
        except (OSError, ValueError, subprocess.TimeoutExpired, AttributeError):
            record = {}
        _records[thread_id] = record if isinstance(record, dict) else {}
    return _records[thread_id]


def thread_title(thread_id):
    """The thread's title from T3, or "" when it cannot be found quickly."""
    return str(thread_record(thread_id).get("title") or "").strip()


def spoken_thread(match):
    return f"{thread_title(match.group(1).lower()) or UNKNOWN_THREAD} 스레드"


def clean_for_speech(text):
    """Strip code, markdown marks and emoji, then trim to a spoken length."""
    text = CODE_FENCE.sub(" ", text)
    text = MARKDOWN_LINK.sub(r"\1", text)
    text = THREAD_ADDRESS.sub(spoken_thread, text)
    text = ADDRESS.sub("링크", text)
    text = LONG_ID.sub(spoken_thread, text)
    text = DOUBLE_THREAD_WORD.sub(r"\1", text)
    text = LOOSE_PARTICLE.sub(lambda m: m.group(1) + VOWEL_PARTICLE.get(m.group(2), m.group(2)), text)
    text = EMOJI.sub("", text)
    text = MARKDOWN_MARKS.sub("", text)
    text = SPACES.sub(" ", text)
    text = BLANK_LINES.sub("\n", text).strip()
    if len(text) <= MAX_CHARS:
        return text
    cut = text[:MAX_CHARS]
    last_stop = max(cut.rfind("."), cut.rfind("?"), cut.rfind("!"), cut.rfind("\n"))
    return cut[: last_stop + 1] if last_stop > 0 else cut


def voice_thread_files():
    """The voice-thread-id file of every assistant (persona.py), the main one's when that fails."""
    try:
        import persona
        return [persona.value(persona_id, "thread_file") for persona_id in persona.persona_ids()]
    except (ImportError, OSError, ValueError) as error:
        log(f"cannot list the assistants' threads: {error}")
        return [VOICE_THREAD_FILE]


def is_voice_thread(payload):
    """True when the reply came in a thread that voice conversations use (any assistant's).

    A thread without a project runs in a folder whose name ends with the last 8 characters of its
    id. Otherwise the folder T3 reports for the voice thread decides. When T3 reports none, any
    reply counts: this hook only runs for the assistant instances anyway.
    """
    folder = str(payload.get("cwd") or "").rstrip("/")
    for path in voice_thread_files():
        try:
            with open(path, encoding="utf-8") as handle:
                thread_id = handle.read().strip()
        except OSError:
            continue
        if len(thread_id) < THREAD_SUFFIX_CHARS:
            continue
        if folder.endswith(thread_id[-THREAD_SUFFIX_CHARS:]):
            return True
        recorded = str(thread_record(thread_id).get("worktreePath") or "").rstrip("/")
        if not recorded or recorded == folder:
            return True
    return False


def take_end_tag(text):
    """Remove the end tag. When it was there, mark the conversation as closed by the assistant."""
    if not END_TAG_PATTERN.search(text):
        return text, False
    with open(END_FLAG_PATH, "w", encoding="utf-8") as handle:
        handle.write(f"{int(time.time())}\n")
    log("reply closes the conversation")
    return END_TAG_PATTERN.sub("", text).strip(), True


def in_quiet_hours(now=None):
    hour = (now or datetime.now()).hour
    return hour >= QUIET_START_HOUR or hour < QUIET_END_HOUR


def conversation_running():
    try:
        with open(CONVERSATION_LOCK_PID, encoding="utf-8") as handle:
            os.kill(int(handle.read().strip()), 0)
        return True
    except (OSError, ValueError):
        return False


def keep_for_morning(text):
    with open(DIGEST_PATH, "a", encoding="utf-8") as handle:
        handle.write(f"{datetime.now():%H:%M} {VOICE_TAG.sub('', text).strip()}\n")
    log("quiet hours: reply kept for the morning briefing")


def speak(text, follow_up=False):
    """Hand the text to voice.py in its own session, so the hook returns at once.

    voice.py waits for any earlier speech to finish (a reply never cuts another off), makes the
    audio, and logs "speech started" when it plays.
    With follow_up it opens listening afterwards, unless a conversation is already going on.
    """
    command = [sys.executable, "-I", VOICE_SCRIPT, "speak"] + (["--follow-up"] if follow_up else [])
    process = subprocess.Popen(
        command,
        stdin=subprocess.PIPE,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    process.stdin.write(text.encode("utf-8"))
    process.stdin.close()
    log(f"speech handed to voice.py pid={process.pid} chars={len(text)} follow_up={follow_up}")


# Messages from other threads ([마일스톤]) and from the voice system itself ([알림], such as the
# ElevenLabs credit alert from credit_alert.py) wait for the morning during quiet hours.
REPORT_PREFIX = ("[마일스톤]", "[알림]")
# Messages the voice system writes itself; they are spoken like the ones the user says aloud.
AUTOMATIC_PREFIX = REPORT_PREFIX + ("[아침 브리핑]",)


def last_user_text(transcript_path):
    """The text of the last message the assistant answered (tool results are skipped)."""
    last = ""
    with open(transcript_path, encoding="utf-8") as handle:
        for line in handle:
            try:
                entry = json.loads(line)
            except ValueError:
                continue
            message = entry.get("message")
            if entry.get("type") != "user" or not isinstance(message, dict):
                continue
            content = message.get("content")
            if isinstance(content, str):
                last = content
            elif isinstance(content, list):
                texts = [block.get("text", "") for block in content if block.get("type") == "text"]
                if texts:
                    last = texts[0]
    return last


def answers_a_report(transcript_path):
    """True when the assistant is answering another thread's milestone report, not the user himself."""
    try:
        return last_user_text(transcript_path).lstrip().startswith(REPORT_PREFIX)
    except OSError:
        return False


def sent_by_voice(text, now=None):
    """True when say_to_assistant.sh sent exactly this text a short while ago."""
    wanted = hashlib.sha256(text.encode("utf-8")).hexdigest()
    now = time.time() if now is None else now
    try:
        with open(VOICE_SENT_PATH, encoding="utf-8") as handle:
            lines = handle.read().splitlines()
    except OSError:
        return False
    for line in lines:
        parts = line.split()
        if len(parts) != 2 or not parts[0].isdigit():
            continue
        if parts[1] == wanted and now - int(parts[0]) <= VOICE_SENT_MAX_AGE_SECONDS:
            return True
    return False


def typed_in_chat(transcript_path, now=None):
    """True when the message being answered was typed in the chat, not said aloud or automatic."""
    try:
        text = last_user_text(transcript_path)
    except OSError:
        return False
    if text.lstrip().startswith(AUTOMATIC_PREFIX):
        return False
    return not sent_by_voice(text, now)


def read_reply_with_retry(transcript_path, final_part=""):
    """Read the whole reply, waiting briefly until the transcript holds its final part.

    A reply can come in pieces around tool calls ("찾아볼게" ... tool ... "찾았어, 보낼까?").
    The hook can run before the last piece is written, so wait until the final part from the
    hook payload shows up, and add it ourselves if it never does.
    """
    final_part = final_part.strip()
    raw = ""
    for attempt in range(RETRY_COUNT):
        raw = last_assistant_text(transcript_path)
        if raw.strip() and (not final_part or final_part in raw):
            return clean_for_speech(raw)
        time.sleep(RETRY_DELAY_SECONDS)
    if final_part and final_part not in raw:
        log("transcript lacked the final part of the reply, added it from the hook payload")
        raw = f"{raw}\n{final_part}" if raw.strip() else final_part
    return clean_for_speech(raw)


def main():
    dry_run = "--dry" in sys.argv
    if not dry_run:
        log("hook invoked")
    try:
        payload = json.load(sys.stdin)
    except ValueError as error:
        print(f"speak.py: bad hook payload: {error}", file=sys.stderr)
        return 0

    if not dry_run:
        log(f"payload keys={sorted(payload)} transcript={payload.get('transcript_path')}")

    transcript_path = os.path.realpath(payload.get("transcript_path") or "")
    if not transcript_path.startswith(ALLOWED_ROOT + os.sep):
        log(f"skipped: transcript outside config dir: {transcript_path}")
        print("speak.py: transcript outside the Claude config dir, skipping", file=sys.stderr)
        return 0

    try:
        text = read_reply_with_retry(transcript_path, str(payload.get("last_assistant_message") or ""))
    except OSError as error:
        log(f"cannot read transcript: {error}")
        print(f"speak.py: cannot read transcript: {error}", file=sys.stderr)
        return 0

    if not text:
        text = clean_for_speech(str(payload.get("last_assistant_message") or ""))
    if not text:
        log("skipped: no reply text found in transcript or payload")
        return 0
    if dry_run:
        print(text)
        return 0
    if typed_in_chat(transcript_path):
        log("typed in the chat: the reply stays in the chat, not spoken")
        return 0
    text, closes = take_end_tag(text)
    if not text:
        return 0
    # Quiet hours only hold back news from other threads; when the user talks to it, they are awake.
    if in_quiet_hours() and not conversation_running() and answers_a_report(transcript_path):
        keep_for_morning(text)
        return 0
    speak(text, follow_up=is_voice_thread(payload) and not closes)
    return 0


if __name__ == "__main__":
    sys.exit(main())
