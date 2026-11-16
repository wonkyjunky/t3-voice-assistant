"""Tests for mac_control.py. Run: /opt/homebrew/bin/python3 -m unittest discover -s tests"""
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import mac_control as mc  # noqa: E402


class FakeRunner:
    """Records commands and answers each with the next scripted (returncode, stdout)."""

    def __init__(self, *answers):
        self.answers = list(answers)
        self.calls = []

    def __call__(self, args):
        self.calls.append(list(args))
        answer = self.answers.pop(0) if self.answers else (0, "")
        return mc.Result(*answer)


def run_cli(argv, runner, state_dir=None, fetch=None):
    state_dir = state_dir or tempfile.mkdtemp()
    fetch = fetch or (lambda url: None)
    return mc.main(argv, runner=runner, state_dir=Path(state_dir), fetch=fetch)


SEARCH_PAGE = (
    '{"adSlotRenderer":{"videoId":"AAAAAAAAAAA"}},'
    '{"videoRenderer":{"videoId":"EjMTw4xLcBI","thumbnail":{"thumbnails":[]},'
    '"title":{"runs":[{"text":"IU - \\ubc24\\ud3b8\\uc9c0 \\u0026 Lyrics"}]}}},'
    '{"videoRenderer":{"videoId":"BzYnNdJhZQw","title":{"runs":[{"text":"second"}]}}}'
)


class VolumeTests(unittest.TestCase):
    def test_set_volume_sends_level_and_unmutes(self):
        runner = FakeRunner((0, ""))
        self.assertEqual(run_cli(["volume", "set", "40"], runner), mc.EXIT_OK)
        script = runner.calls[0][2]
        self.assertIn("output volume 40", script)
        self.assertIn("without output muted", script)

    def test_set_volume_rejects_out_of_range(self):
        runner = FakeRunner()
        self.assertEqual(run_cli(["volume", "set", "101"], runner), mc.EXIT_USAGE)
        self.assertEqual(runner.calls, [])

    def test_volume_up_clamps_at_maximum(self):
        runner = FakeRunner((0, "95"), (0, ""))
        self.assertEqual(run_cli(["volume", "up"], runner), mc.EXIT_OK)
        self.assertIn("output volume 100", runner.calls[1][2])

    def test_volume_down_clamps_at_zero(self):
        runner = FakeRunner((0, "5"), (0, ""))
        self.assertEqual(run_cli(["volume", "down"], runner), mc.EXIT_OK)
        self.assertIn("output volume 0", runner.calls[1][2])

    def test_osascript_failure_reports_system_error(self):
        runner = FakeRunner((1, ""))
        self.assertEqual(run_cli(["volume", "mute"], runner), mc.EXIT_FAILED)


class MusicTests(unittest.TestCase):
    def test_song_query_is_passed_as_argument_not_in_script(self):
        query = 'IU "Blueming"'
        runner = FakeRunner((0, "Blueming - IU"))
        self.assertEqual(run_cli(["music", "song", query], runner), mc.EXIT_OK)
        call = runner.calls[0]
        self.assertEqual(call[-1], query)
        self.assertNotIn("Blueming", call[2])

    def test_song_without_match_is_not_found(self):
        runner = FakeRunner((0, ""))
        self.assertEqual(run_cli(["music", "song", "nothing here"], runner), mc.EXIT_NOT_FOUND)

    def test_missing_playlist_is_not_found(self):
        runner = FakeRunner((0, ""))
        self.assertEqual(run_cli(["music", "playlist", "Gym"], runner), mc.EXIT_NOT_FOUND)

    def test_next_track_command(self):
        runner = FakeRunner((0, ""))
        self.assertEqual(run_cli(["music", "next"], runner), mc.EXIT_OK)
        self.assertIn("next track", runner.calls[0][2])

    def test_empty_song_query_is_usage_error(self):
        self.assertEqual(run_cli(["music", "song", "  "], FakeRunner()), mc.EXIT_USAGE)


class DuckTests(unittest.TestCase):
    def setUp(self):
        self.state_dir = Path(tempfile.mkdtemp())
        self.state_file = self.state_dir / mc.DUCK_STATE_NAME

    def test_duck_saves_volume_and_lowers_it(self):
        runner = FakeRunner((0, "80"), (0, ""))
        self.assertEqual(run_cli(["music", "duck"], runner, self.state_dir), mc.EXIT_OK)
        self.assertEqual(self.state_file.read_text().strip(), "80")
        self.assertEqual(runner.calls[1][-1], "24")

    def test_duck_does_nothing_when_music_is_not_playing(self):
        runner = FakeRunner((0, ""))
        self.assertEqual(run_cli(["music", "duck"], runner, self.state_dir), mc.EXIT_OK)
        self.assertFalse(self.state_file.exists())
        self.assertEqual(len(runner.calls), 1)

    def test_duck_twice_keeps_the_first_saved_volume(self):
        self.state_file.write_text("80\n")
        runner = FakeRunner()
        self.assertEqual(run_cli(["music", "duck"], runner, self.state_dir), mc.EXIT_OK)
        self.assertEqual(runner.calls, [])
        self.assertEqual(self.state_file.read_text().strip(), "80")

    def test_unduck_restores_and_removes_state(self):
        self.state_file.write_text("80\n")
        runner = FakeRunner((0, ""))
        self.assertEqual(run_cli(["music", "unduck"], runner, self.state_dir), mc.EXIT_OK)
        self.assertEqual(runner.calls[0][-1], "80")
        self.assertFalse(self.state_file.exists())

    def test_unduck_without_state_does_nothing(self):
        runner = FakeRunner()
        self.assertEqual(run_cli(["music", "unduck"], runner, self.state_dir), mc.EXIT_OK)
        self.assertEqual(runner.calls, [])

    def test_unduck_with_corrupt_state_removes_it(self):
        self.state_file.write_text("loud\n")
        runner = FakeRunner()
        self.assertEqual(run_cli(["music", "unduck"], runner, self.state_dir), mc.EXIT_FAILED)
        self.assertFalse(self.state_file.exists())


