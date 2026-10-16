#!/bin/sh
# Builds a release binary and wraps it in a signed, sandboxed Fallow.app, ad-hoc unless
# --sign names an identity. It always signs with the hardened runtime and the sandbox
# entitlements, so every build runs the way the App Store build will.
#
#   scripts/bundle.sh                                # this Mac's architecture
#   scripts/bundle.sh --universal --version 1.2.3    # Apple Silicon + Intel, stamped 1.2.3
#   scripts/bundle.sh --sign "Developer ID Application: Name (TEAMID)"
set -eu
cd "$(dirname "$0")/.."

universal=0
version=""
identity="-"
while [ $# -gt 0 ]; do
    case "$1" in
        --universal) universal=1 ;;
        --version) version="$2"; shift ;;
        --sign) identity="$2"; shift ;;
        *) echo "usage: scripts/bundle.sh [--universal] [--version X.Y.Z] [--sign IDENTITY]" >&2; exit 2 ;;
    esac
    shift
done

set --
if [ "$universal" = 1 ]; then set -- --arch arm64 --arch x86_64; fi
swift build -c release "$@"
bin="$(swift build -c release "$@" --show-bin-path)/Fallow"

app=Fallow.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/Fallow"
cp Resources/Info.plist "$app/Contents/Info.plist"
swift scripts/make-icon.swift "$app/Contents/Resources/AppIcon.icns"
if [ -n "$version" ]; then
    plutil -replace CFBundleShortVersionString -string "$version" "$app/Contents/Info.plist"
    # The build number must be numbers and dots, so drop a pre-release suffix like "-beta.1".
    plutil -replace CFBundleVersion -string "${version%%-*}" "$app/Contents/Info.plist"
fi
set -- --force --options runtime --entitlements Resources/Fallow.entitlements
if [ "$identity" = "-" ]; then
    codesign "$@" --sign - "$app"
else
    # A secure timestamp is required for notarization; ad-hoc signatures can't have one.
    codesign "$@" --timestamp --sign "$identity" "$app"
fi

echo "Built $app"
