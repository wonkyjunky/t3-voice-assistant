#!/usr/bin/env python3
"""The assistant's voice: ElevenLabs (a cloned voice, model Eleven v4), with the macOS Yuna voice as fallback.

Usage:
  voice.py speak          read text on stdin, wait for earlier speech to finish, speak it (returns when done)
  voice.py speak --follow-up   the same, then open listening (talk.sh --follow-up)
                          unless a voice conversation is already going on
  voice.py phrase         like speak, for fixed phrases: the audio is made once and kept in
                          voice_cache/, so later it costs nothing and works offline
  voice.py save OUT.mp3   read text on stdin, write ElevenLabs audio to OUT.mp3 (exit 1 on failure)
  voice.py stop           stop the speech that is playing
  voice.py usage          print how many ElevenLabs characters are left this month

Replies are streamed: playback starts with the first audio bytes (through ffplay), instead of
after the whole reply has been made. Short audio tags such as [cheerfully] are kept for
ElevenLabs, which acts them out, and removed for the Yuna fallback, which would read them aloud.

While speaking, speaking.pid holds the player's pid, so the avatar and the talk scripts can tell
that the assistant is talking; caption-bot.txt holds what it says and level-bot.txt how loud it is,
for the avatar's caption bubble and sound bars (both removed when it stops). The API key is read
from the login Keychain (service voice-assistant-elevenlabs),
never from a file. Logs go to speak.log with the engine, length and timing only, never the text.
Set ASSISTANT_VOICE_ENGINE=yuna to skip ElevenLabs.
"""
import base64
import fcntl
import hashlib
import json
import math
import os
import re
import signal
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
from array import array
from contextlib import contextmanager
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import assistant_config  # noqa: E402  (this install's settings in assistant.conf)
LOG_PATH = os.path.join(HERE, "speak.log")
MARKER_PATH = os.path.join(HERE, "speaking.pid")
# While speaking, the avatar plays the talking clip that matches the reply's first voice tag
# (speaking.style holds its name; no file means the plain speaking clip).
STYLE_PATH = os.path.join(HERE, "speaking.style")
EMOTION_CLIPS = {
    "speaking_happy": ("cheerful", "excited", "laugh", "happ", "joy", "delight"),
    "speaking_sad": ("apolog", "sad", "sorry", "regret"),
    "speaking_playful": ("playful", "teas", "mischiev", "wink"),
    "speaking_comfort": ("gentl", "sympath", "comfort", "tender", "reassur", "soft"),
}
TAG_WORDS = re.compile(r"\[([^\[\]\n]{1,40})\]")
# What the assistant is saying, without voice tags, for the caption bubble next to the avatar. The file
# lives only while it speaks; the avatar keeps the words on screen a few seconds from memory.
# Readable only by the user, and never logged.
CAPTION_PATH = os.path.join(HERE, "caption-bot.txt")
PRIVATE_FILE_MODE = 0o600
# How loud the assistant's voice is, for the sound bars on the avatar: ffmpeg decodes the same audio the
# player gets (faster than it plays) and level-bot.txt gets one value from 0 to 1 per step, under
# a header with the time the player started. Only numbers, never the sound.
LEVEL_PATH = os.path.join(HERE, "level-bot.txt")
FFMPEG = "/opt/homebrew/bin/ffmpeg"
LEVEL_SAMPLE_RATE = 16000
LEVEL_STEP_SECONDS = 0.05
BYTES_PER_SAMPLE = 2
LEVEL_STEP_BYTES = int(LEVEL_SAMPLE_RATE * LEVEL_STEP_SECONDS) * BYTES_PER_SAMPLE
FULL_SCALE = 32768
# Loudness in decibels below full scale: QUIET_DB and softer shows no bar, LOUD_DB and louder full bars.
QUIET_DB = -50.0
LOUD_DB = -10.0
LEVEL_READER_WAIT_SECONDS = 5
# Speech takes turns: a reply that arrives while another plays (a report from another thread in
# the middle of an answer) waits for it instead of cutting it off. Waiting speech is listed in
# speech-queue/ (one file per speech, named after its pid) so the talk scripts treat it as
# speaking. Stopping the speech (voice.py stop) also drops whatever was waiting.
SPEECH_LOCK_PATH = os.path.join(HERE, "speech.lock")
QUEUE_DIR = os.path.join(HERE, "speech-queue")
STOP_PATH = os.path.join(HERE, "speech-stopped")
SPEECH_WAIT_SECONDS = 300
TURN_POLL_SECONDS = 0.1
CONVERSATION_LOCK_PID = os.path.join(HERE, "talk.lock", "pid")
TALK_SCRIPT = os.path.join(HERE, "talk.sh")
# The assistant picked in the avatar's menu (persona.py) brings its own voice and voice cache.
import persona as persona_config  # noqa: E402

