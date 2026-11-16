#!/usr/bin/env python3
"""Fixed set of Mac controls for the assistant: volume, the Music app, YouTube search, opening and
quitting apps.

The assistant runs only this script for Mac control, so what it can do is limited to the commands
below. User-supplied text (song names, app names, search words) always reaches AppleScript as a
run argument, never inside the script source, so it cannot inject AppleScript.

  volume get | up | down | mute | unmute | set <0-100>
  music play | pause | toggle | next | previous | now
  music song <words>        play the first match in the Music library, else in Apple Music
  music playlist <name>     play one of the user's playlists
  music duck | unduck       lower Music while a voice conversation runs, then restore it
  music volume <0-100>      the Music app's own volume (the Mac's volume stays)
  youtube play <words>      open the first YouTube result in the default browser, which plays it
  youtube search <words>    open YouTube search results in the default browser
  youtube volume <0-100>    the volume of YouTube playing in Chrome (the Mac's volume stays)
  playing pause | resume | next | now   whatever plays: YouTube in Chrome or the Music app
  app open <name> | app quit <name>

Music plays in one place at a time: music play | song | playlist and youtube play | resume pause
music playing in the other place first (music_sources.py). music song plays from the Apple Music
catalog (apple_music.py, needs an Apple Music subscription) when the song is not in the library.

youtube play reads YouTube's search page to find the first video. When YouTube cannot be reached
or the page has no video, it opens the search results instead and exits with 3.

Prints one short line for the assistant to read. Exit status: 0 done, 1 the Mac refused or failed,
2 bad command, 3 nothing matched (song, playlist, app), 4 refused on purpose (protected app).
"""
import argparse
import json
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Optional

# Run as python3 -I, which leaves this folder off the import path; its own modules live here.
sys.path.insert(0, str(Path(__file__).resolve().parent))
import apple_music  # noqa: E402
import music_sources  # noqa: E402

EXIT_OK = 0
EXIT_FAILED = 1
EXIT_USAGE = 2
EXIT_NOT_FOUND = 3
EXIT_REFUSED = 4

OSASCRIPT = "/usr/bin/osascript"
OPEN = "/usr/bin/open"
COMMAND_TIMEOUT_SECONDS = 15
VOLUME_STEP = 10
MAX_VOLUME = 100
DUCK_RATIO = 0.3
DUCK_STATE_NAME = "music-duck.state"
DEFAULT_STATE_DIR = Path(__file__).resolve().parent
MAX_APP_NAME_LENGTH = 80
YOUTUBE_SEARCH_URL = "https://www.youtube.com/results?search_query="
YOUTUBE_WATCH_URL = "https://www.youtube.com/watch?v="
FETCH_TIMEOUT_SECONDS = 8
MAX_PAGE_BYTES = 4_000_000
# YouTube serves the full results page only to browsers; this is a generic desktop Chrome.
BROWSER_USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/130.0 Safari/537.36"
)
# Search results are videoRenderer entries; ads and shorts use other renderers and are skipped.
VIDEO_PATTERN = re.compile(r'"videoRenderer":\{"videoId":"([A-Za-z0-9_-]{11})"')
TITLE_PATTERN = re.compile(r'"title":\{"runs":\[\{"text":"((?:[^"\\]|\\.)*)"')
TITLE_SEARCH_WINDOW = 3000
# YouTube sometimes serves a newer layout without videoRenderer entries; these catch that page.
LOCKUP_VIDEO_PATTERN = re.compile(r'"contentId":"([A-Za-z0-9_-]{11})","contentType":"LOCKUP_CONTENT_TYPE_VIDEO"')
WATCH_LINK_PATTERN = re.compile(r"/watch\?v=([A-Za-z0-9_-]{11})")
# The last results page with no video found is kept here, to see what YouTube sent.
YOUTUBE_MISS_NAME = "youtube-miss.html"
# Exists while a YouTube tab was turned down for a voice conversation, so unduck can skip Chrome.
YOUTUBE_DUCK_NAME = "youtube-duck.state"

