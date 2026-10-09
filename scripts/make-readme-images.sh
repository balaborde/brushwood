#!/bin/bash
# Regenerates the pictures in docs/images used by README.md: the banner, and screenshots of Brushwood editing
# a demo picture drawn by scripts/readme-images.swift. With the disk image built (scripts/make-dmg.sh), it also
# captures its install window.
#
# The screenshots are real window captures: the terminal needs Screen Recording permission, and Brushwood
# appears on screen for a few seconds per picture. Leave the Mac alone meanwhile, since Brushwood's floating
# windows hide as soon as another app becomes active. Your own Brushwood settings are restored afterwards.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="docs/images"
DOMAIN="app.brushwood.Brushwood"
WORK="$(mktemp -d)"
mkdir -p "$OUT"

scripts/build-app.sh release >/dev/null
APP="build/Brushwood.app"
swiftc -O scripts/readme-images.swift -o "$WORK/readme-images"
HELPER="$WORK/readme-images"

# Demo picture, as an OpenRaster file so it keeps its layers. Its name shows in the window title.
DEMO="$WORK/Evening Lake.ora"
"$HELPER" art "$WORK/demo"
(cd "$WORK/demo" && zip -X -0 -q "$DEMO" mimetype && zip -X -0 -q -r "$DEMO" stack.xml data)

"$APP/Contents/MacOS/Brushwood" --render-icon "$WORK/AppIcon.iconset"
"$HELPER" banner "$WORK/AppIcon.iconset/icon_512x512@2x.png" "$OUT/banner.png"

# Brushwood saves window positions and other preferences while it runs: keep a copy of yours.
HAD_DEFAULTS=0
defaults export "$DOMAIN" "$WORK/defaults.plist" 2>/dev/null && HAD_DEFAULTS=1
PID=""
cleanup() {
    [ -n "$PID" ] && kill "$PID" 2>/dev/null
    defaults delete "$DOMAIN" >/dev/null 2>&1 || true
    [ "$HAD_DEFAULTS" = 1 ] && defaults import "$DOMAIN" "$WORK/defaults.plist"
    rm -rf "$WORK"
}
trap cleanup EXIT

FRAME="$("$HELPER" frame 1280 820)"

# shot <file> <language> <locale> <appearance: 1 light, 2 dark> <DebugScript commands>
shot() {
    open -n "$APP" --env BRUSHWOOD_SNAPSHOT="$WORK/snapshot" --env BRUSHWOOD_SNAPSHOT_DELAY=60 --env BRUSHWOOD_SCRIPT="$5" \
        --args -AppleLanguages "($2)" -AppleLocale "$3" -appearance "$4" "-NSWindow Frame BrushwoodMainWindow" "$FRAME" \
        -panelHidden.Tools NO -panelHidden.Colors NO -panelHidden.History NO -panelHidden.Layers NO "$DEMO"
    sleep 1
    PID="$(pgrep -n -f "$APP/Contents/MacOS/Brushwood")"
    sleep 6
    "$HELPER" capture "$PID" "$OUT/$1" 1600
    kill "$PID"
    while kill -0 "$PID" 2>/dev/null; do sleep 0.2; done
    PID=""
    echo "Captured $OUT/$1"
}

# The sky gets clouds blended in Soft Light, and the far mountains a slight blur.
CLOUDS="Clouds|blendMode=15|scale=320|power=0.6"
SETUP="color:3B3A7A; color:F6B7A6,secondary; menu:selectBottomLayer:; menu:selectLayerAbove:; menu:selectLayerAbove:;"
SETUP+=" effectvalues:Gaussian Blur|radius=2; menu:selectBottomLayer:;"
DONE="$SETUP effectvalues:$CLOUDS; menu:selectTopLayer:; menu:selectLayerBelow:; color:F08A5D; color:2B2350,secondary;"

shot main-window.png en en_US 1 "$DONE tool:paintbrush"
shot effect-preview.png en en_US 1 "$SETUP dialog:$CLOUDS"
shot dark-french.png fr fr_FR 2 "$DONE tool:text; color:FFFFFF; setting:fontsize=64; click:560,80; type:Lac du soir"

# Install window of the disk image, when it has been built.
DMG="$(ls -t build/Brushwood-*.dmg 2>/dev/null | head -1 || true)"
if [ -n "$DMG" ] && [ ! -e /Volumes/Brushwood ]; then
    hdiutil attach "$DMG" -quiet
    osascript -e 'tell application "Finder" to open disk "Brushwood"' -e 'tell application "Finder" to activate' >/dev/null
    sleep 2
    "$HELPER" capture-finder Brushwood "$OUT/install.png" 1000
    osascript -e 'tell application "Finder" to close window "Brushwood"' >/dev/null
    hdiutil detach /Volumes/Brushwood -quiet
    echo "Captured $OUT/install.png"
fi
du -h "$OUT"/*.png
