import AppKit
import BrushwoodCore

/// Move Selected Pixels: lifts the selected pixels into a floating bitmap that can be moved, scaled (handles)
/// and rotated (right-drag). ⌘-drag leaves a copy behind. Pasting also goes through this tool.
final class MoveSelectedPixelsTool: Tool {
    private var session: PixelEditSession?
    private var floating: Surface?
    private var floatingOrigin = CGPoint.zero
    private var baseSelection: Selection?
    private var selectionBefore: Selection?
    private var transform = CGAffineTransform.identity
    private var gesture: FrameGesture?
    private var holeRect = IntRect.zero
    private var holeMask: MaskSurface?
    private var leaveCopy = false
    private var lastRendered = IntRect.zero
    private var historyName = ""
    private var historyIcon = ""
    /// While dragging, the floating pixels are drawn over the canvas instead of being written into the layer at every
    /// mouse move, which made every display tile under them be composited again: far too slow on large images. They
    /// are written into the layer when the button is released (or at once when drawing over can't look the same).
    private var drawsFloating = false
    private var floatingImage: CGImage?
    /// The floating pixels reduced to the screen's resolution when zoomed out, so each frame draws few pixels.
    private var floatingPreview: (image: CGImage, scale: CGFloat)?

    override var hasPendingEdits: Bool { session != nil }

    private func lift(copy: Bool) {
        let layer = doc.activeLayer
        session = PixelEditSession(layer: layer)
        selectionBefore = doc.selection
        let selection = doc.selection ?? Selection.rect(doc.bounds.cgRect)
        baseSelection = selection
        let rect = selection.intBounds.intersection(doc.bounds)
        historyName = kind.name
        historyIcon = kind.icon
        transform = .identity
        leaveCopy = copy
        guard !rect.isEmpty, let f = layer.surface.copy(rect: rect) else {
            floating = nil
            return
        }
        let mask = doc.selection == nil ? nil : selection.mask(width: doc.width, height: doc.height,
                                                                antialias: settings.selectionClippingAntialiased)
        if let mask {
            for y in 0..<f.height {
                let row = f.row(y), m = mask.row(y + rect.top)
                for x in 0..<f.width {
                    let c = Int(m[x + rect.left])
                    if c < 255 { row[x].a = UInt8(mul255(Int(row[x].a), c)) }
                }
            }
        }
        floating = f
        floatingImage = nil
        floatingPreview = nil
        floatingOrigin = CGPoint(x: rect.x, y: rect.y)
        holeRect = copy ? .zero : rect
        holeMask = mask
        lastRendered = rect
    }

    /// Starts a paste: the surface floats above the active layer at `origin`.
    func beginPaste(_ surface: Surface, at origin: IntPoint) {
        commit()
        let layer = doc.activeLayer
        session = PixelEditSession(layer: layer)
        selectionBefore = doc.selection
        floating = surface
        floatingImage = nil
        floatingPreview = nil
        floatingOrigin = CGPoint(x: origin.x, y: origin.y)
        baseSelection = Selection.rect(CGRect(x: origin.x, y: origin.y, width: surface.width, height: surface.height))
        transform = .identity
        holeRect = .zero
        holeMask = nil
        leaveCopy = true
        historyName = L("Paste")
        historyIcon = "history.paste"
        lastRendered = .zero
        render()
    }

    private var currentFloatingRect: CGRect {
        guard let floating else { return .zero }
        return CGRect(x: floatingOrigin.x, y: floatingOrigin.y, width: CGFloat(floating.width), height: CGFloat(floating.height))
            .applying(transform)
    }

