#!/bin/bash
# tools/prepare_clip.sh INPUT NAME [SECONDS] [CROP]
#
# Turns a video you made (any size, with or without sound) into the avatar clip the app expects:
# avatar/NAME.mp4, a 360x360 square, 24 frames a second, H.264, no sound, SECONDS long
# (default 10; use 4 for greeting). CROP is an ffmpeg crop filter for the square around the face;
# the default takes the largest centered square. Example for a face in the upper part of a
# portrait video:  tools/prepare_clip.sh raw/idle.mp4 idle 10 "crop=iw:iw:0:ih*0.1"
#
# NAME is one of: idle greeting listening thinking speaking speaking_happy speaking_sad
# speaking_playful speaking_comfort. Also makes avatar.png from the first idle frame.

set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
FFMPEG=/opt/homebrew/bin/ffmpeg
NAMES=" idle greeting listening thinking speaking speaking_happy speaking_sad speaking_playful speaking_comfort "
SIZE=360
FPS=24

if [ $# -lt 2 ]; then
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
fi
INPUT="$1"
NAME="$2"
SECONDS_LONG="${3:-10}"
CROP="${4:-crop=min(iw\,ih):min(iw\,ih)}"

case "$NAMES" in *" $NAME "*) ;; *) echo "prepare_clip: unknown clip name $NAME" >&2; exit 2 ;; esac
[ -f "$INPUT" ] || { echo "prepare_clip: no such file $INPUT" >&2; exit 2; }
[ -x "$FFMPEG" ] || { echo "prepare_clip: ffmpeg missing, run: brew install ffmpeg" >&2; exit 1; }

mkdir -p "$HERE/avatar"
OUT="$HERE/avatar/$NAME.mp4"
"$FFMPEG" -hide_banner -loglevel error -y -i "$INPUT" -t "$SECONDS_LONG" -an \
  -vf "$CROP,scale=$SIZE:$SIZE,fps=$FPS" -c:v libx264 -pix_fmt yuv420p -movflags +faststart "$OUT"
echo "made $OUT"

if [ "$NAME" = idle ]; then
  "$FFMPEG" -hide_banner -loglevel error -y -i "$OUT" -frames:v 1 "$HERE/avatar.png"
  echo "made $HERE/avatar.png"
fi
