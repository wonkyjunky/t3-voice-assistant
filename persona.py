#!/usr/bin/env python3
"""Which assistant is in use, picked in the avatar's menu ("Assistant").

  persona.py get <key>     a setting of the assistant in use (a KEY of assistant.conf, or dir,
                           thread_file, voice_cache), for the shell scripts
  persona.py list          the assistants, one "id<TAB>Korean name<TAB>English name" line each
  persona.py set <id>      switch to that assistant

The main assistant ("main") is the one set up by assistant.conf and persona.md, with its files
next to this script. More assistants live in personas/<id>/, each with:

  persona.conf       KEY="value" lines that differ from assistant.conf (at least the names, its
                     ELEVENLABS_VOICE_ID and ASSISTANT_INSTANCE; see docs/PERSONAS.md)
  persona.md         its character and speech style
  avatar/, avatar.png, voice_cache/, voice-thread-id   its own clips, photo, voice cache, thread

Every assistant talks in its own thread (on its own T3 instance) and shares the memory notes. The
one in use is named in the file "persona"; no file means the main one.
"""
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import assistant_config  # noqa: E402

PERSONAS_DIR = HERE / "personas"
CURRENT_PATH = HERE / "persona"
MAIN_ID = "main"


def persona_ids():
    extra = []
    if PERSONAS_DIR.is_dir():
        extra = sorted(path.name for path in PERSONAS_DIR.iterdir() if (path / "persona.conf").is_file())
    return [MAIN_ID] + extra


def folder(persona_id):
    return HERE if persona_id == MAIN_ID else PERSONAS_DIR / persona_id


def settings(persona_id):
    """assistant.conf with the persona's own values on top."""
    base = assistant_config.load()
    if persona_id == MAIN_ID:
        return base
    return {**base, **assistant_config.read(folder(persona_id) / "persona.conf")}


def current_id():
    try:
        chosen = CURRENT_PATH.read_text(encoding="utf-8").strip()
    except OSError:
        return MAIN_ID
    return chosen if chosen in persona_ids() else MAIN_ID


def value(persona_id, key):
    place = folder(persona_id)
    paths = {"dir": place, "thread_file": place / "voice-thread-id", "voice_cache": place / "voice_cache"}
    if key in paths:
        return str(paths[key])
    return settings(persona_id).get(key, "")


def switch(persona_id):
    if persona_id not in persona_ids():
        raise ValueError(f"no assistant {persona_id}")
    tmp = CURRENT_PATH.with_suffix(".tmp")
    tmp.write_text(persona_id + "\n", encoding="utf-8")
    os.replace(tmp, CURRENT_PATH)


def main(argv):
    try:
        if len(argv) == 2 and argv[0] == "get":
            print(value(current_id(), argv[1]))
        elif argv == ["list"]:
            for persona_id in persona_ids():
                found = settings(persona_id)
                print(f"{persona_id}\t{found.get('ASSISTANT_NAME_KO', persona_id)}\t{found.get('ASSISTANT_NAME_EN', persona_id)}")
        elif len(argv) == 2 and argv[0] == "set":
            switch(argv[1])
            print(f"assistant {argv[1]}")
        else:
            print("usage: persona.py get <key> | list | set <id>", file=sys.stderr)
            return 2
    except (OSError, ValueError) as error:
        print(f"persona: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
