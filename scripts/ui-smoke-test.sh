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

run paint "tool:pencil; color:FF0000; drag:10,10,10,50; expect:10,30,FF0000FF; menu:brushwoodUndo:; expect:10,30,FFFFFFFF;
 menu:brushwoodRedo:; expect:10,30,FF0000FF; tool:paintbrush; color:0000FF; width:20; drag:100,100,200,100; expect:150,100,0000FF;
 expect:150,130,FFFFFF; tool:eraser; width:30; drag:150,90,150,110; expect:150,100,0000FF00; expecthistory:3;
 tool:paintbrush; color:00FF00,secondary; drag:300,300,350,300,right; expect:320,300,00FF00"

run select "tool:rectangleSelect; drag:100,100,300,200; key:return; expectselection:100,100,200,100; color:00FF00;
 menu:fillSelection:; expect:150,150,00FF00; expect:50,50,FFFFFF; menu:invertSelection:; menu:eraseSelection:;
 expect:50,50,FFFFFF00; expect:150,150,00FF00; expectselection:none; menu:brushwoodUndo:; expect:50,50,FFFFFF;
 select:100,100,200,100; menu:cropToSelection:; expectsize:200,100; menu:brushwoodUndo:; expectsize:800,600;
 tool:ellipseSelect; drag:0,0,100,100; drag:50,0,150,100,cmd; key:return; expectselection:0,0,150,100;
 tool:rectangleSelect; drag:0,0,150,100; drag:0,0,75,100,opt; key:return; expectselection:75,0,75,100"

run layers "menu:addLayer:; expectlayers:2; tool:paintBucket; color:FF0000; click:10,10; key:return; expect:10,10,FF0000;
 menu:duplicateLayer:; expectlayers:3; menu:mergeLayerDown:; expectlayers:2; menu:flatten:; expectlayers:1;
 menu:brushwoodUndo:; expectlayers:2; menu:moveLayerDown:; expect:10,10,FFFFFF; menu:moveLayerUp:; expect:10,10,FF0000"

# Brushwood Plus snapshots: going back survives undo and new edits, and is itself a step that can be undone.
run snapshots "plusfeature:smoothing=1; plusfeature:magneticClosing=1; plusfeature:snapshots=1; tool:paintBucket; color:FF0000; click:10,10; key:return; snapshot; expectsnapshots:1; gobacktosnapshot:0;
 expecthistory:1; color:0000FF; click:10,10; key:return; menu:brushwoodUndo:; menu:brushwoodUndo:; tool:pencil;
 color:00FF00; drag:400,10,400,50; expecthistory:1; gobacktosnapshot:0; expect:10,10,FF0000; expect:400,30,FF0000;
 expecthistory:2; menu:brushwoodUndo:; expect:10,10,FFFFFF; expect:400,30,00FF00; snapshot; expectsnapshots:2"

# Brushwood Plus color history: colors join when a step paints with them (not when picked, nor on undo and redo),
# newest first and once each, 26 at most; a click brings one back. The bar shows 16, all 26 once the window is expanded.
fills=""; for i in $(seq 10 37); do fills="$fills color:${i}${i}${i}; click:$((i * 20)),500;"; done
kept=$(for i in $(seq 37 -1 12); do printf "%s," "$i$i$i"; done); kept="${kept%,}"
run colorhistory "showpanels; plusfeature:colorHistory=1; colorhistoryclear; expectcolorhistory:none; color:00FF00;
 color:FF00FF; expectcolorhistory:none; tool:paintbrush; width:6; color:FF0000; drag:100,100,200,100; expectcolorhistory:FF0000;
 color:0000FF; drag:100,150,200,150; expectcolorhistory:0000FF,FF0000; color:FF0000; tool:pencil; drag:100,200,200,200;
 expectcolorhistory:FF0000,0000FF; menu:brushwoodUndo:; menu:brushwoodUndo:; menu:brushwoodRedo:; expectcolorhistory:FF0000,0000FF;
 color:00FF00,secondary; drag:100,250,200,250,right; expectcolorhistory:00FF00,FF0000,0000FF;
 tool:gradient; setting:transparency=0; color:FFFF00; color:FF00FF,secondary; drag:0,300,800,300; key:return;
 expectcolorhistory:FFFF00,FF00FF,00FF00,FF0000,0000FF; colorhistoryclick:4; expectcolor:primary,0000FF;
 colorhistoryclick:3,right; expectcolor:secondary,FF0000; expectcolor:primary,0000FF; expectcolorhistory:FFFF00,FF00FF,00FF00,FF0000,0000FF;
 color:888888; menu:selectAll:; menu:fillSelection:; menu:deselect:; expectcolorhistory:888888,FFFF00,FF00FF,00FF00,FF0000,0000FF;
 plusfeature:colorHistory=0; tool:paintbrush; color:123456; drag:100,350,200,350; expectcolorhistory:888888,FFFF00,FF00FF,00FF00,FF0000,0000FF;
 plusfeature:colorHistory=1; expectcolorhistory:888888,FFFF00,FF00FF,00FF00,FF0000,0000FF; tool:paintBucket; $fills
 expectcolorhistory:$kept; expectcolorhistorycells:16; colorhistoryclick:20; expectcolor:primary,373737; colorsmore;
 expectcolorhistorycells:26; colorhistoryclick:20; expectcolor:primary,171717; colorsmore; expectcolorhistorycells:16;
 colorhistoryclear; expectcolorhistory:none"

