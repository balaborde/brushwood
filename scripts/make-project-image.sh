#!/bin/bash
# Regenerates Resources/EveningLake.png, the goal picture of the Brushwood Plus guided project "Evening Lake": the
# README's demo picture (scripts/readme-images.swift), with the same effects as the README screenshots, at 720 × 480.
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
swiftc -O scripts/readme-images.swift -o "$WORK/readme-images"
"$WORK/readme-images" art "$WORK/demo"
(cd "$WORK/demo" && zip -X -0 -q ../demo.ora mimetype && zip -X -0 -q -r ../demo.ora stack.xml data)
swift build --product Brushwood >/dev/null
BRUSHWOOD_SNAPSHOT="$WORK/snapshot" BRUSHWOOD_SNAPSHOT_DELAY=4 \
BRUSHWOOD_SCRIPT="open:$WORK/demo.ora; wait:1; menu:selectBottomLayer:; menu:selectLayerAbove:; menu:selectLayerAbove:;
 effectvalues:Gaussian Blur|radius=2; menu:selectBottomLayer:; effectvalues:Clouds|blendMode=15|scale=320|power=0.6;
 resize:720,480; save:$PWD/Resources/EveningLake.png" "$(swift build --show-bin-path)/Brushwood" >/dev/null
echo "Wrote Resources/EveningLake.png"
