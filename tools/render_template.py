#!/usr/bin/env python3
"""render_template.py TEMPLATE OUTPUT

Fills {{KEY}} placeholders in TEMPLATE with this install's values and writes OUTPUT. The values
are everything in assistant.conf plus ASSISTANT_DIR (the repository folder), PYTHON (the Python
that runs the scripts), PERSONA (persona.md, or persona.example.md until you write your own) and
SONG_RULE (how to play a named song: Apple Music first when APPLE_MUSIC is "yes", else YouTube).
Placeholders inside the persona are filled too. Stops with an error, and writes nothing, when a placeholder has no value,
so a half-filled prompt or settings file never gets installed.
"""
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO))

import assistant_config  # noqa: E402

PYTHON = "/opt/homebrew/bin/python3"
PLACEHOLDER = re.compile(r"\{\{([A-Z][A-Z0-9_]*)\}\}")


def read_persona():
    for name in ("persona.md", "persona.example.md"):
        try:
            return (REPO / name).read_text(encoding="utf-8").strip()
        except OSError:
            continue
    return ""


# How the assistant plays a song the user names. Apple Music plays whole songs only with a
# subscription, so it comes first only when assistant.conf says APPLE_MUSIC="yes".
APPLE_MUSIC_SONG_RULE = (
    "- When the user names a song or a singer (아이유 love wins all, 뉴진스 노래), use music song \"<words>\" first: "
    "it plays the song from their Music library, else from the Apple Music catalog, in the Music app kept out of "
    "sight, and prints the song and artist; mention them briefly. Put the artist and the song name in the words "
    "when they give them. If it exits with 1 or 3, or they ask for YouTube by name, or for a mood or a mix rather "
    "than a song (잔잔한 음악, lofi), use youtube play \"<words>\" instead."
)
YOUTUBE_SONG_RULE = (
    "- When the user asks for a song, a singer or some kind of music, use youtube play \"<words>\" (described "
    "below). music song \"<words>\" plays only songs in their Music library; use it when they name the Music app."
)


def song_rule(config):
    return APPLE_MUSIC_SONG_RULE if config.get("APPLE_MUSIC", "").strip().lower() == "yes" else YOUTUBE_SONG_RULE


def install_values():
    config = assistant_config.load()
    return {**config, "ASSISTANT_DIR": str(REPO), "PYTHON": PYTHON, "PERSONA": read_persona(),
            "SONG_RULE": song_rule(config)}


def render(text, values):
    # The persona goes in first, so placeholders it contains are filled in the same pass.
    text = text.replace("{{PERSONA}}", values.get("PERSONA") or "{{PERSONA}}")
    missing = sorted({key for key in PLACEHOLDER.findall(text) if not values.get(key)})
    if missing:
        raise KeyError(", ".join(missing))
    return PLACEHOLDER.sub(lambda match: values[match.group(1)], text)


def main(argv):
    if len(argv) != 3:
        print(__doc__.strip().splitlines()[0], file=sys.stderr)
        return 2
    template, output = Path(argv[1]), Path(argv[2])
    try:
        text = render(template.read_text(encoding="utf-8"), install_values())
    except KeyError as missing:
        print(f"render_template: {template.name} needs values in assistant.conf for: {missing}", file=sys.stderr)
        return 1
    output.write_text(text, encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
