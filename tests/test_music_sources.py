"""Tests for music_sources.py. Run: /opt/homebrew/bin/python3 -m unittest discover -s tests"""
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import music_sources as ms  # noqa: E402


class Place:
    """A music source with a state that pause, resume and skip change, recording what happened."""

    def __init__(self, name, state):
        self.state_now = state
        self.done = []
        self.source = ms.Source(
            name, name.title(), lambda ctx: self.state_now,
            pause=lambda ctx: self.act("pause", ms.PAUSED),
            resume=lambda ctx: self.act("resume", ms.PLAYING),
            skip=lambda ctx: self.act("skip", self.state_now),
            now=lambda ctx: self.act("now", self.state_now) or ms.EXIT_OK,
        )

    def act(self, what, state):
        self.done.append(what)
        self.state_now = state


def context():
    return SimpleNamespace(state_dir=Path(tempfile.mkdtemp()))


class MusicSourcesTests(unittest.TestCase):
    def test_starting_music_pauses_only_what_plays_elsewhere(self):
        player, chrome, music = Place("player", ms.PLAYING), Place("chrome", ms.PAUSED), Place("music", None)
        ms.pause_others(context(), [player.source, chrome.source, music.source], keep="music")
        self.assertEqual((player.done, chrome.done, music.done), (["pause"], [], []))

    def test_the_place_starting_music_is_left_alone(self):
        music = Place("music", ms.PLAYING)
        ms.pause_others(context(), [music.source], keep="music")
        self.assertEqual(music.done, [])

    def test_pause_then_resume_plays_again_what_was_paused(self):
        ctx = context()
        player, music = Place("player", ms.PAUSED), Place("music", ms.PLAYING)
        sources = [player.source, music.source]
        self.assertEqual(ms.control("pause", ctx, sources), ms.EXIT_OK)
        self.assertEqual(ms.control("resume", ctx, sources), ms.EXIT_OK)
        self.assertEqual(music.done, ["pause", "resume"])
        self.assertEqual(player.done, [], "the player paused before stays paused")

    def test_resume_without_a_memory_takes_the_first_paused_place(self):
        player, music = Place("player", ms.PAUSED), Place("music", ms.PAUSED)
        ms.control("resume", context(), [player.source, music.source])
        self.assertEqual(player.done, ["resume"])

    def test_next_and_now_go_to_the_place_that_plays(self):
        player, music = Place("player", ms.PAUSED), Place("music", ms.PLAYING)
        sources = [player.source, music.source]
        ms.control("next", context(), sources)
        ms.control("now", context(), sources)
        self.assertEqual(music.done, ["skip", "now"])
        self.assertEqual(player.done, [])

    def test_nothing_playing_is_not_found(self):
        self.assertEqual(ms.control("pause", context(), [Place("music", None).source]), ms.EXIT_NOT_FOUND)
        self.assertEqual(ms.control("next", context(), [Place("music", ms.PAUSED).source]), ms.EXIT_NOT_FOUND)


if __name__ == "__main__":
    unittest.main()