PERSONA_ID = persona_config.current_id()
CACHE_DIR = persona_config.value(PERSONA_ID, "voice_cache")
CACHE_NAME_CHARS = 16

KEYCHAIN_SERVICE = "voice-assistant-elevenlabs"
# Her voice: ELEVENLABS_VOICE_ID in assistant.conf, for example an instant voice clone made from
# the voice in your avatar videos (see docs/AVATAR.md). Empty means the Yuna fallback voice.
VOICE_ID = persona_config.value(PERSONA_ID, "ELEVENLABS_VOICE_ID")
MODEL_ID = "eleven_v4"  # chosen by the user over eleven_v4_turbo
# Each reply is spoken in its own language: English when it has clearly more English letters than
# Korean (one Korean syllable carries about HANGUL_WEIGHT letters' worth of sound), Korean
# otherwise, so a Korean sentence with a few English words stays Korean.
HANGUL = re.compile(r"[가-힣ᄀ-ᇿ㄰-㆏]")
LATIN = re.compile(r"[A-Za-z]")
HANGUL_WEIGHT = 3
# A reply with no letters at all (only numbers) is read in the primary language set in the menu.
PRIMARY_LANGUAGE_PATH = os.path.join(HERE, "primary-language")
FALLBACK_VOICES = {"ko": "Yuna", "en": "Samantha"}
OUTPUT_FORMAT = "mp3_44100_192"  # highest MP3 quality on the Creator plan
API_URL = f"https://api.elevenlabs.io/v1/text-to-speech/{VOICE_ID}?output_format={OUTPUT_FORMAT}"
STREAM_URL = f"https://api.elevenlabs.io/v1/text-to-speech/{VOICE_ID}/stream/with-timestamps?output_format={OUTPUT_FORMAT}"
SUBSCRIPTION_URL = "https://api.elevenlabs.io/v1/user/subscription"
REQUEST_TIMEOUT_SECONDS = 15
USAGE_TIMEOUT_SECONDS = 5
STREAM_CHUNK_BYTES = 4096
ERROR_DETAIL_CHARS = 200
AUDIO_TAG = re.compile(r"\[[^\[\]\n]{1,40}\]\s*")

AFPLAY = "/usr/bin/afplay"
FFPLAY = "/opt/homebrew/bin/ffplay"
# The audio is always MP3, so ffplay and ffmpeg need not study the stream before starting. Measured
# on a stream fed at playback pace: ffplay made its first sound 1.4 s after starting without these
# flags and 0.22 s with them; ffmpeg gave its first loudness value after 1.2 s and 0.02 s.
MP3_FAST_START = ["-f", "mp3", "-probesize", "32", "-analyzeduration", "0"]
FFPLAY_STDIN = [FFPLAY, "-nodisp", "-autoexit", "-loglevel", "quiet", *MP3_FAST_START, "-i", "pipe:0"]
SAY = "/usr/bin/say"
PLAYER_NAMES = {"afplay", "ffplay", "say"}


def log(message):
    stamp = datetime.now().isoformat(timespec="seconds")
    with open(LOG_PATH, "a", encoding="utf-8") as handle:
        handle.write(f"{stamp} voice: {message}\n")


def api_key():
    result = subprocess.run(
        ["/usr/bin/security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-w"],
        capture_output=True,
        text=True,
    )
    return result.stdout.strip() if result.returncode == 0 else ""


