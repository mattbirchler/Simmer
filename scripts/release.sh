#!/bin/zsh
# Builds Simmer, signs it with a Developer ID certificate, has Apple
# notarize it, and packs it into a disk image, so it opens on any Mac
# without a warning. Prints the disk image's path as the last line.
#
# Needs a .env file (gitignored) with an App Store Connect API key:
#   ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (full path to the .p8)
# and a "Developer ID Application" certificate in your keychain. Set
# SIGNING_IDENTITY in .env if you have more than one. Also needs create-dmg
# (brew install create-dmg) for the disk image.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=build/release

[[ -f .env ]] || { echo "Missing .env with ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH." >&2; exit 1; }
set -a; source .env; set +a
KEY="${ASC_KEY_PATH/#\~/$HOME}"
[[ -f "$KEY" ]] || { echo "Can't find the API key at $KEY." >&2; exit 1; }
IDENTITY="${SIGNING_IDENTITY:-Developer ID Application}"

rm -rf "$OUT" && mkdir -p "$OUT"
xcodegen generate --quiet

echo "Building" >&2
xcodebuild -project Simmer.xcodeproj -scheme Simmer -configuration Release -derivedDataPath build \
    ONLY_ACTIVE_ARCH=NO build > "$OUT/build.log" 2>&1 \
    || { grep -E "error:" "$OUT/build.log" >&2; echo "Build failed. See $OUT/build.log" >&2; exit 1; }
APP="$OUT/Simmer.app"
ditto build/Build/Products/Release/Simmer.app "$APP"

echo "Signing with Developer ID" >&2
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"

# Sends a file to Apple and waits for the verdict, printing Apple's log
# and stopping if it's turned down.
notarize() {
    local result id
    result=$(xcrun notarytool submit "$1" --key "$KEY" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --wait)
    if ! grep -q "status: Accepted" <<< "$result"; then
        echo "$result" >&2
        id=$(grep -m1 "id:" <<< "$result" | awk '{print $2}')
        [[ -n "$id" ]] && xcrun notarytool log "$id" --key "$KEY" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" >&2
        exit 1
    fi
}

echo "Sending the app to Apple for notarization (a few minutes)" >&2
ditto -c -k --keepParent "$APP" "$OUT/upload.zip"
notarize "$OUT/upload.zip"
rm "$OUT/upload.zip"
xcrun stapler staple -q "$APP"
spctl --assess --type execute "$APP"

# Always the same file name, so the README's download link keeps working.
DMG="$OUT/Simmer.dmg"
echo "Making the disk image" >&2
scripts/make-dmg.sh "$APP" "$DMG" > /dev/null
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

# The disk image is notarized as well, so it opens without a warning even
# on a Mac that's offline.
echo "Sending the disk image to Apple for notarization (a few more minutes)" >&2
notarize "$DMG"
xcrun stapler staple -q "$DMG"
spctl --assess --type open --context context:primary-signature "$DMG"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
echo "Notarized Simmer $VERSION" >&2
echo "$DMG"
