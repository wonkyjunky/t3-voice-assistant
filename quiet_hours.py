"""Quiet hours: the hours of the Mac's clock in which news from other threads waits for the morning.

The avatar's menu ("Quiet hours") and mac_control.py quiet (asked by voice) write the file
"quiet-hours" next to the app: one line "23 12" (from 23:00 until 12:00), or "off 23 12" when quiet
hours are turned off (the hours are kept for when they are turned on again). No file, or one that cannot be read, means 23:00 to 12:00.
A start equal to the end means no quiet hours at all.

speak.py asks in_quiet_hours() before speaking a report; morning_digest.sh runs every hour and
asks "quiet_hours.py now", so the briefing goes out in the first hour after quiet hours end.

Run: quiet_hours.py now   exits 0 during quiet hours, 1 outside them.
"""
import os
import sys
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
SETTING_PATH = os.path.join(HERE, "quiet-hours")
DEFAULT_START_HOUR = 23
DEFAULT_END_HOUR = 12
DEFAULT_SETTING = (True, DEFAULT_START_HOUR, DEFAULT_END_HOUR)
HOURS_IN_DAY = 24
OFF_WORD = "off"


def parse(text):
    """(on, start, end) from the file's text; the default for anything unreadable."""
    words = text.split()
    on = not (words and words[0] == OFF_WORD)
    hours = words if on else words[1:]
    if len(hours) != 2:
        return DEFAULT_SETTING
    try:
        start, end = int(hours[0]), int(hours[1])
    except ValueError:
        return DEFAULT_SETTING
    if not (0 <= start < HOURS_IN_DAY and 0 <= end < HOURS_IN_DAY):
        return DEFAULT_SETTING
    return on, start, end


def load(path=None):
    try:
        with open(path or SETTING_PATH, encoding="utf-8") as handle:
            return parse(handle.read())
    except OSError:
        return DEFAULT_SETTING


def text_of(setting):
    on, start, end = setting
    return f"{'' if on else OFF_WORD + ' '}{start} {end}\n"


def save(setting, path=None):
    """Written whole, then moved into place, so a reader never sees half a line."""
    target = path or SETTING_PATH
    temporary = f"{target}.tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        handle.write(text_of(setting))
    os.replace(temporary, target)


def describe(setting):
    on, start, end = setting
    span = f"{start:02d}:00-{end:02d}:00"
    if not on or start == end:
        return f"quiet hours off ({span} kept for when they are turned on)"
    return f"quiet hours on, {span} by the Mac's clock"


def in_quiet_hours(now=None, setting=None):
    on, start, end = setting or load()
    if not on or start == end:
        return False
    hour = (now or datetime.now()).hour
    if start < end:
        return start <= hour < end
    return hour >= start or hour < end


def main(argv):
    if argv[1:] == ["now"]:
        return 0 if in_quiet_hours() else 1
    print("usage: quiet_hours.py now", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
