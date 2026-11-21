#!/bin/zsh
# Packs a Simmer.app into a disk image that opens to the app, an arrow,
# and the Applications folder. Prints the image's path as the last line.
#
#   scripts/make-dmg.sh build/release/Simmer.app build/release/Simmer.dmg
#
# Needs create-dmg (brew install create-dmg). The picture behind the icons
# comes from scripts/make-dmg-background.swift.
set -euo pipefail
[[ $# -eq 2 ]] || { echo "Usage: $0 <Simmer.app> <Simmer.dmg>" >&2; exit 1; }
APP=${1:A}
DMG=${2:A}
cd "$(dirname "$0")/.."

command -v create-dmg > /dev/null || { echo "Missing create-dmg. Install it with: brew install create-dmg" >&2; exit 1; }
[[ -d "$APP" ]] || { echo "Can't find the app at $APP." >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# create-dmg copies a whole folder, so give it one holding only the app.
mkdir "$WORK/contents"
ditto "$APP" "$WORK/contents/Simmer.app"

# The mounted disk gets the app's icon.
mkdir "$WORK/Simmer.iconset"
cp Simmer/Assets.xcassets/AppIcon.appiconset/icon_*.png "$WORK/Simmer.iconset/"
iconutil -c icns "$WORK/Simmer.iconset" -o "$WORK/Simmer.icns"

rm -f "$DMG"
# The window is 28 points taller than the picture to leave room for its
# title bar. Icon positions are measured from the picture's top left.
create-dmg \
    --volname "Simmer" \
    --volicon "$WORK/Simmer.icns" \
    --background scripts/dmg/background.tiff \
    --window-pos 200 120 \
    --window-size 660 428 \
    --icon-size 128 \
    --text-size 13 \
    --icon "Simmer.app" 166 206 \
    --hide-extension "Simmer.app" \
    --app-drop-link 496 206 \
    --no-internet-enable \
    "$DMG" "$WORK/contents" >&2

echo "$DMG"