class YoutubeTests(unittest.TestCase):
    def test_youtube_search_opens_encoded_search_url(self):
        runner = FakeRunner((0, ""))
        self.assertEqual(run_cli(["youtube", "search", "아이유 밤편지"], runner), mc.EXIT_OK)
        url = runner.calls[0][-1]
        self.assertTrue(url.startswith("https://www.youtube.com/results?search_query="))
        self.assertNotIn(" ", url)

    def test_first_video_skips_ads_and_decodes_title(self):
        self.assertEqual(mc.first_video(SEARCH_PAGE), ("EjMTw4xLcBI", "IU - 밤편지 & Lyrics"))

    def test_first_video_without_results_is_none(self):
        self.assertIsNone(mc.first_video('{"videoRenderer":{"videoId":"short"}}'))

    def test_first_video_reads_newer_lockup_layout(self):
        page = ('{"lockupViewModel":{"contentImage":{},"metadata":{"lockupMetadataViewModel":'
                '{"title":{"content":"IU Playlist"}}},"contentId":"hyRjJG5mq_Q",'
                '"contentType":"LOCKUP_CONTENT_TYPE_VIDEO"}}')
        self.assertEqual(mc.first_video(page), ("hyRjJG5mq_Q", ""))

    def test_first_video_falls_back_to_first_watch_link(self):
        page = '{"url":"/watch?v=IHIt9S2DWcQ\\u0026list=RD"}'
        self.assertEqual(mc.first_video(page), ("IHIt9S2DWcQ", ""))

    def test_youtube_play_miss_keeps_page_for_diagnosis(self):
        state_dir = Path(tempfile.mkdtemp())
        runner = FakeRunner((0, ""))
        run_cli(["youtube", "play", "zzz"], runner, state_dir, fetch=lambda url: "<html>odd</html>")
        self.assertEqual((state_dir / mc.YOUTUBE_MISS_NAME).read_text(), "<html>odd</html>")

    def test_youtube_play_opens_first_video(self):
        runner = FakeRunner((0, ""))
        fetched = []
        fetch = lambda url: fetched.append(url) or SEARCH_PAGE
        self.assertEqual(run_cli(["youtube", "play", "아이유 밤편지"], runner, fetch=fetch), mc.EXIT_OK)
        self.assertTrue(fetched[0].startswith(mc.YOUTUBE_SEARCH_URL))
        self.assertEqual(runner.calls[0], [mc.OPEN, "https://www.youtube.com/watch?v=EjMTw4xLcBI"])

    def test_youtube_play_falls_back_to_search_when_no_video_found(self):
        runner = FakeRunner((0, ""))
        code = run_cli(["youtube", "play", "zzz"], runner, fetch=lambda url: "<html></html>")
        self.assertEqual(code, mc.EXIT_NOT_FOUND)
        self.assertTrue(runner.calls[0][-1].startswith(mc.YOUTUBE_SEARCH_URL))

    def test_youtube_play_falls_back_to_search_when_youtube_unreachable(self):
        runner = FakeRunner((0, ""))
        code = run_cli(["youtube", "play", "zzz"], runner, fetch=lambda url: None)
        self.assertEqual(code, mc.EXIT_NOT_FOUND)
        self.assertTrue(runner.calls[0][-1].startswith(mc.YOUTUBE_SEARCH_URL))


