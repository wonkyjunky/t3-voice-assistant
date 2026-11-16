"""Tests for the voice language voice.py picks per reply. Run: /opt/homebrew/bin/python3 tests/test_voice_language.py"""
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import voice  # noqa: E402


class LanguageTests(unittest.TestCase):
    def setUp(self):
        # Never read the real setting the avatar's menu writes next to voice.py.
        self.original_primary = voice.PRIMARY_LANGUAGE_PATH
        voice.PRIMARY_LANGUAGE_PATH = os.path.join(tempfile.mkdtemp(), "primary-language")

    def tearDown(self):
        voice.PRIMARY_LANGUAGE_PATH = self.original_primary

    def test_korean_with_english_words_stays_korean(self):
        self.assertEqual(voice.language_of("[cheerfully] 민준님, YouTube에서 아이유 노래 틀었어요!"), "ko")
        self.assertEqual(voice.language_of("Play Console 계정은 새 개인 계정이에요."), "ko")

    def test_english_reply_is_english(self):
        self.assertEqual(voice.language_of("[cheerfully] Hi Alex, the build passed!"), "en")

    def test_english_with_a_korean_name_is_english(self):
        self.assertEqual(voice.language_of("I put on some 아이유 songs for you on YouTube."), "en")

    def test_voice_tags_do_not_count_as_english(self):
        self.assertEqual(voice.language_of("[excited] [laughs] 대박!"), "ko")

    def test_no_letters_falls_back_to_korean(self):
        self.assertEqual(voice.language_of(""), "ko")
        self.assertEqual(voice.language_of("12,345 !!"), "ko")

    def test_no_letters_follows_the_primary_language_setting(self):
        with open(voice.PRIMARY_LANGUAGE_PATH, "w", encoding="utf-8") as handle:
            handle.write("en\n")
        self.assertEqual(voice.language_of("12,345 !!"), "en")
        self.assertEqual(voice.language_of("다 됐어"), "ko")

    def test_request_carries_the_reply_language(self):
        self.assertEqual(json.loads(voice.elevenlabs_body("Done, the tests passed."))["language_code"], "en")
        body = json.loads(voice.elevenlabs_body("다 됐어!"))
        self.assertEqual((body["language_code"], body["text"], body["model_id"]), ("ko", "다 됐어!", voice.MODEL_ID))

    def test_usage_line_in_english_and_korean(self):
        self.assertEqual(voice.usage_line(6736, 156736, "en"), "150,000 of 156,736 characters left")
        self.assertEqual(voice.usage_line(6736, 156736, "ko"), "남은 글자 150,000 / 156,736")
        self.assertEqual(voice.usage_line(200, 100, "en"), "0 of 100 characters left")

    def test_usage_problems_in_english_and_korean(self):
        self.assertEqual(voice.USAGE_PROBLEMS["en"]["no key"], "usage: no key")
        self.assertEqual(voice.USAGE_PROBLEMS["ko"]["unknown"], "사용량: 확인 못 함")

    def test_fallback_voice_follows_the_language(self):
        self.assertEqual(voice.fallback_voice_for("All done."), "Samantha")
        self.assertEqual(voice.fallback_voice_for("다 됐어."), "Yuna")


if __name__ == "__main__":
    unittest.main()
