"""Tests for speech taking turns in voice.py: a new reply waits for the one playing instead of
cutting it off. Run: /opt/homebrew/bin/python3 tests/test_voice_queue.py"""
import os
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import voice  # noqa: E402

PATCHED = ("SPEECH_LOCK_PATH", "QUEUE_DIR", "STOP_PATH", "LOG_PATH", "SPEECH_WAIT_SECONDS")


class SpeechTurnTests(unittest.TestCase):
    def setUp(self):
        folder = tempfile.mkdtemp()
        self.saved = {name: getattr(voice, name) for name in PATCHED}
        voice.SPEECH_LOCK_PATH = os.path.join(folder, "speech.lock")
        voice.QUEUE_DIR = os.path.join(folder, "speech-queue")
        voice.STOP_PATH = os.path.join(folder, "speech-stopped")
        voice.LOG_PATH = os.path.join(folder, "speak.log")

    def tearDown(self):
        for name, value in self.saved.items():
            setattr(voice, name, value)

    def test_a_new_reply_waits_for_the_one_playing(self):
        order = []
        first_started = threading.Event()

        def first():
            with voice.speech_turn() as allowed:
                order.append(("first starts", allowed))
                first_started.set()
                time.sleep(0.4)
                order.append(("first ends", allowed))

        def second():
            first_started.wait()
            with voice.speech_turn() as allowed:
                order.append(("second starts", allowed))

        threads = [threading.Thread(target=first), threading.Thread(target=second)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(5)
        self.assertEqual(order, [("first starts", True), ("first ends", True), ("second starts", True)])

    def test_waiting_speech_counts_as_speaking(self):
        inside = threading.Event()
        release = threading.Event()

        def hold():
            with voice.speech_turn():
                inside.set()
                release.wait(5)

        thread = threading.Thread(target=hold)
        thread.start()
        inside.wait(5)
        self.assertTrue(voice.speech_pending())
        release.set()
        thread.join(5)
        self.assertFalse(voice.speech_pending())

    def test_speech_waiting_when_the_user_stops_her_is_dropped(self):
        holding = threading.Event()
        release = threading.Event()
        results = []

        def hold():
            with voice.speech_turn():
                holding.set()
                release.wait(5)

        def queued():
            with voice.speech_turn() as allowed:
                results.append(allowed)

        first = threading.Thread(target=hold)
        first.start()
        holding.wait(5)
        second = threading.Thread(target=queued)
        second.start()
        time.sleep(0.2)
        voice.mark_stopped()
        release.set()
        first.join(5)
        second.join(5)
        self.assertEqual(results, [False])

    def test_speech_after_a_stop_plays_normally(self):
        voice.mark_stopped()
        time.sleep(0.01)
        with voice.speech_turn() as allowed:
            self.assertTrue(allowed)

    def test_a_stuck_turn_is_not_waited_for_forever(self):
        voice.SPEECH_WAIT_SECONDS = 0.3
        release = threading.Event()
        inside = threading.Event()

        def stuck():
            with voice.speech_turn():
                inside.set()
                release.wait(5)

        thread = threading.Thread(target=stuck)
        thread.start()
        inside.wait(5)
        started = time.time()
        with voice.speech_turn() as allowed:
            waited = time.time() - started
        release.set()
        thread.join(5)
        self.assertTrue(allowed)
        self.assertLess(waited, 2)


if __name__ == "__main__":
    unittest.main()
