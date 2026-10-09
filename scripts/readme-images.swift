// Helper for scripts/make-readme-images.sh.
//   readme-images art <dir>                          writes the demo picture as OpenRaster parts (stack.xml, data/*.png)
//   readme-images banner <icon.png> <out.png>        draws the README banner (also the repository's social preview)
//   readme-images frame <width> <height>             prints a main-window frame centered on the main screen
//   readme-images capture <pid> <out.png> <max-px>   captures the windows of a process, composited with shadows
//   readme-images capture-finder <title> <out.png> <max-px>   same for one Finder window
import AppKit

let args = CommandLine.arguments
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

func writePNG(_ image: CGImage, to path: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else { fail("could not encode \(path)") }
    do { try data.write(to: URL(fileURLWithPath: path)) } catch { fail("\(error)") }
}

/// A bitmap context with the origin at the top left, like image coordinates.
func canvas(_ width: Int, _ height: Int) -> CGContext {
    guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fail("no bitmap context") }
    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: 1, y: -1)
    ctx.interpolationQuality = .high
    return ctx
}

func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: stops.map(\.1) as CFArray,
               locations: stops.map(\.0))!
}

/// Deterministic random numbers, so the demo picture is the same on every run.
struct Random {
    var state: UInt64
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(state >> 11) / CGFloat(1 << 53)
    }
    mutating func range(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * next() }
}

// MARK: - Demo picture

