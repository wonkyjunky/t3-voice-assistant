"""One music at a time, across the places music plays on the Mac, for mac_control.py.

The places are YouTube tabs in Chrome and the Music app.
mac_control.py describes each as a Source (how to tell its state, pause, resume, skip and say what
plays); this module holds the rules that work on all of them:

- When the assistant (or the now-playing card) starts music somewhere, music playing anywhere else
  is paused, not stopped, so it can be played again later. Music the user starts is left alone.
- mac_control.py playing pause | resume | next | now acts on whatever plays, so the assistant does
  not have to guess the place. resume plays again what playing pause paused last.
"""
from dataclasses import dataclass
from typing import Callable, Optional

EXIT_OK = 0
EXIT_NOT_FOUND = 3
PLAYING = "playing"
PAUSED = "paused"
# What playing pause paused last, one source name per line, for playing resume.
LAST_PAUSED_NAME = "music-last-paused"


@dataclass(frozen=True)
class Source:
    name: str
    label: str
    state: Callable[[object], Optional[str]]  # "playing", "paused", or None when it is not there
    pause: Callable[[object], None]
    resume: Callable[[object], None]
    skip: Callable[[object], None]
    now: Callable[[object], int]  # prints what plays there; returns an exit status


def states(ctx, sources):
    """Each present source with its state, in the order given."""
    found = []
    for source in sources:
        state = source.state(ctx)
        if state in (PLAYING, PAUSED):
            found.append((source, state))
    return found


def pause_others(ctx, sources, keep):
    """Pauses music playing anywhere but keep (a source name), before music starts there."""
    for source, state in states(ctx, sources):
        if source.name != keep and state == PLAYING:
            source.pause(ctx)


def last_paused(ctx):
    try:
        return (ctx.state_dir / LAST_PAUSED_NAME).read_text().split()
    except OSError:
        return []


def pause_all(ctx, sources):
    playing = [source for source, state in states(ctx, sources) if state == PLAYING]
    if not playing:
        print("nothing is playing")
        return EXIT_NOT_FOUND
    for source in playing:
        source.pause(ctx)
    (ctx.state_dir / LAST_PAUSED_NAME).write_text("".join(f"{source.name}\n" for source in playing))
    print("paused " + " and ".join(source.label for source in playing))
    return EXIT_OK


def resume_last(ctx, sources):
    """Plays again what playing pause paused, else the first paused source."""
    present = states(ctx, sources)
    if any(state == PLAYING for _, state in present):
        print("music is already playing")
        return EXIT_OK
    paused = [source for source, state in present if state == PAUSED]
    remembered = last_paused(ctx)
    chosen = next((source for source in paused if source.name in remembered), paused[0] if paused else None)
    if chosen is None:
        print("nothing is paused")
        return EXIT_NOT_FOUND
    chosen.resume(ctx)
    (ctx.state_dir / LAST_PAUSED_NAME).unlink(missing_ok=True)
    print(f"{chosen.label} playing again")
    return EXIT_OK


def control(action, ctx, sources):
    """playing pause | resume | next | now."""
    if action == "pause":
        return pause_all(ctx, sources)
    if action == "resume":
        return resume_last(ctx, sources)
    present = states(ctx, sources)
    playing = next((source for source, state in present if state == PLAYING), None)
    if action == "now":
        if playing is not None:
            return playing.now(ctx)
        if present:
            print("paused: " + ", ".join(source.label for source, _ in present))
            return EXIT_OK
        print("nothing is playing")
        return EXIT_OK
    if playing is None:
        print("nothing is playing")
        return EXIT_NOT_FOUND
    playing.skip(ctx)
    print(f"skipped to the next song on {playing.label}")
    return EXIT_OK
