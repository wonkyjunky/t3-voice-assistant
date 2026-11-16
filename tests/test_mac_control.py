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


def run_cli(argv, runner, state_dir=None, fetch=None, spawned=None):
    state_dir = Path(state_dir or tempfile.mkdtemp())
    fetch = fetch or (lambda url: None)
    clock = FakeClock()
    return mc.main(argv, runner=runner, state_dir=state_dir, fetch=fetch, sleep=clock.sleep, clock=clock,
                   spawn=spawned.start if spawned else FakeSpawn().start)


class FakeSpawn:
    """Records background helpers instead of starting them (the real one hides the real Music)."""

    def __init__(self):
        self.started = []

    def start(self, args):
        self.started.append(args)
        return self


# What the state checks before starting music see when nothing else plays: no Chrome tab, Music closed.
NOTHING_ELSE_PLAYS = [(0, "no-browser"), (0, "")]


class FakeClock:
    """Time that moves only when the code under test sleeps."""

    def __init__(self):
        self.now = 0.0

    def __call__(self):
        return self.now

    def sleep(self, seconds):
        self.now = round(self.now + seconds, 6)


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


CATALOG_ANSWER = (
    '{"resultCount":1,"results":[{"trackId":1712645271,"collectionId":1712644900,'
    '"trackName":"Shika","artistName":"Zuchu"}]}'
)


class MusicApp:
    """Answers mac_control's Music scripts like the app would: its library is empty; a song page
    opened with open -g becomes playable after loads_after plays, and play starts its album (the
    tracks in album) from the first track."""

    def __init__(self, running, loads_after, album=("Shika",), front="com.apple.Safari"):
        self.running = running
        self.loads_after = loads_after
        self.album = list(album)
        self.page = None
        self.playing = None
        self.volume = "54"
        self.volumes = []
        self.front = front
        self.put_out_of_sight = []
        self.calls = []

    def __call__(self, args):
        self.calls.append(list(args))
        if args[0] == mc.apple_music.LSAPPINFO:
            if args[1] == "front":
                return mc.Result(0, "ASN:0x0-0x1:")
            return mc.Result(0, f'"App" ASN:0x0-0x1:\n    bundleID="{self.front}"')
        if args[1:3] == ["-l", "JavaScript"]:
            self.put_out_of_sight.append(args[-1])
            return mc.Result(0, "hidden")
        if args[0] == mc.apple_music.OPEN:
            if "-j" in args:
                self.running = True
            else:
                self.page = self.album
            return mc.Result(0, "")
        script = args[2]
        if "is running" in script:
            return mc.Result(0, "true" if self.running else "false")
        if "search library" in script:
            return mc.Result(0, "")
        if script.endswith(" to play"):
            if self.page and self.loads_after <= 0 and self.playing is None:
                self.playing = self.page[0]
            self.loads_after -= 1
            return mc.Result(0, "")
        if script.endswith(" to next track") and self.playing:
            self.playing = self.page[(self.page.index(self.playing) + 1) % len(self.page)]
            return mc.Result(0, "")
        if script.endswith(" to stop"):
            self.playing = None
            return mc.Result(0, "")
        if "return sound volume" in script:
            return mc.Result(0, self.volume)
        if "set sound volume" in script:
            self.volumes.append(args[-1])
            return mc.Result(0, "")
        if "current track" in script:
            return mc.Result(0, f"{self.playing}\nZuchu") if self.playing else mc.Result(1, "")
        return mc.Result(0, "")


