#!/usr/bin/env python3
"""Finds files for the assistant in the folders it may read.

Claude Code here has no Grep or Glob tools, and tool_guard.py lets Bash run only fixed commands,
so this is how it looks things up (notes and project folders listed in ASSISTANT_READ_FOLDERS).
It searches only the folders tool_guard.py lets it read, never lists files that look like
secrets, and prints paths only; the assistant reads a file with the Read tool.

Usage:
  file_search.py contains "<text>" [folder]   files whose text contains <text>
  file_search.py named "<text>" [folder]      files whose name contains <text>
Case does not matter, Korean matches in either Unicode form, and "a|b" matches either. Without a
folder every readable folder is searched. At most MAX_RESULTS paths are printed, newest first.
Exit status: 0 found, 1 nothing found, 2 usage, 4 the folder is not a readable one.
"""
import os
import sys
import time
import unicodedata
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))  # run as `python3 -I`, which leaves this folder off the import path

import tool_guard  # noqa: E402

FOUND, NOT_FOUND, USAGE, REFUSED = 0, 1, 2, 4
MAX_RESULTS = 30
MAX_FILE_BYTES = 2_000_000
MAX_SECONDS = 10
BINARY_PROBE_BYTES = 1024
# iCloud files that are not downloaded yet; reading them would start a download.
DATALESS_FLAG = 0x40000000
SKIPPED_FOLDERS = frozenset({"node_modules", "__pycache__", "DerivedData", "Pods", "venv", "build", "dist"})


def default_roots():
    return tool_guard.ReadScope(extra_folders=tool_guard.configured_read_folders()).all_folders()


def normalized(text):
    return unicodedata.normalize("NFC", text).lower()


def search_terms(query):
    return [normalized(term.strip()) for term in query.split("|") if term.strip()]


def skipped_folder(name):
    return name.startswith(".") or name in SKIPPED_FOLDERS or name.endswith(".app")


def readable_text(path, size):
    if size > MAX_FILE_BYTES:
        return None
    try:
        data = path.read_bytes()
    except OSError:
        return None
    if b"\0" in data[:BINARY_PROBE_BYTES]:
        return None
    return normalized(data.decode("utf-8", "ignore"))


def matches(mode, path, terms, size):
    if mode == "named":
        name = normalized(path.name)
        return any(term in name for term in terms)
    text = readable_text(path, size)
    return text is not None and any(term in text for term in terms)


def candidate_files(folders, deadline):
    """Files under the folders, skipping hidden and generated folders, secrets and iCloud stubs."""
    for folder in folders:
        for current, subfolders, names in os.walk(folder):
            subfolders[:] = [name for name in subfolders if not skipped_folder(name)]
            for name in names:
                if time.monotonic() > deadline:
                    return
                path = Path(current) / name
                try:
                    info = path.lstat()
                except OSError:
                    continue
                if path.is_symlink() or tool_guard.looks_secret(path) or info.st_flags & DATALESS_FLAG:
                    continue
                yield path, info


def search(mode, terms, folders, deadline):
    found = [(info.st_mtime, path) for path, info in candidate_files(folders, deadline)
             if matches(mode, path, terms, info.st_size)]
    return [path for _, path in sorted(found, key=lambda item: item[0], reverse=True)]


def chosen_folders(folder, roots):
    """The folders to search, or None when the folder is outside the readable ones."""
    if folder is None:
        return roots
    path = Path(os.path.expanduser(folder)).resolve()
    return [path] if any(tool_guard.is_inside(path, root) for root in roots) else None


def main(argv, roots=None, out=sys.stdout, err=sys.stderr):
    if len(argv) not in (2, 3) or argv[0] not in ("contains", "named") or not search_terms(argv[1]):
        print(__doc__, file=err)
        return USAGE
    roots = [Path(root).resolve() for root in (roots if roots is not None else default_roots())]
    folders = chosen_folders(argv[2] if len(argv) == 3 else None, roots)
    if folders is None:
        print("That folder is not one of the readable folders.", file=err)
        return REFUSED
    deadline = time.monotonic() + MAX_SECONDS
    paths = search(argv[0], search_terms(argv[1]), folders, deadline)
    if time.monotonic() > deadline:
        print("The search took too long and stopped early; name a smaller folder.", file=err)
    if not paths:
        print("nothing found", file=err)
        return NOT_FOUND
    for path in paths[:MAX_RESULTS]:
        print(path, file=out)
    if len(paths) > MAX_RESULTS:
        print(f"... and {len(paths) - MAX_RESULTS} more; add words or name a folder to narrow it", file=out)
    return FOUND


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
