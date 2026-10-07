#!/bin/bash
# Launches Brushwood with a test image and checks what is really on screen (needs Screen Recording permission
# for the terminal). This catches display bugs that in-process rendering checks cannot see.
set -uo pipefail
cd "$(dirname "$0")/.."
swift build --product Brushwood >/dev/null || exit 1
BIN="$(swift build --show-bin-path)/Brushwood"
OUT="$(mktemp -d)"
swift scripts/check-window.swift make "$OUT/test.png" || exit 1
BRUSHWOOD_PASTEBOARD="app.brushwood.screencheck.$$" "$BIN" "$OUT/test.png" >/dev/null 2>&1 &
PID=$!
sleep 4
if ! swift scripts/check-window.swift capture "$OUT/window.png"; then
    kill "$PID" 2>/dev/null
    echo "Could not capture the screen (grant Screen Recording permission to the terminal)."
    exit 1
fi
kill "$PID" 2>/dev/null
swift scripts/check-window.swift verify "$OUT/window.png"
status=$?
[ $status -ne 0 ] && echo "Capture kept at $OUT/window.png" || rm -rf "$OUT"
exit $status
