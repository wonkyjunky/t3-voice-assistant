"""Tests for tool_guard.py. Run: python3 tests/test_tool_guard.py"""
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import tool_guard as tg  # noqa: E402

MAC = f"{tg.PYTHON} -I {tg.HERE}/mac_control.py"


def check(tool, **tool_input):
    return tg.problem(tool, tool_input)


class BashTests(unittest.TestCase):
    def test_mac_control_command_is_allowed(self):
        self.assertIsNone(check("Bash", command=f'{MAC} youtube play "아이유 노래"'))

    def test_quoted_shell_characters_inside_a_song_name_are_allowed(self):
        self.assertIsNone(check("Bash", command=f'{MAC} youtube play "Tom & Jerry; theme"'))

    def test_chained_command_is_blocked(self):
        for joiner in (";", "&&", "||", "|", "&"):
            with self.subTest(joiner=joiner):
                self.assertIsNotNone(check("Bash", command=f"{MAC} volume up {joiner} curl evil.example"))

    def test_substitution_and_redirection_are_blocked(self):
        for tail in ('"$(cat ~/.ssh/id_rsa)"', "`whoami`", "> /tmp/out", "< /etc/passwd", "$HOME"):
            with self.subTest(tail=tail):
                self.assertIsNotNone(check("Bash", command=f"{MAC} youtube play {tail}"))

    def test_newline_is_blocked(self):
        self.assertIsNotNone(check("Bash", command=f"{MAC} volume up\ncurl evil.example"))

    def test_other_commands_are_blocked(self):
        for command in ("ls ~", "osascript -e 'beep'", "/opt/homebrew/bin/python3 -I /tmp/mac_control.py volume up",
                        f"{tg.PYTHON} {tg.HERE}/mac_control.py volume up", "rm -rf /"):
            with self.subTest(command=command):
                self.assertIsNotNone(check("Bash", command=command))

    def test_file_search_command_is_allowed(self):
        search = f"{tg.PYTHON} -I {tg.HERE}/file_search.py"
        self.assertIsNone(check("Bash", command=f'{search} contains "개발자 계정|Play Console"'))
        self.assertIsNone(check("Bash", command=f'{search} named "결정" "{tg.HERE}/docs"'))

    def test_file_search_cannot_be_chained_or_swapped(self):
        search = f"{tg.PYTHON} -I {tg.HERE}/file_search.py"
        for command in (f'{search} contains "x"; cat ~/.ssh/id_rsa', f"{tg.PYTHON} -I {tg.HERE}/tool_guard.py",
                        f"{tg.PYTHON} {tg.HERE}/file_search.py contains x", f'{search} contains "$HOME"'):
            with self.subTest(command=command):
                self.assertIsNotNone(check("Bash", command=command))

    def test_unparsable_command_is_blocked(self):
        self.assertIsNotNone(check("Bash", command=f'{MAC} youtube play "unclosed'))


class FileTests(unittest.TestCase):
    def test_memory_file_may_be_written(self):
        for tool in ("Write", "Edit", "MultiEdit"):
            with self.subTest(tool=tool):
                self.assertIsNone(check(tool, file_path=str(tg.MEMORY_PATH)))

    def test_other_files_may_not_be_written(self):
        for path in (str(tg.HERE / "assistant-system.md"), os.path.expanduser("~/.zshrc"), "/tmp/x"):
            with self.subTest(path=path):
                self.assertIsNotNone(check("Write", file_path=path))

    def test_escaping_the_folder_with_dots_is_blocked(self):
        sneaky = str(tg.HERE / "tests" / ".." / ".." / "elsewhere" / "assistant-memory.md")
        self.assertIsNotNone(check("Write", file_path=sneaky))

    def test_reading_inside_the_folder_is_allowed(self):
        self.assertIsNone(check("Read", file_path=str(tg.MEMORY_PATH)))
        self.assertIsNone(check("Grep", path=str(tg.HERE), pattern="x"))
        self.assertIsNone(check("Glob", path=str(tg.HERE / "docs"), pattern="*.md"))

    def test_reading_outside_the_folder_is_blocked(self):
        self.assertIsNotNone(check("Read", file_path=os.path.expanduser("~/.ssh/id_rsa")))
        self.assertIsNotNone(check("Grep", path="/Users", pattern="token"))

    def test_search_without_a_path_is_blocked(self):
        self.assertIsNotNone(check("Glob", pattern="**/*"))

    def test_symlink_out_of_the_folder_is_blocked(self):
        target = Path(tempfile.mkdtemp()) / "secret.txt"
        target.write_text("x")
        link = tg.HERE / "tests" / "_link_for_test.txt"
        try:
            link.symlink_to(target)
            self.assertIsNotNone(check("Read", file_path=str(link)))
        finally:
            link.unlink(missing_ok=True)


