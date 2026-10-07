#!/bin/bash
# Builds build/Brushwood.app (release by default). Usage: scripts/build-app.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
swift build -c "$CONFIG" --product Brushwood
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Brushwood"
APP="build/Brushwood.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Brushwood"
cp Resources/Info.plist "$APP/Contents/Info.plist"
for lproj in Resources/*.lproj; do
    [ -d "$lproj" ] && cp -R "$lproj" "$APP/Contents/Resources/"
done
ICONSET="$(mktemp -d)/AppIcon.iconset"
"$BIN" --render-icon "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "warning: ad-hoc codesign failed"
echo "Built $APP"