# Playing YouTube in Google Chrome is controlled with fixed JavaScript run in
# every open YouTube video tab (or only the first, when argument 2 is "first"). The JavaScript is
# passed as a run argument. Chrome must allow it: View > Developer > Allow JavaScript from Apple
# Events. Each tab answers one word; the script returns them one per line.
CHROME_TABS_SCRIPT = """
on run argv
    set js to item 1 of argv
    set onlyFirst to (item 2 of argv) is "first"
    if application "Google Chrome" is not running then return "no-browser"
    set answers to {}
    tell application "Google Chrome"
        repeat with w in windows
            repeat with t in tabs of w
                if (URL of t) contains "youtube.com/watch" then
                    set end of answers to ((execute t javascript js) as text)
                    if onlyFirst then exit repeat
                end if
            end repeat
            if onlyFirst and answers is not {} then exit repeat
        end repeat
    end tell
    if answers is {} then return "no-tab"
    set AppleScript's text item delimiters to linefeed
    return answers as text
end run
"""
VIDEO_JS = "const v=document.querySelector('video');"
PAUSE_JS = f"(()=>{{{VIDEO_JS}if(!v)return 'none';if(v.paused)return 'idle';v.pause();window.__assistantPaused=true;return 'paused';}})()"
RESUME_PAUSED_JS = f"(()=>{{{VIDEO_JS}if(!v)return 'none';if(!window.__assistantPaused)return 'unmarked';delete window.__assistantPaused;v.play();return 'resumed';}})()"
PLAY_JS = f"(()=>{{{VIDEO_JS}if(!v)return 'none';v.play();return 'resumed';}})()"
NEXT_JS = f"(()=>{{{VIDEO_JS}if(!v||v.paused)return 'skip';const b=document.querySelector('.ytp-next-button');if(!b)return 'no-next';b.click();return 'next';}})()"
NOW_JS = f"(()=>{{{VIDEO_JS}const t=document.title.replace(/ - YouTube$/,'');return (v&&!v.paused?'playing:':'paused:')+t;}})()"
DUCK_JS = (
    f"(()=>{{{VIDEO_JS}if(!v||v.paused)return 'idle';if(window.__assistantVolume===undefined)"
    f"{{window.__assistantVolume=v.volume;v.volume=Math.max(0.01,v.volume*{DUCK_RATIO});}}return 'ducked';}})()"
)
# Sets every YouTube tab's volume; a lowering for a conversation is forgotten (the user's choice wins).
def volume_js(level):
    return (f"(()=>{{{VIDEO_JS}if(!v)return 'none';delete window.__assistantVolume;"
            f"v.volume={int(level) / MAX_VOLUME:.2f};return 'set';}})()")


UNDUCK_JS = (
    f"(()=>{{{VIDEO_JS}if(!v||window.__assistantVolume===undefined)return 'idle';"
    "v.volume=window.__assistantVolume;delete window.__assistantVolume;return 'restored';})()"
)
CHROME_JS_OFF_HINT = (
    "Chrome blocks this: in Chrome turn on View > Developer > Allow JavaScript from Apple Events"
)
CHROME_NOT_ALLOWED_HINT = (
    "T3 Code may not control Chrome: allow it in System Settings > Privacy & Security > Automation"
)
# Quitting these would end the assistant itself or the voice system.
PROTECTED_APPS = frozenset({"t3 code", "t3 code (beta)", "assistantavatar", "assistantlisten", "finder"})

