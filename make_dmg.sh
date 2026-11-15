#!/bin/bash
# Packages "Ameen Mac Cleaner" into a shareable DMG: build/AmeenMacCleaner-<version>.dmg
#
#   ./make_dmg.sh                       → ad-hoc signed (recipients must approve it once in Settings)
#   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_PROFILE=my-notary ./make_dmg.sh   → signed + notarized (opens without warnings)
#
# One-time setup for NOTARY_PROFILE:
#   xcrun notarytool store-credentials my-notary --apple-id you@example.com --team-id TEAMID
set -euo pipefail
cd "$(dirname "$0")"

NAME="Ameen Mac Cleaner"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
APP="build/$NAME.app"
DMG="build/AmeenMacCleaner-$VERSION.dmg"
STAGE="build/dmg-stage"

echo "▸ Building universal binary (Apple silicon + Intel)…"
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/AmeenMacCleaner"

if [ ! -f build/AppIcon.icns ]; then
  swift Scripts/make_icon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi

echo "▸ Assembling app bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/AmeenMacCleaner"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

if [ -n "${DEVELOPER_ID:-}" ]; then
  echo "▸ Signing with $DEVELOPER_ID (hardened runtime)…"
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP"
else
  echo "▸ Ad-hoc signing (no Developer ID set)…"
  codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"

echo "▸ Creating DMG…"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$NAME" -srcfolder "$STAGE" -ov -format UDZO -fs HFS+ "$DMG" >/dev/null
rm -rf "$STAGE"

if [ -n "${DEVELOPER_ID:-}" ]; then
  codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"
  if [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "▸ Notarizing (takes a few minutes)…"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
  fi
fi

echo "✓ $DMG ($(du -h "$DMG" | cut -f1))"
