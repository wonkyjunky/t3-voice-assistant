"""Reads assistant.conf, the one file with this install's personal settings.

assistant.conf holds KEY="value" lines (the shell scripts source the same file). Missing keys fall
back to assistant.conf.example, so a partly filled file still works. $HOME and other environment
variables in values are expanded. Lines that are not KEY="value" are ignored.
"""
import os
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONF_PATH = HERE / "assistant.conf"
EXAMPLE_PATH = HERE / "assistant.conf.example"
LINE = re.compile(r'^\s*([A-Za-z_][A-Za-z0-9_]*)="([^"]*)"\s*(?:#.*)?$')


def parse(text):
    values = {}
    for line in text.splitlines():
        match = LINE.match(line)
        if match:
            values[match.group(1)] = os.path.expandvars(match.group(2))
    return values


def read(path):
    try:
        return parse(path.read_text(encoding="utf-8"))
    except OSError:
        return {}


def load(conf_path=CONF_PATH, example_path=EXAMPLE_PATH):
    return {**read(example_path), **read(conf_path)}


def get(key, default=""):
    return load().get(key, default)


def get_int(key, default=0):
    try:
        return int(get(key, str(default)))
    except ValueError:
        return default
