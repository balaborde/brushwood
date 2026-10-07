import AppKit
import BrushwoodCore

/// Resolves the combine mode from modifiers exactly like Paint.NET (Ctrl→⌘ union, Alt→⌥ exclude,
/// right button xor, Alt+right intersect), falling back to the toolbar setting.
func selectionCombineMode(for e: ToolEvent, default mode: SelectionCombineMode) -> SelectionCombineMode {
    if e.button == .right { return e.option ? .intersect : .xor }
    if e.command { return .union }
    if e.option { return .exclude }
    return mode
}

/// Eight resize handles around a rectangle: TL, T, TR, R, BR, B, BL, L.
func handlePoints(_ r: CGRect) -> [CGPoint] {
    [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
     CGPoint(x: r.maxX, y: r.midY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.midX, y: r.maxY),
     CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.minX, y: r.midY)]
}

/// Move / scale / rotate gesture math shared by the move tools.
struct TransformGesture {
    enum Kind: Equatable { case move, scale(Int), rotate }

    let kind: Kind
    let start: CGPoint
    let bounds: CGRect

    func transform(to p: CGPoint, shift: Bool) -> CGAffineTransform {
        switch kind {
        case .move:
            var dx = p.x - start.x, dy = p.y - start.y
            if shift { if abs(dx) > abs(dy) { dy = 0 } else { dx = 0 } }
            return CGAffineTransform(translationX: dx, y: dy)
        case .rotate:
            let c = bounds.center
            var a = atan2(p.y - c.y, p.x - c.x) - atan2(start.y - c.y, start.x - c.x)
            if shift { a = (a / (.pi / 12)).rounded() * (.pi / 12) }
            return CGAffineTransform(translationX: c.x, y: c.y).rotated(by: a).translatedBy(x: -c.x, y: -c.y)
        case .scale(let i):
            let pts = handlePoints(bounds)
            let h = pts[i], anchor = pts[(i + 4) % 8]
            let nh = CGPoint(x: h.x + p.x - start.x, y: h.y + p.y - start.y)
            var sx: CGFloat = 1, sy: CGFloat = 1
            if i != 1 && i != 5, abs(h.x - anchor.x) > 0.001 { sx = (nh.x - anchor.x) / (h.x - anchor.x) }
            if i != 3 && i != 7, abs(h.y - anchor.y) > 0.001 { sy = (nh.y - anchor.y) / (h.y - anchor.y) }
            if shift && i % 2 == 0 {
                let s = max(abs(sx), abs(sy))
                sx = sx < 0 ? -s : s
                sy = sy < 0 ? -s : s
            }
            if abs(sx) < 0.001 { sx = 0.001 }
            if abs(sy) < 0.001 { sy = 0.001 }
            return CGAffineTransform(translationX: anchor.x, y: anchor.y).scaledBy(x: sx, y: sy)
                .translatedBy(x: -anchor.x, y: -anchor.y)
        }
    }
}

/// Move / scale / rotate of a rectangle that already carries a transform: handles follow the rotated frame,
/// and scaling happens along the frame's own axes (as in Paint.NET's move tools).
struct FrameGesture {
    let kind: TransformGesture.Kind
    let start: CGPoint
    /// The frame in local (untransformed) coordinates.
    let base: CGRect
    /// Local → image transform at the start of the gesture.
    let startTransform: CGAffineTransform

    func transform(to p: CGPoint, shift: Bool) -> CGAffineTransform {
        switch kind {
        case .move, .rotate:
            let c = base.center.applying(startTransform)
            let g = TransformGesture(kind: kind, start: start, bounds: CGRect(x: c.x, y: c.y, width: 0, height: 0))
            return startTransform.concatenating(g.transform(to: p, shift: shift))
        case .scale:
            let inv = startTransform.inverted()
            let local = TransformGesture(kind: kind, start: start.applying(inv), bounds: base).transform(to: p.applying(inv), shift: shift)
            return local.concatenating(startTransform)
        }
    }
}

/// Handle positions of a transformed frame.
func frameHandles(_ base: CGRect, _ t: CGAffineTransform) -> [CGPoint] {
    handlePoints(base).map { $0.applying(t) }
}

/// Common behaviour of selection-creating tools: the result stays pending (editable) until committed.
class SelectionToolBase: Tool {
    var baseSelection: Selection?
    var combineMode: SelectionCombineMode = .replace
    var pending = false
    var dragging = false