GET_VOLUME_SCRIPT = "output volume of (get volume settings)"
MUTE_SCRIPT = "set volume with output muted"
UNMUTE_SCRIPT = "set volume without output muted"
MUSIC_VERBS = {
    "play": "play",
    "pause": "pause",
    "toggle": "playpause",
    "next": "next track",
    "previous": "previous track",
}
NOW_PLAYING_SCRIPT = """
if application "Music" is running then
    tell application "Music"
        if player state is playing then return (name of current track) & " - " & (artist of current track)
    end tell
end if
return ""
"""
# The Music app's state without starting it: playing, paused, stopped, or nothing when closed.
MUSIC_STATE_SCRIPT = """
if application "Music" is running then
    tell application "Music" to return player state as text
end if
return ""
"""
# pause | play | next for a Music app that runs; a closed one is left closed.
MUSIC_IF_RUNNING_SCRIPT = """
on run argv
    if application "Music" is running then
        tell application "Music"
            if (item 1 of argv) is "pause" then pause
            if (item 1 of argv) is "play" then play
            if (item 1 of argv) is "next" then next track
        end tell
    end if
end run
"""
PLAYING_VOLUME_SCRIPT = """
if application "Music" is running then
    tell application "Music"
        if player state is playing then return sound volume
    end tell
end if
return ""
"""
SET_MUSIC_VOLUME_SCRIPT = """
on run argv
    if application "Music" is running then
        tell application "Music" to set sound volume to ((item 1 of argv) as integer)
    end if
end run
"""
PLAY_SONG_SCRIPT = """
on run argv
    tell application "Music"
        set hits to (search library playlist 1 for (item 1 of argv))
        if hits is {} then return ""
        set picked to item 1 of hits
        play picked
        return (name of picked) & " - " & (artist of picked)
    end tell
end run
"""
PLAY_PLAYLIST_SCRIPT = """
on run argv
    tell application "Music"
        if not (exists user playlist (item 1 of argv)) then return ""
        play user playlist (item 1 of argv)
        return name of user playlist (item 1 of argv)
    end tell
end run
"""
# Asks System Events first: "application X is running" pops up a "where is X?" dialog and hangs
# when no app has that name. Looks the process up by name only: a "whose" search walks every
# process and stalls for many seconds when one of them is unresponsive.
# Only an app that is running gets told to quit.
QUIT_APP_SCRIPT = """
on run argv
    set appName to item 1 of argv
    tell application "System Events"
        set isRunning to exists (application process appName)
    end tell
    if not isRunning then return "not running"
    tell application appName to quit
    return "quit"
end run
"""


@dataclass(frozen=True)
class Result:
    returncode: int
    stdout: str
    stderr: str = ""


@dataclass(frozen=True)
class Context:
    runner: Callable[[list], Result]
    state_dir: Path
    fetch: Callable[[str], Optional[str]]
    sleep: Callable[[float], None] = time.sleep
    clock: Callable[[], float] = time.monotonic


class UsageError(Exception):
    pass


def fetch_page(url):
    headers = {"User-Agent": BROWSER_USER_AGENT, "Accept-Language": "ko-KR,ko;q=0.9,en;q=0.8"}
    request = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=FETCH_TIMEOUT_SECONDS) as response:
            return response.read(MAX_PAGE_BYTES).decode("utf-8", "replace")
    except (OSError, ValueError) as error:
        print(f"mac_control: could not reach {urllib.parse.urlsplit(url).netloc}: {error}", file=sys.stderr)
        return None


def decode_json_text(raw):
    try:
        return json.loads(f'"{raw}"')
    except ValueError:
        return raw


def first_video(page):
    """The first search result on a YouTube results page as (video id, title), or None.

    The title is known only for the usual videoRenderer layout; the fallbacks give "".
    """
    page = page or ""
    match = VIDEO_PATTERN.search(page)
    if match is not None:
        title = TITLE_PATTERN.search(page, match.end(), match.end() + TITLE_SEARCH_WINDOW)
        return match.group(1), decode_json_text(title.group(1)) if title else ""
    for pattern in (LOCKUP_VIDEO_PATTERN, WATCH_LINK_PATTERN):
        match = pattern.search(page)
        if match is not None:
            return match.group(1), ""
    return None


