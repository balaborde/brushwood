# Brushwood

**A free, open-source image editor for macOS that works like Paint.NET.**

Brushwood brings Paint.NET's workflow to the Mac as a native AppKit application: one main window with image tabs, the four
floating windows (Tools, History, Layers, Colors), layers with blend modes, unlimited history you can click through,
editable shapes and selections, and the full set of Adjustments and Effects with live preview.

> *En bref (FR) :* Brushwood est une alternative libre à Paint.NET pour macOS, écrite en Swift/AppKit. Même organisation
> (fenêtre principale à onglets, fenêtres flottantes Outils/Historique/Calques/Couleurs), mêmes outils, mêmes réglages et
> effets, mêmes raccourcis (Ctrl → ⌘). L'interface est disponible en anglais et en français.

Brushwood is an independent project. It is not affiliated with or endorsed by dotPDN LLC; "Paint.NET" is a trademark of its
owner. No Paint.NET code, icons or other assets are used — every icon is drawn in code.

## Features

**Window layout (as in Paint.NET)**
- Main toolbar (New, Open, Save, Print, Cut/Copy/Paste, Crop to Selection, Deselect, Undo/Redo, Pixel Grid, Rulers) with
  the image list as thumbnails, and toggles for the floating windows
- Context-sensitive tool bar with the active tool's options
- Floating **Tools**, **History**, **Layers** and **Colors** windows (F5–F8)
- Status bar with tool hint, selection size, cursor position, units and zoom slider
- Rulers, pixel grid, units (pixels / inches / centimeters), checkerboard transparency, drag & drop to open

**Tools** (same order and letter shortcuts as Paint.NET; pressing a letter again cycles tools that share it)

| Key | Tools |
|-----|-------|
| M | Move Selected Pixels (move, scale with handles, rotate with right-drag, ⌘-drag leaves a copy), Move Selection |
| S | Rectangle Select, Lasso Select, Ellipse Select, Magic Wand |
| Z / H | Zoom, Pan (hold Space anywhere to pan) |
| F / G | Paint Bucket (live: tolerance, fill style and origin stay editable), Gradient (7 types, color/transparency modes, repeat modes, editable handles) |
| B / E / P | Paintbrush (width, hardness, antialiasing, blend mode), Eraser, Pencil |
| K / L / R | Color Picker (sample size, layer/image, after-click action), Clone Stamp (⌘-click sets the source), Recolor |
| T / O | Text (font, size, bold/italic/underline/strikethrough, alignment; editable until finished), Line/Curve (spline handles, dash styles, arrow caps), Shapes (31 shapes, outline/filled/both) |

Selections combine like Paint.NET: ⌘ = union, ⌥ = exclude, right-click = xor, ⌥+right-click = intersect, or pick the mode in
the tool bar. Every tool can use any of the layer blend modes, or **Overwrite**.

**Layers** — add, delete, duplicate, merge down, move up/down (or drag in the Layers window), import from file, flip,
Rotate/Zoom, properties (name, visibility, opacity, blend mode). Blend modes: Normal, Multiply, Additive, Color Burn,
Color Dodge, Reflect, Glow, Overlay, Difference, Negation, Lighten, Darken, Screen, Xor (Paint.NET's set, verified
pixel-exact against Paint.NET renders), plus Hard Light, Soft Light, Color, Luminosity, Hue and Saturation.

**Image** — Crop to Selection, Resize (Best Quality, Supersampling, Bicubic, Bilinear, Lanczos 3, Nearest Neighbor; by
percentage or absolute size, print size), Canvas Size with anchor, Flip, Rotate 90°/180°, Flatten.

**Adjustments** — Auto-Level, Black and White, Brightness/Contrast, Curves (luminosity or per-channel RGB), Exposure,
Highlights/Shadows, Hue/Saturation, Invert Alpha, Invert Colors, Levels, Posterize, Sepia, Temperature and Tint.

**Effects** (all with live preview; ⌘F repeats the last one) — the same menu as Paint.NET 5
- Artistic: Ink Sketch, Oil Painting, Pencil Sketch
- Blurs: Bokeh Blur, Fragment Blur, Gaussian Blur, Median Blur, Motion Blur, Radial Blur, Sketch Blur, Square Blur,
  Surface Blur, Zoom Blur
- Color: Quantize (Octree or Median Cut, dithering)
- Distort: Bulge, Crystalize, Dents, Frosted Glass, Morphology, Pixelate, Polar Inversion, Tile Reflection, Twist
- Noise: Add Noise, Reduce Noise
- Object: Drop Shadow, Feather, Outline Object
- Photo: Glow, Red Eye Removal, Sharpen, Soften Portrait, Straighten, Vignette
- Render: Clouds, Julia Fractal, Mandelbrot Fractal, Turbulence, Voronoi Diagram
- Stylize: Edge Detect, Emboss, Outline, Relief

**Colors** — primary/secondary colors, HSV wheel, 96-color palette (Paint.NET's default; load/save Paint.NET `.txt`
palettes), hex/RGB/HSV/alpha controls.

