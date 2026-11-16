#!/usr/bin/env python3
"""Limits what the assistant's own tools can do, in code instead of only in the prompt.

Runs as a Claude Code PreToolUse hook for the assistant instance only (assistant-settings.json).
The assistant reads other threads and their milestone reports, which can carry text written to
trick it (prompt injection). Its thread runs with full access, so this hook decides what a tool
call may touch, whatever the model was talked into. Only the tools in ALLOWED_TOOLS run at all:

  Bash                       only the fixed Mac control command and the fixed file search command
                             (file_search.py), with no chaining, redirection, substitution or
                             unquoted wildcards
  Write, Edit, MultiEdit     only the memory notes file
  Read, Glob, Grep           only inside this repository folder, the results Claude Code saved
                             from this session's own tool calls (a long thread it read), and the
                             folders listed in ASSISTANT_READ_FOLDERS in assistant.conf; never
                             files that look like secrets (.env, keys, certificates, credentials).
                             In the listed folders Grep may list matching files, but matching lines
                             only come out of single files, so a search cannot sweep keys out of a
                             whole folder.
  ToolSearch, TodoWrite      always (loading tool definitions, a private to-do list)
  T3 Code tools              only the ones for reading, searching, messaging and starting threads
  anything else              never, including tools Claude Code or T3 Code add later

The list was taken from the tools the assistant really used, plus the ones its prompt allows.
To give it another tool, add the name to ALLOWED_TOOLS and to the tests.

Paths are resolved first (symlinks and "..") so a path cannot step outside the allowed place.
Exit status 2 blocks the call and feeds the reason back to the model.
"""
import fnmatch
import json
import os
import shlex
import sys
from dataclasses import dataclass, field
from pathlib import Path

HERE = Path(__file__).resolve().parent
# Run as `python3 -I`, which leaves this folder off the import path.
sys.path.insert(0, str(HERE))

import assistant_config  # noqa: E402
PYTHON = "/opt/homebrew/bin/python3"
MAC_CONTROL = HERE / "mac_control.py"
# Claude Code may have no Grep or Glob tools, so file lookups go through this fixed command.
FILE_SEARCH = HERE / "file_search.py"
MEMORY_PATH = HERE / "assistant-memory.md"
BLOCK_EXIT_STATUS = 2

WRITE_TOOLS = frozenset({"Write", "Edit", "MultiEdit"})
READ_TOOLS = frozenset({"Read", "Glob", "Grep"})
T3_TOOLS = frozenset(f"mcp__t3-code__{name}" for name in (
    "t3_thread_list", "t3_thread_read", "t3_thread_search", "t3_thread_send", "t3_thread_launch",
    "t3_thread_wait", "t3_thread_interrupt", "task_status", "t3_project_list", "t3_project_read",
))
ALLOWED_TOOLS = WRITE_TOOLS | READ_TOOLS | T3_TOOLS | frozenset({"Bash", "ToolSearch", "TodoWrite"})
# Never allowed anywhere in a command, quoted or not: they expand inside double quotes too.
FORBIDDEN_CHARS = ("$", "`", "\n", "\r", "\\")
OPERATOR_CHARS = frozenset("();<>|&")
WILDCARD_CHARS = frozenset("*?[]{}")
QUOTES = ("'", '"')
# File names (lower case) that are never read, wherever they are.
SECRET_NAME_PATTERNS = (
    ".env", ".env.*", "*.pem", "*.key", "*.p12", "*.pfx", "id_rsa*", "id_ed25519*", "id_ecdsa*",
    "id_dsa*", ".netrc", "*credential*", "*secret*", "*.keychain", "*.keychain-db",
)
READ_FOLDERS_KEY = "ASSISTANT_READ_FOLDERS"
CONTENT_MODE = "content"
TOOL_RESULTS_FOLDER = "tool-results"


@dataclass(frozen=True)
class ReadScope:
    """Where file tools may look besides this folder.

    Claude Code keeps a session's transcript at <dir>/<session>.jsonl and saves long tool results
    (such as a long thread) in <dir>/<session>/tool-results/, which the model then has to read.
    """

    transcript_path: str = ""
    extra_folders: list = field(default_factory=list)

    def session_results(self):
        if not self.transcript_path:
            return None
        transcript = resolved(self.transcript_path)
        return transcript.with_suffix("") / TOOL_RESULTS_FOLDER if transcript else None

    def open_folders(self):
        """Folders where any search is fine: this one and the session's saved results."""
        results = self.session_results()
        return [HERE] + ([results] if results else [])

    def all_folders(self):
        extra = [resolved(folder) for folder in self.extra_folders]
        return self.open_folders() + [folder for folder in extra if folder]