    private func render() {
        guard let session, let floating else { return }
        let layer = session.layer.surface
        let newBounds = IntRect(enclosing: currentFloatingRect.insetBy(dx: -1, dy: -1)).intersection(doc.bounds)
        let dirty = lastRendered.union(newBounds).union(holeRect).intersection(doc.bounds)
        // Restore, punch the hole, then draw the floating pixels.
        session.restore(dirty)
        punchHole()
        let t = transform
        let isTranslation = t.a == 1 && t.b == 0 && t.c == 0 && t.d == 1 && t.tx == t.tx.rounded() && t.ty == t.ty.rounded()
        if isTranslation {
            let ox = Int(floatingOrigin.x + t.tx), oy = Int(floatingOrigin.y + t.ty)
            for y in newBounds.top..<newBounds.bottom {
                let fy = y - oy
                if fy < 0 || fy >= floating.height { continue }
                let x0 = max(newBounds.left, ox), x1 = min(newBounds.right, ox + floating.width)
                if x1 <= x0 { continue }
                Blender.blendRow(.normal, dst: layer.row(y) + x0, src: floating.row(fy) + (x0 - ox), count: x1 - x0, opacity: 255)
            }
        } else {
            let inv = CGAffineTransform(translationX: floatingOrigin.x, y: floatingOrigin.y).concatenating(t).inverted()
            let bilinear = settings.bilinearResampling
            DispatchQueue.concurrentPerform(iterations: max(0, newBounds.height)) { i in
                let y = newBounds.top + i
                let row = layer.row(y)
                for x in newBounds.left..<newBounds.right {
                    let p = CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5).applying(inv)
                    let c: ColorBgra
                    if bilinear {
                        c = floating.bilinearSampleTransparentEdges(Double(p.x), Double(p.y))
                    } else {
                        let sx = Int(floor(p.x)), sy = Int(floor(p.y))
                        c = (sx >= 0 && sy >= 0 && sx < floating.width && sy < floating.height) ? floating[sx, sy] : .transparent
                    }
                    if c.a != 0 { row[x] = Blender.blend(.normal, row[x], c) }
                }
            }
        }
        if let baseSelection { doc.setSelection(baseSelection.transformed(transform)) }
        session.touch(dirty)
        lastRendered = newBounds
        doc.invalidate(dirty)
        canvas.needsDisplay = true
    }

    /// Clears the pixels that were lifted from the layer (not for a copy or a paste).
    private func punchHole() {
        guard let session, !holeRect.isEmpty else { return }
        let layer = session.layer.surface
        for y in holeRect.top..<holeRect.bottom {
            let row = layer.row(y)
            let m = holeMask?.row(y)
            for x in holeRect.left..<holeRect.right {
                let c = Int(m?[x] ?? 255)
                if c > 0 { row[x] = Blender.lerpTo(row[x], row[x].withAlpha(0), coverage: c) }
            }
        }
    }

    /// Drawing the floating pixels over the canvas looks the same as writing them into the layer only when nothing is
    /// composited above that layer and it blends normally at full opacity.
    private var canDrawFloating: Bool {
        guard let session, let i = doc.layers.firstIndex(where: { $0 === session.layer }) else { return false }
        let layer = doc.layers[i]
        guard layer.isVisible, layer.opacity == 255, layer.blendMode == .normal else { return false }
        return doc.layers[(i + 1)...].allSatisfy { !$0.isVisible || $0.opacity == 0 }
    }

    /// Takes the floating pixels out of the layer (keeping the hole) and starts drawing them over the canvas.
    private func beginDrawingFloating() {
        guard let session, let floating else { return }
        let dirty = lastRendered.union(holeRect).intersection(doc.bounds)
        session.restore(dirty)
        punchHole()
        session.touch(dirty)
        lastRendered = .zero
        if floatingImage == nil { floatingImage = floating.makePremultipliedCGImage(rect: floating.bounds) }
        let scale = min(1, canvas.zoom * (canvas.window?.backingScaleFactor ?? 2))
        if scale < 0.75, floatingPreview?.scale != scale, let image = floatingImage {
            floatingPreview = Self.reduced(image, scale: scale).map { ($0, scale) }
        }
        drawsFloating = true
        canvas.isInteracting = true
        canvas.redrawsSelectionChangesItself = true
        if !dirty.isEmpty { doc.invalidate(dirty) }
    }

    /// Writes the floating pixels back into the layer at their current place.
    private func endDrawingFloating() {
        guard drawsFloating else { return }
        drawsFloating = false
        canvas.isInteracting = false
        canvas.redrawsSelectionChangesItself = false
        render()
    }

    private static func reduced(_ image: CGImage, scale: CGFloat) -> CGImage? {
        let w = max(1, Int((CGFloat(image.width) * scale).rounded(.up))), h = max(1, Int((CGFloat(image.height) * scale).rounded(.up)))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    override func drawContent(_ ctx: CGContext) {
        guard drawsFloating, let floating, let image = floatingPreview?.image ?? floatingImage else { return }
        let w = CGFloat(floating.width), h = CGFloat(floating.height)
        // Floating pixels' own frame → image → view.
        ctx.concatenate(CGAffineTransform(translationX: floatingOrigin.x, y: floatingOrigin.y).concatenating(transform)
            .concatenating(canvas.imageToView))
        // CGImage rows go upwards; the canvas is flipped.
        ctx.translateBy(x: 0, y: h)
        ctx.scaleBy(x: 1, y: -1)
        let t = transform
        let isTranslation = t.a == 1 && t.b == 0 && t.c == 0 && t.d == 1
        ctx.interpolationQuality = isTranslation && canvas.zoom >= 1 ? .none
            : floatingPreview != nil ? .medium : (settings.bilinearResampling ? .high : .none)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }

    /// The floating pixels' rectangle before the transform (local frame).
    private var floatingBaseRect: CGRect {
        guard let floating else { return .zero }
        return CGRect(x: floatingOrigin.x, y: floatingOrigin.y, width: CGFloat(floating.width), height: CGFloat(floating.height))
    }

    /// Handles follow the transformed frame while moving; otherwise they sit on the selection bounds.
    private var handles: [CGPoint] {
        if session != nil, floating != nil { return frameHandles(floatingBaseRect, transform) }
        return doc.selection.map { handlePoints($0.bounds) } ?? []
    }

    private func gestureKind(_ e: ToolEvent) -> TransformGesture.Kind {
        if e.button == .right { return .rotate }
        for (i, h) in handles.enumerated() where canvas.hitHandle(e.viewPoint, h) { return .scale(i) }
        return .move
    }

    override func mouseDown(_ e: ToolEvent) {
        if e.command && session != nil {
            // ⌘-drag again stamps the current pixels and continues with a copy.
            commit()
        }
        let kindForGesture = gestureKind(e)
        if session == nil { lift(copy: e.command) }
        guard session != nil, floating != nil else {
            session = nil
            return
        }
        gesture = FrameGesture(kind: kindForGesture, start: e.point, base: floatingBaseRect, startTransform: transform)
        if canDrawFloating { beginDrawingFloating() }
    }

    override func mouseDragged(_ e: ToolEvent) {
        guard let gesture else { return }
        var t = gesture.transform(to: e.point, shift: e.shift)
        if case .move = gesture.kind {
            // Moving goes by whole pixels, as in Paint.NET: no resampling, so the pixels stay sharp.
            t.tx = t.tx.rounded()
            t.ty = t.ty.rounded()
        }
        if drawsFloating {
            // Redraw only where the pixels were and where they are now, with room for the handles.
            let before = currentFloatingRect
            transform = t
            if let baseSelection { doc.setSelection(baseSelection.transformed(transform)) }
            let r = before.union(currentFloatingRect).applying(canvas.imageToView)
            canvas.setNeedsDisplay(r.insetBy(dx: -12, dy: -12))
        } else {
            transform = t
            render()
        }
    }

    override func mouseUp(_ e: ToolEvent) {
        gesture = nil
        endDrawingFloating()
    }

    override func keyDown(_ e: NSEvent) -> Bool {
        guard let d = arrowDelta(e) else { return false }
        if session == nil { lift(copy: false) }
        guard session != nil, floating != nil else { return true }
        transform = transform.concatenating(CGAffineTransform(translationX: d.x, y: d.y))
        render()
        return true
    }

    override func commit() {
        guard let session else { return }
        endDrawingFloating()
        let item = session.makeHistoryItem(name: historyName, icon: historyIcon, selectionBefore: selectionBefore,
                                           selectionAfter: doc.selection, changesSelection: true)
        if let item { doc.history.push(item) }
        self.session = nil
        floating = nil
        floatingImage = nil
        floatingPreview = nil
        gesture = nil
        holeMask = nil
        canvas.needsDisplay = true
    }

    override func cancel() {
        guard let session else { return }
        drawsFloating = false
        canvas.isInteracting = false
        canvas.redrawsSelectionChangesItself = false
        session.cancel(doc)
        doc.setSelection(selectionBefore)
        self.session = nil
        floating = nil
        floatingImage = nil
        floatingPreview = nil
        gesture = nil
        canvas.needsDisplay = true
    }

    override func drawOverlay(_ ctx: CGContext) {
        for h in handles { canvas.drawHandle(ctx, at: h) }
    }

    override func cursor(atView p: CGPoint) -> NSCursor {
        guard let sel = doc.selection else { return .openHand }
        if handles.contains(where: { canvas.hitHandle(p, $0) }) { return ToolCursors.resizeDiagonal }
        return sel.contains(canvas.toImage(p)) ? .openHand : ToolCursors.rotate
    }
}