def primary_language():
    """The language set in the avatar's menu (primary-language next to this file), Korean by default."""
    try:
        with open(PRIMARY_LANGUAGE_PATH, encoding="utf-8") as handle:
            return "en" if handle.read().strip() == "en" else "ko"
    except OSError:
        return "ko"


def language_of(text):
    plain = AUDIO_TAG.sub("", text)
    hangul = len(HANGUL.findall(plain))
    latin = len(LATIN.findall(plain))
    if hangul == 0 and latin == 0:
        return primary_language()
    return "en" if latin > hangul * HANGUL_WEIGHT else "ko"


def elevenlabs_body(text):
    return json.dumps({"text": text, "model_id": MODEL_ID, "language_code": language_of(text)}).encode()


def fallback_voice_for(text):
    return FALLBACK_VOICES[language_of(text)]


def open_elevenlabs(text, url):
    """Return an open HTTP response with MP3 audio, or None on any failure (logged)."""
    if os.environ.get("ASSISTANT_VOICE_ENGINE") == "yuna":
        return None
    if not VOICE_ID:
        log("elevenlabs skipped: no ELEVENLABS_VOICE_ID for this assistant")
        return None
    key = api_key()
    if not key:
        log("elevenlabs skipped: no key in Keychain")
        return None
    request = urllib.request.Request(
        url,
        data=elevenlabs_body(text),
        headers={"xi-api-key": key, "Content-Type": "application/json", "Accept": "audio/mpeg"},
        method="POST",
    )
    try:
        return urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT_SECONDS)
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", "replace")[:ERROR_DETAIL_CHARS]
        log(f"elevenlabs failed: HTTP {error.code} {detail}")
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        log(f"elevenlabs failed: {error}")
    return None


def synthesize(text):
    """Return MP3 bytes from ElevenLabs, or None on any failure (logged)."""
    started = time.time()
    response = open_elevenlabs(text, API_URL)
    if response is None:
        return None
    try:
        with response:
            audio = response.read()
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        log(f"elevenlabs failed while reading: {error}")
        return None
    log(f"elevenlabs ok in {time.time() - started:.2f}s, {len(audio)} bytes")
    return audio or None


def without_audio_tags(text):
    return AUDIO_TAG.sub("", text).strip()


def read_marker_pid():
    try:
        with open(MARKER_PATH, encoding="utf-8") as handle:
            return int(handle.read().strip())
    except (OSError, ValueError):
        return None


def is_player(pid):
    """True only for a running afplay or say, so a reused pid is never killed."""
    result = subprocess.run(["/bin/ps", "-p", str(pid), "-o", "comm="], capture_output=True, text=True)
    return os.path.basename(result.stdout.strip()) in PLAYER_NAMES


def remove_marker(pid):
    if read_marker_pid() == pid:
        try:
            os.remove(MARKER_PATH)
        except FileNotFoundError:
            pass


def emotion_of(text):
    """The talking clip for the reply's first voice tag, or "" when that tag has no clip.

    Only the first tag picks the face (the assistant is told so); later tags only colour the voice.
    """
    for tag in TAG_WORDS.findall(text)[:1]:
        words = tag.lower()
        for clip, hints in EMOTION_CLIPS.items():
            if any(hint in words for hint in hints):
                return clip
    return ""


def set_style(text):
    style = emotion_of(text)
    if not style:
        clear_style()
        return
    with open(STYLE_PATH, "w", encoding="utf-8") as handle:
        handle.write(f"{style}\n")


def clear_style():
    try:
        os.remove(STYLE_PATH)
    except FileNotFoundError:
        pass


def write_private(path, text):
    """Write text so readers never see half of it, readable only by the user."""
    temporary = f"{path}.tmp"
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, PRIVATE_FILE_MODE)
    with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
        handle.write(text)
    os.replace(temporary, path)


def set_caption(text):
    shown = without_audio_tags(text)
    if shown:
        write_private(CAPTION_PATH, shown)


def clear_caption(text):
    """Remove the caption, but only while it still shows this text and not a newer reply."""
    try:
        with open(CAPTION_PATH, encoding="utf-8") as handle:
            if handle.read() != without_audio_tags(text):
                return
        os.remove(CAPTION_PATH)
    except FileNotFoundError:
        pass