    override var hasPendingEdits: Bool { pending }

    func beginGesture(_ e: ToolEvent) {
        commit()
        baseSelection = doc.selection
        combineMode = selectionCombineMode(for: e, default: settings.selectionMode)
        pending = true
    }

    func apply(shape: CGPath?) {
        guard let shape else {
            doc.setSelection(baseSelection)
            return
        }
        doc.setSelection(Selection.combine(baseSelection, with: shape, mode: combineMode))
    }

    override func commit() {
        guard pending else { return }
        pending = false
        let after = doc.selection
        if after === baseSelection { return }
        doc.history.push(SelectionHistoryItem(name: kind.name, icon: kind.icon, before: baseSelection, after: after))
        canvas.needsDisplay = true
    }

    override func cancel() {
        guard pending else { return }
        pending = false
        doc.setSelection(baseSelection)
    }
}

/// Rectangle and Ellipse Select, with handles to adjust the shape after drawing.
final class ShapeSelectTool: SelectionToolBase {
    private var rect: CGRect = .zero
    private var startPoint: CGPoint = .zero
    private var activeHandle: Int?
    private var handleStartRect: CGRect = .zero
    private var moved = false
    private var isEllipse: Bool { kind == .ellipseSelect }

    private func path(_ r: CGRect) -> CGPath {
        isEllipse ? CGPath(ellipseIn: r, transform: nil) : CGPath(rect: r, transform: nil)
    }

    override func mouseDown(_ e: ToolEvent) {
        // Modifier keys always start a new (combined) selection instead of grabbing a handle.
        if pending, !rect.isEmpty, e.button == .left, !e.command, !e.option {
            for (i, h) in handlePoints(rect).enumerated() where canvas.hitHandle(e.viewPoint, h) {
                activeHandle = i
                handleStartRect = rect
                startPoint = e.point
                dragging = true
                return
            }
        }
        beginGesture(e)
        startPoint = snap(e.point)
        rect = .zero
        moved = false
        dragging = true
    }

    private func snap(_ p: CGPoint) -> CGPoint {
        CGPoint(x: clampDouble(p.x.rounded(), 0, CGFloat(doc.width)), y: clampDouble(p.y.rounded(), 0, CGFloat(doc.height)))
    }

    override func mouseDragged(_ e: ToolEvent) {
        guard dragging else { return }
        moved = true
        if let h = activeHandle {
            var r = handleStartRect
            let dx = e.point.x - startPoint.x, dy = e.point.y - startPoint.y
            switch h {
            case 0: r = CGRect(corner: CGPoint(x: r.minX + dx, y: r.minY + dy), corner: CGPoint(x: r.maxX, y: r.maxY))
            case 1: r = CGRect(corner: CGPoint(x: r.minX, y: r.minY + dy), corner: CGPoint(x: r.maxX, y: r.maxY))
            case 2: r = CGRect(corner: CGPoint(x: r.minX, y: r.minY + dy), corner: CGPoint(x: r.maxX + dx, y: r.maxY))
            case 3: r = CGRect(corner: CGPoint(x: r.minX, y: r.minY), corner: CGPoint(x: r.maxX + dx, y: r.maxY))
            case 4: r = CGRect(corner: CGPoint(x: r.minX, y: r.minY), corner: CGPoint(x: r.maxX + dx, y: r.maxY + dy))
            case 5: r = CGRect(corner: CGPoint(x: r.minX, y: r.minY), corner: CGPoint(x: r.maxX, y: r.maxY + dy))
            case 6: r = CGRect(corner: CGPoint(x: r.minX + dx, y: r.minY), corner: CGPoint(x: r.maxX, y: r.maxY + dy))
            default: r = CGRect(corner: CGPoint(x: r.minX + dx, y: r.minY), corner: CGPoint(x: r.maxX, y: r.maxY))
            }
            rect = r.integral
        } else {
            let p = snap(e.point)
            var w = p.x - startPoint.x, h = p.y - startPoint.y
            switch settings.selectionDrawMode {
            case .fixedSize:
                w = CGFloat(settings.selectionFixedWidth)
                h = CGFloat(settings.selectionFixedHeight)
                rect = CGRect(x: p.x - w, y: p.y - h, width: w, height: h)
            case .fixedRatio:
                let ratio = CGFloat(settings.selectionFixedWidth / max(0.0001, settings.selectionFixedHeight))
                let s = max(abs(w), abs(h) * ratio)
                w = (w < 0 ? -s : s)
                h = (h < 0 ? -s : s) / ratio
                rect = CGRect(corner: startPoint, corner: CGPoint(x: startPoint.x + w, y: startPoint.y + h))
            case .normal:
                if e.shift {
                    let s = max(abs(w), abs(h))
                    w = w < 0 ? -s : s
                    h = h < 0 ? -s : s
                }
                rect = CGRect(corner: startPoint, corner: CGPoint(x: startPoint.x + w, y: startPoint.y + h))
            }
        }
        apply(shape: rect.width >= 1 && rect.height >= 1 ? path(rect) : nil)
        setStatus(LF("Selection: %d × %d", Int(rect.width), Int(rect.height)))
        canvas.needsDisplay = true
    }

