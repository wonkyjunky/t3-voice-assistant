"""Plays a song from the Apple Music catalog in the Music app, for mac_control.py's music song.

AppleScript can search only the Music library, so the catalog is searched with Apple's public
iTunes Search API (no key). The song's page is then opened in Music and played. Music is started
hidden when it is not running, so no window appears; the app in front stays in front.

Opening a song page only shows it, and "play" then starts its album from the first track. So
playing takes these steps: stop what plays, open the page, turn Music's volume down, play, skip
ahead until Music reports that very song, start it from the beginning, and give the volume back.
"""
import json
import urllib.parse

OSASCRIPT = "/usr/bin/osascript"
OPEN = "/usr/bin/open"
MUSIC_BUNDLE_ID = "com.apple.Music"
SEARCH_URL = "https://itunes.apple.com/search?"
# The Apple Music store the songs come from.
STOREFRONT = "us"
SEARCH_LIMIT = 5
LAUNCH_WAIT_SECONDS = 10
PAGE_LOAD_SECONDS = 1.5
PLAY_WAIT_SECONDS = 12
RETRY_SECONDS = 0.5
SKIP_SECONDS = 0.6
# Now and then Music does not take the opened page; with no track this long, it is opened again.
REOPEN_SECONDS = 3
# Used when the catalog does not say how many tracks the album has.
DEFAULT_TRACK_COUNT = 30

EXIT_OK = 0
EXIT_FAILED = 1
EXIT_NOT_FOUND = 3

IS_RUNNING_SCRIPT = f'return application id "{MUSIC_BUNDLE_ID}" is running'
READY_SCRIPT = f'tell application id "{MUSIC_BUNDLE_ID}" to return player state as text'
STOP_SCRIPT = f'tell application id "{MUSIC_BUNDLE_ID}" to stop'
PLAY_SCRIPT = f'tell application id "{MUSIC_BUNDLE_ID}" to play'
NEXT_SCRIPT = f'tell application id "{MUSIC_BUNDLE_ID}" to next track'
REWIND_SCRIPT = f'tell application id "{MUSIC_BUNDLE_ID}" to set player position to 0'
GET_VOLUME_SCRIPT = f'tell application id "{MUSIC_BUNDLE_ID}" to return sound volume'
SET_VOLUME_SCRIPT = f"""
on run argv
    tell application id "{MUSIC_BUNDLE_ID}" to set sound volume to ((item 1 of argv) as integer)
end run
"""
# Empty while there is no current track yet (Music answers that with an error).
CURRENT_SCRIPT = f"""
tell application id "{MUSIC_BUNDLE_ID}"
    try
        return (name of current track) & linefeed & (artist of current track)
    on error
        return ""
    end try
end tell
"""


def search_url(words):
    query = urllib.parse.urlencode(
        {"term": words, "entity": "song", "limit": SEARCH_LIMIT, "country": STOREFRONT}
    )
    return SEARCH_URL + query


def parse_songs(text):
    """The search answer as dicts with track id, album id, name and artist; [] when unreadable."""
    try:
        results = json.loads(text or "")["results"]
    except (ValueError, KeyError, TypeError):
        return []
    songs = []
    for result in results:
        track, album = result.get("trackId"), result.get("collectionId")
        if isinstance(track, int) and isinstance(album, int) and result.get("trackName"):
            count = result.get("trackCount")
            songs.append({"track": track, "album": album, "name": result["trackName"],
                          "artist": result.get("artistName", ""),
                          "count": count if isinstance(count, int) and count > 0 else DEFAULT_TRACK_COUNT})
    return songs


def song_link(song):
    """A Music app link built only from the two numeric ids (never from text in the answer)."""
    return f"music://music.apple.com/{STOREFRONT}/album/{int(song['album'])}?i={int(song['track'])}"


def osa(runner, script, *args):
    return runner([OSASCRIPT, "-e", script, *args])


def wait_for(sleep, clock, seconds, interval, check):
    deadline = clock() + seconds
    while True:
        if check():
            return True
        if clock() >= deadline:
            return False
        sleep(interval)


def start_hidden(runner, sleep, clock):
    """Makes sure Music runs, starting it hidden when it does not. False if it never answers."""
    if osa(runner, IS_RUNNING_SCRIPT).stdout == "true":
        return True
    if runner([OPEN, "-g", "-j", "-b", MUSIC_BUNDLE_ID]).returncode != 0:
        return False
    return wait_for(sleep, clock, LAUNCH_WAIT_SECONDS, RETRY_SECONDS, lambda: osa(runner, READY_SCRIPT).returncode == 0)


def current_name(runner):
    """The current track's name, or None when there is none yet."""
    current = osa(runner, CURRENT_SCRIPT)
    if current.returncode != 0 or not current.stdout:
        return None
    return current.stdout.split("\n", 1)[0]


def find_in_album(runner, song, sleep, clock):
    """Plays the opened album and skips ahead to the song; True once Music is on it."""
    skips_left = song["count"]
    empty_since = clock()

    def on_song():
        nonlocal skips_left, empty_since
        name = current_name(runner)
        if name is None:
            if clock() - empty_since >= REOPEN_SECONDS:
                runner([OPEN, "-g", song_link(song)])
                sleep(PAGE_LOAD_SECONDS)
                empty_since = clock()
            osa(runner, PLAY_SCRIPT)
            return False
        if name.casefold() == song["name"].casefold():
            return True
        if skips_left <= 0:
            return False
        skips_left -= 1
        osa(runner, NEXT_SCRIPT)
        sleep(SKIP_SECONDS)
        return False

    return wait_for(sleep, clock, PLAY_WAIT_SECONDS, RETRY_SECONDS, on_song)


def play_song(runner, song, sleep, clock):
    """Opens the song's page in Music and plays that song from its start, silently finding it."""
    volume = osa(runner, GET_VOLUME_SCRIPT).stdout
    osa(runner, STOP_SCRIPT)
    if runner([OPEN, "-g", song_link(song)]).returncode != 0:
        return False
    sleep(PAGE_LOAD_SECONDS)
    if volume.isdigit():
        osa(runner, SET_VOLUME_SCRIPT, "0")
    try:
        found = find_in_album(runner, song, sleep, clock)
        if found:
            osa(runner, REWIND_SCRIPT)
        else:
            osa(runner, STOP_SCRIPT)
    finally:
        if volume.isdigit():
            osa(runner, SET_VOLUME_SCRIPT, volume)
    return found


def play_from_catalog(words, runner, fetch, sleep, clock):
    """Finds words in the Apple Music catalog and plays the first song. Prints one line."""
    songs = parse_songs(fetch(search_url(words)))
    if not songs:
        print("no song matched in Apple Music")
        return EXIT_NOT_FOUND
    if not start_hidden(runner, sleep, clock):
        print("the Music app did not start")
        return EXIT_FAILED
    song = songs[0]
    if not play_song(runner, song, sleep, clock):
        print(f"could not start {song['name']} - {song['artist']} in Music")
        return EXIT_FAILED
    print(f"playing from Apple Music: {song['name']} - {song['artist']}")
    return EXIT_OK