class MusicTests(unittest.TestCase):
    def test_song_query_is_passed_as_argument_not_in_script(self):
        query = 'IU "Blueming"'
        front = [(0, "ASN:0x0-0x1:"), (0, 'bundleID="com.apple.Safari"')]
        runner = FakeRunner(*NOTHING_ELSE_PLAYS, *front, (0, "true"), (0, "Blueming - IU"))
        self.assertEqual(run_cli(["music", "song", query], runner), mc.EXIT_OK)
        call = runner.calls[5]
        self.assertEqual(call[-1], query)
        self.assertNotIn("Blueming", call[2])

    def test_song_in_neither_library_nor_catalog_is_not_found(self):
        runner = FakeRunner((0, "true"), (0, ""))
        fetch = lambda url: '{"resultCount":0,"results":[]}'
        self.assertEqual(run_cli(["music", "song", "nothing here"], runner, fetch=fetch), mc.EXIT_NOT_FOUND)

    def test_song_missing_from_library_plays_from_apple_music(self):
        runner = MusicApp(running=True, loads_after=2)
        fetched = []
        fetch = lambda url: fetched.append(url) or CATALOG_ANSWER
        self.assertEqual(run_cli(["music", "song", "shika"], runner, fetch=fetch), mc.EXIT_OK)
        self.assertIn("term=shika", fetched[0])
        self.assertIn([mc.apple_music.OPEN, "-g", "music://music.apple.com/us/album/1712644900?i=1712645271"], runner.calls)
        self.assertEqual(runner.playing, "Shika")

    def test_a_song_inside_an_album_is_reached_silently_and_the_volume_comes_back(self):
        runner = MusicApp(running=True, loads_after=0, album=("Attention", "Hype Boy", "Cookie"))
        answer = CATALOG_ANSWER.replace('"Shika"', '"Hype Boy"')
        self.assertEqual(run_cli(["music", "song", "hype boy"], runner, fetch=lambda url: answer), mc.EXIT_OK)
        self.assertEqual(runner.playing, "Hype Boy")
        self.assertEqual(runner.volumes, ["0", "54"], "silent while skipping, then back to the user's level")

    def test_a_song_never_found_in_the_album_stops_and_restores_the_volume(self):
        runner = MusicApp(running=True, loads_after=0, album=("Attention", "Cookie"))
        answer = CATALOG_ANSWER.replace('"Shika"', '"Hype Boy"').replace('"trackId"', '"trackCount":2,"trackId"')
        self.assertEqual(run_cli(["music", "song", "hype boy"], runner, fetch=lambda url: answer), mc.EXIT_FAILED)
        self.assertIsNone(runner.playing)
        self.assertEqual(runner.volumes[-1], "54")

    def test_a_page_music_did_not_take_is_opened_again(self):
        runner = MusicApp(running=True, loads_after=0, album=("Shika",))
        opened = []
        original = runner.__call__

        def ignore_first_open(args):
            if args[0] == mc.apple_music.OPEN and "-j" not in args:
                opened.append(args)
                if len(opened) == 1:
                    runner.calls.append(list(args))
                    return mc.Result(0, "")
            return original(args)

        code = run_cli(["music", "song", "shika"], ignore_first_open, fetch=lambda url: CATALOG_ANSWER)
        self.assertEqual(code, mc.EXIT_OK)
        self.assertEqual(len(opened), 2)

    def test_music_is_put_out_of_sight_and_the_app_in_front_comes_back(self):
        runner = MusicApp(running=True, loads_after=0, front="com.apple.Safari")
        spawned = FakeSpawn()
        self.assertEqual(run_cli(["music", "song", "shika"], runner, fetch=lambda url: CATALOG_ANSWER, spawned=spawned),
                         mc.EXIT_OK)
        self.assertEqual(len(spawned.started), 1, "a watcher keeps Music hidden while the page opens")
        self.assertIn(mc.apple_music.HIDE_LOOP_JS, spawned.started[0])
        self.assertEqual(spawned.started[0][-1], str(mc.apple_music.HIDE_LOOP_SECONDS), "and runs on past the start")
        self.assertTrue(runner.put_out_of_sight, "Music is hidden once the song plays")
        self.assertEqual(set(runner.put_out_of_sight), {"com.apple.Safari"})

    def test_music_in_front_is_left_alone(self):
        runner = MusicApp(running=True, loads_after=0, front="com.apple.Music")
        spawned = FakeSpawn()
        run_cli(["music", "song", "shika"], runner, fetch=lambda url: CATALOG_ANSWER, spawned=spawned)
        self.assertEqual(runner.put_out_of_sight, [], "the user is using Music, so it stays")
        self.assertEqual(spawned.started, [])

    def test_closed_music_app_is_started_hidden(self):
        runner = MusicApp(running=False, loads_after=0)
        run_cli(["music", "song", "shika"], runner, fetch=lambda url: CATALOG_ANSWER)
        self.assertIn([mc.apple_music.OPEN, "-g", "-j", "-b", "com.apple.Music"], runner.calls)

    def test_catalog_link_is_built_only_from_numeric_ids(self):
        songs = mc.apple_music.parse_songs(
            '{"results":[{"trackId":"1;rm","collectionId":2,"trackName":"x"},'
            '{"trackId":5,"collectionId":6,"trackName":"ok","trackViewUrl":"javascript:alert(1)"}]}'
        )
        self.assertEqual([mc.apple_music.song_link(song) for song in songs], ["music://music.apple.com/us/album/6?i=5"])

    def test_unreadable_catalog_answer_finds_nothing(self):
        self.assertEqual(mc.apple_music.parse_songs("<html>"), [])
        self.assertEqual(mc.apple_music.parse_songs(None), [])


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
        runner = FakeRunner(*NOTHING_ELSE_PLAYS, (0, ""))
        fetched = []
        fetch = lambda url: fetched.append(url) or SEARCH_PAGE
        self.assertEqual(run_cli(["youtube", "play", "아이유 밤편지"], runner, fetch=fetch), mc.EXIT_OK)
        self.assertTrue(fetched[0].startswith(mc.YOUTUBE_SEARCH_URL))
        self.assertEqual(runner.calls[-1], [mc.OPEN, "https://www.youtube.com/watch?v=EjMTw4xLcBI"])

    def test_youtube_play_pauses_the_music_app_first(self):
        runner = FakeRunner((0, "no-browser"), (0, "playing"))
        run_cli(["youtube", "play", "아이유"], runner, fetch=lambda url: SEARCH_PAGE)
        self.assertEqual(runner.calls[2][-1], "pause", "the playing Music app is paused")

    def test_leave_others_starts_music_without_pausing_elsewhere(self):
        runner = FakeRunner((0, "resumed"))
        self.assertEqual(run_cli(["--leave-others", "youtube", "resume"], runner), mc.EXIT_OK)
        self.assertEqual(len(runner.calls), 1, "no state checks, no pausing: only the resume itself")

    def test_youtube_volume_sets_chrome_tabs(self):
        runner = FakeRunner((0, "set"))
        self.assertEqual(run_cli(["youtube", "volume", "40"], runner), mc.EXIT_OK)
        script = runner.calls[0][-2]
        self.assertIn("__assistantLevel=0.40", script)
        self.assertIn("volumechange", script, "a guard keeps the level when YouTube puts back its own")

    def test_volume_level_must_be_0_to_100(self):
        self.assertEqual(run_cli(["youtube", "volume", "150"], FakeRunner()), mc.EXIT_USAGE)
        self.assertEqual(run_cli(["music", "volume", "loud"], FakeRunner()), mc.EXIT_USAGE)

    def test_music_volume_is_passed_as_argument_and_forgets_a_lowering(self):
        state_dir = Path(tempfile.mkdtemp())
        (state_dir / mc.DUCK_STATE_NAME).write_text("60\n")
        runner = FakeRunner((0, ""))
        self.assertEqual(run_cli(["music", "volume", "30"], runner, state_dir), mc.EXIT_OK)
        self.assertEqual(runner.calls[0][-1], "30")
        self.assertFalse((state_dir / mc.DUCK_STATE_NAME).exists())

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
        runner = FakeRunner(*NOTHING_ELSE_PLAYS, (0, "unmarked\nunmarked"), (0, "resumed"))
        self.assertEqual(run_cli(["youtube", "resume"], runner), mc.EXIT_OK)
        self.assertEqual(runner.calls[3][4], "first")

    def test_resume_of_paused_tab_needs_one_call(self):
        runner = FakeRunner(*NOTHING_ELSE_PLAYS, (0, "resumed\nunmarked"))
        self.assertEqual(run_cli(["youtube", "resume"], runner), mc.EXIT_OK)
        self.assertEqual(len(runner.calls), len(NOTHING_ELSE_PLAYS) + 1)

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
