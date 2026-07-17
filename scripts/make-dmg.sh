#!/usr/bin/env bash
# Package Holocron.app into a compressed DMG with an /Applications shortcut.
# Usage: scripts/make-dmg.sh path/to/Holocron.app [output-dir]
set -euo pipefail

APP="${1:?usage: make-dmg.sh path/to/Holocron.app [outdir]}"
OUT="${2:-dist}"

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
STAGING="$OUT/dmg-root"

rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

DMG="$OUT/Holocron-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Holocron $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"

echo "$DMG"