def configured_read_folders(values=None):
    """The folders in ASSISTANT_READ_FOLDERS (separated by ":"), with ~ expanded."""
    raw = (assistant_config.load() if values is None else values).get(READ_FOLDERS_KEY, "")
    return [os.path.expanduser(part.strip()) for part in raw.split(":") if part.strip()]


def looks_secret(path):
    name = path.name.lower()
    return any(fnmatch.fnmatch(name, pattern) for pattern in SECRET_NAME_PATTERNS)


def resolved(path_text):
    try:
        return Path(os.path.expanduser(str(path_text))).resolve()
    except (OSError, RuntimeError, ValueError):
        return None


def is_inside(path, folder):
    return path == folder or folder in path.parents


def command_tokens(command):
    """Shell words with operators split out, or None when the quoting is broken."""
    try:
        lexer = shlex.shlex(command, posix=True, punctuation_chars=True)
        lexer.whitespace_split = True
        return list(lexer)
    except ValueError:
        return None


def has_unquoted_wildcard(command):
    try:
        raw_words = shlex.shlex(command, posix=False)
        raw_words.whitespace_split = True
        words = list(raw_words)
    except ValueError:
        return True
    return any(not word.startswith(QUOTES) and WILDCARD_CHARS & set(word) for word in words)


def bash_problem(command):
    if any(char in command for char in FORBIDDEN_CHARS):
        return "Shell commands may not contain $, backticks, backslashes or line breaks."
    tokens = command_tokens(command)
    if tokens is None:
        return "The command's quotes do not match."
    if any(token and set(token) <= OPERATOR_CHARS for token in tokens):
        return "Commands may not be chained, piped, redirected or run in the background."
    if has_unquoted_wildcard(command):
        return "Put words in double quotes; unquoted wildcards are not allowed."
    if tokens[:2] != [PYTHON, "-I"] or tokens[2:3] not in ([str(MAC_CONTROL)], [str(FILE_SEARCH)]):
        return (f"The only shell commands allowed are {PYTHON} -I {MAC_CONTROL} (Mac control) and "
                f"{PYTHON} -I {FILE_SEARCH} (finding files).")
    return None


def file_problem(tool, tool_input, scope):
    target = tool_input.get("file_path") or tool_input.get("notebook_path") or tool_input.get("path")
    if not target:
        return f"{tool} needs an explicit path inside {HERE}."
    path = resolved(target)
    if path is None:
        return f"{tool} got a path that cannot be resolved."
    if tool in WRITE_TOOLS:
        return None if path == MEMORY_PATH.resolve() else f"Only the memory notes ({MEMORY_PATH}) may be changed."
    if looks_secret(path):
        return f"{path.name} looks like a file with secrets, which is never read."
    if not any(is_inside(path, folder) for folder in scope.all_folders()):
        return f"{tool} may only look inside {HERE}, this session's saved results and the folders in {READ_FOLDERS_KEY}."
    sweeps_lines = tool == "Grep" and tool_input.get("output_mode") == CONTENT_MODE and not path.is_file()
    if sweeps_lines and not any(is_inside(path, folder) for folder in scope.open_folders()):
        return "Search this folder for matching file names, then read the single file you need."
    return None


def problem(tool, tool_input=None, scope=None):
    """Why this call is not allowed, or None when it is."""
    tool_input = tool_input or {}
    if tool not in ALLOWED_TOOLS:
        return f"{tool or 'This tool'} is not available to the voice assistant."
    if tool == "Bash":
        return bash_problem(str(tool_input.get("command") or ""))
    if tool in WRITE_TOOLS or tool in READ_TOOLS:
        return file_problem(tool, tool_input, scope or ReadScope())
    return None


def main(payload_text=None, extra_folders=None):
    try:
        payload = json.loads(sys.stdin.read() if payload_text is None else payload_text)
    except ValueError:
        print("tool_guard: unreadable hook input, blocking to be safe", file=sys.stderr)
        return BLOCK_EXIT_STATUS
    folders = configured_read_folders() if extra_folders is None else extra_folders
    scope = ReadScope(transcript_path=str(payload.get("transcript_path") or ""), extra_folders=folders)
    reason = problem(str(payload.get("tool_name", "")), payload.get("tool_input") or {}, scope)
    if reason is None:
        return 0
    print(reason, file=sys.stderr)
    return BLOCK_EXIT_STATUS


if __name__ == "__main__":
    sys.exit(main())
