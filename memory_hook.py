#!/usr/bin/env python3
"""Give the assistant its memory notes when a new session starts.

Runs as a Claude Code SessionStart hook for the assistant instance only (assistant-settings.json).
On a fresh start (or after the context was cleared or compacted) it hands the notes in
assistant-memory.md to the model as extra context. When an existing session is resumed the
notes are already in its context, so nothing is added.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MEMORY_PATH = os.path.join(HERE, "assistant-memory.md")
MAX_MEMORY_CHARS = 4000
SKIPPED_SOURCES = {"resume"}


def main():
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        payload = {}
    if payload.get("source") in SKIPPED_SOURCES:
        return 0
    try:
        with open(MEMORY_PATH, encoding="utf-8") as handle:
            notes = handle.read().strip()[:MAX_MEMORY_CHARS]
    except OSError:
        return 0
    if not notes:
        return 0
    context = (
        f"Your memory notes from earlier sessions (kept in {MEMORY_PATH}). "
        "Use them naturally and do not read them out:\n\n" + notes
    )
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": context}},
                     ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
