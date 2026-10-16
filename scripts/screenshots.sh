#!/bin/sh
# Renders the README's screenshots and the repository's social preview into docs/images,
# from Fallow's own views with a sample passage (see Tests/FallowKitTests/ShowcaseTests.swift).
# Only Fallow's windows are captured.
set -eu
cd "$(dirname "$0")/.."
mkdir -p docs/images
FALLOW_SHOWCASE="$PWD/docs/images" scripts/test.sh --filter ShowcaseTests
# GitHub shows README images about 900 pixels wide; 1800 stays sharp on Retina screens and
# keeps each file small, since every regenerated image stays in the repository's history.
for image in docs/images/writing-light.png docs/images/writing-dark.png docs/images/sound-panel.png; do
    sips --resampleWidth 1800 "$image" >/dev/null
done