class YoutubeControlTests(unittest.TestCase):
    def setUp(self):
        self.state_dir = Path(tempfile.mkdtemp())
        self.marker = self.state_dir / mc.YOUTUBE_DUCK_NAME

    def test_pause_sends_fixed_javascript_as_argument(self):
        runner = FakeRunner((0, "paused"))
        self.assertEqual(run_cli(["youtube", "pause"], runner), mc.EXIT_OK)
        call = runner.calls[0]
        self.assertEqual(call[:2], [mc.OSASCRIPT, "-e"])
        self.assertIn("pause()", call[3])
        self.assertEqual(call[4], "all")

    def test_pause_without_youtube_tab_is_not_found(self):
        runner = FakeRunner((0, "no-tab"))
        self.assertEqual(run_cli(["youtube", "pause"], runner), mc.EXIT_NOT_FOUND)

    def test_pause_when_chrome_is_not_running_is_not_found(self):
        runner = FakeRunner((0, "no-browser"))
        self.assertEqual(run_cli(["youtube", "pause"], runner), mc.EXIT_NOT_FOUND)

    def test_chrome_javascript_turned_off_is_explained(self):
        stderr = "execution error: Google Chrome got an error: Executing JavaScript through AppleScript is turned off."
        runner = FakeRunner((1, "", stderr))
        self.assertEqual(run_cli(["youtube", "pause"], runner), mc.EXIT_FAILED)

    def test_resume_plays_first_tab_when_none_was_paused_by_the_assistant(self):
        runner = FakeRunner((0, "unmarked\nunmarked"), (0, "resumed"))
        self.assertEqual(run_cli(["youtube", "resume"], runner), mc.EXIT_OK)
        self.assertEqual(runner.calls[1][4], "first")

    def test_resume_of_paused_tab_needs_one_call(self):
        runner = FakeRunner((0, "resumed\nunmarked"))
        self.assertEqual(run_cli(["youtube", "resume"], runner), mc.EXIT_OK)
        self.assertEqual(len(runner.calls), 1)

    def test_next_with_nothing_playing_is_not_found(self):
        runner = FakeRunner((0, "skip\nskip"))
        self.assertEqual(run_cli(["youtube", "next"], runner), mc.EXIT_NOT_FOUND)

    def test_now_reports_playing_title(self):
        runner = FakeRunner((0, "paused:Old\nplaying:IU Playlist"))
        self.assertEqual(run_cli(["youtube", "now"], runner), mc.EXIT_OK)

    def test_duck_leaves_marker_only_when_a_tab_was_lowered(self):
        self.assertEqual(run_cli(["youtube", "duck"], FakeRunner((0, "idle")), self.state_dir), mc.EXIT_OK)
        self.assertFalse(self.marker.exists())
        self.assertEqual(run_cli(["youtube", "duck"], FakeRunner((0, "ducked")), self.state_dir), mc.EXIT_OK)
        self.assertTrue(self.marker.exists())

    def test_duck_skips_chrome_when_it_is_not_running(self):
        runner = FakeRunner((0, "no-browser"))
        self.assertEqual(run_cli(["youtube", "duck"], runner, self.state_dir), mc.EXIT_OK)
        self.assertFalse(self.marker.exists())

    def test_unduck_without_marker_never_touches_chrome(self):
        runner = FakeRunner()
        self.assertEqual(run_cli(["youtube", "unduck"], runner, self.state_dir), mc.EXIT_OK)
        self.assertEqual(runner.calls, [])

    def test_unduck_restores_and_removes_marker(self):
        self.marker.write_text("1\n")
        runner = FakeRunner((0, "restored"))
        self.assertEqual(run_cli(["youtube", "unduck"], runner, self.state_dir), mc.EXIT_OK)
        self.assertIn("__assistantVolume", runner.calls[0][3])
        self.assertFalse(self.marker.exists())


class AppTests(unittest.TestCase):
    def test_open_app_uses_open_dash_a(self):
        runner = FakeRunner((0, ""))
        self.assertEqual(run_cli(["app", "open", "Safari"], runner), mc.EXIT_OK)
        self.assertEqual(runner.calls[0], ["/usr/bin/open", "-a", "Safari"])

    def test_open_unknown_app_is_not_found(self):
        runner = FakeRunner((1, ""))
        self.assertEqual(run_cli(["app", "open", "Nope"], runner), mc.EXIT_NOT_FOUND)

    def test_app_name_with_path_is_rejected(self):
        runner = FakeRunner()
        self.assertEqual(run_cli(["app", "open", "/tmp/evil.app"], runner), mc.EXIT_USAGE)
        self.assertEqual(runner.calls, [])

    def test_quitting_protected_app_is_refused(self):
        runner = FakeRunner()
        self.assertEqual(run_cli(["app", "quit", "t3 code (beta)"], runner), mc.EXIT_REFUSED)
        self.assertEqual(runner.calls, [])

    def test_quit_checks_running_apps_through_system_events(self):
        # "application X is running" asks where X is when no such app exists, and hangs.
        self.assertIn('application "System Events"', mc.QUIT_APP_SCRIPT)
        self.assertNotIn("application appName is running", mc.QUIT_APP_SCRIPT)

    def test_quit_app_not_running_is_not_found(self):
        runner = FakeRunner((0, "not running"))
        self.assertEqual(run_cli(["app", "quit", "Safari"], runner), mc.EXIT_NOT_FOUND)

    def test_quit_app_passes_name_as_argument(self):
        runner = FakeRunner((0, "quit"))
        self.assertEqual(run_cli(["app", "quit", "Safari"], runner), mc.EXIT_OK)
        self.assertEqual(runner.calls[0][-1], "Safari")


class CliTests(unittest.TestCase):
    def test_unknown_command_is_usage_error(self):
        self.assertEqual(run_cli(["dance"], FakeRunner()), mc.EXIT_USAGE)


if __name__ == "__main__":
    unittest.main()