def keep_missed_page(state_dir, page):
    try:
        (state_dir / YOUTUBE_MISS_NAME).write_text(page, encoding="utf-8")
    except OSError as error:
        print(f"mac_control: could not keep the missed page: {error}", file=sys.stderr)
        return
    print(f"mac_control: no video in a {len(page)}-character page, kept in {YOUTUBE_MISS_NAME}", file=sys.stderr)


def system_runner(args):
    try:
        done = subprocess.run(args, capture_output=True, text=True, timeout=COMMAND_TIMEOUT_SECONDS)
    except (OSError, subprocess.TimeoutExpired) as error:
        print(f"mac_control: {args[0]} failed: {error}", file=sys.stderr)
        return Result(EXIT_FAILED, "")
    if done.returncode != 0 and done.stderr:
        print(f"mac_control: {done.stderr.strip()}", file=sys.stderr)
    return Result(done.returncode, done.stdout.strip(), done.stderr.strip())


def osa(runner, script, *args):
    return runner([OSASCRIPT, "-e", script, *args])


def report(result, message):
    if result.returncode != 0:
        print("the Mac refused or failed")
        return EXIT_FAILED
    print(message)
    return EXIT_OK


def parse_volume(text):
    try:
        level = int(text)
    except (TypeError, ValueError):
        return None
    return level if 0 <= level <= MAX_VOLUME else None


def set_volume(runner, level):
    script = f"set volume output volume {level}\n{UNMUTE_SCRIPT}"
    return report(osa(runner, script), f"volume {level}")


def step_volume(runner, delta):
    current = osa(runner, GET_VOLUME_SCRIPT)
    level = parse_volume(current.stdout) if current.returncode == 0 else None
    if level is None:
        print("could not read the volume")
        return EXIT_FAILED
    return set_volume(runner, max(0, min(MAX_VOLUME, level + delta)))


def handle_volume(options, ctx):
    action, runner = options.action, ctx.runner
    if action == "set":
        level = parse_volume(options.level)
        if level is None:
            raise UsageError(f"volume set needs a level from 0 to {MAX_VOLUME}")
        return set_volume(runner, level)
    if action == "get":
        current = osa(runner, GET_VOLUME_SCRIPT)
        return report(current, f"volume {current.stdout}")
    if action in ("up", "down"):
        return step_volume(runner, VOLUME_STEP if action == "up" else -VOLUME_STEP)
    script = MUTE_SCRIPT if action == "mute" else UNMUTE_SCRIPT
    return report(osa(runner, script), "muted" if action == "mute" else "unmuted")


def required_text(words, what):
    text = " ".join(words or []).strip()
    if not text:
        raise UsageError(f"{what} is missing")
    return text


def play_matching(runner, script, query, label):
    found = osa(runner, script, query)
    if found.returncode != 0:
        print("the Mac refused or failed")
        return EXIT_FAILED
    if not found.stdout:
        print(f"no {label} matched")
        return EXIT_NOT_FOUND
    print(f"playing {found.stdout}")
    return EXIT_OK


def play_song(words, ctx):
    """A song from the Music library, else from the Apple Music catalog. Music starts hidden when it
    is not running, so asking the library opens no window."""
    if not apple_music.start_hidden(ctx.runner, ctx.sleep, ctx.clock):
        print("the Music app did not start")
        return EXIT_FAILED
    found = osa(ctx.runner, PLAY_SONG_SCRIPT, words)
    if found.returncode == 0 and found.stdout:
        print(f"playing {found.stdout}")
        return EXIT_OK
    return apple_music.play_from_catalog(words, ctx.runner, ctx.fetch, ctx.sleep, ctx.clock)


def duck_music(runner, state_file):
    if state_file.exists():
        print("music already lowered")
        return EXIT_OK
    current = osa(runner, PLAYING_VOLUME_SCRIPT)
    level = parse_volume(current.stdout) if current.returncode == 0 else None
    if level is None:
        print("music not playing")
        return EXIT_OK
    state_file.write_text(f"{level}\n")
    lowered = min(level, max(1, round(level * DUCK_RATIO)))
    return report(osa(runner, SET_MUSIC_VOLUME_SCRIPT, str(lowered)), f"music lowered to {lowered}")


