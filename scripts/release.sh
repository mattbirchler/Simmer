#!/bin/zsh
# Builds Simmer, signs it with a Developer ID certificate, has Apple
# notarize it, and packs it into a disk image, so it opens on any Mac
# without a warning. Then signs the disk image for Sparkle and writes the
# update feed that goes up beside it. Prints the disk image's path as the
# last line.
#
#   NOTES=notes.md scripts/release.sh
#
# NOTES is a short Markdown file written for people: what changed and why
# they'd care. It shows in Sparkle's update window. scripts/publish.sh runs
# this and then puts the result on GitHub.
#
# Needs a .env file (gitignored) with an App Store Connect API key:
#   ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (full path to the .p8)
# and a "Developer ID Application" certificate in your keychain. Set
# SIGNING_IDENTITY in .env if you have more than one. Also needs create-dmg
# (brew install create-dmg) for the disk image, and Simmer's Sparkle key in
# your keychain (vendor/sparkle/bin/generate_keys --account simmer).
set -euo pipefail
NOTES=${NOTES:+${NOTES:A}}
cd "$(dirname "$0")/.."

[[ -n "${NOTES:-}" && -s "$NOTES" ]] || { echo "Write release notes for people first, then run: NOTES=path/to/notes.md $0" >&2; exit 1; }

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
# Xcode reuses the folder it built into, so the app would carry the date of
# the very first build forever. macOS keeps app icons by path and date, and
# an unchanged date leaves an old icon showing after an update.
touch "$APP"

echo "Signing with Developer ID" >&2
# Sparkle's helpers are signed first, from the inside out, each with the
# hardened runtime that notarization asks for. The downloader keeps the
# entitlements it was built with.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
codesign --force --options runtime --timestamp --sign "$IDENTITY" --preserve-metadata=entitlements \
    "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$SPARKLE/Versions/B/Autoupdate"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$SPARKLE/Versions/B/Updater.app"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$SPARKLE"
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
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Contents/Info.plist")

# The update feed. Sparkle only trusts a download signed with Simmer's key,
# and the signature has to be made after stapling, which changes the file.
scripts/sparkle-tools.sh
SIGNATURE=$(vendor/sparkle/bin/sign_update --account simmer "$DMG")
[[ "$SIGNATURE" == *edSignature* ]] || { echo "Couldn't sign the update: $SIGNATURE" >&2; exit 1; }
python3 scripts/appcast.py "$OUT/appcast.xml" "$VERSION" "$BUILD" \
    "https://github.com/mattbirchler/Simmer/releases/download/v$VERSION/Simmer.dmg" "$SIGNATURE" "$NOTES"

echo "Notarized Simmer $VERSION (build $BUILD). Update feed: $OUT/appcast.xml" >&2
echo "$DMG"