/// A lake at sunset in separate layers, so the Layers window has something to show.
func drawArt(to dir: String) {
    let w = 1200, h = 800
    let W = CGFloat(w), horizon: CGFloat = 560
    var rnd = Random(state: 7)

    /// A mountain ridge through the given peaks, roughened by midpoint displacement.
    func ridge(_ peaks: [(CGFloat, CGFloat)], roughness: CGFloat) -> [CGPoint] {
        var pts = peaks.map { CGPoint(x: $0.0, y: $0.1) }
        var amp = roughness
        for _ in 0..<7 {
            var next: [CGPoint] = []
            for (a, b) in zip(pts, pts.dropFirst()) {
                next.append(a)
                next.append(CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 + rnd.range(-amp, amp)))
            }
            next.append(pts.last!)
            pts = next
            amp *= 0.55
        }
        return pts
    }
    func fill(_ ctx: CGContext, ridge pts: [CGPoint], base: CGFloat, mirrored: Bool = false) {
        ctx.beginPath()
        ctx.move(to: CGPoint(x: pts[0].x, y: base))
        for p in pts { ctx.addLine(to: CGPoint(x: p.x, y: mirrored ? 2 * horizon - p.y : p.y)) }
        ctx.addLine(to: CGPoint(x: pts.last!.x, y: base))
        ctx.closePath()
    }
    let far = ridge([(-20, 420), (160, 360), (330, 430), (520, 318), (700, 450), (810, 505), (960, 410), (1100, 372), (1220, 430)],
                    roughness: 26)
    let near = ridge([(-20, 470), (140, 500), (320, 418), (520, 520), (700, 548), (880, 500), (1060, 432), (1220, 478)],
                     roughness: 20)
    let sun = CGPoint(x: 800, y: 520)

    var layers: [(name: String, op: String, image: CGImage)] = []
    func layer(_ name: String, op: String = "svg:src-over", _ draw: (CGContext) -> Void) {
        let ctx = canvas(w, h)
        draw(ctx)
        layers.append((name, op, ctx.makeImage()!))
    }

    layer("Sky") { ctx in
        let sky = gradient([(0, color(0x141C45)), (0.32, color(0x3B3A7A)), (0.6, color(0x9C5490)), (0.8, color(0xEE7E5C)),
                            (1, color(0xFFC77D))])
        ctx.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: horizon), options: [.drawsAfterEndLocation])
        for _ in 0..<150 {
            let y = pow(rnd.next(), 1.6) * 330, r = rnd.range(0.5, 1.7)
            ctx.setFillColor(color(0xFFFFFF, (1 - y / 330) * rnd.range(0.4, 0.95)))
            ctx.fillEllipse(in: CGRect(x: rnd.range(0, W), y: y, width: r * 2, height: r * 2))
        }
    }
    layer("Sun", op: "svg:screen") { ctx in
        let glow = gradient([(0, color(0xFFE2A8, 0.75)), (0.25, color(0xFFB27A, 0.35)), (1, color(0xFF8A6A, 0))])
        ctx.drawRadialGradient(glow, startCenter: sun, startRadius: 0, endCenter: sun, endRadius: 380, options: [])
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: sun.x - 62, y: sun.y - 62, width: 124, height: 124))
        ctx.clip()
        ctx.drawLinearGradient(gradient([(0, color(0xFFF6D6)), (1, color(0xFFC165))]), start: CGPoint(x: 0, y: sun.y - 62),
                               end: CGPoint(x: 0, y: sun.y + 62), options: [])
        ctx.restoreGState()
    }
    layer("Far mountains") { ctx in
        fill(ctx, ridge: far, base: horizon + 2)
        ctx.saveGState()
        ctx.clip()
        ctx.drawLinearGradient(gradient([(0, color(0x9C6E9E)), (1, color(0xC98A92))]), start: CGPoint(x: 0, y: 320),
                               end: CGPoint(x: 0, y: horizon), options: [])
        ctx.restoreGState()
    }
    layer("Mountains") { ctx in
        fill(ctx, ridge: near, base: horizon + 2)
        ctx.saveGState()
        ctx.clip()
        ctx.drawLinearGradient(gradient([(0, color(0x4A3A72)), (1, color(0x6A4A7E))]), start: CGPoint(x: 0, y: 420),
                               end: CGPoint(x: 0, y: horizon), options: [])
        // Haze along the water line.
        ctx.drawLinearGradient(gradient([(0, color(0xF3A07E, 0)), (1, color(0xF3A07E, 0.45))]), start: CGPoint(x: 0, y: 500),
                               end: CGPoint(x: 0, y: horizon), options: [])
        ctx.restoreGState()
    }
    layer("Lake") { ctx in
        let water = gradient([(0, color(0xE58A78)), (0.35, color(0x8C4F7E)), (1, color(0x1F2350))])
        ctx.drawLinearGradient(water, start: CGPoint(x: 0, y: horizon), end: CGPoint(x: 0, y: CGFloat(h)), options: [])
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: horizon, width: W, height: CGFloat(h) - horizon))
        // Reflections of the mountains, fading with depth.
        fill(ctx, ridge: far, base: horizon, mirrored: true)
        ctx.setFillColor(color(0x8E5E8E, 0.45))
        ctx.fillPath()
        fill(ctx, ridge: near, base: horizon, mirrored: true)
        ctx.setFillColor(color(0x3E2F62, 0.5))
        ctx.fillPath()
        ctx.restoreGState()
        // Glitter under the sun.
        ctx.setLineCap(.round)
        for i in 0..<48 {
            let t = CGFloat(i) / 48, y = horizon + 5 + pow(t, 1.3) * 225
            for _ in 0..<(rnd.next() < 0.4 ? 2 : 1) {
                let half = (10 + t * 60) * rnd.range(0.3, 1)
                let x = sun.x + rnd.range(-1, 1) * (14 + t * 60)
                ctx.setStrokeColor(color(0xFFE0A6, (1 - t) * rnd.range(0.45, 0.9)))
                ctx.setLineWidth(1.5 + t * 3)
                ctx.move(to: CGPoint(x: x - half, y: y))
                ctx.addLine(to: CGPoint(x: x + half, y: y))
                ctx.strokePath()
            }
        }
    }
    layer("Forest") { ctx in
        let dark = [color(0x16142C), color(0x1C1936), color(0x110F24)]
        func pine(_ x: CGFloat, _ base: CGFloat, _ height: CGFloat) {
            let width = height * rnd.range(0.32, 0.4), tiers = 5
            var right: [CGPoint] = [], left: [CGPoint] = []
            for k in 1...tiers {
                let t = CGFloat(k) / CGFloat(tiers)
                let y = base - height + height * 0.92 * t, half = width / 2 * t
                right.append(CGPoint(x: x + half, y: y))
                right.append(CGPoint(x: x + half * 0.45, y: y - height * 0.05))
                left.append(CGPoint(x: x - half, y: y))
                left.append(CGPoint(x: x - half * 0.45, y: y - height * 0.05))
            }
            ctx.beginPath()
            ctx.move(to: CGPoint(x: x, y: base - height))
            for p in right { ctx.addLine(to: p) }
            ctx.addLine(to: CGPoint(x: x + width * 0.05, y: base))
            ctx.addLine(to: CGPoint(x: x - width * 0.05, y: base))
            for p in left.reversed() { ctx.addLine(to: p) }
            ctx.closePath()
            ctx.setFillColor(dark[Int(rnd.next() * 3) % 3])
            ctx.fillPath()
        }
        /// A shore through the points (smoothed), closed along the bottom edge.
        func bank(_ points: [CGPoint]) {
            ctx.beginPath()
            ctx.move(to: points[0])
            for (a, b) in zip(points.dropFirst(), points.dropFirst(2)) {
                ctx.addQuadCurve(to: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), control: a)
            }
            ctx.addLine(to: points.last!)
            ctx.addLine(to: CGPoint(x: points.last!.x, y: 800))
            ctx.addLine(to: CGPoint(x: points[0].x, y: 800))
            ctx.closePath()
            ctx.setFillColor(dark[2])
            ctx.fillPath()
        }
        // Left shore, close and tall; right shore, farther away.
        bank([CGPoint(x: 0, y: 586), CGPoint(x: 160, y: 598), CGPoint(x: 300, y: 628), CGPoint(x: 400, y: 690),
              CGPoint(x: 450, y: 760), CGPoint(x: 470, y: 801)])
        for i in stride(from: 0, to: 19, by: 1) {
            let x = CGFloat(i) * 21 + rnd.range(-6, 6) - 10
            let base = 600 + max(0, x - 120) * 0.25 + rnd.range(0, 30)
            pine(x, base, rnd.range(150, 300) * (1 - max(0, x - 200) / 500))
        }
        bank([CGPoint(x: 1200, y: 596), CGPoint(x: 1090, y: 604), CGPoint(x: 1000, y: 632), CGPoint(x: 950, y: 690),
              CGPoint(x: 920, y: 760), CGPoint(x: 910, y: 801)])
        for i in 0..<12 {
            let x = 1210 - CGFloat(i) * 20 + rnd.range(-5, 5)
            pine(x, 612 + rnd.range(0, 14) + max(0, 1090 - x) * 0.3, rnd.range(90, 170) * (1 - max(0, 1050 - x) / 400))
        }
    }
    layer("Birds") { ctx in
        ctx.setStrokeColor(color(0x231C3A, 0.85))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for (x, y, s) in [(330.0, 190.0, 1.0), (372, 214, 0.75), (300, 236, 0.65), (412, 178, 0.55)] as [(CGFloat, CGFloat, CGFloat)] {
            ctx.setLineWidth(3 * s)
            ctx.move(to: CGPoint(x: x - 16 * s, y: y - 6 * s))
            ctx.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: x - 8 * s, y: y - 10 * s))
            ctx.addQuadCurve(to: CGPoint(x: x + 16 * s, y: y - 6 * s), control: CGPoint(x: x + 8 * s, y: y - 10 * s))
            ctx.strokePath()
        }
    }

    let fm = FileManager.default
    try? fm.createDirectory(atPath: dir + "/data", withIntermediateDirectories: true)
    try? Data("image/openraster".utf8).write(to: URL(fileURLWithPath: dir + "/mimetype"))
    var xml = "<?xml version='1.0' encoding='UTF-8'?>\n<image w=\"\(w)\" h=\"\(h)\" version=\"0.0.3\">\n<stack>\n"
    for (i, l) in layers.enumerated().reversed() {
        writePNG(l.image, to: dir + "/data/layer\(i).png")
        xml += "<layer name=\"\(l.name)\" src=\"data/layer\(i).png\" x=\"0\" y=\"0\" opacity=\"1.000\" visibility=\"visible\" "
        xml += "composite-op=\"\(l.op)\"/>\n"
    }
    xml += "</stack>\n</image>\n"
    try? Data(xml.utf8).write(to: URL(fileURLWithPath: dir + "/stack.xml"))
}

