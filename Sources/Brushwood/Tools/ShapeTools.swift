import AppKit
import BrushwoodCore

/// The shape library of the Shapes tool.
enum ShapeKind: Int, CaseIterable {
    case rectangle, roundedRectangle, ellipse
    case triangle, rightTriangle, diamond, pentagon, hexagon, octagon
    case star4, star5, star6, star8, burst
    case arrowRight, arrowLeft, arrowUp, arrowDown, doubleArrow, chevron
    case calloutRectangle, calloutRoundedRectangle, calloutEllipse
    case heart, lightning, plus, cloud, moon, trapezoid, parallelogram, cylinder

    enum Category: Int, CaseIterable {
        case basic, polygons, stars, arrows, callouts, symbols

        var name: String {
            switch self {
            case .basic: return L("Basic")
            case .polygons: return L("Polygons")
            case .stars: return L("Stars")
            case .arrows: return L("Arrows")
            case .callouts: return L("Callouts")
            case .symbols: return L("Symbols")
            }
        }
    }

    var category: Category {
        switch self {
        case .rectangle, .roundedRectangle, .ellipse: return .basic
        case .triangle, .rightTriangle, .diamond, .pentagon, .hexagon, .octagon, .trapezoid, .parallelogram: return .polygons
        case .star4, .star5, .star6, .star8, .burst: return .stars
        case .arrowRight, .arrowLeft, .arrowUp, .arrowDown, .doubleArrow, .chevron: return .arrows
        case .calloutRectangle, .calloutRoundedRectangle, .calloutEllipse: return .callouts
        case .heart, .lightning, .plus, .cloud, .moon, .cylinder: return .symbols
        }
    }

    var name: String {
        switch self {
        case .rectangle: return L("Rectangle")
        case .roundedRectangle: return L("Rounded Rectangle")
        case .ellipse: return L("Ellipse")
        case .triangle: return L("Triangle")
        case .rightTriangle: return L("Right Triangle")
        case .diamond: return L("Diamond")
        case .pentagon: return L("Pentagon")
        case .hexagon: return L("Hexagon")
        case .octagon: return L("Octagon")
        case .star4: return L("4 Point Star")
        case .star5: return L("5 Point Star")
        case .star6: return L("6 Point Star")
        case .star8: return L("8 Point Star")
        case .burst: return L("Explosion")
        case .arrowRight: return L("Right Arrow")
        case .arrowLeft: return L("Left Arrow")
        case .arrowUp: return L("Up Arrow")
        case .arrowDown: return L("Down Arrow")
        case .doubleArrow: return L("Double Arrow")
        case .chevron: return L("Chevron")
        case .calloutRectangle: return L("Rectangle Callout")
        case .calloutRoundedRectangle: return L("Rounded Rectangle Callout")
        case .calloutEllipse: return L("Ellipse Callout")
        case .heart: return L("Heart")
        case .lightning: return L("Lightning")
        case .plus: return L("Plus")
        case .cloud: return L("Cloud")
        case .moon: return L("Moon")
        case .trapezoid: return L("Trapezoid")
        case .parallelogram: return L("Parallelogram")
        case .cylinder: return L("Cylinder")
        }
    }

    private func polygon(_ pts: [(CGFloat, CGFloat)], _ r: CGRect) -> CGPath {
        let p = CGMutablePath()
        p.addLines(between: pts.map { CGPoint(x: r.minX + $0.0 * r.width, y: r.minY + $0.1 * r.height) })
        p.closeSubpath()
        return p
    }

    private func regular(_ n: Int, _ r: CGRect, rotation: CGFloat = -.pi / 2) -> CGPath {
        polygon((0..<n).map { i in
            let a = rotation + CGFloat(i) * 2 * .pi / CGFloat(n)
            return (0.5 + 0.5 * cos(a), 0.5 + 0.5 * sin(a))
        }, r)
    }

    private func star(_ n: Int, inner: CGFloat, _ r: CGRect) -> CGPath {
        polygon((0..<(2 * n)).map { i in
            let a = -.pi / 2 + CGFloat(i) * .pi / CGFloat(n)
            let k: CGFloat = i % 2 == 0 ? 0.5 : 0.5 * inner
            return (0.5 + k * cos(a), 0.5 + k * sin(a))
        }, r)
    }

