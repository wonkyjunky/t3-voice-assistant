"""Tests for the caption file voice.py writes for the avatar. Run: /opt/homebrew/bin/python3 tests/test_voice_caption.py"""
import os
import stat
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import voice  # noqa: E402


class CaptionTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.mkdtemp()
        self.original = voice.CAPTION_PATH
        voice.CAPTION_PATH = os.path.join(self.folder, "caption-bot.txt")

    def tearDown(self):
        voice.CAPTION_PATH = self.original

    def read(self):
        with open(voice.CAPTION_PATH, encoding="utf-8") as handle:
            return handle.read()

    def test_caption_is_the_reply_without_voice_tags(self):
        voice.set_caption("[cheerfully] 민준님, 테스트 다 통과했어요! [laughs] 대박")
        self.assertEqual(self.read(), "민준님, 테스트 다 통과했어요! 대박")

    def test_caption_only_the_user_can_read(self):
        voice.set_caption("비밀 얘기")
        mode = stat.S_IMODE(os.stat(voice.CAPTION_PATH).st_mode)
        self.assertEqual(mode, 0o600)

    def test_reply_of_only_tags_writes_nothing(self):
        voice.set_caption("[sighs]")
        self.assertFalse(os.path.exists(voice.CAPTION_PATH))

    def test_clear_removes_own_caption(self):
        voice.set_caption("[warmly] 알겠어")
        voice.clear_caption("[warmly] 알겠어")
        self.assertFalse(os.path.exists(voice.CAPTION_PATH))

    def test_clear_keeps_a_newer_reply(self):
        # A stopped speech finishing late must not remove the caption of the reply that replaced it.
        voice.set_caption("새 대답")
        voice.clear_caption("예전 대답")
        self.assertEqual(self.read(), "새 대답")

    def test_clear_without_caption_is_fine(self):
        voice.clear_caption("아무거나")
        self.assertFalse(os.path.exists(voice.CAPTION_PATH))

    def test_no_temporary_file_is_left(self):
        voice.set_caption("한 줄")
        self.assertEqual(os.listdir(self.folder), ["caption-bot.txt"])


if __name__ == "__main__":
    unittest.main()