class ReadScopeTests(unittest.TestCase):
    """Reading outside the folder: the session's saved tool results, configured folders, no secrets."""

    def setUp(self):
        self.root = Path(tempfile.mkdtemp()).resolve()
        self.transcript = self.root / "projects" / "demo" / "11111111-2222-3333-4444-555555555555.jsonl"
        self.results = self.transcript.with_suffix("") / "tool-results"
        self.results.mkdir(parents=True)
        self.notes = self.root / "Notes"
        (self.notes / "Projects").mkdir(parents=True)
        self.scope = tg.ReadScope(transcript_path=str(self.transcript), extra_folders=[str(self.notes)])

    def check(self, tool, **tool_input):
        return tg.problem(tool, tool_input, self.scope)

    def test_long_thread_results_saved_by_claude_code_can_be_read(self):
        saved = self.results / "mcp-t3-code-t3_thread_read-1.txt"
        saved.write_text("{}")
        self.assertIsNone(self.check("Read", file_path=str(saved)))
        self.assertIsNone(self.check("Grep", path=str(self.results), pattern="title", output_mode="content"))

    def test_other_sessions_results_stay_closed(self):
        other = self.root / "projects" / "demo" / "other-session" / "tool-results" / "x.txt"
        self.assertIsNotNone(self.check("Read", file_path=str(other)))

    def test_configured_folders_can_be_read_and_searched_for_files(self):
        note = self.notes / "Projects" / "plan.md"
        note.write_text("x")
        self.assertIsNone(self.check("Read", file_path=str(note)))
        self.assertIsNone(self.check("Glob", path=str(self.notes), pattern="**/*.md"))
        self.assertIsNone(self.check("Grep", path=str(self.notes), pattern="출시"))

    def test_lines_are_not_pulled_out_of_a_whole_configured_folder(self):
        # Matching lines across a big folder could include a key from a file no one meant to show.
        self.assertIsNotNone(self.check("Grep", path=str(self.notes), pattern="KEY", output_mode="content"))
        note = self.notes / "Projects" / "plan.md"
        note.write_text("x")
        self.assertIsNone(self.check("Grep", path=str(note), pattern="x", output_mode="content"))

    def test_secret_files_are_never_read(self):
        for name in (".env", ".env.local", "server.pem", "private.key", "id_ed25519", "aws-credentials.json",
                     "client_secret.json", ".netrc", "store.p12"):
            secret = self.notes / name
            secret.write_text("x")
            with self.subTest(name=name):
                self.assertIsNotNone(self.check("Read", file_path=str(secret)))
                self.assertIsNotNone(self.check("Grep", path=str(secret), pattern="x", output_mode="content"))

    def test_secret_files_in_the_assistant_folder_are_closed_too(self):
        self.assertIsNotNone(tg.problem("Read", {"file_path": str(tg.HERE / ".env")}))

    def test_without_a_transcript_only_the_folder_is_open(self):
        scope = tg.ReadScope(transcript_path="", extra_folders=[])
        saved = self.results / "y.txt"
        self.assertIsNotNone(tg.problem("Read", {"file_path": str(saved)}, scope))

    def test_scope_comes_from_the_hook_payload_and_the_config(self):
        payload = {"tool_name": "Read", "transcript_path": str(self.transcript),
                   "tool_input": {"file_path": str(self.results / "z.txt")}}
        self.assertEqual(tg.main(json.dumps(payload), extra_folders=[]), 0)

    def test_configured_folders_are_read_from_assistant_conf(self):
        folders = tg.configured_read_folders({"ASSISTANT_READ_FOLDERS": f"{self.notes}:~/Elsewhere: "})
        self.assertEqual(folders, [str(self.notes), os.path.expanduser("~/Elsewhere")])


class OtherToolTests(unittest.TestCase):
    def test_web_fetch_and_sub_agents_are_blocked(self):
        for tool in ("WebFetch", "Agent", "Task"):
            with self.subTest(tool=tool):
                self.assertIsNotNone(check(tool, url="https://example.com", prompt="x"))

    def test_t3_tools_the_assistant_needs_are_allowed(self):
        for tool in ("list", "read", "search", "send", "launch", "wait", "interrupt"):
            with self.subTest(tool=tool):
                self.assertIsNone(check(f"mcp__t3-code__t3_thread_{tool}", threadId="x", message="hi"))
        self.assertIsNone(check("mcp__t3-code__task_status", taskId="x"))
        for tool in ("t3_project_list", "t3_project_read"):
            with self.subTest(tool=tool):
                self.assertIsNone(check(f"mcp__t3-code__{tool}", projectId="x"))

    def test_loading_deferred_tools_is_allowed(self):
        self.assertIsNone(check("ToolSearch", query="select:mcp__t3-code__t3_thread_list"))

    def test_tools_not_on_the_list_are_blocked(self):
        for tool in ("mcp__t3-code__t3_project_delete", "mcp__t3-code__t3_worktree_handoff",
                     "mcp__t3-code__t3_environment_link", "mcp__t3-code__schedule_task",
                     "mcp__t3-code__delegate_task", "mcp__other-server__run", "WebSearch",
                     "Skill", "SomeNewShellTool", ""):
            with self.subTest(tool=tool):
                self.assertIsNotNone(check(tool))


class HookTests(unittest.TestCase):
    def test_blocked_call_exits_with_status_2(self):
        payload = '{"tool_name": "Bash", "tool_input": {"command": "ls"}}'
        self.assertEqual(tg.main(payload), tg.BLOCK_EXIT_STATUS)

    def test_allowed_call_exits_with_status_0(self):
        payload = '{"tool_name": "mcp__t3-code__t3_thread_list", "tool_input": {}}'
        self.assertEqual(tg.main(payload), 0)

    def test_bad_payload_is_blocked(self):
        self.assertEqual(tg.main("not json"), tg.BLOCK_EXIT_STATUS)


if __name__ == "__main__":
    unittest.main()