// MARK: - Banner

func drawBanner(icon iconPath: String, to path: String) {
    let w: CGFloat = 1280, h: CGFloat = 640
    let ctx = canvas(Int(w), Int(h))
    ctx.drawRadialGradient(gradient([(0, color(0x7A5A43)), (1, color(0x3A2A20))]), startCenter: CGPoint(x: 360, y: 300),
                           startRadius: 0, endCenter: CGPoint(x: 360, y: 300), endRadius: 1100, options: [.drawsAfterEndLocation])
    // Brush strokes in the icon's colors.
    ctx.setLineCap(.round)
    for (i, c) in [0xE84C3D, 0xF9C733, 0x3485DB, 0x4DB04F].enumerated() {
        let y = 470 + CGFloat(i) * 38
        ctx.move(to: CGPoint(x: -40, y: y + 30))
        ctx.addCurve(to: CGPoint(x: w + 40, y: y - 40), control1: CGPoint(x: 380, y: y - 70), control2: CGPoint(x: 820, y: y + 80))
        ctx.setStrokeColor(color(UInt32(c), 0.75))
        ctx.setLineWidth(22)
        ctx.strokePath()
    }
    // Icon (its picture already has a margin and a shadow).
    if let img = NSImage(contentsOfFile: iconPath)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        ctx.saveGState()
        ctx.translateBy(x: 70, y: 70 + 400)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: 400, height: 400))
        ctx.restoreGState()
    }
    // Text, drawn through AppKit in a flipped context.
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
    }
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 12
    shadow.shadowOffset = NSSize(width: 0, height: 3)
    let x: CGFloat = 500
    NSAttributedString(string: "Brushwood", attributes: [.font: rounded(128, .bold), .foregroundColor: NSColor.white,
                                                          .shadow: shadow]).draw(at: NSPoint(x: x - 6, y: 112))
    let tagline = NSMutableParagraphStyle()
    tagline.lineSpacing = 4
    NSAttributedString(string: "A free, open-source image editor\nfor macOS that works like Paint.NET",
                       attributes: [.font: rounded(40, .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.92),
                                    .paragraphStyle: tagline, .shadow: shadow])
        .draw(in: NSRect(x: x, y: 278, width: w - x - 40, height: 120))
    NSGraphicsContext.restoreGraphicsState()
    writePNG(ctx.makeImage()!, to: path)
}

