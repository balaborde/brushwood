#!/bin/bash
# Builds a universal Brushwood.app (Apple silicon + Intel) and packages it as build/Brushwood-<version>.dmg,
# which opens on a window where the app is dragged onto the Applications folder.
#
# By default the app is only ad-hoc signed: it works, but the first time it is opened macOS asks people to
# allow it in System Settings › Privacy & Security (see README › Installing). With a paid Apple Developer
# account it can be signed with a Developer ID and notarized, which removes that step:
#   DEVELOPER_ID="Developer ID Application: Name (TEAMID)" NOTARY_PROFILE=brushwood scripts/make-dmg.sh
# where the notary profile was saved once with `xcrun notarytool store-credentials brushwood`.
#
# The window layout is set by Finder, so the first run asks to let the terminal control Finder.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)"
VOLUME="Brushwood"
MOUNT="/Volumes/$VOLUME"
APP="build/Brushwood.app"
DMG="build/Brushwood-$VERSION.dmg"

if [ -e "$MOUNT" ]; then
    echo "error: a volume named $VOLUME is already mounted; eject it first" >&2
    exit 1
fi

scripts/build-app.sh release --universal
if [ -n "${DEVELOPER_ID:-}" ]; then
    codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP"
fi
codesign --verify --strict "$APP"

WORK="$(mktemp -d)"
DEVICE=""
cleanup() {
    [ -n "$DEVICE" ] && hdiutil detach "$DEVICE" -force -quiet 2>/dev/null
    rm -rf "$WORK"
}
trap cleanup EXIT

# Contents: the app, a link to /Applications, the background picture and the volume icon.
STAGE="$WORK/stage"
mkdir -p "$STAGE/.background"
ditto "$APP" "$STAGE/Brushwood.app"
ln -s /Applications "$STAGE/Applications"
swift scripts/dmg-background.swift "$WORK/background.png" "$WORK/background@2x.png"
tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" -out "$STAGE/.background/background.tiff" >/dev/null 2>&1
cp "$APP/Contents/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"

SIZE_MB=$(( $(du -sm "$STAGE" | cut -f1) + 20 ))
hdiutil create -quiet -srcfolder "$STAGE" -volname "$VOLUME" -fs HFS+ -format UDRW -size "${SIZE_MB}m" "$WORK/rw.dmg"
DEVICE="$(hdiutil attach -readwrite -noverify -noautoopen "$WORK/rw.dmg" | awk '/^\/dev\// && !d { d = $1 } END { print d }')"
[ -d "$MOUNT" ] || { echo "error: the disk image did not mount at $MOUNT" >&2; exit 1; }

SetFile -c icnC "$MOUNT/.VolumeIcon.icns"
SetFile -a C "$MOUNT"
SetFile -a V "$MOUNT/.background"

# Window: 640 × 400 points of content below the title bar, icons centered where dmg-background.swift expects
# them. The background is taller than that so a different title bar height on other macOS versions shows no gap.
osascript <<EOF
tell application "Finder"
    tell disk "$VOLUME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set pathbar visible of container window to false
        set the bounds of container window to {200, 120, 840, 552}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set text size of viewOptions to 13
        set background picture of viewOptions to file ".background:background.tiff"
        set position of item "Brushwood.app" of container window to {170, 190}
        set position of item "Applications" of container window to {470, 190}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
EOF
for _ in $(seq 20); do [ -f "$MOUNT/.DS_Store" ] && break; sleep 0.5; done
[ -f "$MOUNT/.DS_Store" ] || { echo "error: Finder did not save the window layout" >&2; exit 1; }
rm -rf "$MOUNT/.fseventsd"
sync

for _ in $(seq 10); do hdiutil detach "$DEVICE" -quiet && break; sleep 1; done
[ -d "$MOUNT" ] && { echo "error: could not eject $MOUNT" >&2; exit 1; }
DEVICE=""

rm -f "$DMG"
hdiutil convert -quiet "$WORK/rw.dmg" -format ULFO -o "$DMG"
if [ -n "${DEVELOPER_ID:-}" ]; then
    codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"
    if [ -n "${NOTARY_PROFILE:-}" ]; then
        xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$DMG"
    fi
fi
hdiutil verify -quiet "$DMG"

echo "Built $DMG ($(du -h "$DMG" | cut -f1 | tr -d ' '))"
echo "SHA-256: $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