    /// Shape outline inside `r` (image space, y down).
    func path(in r: CGRect, cornerRadius: CGFloat = 20) -> CGPath {
        switch self {
        case .rectangle: return CGPath(rect: r, transform: nil)
        case .roundedRectangle:
            let rad = min(max(0, cornerRadius), min(r.width, r.height) / 2)
            return CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil)
        case .ellipse: return CGPath(ellipseIn: r, transform: nil)
        case .triangle: return polygon([(0.5, 0), (1, 1), (0, 1)], r)
        case .rightTriangle: return polygon([(0, 0), (1, 1), (0, 1)], r)
        case .diamond: return polygon([(0.5, 0), (1, 0.5), (0.5, 1), (0, 0.5)], r)
        case .pentagon: return regular(5, r)
        case .hexagon: return regular(6, r, rotation: 0)
        case .octagon: return regular(8, r, rotation: .pi / 8)
        case .star4: return star(4, inner: 0.4, r)
        case .star5: return star(5, inner: 0.45, r)
        case .star6: return star(6, inner: 0.55, r)
        case .star8: return star(8, inner: 0.6, r)
        case .burst:
            return polygon((0..<24).map { i in
                let a = CGFloat(i) * .pi / 12
                let k: CGFloat = i % 2 == 0 ? 0.5 : (i % 4 == 1 ? 0.3 : 0.36)
                return (0.5 + k * cos(a), 0.5 + k * sin(a))
            }, r)
        case .arrowRight: return polygon([(0, 0.3), (0.6, 0.3), (0.6, 0), (1, 0.5), (0.6, 1), (0.6, 0.7), (0, 0.7)], r)
        case .arrowLeft: return polygon([(1, 0.3), (0.4, 0.3), (0.4, 0), (0, 0.5), (0.4, 1), (0.4, 0.7), (1, 0.7)], r)
        case .arrowUp: return polygon([(0.3, 1), (0.3, 0.4), (0, 0.4), (0.5, 0), (1, 0.4), (0.7, 0.4), (0.7, 1)], r)
        case .arrowDown: return polygon([(0.3, 0), (0.3, 0.6), (0, 0.6), (0.5, 1), (1, 0.6), (0.7, 0.6), (0.7, 0)], r)
        case .doubleArrow:
            return polygon([(0, 0.5), (0.25, 0), (0.25, 0.3), (0.75, 0.3), (0.75, 0), (1, 0.5), (0.75, 1), (0.75, 0.7),
                            (0.25, 0.7), (0.25, 1)], r)
        case .chevron: return polygon([(0, 0), (0.7, 0), (1, 0.5), (0.7, 1), (0, 1), (0.3, 0.5)], r)
        case .trapezoid: return polygon([(0.2, 0), (0.8, 0), (1, 1), (0, 1)], r)
        case .parallelogram: return polygon([(0.25, 0), (1, 0), (0.75, 1), (0, 1)], r)
        case .plus: return polygon([(0.35, 0), (0.65, 0), (0.65, 0.35), (1, 0.35), (1, 0.65), (0.65, 0.65), (0.65, 1),
                                    (0.35, 1), (0.35, 0.65), (0, 0.65), (0, 0.35), (0.35, 0.35)], r)
        case .lightning:
            return polygon([(0.55, 0), (0.15, 0.55), (0.45, 0.55), (0.3, 1), (0.85, 0.4), (0.55, 0.4), (0.75, 0)], r)
        case .calloutRectangle, .calloutRoundedRectangle, .calloutEllipse:
            let body = CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height * 0.75)
            let p = CGMutablePath()
            switch self {
            case .calloutRectangle: p.addRect(body)
            case .calloutRoundedRectangle:
                let rad = min(max(0, cornerRadius), min(body.width, body.height) / 2)
                p.addRoundedRect(in: body, cornerWidth: rad, cornerHeight: rad)
            default: p.addEllipse(in: body)
            }
            let tail = polygon([(0.2, 0.7), (0.15, 1), (0.42, 0.7)], r)
            return p.union(tail)
        case .heart:
            let p = CGMutablePath()
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
            p.move(to: pt(0.5, 1))
            p.addCurve(to: pt(0, 0.3), control1: pt(0.2, 0.8), control2: pt(0, 0.6))
            p.addCurve(to: pt(0.5, 0.2), control1: pt(0, 0), control2: pt(0.4, -0.05))
            p.addCurve(to: pt(1, 0.3), control1: pt(0.6, -0.05), control2: pt(1, 0))
            p.addCurve(to: pt(0.5, 1), control1: pt(1, 0.6), control2: pt(0.8, 0.8))
            p.closeSubpath()
            return p
        case .cloud:
            let p = CGMutablePath()
            let blobs: [(CGFloat, CGFloat, CGFloat)] = [(0.25, 0.55, 0.22), (0.45, 0.38, 0.25), (0.68, 0.42, 0.22),
                                                         (0.78, 0.62, 0.18), (0.5, 0.65, 0.25), (0.2, 0.7, 0.15)]
            var result: CGPath = CGMutablePath()
            for (cx, cy, rr) in blobs {
                let e = CGPath(ellipseIn: CGRect(x: r.minX + (cx - rr) * r.width, y: r.minY + (cy - rr) * r.height,
                                                 width: 2 * rr * r.width, height: 2 * rr * r.height), transform: nil)
                result = result.isEmpty ? e : result.union(e)
            }
            p.addPath(result)
            return p
        case .moon:
            let outer = CGPath(ellipseIn: r, transform: nil)
            let inner = CGPath(ellipseIn: CGRect(x: r.minX + r.width * 0.3, y: r.minY - r.height * 0.05,
                                                 width: r.width * 0.9, height: r.height * 0.9), transform: nil)
            return outer.subtracting(inner)
        case .cylinder:
            let eh = r.height * 0.15
            let top = CGPath(ellipseIn: CGRect(x: r.minX, y: r.minY, width: r.width, height: 2 * eh), transform: nil)
            let bottom = CGPath(ellipseIn: CGRect(x: r.minX, y: r.maxY - 2 * eh, width: r.width, height: 2 * eh), transform: nil)
            let body = CGPath(rect: CGRect(x: r.minX, y: r.minY + eh, width: r.width, height: max(0, r.height - 2 * eh)),
                              transform: nil)
            return body.union(top).union(bottom)
        }
    }
}

