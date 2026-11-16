#!/bin/bash
# tools/voice_sample.sh OUTPUT.wav VIDEO...
#
# Collects the speech from your original avatar videos (the ones with sound, before
# prepare_clip.sh removed it) into one mono WAV for an ElevenLabs Instant Voice Clone. About one
# minute of clean speech is enough.

set -euo pipefail

FFMPEG=/opt/homebrew/bin/ffmpeg
if [ $# -lt 2 ]; then
  sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
fi
OUTPUT="$1"
shift
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

: > "$work/list.txt"
index=0
for video in "$@"; do
  index=$((index + 1))
  "$FFMPEG" -hide_banner -loglevel error -y -i "$video" -vn -ac 1 -ar 44100 "$work/part$index.wav"
  printf "file '%s'\n" "$work/part$index.wav" >> "$work/list.txt"
done
"$FFMPEG" -hide_banner -loglevel error -y -f concat -safe 0 -i "$work/list.txt" -c copy "$OUTPUT"
echo "made $OUTPUT"
