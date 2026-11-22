#!/bin/zsh
# Ships a new version of Simmer: builds and notarizes it (scripts/release.sh),
# then creates the GitHub release with the disk image, the update feed that
# Sparkle reads, and the release notes.
#
#   scripts/publish.sh notes.md
#
# notes.md is a short Markdown file written for people: what changed and
# why they'd care. It becomes the release's description and shows in
# Sparkle's update window.
#
# Set the version in project.yml first (MARKETING_VERSION, and a higher
# CURRENT_PROJECT_VERSION, which is how Sparkle tells new from old), and
# commit it as "<version> build <number>". Run this from an up to date main.
set -euo pipefail
[[ $# -eq 1 && -s "$1" ]] || { echo "Usage: $0 <release notes.md>" >&2; exit 1; }
NOTES=${1:A}
cd "$(dirname "$0")/.."

fail() { echo "$1" >&2; exit 1; }

[[ -z "$(git status --porcelain)" ]] || fail "There are uncommitted changes. Commit them first."
git fetch -q origin main
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || fail "This isn't the main branch as it is on GitHub. Merge and pull first."

VERSION=$(grep -m1 'MARKETING_VERSION:' project.yml | sed 's/.*"\(.*\)".*/\1/')
BUILD=$(grep -m1 'CURRENT_PROJECT_VERSION:' project.yml | awk '{print $2}')
TAG="v$VERSION"
gh release view "$TAG" > /dev/null 2>&1 && fail "$TAG is already released. Raise the version in project.yml."

# Sparkle only offers a build whose number is higher than the one installed.
LIVE=$(curl -fsSL https://github.com/mattbirchler/Simmer/releases/latest/download/appcast.xml 2>/dev/null \
    | grep -o '<sparkle:version>[0-9]*' | grep -o '[0-9]*$' || true)
[[ -z "$LIVE" || "$BUILD" -gt "$LIVE" ]] || fail "Build $BUILD isn't higher than the released build $LIVE. Raise CURRENT_PROJECT_VERSION."

echo "Publishing Simmer $VERSION (build $BUILD)" >&2
NOTES="$NOTES" scripts/release.sh > /dev/null

gh release create "$TAG" build/release/Simmer.dmg build/release/appcast.xml \
    --target main --title "Simmer $VERSION" --notes-file "$NOTES"