/// Shared rendering of stroked/filled vector content into the active layer.
final class VectorRenderer {
    let session: PixelEditSession
    private let fillMask: MaskSurface
    private let strokeMask: MaskSurface
    private var lastDirty = IntRect.zero
    let clip: MaskSurface?

    init(layer: BitmapLayer, clip: MaskSurface?) {
        session = PixelEditSession(layer: layer)
        fillMask = MaskSurface(width: layer.surface.width, height: layer.surface.height)
        strokeMask = MaskSurface(width: layer.surface.width, height: layer.surface.height)
        self.clip = clip
    }

    /// Re-renders: restores the previous area, then fills and/or strokes `path`.
    func render(doc: Document, fill: CGPath?, fillColor: ColorBgra, fillStyle: FillStyle = .solid, fillBackground: ColorBgra = .transparent,
                stroke: CGPath?, strokeColor: ColorBgra, width: CGFloat, dash: [CGFloat], cap: CGLineCap, join: CGLineJoin = .miter,
                strokeFill: CGPath? = nil, antialias: Bool, mode: BlendMode) {
        let layer = session.layer.surface
        var bounds = CGRect.null
        if let fill { bounds = bounds.union(fill.boundingBoxOfPath) }
        if let stroke { bounds = bounds.union(stroke.boundingBoxOfPath.insetBy(dx: -width * 2 - 2, dy: -width * 2 - 2)) }
        if let strokeFill { bounds = bounds.union(strokeFill.boundingBoxOfPath) }
        let newDirty = bounds.isNull ? IntRect.zero : IntRect(enclosing: bounds.insetBy(dx: -2, dy: -2)).intersection(layer.bounds)
        let dirty = lastDirty.union(newDirty).intersection(layer.bounds)
        session.restore(dirty)
        PathRasterizer.clear(fillMask, rect: dirty)
        PathRasterizer.clear(strokeMask, rect: dirty)
        if let fill, !newDirty.isEmpty {
            PathRasterizer.fill(fill, into: fillMask, antialias: antialias, rule: .evenOdd)
            Compositor.apply(style: fillStyle, foreground: fillColor, background: fillBackground, mask: fillMask, rect: newDirty,
                             src: session.original, dst: layer, mode: mode, clip: clip)
        }
        if (stroke != nil || strokeFill != nil), !newDirty.isEmpty {
            if let stroke {
                PathRasterizer.stroke(stroke, into: strokeMask, width: width, antialias: antialias, dash: dash, cap: cap, join: join)
            }
            if let strokeFill { PathRasterizer.fill(strokeFill, into: strokeMask, antialias: antialias) }
            Compositor.apply(color: strokeColor, mask: strokeMask, rect: newDirty, src: fill == nil ? session.original : layer,
                             dst: layer, mode: mode, clip: clip)
        }
        session.touch(dirty)
        lastDirty = newDirty
        doc.invalidate(dirty)
    }
}