    override func mouseUp(_ e: ToolEvent) {
        guard dragging else { return }
        dragging = false
        if activeHandle != nil {
            activeHandle = nil
            return
        }
        if !moved || rect.width < 1 || rect.height < 1 {
            // A plain click deselects (in replace mode).
            pending = false
            rect = .zero
            if combineMode == .replace && baseSelection != nil {
                doc.setSelection(nil)
                doc.history.push(SelectionHistoryItem(name: L("Deselect"), icon: "cmd.deselect", before: baseSelection, after: nil))
            } else {
                doc.setSelection(baseSelection)
            }
        }
        canvas.needsDisplay = true
    }

    override func commit() {
        super.commit()
        rect = .zero
    }

    override func drawOverlay(_ ctx: CGContext) {
        guard pending, !rect.isEmpty else { return }
        for h in handlePoints(rect) { canvas.drawHandle(ctx, at: h) }
    }

    override func cursor(atView p: CGPoint) -> NSCursor {
        if pending, !rect.isEmpty, handlePoints(rect).contains(where: { canvas.hitHandle(p, $0) }) {
            return ToolCursors.resizeDiagonal
        }
        return super.cursor(atView: p)
    }
}

final class LassoSelectTool: SelectionToolBase {
    private var points: [CGPoint] = []

    override func mouseDown(_ e: ToolEvent) {
        beginGesture(e)
        points = [e.point]
        dragging = true
    }

    override func mouseDragged(_ e: ToolEvent) {
        guard dragging else { return }
        if let last = points.last, last.distance(to: e.point) < 0.5 / canvas.zoom { return }
        points.append(e.point)
        let p = CGMutablePath()
        p.addLines(between: points)
        p.closeSubpath()
        apply(shape: points.count > 2 ? p : nil)
        canvas.needsDisplay = true
    }

    override func mouseUp(_ e: ToolEvent) {
        guard dragging else { return }
        dragging = false
        if points.count < 3 {
            pending = false
            if combineMode == .replace && baseSelection != nil {
                doc.setSelection(nil)
                doc.history.push(SelectionHistoryItem(name: L("Deselect"), icon: "cmd.deselect", before: baseSelection, after: nil))
            }
        } else {
            commit()
        }
        points = []
    }

    override func drawOverlay(_ ctx: CGContext) {
        guard dragging, points.count > 1 else { return }
        let p = CGMutablePath()
        p.addLines(between: points.map { canvas.toView($0) })
        canvas.drawMarchingAnts(ctx, p)
    }
}

final class MagicWandTool: SelectionToolBase {
    private var seed: CGPoint?
    private var global = false
    private var sample: Surface?
    private var draggingSeed = false

    override func mouseDown(_ e: ToolEvent) {
        if pending, let seed, canvas.hitHandle(e.viewPoint, seed) {
            draggingSeed = true
            return
        }
        guard doc.bounds.contains(x: e.intPoint.x, y: e.intPoint.y) else { return }
        beginGesture(e)
        global = e.shift
        sample = settings.floodSampling == .image ? doc.flattened() : doc.activeLayer.surface
        seed = e.point
        run()
    }

    override func mouseDragged(_ e: ToolEvent) {
        guard draggingSeed else { return }
        seed = CGPoint(x: clampDouble(e.point.x, 0, Double(doc.width) - 0.5), y: clampDouble(e.point.y, 0, Double(doc.height) - 0.5))
        run()
    }

