"""Tests for the loudness track voice.py writes for the avatar's sound bars.
Run: /opt/homebrew/bin/python3 tests/test_voice_levels.py"""
import math
import os
import struct
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import voice  # noqa: E402

FULL_SCALE = 32767


def pcm(amplitude, samples=800):
    """16-bit mono samples of a sine wave at the given peak (0 to 1)."""
    values = (int(FULL_SCALE * amplitude * math.sin(index / 5)) for index in range(samples))
    return struct.pack(f"<{samples}h", *values)


def mp3_tone_then_silence():
    """One second of a loud tone, then half a second of silence, as MP3 bytes."""
    result = subprocess.run(
        [voice.FFMPEG, "-loglevel", "quiet", "-f", "lavfi", "-i", "sine=frequency=220:duration=1",
         "-f", "lavfi", "-i", "anullsrc=r=44100:cl=mono", "-filter_complex",
         "[0:a]volume=0.5[tone];[1:a]atrim=duration=0.5[quiet];[tone][quiet]concat=n=2:v=0:a=1",
         "-f", "mp3", "pipe:1"],
        capture_output=True, check=True)
    return result.stdout


class LevelOfTests(unittest.TestCase):
    def test_silence_is_zero(self):
        self.assertEqual(voice.level_of(pcm(0)), 0)

    def test_full_scale_is_one(self):
        self.assertEqual(voice.level_of(pcm(1)), 1)

    def test_normal_speech_is_in_between(self):
        self.assertTrue(0.3 < voice.level_of(pcm(0.05)) < 0.9)

    def test_louder_is_higher(self):
        self.assertLess(voice.level_of(pcm(0.01)), voice.level_of(pcm(0.1)))

    def test_no_samples_is_zero(self):
        self.assertEqual(voice.level_of(b""), 0)


class LevelTrackTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.mkdtemp()
        self.original = (voice.LEVEL_PATH, voice.LOG_PATH)
        voice.LEVEL_PATH = os.path.join(self.folder, "level-bot.txt")
        voice.LOG_PATH = os.path.join(self.folder, "speak.log")

    def tearDown(self):
        voice.LEVEL_PATH, voice.LOG_PATH = self.original

    def lines(self):
        with open(voice.LEVEL_PATH, encoding="utf-8") as handle:
            return handle.read().splitlines()

    @unittest.skipUnless(os.path.exists(voice.FFMPEG), "needs ffmpeg")
    def test_track_follows_the_loudness_of_the_audio(self):
        track = voice.LevelTrack(started_at=1000.5)
        track.feed(mp3_tone_then_silence())
        track.finish()
        header, *values = self.lines()
        self.assertEqual(header, f"start 1000.500 step 0.05 pid {os.getpid()}")
        levels = [float(value) for value in values]
        self.assertTrue(28 <= len(levels) <= 32, len(levels))
        self.assertTrue(all(level > 0.5 for level in levels[2:18]), levels)
        self.assertTrue(all(level < 0.1 for level in levels[-6:]), levels)

    @unittest.skipUnless(os.path.exists(voice.FFMPEG), "needs ffmpeg")
    def test_levels_arrive_while_audio_is_still_coming(self):
        # The bars follow the voice as it plays, so values must not wait for the end of the reply.
        audio = mp3_tone_then_silence()
        track = voice.LevelTrack(started_at=1.0)
        try:
            track.feed(audio[: len(audio) // 2])
            deadline = time.time() + 2
            while len(self.lines()) < 2 and time.time() < deadline:
                time.sleep(0.05)
            self.assertGreater(len(self.lines()), 1)
        finally:
            track.finish()

    @unittest.skipUnless(os.path.exists(voice.FFMPEG), "needs ffmpeg")
    def test_track_file_is_private(self):
        track = voice.LevelTrack(started_at=1.0)
        track.finish()
        self.assertEqual(os.stat(voice.LEVEL_PATH).st_mode & 0o777, 0o600)

    def test_without_ffmpeg_nothing_breaks_and_nothing_is_written(self):
        original = voice.FFMPEG
        voice.FFMPEG = os.path.join(self.folder, "no-ffmpeg")
        try:
            track = voice.LevelTrack(started_at=1.0)
            track.feed(b"abc")
            track.finish()
        finally:
            voice.FFMPEG = original
        self.assertFalse(os.path.exists(voice.LEVEL_PATH))

    def test_clear_removes_own_track_only(self):
        with open(voice.LEVEL_PATH, "w", encoding="utf-8") as handle:
            handle.write("start 1.000 step 0.05 pid 1\n0.5\n")
        voice.clear_levels()
        self.assertTrue(os.path.exists(voice.LEVEL_PATH))
        with open(voice.LEVEL_PATH, "w", encoding="utf-8") as handle:
            handle.write(f"start 1.000 step 0.05 pid {os.getpid()}\n0.5\n")
        voice.clear_levels()
        self.assertFalse(os.path.exists(voice.LEVEL_PATH))


if __name__ == "__main__":
    unittest.main()