def unduck_music(runner, state_file):
    if not state_file.exists():
        print("music was not lowered")
        return EXIT_OK
    level = parse_volume(state_file.read_text().strip())
    state_file.unlink()
    if level is None:
        print("saved music volume was unreadable")
        return EXIT_FAILED
    return report(osa(runner, SET_MUSIC_VOLUME_SCRIPT, str(level)), f"music restored to {level}")


def required_level(words):
    level = parse_volume(" ".join(words).strip())
    if level is None:
        raise UsageError(f"give a volume from 0 to {MAX_VOLUME}")
    return level


def set_music_volume(runner, state_file, level):
    """The user's own choice of Music volume; a lowering for a conversation is forgotten."""
    state_file.unlink(missing_ok=True)
    return report(osa(runner, SET_MUSIC_VOLUME_SCRIPT, str(level)), f"music volume {level}")


def handle_music(options, ctx):
    action, runner = options.action, ctx.runner
    state_file = ctx.state_dir / DUCK_STATE_NAME
    if action in ("play", "song", "playlist") or (action == "toggle" and music_state(ctx) != music_sources.PLAYING):
        music_sources.pause_others(ctx, SOURCES, keep="music")
    if action in MUSIC_VERBS:
        script = f'tell application "Music" to {MUSIC_VERBS[action]}'
        return report(osa(runner, script), f"music {action}")
    if action == "now":
        playing = osa(runner, NOW_PLAYING_SCRIPT)
        return report(playing, f"now playing {playing.stdout}" if playing.stdout else "nothing playing")
    if action == "song":
        return play_song(required_text(options.query, "song"), ctx)
    if action == "playlist":
        name = required_text(options.query, "playlist name")
        return play_matching(runner, PLAY_PLAYLIST_SCRIPT, name, "playlist")
    if action == "volume":
        return set_music_volume(runner, state_file, required_level(options.query))
    if action == "duck":
        return duck_music(runner, state_file)
    return unduck_music(runner, state_file)


def chrome_error(stderr):
    if "JavaScript" in stderr:
        return CHROME_JS_OFF_HINT
    if "-1743" in stderr or "Not authorized" in stderr:
        return CHROME_NOT_ALLOWED_HINT
    return "the Mac refused or failed"


def in_youtube_tabs(ctx, js, scope="all", quiet=False):
    """Each YouTube tab's answer to js, [] when none is open, or None after a failure (printed
    unless quiet)."""
    result = osa(ctx.runner, CHROME_TABS_SCRIPT, js, scope)
    if result.returncode != 0:
        if not quiet:
            print(chrome_error(result.stderr))
        return None
    if result.stdout in ("no-browser", "no-tab", ""):
        return []
    return result.stdout.splitlines()


def tab_outcome(answers, wanted, done_message, missed_message):
    if answers is None:
        return EXIT_FAILED
    if not answers:
        print("no YouTube video is open in Chrome")
        return EXIT_NOT_FOUND
    if wanted in answers:
        print(done_message)
        return EXIT_OK
    print(missed_message)
    return EXIT_NOT_FOUND


def resume_youtube(ctx):
    answers = in_youtube_tabs(ctx, RESUME_PAUSED_JS)
    if answers and "resumed" not in answers:
        answers = in_youtube_tabs(ctx, PLAY_JS, "first")
    return tab_outcome(answers, "resumed", "YouTube playing again", "could not start the video")


def youtube_now(ctx):
    answers = in_youtube_tabs(ctx, NOW_JS)
    if not answers:
        return tab_outcome(answers, "", "", "")
    playing = [answer for answer in answers if answer.startswith("playing:")]
    if playing:
        print(f"now playing on YouTube: {playing[0].removeprefix('playing:')}")
    else:
        print(f"YouTube is paused: {answers[0].removeprefix('paused:')}")
    return EXIT_OK