# Snapshots stay in view above a long history, in their own list.
strokes=""; for i in $(seq 1 30); do strokes="$strokes drag:$((i * 20)),300,$((i * 20)),340;"; done
run snapshotlist "showpanels; plusfeature:snapshots=1; tool:pencil; color:FF0000; expectsnapshotlist:0; snapshot;
 expectsnapshotlist:1; drag:10,10,10,50; snapshot; drag:30,10,30,50; snapshot; drag:50,10,50,50; snapshot; expectsnapshotlist:4;
 $strokes expecthistory:33; snapshot; expectsnapshotlist:5; plusfeature:snapshots=0; expectsnapshotlist:0;
 plusfeature:snapshots=1; expectsnapshotlist:5; gobacktosnapshot:1; expecthistory:34; expect:30,30,FFFFFF; expect:10,30,FF0000"

# Brushwood Plus smoothing: a zigzag drawn without smoothing keeps its corners; with it, the stroke runs straight
# through the middle and ends at the brush, a string's length before the pointer (no straight tail to it).
run smoothing "plusfeature:smoothing=1; plusfeature:magneticClosing=1; plusfeature:snapshots=1; tool:paintbrush; color:0000FF; width:6; setting:smoothing=0; path:100,300,110,292,120,308,130,292,140,308,150,292,160,308,170,292,180,308,190,292,200,308,210,292,220,308,230,292,240,308,250,292,260,308,270,292,280,308,290,292,300,308,310,300; expect:120,308,0000FF;
 setting:smoothing=1; path:100,400,110,392,120,408,130,392,140,408,150,392,160,408,170,392,180,408,190,392,200,408,210,392,220,408,230,392,240,408,250,392,260,408,270,392,280,408,290,392,300,408,310,400; expect:120,408,FFFFFF; expect:200,400,0000FF; expect:285,400,0000FF; expect:308,400,FFFFFF; expecthistory:2;
 setting:smoothing=0"

# Magnetic closing: a circle released near its start is joined to it; without the option the gap stays.
run closing "plusfeature:smoothing=1; plusfeature:magneticClosing=1; plusfeature:snapshots=1; tool:paintbrush; color:0000FF; width:8; setting:closing=0; path:560,300,559,283,557,267,552,251,546,235,539,220,529,206,519,193,507,181,494,171,480,161,465,154,449,148,433,143,417,141,400,140,383,141,367,143,351,148,335,154,320,161,306,171,293,181,281,193,271,206,261,220,254,235,248,251,243,267,241,283,240,300,241,317,243,333,248,349,254,365,261,380,271,394,281,407,293,419,306,429,320,439,335,446,351,452,367,457,383,459,400,460,417,459,433,457,449,452,465,446,480,439,494,429,507,419,519,407,529,394,539,380,546,365,552,349,557,333,558,322; expect:560,311,FFFFFF;
 menu:brushwoodUndo:; setting:closing=1; path:560,300,559,283,557,267,552,251,546,235,539,220,529,206,519,193,507,181,494,171,480,161,465,154,449,148,433,143,417,141,400,140,383,141,367,143,351,148,335,154,320,161,306,171,293,181,281,193,271,206,261,220,254,235,248,251,243,267,241,283,240,300,241,317,243,333,248,349,254,365,261,380,271,394,281,407,293,419,306,429,320,439,335,446,351,452,367,457,383,459,400,460,417,459,433,457,449,452,465,446,480,439,494,429,507,419,519,407,529,394,539,380,546,365,552,349,557,333,558,322; expect:560,311,0000FF; expect:400,140,0000FF; expecthistory:1;
 setting:closing=0"

