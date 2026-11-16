"""Tests for file_search.py. Run: /opt/homebrew/bin/python3 tests/test_file_search.py"""
import io
import os
import sys
import tempfile
import time
import unicodedata
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import file_search as fs  # noqa: E402


class SearchTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp()).resolve()
        self.notes = self.root / "Notes"
        (self.notes / "Projects" / "my-app").mkdir(parents=True)
        self.other = self.root / "Elsewhere"
        self.other.mkdir()

    def write(self, relative, text, folder=None, mtime=None):
        path = (folder or self.notes) / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        if mtime:
            os.utime(path, (mtime, mtime))
        return path

    def run_search(self, *argv):
        out, err = io.StringIO(), io.StringIO()
        status = fs.main(list(argv), roots=[self.notes], out=out, err=err)
        return status, out.getvalue().splitlines(), err.getvalue()

    def test_finds_files_containing_the_text_case_insensitively(self):
        note = self.write("Projects/my-app/결정.md", "Apple Developer 계정 등록 완료")
        self.write("Projects/other.md", "관계없는 내용")
        status, lines, _ = self.run_search("contains", "apple developer")
        self.assertEqual(status, 0)
        self.assertEqual(lines, [str(note)])

    def test_korean_in_decomposed_form_is_found(self):
        note = self.write("Projects/메모.md", unicodedata.normalize("NFD", "개발자 계정은 두 개"))
        status, lines, _ = self.run_search("contains", "개발자 계정")
        self.assertEqual((status, lines), (0, [str(note)]))

    def test_alternatives_split_by_a_bar_match_any(self):
        first = self.write("a.md", "Play Console 등록", mtime=1000)
        second = self.write("b.md", "개발자 계정", mtime=2000)
        status, lines, _ = self.run_search("contains", "play console|개발자 계정")
        self.assertEqual((status, lines), (0, [str(second), str(first)]))

    def test_finds_files_by_name(self):
        note = self.write(unicodedata.normalize("NFD", "Projects/my-app/my-app 결정.md"), "x")
        status, lines, _ = self.run_search("named", "app 결정")
        self.assertEqual(status, 0)
        self.assertEqual([unicodedata.normalize("NFC", line) for line in lines],
                         [unicodedata.normalize("NFC", str(note))])

    def test_secret_files_are_never_listed(self):
        self.write("app/.env", "API_KEY=개발자 계정")
        self.write("app/client_secret.json", "개발자 계정")
        status, lines, _ = self.run_search("contains", "개발자 계정")
        self.assertEqual((status, lines), (1, []))

    def test_hidden_folders_dependencies_and_binaries_are_skipped(self):
        self.write(".obsidian/cache.json", "개발자 계정")
        self.write("app/node_modules/pkg/readme.md", "개발자 계정")
        (self.notes / "image.bin").write_bytes(b"\x00\x01" + "개발자 계정".encode("utf-8"))
        status, lines, _ = self.run_search("contains", "개발자 계정")
        self.assertEqual((status, lines), (1, []))

    def test_a_folder_inside_the_readable_ones_narrows_the_search(self):
        inside = self.write("Projects/my-app/x.md", "목표")
        self.write("Projects/y.md", "목표")
        status, lines, _ = self.run_search("contains", "목표", str(self.notes / "Projects" / "my-app"))
        self.assertEqual((status, lines), (0, [str(inside)]))

    def test_a_folder_outside_the_readable_ones_is_refused(self):
        self.write("z.md", "목표", folder=self.other)
        status, lines, err = self.run_search("contains", "목표", str(self.other))
        self.assertEqual((status, lines), (fs.REFUSED, []))
        self.assertIn("readable", err)

    def test_escaping_with_dots_is_refused(self):
        status, _, _ = self.run_search("contains", "x", str(self.notes / ".." / "Elsewhere"))
        self.assertEqual(status, fs.REFUSED)

    def test_nothing_found(self):
        status, lines, err = self.run_search("named", "없는파일")
        self.assertEqual((status, lines), (fs.NOT_FOUND, []))
        self.assertIn("nothing", err)

    def test_results_are_capped_and_say_how_many_more(self):
        now = time.time()
        for index in range(fs.MAX_RESULTS + 5):
            self.write(f"many/{index}.md", "같은 말", mtime=now - index)
        status, lines, _ = self.run_search("contains", "같은 말")
        self.assertEqual(status, 0)
        self.assertEqual(len(lines), fs.MAX_RESULTS + 1)
        self.assertEqual(lines[0], str(self.notes / "many" / "0.md"))
        self.assertIn("5 more", lines[-1])

    def test_usage_errors(self):
        for argv in ([], ["contains"], ["contains", "  "], ["grep", "x"]):
            with self.subTest(argv=argv):
                status, _, _ = self.run_search(*argv)
                self.assertEqual(status, fs.USAGE)

    def test_default_roots_are_the_guard_read_folders(self):
        roots = fs.default_roots()
        self.assertIn(fs.tool_guard.HERE, roots)


if __name__ == "__main__":
    unittest.main()