def level_of(pcm):
    """Loudness from 0 to 1 of 16-bit mono samples, on a decibel scale like a meter."""
    samples = array("h")
    samples.frombytes(pcm[: len(pcm) - len(pcm) % BYTES_PER_SAMPLE])
    if not samples:
        return 0
    rms = math.sqrt(sum(sample * sample for sample in samples) / len(samples)) / FULL_SCALE
    if rms <= 0:
        return 0
    decibels = 20 * math.log10(rms)
    return min(1, max(0, (decibels - QUIET_DB) / (LOUD_DB - QUIET_DB)))


class LevelTrack:
    """Works out the loudness of audio fed to it and writes it to level-bot.txt as it goes.

    Without ffmpeg there are no levels and the avatar moves its bars on its own; speech is never
    held up by this.
    """

    def __init__(self, started_at):
        self._process = None
        self._reader = None
        command = [FFMPEG, "-loglevel", "quiet", *MP3_FAST_START, "-i", "pipe:0",
                   "-f", "s16le", "-ac", "1", "-ar", str(LEVEL_SAMPLE_RATE), "pipe:1"]
        try:
            self._process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                              stderr=subprocess.DEVNULL)
        except OSError as error:
            log(f"sound levels off: {error.strerror}")
            return
        descriptor = os.open(LEVEL_PATH, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, PRIVATE_FILE_MODE)
        track = os.fdopen(descriptor, "w", encoding="utf-8")
        track.write(f"start {started_at:.3f} step {LEVEL_STEP_SECONDS} pid {os.getpid()}\n")
        track.flush()
        self._reader = threading.Thread(target=self._write_levels, args=(track,), daemon=True)
        self._reader.start()

    def _write_levels(self, track):
        with track:
            while True:
                chunk = self._process.stdout.read(LEVEL_STEP_BYTES)
                if not chunk:
                    return
                track.write(f"{level_of(chunk):.3f}\n")
                track.flush()

    def feed(self, audio):
        if self._process is None:
            return
        try:
            self._process.stdin.write(audio)
            self._process.stdin.flush()
        except (BrokenPipeError, OSError):
            pass

    def finish(self):
        if self._process is None:
            return
        try:
            self._process.stdin.close()
        except (BrokenPipeError, OSError):
            pass
        self._process.wait()
        self._reader.join(LEVEL_READER_WAIT_SECONDS)


def clear_levels():
    """Remove level-bot.txt, but only when this process wrote it (not a newer reply)."""
    try:
        with open(LEVEL_PATH, encoding="utf-8") as handle:
            if not handle.readline().rstrip("\n").endswith(f" pid {os.getpid()}"):
                return
        os.remove(LEVEL_PATH)
    except FileNotFoundError:
        pass


def mark_stopped():
    write_private(STOP_PATH, f"{time.time():.6f}")


def stopped_at():
    try:
        with open(STOP_PATH, encoding="utf-8") as handle:
            return float(handle.read().strip())
    except (OSError, ValueError):
        return 0.0


def queued_pids():
    try:
        names = os.listdir(QUEUE_DIR)
    except FileNotFoundError:
        return []
    pids = []
    for name in names:
        try:
            pids.append((name, int(name.split("-", 1)[0])))
        except ValueError:
            continue
    return pids


def process_alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def speech_pending():
    """True while any speech is playing or waiting for its turn."""
    return any(process_alive(pid) for _, pid in queued_pids())


def prune_queue():
    """Remove entries left by speech processes that died."""
    for name, pid in queued_pids():
        if not process_alive(pid):
            try:
                os.remove(os.path.join(QUEUE_DIR, name))
            except FileNotFoundError:
                pass


def wait_for_turn(lock):
    deadline = time.time() + SPEECH_WAIT_SECONDS
    while True:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return True
        except BlockingIOError:
            if time.time() >= deadline:
                log("earlier speech still holds its turn, speaking anyway")
                return False
            time.sleep(TURN_POLL_SECONDS)