# Brushwood Plus features turned off have no effect, alone or by category from the Plus Features window.
run plusfeatures "plusfeature:historyTimes=1; plusfeature:snapshots=1; plusfeature:smoothing=1; plusfeature:magneticClosing=1; tool:paintbrush; color:0000FF; width:6;
 setting:smoothing=1; plusfeature:smoothing=0; path:100,300,110,292,120,308,130,292,140,308,150,292,160,308,170,292,180,308,190,292,200,308,210,292,220,308,230,292,240,308,250,292,260,308,270,292,280,308,290,292,300,308,310,300; expect:120,308,0000FF; plusfeature:smoothing=1;
 plusfeature:snapshots=0; snapshot; expectsnapshots:0; plusfeature:snapshots=1; snapshot; expectsnapshots:1;
 plusfeatures:menu; plusclick:painting; expectplus:smoothing=0; expectplus:magneticClosing=0; expectplus:snapshots=1;
 plusclick:smoothing; expectplus:smoothing=1; plusclick:painting; expectplus:magneticClosing=1; plusclick:painting;
 expectplus:smoothing=0; expectplus:magneticClosing=0; plusclick:painting; expectplus:smoothing=1; plusclick:history;
 expectplus:historyTimes=0; expectplus:snapshots=0; plusfeature:historyTimes=1; plusfeature:snapshots=1; plusfeature:smoothing=1; plusfeature:magneticClosing=1; setting:smoothing=0"

# Brushwood Plus: the brush width's double-chevron stepper goes to the next multiple of 5, within 1…2000, for the tools
# that have a brush width, and is gone while its Plus feature is off.
run widthsnap "plusfeature:brushWidthSteps=1; tool:paintbrush; width:1; widthsnap:up; expectwidth:5; widthsnap:up;
 expectwidth:10; width:7; widthsnap:up; expectwidth:10; width:12; widthsnap:down; expectwidth:10; widthsnap:down;
 expectwidth:5; widthsnap:down; expectwidth:1; widthsnap:down; expectwidth:1; width:1999; widthsnap:up; expectwidth:2000;
 tool:shapes; expectwidthsnap:1; tool:pencil; expectwidthsnap:0; tool:paintbrush; plusfeature:brushWidthSteps=0;
 expectwidthsnap:0; plusfeature:brushWidthSteps=1; expectwidthsnap:1; width:2"

# Brushwood Plus tutorial: every step of every tour points at a part on screen; a tour goes forward and back and ends.
# Plus features are steps of the tours they belong to (tagged Plus), skipped while they are off.
run tutorial "showpanels; plusfeature:historyTimes=1; plusfeature:snapshots=1; plusfeature:smoothing=1; plusfeature:colorHistory=1;
 plusfeature:magneticClosing=1; plusfeature:brushWidthSteps=1; tutorialcheck; tutorialstart:paintbrush;
 expecttutorial:paintbrush,1; expecttutorialsteps:9; expecttutorialplus:0; tutorialnext; tutorialnext;
 expecttutorial:paintbrush,3; expecttutorialplus:1; expecttool:paintbrush; tutorialback; tutorialback;
 expecttutorial:paintbrush,1; tutorialend; expecttutorial:none; plusfeature:smoothing=0; plusfeature:magneticClosing=0;
 plusfeature:brushWidthSteps=0; tutorialstart:paintbrush; expecttutorialsteps:6; tutorialend; plusfeature:historyTimes=0;
 plusfeature:snapshots=0; plusfeature:colorHistory=0; tutorialstart:floating; expecttutorialsteps:4; tutorialend; plusfeature:historyTimes=1;
 plusfeature:snapshots=1; plusfeature:smoothing=1; plusfeature:magneticClosing=1; plusfeature:brushWidthSteps=1; plusfeature:colorHistory=1;
 tutorialstart:floating; expecttutorialsteps:7; tutorialnext; tutorialnext; expecttutorial:floating,3; expecttutorialplus:1; tutorialend;
 tutorialstart:shapes; tutorialnext; tutorialnext; tutorialnext; expecttutorial:shapes,4; expecttool:shapes; tutorialnext;
 tutorialnext; tutorialnext; expecttutorial:shapes,7; tutorialnext; expecttutorial:none"