    override func mouseUp(_ e: ToolEvent) {
        draggingSeed = false
    }

    private func run() {
        guard let seed, let sample else { return }
        let mask = FloodFill.fillMask(surface: sample, seed: IntPoint(x: Int(seed.x), y: Int(seed.y)),
                                      tolerance: settings.tolerance, mode: global ? .global : settings.floodMode)
        let shape = Selection.fromMask(mask)?.path
        apply(shape: shape)
        canvas.needsDisplay = true
    }

    override func settingsChanged() {
        if pending { run() }
    }

    override func commit() {
        super.commit()
        seed = nil
        sample = nil
    }

    override func cancel() {
        super.cancel()
        seed = nil
    }

    override func drawOverlay(_ ctx: CGContext) {
        if pending, let seed { canvas.drawHandle(ctx, at: seed, round: true) }
    }
}

/// Moves, scales or rotates the selection outline only.
final class MoveSelectionTool: Tool {
    private var frameBase: Selection?
    private var frameRect = CGRect.zero
    private var frameTransform = CGAffineTransform.identity
    private var lastResult: Selection?
    private var before: Selection?
    private var gesture: FrameGesture?

    /// Restarts the frame when the selection was changed by something else (undo, other tools...).
    private func syncFrame() {
        guard let sel = doc.selection else {
            frameBase = nil
            return
        }
        if sel !== lastResult {
            frameBase = sel
            frameRect = sel.bounds
            frameTransform = .identity
            lastResult = sel
        }
    }

    private var handles: [CGPoint] {
        syncFrame()
        return frameBase == nil ? [] : frameHandles(frameRect, frameTransform)
    }

    private func hitKind(_ e: ToolEvent) -> TransformGesture.Kind {
        if e.button == .right { return .rotate }
        for (i, h) in handles.enumerated() where canvas.hitHandle(e.viewPoint, h) { return .scale(i) }
        return .move
    }

    override func mouseDown(_ e: ToolEvent) {
        syncFrame()
        guard frameBase != nil else { return }
        before = doc.selection
        gesture = FrameGesture(kind: hitKind(e), start: e.point, base: frameRect, startTransform: frameTransform)
    }

    override func mouseDragged(_ e: ToolEvent) {
        guard let base = frameBase, let gesture else { return }
        frameTransform = gesture.transform(to: e.point, shift: e.shift)
        let result = base.transformed(frameTransform)
        lastResult = result
        doc.setSelection(result)
        canvas.needsDisplay = true
    }

    override func mouseUp(_ e: ToolEvent) {
        guard gesture != nil else { return }
        gesture = nil
        if doc.selection !== before {
            doc.history.push(SelectionHistoryItem(name: kind.name, icon: kind.icon, before: before, after: doc.selection))
        }
    }

    override func keyDown(_ e: NSEvent) -> Bool {
        syncFrame()
        guard let base = frameBase, let d = arrowDelta(e) else { return false }
        let prev = doc.selection
        frameTransform = frameTransform.concatenating(CGAffineTransform(translationX: d.x, y: d.y))
        let result = base.transformed(frameTransform)
        lastResult = result
        doc.setSelection(result)
        doc.history.push(SelectionHistoryItem(name: kind.name, icon: kind.icon, before: prev, after: result))
        return true
    }

    override func drawOverlay(_ ctx: CGContext) {
        for h in handles { canvas.drawHandle(ctx, at: h) }
    }

    override func cursor(atView p: CGPoint) -> NSCursor {
        guard let sel = doc.selection else { return .arrow }
        if handles.contains(where: { canvas.hitHandle(p, $0) }) { return ToolCursors.resizeDiagonal }
        return sel.contains(canvas.toImage(p)) ? .openHand : ToolCursors.rotate
    }
}

/// Arrow-key nudge (1 px, Shift = 10 px).
func arrowDelta(_ e: NSEvent) -> CGPoint? {
    let step: CGFloat = e.modifierFlags.contains(.shift) ? 10 : 1
    switch e.keyCode {
    case 123: return CGPoint(x: -step, y: 0)
    case 124: return CGPoint(x: step, y: 0)
    case 125: return CGPoint(x: 0, y: step)
    case 126: return CGPoint(x: 0, y: -step)
    default: return nil
    }
}
