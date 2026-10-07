import AppKit
import BrushwoodCore

/// Paint Bucket. Like Paint.NET 4+, the fill stays live after clicking: changing tolerance, colors, fill style
/// or dragging the origin handle re-renders it until it is committed.
final class PaintBucketTool: Tool {
    private var session: PixelEditSession?
    private var seed: CGPoint?
    private var button: ToolEvent.Button = .left
    private var global = false
    private var draggingSeed = false
    private var sampleImage: Surface?
    private var clip: MaskSurface?

    override var hasPendingEdits: Bool { session != nil }

    override func mouseDown(_ e: ToolEvent) {
        if let seed, session != nil, canvas.hitHandle(e.viewPoint, seed) {
            draggingSeed = true
            return
        }
        commit()
        guard doc.bounds.contains(x: e.intPoint.x, y: e.intPoint.y) else { return }
        session = PixelEditSession(layer: doc.activeLayer)
        sampleImage = settings.floodSampling == .image ? doc.flattened() : nil
        clip = selectionClip
        seed = e.point
        button = e.button
        global = e.shift
        renderFill()
    }

    override func mouseDragged(_ e: ToolEvent) {
        guard draggingSeed else { return }
        let p = CGPoint(x: clampDouble(e.point.x, 0, Double(doc.width) - 0.5), y: clampDouble(e.point.y, 0, Double(doc.height) - 0.5))
        seed = p
        renderFill()
    }

    override func mouseUp(_ e: ToolEvent) {
        draggingSeed = false
    }

    private func renderFill() {
        guard let session, let seed else { return }
        let previous = session.dirty
        session.restore(previous)
        let sample = sampleImage ?? session.original
        let mode: FloodMode = global ? .global : settings.floodMode
        let mask = FloodFill.fillMask(surface: sample, seed: IntPoint(x: Int(seed.x), y: Int(seed.y)),
                                      tolerance: settings.tolerance, mode: mode, limit: clip)
        if let bounds = mask.nonZeroBounds() {
            Compositor.apply(style: settings.fillStyle, foreground: color(for: button), background: otherColor(for: button),
                             mask: mask, rect: bounds, src: session.original, dst: session.layer.surface,
                             mode: settings.blendMode, clip: clip)
            session.touch(bounds)
            doc.invalidate(previous.union(bounds))
        } else {
            doc.invalidate(previous)
        }
        canvas.needsDisplay = true
    }

    override func settingsChanged() { if session != nil { renderFill() } }
    override func colorsChanged() { if session != nil { renderFill() } }

    override func commit() {
        guard let session else { return }
        session.commit(doc, name: L("Paint Bucket"), icon: kind.icon)
        self.session = nil
        seed = nil
        sampleImage = nil
        canvas.needsDisplay = true
    }

    override func cancel() {
        session?.cancel(doc)
        session = nil
        seed = nil
        canvas.needsDisplay = true
    }

    override func drawOverlay(_ ctx: CGContext) {
        if let seed, session != nil { canvas.drawHandle(ctx, at: seed, round: true) }
    }

    override func cursor(atView p: CGPoint) -> NSCursor {
        if let seed, session != nil, canvas.hitHandle(p, seed) { return .openHand }
        return super.cursor(atView: p)
    }
}

/// Gradient tool with editable start/end handles.
final class GradientTool: Tool {
    private enum Drag { case none, creating, start, end, move }

    private var session: PixelEditSession?
    private var start: CGPoint = .zero
    private var end: CGPoint = .zero
    private var button: ToolEvent.Button = .left
    private var drag: Drag = .none
    private var dragOrigin: CGPoint = .zero
    private var clip: MaskSurface?

    override var hasPendingEdits: Bool { session != nil }

    override func mouseDown(_ e: ToolEvent) {
        if session != nil {
            if canvas.hitHandle(e.viewPoint, start) { drag = .start; return }
            if canvas.hitHandle(e.viewPoint, end) { drag = .end; return }
        }
        commit()
        session = PixelEditSession(layer: doc.activeLayer)
        clip = selectionClip
        button = e.button
        start = e.point
        end = e.point
        drag = .creating
    }

    override func mouseDragged(_ e: ToolEvent) {
        guard session != nil else { return }
        var p = e.point
        let anchor = drag == .start ? end : start
        if e.shift {
            // Constrain angle to 15° steps.
            let dx = p.x - anchor.x, dy = p.y - anchor.y
            let len = hypot(dx, dy)
            let a = (atan2(dy, dx) / (.pi / 12)).rounded() * (.pi / 12)
            p = CGPoint(x: anchor.x + cos(a) * len, y: anchor.y + sin(a) * len)
        }
        switch drag {
        case .creating, .end: end = p
        case .start: start = p
        default: return
        }
        render()
    }

