#!/bin/zsh
# Builds Simmer, signs it with a Developer ID certificate, has Apple
# notarize it, and zips it, so it opens on any Mac without a warning.
# Prints the zip's path as the last line.
#
# Needs a .env file (gitignored) with an App Store Connect API key:
#   ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (full path to the .p8)
# and a "Developer ID Application" certificate in your keychain. Set
# SIGNING_IDENTITY in .env if you have more than one.
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

echo "Sending to Apple for notarization (a few minutes)" >&2
ditto -c -k --keepParent "$APP" "$OUT/upload.zip"
RESULT=$(xcrun notarytool submit "$OUT/upload.zip" --key "$KEY" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --wait)
rm "$OUT/upload.zip"
if ! grep -q "status: Accepted" <<< "$RESULT"; then
    echo "$RESULT" >&2
    ID=$(grep -m1 "id:" <<< "$RESULT" | awk '{print $2}')
    [[ -n "$ID" ]] && xcrun notarytool log "$ID" --key "$KEY" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" >&2
    exit 1
fi

xcrun stapler staple -q "$APP"
spctl --assess --type execute "$APP"

# Always the same file name, so the README's download link keeps working.
ZIP="$OUT/Simmer.zip"
ditto -c -k --keepParent "$APP" "$ZIP"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
echo "Notarized Simmer $VERSION" >&2
echo "$ZIP"
