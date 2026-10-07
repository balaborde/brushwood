#!/bin/bash
# Drives the debug build through scripted scenarios and checks pixels/state. Usage: scripts/ui-smoke-test.sh
set -uo pipefail
cd "$(dirname "$0")/.."
swift build --product Brushwood >/dev/null || exit 1
BIN="$(swift build --show-bin-path)/Brushwood"
OUT="$(mktemp -d)"
export BRUSHWOOD_PASTEBOARD="app.brushwood.test.$$"
fail=0
run() {
    local name="$1" script="$2"
    BRUSHWOOD_SNAPSHOT="$OUT/$name" BRUSHWOOD_SNAPSHOT_DELAY=0.8 BRUSHWOOD_SCRIPT="$script" "$BIN" > "$OUT/$name.log" 2>&1
    local p f
    p=$(grep -c '^PASS' "$OUT/$name.log")
    f=$(grep -c '^FAIL' "$OUT/$name.log")
    echo "$name: $p passed, $f failed"
    grep '^FAIL' "$OUT/$name.log"
    [ "$f" -eq 0 ] || fail=1
}

run paint "tool:pencil; color:FF0000; drag:10,10,10,50; expect:10,30,FF0000FF; menu:undo:; expect:10,30,FFFFFFFF;
 menu:redo:; expect:10,30,FF0000FF; tool:paintbrush; color:0000FF; width:20; drag:100,100,200,100; expect:150,100,0000FF;
 expect:150,130,FFFFFF; tool:eraser; width:30; drag:150,90,150,110; expect:150,100,0000FF00; expecthistory:3;
 tool:paintbrush; color:00FF00,secondary; drag:300,300,350,300,right; expect:320,300,00FF00"

run select "tool:rectangleSelect; drag:100,100,300,200; key:return; expectselection:100,100,200,100; color:00FF00;
 menu:fillSelection:; expect:150,150,00FF00; expect:50,50,FFFFFF; menu:invertSelection:; menu:eraseSelection:;
 expect:50,50,FFFFFF00; expect:150,150,00FF00; expectselection:none; menu:undo:; expect:50,50,FFFFFF;
 select:100,100,200,100; menu:cropToSelection:; expectsize:200,100; menu:undo:; expectsize:800,600;
 tool:ellipseSelect; drag:0,0,100,100; drag:50,0,150,100,cmd; key:return; expectselection:0,0,150,100;
 tool:rectangleSelect; drag:0,0,150,100; drag:0,0,75,100,opt; key:return; expectselection:75,0,75,100"

run layers "menu:addLayer:; expectlayers:2; tool:paintBucket; color:FF0000; click:10,10; key:return; expect:10,10,FF0000;
 menu:duplicateLayer:; expectlayers:3; menu:mergeLayerDown:; expectlayers:2; menu:flatten:; expectlayers:1;
 menu:undo:; expectlayers:2; menu:moveLayerDown:; expect:10,10,FFFFFF; menu:moveLayerUp:; expect:10,10,FF0000"

run move "select:10,10,20,20; color:FF0000; menu:fillSelection:; tool:moveSelectedPixels; drag:20,20,120,20; key:return;
 expect:115,15,FF0000; expect:15,15,FF000000; expectselection:110,10,20,20; menu:copy:; menu:deselect:; menu:paste:;
 key:return; expect:5,5,FF0000; menu:undo:; expect:5,5,FFFFFF; tool:moveSelection; select:200,200,50,50;
 drag:210,210,260,260; expectselection:250,250,50,50"

run vector "tool:shapes; shape:0; drawtype:1; color:0000FF; drag:300,300,400,400; key:return; expect:350,350,0000FF;
 tool:lineCurve; color:00FF00; width:5; drag:300,500,500,500; key:return; expect:400,500,00FF00;
 tool:magicWand; click:350,350; key:return; expectselection:300,300,100,100; menu:deselect:;
 tool:gradient; color:000000; color:FFFFFF,secondary; drag:0,0,800,0; key:return; expect:2,550,000000,8; expect:797,550,FFFFFF,8;
 tool:text; color:FF0000; click:20,20; type:Hello; key:return; expecthistory:6"

run effects "effect:Invert Colors; expect:5,5,000000; effect:Gaussian Blur; expect:5,5,000000; effect:Sepia;
 effect:Hue / Saturation; effect:Pixelate; expecthistory:5; menu:undo:; menu:undo:; menu:undo:; menu:undo:; expect:5,5,000000"

run files "tool:pencil; color:FF0000; drag:1,1,1,20; menu:addLayer:; save:$OUT/t.ora; open:$OUT/t.ora; expectlayers:2;
 expect:1,10,FF0000; save:$OUT/t.pdn; open:$OUT/t.pdn; expectlayers:2; expect:1,10,FF0000;
 save:$OUT/t.png; open:$OUT/t.png; expectlayers:1; expect:1,10,FF0000"

rm -rf "$OUT"
[ $fail -eq 0 ] && echo "UI smoke tests passed" || { echo "UI smoke tests FAILED"; exit 1; }