final class ShapesTool: Tool {
    private enum Drag { case none, creating, handle(Int), move }

    private var renderer: VectorRenderer?
    private var rect = CGRect.zero
    private var start = CGPoint.zero
    private var dragStartRect = CGRect.zero
    private var drag: Drag = .none
    private var button: ToolEvent.Button = .left

    override var hasPendingEdits: Bool { renderer != nil }

    override func mouseDown(_ e: ToolEvent) {
        if renderer != nil {
            for (i, h) in handlePoints(rect).enumerated() where canvas.hitHandle(e.viewPoint, h) {
                drag = .handle(i)
                start = e.point
                dragStartRect = rect
                return
            }
            if rect.insetBy(dx: -2, dy: -2).contains(e.point) {
                drag = .move
                start = e.point
                dragStartRect = rect
                return
            }
            commit()
        }
        renderer = VectorRenderer(layer: doc.activeLayer, clip: selectionClip)
        button = e.button
        start = e.point
        rect = CGRect(origin: e.point, size: .zero)
        drag = .creating
    }

    override func mouseDragged(_ e: ToolEvent) {
        switch drag {
        case .none:
            return
        case .creating:
            var w = e.point.x - start.x, h = e.point.y - start.y
            if e.shift {
                let s = max(abs(w), abs(h))
                w = w < 0 ? -s : s
                h = h < 0 ? -s : s
            }
            rect = CGRect(corner: start, corner: CGPoint(x: start.x + w, y: start.y + h))
        case .move:
            rect = dragStartRect.offsetBy(dx: e.point.x - start.x, dy: e.point.y - start.y)
        case .handle(let i):
            let t = TransformGesture(kind: .scale(i), start: start, bounds: dragStartRect).transform(to: e.point, shift: e.shift)
            rect = dragStartRect.applying(t).standardized
        }
        render()
    }

    override func mouseUp(_ e: ToolEvent) {
        if case .creating = drag, rect.width < 1 && rect.height < 1 {
            renderer?.session.cancel(doc)
            renderer = nil
        }
        drag = .none
        canvas.needsDisplay = true
    }

    private func render() {
        guard let renderer, rect.width >= 1 || rect.height >= 1 else { return }
        let path = settings.shapeType.path(in: rect, cornerRadius: settings.cornerRadius)
        let c1 = color(for: button), c2 = otherColor(for: button)
        let width = settings.brushWidth
        let dash = settings.dashStyle.pattern(width: width)
        switch settings.shapeDrawType {
        case .outline:
            renderer.render(doc: doc, fill: nil, fillColor: c1, stroke: path, strokeColor: c1, width: width, dash: dash,
                            cap: .butt, antialias: settings.antialiasing, mode: settings.blendMode)
        case .filled:
            renderer.render(doc: doc, fill: path, fillColor: c1, fillStyle: settings.fillStyle, fillBackground: c2, stroke: nil,
                            strokeColor: c1, width: width, dash: dash, cap: .butt, antialias: settings.antialiasing,
                            mode: settings.blendMode)
        case .filledWithOutline:
            renderer.render(doc: doc, fill: path, fillColor: c2, fillStyle: settings.fillStyle, fillBackground: c1, stroke: path,
                            strokeColor: c1, width: width, dash: dash, cap: .butt, antialias: settings.antialiasing,
                            mode: settings.blendMode)
        }
        canvas.needsDisplay = true
    }

    override func settingsChanged() { if renderer != nil { render() } }
    override func colorsChanged() { if renderer != nil { render() } }

