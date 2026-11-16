"""Replies to messages typed in the chat stay in the chat; spoken ones are read aloud.
Run: python3 -m unittest discover -s tests"""
import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import speak  # noqa: E402

NOW = 1_800_000_000


def transcript(folder, *prompts):
    path = Path(folder) / "t.jsonl"
    lines = []
    for prompt in prompts:
        lines.append({"type": "user", "message": {"role": "user", "content": prompt}})
        lines.append({"type": "assistant", "message": {"content": [{"type": "text", "text": "응"}]}})
    path.write_text("\n".join(json.dumps(line, ensure_ascii=False) for line in lines) + "\n", encoding="utf-8")
    return str(path)


def digest(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


class TypedInChatTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.mkdtemp()
        self.saved = speak.VOICE_SENT_PATH
        speak.VOICE_SENT_PATH = str(Path(self.folder) / "voice-sent")

    def tearDown(self):
        speak.VOICE_SENT_PATH = self.saved

    def said(self, text, when=NOW - 5):
        with open(speak.VOICE_SENT_PATH, "a", encoding="utf-8") as handle:
            handle.write(f"{when} {digest(text)}\n")

    def test_a_typed_message_is_answered_in_the_chat_only(self):
        path = transcript(self.folder, "뭔가 아이디어 없을까")
        self.assertTrue(speak.typed_in_chat(path, now=NOW))

    def test_words_sent_by_the_voice_system_are_spoken(self):
        self.said("노래 틀어 줘")
        path = transcript(self.folder, "노래 틀어 줘")
        self.assertFalse(speak.typed_in_chat(path, now=NOW))

    def test_only_the_last_message_counts(self):
        self.said("노래 틀어 줘")
        path = transcript(self.folder, "노래 틀어 줘", "이건 쳐서 보냈어")
        self.assertTrue(speak.typed_in_chat(path, now=NOW))

    def test_an_old_voice_send_does_not_count(self):
        self.said("노래 틀어 줘", when=NOW - speak.VOICE_SENT_MAX_AGE_SECONDS - 1)
        path = transcript(self.folder, "노래 틀어 줘")
        self.assertTrue(speak.typed_in_chat(path, now=NOW))

    def test_automatic_notices_are_still_spoken(self):
        for notice in ("[마일스톤] 앱: 다 됐어요.", "[알림] 크레딧이 적어요.", "[아침 브리핑] 밤사이 소식"):
            path = transcript(self.folder, notice)
            self.assertFalse(speak.typed_in_chat(path, now=NOW), notice)

    def test_no_marker_file_means_typed(self):
        path = transcript(self.folder, "안녕")
        self.assertTrue(speak.typed_in_chat(path, now=NOW))

    def test_a_broken_marker_line_is_skipped(self):
        Path(speak.VOICE_SENT_PATH).write_text("garbage\n", encoding="utf-8")
        self.said("안녕")
        path = transcript(self.folder, "안녕")
        self.assertFalse(speak.typed_in_chat(path, now=NOW))


class VoiceThreadTests(unittest.TestCase):
    def test_every_assistants_thread_counts_as_a_voice_thread(self):
        folder = Path(tempfile.mkdtemp())
        first, second = folder / "a", folder / "b"
        first.write_text("thread-aaaaaaaa11111111\n", encoding="utf-8")
        second.write_text("mcp:launch:bbbbbbbb22222222\n", encoding="utf-8")
        saved = (speak.voice_thread_files, speak.thread_record)
        speak.voice_thread_files = lambda: [str(first), str(second)]
        speak.thread_record = lambda thread_id: {"worktreePath": "/elsewhere"}
        try:
            self.assertTrue(speak.is_voice_thread({"cwd": "/x/scratch-22222222"}))
            self.assertTrue(speak.is_voice_thread({"cwd": "/x/scratch-11111111/"}))
            self.assertFalse(speak.is_voice_thread({"cwd": "/x/scratch-33333333"}))
        finally:
            speak.voice_thread_files, speak.thread_record = saved


if __name__ == "__main__":
    unittest.main()
