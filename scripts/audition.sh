#!/bin/sh
# Renders preview WAVs of the keystroke sounds and ambient scene, for listening in Quick Look
# without launching the app: 1-keystrokes.wav, 2-ambient.wav and 3-together.wav.
#
#   scripts/audition.sh [folder]    # default: ./audition
set -eu
cd "$(dirname "$0")/.."
folder="${1:-$PWD/audition}"
FALLOW_AUDITION="$folder" scripts/test.sh --filter Audition
echo "Previews in $folder"