@contextmanager
def speech_turn():
    """Wait until earlier speech has finished, then yield whether this speech may still play.

    It may not when speech was stopped (voice.py stop) after this one started waiting.
    """
    queued_at = time.time()
    prune_queue()
    os.makedirs(QUEUE_DIR, exist_ok=True)
    entry = os.path.join(QUEUE_DIR, f"{os.getpid()}-{threading.get_ident()}-{time.time_ns()}")
    with open(entry, "w", encoding="utf-8"):
        pass
    try:
        with open(SPEECH_LOCK_PATH, "a", encoding="utf-8") as lock:
            holds_turn = wait_for_turn(lock)
            try:
                allowed = stopped_at() < queued_at
                if not allowed:
                    log("speech dropped: speech was stopped while it waited")
                yield allowed
            finally:
                if holds_turn:
                    fcntl.flock(lock, fcntl.LOCK_UN)
    finally:
        try:
            os.remove(entry)
        except FileNotFoundError:
            pass


def stop_speech():
    pid = read_marker_pid()
    if pid and is_player(pid):
        try:
            os.kill(pid, signal.SIGTERM)
        except (ProcessLookupError, PermissionError):
            pass
    if pid:
        remove_marker(pid)
    subprocess.run(["/usr/bin/pkill", "-x", "say"], check=False)
    clear_style()