// MARK: - Window captures

struct WindowInfo {
    let id: CGWindowID
    let bounds: CGRect // screen points, origin at the top left
}

/// On-screen windows matching the filter, front to back.
func windows(_ match: ([String: Any]) -> Bool) -> [WindowInfo] {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    return list.compactMap { info in
        guard match(info), let n = info[kCGWindowNumber as String] as? Int,
              let b = info[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: b), rect.width > 40, rect.height > 40,
              (info[kCGWindowLayer as String] as? Int ?? 0) < 100, (info[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { return nil }
        return WindowInfo(id: CGWindowID(n), bounds: rect)
    }
}

/// Captures each window on its own (`screencapture` keeps rounded corners transparent) and composites them with
/// shadows on a transparent background, at most `maxWidth` pixels wide. A window's capture includes its child
/// windows (Brushwood's floating windows); capturing a child returns the whole group, so those are skipped.
func capture(_ list: [WindowInfo], to path: String, maxWidth: CGFloat) {
    let tmp = NSTemporaryDirectory()
    let scale = NSScreen.main?.backingScaleFactor ?? 2
    var shots: [(WindowInfo, CGImage)] = []
    for win in list.reversed() {
        let file = tmp + "brushwood-window-\(win.id).png"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-o", "-l\(win.id)", "-t", "png", file]
        try? p.run()
        p.waitUntilExit()
        guard let img = NSImage(contentsOfFile: file)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            fail("could not capture window \(win.id) (does the terminal have Screen Recording permission?)")
        }
        try? FileManager.default.removeItem(atPath: file)
        if abs(CGFloat(img.width) - win.bounds.width * scale) <= 2 { shots.append((win, img)) }
    }
    guard !shots.isEmpty else { fail("no window to capture") }
    let union = shots.map(\.0.bounds).reduce(shots[0].0.bounds) { $0.union($1) }
    let area = CGRect(x: union.minX - 50, y: union.minY - 34, width: union.width + 100, height: union.height + 100)
    let k = min(maxWidth / area.width, CGFloat(shots[0].1.width) / shots[0].0.bounds.width)
    let ctx = canvas(Int((area.width * k).rounded()), Int((area.height * k).rounded()))
    for (i, (win, img)) in shots.enumerated() {
        let main = i == 0
        let r = CGRect(x: (win.bounds.minX - area.minX) * k, y: (win.bounds.minY - area.minY) * k,
                       width: win.bounds.width * k, height: win.bounds.height * k)
        ctx.saveGState()
        // Shadow offsets ignore the flip: a negative height casts the shadow downward.
        ctx.setShadow(offset: CGSize(width: 0, height: -(main ? 18 : 8) * k), blur: (main ? 44 : 22) * k,
                      color: color(0x000000, main ? 0.42 : 0.32))
        ctx.translateBy(x: r.minX, y: r.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(img, in: CGRect(origin: .zero, size: r.size))
        ctx.restoreGState()
    }
    writePNG(ctx.makeImage()!, to: path)
}

// MARK: - Main

switch args.count > 1 ? args[1] : "" {
case "art" where args.count == 3:
    drawArt(to: args[2])
case "banner" where args.count == 4:
    drawBanner(icon: args[2], to: args[3])
case "frame" where args.count == 4:
    guard let screen = NSScreen.main, let w = Double(args[2]), let h = Double(args[3]) else { fail("no screen") }
    let v = screen.visibleFrame
    let f = NSRect(x: (v.midX - w / 2).rounded(), y: (v.midY - h / 2).rounded(), width: w, height: h)
    print("\(Int(f.minX)) \(Int(f.minY)) \(Int(w)) \(Int(h)) \(Int(v.minX)) \(Int(v.minY)) \(Int(v.width)) \(Int(v.height))")
case "capture" where args.count == 5:
    guard let pid = Int(args[2]), let maxWidth = Double(args[4]) else { fail("bad arguments") }
    capture(windows { ($0[kCGWindowOwnerPID as String] as? Int) == pid }, to: args[3], maxWidth: maxWidth)
case "capture-finder" where args.count == 5:
    guard let maxWidth = Double(args[4]) else { fail("bad arguments") }
    let found = windows { ($0[kCGWindowOwnerName as String] as? String) == "Finder" && ($0[kCGWindowName as String] as? String) == args[2] }
    capture(Array(found.prefix(1)), to: args[3], maxWidth: maxWidth)
default:
    fail("usage: readme-images art <dir> | banner <icon.png> <out.png> | frame <w> <h> | capture <pid> <out.png> <max-px> | "
        + "capture-finder <title> <out.png> <max-px>")
}
