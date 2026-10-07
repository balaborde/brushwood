import AppKit
import BrushwoodCore

/// Freehand stroke tools. Stroke coverage accumulates in a mask (max), and pixels are re-composited from the
/// layer's original state so semi-transparent strokes don't build up — the same look as Paint.NET.
class StrokeTool: Tool {
    var session: PixelEditSession?
    var mask: MaskSurface?
    var clip: MaskSurface?
    var lastPoint: CGPoint?
    var button: ToolEvent.Button = .left

    override var showsBrushOutline: Bool { true }

    var historyName: String { kind.name }

    /// Return false to refuse starting a stroke.
    func beginStroke(_ e: ToolEvent) -> Bool { true }

    override func mouseDown(_ e: ToolEvent) {
        guard session == nil, beginStroke(e) else { return }
        button = e.button
        session = PixelEditSession(layer: doc.activeLayer)
        mask = MaskSurface(width: doc.width, height: doc.height)
        clip = selectionClip
        lastPoint = e.point
        stroke(from: e.point, to: e.point)
    }

    override func mouseDragged(_ e: ToolEvent) {
        guard session != nil, let last = lastPoint else { return }
        var p = e.point
        if e.shift {
            // Shift constrains to horizontal/vertical from the stroke start.
            if abs(p.x - last.x) > abs(p.y - last.y) { p.y = last.y } else { p.x = last.x }
        }
        stroke(from: last, to: p)
        lastPoint = p
    }

    override func mouseUp(_ e: ToolEvent) {
        guard let session else { return }
        session.commit(doc, name: historyName, icon: kind.icon)
        self.session = nil
        mask = nil
        clip = nil
        lastPoint = nil
    }

    override func cancel() {
        session?.cancel(doc)
        session = nil
    }

    override func deactivate() {
        if let session {
            session.commit(doc, name: historyName, icon: kind.icon)
            self.session = nil
        }
    }

    func stroke(from a: CGPoint, to b: CGPoint) {
        guard let mask, let session else { return }
        let dirty = rasterize(from: a, to: b, into: mask)
        if dirty.isEmpty { return }
        render(dirty, session: session, mask: mask)
        session.touch(dirty)
        doc.invalidate(dirty)
    }

    /// Adds the segment's coverage to the mask; returns the changed area.
    func rasterize(from a: CGPoint, to b: CGPoint, into mask: MaskSurface) -> IntRect {
        StrokeTool.capsule(mask: mask, a: a, b: b, width: Double(settings.brushWidth),
                           hardness: settings.hardness / 100, antialias: settings.antialiasing)
    }

    func render(_ rect: IntRect, session: PixelEditSession, mask: MaskSurface) {
        Compositor.apply(color: color(for: button), mask: mask, rect: rect, src: session.original, dst: session.layer.surface,
                         mode: settings.blendMode, clip: clip)
    }

    /// Round-capped thick segment with optional soft edge. Coverage is max-accumulated.
    static func capsule(mask: MaskSurface, a: CGPoint, b: CGPoint, width: Double, hardness: Double, antialias: Bool) -> IntRect {
        let r = max(0.5, width / 2)
        let pad = r + 2
        let x0 = max(0, Int(floor(min(a.x, b.x) - pad))), x1 = min(mask.width, Int(ceil(max(a.x, b.x) + pad)))
        let y0 = max(0, Int(floor(min(a.y, b.y) - pad))), y1 = min(mask.height, Int(ceil(max(a.y, b.y) + pad)))
        if x1 <= x0 || y1 <= y0 { return .zero }
        let ax = Double(a.x), ay = Double(a.y)
        let dx = Double(b.x) - ax, dy = Double(b.y) - ay
        let len2 = dx * dx + dy * dy
        let inner = r * clampDouble(hardness, 0, 1)
        let span = max(1, (r + 0.5) - (inner - 0.5))
        let aliasedRadius = width <= 1 ? 0.5 : r
        for y in y0..<y1 {
            let m = mask.row(y)
            let py = Double(y) + 0.5
            for x in x0..<x1 {
                let px = Double(x) + 0.5
                var t = len2 > 0 ? ((px - ax) * dx + (py - ay) * dy) / len2 : 0
                t = t < 0 ? 0 : (t > 1 ? 1 : t)
                let ex = px - (ax + t * dx), ey = py - (ay + t * dy)
                let d = (ex * ex + ey * ey).squareRoot()
                var cov: Double
                if antialias {
                    if d <= inner - 0.5 {
                        cov = 1
                    } else {
                        cov = (r + 0.5 - d) / span
                        if cov <= 0 { continue }
                        if cov > 1 { cov = 1 }
                        cov = cov * cov * (3 - 2 * cov)
                    }
                } else {
                    if d > aliasedRadius { continue }
                    cov = 1
                }
                let v = UInt8(cov * 255 + 0.5)
                if v > m[x] { m[x] = v }
            }
        }
        return IntRect(left: x0, top: y0, right: x1, bottom: y1)
    }
}

final class PaintbrushTool: StrokeTool {}

final class EraserTool: StrokeTool {
    override func render(_ rect: IntRect, session: PixelEditSession, mask: MaskSurface) {
        let src = session.original, dst = session.layer.surface
        let r = rect.intersection(dst.bounds)
        for y in r.top..<r.bottom {
            let m = mask.row(y), s = src.row(y), d = dst.row(y)
            let c = clip?.row(y)
            for x in r.left..<r.right {
                var cov = Int(m[x])
                if let c { cov = mul255(cov, Int(c[x])) }
                d[x] = cov == 0 ? s[x] : Blender.lerpTo(s[x], s[x].withAlpha(0), coverage: cov)
            }
        }
    }
}