def duck_youtube(ctx):
    marker = ctx.state_dir / YOUTUBE_DUCK_NAME
    if marker.exists():
        print("YouTube already lowered")
        return EXIT_OK
    answers = in_youtube_tabs(ctx, DUCK_JS)
    if answers is None:
        return EXIT_FAILED
    if "ducked" not in answers:
        print("YouTube not playing")
        return EXIT_OK
    marker.write_text("1\n")
    print("YouTube lowered")
    return EXIT_OK


def unduck_youtube(ctx):
    marker = ctx.state_dir / YOUTUBE_DUCK_NAME
    if not marker.exists():
        print("YouTube was not lowered")
        return EXIT_OK
    marker.unlink()
    answers = in_youtube_tabs(ctx, UNDUCK_JS)
    if answers is None:
        return EXIT_FAILED
    print("YouTube restored")
    return EXIT_OK


def youtube_volume(level, ctx):
    (ctx.state_dir / YOUTUBE_DUCK_NAME).unlink(missing_ok=True)
    answers = in_youtube_tabs(ctx, volume_js(level))
    return tab_outcome(answers, "set", f"YouTube volume {level}", "no YouTube video is open in Chrome")


def control_youtube(action, ctx):
    if action == "resume":
        music_sources.pause_others(ctx, SOURCES, keep="chrome")
    if action == "pause":
        answers = in_youtube_tabs(ctx, PAUSE_JS)
        return tab_outcome(answers, "paused", "paused YouTube", "YouTube was not playing")
    if action == "next":
        answers = in_youtube_tabs(ctx, NEXT_JS)
        return tab_outcome(answers, "next", "skipped to the next YouTube video", "no YouTube video is playing")
    if action == "resume":
        return resume_youtube(ctx)
    if action == "now":
        return youtube_now(ctx)
    if action == "duck":
        return duck_youtube(ctx)
    return unduck_youtube(ctx)


YOUTUBE_CONTROLS = ("pause", "resume", "next", "now", "duck", "unduck")


def handle_youtube(options, ctx):
    if options.action == "volume":
        return youtube_volume(required_level(options.query), ctx)
    if options.action in YOUTUBE_CONTROLS:
        return control_youtube(options.action, ctx)
    query = required_text(options.query, "search words")
    search_url = YOUTUBE_SEARCH_URL + urllib.parse.quote_plus(query)
    if options.action == "search":
        return report(ctx.runner([OPEN, search_url]), "opened YouTube search results")
    page = ctx.fetch(search_url)
    video = first_video(page)
    if video is None:
        if page is not None:
            keep_missed_page(ctx.state_dir, page)
        if ctx.runner([OPEN, search_url]).returncode != 0:
            print("the Mac refused or failed")
            return EXIT_FAILED
        print("found no video to play, opened YouTube search results instead")
        return EXIT_NOT_FOUND
    video_id, title = video
    music_sources.pause_others(ctx, SOURCES, keep="chrome")
    return report(ctx.runner([OPEN, YOUTUBE_WATCH_URL + video_id]), f"playing on YouTube: {title or video_id}")


# The two places music plays, for music_sources.py.
def chrome_state(ctx):
    answers = in_youtube_tabs(ctx, NOW_JS, quiet=True)
    if not answers:
        return None
    return music_sources.PLAYING if any(a.startswith("playing:") for a in answers) else music_sources.PAUSED


def chrome_resume(ctx):
    answers = in_youtube_tabs(ctx, RESUME_PAUSED_JS, quiet=True)
    if answers and "resumed" not in answers:
        in_youtube_tabs(ctx, PLAY_JS, "first", quiet=True)


def music_state(ctx):
    state = osa(ctx.runner, MUSIC_STATE_SCRIPT).stdout
    return state if state in (music_sources.PLAYING, music_sources.PAUSED) else None


