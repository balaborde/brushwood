// Draws the background of the disk image window (used by scripts/make-dmg.sh).
//   swift scripts/dmg-background.swift <out.png> <out@2x.png>
// The window content is 640 × 400 points, with the app icon centered at (170, 190) and the Applications
// folder at (470, 190), measured from the top left. The picture is 40 points taller, since Finder pins it to
// the top left and the title bar height differs between macOS versions. Finder draws the icon names in black
// in Light Mode and in white in Dark Mode, so the background is a mid-tone that keeps both readable.
import AppKit

let size = NSSize(width: 640, height: 440)
let args = CommandLine.arguments
guard args.count == 3 else {
    print("usage: dmg-background.swift <out.png> <out@2x.png>")
    exit(2)
}

/// Converts a y coordinate measured from the top (as Finder does) to AppKit's bottom-up one.
func top(_ y: CGFloat) -> CGFloat { size.height - y }

func draw() {
    let bounds = NSRect(origin: .zero, size: size)
    NSGradient(colors: [NSColor(srgbRed: 0.64, green: 0.53, blue: 0.43, alpha: 1),
                        NSColor(srgbRed: 0.42, green: 0.33, blue: 0.26, alpha: 1)])?
        .draw(in: bounds, relativeCenterPosition: NSPoint(x: 0, y: 0.2))

    // Faint strokes in the icon's colors along the bottom edge.
    let strokes: [(NSColor, CGFloat)] = [
        (NSColor(srgbRed: 0.91, green: 0.30, blue: 0.24, alpha: 1), 352),
        (NSColor(srgbRed: 0.98, green: 0.78, blue: 0.20, alpha: 1), 364),
        (NSColor(srgbRed: 0.20, green: 0.52, blue: 0.86, alpha: 1), 376),
        (NSColor(srgbRed: 0.30, green: 0.69, blue: 0.31, alpha: 1), 388),
    ]
    for (color, y) in strokes {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: -20, y: top(y)))
        p.curve(to: NSPoint(x: 660, y: top(y - 6)), controlPoint1: NSPoint(x: 200, y: top(y - 22)),
                controlPoint2: NSPoint(x: 430, y: top(y + 16)))
        p.lineWidth = 7
        p.lineCapStyle = .round
        color.withAlphaComponent(0.35).setStroke()
        p.stroke()
    }

    // A brush-drawn arrow from the app to the Applications folder (one layer, so the overlap is not brighter).
    let cg = NSGraphicsContext.current!.cgContext
    cg.setAlpha(0.9)
    cg.beginTransparencyLayer(auxiliaryInfo: nil)
    NSColor.white.setStroke()
    let shaft = NSBezierPath()
    shaft.move(to: NSPoint(x: 262, y: top(196)))
    shaft.curve(to: NSPoint(x: 376, y: top(186)), controlPoint1: NSPoint(x: 300, y: top(174)),
                controlPoint2: NSPoint(x: 336, y: top(204)))
    shaft.lineWidth = 9
    shaft.lineCapStyle = .round
    shaft.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 354, y: top(166)))
    head.line(to: NSPoint(x: 378, y: top(186)))
    head.line(to: NSPoint(x: 352, y: top(204)))
    head.lineWidth = 9
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()
    cg.endTransparencyLayer()
}

func render(scale: CGFloat, to path: String) {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                     pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                                     bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let t = NSAffineTransform()
    t.scale(by: scale)
    t.concat()
    draw()
    NSGraphicsContext.restoreGraphicsState()
    rep.size = size // 72 dpi at 1x and 144 dpi at 2x, so Finder shows both at the same size
    guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
    do { try png.write(to: URL(fileURLWithPath: path)) } catch { print(error); exit(1) }
}

render(scale: 1, to: args[1])
render(scale: 2, to: args[2])
