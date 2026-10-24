#!/bin/sh
# Runs the iPhone and iPad interface's tests (Tests/FallowTouchTests) on an iOS simulator.
# They're iOS-only, so `swift test` on the Mac builds them empty. Pass a simulator's name to
# use another than the default, such as "iPad Pro 13-inch (M5)".
set -u
cd "$(dirname "$0")/.."
device="${1:-iPhone 18 Pro}"
log="$(mktemp)"
trap 'rm -f "$log"' EXIT

status=0
xcodebuild test -scheme FallowTouch -destination "platform=iOS Simulator,name=$device" \
    -derivedDataPath .build/xcode > "$log" 2>&1 || status=$?
# Shows the tests' own output, errors and the result, not the build's chatter.
grep -E '^[◇✔✘↳]|error:|\*\* TEST' "$log"
exit "$status"
