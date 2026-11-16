"""Tests for the voice thread check in speak.py. Run: python3 tests/test_speak.py"""
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import speak  # noqa: E402

THREAD_ID = "0b5e7c1d-2f3a-4b6c-8d9e-1a2b3c4d5e6f"


class VoiceThreadTests(unittest.TestCase):
    def setUp(self):
        folder = Path(tempfile.mkdtemp())
        self.id_file = folder / "voice-thread-id"
        self.id_file.write_text(THREAD_ID + "\n")
        self.saved = (speak.VOICE_THREAD_FILE, speak.thread_record)
        speak.VOICE_THREAD_FILE = str(self.id_file)
        self.record = {}
        speak.thread_record = lambda thread_id: self.record

    def tearDown(self):
        speak.VOICE_THREAD_FILE, speak.thread_record = self.saved

    def test_scratch_folder_ending_in_the_id_is_the_voice_thread(self):
        self.assertTrue(speak.is_voice_thread({"cwd": "/x/scratch/2026-01-01-3c4d5e6f"}))

    def test_folder_named_by_t3_is_the_voice_thread(self):
        self.record = {"worktreePath": "/Users/someone/projects/home"}
        self.assertTrue(speak.is_voice_thread({"cwd": "/Users/someone/projects/home/"}))

    def test_other_folder_is_not_the_voice_thread(self):
        self.record = {"worktreePath": "/Users/someone/projects/home"}
        self.assertFalse(speak.is_voice_thread({"cwd": "/Users/someone/projects/other"}))

    def test_unknown_folder_counts_as_the_voice_thread(self):
        self.record = {"worktreePath": None}
        self.assertTrue(speak.is_voice_thread({"cwd": "/Users/someone/projects/other"}))

    def test_missing_id_file_is_not_the_voice_thread(self):
        self.id_file.unlink()
        self.assertFalse(speak.is_voice_thread({"cwd": "/x/scratch/2026-01-01-3c4d5e6f"}))


if __name__ == "__main__":
    unittest.main()