def start_player(command, engine, chars, takes_stdin=False):
    """Start a player and mark it as the assistant's speech while it runs."""
    process = subprocess.Popen(
        command,
        stdin=subprocess.PIPE if takes_stdin else subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    with open(MARKER_PATH, "w", encoding="utf-8") as handle:
        handle.write(f"{process.pid}\n")
    log(f"speech started engine={engine} chars={chars} pid={process.pid}")
    return process


def finish_player(process):
    """Close the player's input (a stopped player may already be gone) and wait for it."""
    if process.stdin:
        try:
            process.stdin.close()
        except BrokenPipeError:
            pass
    process.wait()
    remove_marker(process.pid)


def play(command, engine, chars, stdin_text=None):
    process = start_player(command, engine, chars, takes_stdin=stdin_text is not None)
    if stdin_text is not None:
        try:
            process.stdin.write(stdin_text.encode("utf-8"))
        except BrokenPipeError:
            pass
    finish_player(process)


def speak_with_fallback_voice(text):
    spoken = without_audio_tags(text)
    if spoken:
        fallback = fallback_voice_for(spoken)
        play([SAY, "-v", fallback], fallback.lower(), len(spoken), stdin_text=spoken)
    return 0


def speak_streaming(text):
    """Play the reply while it downloads.

    The stream is one JSON object per line with base64 audio (it also carries per-character
    times, unused for now). Returns False when nothing could be played.
    """
    started = time.time()
    response = open_elevenlabs(text, STREAM_URL)
    if response is None:
        return False
    player = None
    levels = None
    try:
        with response:
            for line in response:
                if not line.strip():
                    continue
                chunk = json.loads(line)
                audio = base64.b64decode(chunk.get("audio_base64") or "")
                if audio and player is None:
                    log(f"elevenlabs first audio in {time.time() - started:.2f}s")
                    player = start_player(FFPLAY_STDIN, "elevenlabs-stream", len(text), takes_stdin=True)
                    levels = LevelTrack(time.time())
                if audio:
                    # Flushed at once: otherwise Python holds the audio back in its write buffer
                    # (128 KB, several seconds of speech) and the player starts late.
                    player.stdin.write(audio)
                    player.stdin.flush()
                    levels.feed(audio)
    except BrokenPipeError:
        log("stream stopped: player was stopped")
    except (urllib.error.URLError, TimeoutError, OSError, ValueError) as error:
        log(f"stream broke off: {error}")
    if player is None:
        return False
    levels.finish()
    finish_player(player)
    return True


def play_file(path, engine, chars):
    """Play an audio file while its loudness is worked out (much faster than it plays)."""
    process = start_player([AFPLAY, path], engine, chars)
    levels = LevelTrack(time.time())
    with open(path, "rb") as audio:
        levels.feed(audio.read())
    levels.finish()
    finish_player(process)


def phrase_path(text):
    """The cache name covers voice, model and quality too, so changing any of them makes new audio."""
    digest = hashlib.sha256(f"{VOICE_ID}|{MODEL_ID}|{OUTPUT_FORMAT}|{text}".encode("utf-8")).hexdigest()
    return os.path.join(CACHE_DIR, f"phrase-{digest[:CACHE_NAME_CHARS]}.mp3")


def speak_phrase(text):
    with speech_turn() as allowed:
        if not allowed:
            return 0
        set_style(text)
        set_caption(text)
        try:
            return speak_phrase_audio(text)
        finally:
            clear_style()
            clear_caption(text)
            clear_levels()


def speak_phrase_audio(text):
    path = phrase_path(text)
    if not os.path.exists(path):
        audio = synthesize(text)
        if not audio:
            return speak_with_fallback_voice(text)
        os.makedirs(CACHE_DIR, exist_ok=True)
        with open(f"{path}.tmp", "wb") as handle:
            handle.write(audio)
        os.replace(f"{path}.tmp", path)
    play_file(path, "elevenlabs-cached", len(text))
    return 0


def speak(text):
    with speech_turn() as allowed:
        if not allowed:
            return 0
        set_style(text)
        set_caption(text)
        try:
            return speak_audio(text)
        finally:
            clear_style()
            clear_caption(text)
            clear_levels()


def speak_audio(text):
    if os.path.exists(FFPLAY) and speak_streaming(text):
        return 0
    audio = synthesize(text)
    if not audio:
        return speak_with_fallback_voice(text)
    handle, path = tempfile.mkstemp(prefix="voice-assistant-", suffix=".mp3")
    try:
        with os.fdopen(handle, "wb") as audio_file:
            audio_file.write(audio)
        play_file(path, "elevenlabs", len(text))
    finally:
        os.remove(path)
    return 0


def conversation_running():
    try:
        with open(CONVERSATION_LOCK_PID, encoding="utf-8") as handle:
            os.kill(int(handle.read().strip()), 0)
        return True
    except (OSError, ValueError):
        return False


def start_follow_up():
    """Let the user answer what the assistant just read out, without pressing anything."""
    if conversation_running():
        return
    subprocess.Popen(
        ["/bin/bash", TALK_SCRIPT, "--follow-up"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    log("follow-up listening started")


def save(text, out_path):
    audio = synthesize(text)
    if not audio:
        return 1
    with open(out_path, "wb") as handle:
        handle.write(audio)
    return 0


# The avatar's menu shows this line in its menu language ("en" or "ko").
USAGE_PROBLEMS = {
    "en": {"no key": "usage: no key", "unknown": "usage: could not check"},
    "ko": {"no key": "사용량: 키 없음", "unknown": "사용량: 확인 못 함"},
}


def usage_line(used, limit, language):
    left = max(limit - used, 0)
    if language == "en":
        return f"{left:,} of {limit:,} characters left"
    return f"남은 글자 {left:,} / {limit:,}"


def print_usage(language="ko"):
    language = language if language in USAGE_PROBLEMS else "ko"
    key = api_key()
    if not key:
        print(USAGE_PROBLEMS[language]["no key"])
        return 1
    request = urllib.request.Request(SUBSCRIPTION_URL, headers={"xi-api-key": key})
    try:
        with urllib.request.urlopen(request, timeout=USAGE_TIMEOUT_SECONDS) as response:
            data = json.load(response)
    except (urllib.error.URLError, TimeoutError, OSError, ValueError):
        print(USAGE_PROBLEMS[language]["unknown"])
        return 1
    print(usage_line(data.get("character_count") or 0, data.get("character_limit") or 0, language))
    return 0


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "stop":
        mark_stopped()
        stop_speech()
        return 0
    if command == "usage":
        return print_usage(sys.argv[2] if len(sys.argv) > 2 else "ko")
    text = sys.stdin.read().strip()
    if not text:
        return 1
    if command == "speak":
        status = speak(text)
        if "--follow-up" in sys.argv[2:]:
            start_follow_up()
        return status
    if command == "phrase":
        return speak_phrase(text)
    if command == "save" and len(sys.argv) > 2:
        return save(text, sys.argv[2])
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