    override func commit() {
        guard let renderer else { return }
        renderer.session.commit(doc, name: settings.shapeType.name, icon: kind.icon)
        self.renderer = nil
        canvas.needsDisplay = true
    }

    override func cancel() {
        renderer?.session.cancel(doc)
        renderer = nil
        canvas.needsDisplay = true
    }

    override func drawOverlay(_ ctx: CGContext) {
        guard renderer != nil else { return }
        let r = canvas.toView(rect)
        ctx.saveGState()
        ctx.setStrokeColor(Theme.handleStroke.withAlphaComponent(0.6).cgColor)
        ctx.setLineDash(phase: 0, lengths: [3, 3])
        ctx.stroke(r)
        ctx.restoreGState()
        for h in handlePoints(rect) { canvas.drawHandle(ctx, at: h) }
    }

    override func cursor(atView p: CGPoint) -> NSCursor {
        if renderer != nil {
            if handlePoints(rect).contains(where: { canvas.hitHandle(p, $0) }) { return ToolCursors.resizeDiagonal }
            if rect.contains(canvas.toImage(p)) { return .openHand }
        }
        return super.cursor(atView: p)
    }
}

final class LineCurveTool: Tool {
    private var renderer: VectorRenderer?
    private var points: [CGPoint] = []
    private var dragIndex: Int?
    private var button: ToolEvent.Button = .left
    private var creating = false
    static let maxPoints = 6

    override var hasPendingEdits: Bool { renderer != nil }

    override func mouseDown(_ e: ToolEvent) {
        if renderer != nil {
            if let i = points.firstIndex(where: { canvas.hitHandle(e.viewPoint, $0) }) {
                dragIndex = i
                return
            }
            if points.count < LineCurveTool.maxPoints, let insert = insertionIndex(near: e.point) {
                points.insert(e.point, at: insert)
                dragIndex = insert
                render()
                return
            }
            commit()
        }
        renderer = VectorRenderer(layer: doc.activeLayer, clip: selectionClip)
        button = e.button
        points = [e.point, e.point]
        dragIndex = 1
        creating = true
    }

    /// Index to insert a new control point if `p` lies near the curve.
    private func insertionIndex(near p: CGPoint) -> Int? {
        let tolerance = max(settings.brushWidth / 2 + 3, 6 / canvas.zoom)
        let samples = curvePoints(points, steps: 24)
        for (k, s) in samples.enumerated() where s.0.distance(to: p) <= tolerance {
            _ = k
            return s.1 + 1
        }
        return nil
    }

    override func mouseDragged(_ e: ToolEvent) {
        guard let i = dragIndex else { return }
        var p = e.point
        if e.shift && points.count == 2 {
            let anchor = points[1 - i]
            let dx = p.x - anchor.x, dy = p.y - anchor.y
            let len = hypot(dx, dy)
            let a = (atan2(dy, dx) / (.pi / 12)).rounded() * (.pi / 12)
            p = CGPoint(x: anchor.x + cos(a) * len, y: anchor.y + sin(a) * len)
        }
        points[i] = p
        render()
    }

    override func mouseUp(_ e: ToolEvent) {
        if creating && points.count == 2 && points[0].distance(to: points[1]) < 0.5 {
            renderer?.session.cancel(doc)
            renderer = nil
        }
        creating = false
        dragIndex = nil
        canvas.needsDisplay = true
    }