**Files**

| Format | Open | Save | Notes |
|--------|:----:|:----:|-------|
| Paint.NET `.pdn` | ✓ | ✓ | Default for layered images. Layers, names, opacity, visibility and blend modes |
| OpenRaster `.ora` | ✓ | ✓ | Layered format also read by Krita, GIMP and MyPaint; keeps the extra blend modes |
| PNG, JPEG, BMP, GIF, TIFF, TGA, DDS, HEIC, AVIF, ICO | ✓ | ✓ | Quality / bit depth options, live file-size estimate |
| WebP, JPEG XL, PSD (flattened) | ✓ | | via ImageIO |

Clipboard (copy, copy merged, paste, paste into new layer / new image), printing, recent files and unsaved-changes
prompts are supported.

## Requirements

- macOS 13 Ventura or later (Apple silicon or Intel)
- To build: Swift 5.9+ (the Xcode Command Line Tools are enough — a full Xcode install is not required)

## Building

```sh
scripts/build-app.sh          # builds build/Brushwood.app (release)
open build/Brushwood.app
```

During development you can also run `swift run Brushwood`.

The app is signed ad hoc. The first time you open a copy downloaded from elsewhere, macOS may ask you to confirm it in
**System Settings › Privacy & Security**.

## Keyboard shortcuts

Paint.NET's shortcuts with Ctrl mapped to ⌘. Where macOS reserves a key, Brushwood uses an alternative:

| Command | Paint.NET | Brushwood |
|---------|-----------|-----------|
| Rotate 90° clockwise | Ctrl+H | ⌃⌘H (⌘H hides the app) |
| Merge Layer Down | Ctrl+M | ⌃⌘M (⌘M minimizes) |
| Layer Rotate/Zoom | Ctrl+Shift+Z | ⌥⌘Z (⇧⌘Z is Redo) |
| Redo | Ctrl+Y | ⇧⌘Z or ⌘Y |
| Toggle Layer Visibility | Ctrl+, | ⌃⌘, (⌘, opens Settings) |
| Erase / Fill Selection | Delete / Backspace | ⌫ / ⇧⌫ |

The complete list is under **Help › Keyboard Shortcuts**.

## Project layout

```
Sources/BrushwoodCore/     Pixel engine (no UI): surfaces, layers, blend modes, selections, history,
                           flood fill, resampling, adjustments & effects, file formats (PDN read/write, ORA, ImageIO)
Sources/Brushwood/         AppKit application
  App/                     app delegate, menus, main window controller, documents, effects plumbing
  Canvas/                  tiled canvas view and renderer
  Tools/                   the 19 tools
  Panels/                  Tools, History, Layers and Colors windows
  Chrome/                  toolbars, status bar, icons, shared controls
  Dialogs/                 effect dialogs (auto-generated), Curves, Levels, New/Resize/Canvas Size, etc.
Resources/                 Info.plist and localizations (fr.lproj is generated by scripts/gen_strings.py)
Tests/SelfTest/            engine test suite
scripts/                   app bundling, UI smoke tests, localization generator
```

Pixels are stored as straight-alpha BGRA like Paint.NET's `ColorBgra`. Blend modes, flood-fill tolerance and the main
adjustments (Brightness/Contrast, Hue/Saturation, Levels, Sepia, Posterize…) follow Paint.NET's published 3.x algorithms.

## Testing

```sh
swift run -c release selftest          # engine tests (blend modes, selections, flood fill, history, formats, effects)
swift run -c release selftest <dir>    # also checks .pdn decoding and blend modes against Paint.NET reference renders
                                       # (FlattenBlendTest.pdn + Flatten*Test.png from the pypdn project)
scripts/ui-smoke-test.sh               # drives the app through scripted scenarios and checks the resulting pixels
```

The UI tests use a private pasteboard, so they never touch your clipboard.

## Localization

Strings are written in English in the source (`L("…")`). To add or update a language, edit `scripts/fr_translations.py`
(or add a new table) and run `python3 scripts/gen_strings.py`, which reports any untranslated strings.

## Known differences from Paint.NET

- `.pdn` files are written with the same object graph and chunked pixel layout as Paint.NET 4.21 (checked record by
  record against files saved by Paint.NET), but they have not been opened in Paint.NET itself during development. The six
  extra blend modes are saved as Normal in `.pdn` (Brushwood warns and suggests OpenRaster).
- Several effects (for example Ink Sketch, Dents, Frosted Glass, Vignette, the Paint.NET 5 additions such as Bokeh Blur,
  Sketch Blur, Crystalize or Turbulence, and the Object effects) are reimplementations of the documented behaviour, not
  exact ports, so their output can differ from Paint.NET's.
- Selection handles of Move Selected Pixels follow the axis-aligned bounds (Paint.NET rotates them with the content).
- No plugin system, no tablet pressure, and no Windows-specific features such as scanner/camera acquisition.

## License

MIT — see [LICENSE](LICENSE).
