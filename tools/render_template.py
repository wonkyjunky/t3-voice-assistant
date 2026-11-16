#!/usr/bin/env python3
"""render_template.py TEMPLATE OUTPUT

Fills {{KEY}} placeholders in TEMPLATE with this install's values and writes OUTPUT. The values
are everything in assistant.conf plus ASSISTANT_DIR (the repository folder), PYTHON (the Python
that runs the scripts) and PERSONA (persona.md, or persona.example.md until you write your own).
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


def install_values():
    return {**assistant_config.load(), "ASSISTANT_DIR": str(REPO), "PYTHON": PYTHON, "PERSONA": read_persona()}


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