def music_if_running(word):
    return lambda ctx: osa(ctx.runner, MUSIC_IF_RUNNING_SCRIPT, word)


def music_now(ctx):
    playing = osa(ctx.runner, NOW_PLAYING_SCRIPT)
    return report(playing, f"now playing on Music: {playing.stdout}" if playing.stdout else "Music is paused")


SOURCES = (
    music_sources.Source(
        "chrome", "YouTube in Chrome", chrome_state,
        pause=lambda ctx: in_youtube_tabs(ctx, PAUSE_JS, quiet=True),
        resume=chrome_resume,
        skip=lambda ctx: in_youtube_tabs(ctx, NEXT_JS, quiet=True),
        now=lambda ctx: youtube_now(ctx),
    ),
    music_sources.Source(
        "music", "Music", music_state,
        pause=music_if_running("pause"), resume=music_if_running("play"), skip=music_if_running("next"),
        now=music_now,
    ),
)


def handle_playing(options, ctx):
    return music_sources.control(options.action, ctx, SOURCES)


def checked_app_name(words):
    name = required_text(words, "app name")
    if len(name) > MAX_APP_NAME_LENGTH or "/" in name or name.startswith("-"):
        raise UsageError("give an app name, not a path or option")
    if any(ord(char) < 32 for char in name):
        raise UsageError("app name has control characters")
    return name


def handle_app(options, ctx):
    runner = ctx.runner
    name = checked_app_name(options.name)
    if options.action == "open":
        if runner([OPEN, "-a", name]).returncode != 0:
            print(f"no app named {name}")
            return EXIT_NOT_FOUND
        print(f"opened {name}")
        return EXIT_OK
    if name.lower().removesuffix(".app") in PROTECTED_APPS:
        print(f"{name} is protected and was not quit")
        return EXIT_REFUSED
    quit_result = osa(runner, QUIT_APP_SCRIPT, name)
    if quit_result.returncode == 0 and quit_result.stdout == "not running":
        print(f"{name} was not running")
        return EXIT_NOT_FOUND
    return report(quit_result, f"quit {name}")


def build_parser():
    parser = argparse.ArgumentParser(prog="mac_control.py", description="the assistant's Mac controls")
    groups = parser.add_subparsers(dest="group", required=True)
    volume = groups.add_parser("volume")
    volume.add_argument("action", choices=["get", "up", "down", "mute", "unmute", "set"])
    volume.add_argument("level", nargs="?")
    music = groups.add_parser("music")
    music.add_argument("action", choices=[*MUSIC_VERBS, "now", "song", "playlist", "duck", "unduck", "volume"])
    music.add_argument("query", nargs="*")
    youtube = groups.add_parser("youtube")
    youtube.add_argument("action", choices=["play", "search", "volume", *YOUTUBE_CONTROLS])
    youtube.add_argument("query", nargs="*")
    playing = groups.add_parser("playing")
    playing.add_argument("action", choices=["pause", "resume", "next", "now"])
    app = groups.add_parser("app")
    app.add_argument("action", choices=["open", "quit"])
    app.add_argument("name", nargs="*")
    return parser


HANDLERS = {"volume": handle_volume, "music": handle_music, "youtube": handle_youtube, "playing": handle_playing,
            "app": handle_app}


def main(argv=None, runner=system_runner, state_dir=DEFAULT_STATE_DIR, fetch=fetch_page, sleep=time.sleep,
         clock=time.monotonic):
    try:
        options = build_parser().parse_args(argv)
    except SystemExit as stop:
        return EXIT_OK if stop.code == 0 else EXIT_USAGE
    try:
        return HANDLERS[options.group](options, Context(runner, state_dir, fetch, sleep, clock))
    except UsageError as error:
        print(f"mac_control: {error}", file=sys.stderr)
        return EXIT_USAGE


if __name__ == "__main__":
    sys.exit(main())
