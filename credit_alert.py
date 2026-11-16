#!/usr/bin/env python3
"""Tells the user, through the assistant, when ElevenLabs use passes 80% of this month's limit.

Run every few hours by the LaunchAgent local.voice-assistant.credit. Sends at most one alert per
billing period: credit-alert.state holds the reset time of the period already alerted.

The limit is the smaller of the account's monthly characters and ELEVENLABS_KEY_MONTHLY_LIMIT in
assistant.conf, the monthly cap set on the API key itself (0 means the key has no cap). ElevenLabs has no call that reports a key's own use, so the
account's use stands in for it; use outside this key makes the alert come early, never late.

The alert goes to the voice thread as a message starting with [알림]. speak.py treats it like a
milestone report, so during quiet hours it waits for the morning briefing.
Logs only that an alert was sent, never the API key.
"""
import json
import subprocess
import sys
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import assistant_config  # noqa: E402
import voice  # noqa: E402  (api_key, SUBSCRIPTION_URL)

ALERT_PREFIX = "[알림]"
ALERT_RATIO = 0.8
# The monthly character cap set on the API key in ElevenLabs, 0 for none. ElevenLabs does not
# report it through the API, so keep assistant.conf in step when the key's cap changes.
KEY_MONTHLY_LIMIT = assistant_config.get_int("ELEVENLABS_KEY_MONTHLY_LIMIT")
USER_CALL = assistant_config.get("USER_CALL_KO", "사용자")
FETCH_TIMEOUT_SECONDS = 10
SEND_TIMEOUT_SECONDS = 30
STATE_PATH = HERE / "credit-alert.state"
ID_FILE = HERE / "voice-thread-id"
LOG_PATH = HERE / "voice.log"
T3 = assistant_config.get("T3_BIN", str(Path.home() / ".local/bin/t3"))


def log(message):
    stamp = datetime.now().isoformat(timespec="seconds")
    try:
        with open(LOG_PATH, "a", encoding="utf-8") as handle:
            handle.write(f"{stamp} credit alert: {message}\n")
    except OSError:
        pass


def as_int(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def alert_message(data, key_limit, alerted_reset):
    """The alert text when use passed the threshold in a period not yet alerted, else None."""
    used = as_int(data.get("character_count"))
    account_limit = as_int(data.get("character_limit"))
    reset = as_int(data.get("next_character_count_reset_unix"))
    if used is None or not account_limit or reset is None or reset == alerted_reset:
        return None
    limit = min(account_limit, key_limit) if key_limit > 0 else account_limit
    if used < limit * ALERT_RATIO:
        return None
    which = "API 키 월 한도" if 0 < key_limit < account_limit else "이번 달 한도"
    reset_day = datetime.fromtimestamp(reset)
    percent = min(100, round(used * 100 / limit))
    return (
        f"{ALERT_PREFIX} ElevenLabs 목소리 사용량이 {which}의 {percent}%야. "
        f"{limit:,}자 중 {used:,}자를 썼고 {max(limit - used, 0):,}자 남았어. "
        f"{reset_day.month}월 {reset_day.day}일에 초기화돼. {USER_CALL}한테 한두 문장으로 알려 줘."
    )


def fetch_subscription():
    key = voice.api_key()
    if not key:
        log("no API key in the Keychain")
        return None
    request = urllib.request.Request(voice.SUBSCRIPTION_URL, headers={"xi-api-key": key})
    try:
        with urllib.request.urlopen(request, timeout=FETCH_TIMEOUT_SECONDS) as response:
            return json.load(response)
    except (urllib.error.URLError, OSError, ValueError) as error:
        log(f"could not read usage ({type(error).__name__})")
        return None


def send_to_voice_thread(text):
    try:
        thread_id = ID_FILE.read_text().strip()
    except OSError:
        thread_id = ""
    if not thread_id:
        log("no voice thread id")
        return False
    try:
        done = subprocess.run([T3, "thread", "send", thread_id, "-"], input=text, text=True,
                              capture_output=True, timeout=SEND_TIMEOUT_SECONDS)
    except (OSError, subprocess.TimeoutExpired) as error:
        log(f"send failed ({type(error).__name__})")
        return False
    if done.returncode != 0:
        log(f"send failed with status {done.returncode}")
        return False
    log("sent to the voice thread")
    return True


def read_alerted_reset(state_path):
    try:
        return as_int(state_path.read_text().strip())
    except OSError:
        return None


def main(fetch=fetch_subscription, send=send_to_voice_thread, state_path=STATE_PATH,
         key_limit=KEY_MONTHLY_LIMIT):
    data = fetch()
    if not isinstance(data, dict):
        return 1
    message = alert_message(data, key_limit, read_alerted_reset(state_path))
    if message is None:
        return 0
    if not send(message):
        return 1
    try:
        state_path.write_text(f"{data['next_character_count_reset_unix']}\n")
    except OSError as error:
        log(f"alert sent but not remembered, it may repeat ({type(error).__name__})")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