    /// Catmull-Rom spline sampled into points, each tagged with its segment index.
    private func curvePoints(_ pts: [CGPoint], steps: Int) -> [(CGPoint, Int)] {
        if pts.count < 3 { return pts.enumerated().map { ($0.element, min($0.offset, max(0, pts.count - 2))) } }
        var out: [(CGPoint, Int)] = []
        for i in 0..<(pts.count - 1) {
            let p0 = pts[max(0, i - 1)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[min(pts.count - 1, i + 2)]
            for s in 0...steps {
                let t = CGFloat(s) / CGFloat(steps)
                let t2 = t * t, t3 = t2 * t
                let x = 0.5 * ((2 * p1.x) + (-p0.x + p2.x) * t + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2
                    + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3)
                let y = 0.5 * ((2 * p1.y) + (-p0.y + p2.y) * t + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2
                    + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)
                out.append((CGPoint(x: x, y: y), i))
            }
        }
        return out
    }

    private func curvePath() -> CGPath {
        let p = CGMutablePath()
        if points.count == 2 {
            p.move(to: points[0])
            p.addLine(to: points[1])
            return p
        }
        // Catmull-Rom → cubic Bézier segments.
        p.move(to: points[0])
        for i in 0..<(points.count - 1) {
            let p0 = points[max(0, i - 1)], p1 = points[i], p2 = points[i + 1], p3 = points[min(points.count - 1, i + 2)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            p.addCurve(to: p2, control1: c1, control2: c2)
        }
        return p
    }

    /// Arrow head polygon at `tip` pointing away from `from`.
    private func arrowHead(tip: CGPoint, from: CGPoint, width: CGFloat) -> CGPath {
        let a = atan2(tip.y - from.y, tip.x - from.x)
        let len = max(6, width * 3), half = max(4, width * 2)
        let base = CGPoint(x: tip.x - cos(a) * len, y: tip.y - sin(a) * len)
        let p = CGMutablePath()
        p.move(to: tip)
        p.addLine(to: CGPoint(x: base.x + sin(a) * half, y: base.y - cos(a) * half))
        p.addLine(to: CGPoint(x: base.x - sin(a) * half, y: base.y + cos(a) * half))
        p.closeSubpath()
        return p
    }

    private func render() {
        guard let renderer, points.count >= 2 else { return }
        let width = settings.brushWidth
        let path = curvePath()
        let samples = curvePoints(points, steps: 16).map(\.0)
        let extra = CGMutablePath()
        var caps: [(LineCap, CGPoint, CGPoint)] = []
        if samples.count >= 2 {
            caps.append((settings.startCap, samples[0], samples[min(2, samples.count - 1)]))
            caps.append((settings.endCap, samples[samples.count - 1], samples[max(0, samples.count - 3)]))
        }
        var openArrows = CGMutablePath()
        for (cap, tip, from) in caps where cap == .arrow || cap == .filledArrow {
            let head = arrowHead(tip: tip, from: from, width: width)
            if cap == .filledArrow {
                extra.addPath(head)
            } else {
                // Open arrow: two strokes from the tip.
                let a = atan2(tip.y - from.y, tip.x - from.x)
                let len = max(6, width * 3), half = max(4, width * 2)
                let base = CGPoint(x: tip.x - cos(a) * len, y: tip.y - sin(a) * len)
                openArrows.move(to: CGPoint(x: base.x + sin(a) * half, y: base.y - cos(a) * half))
                openArrows.addLine(to: tip)
                openArrows.addLine(to: CGPoint(x: base.x - sin(a) * half, y: base.y + cos(a) * half))
            }
        }
        let combined = CGMutablePath()
        combined.addPath(path)
        combined.addPath(openArrows)
        if openArrows.isEmpty { openArrows = CGMutablePath() }
        let cap: CGLineCap = (settings.startCap == .rounded || settings.endCap == .rounded) ? .round : .butt
        renderer.render(doc: doc, fill: nil, fillColor: .black, stroke: combined, strokeColor: color(for: button), width: width,
                        dash: settings.dashStyle.pattern(width: width), cap: cap, join: .round,
                        strokeFill: extra.isEmpty ? nil : extra, antialias: settings.antialiasing, mode: settings.blendMode)
        canvas.needsDisplay = true
    }

    override func settingsChanged() { if renderer != nil { render() } }
    override func colorsChanged() { if renderer != nil { render() } }

    override func commit() {
        guard let renderer else { return }
        renderer.session.commit(doc, name: points.count > 2 ? L("Curve") : L("Line"), icon: kind.icon)
        self.renderer = nil
        points = []
        canvas.needsDisplay = true
    }

    override func cancel() {
        renderer?.session.cancel(doc)
        renderer = nil
        points = []
        canvas.needsDisplay = true
    }

    override func drawOverlay(_ ctx: CGContext) {
        guard renderer != nil else { return }
        for p in points { canvas.drawHandle(ctx, at: p, round: true) }
    }

    override func cursor(atView p: CGPoint) -> NSCursor {
        if renderer != nil && points.contains(where: { canvas.hitHandle(p, $0) }) { return .openHand }
        return super.cursor(atView: p)
    }
}