final class PencilTool: StrokeTool {
    override var showsBrushOutline: Bool { false }

    override func rasterize(from a: CGPoint, to b: CGPoint, into mask: MaskSurface) -> IntRect {
        // Bresenham one-pixel line, aliased.
        var x0 = Int(floor(a.x)), y0 = Int(floor(a.y))
        let x1 = Int(floor(b.x)), y1 = Int(floor(b.y))
        let dx = abs(x1 - x0), sx = x0 < x1 ? 1 : -1
        let dy = -abs(y1 - y0), sy = y0 < y1 ? 1 : -1
        var err = dx + dy
        var rect = IntRect.zero
        while true {
            if x0 >= 0 && y0 >= 0 && x0 < mask.width && y0 < mask.height {
                mask[x0, y0] = 255
                rect = rect.union(IntRect(x: x0, y: y0, width: 1, height: 1))
            }
            if x0 == x1 && y0 == y1 { break }
            let e2 = 2 * err
            if e2 >= dy { err += dy; x0 += sx }
            if e2 <= dx { err += dx; y0 += sy }
        }
        return rect
    }
}

final class CloneStampTool: StrokeTool {
    private var source: CGPoint?
    private var offset: CGPoint = .zero
    private var sourceLayer: BitmapLayer?

    override func beginStroke(_ e: ToolEvent) -> Bool {
        if e.command {
            source = e.point
            sourceLayer = doc.activeLayer
            setStatus(LF("Clone source set at %d, %d", Int(e.point.x), Int(e.point.y)))
            canvas.needsDisplay = true
            return false
        }
        guard let source else {
            setStatus(L("⌘-click to set the clone origin first."))
            NSSound.beep()
            return false
        }
        offset = CGPoint(x: e.point.x - source.x, y: e.point.y - source.y)
        return true
    }

    override func render(_ rect: IntRect, session: PixelEditSession, mask: MaskSurface) {
        let src = session.original, dst = session.layer.surface
        // Cloning from another layer reads that layer's current pixels.
        let from = (sourceLayer === session.layer || sourceLayer == nil) ? src : sourceLayer!.surface
        let ox = Int(offset.x.rounded()), oy = Int(offset.y.rounded())
        let r = rect.intersection(dst.bounds)
        for y in r.top..<r.bottom {
            let m = mask.row(y), s = src.row(y), d = dst.row(y)
            let c = clip?.row(y)
            let sy = y - oy
            for x in r.left..<r.right {
                var cov = Int(m[x])
                if let c { cov = mul255(cov, Int(c[x])) }
                let sx = x - ox
                if cov == 0 || sx < 0 || sy < 0 || sx >= from.width || sy >= from.height { d[x] = s[x]; continue }
                d[x] = Blender.blend(settings.blendMode, s[x], from[sx, sy], opacity: cov)
            }
        }
    }

    override func mouseMoved(_ e: ToolEvent) {
        canvas.needsDisplay = source != nil
    }

    override func drawOverlay(_ ctx: CGContext) {
        guard let source else { return }
        var p = source
        if session != nil, let m = canvas.mouseImagePoint {
            p = CGPoint(x: m.x - offset.x, y: m.y - offset.y)
        }
        let c = canvas.toView(p)
        ctx.saveGState()
        ctx.setLineWidth(3)
        ctx.setStrokeColor(NSColor.white.cgColor)
        for pass in 0..<2 {
            ctx.move(to: CGPoint(x: c.x - 8, y: c.y)); ctx.addLine(to: CGPoint(x: c.x + 8, y: c.y))
            ctx.move(to: CGPoint(x: c.x, y: c.y - 8)); ctx.addLine(to: CGPoint(x: c.x, y: c.y + 8))
            ctx.strokePath()
            if pass == 0 {
                ctx.setLineWidth(1)
                ctx.setStrokeColor(NSColor.black.cgColor)
            }
        }
        let w = settings.brushWidth * canvas.zoom
        ctx.strokeEllipse(in: CGRect(x: c.x - w / 2, y: c.y - w / 2, width: w, height: w))
        ctx.restoreGState()
    }
}

final class RecolorTool: StrokeTool {
    override func render(_ rect: IntRect, session: PixelEditSession, mask: MaskSurface) {
        // Left button replaces the secondary color with the primary; right does the opposite.
        let from = otherColor(for: button), to = color(for: button)
        let tol = FloodFill.toleranceThreshold(settings.tolerance)
        let src = session.original, dst = session.layer.surface
        let r = rect.intersection(dst.bounds)
        for y in r.top..<r.bottom {
            let m = mask.row(y), s = src.row(y), d = dst.row(y)
            let c = clip?.row(y)
            for x in r.left..<r.right {
                var cov = Int(m[x])
                if let c { cov = mul255(cov, Int(c[x])) }
                let o = s[x]
                if cov == 0 || !FloodFill.colorsMatch(from, o, toleranceSquared4: tol) { d[x] = o; continue }
                // Keep the shading difference relative to the replaced color.
                let rc = ColorBgra(b: clampToByte(Int(to.b) + Int(o.b) - Int(from.b)),
                                   g: clampToByte(Int(to.g) + Int(o.g) - Int(from.g)),
                                   r: clampToByte(Int(to.r) + Int(o.r) - Int(from.r)), a: o.a)
                d[x] = Blender.lerpTo(o, rc, coverage: cov)
            }
        }
    }
}
