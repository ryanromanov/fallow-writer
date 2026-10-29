#!/bin/sh
# Runs the iPhone and iPad interface's tests (Tests/FallowTouchTests) on an iOS simulator.
# They're iOS-only, so `swift test` on the Mac builds them empty. Pass a simulator's name to
# use another than the default, such as "iPad Pro 13-inch (M5)".
set -u
cd "$(dirname "$0")/.."
if [ $# -gt 0 ]; then
    destination="platform=iOS Simulator,name=$1"
else
    # The newest iPhone Pro this Xcode has, here or on CI, whose simulators differ.
    id="$(xcrun simctl list devices available | grep -E '^ +iPhone [0-9]+ Pro \(' | tail -1 | grep -oE '[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}')"
    destination="platform=iOS Simulator,id=$id"
fi
log="$(mktemp)"
trap 'rm -f "$log"' EXIT

status=0
xcodebuild test -scheme FallowTouch -destination "$destination" \
    -derivedDataPath .build/xcode > "$log" 2>&1 || status=$?
# Shows the tests' own output, errors and the result, not the build's chatter.
grep -E '^[◇✔✘↳]|error:|\*\* TEST' "$log"
exit "$status"