# Brushwood Plus guided project "Evening Lake": every step, carried out with the tools as a user would, is not done
# before its action and done after it; the image is saved with its layers at the end.
run project "plusfeature:snapshots=1; plusfeature:smoothing=1; plusfeature:brushWidthSteps=1;
 project:eveningLake; expectproject:1,done; projectnext;
 expectproject:2,waiting; layername:Sky; expectproject:2,done; projectnext;
 expectproject:3,waiting; projectcolors; expectproject:3,done; projectnext;
 expectproject:4,waiting; tool:gradient; path:600,0,600,300,600,560; keyeq:return; expectproject:4,done; projectnext;
 expectproject:5,waiting; projectcolors; tool:paintbrush; width:3; click:80,40; click:200,90; click:330,30; click:470,120; click:560,60; click:690,150; click:820,40; click:950,110; click:1080,70; click:1150,160; click:260,200; click:640,230; expectproject:5,done; projectnext;
 expectproject:6,waiting; snapshot; expectproject:6,done; projectnext;
 expectproject:7,waiting; menu:addLayer:; expectproject:7,waiting; layername:Sun; expectproject:7,done; projectnext;
 expectproject:8,waiting; tool:ellipseSelect; drag:740,400,860,520; key:return; expectproject:8,done; projectnext;
 expectproject:9,waiting; projectcolors; menu:fillSelection:; expectproject:9,done; projectnext;
 expectproject:10,waiting; menu:deselect:; expectproject:10,waiting; effectvalues:Gaussian Blur|radius=30; expectproject:10,done; projectnext;
 expectproject:11,waiting; layerprops:255,12,1; expectproject:11,done; projectnext;
 menu:addLayer:; layername:Mountains; expectproject:12,done; projectnext;
 expectproject:13,waiting; tool:lassoSelect; path:0,560,0,440,160,360,330,430,520,320,700,450,810,500,960,410,1100,370,1200,430,1200,560,0,560; key:return; expectproject:13,done; projectnext;
 expectproject:14,waiting; projectcolors; menu:fillSelection:; expectproject:14,waiting; menu:deselect:; expectproject:14,done; projectnext;
 menu:addLayer:; layername:Lake; expectproject:15,done; projectnext;
 expectproject:16,waiting; tool:rectangleSelect; drag:0,560,1200,800; key:return; expectproject:16,done; projectnext;
 expectproject:17,waiting; projectcolors; tool:gradient; path:600,565,600,700,600,795; keyeq:return; expectproject:17,done; projectnext;
 expectproject:18,waiting; menu:deselect:; menu:selectLayerBelow:; menu:duplicateLayer:; expectproject:18,done; projectnext;
 expectproject:19,waiting; menu:flipLayerVertical:; expectproject:19,done; projectnext;
 expectproject:20,waiting; menu:selectAll:; tool:moveSelectedPixels; drag:600,300,600,620; key:return; menu:deselect:; expectproject:20,done; projectnext;
 expectproject:21,waiting; menu:moveLayerUp:; expectproject:21,done; projectnext;
 expectproject:22,waiting; layerprops:100,0,1; expectproject:22,done; projectnext;
 menu:addLayer:; layername:Forest; expectproject:23,done; projectnext;
 expectproject:24,waiting; projectcolors; tool:paintbrush; width:6; path:0,590,150,598,300,630,400,690,450,760,470,799; expectproject:24,done; projectnext;
 expectproject:25,waiting; tool:paintBucket; click:100,720; key:return; expectproject:25,done; projectnext;
 expectproject:26,waiting; tool:shapes; shape:3; drawtype:1; drag:40,330,110,600; key:return; drag:140,380,200,610; key:return; drag:240,420,300,640; key:return; expectproject:26,done; projectnext;
 expectproject:27,waiting; menu:addLayer:; layername:Birds; projectcolors; tool:paintbrush; width:4; path:310,180,330,192,350,180; path:360,210,372,218,384,210; path:290,230,300,237,310,230; expectproject:27,done; projectnext;
 expectproject:28,waiting; menu:selectBottomLayer:; effectvalues:Clouds|blendMode=15|scale=320|power=0.6; expectproject:28,done; projectnext;
 expectproject:29,waiting; menu:selectTopLayer:; menu:addLayer:; layername:Title; projectcolors; tool:text; setting:fontsize=64; click:420,60; type:Evening Lake; key:return; expectproject:29,done; projectnext;
 expectproject:30,waiting; saveas:$OUT/lake.ora; expectproject:30,done; projectnext;
 expectproject:31,done; projectnext; expectproject:none"