    override func mouseUp(_ e: ToolEvent) {
        if drag == .creating && start == end {
            session = nil
        }
        drag = .none
    }

    override func settingsChanged() { if session != nil && start != end { render() } }
    override func colorsChanged() { if session != nil && start != end { render() } }

    private static func gradientValue(_ px: Double, _ py: Double, sx: Double, sy: Double, dx: Double, dy: Double,
                                      len2: Double, len: Double, baseAngle: Double, type: GradientType,
                                      repeatMode: GradientRepeat) -> Double {
        let vx = px - sx, vy = py - sy
        var t: Double
        switch type {
        case .linear:
            t = (vx * dx + vy * dy) / len2
        case .linearReflected:
            t = abs((vx * dx + vy * dy) / len2)
        case .linearDiamond:
            let u = (vx * dx + vy * dy) / len2, v = (vx * -dy + vy * dx) / len2
            t = abs(u) + abs(v)
        case .radial:
            t = (vx * vx + vy * vy).squareRoot() / len
        case .conical:
            var a = atan2(vy, vx) - baseAngle
            while a > .pi { a -= 2 * .pi }
            while a < -.pi { a += 2 * .pi }
            t = abs(a) / .pi
        case .spiralClockwise, .spiralCounterclockwise:
            var a = atan2(vy, vx) - baseAngle
            if type == .spiralCounterclockwise { a = -a }
            let r = (vx * vx + vy * vy).squareRoot() / len
            t = r + a / (2 * .pi)
            t -= floor(t)
            return t
        }
        switch repeatMode {
        case .none: return min(1, max(0, t))
        case .sawtooth: return t - floor(t)
        case .triangle:
            let f = t - 2 * floor(t / 2)
            return f > 1 ? 2 - f : f
        }
    }

    private func render() {
        guard let session, start != end else { return }
        let layer = session.layer.surface, src = session.original
        let rect = doc.selectionBoundsOrCanvas
        let sx = Double(start.x), sy = Double(start.y)
        let dx = Double(end.x - start.x), dy = Double(end.y - start.y)
        let len2 = dx * dx + dy * dy, len = len2.squareRoot()
        let baseAngle = atan2(dy, dx)
        var c0 = env.primaryColor, c1 = env.secondaryColor
        if button == .right { swap(&c0, &c1) }
        let transparency = settings.gradientTransparencyMode
        let mode = settings.blendMode
        let clip = self.clip
        let type = settings.gradientType, repeatMode = settings.gradientRepeat
        // 256-entry color ramp.
        let ramp = (0...255).map { ColorBgra.lerp(c0, c1, Double($0) / 255) }
        let a0 = Double(c0.a), a1 = 255 - Double(c1.a)
        DispatchQueue.concurrentPerform(iterations: rect.height) { i in
            let y = rect.top + i
            let d = layer.row(y), s = src.row(y)
            let m = clip?.row(y)
            let py = Double(y) + 0.5
            for x in rect.left..<rect.right {
                let cov = Int(m?[x] ?? 255)
                if cov == 0 { d[x] = s[x]; continue }
                let t = GradientTool.gradientValue(Double(x) + 0.5, py, sx: sx, sy: sy, dx: dx, dy: dy, len2: len2, len: len,
                                                   baseAngle: baseAngle, type: type, repeatMode: repeatMode)
                if transparency {
                    let f = (a0 + (a1 - a0) * t) / 255
                    let o = s[x]
                    let na = clampToByte(Double(o.a) * f)
                    d[x] = Blender.lerpTo(o, o.withAlpha(na), coverage: cov)
                } else {
                    d[x] = Blender.blend(mode, s[x], ramp[Int(t * 255 + 0.5)], opacity: cov)
                }
            }
        }
        session.touch(rect)
        doc.invalidate(rect)
        canvas.needsDisplay = true
    }

    override func commit() {
        guard let session else { return }
        session.commit(doc, name: L("Gradient"), icon: kind.icon)
        self.session = nil
        canvas.needsDisplay = true
    }

    override func cancel() {
        session?.cancel(doc)
        session = nil
        canvas.needsDisplay = true
    }

    override func drawOverlay(_ ctx: CGContext) {
        guard session != nil, start != end else { return }
        let a = canvas.toView(start), b = canvas.toView(end)
        ctx.saveGState()
        ctx.setLineWidth(1)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.move(to: a); ctx.addLine(to: b); ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [4, 4])
        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.move(to: a); ctx.addLine(to: b); ctx.strokePath()
        ctx.restoreGState()
        canvas.drawHandle(ctx, at: start, round: true)
        canvas.drawHandle(ctx, at: end, round: true)
    }

    override func cursor(atView p: CGPoint) -> NSCursor {
        if session != nil && (canvas.hitHandle(p, start) || canvas.hitHandle(p, end)) { return .openHand }
        return super.cursor(atView: p)
    }
}