# Floating windows follow their corner of the canvas when the main window is resized.
run panels "showpanels; expectpanels; panel:1400,900; expectpanels; panel:820,560; expectpanels;
 panel:1280,820; expectpanels"

# Thumbnails refresh 0.4 s after an edit; that must not move the active layer back to the top.
run activelayer "menu:addLayer:; menu:addLayer:; menu:selectBottomLayer:; tool:pencil; color:FF0000; drag:10,10,10,30;
 wait:0.6; expectactivelayer:0; menu:selectLayerAbove:; expectactivelayer:1"

run move "select:10,10,20,20; color:FF0000; menu:fillSelection:; tool:moveSelectedPixels; drag:20,20,120,20; key:return;
 expect:115,15,FF0000; expect:15,15,FF000000; expectselection:110,10,20,20; menu:copy:; menu:deselect:; menu:paste:;
 key:return; expect:5,5,FF0000; menu:brushwoodUndo:; expect:5,5,FFFFFF; tool:moveSelection; select:200,200,50,50;
 drag:210,210,260,260; expectselection:250,250,50,50"

run vector "tool:shapes; shape:0; drawtype:1; color:0000FF; drag:300,300,400,400; key:return; expect:350,350,0000FF;
 tool:lineCurve; color:00FF00; width:5; drag:300,500,500,500; key:return; expect:400,500,00FF00;
 tool:magicWand; click:350,350; key:return; expectselection:300,300,100,100; menu:deselect:;
 tool:gradient; color:000000; color:FFFFFF,secondary; drag:0,0,800,0; key:return; expect:2,550,000000,8; expect:797,550,FFFFFF,8;
 tool:text; color:FF0000; click:20,20; type:Hello; key:return; expecthistory:6"

run effects "effect:Invert Colors; expect:5,5,000000; effect:Gaussian Blur; expect:5,5,000000; effect:Sepia;
 effect:Hue / Saturation; effect:Pixelate; expecthistory:5; menu:brushwoodUndo:; menu:brushwoodUndo:; menu:brushwoodUndo:; menu:brushwoodUndo:; expect:5,5,000000"

run files "tool:pencil; color:FF0000; drag:1,1,1,20; menu:addLayer:; save:$OUT/t.ora; open:$OUT/t.ora; expectlayers:2;
 expect:1,10,FF0000; save:$OUT/t.pdn; open:$OUT/t.pdn; expectlayers:2; expect:1,10,FF0000;
 save:$OUT/t.png; open:$OUT/t.png; expectlayers:1; expect:1,10,FF0000"

run tools2 "tool:pencil; color:FF0000; drag:10,10,10,30; tool:cloneStamp; width:6; click:10,20,cmd; drag:100,20,100,22;
 expect:100,21,FF0000; tool:colorPicker; click:100,21; expectcolor:primary,FF0000; click:500,500,right;
 expectcolor:secondary,FFFFFF; setting:pickafter=1; tool:paintbrush; tool:colorPicker; click:5,5; expecttool:paintbrush;
 setting:pickafter=0; color:00FF00; color:FF0000,secondary; tool:recolor; width:20; drag:10,15,10,25; expect:10,20,00FF00;
 expect:100,21,FF0000"

run live "tool:paintBucket; color:0000FF; select:0,0,800,600; menu:deselect:; tool:pencil; color:000000; drag:400,0,400,599;
 tool:paintBucket; color:0000FF; click:10,10; expect:10,10,0000FF; expect:700,10,FFFFFF; setting:flood=1;
 expect:700,10,0000FF; setting:flood=0; expect:700,10,FFFFFF; key:return; setting:fill=5; color:FF0000;
 color:FFFF00,secondary; click:700,10; key:return; setting:fill=0; tool:gradient; color:000000; color:FFFFFF,secondary;
 setting:transparency=1; drag:0,0,0,600; key:return; expect:10,595,0000FF00,10; setting:transparency=0"

run text "tool:text; color:000000; setting:fontsize=24; click:50,50; type:AB; textcmd:deleteBackward:; type:C\nD;
 expecttext:AC|D; textcmd:moveLeft:; textcmd:moveLeft:; textcmd:moveLeft:; type:X; expecttext:AXC|D;
 textcmd:insertNewline:; expecttext:AX|C|D; textcmd:deleteBackward:; textcmd:moveToEndOfLine:; type:!; expecttext:AXC!|D;
 key:return; expecthistory:1"

run image "tool:pencil; color:FF0000; drag:0,0,0,0; resize:400,300; expectsize:400,300; menu:brushwoodUndo:; expectsize:800,600;
 canvassize:1000,700,2,2; expectsize:1000,700; expect:999,699,000000,255; expect:200,100,FF0000; menu:brushwoodUndo:;
 menu:rotateImageCW:; expectsize:600,800; expect:599,0,FF0000; menu:brushwoodUndo:; menu:flipImageHorizontal:; expect:799,0,FF0000;
 menu:brushwoodUndo:; menu:flipLayerVertical:; expect:0,599,FF0000; menu:brushwoodUndo:; expect:0,0,FF0000"

run layers2 "menu:addLayer:; tool:paintBucket; color:FF0000; click:10,10; key:return; layerprops:128,0,1;
 expect:10,10,FF8080,3; layerprops:255,1,1; expect:10,10,FF0000; menu:brushwoodUndo:; menu:brushwoodUndo:; layerprops:255,0,0;
 expect:10,10,FFFFFF; menu:brushwoodUndo:; effectvalues:Rotate / Zoom|zoom=0.5; expect:10,10,FFFFFF; expect:400,300,FF0000;
 effectvalues:Brightness / Contrast|brightness=-100; effectvalues:Gaussian Blur|radius=20"

run images "new:300,200; expectimages:2; expectsize:300,200; activate:0; expectsize:800,600; menu:nextImage:;
 expectsize:300,200; menu:pasteIntoNewImage:; tool:zoom; click:150,100; expectzoom:1.5; click:150,100,right; expectzoom:1"

run keyboard "tool:paintbrush; color:FF0000; width:10; drag:100,100,300,100; expect:200,100,FF0000; keyeq:z,cmd;
 expect:200,100,FFFFFF; keyeq:z,cmd,shift; expect:200,100,FF0000; keyeq:z,cmd; keyeq:y,cmd; expect:200,100,FF0000;
 select:150,80,100,40; keyeq:delete; expect:200,100,FF000000; expectselection:none; keyeq:z,cmd; expect:200,100,FF0000;
 expectselection:150,80,100,40; keyeq:d,cmd; expectselection:none; keyeq:a,cmd; expectselection:0,0,800,600;
 keyeq:d,cmd; keyeq:n,cmd,shift; expectlayers:2; keyeq:d,cmd,shift; expectlayers:3; keyeq:z,cmd; keyeq:z,cmd; expectlayers:1;
 keyeq:i,cmd,shift; expect:10,10,000000; keyeq:z,cmd; expect:10,10,FFFFFF; select:0,0,400,300; keyeq:x,cmd,shift;
 expectsize:400,300; keyeq:z,cmd; expectsize:800,600"

run width "tool:paintbrush; width:2; widthcombo:select,25; expectwidth:25; color:FF0000; drag:100,100,300,100;
 expect:200,106,FF0000,8; expect:200,120,FFFFFF; widthcombo:type,40; expectwidth:40; widthcombo:blur; expectwidth:40; drag:100,300,300,300;
 expect:200,312,FF0000,8; expect:200,330,FFFFFF; widthcombo:wheel,up; expectwidth:45; widthcombo:wheel,down; widthcombo:wheel,down; expectwidth:35;
 tool:eraser; expectwidth:35; widthcombo:type,3; widthcombo:blur; expectwidth:3"

run pan "expectfreescroll; zoom:0.25; expectpanlimits; zoom:1; expectpanlimits; zoom:8; expectpanlimits; tool:pencil; color:FF0000;
 zoom:0.5; scrollby:200,100; drag:10,10,10,40; expect:10,25,FF0000; zoom:2; scrollby:-300,50; expectzoom:2"

rm -rf "$OUT"
[ $fail -eq 0 ] && echo "UI smoke tests passed" || { echo "UI smoke tests FAILED"; exit 1; }
