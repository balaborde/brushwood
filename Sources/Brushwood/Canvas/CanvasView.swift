import AppKit
import BrushwoodCore

/// Mouse input for tools, already converted to image coordinates.
struct ToolEvent {
    enum Button { case left, right }

    var point: CGPoint
    var viewPoint: CGPoint
    var button: Button
    var modifiers: NSEvent.ModifierFlags
    var clickCount: Int
    var pressure: CGFloat

    /// Paint.NET's Ctrl modifier maps to ⌘ on the Mac.
    var command: Bool { modifiers.contains(.command) }
    /// Paint.NET's Alt modifier maps to ⌥.
    var option: Bool { modifiers.contains(.option) }
    var shift: Bool { modifiers.contains(.shift) }
    var intPoint: IntPoint { IntPoint(x: Int(floor(point.x)), y: Int(floor(point.y))) }
}

enum Theme {
    static let canvasBackground = NSColor(name: nil) { a in
        a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0.17, alpha: 1) : NSColor(srgbRed: 0.89, green: 0.9, blue: 0.92, alpha: 1)
    }
    static let selectionTint = NSColor(srgbRed: 0.25, green: 0.55, blue: 1, alpha: 0.1)
    static let handleFill = NSColor.white
    static let handleStroke = NSColor(srgbRed: 0.1, green: 0.35, blue: 0.8, alpha: 1)
}

/// The scrollable drawing surface. Draws the image (tiled), checkerboard, grid, selection and tool overlays,
/// and forwards input to the active tool.
final class CanvasView: NSView {
    weak var host: MainWindowController?
    private(set) var workspace: DocumentWorkspace?
    private(set) var renderer: TileRenderer?
    var tool: Tool? {
        didSet { window?.invalidateCursorRects(for: self); needsDisplay = true }
    }
    private(set) var zoom: CGFloat = 1
    let margin: CGFloat = 24
    private var observers: [NSObjectProtocol] = []
    private var antsPhase: CGFloat = 0
    private var antsTimer: Timer?
    private var selectionViewPath: CGPath?
    private(set) var mouseImagePoint: CGPoint?
    private var panStart: (mouse: NSPoint, origin: NSPoint)?
    private var spaceDown = false
    private var trackingArea: NSTrackingArea?
    private var activeButton: ToolEvent.Button?

    var env: AppEnvironment { .shared }

    override init(frame: NSRect) {
        super.init(frame: frame)
        if #available(macOS 14.0, *) { clipsToBounds = true }
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: .viewSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.needsDisplay = true
        })
        observers.append(nc.addObserver(forName: .toolSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.tool?.settingsChanged()
            self?.needsDisplay = true
        })
        observers.append(nc.addObserver(forName: .colorsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.tool?.colorsChanged()
        })
        antsTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.tickAnts() }
        RunLoop.main.add(antsTimer!, forMode: .common)
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        antsTimer?.invalidate()
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }

    // MARK: - Document binding

    private var docObservers: [NSObjectProtocol] = []

    func setWorkspace(_ ws: DocumentWorkspace?) {
        docObservers.forEach { NotificationCenter.default.removeObserver($0) }
        docObservers.removeAll()
        workspace = ws
        selectionViewPath = nil
        guard let ws else {
            renderer = nil
            updateFrame()
            needsDisplay = true
            return
        }
        renderer = TileRenderer(document: ws.document)
        let nc = NotificationCenter.default
        let doc = ws.document
        docObservers.append(nc.addObserver(forName: .documentInvalidated, object: doc, queue: .main) { [weak self] n in
            guard let self else { return }
            let rect = n.userInfo?["rect"] as? IntRect
            self.renderer?.invalidate(rect)
            if let rect {
                self.setNeedsDisplay(self.toView(rect.cgRect).insetBy(dx: -2, dy: -2))
            } else {
                self.needsDisplay = true
            }
        })
        docObservers.append(nc.addObserver(forName: .documentLayersChanged, object: doc, queue: .main) { [weak self] _ in
            self?.renderer?.invalidate(nil)
            self?.needsDisplay = true
        })
        docObservers.append(nc.addObserver(forName: .documentSizeChanged, object: doc, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.renderer = TileRenderer(document: doc)
            self.selectionViewPath = nil
            self.updateFrame()
            self.needsDisplay = true
        })
        docObservers.append(nc.addObserver(forName: .documentSelectionChanged, object: doc, queue: .main) { [weak self] _ in
            self?.selectionViewPath = nil
            self?.needsDisplay = true
        })
        zoom = ws.zoom
        updateFrame()
        if let c = ws.viewCenter { scroll(toImageCenter: c) } else { centerImage() }
        needsDisplay = true
    }

    // MARK: - Geometry

    var imageSize: CGSize {
        guard let d = workspace?.document else { return .zero }
        return CGSize(width: d.width, height: d.height)
    }

    var imageOrigin: CGPoint {
        let w = imageSize.width * zoom, h = imageSize.height * zoom
        return CGPoint(x: floor((bounds.width - w) / 2), y: floor((bounds.height - h) / 2))
    }

    var imageRectInView: CGRect {
        CGRect(origin: imageOrigin, size: CGSize(width: imageSize.width * zoom, height: imageSize.height * zoom))
    }

    var imageToView: CGAffineTransform {
        let o = imageOrigin
        return CGAffineTransform(a: zoom, b: 0, c: 0, d: zoom, tx: o.x, ty: o.y)
    }

    func toImage(_ p: CGPoint) -> CGPoint {
        let o = imageOrigin
        return CGPoint(x: (p.x - o.x) / zoom, y: (p.y - o.y) / zoom)
    }

    func toView(_ p: CGPoint) -> CGPoint {
        let o = imageOrigin
        return CGPoint(x: o.x + p.x * zoom, y: o.y + p.y * zoom)
    }

    func toView(_ r: CGRect) -> CGRect {
        let o = imageOrigin
        return CGRect(x: o.x + r.minX * zoom, y: o.y + r.minY * zoom, width: r.width * zoom, height: r.height * zoom)
    }

    var clipView: NSClipView? { enclosingScrollView?.contentView }

    /// Resizes the document view so it is at least as large as the viewport plus margins around the image.
    func updateFrame() {
        guard let clip = clipView else { return }
        let vis = clip.bounds.size
        let w = max(vis.width, imageSize.width * zoom + 2 * margin)
        let h = max(vis.height, imageSize.height * zoom + 2 * margin)
        if frame.size != CGSize(width: w, height: h) {
            setFrameSize(NSSize(width: w, height: h))
        }
        selectionViewPath = nil
        host?.canvasGeometryChanged()
    }

    func centerImage() {
        guard let clip = clipView else { return }
        let vis = clip.bounds.size
        clip.scroll(to: NSPoint(x: max(0, (bounds.width - vis.width) / 2), y: max(0, (bounds.height - vis.height) / 2)))
        enclosingScrollView?.reflectScrolledClipView(clip)
    }

    func scroll(toImageCenter c: CGPoint) {
        guard let clip = clipView else { return }
        let vis = clip.bounds.size
        let v = toView(c)
        var o = NSPoint(x: v.x - vis.width / 2, y: v.y - vis.height / 2)
        o.x = clampDouble(o.x, 0, max(0, bounds.width - vis.width))
        o.y = clampDouble(o.y, 0, max(0, bounds.height - vis.height))
        clip.scroll(to: o)
        enclosingScrollView?.reflectScrolledClipView(clip)
    }

    /// Image point currently at the center of the viewport.
    var visibleImageCenter: CGPoint? {
        guard let clip = clipView, workspace != nil else { return nil }
        let b = clip.bounds
        return toImage(CGPoint(x: b.midX, y: b.midY))
    }

    /// Visible part of the image in image coordinates.
    var visibleImageRect: CGRect {
        guard let clip = clipView else { return .zero }
        let b = clip.bounds
        let a = toImage(b.origin), c = toImage(CGPoint(x: b.maxX, y: b.maxY))
        return CGRect(corner: a, corner: c).intersection(CGRect(origin: .zero, size: imageSize))
    }

    static let zoomLevels: [CGFloat] = [0.01, 0.02, 0.03, 0.04, 0.05, 0.06, 0.08, 0.12, 0.16, 0.25, 0.3333, 0.5, 0.6667, 1,
                                        1.5, 2, 3, 4, 5, 6, 7, 8, 10, 12, 14, 16, 18, 20, 24, 28, 32, 36]

    /// Sets the zoom keeping `anchorView` (a point in this view's coordinates) fixed on screen.
    func setZoom(_ z: CGFloat, anchorView: CGPoint? = nil) {
        guard let clip = clipView, let ws = workspace else { return }
        let newZoom = clampDouble(z, 0.01, 36)
        let vis = clip.bounds
        let anchor = anchorView ?? CGPoint(x: vis.midX, y: vis.midY)
        let offsetInClip = CGPoint(x: anchor.x - vis.minX, y: anchor.y - vis.minY)
        let imgPt = toImage(anchor)
        zoom = newZoom
        ws.zoom = newZoom
        updateFrame()
        let nv = toView(imgPt)
        var o = NSPoint(x: nv.x - offsetInClip.x, y: nv.y - offsetInClip.y)
        o.x = clampDouble(o.x, 0, max(0, bounds.width - vis.width))
        o.y = clampDouble(o.y, 0, max(0, bounds.height - vis.height))
        clip.scroll(to: o)
        enclosingScrollView?.reflectScrolledClipView(clip)
        selectionViewPath = nil
        needsDisplay = true
        host?.zoomChanged()
    }

    func zoomIn(anchorView: CGPoint? = nil) {
        setZoom(CanvasView.zoomLevels.first { $0 > zoom * 1.001 } ?? zoom, anchorView: anchorView)
    }

    func zoomOut(anchorView: CGPoint? = nil) {
        setZoom(CanvasView.zoomLevels.last { $0 < zoom * 0.999 } ?? zoom, anchorView: anchorView)
    }

    func zoomToWindow() {
        guard let clip = clipView, imageSize.width > 0 else { return }
        let vis = clip.bounds.size
        let z = min((vis.width - 2 * margin) / imageSize.width, (vis.height - 2 * margin) / imageSize.height)
        setZoom(max(0.01, min(z, 36)))
        centerImage()
    }

    func zoomToRect(_ r: CGRect) {
        guard let clip = clipView, r.width > 0, r.height > 0 else { return }
        let vis = clip.bounds.size
        let z = min((vis.width - 2 * margin) / r.width, (vis.height - 2 * margin) / r.height)
        setZoom(clampDouble(z, 0.01, 36))
        scroll(toImageCenter: r.center)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        Theme.canvasBackground.setFill()
        // Since macOS 14 views don't clip to their bounds and dirtyRect can extend past them.
        dirtyRect.intersection(bounds).fill()
        guard let renderer, workspace != nil else { return }
        let imgRect = imageRectInView

        // Drop shadow around the canvas.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 6, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        NSColor.white.setFill()
        imgRect.fill()
        ctx.restoreGState()

        let visible = imgRect.intersection(dirtyRect)
        guard !visible.isEmpty else {
            drawOverlays(ctx, dirtyRect)
            return
        }
        ctx.saveGState()
        Checkerboard.patternColor.setFill()
        visible.fill()

        // Tiles.
        ctx.interpolationQuality = zoom >= 1 ? .none : .high
        ctx.setShouldAntialias(false)
        let ts = CGFloat(TileRenderer.tileSize)
        let a = toImage(visible.origin), b = toImage(CGPoint(x: visible.maxX, y: visible.maxY))
        let tx0 = max(0, Int(floor(a.x / ts))), ty0 = max(0, Int(floor(a.y / ts)))
        let tx1 = min(renderer.columns - 1, Int(floor((b.x - 0.0001) / ts)))
        let ty1 = min(renderer.rows - 1, Int(floor((b.y - 0.0001) / ts)))
        if tx1 >= tx0 && ty1 >= ty0 {
            for ty in ty0...ty1 {
                for tx in tx0...tx1 {
                    guard let img = renderer.image(tx, ty) else { continue }
                    var dest = toView(renderer.tileRect(tx, ty).cgRect)
                    dest = CGRect(x: round(dest.minX), y: round(dest.minY), width: round(dest.maxX) - round(dest.minX),
                                  height: round(dest.maxY) - round(dest.minY))
                    ctx.saveGState()
                    ctx.translateBy(x: 0, y: dest.maxY)
                    ctx.scaleBy(x: 1, y: -1)
                    ctx.draw(img, in: CGRect(x: dest.minX, y: 0, width: dest.width, height: dest.height))
                    ctx.restoreGState()
                }
            }
        }
        ctx.restoreGState()

        if env.showPixelGrid && zoom >= 2 { drawPixelGrid(ctx, visible) }
        drawOverlays(ctx, dirtyRect)
    }

    private func drawPixelGrid(_ ctx: CGContext, _ visible: CGRect) {
        let a = toImage(visible.origin), b = toImage(CGPoint(x: visible.maxX, y: visible.maxY))
        let x0 = Int(floor(a.x)), x1 = Int(ceil(b.x)), y0 = Int(floor(a.y)), y1 = Int(ceil(b.y))
        ctx.saveGState()
        ctx.setShouldAntialias(false)
        ctx.setLineWidth(1)
        ctx.setStrokeColor(NSColor(white: 0.5, alpha: 0.55).cgColor)
        let o = imageOrigin
        for x in x0...x1 {
            let vx = round(o.x + CGFloat(x) * zoom) + 0.5
            ctx.move(to: CGPoint(x: vx, y: visible.minY))
            ctx.addLine(to: CGPoint(x: vx, y: visible.maxY))
        }
        for y in y0...y1 {
            let vy = round(o.y + CGFloat(y) * zoom) + 0.5
            ctx.move(to: CGPoint(x: visible.minX, y: vy))
            ctx.addLine(to: CGPoint(x: visible.maxX, y: vy))
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    private func drawOverlays(_ ctx: CGContext, _ dirtyRect: CGRect) {
        if let sel = workspace?.document.selection, tool?.hidesSelectionOutline != true {
            if selectionViewPath == nil {
                var t = imageToView
                selectionViewPath = sel.path.copy(using: &t)
            }
            if let p = selectionViewPath {
                ctx.saveGState()
                ctx.addPath(p)
                ctx.setFillColor(Theme.selectionTint.cgColor)
                ctx.fillPath(using: .evenOdd)
                drawMarchingAnts(ctx, p)
                ctx.restoreGState()
            }
        }
        tool?.drawOverlay(ctx)
        if let p = mouseImagePoint, tool?.showsBrushOutline == true, panStart == nil {
            let w = max(1, env.tools.brushWidth * zoom)
            let c = toView(p)
            let r = CGRect(x: c.x - w / 2, y: c.y - w / 2, width: w, height: w)
            ctx.saveGState()
            ctx.setLineWidth(1)
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.8).cgColor)
            ctx.strokeEllipse(in: r.insetBy(dx: -1, dy: -1))
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.8).cgColor)
            ctx.strokeEllipse(in: r)
            ctx.restoreGState()
        }
    }

    func drawMarchingAnts(_ ctx: CGContext, _ p: CGPath) {
        ctx.saveGState()
        ctx.setLineWidth(1)
        ctx.setShouldAntialias(true)
        ctx.addPath(p)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.strokePath()
        ctx.addPath(p)
        ctx.setLineDash(phase: antsPhase, lengths: [4, 4])
        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.strokePath()
        ctx.restoreGState()
    }

    private func tickAnts() {
        guard window?.isVisible == true, window?.occlusionState.contains(.visible) == true else { return }
        guard let p = selectionViewPath, workspace?.document.selection != nil else { return }
        antsPhase = (antsPhase + 1).truncatingRemainder(dividingBy: 8)
        setNeedsDisplay(p.boundingBoxOfPath.insetBy(dx: -2, dy: -2).intersection(visibleRect))
    }

    /// Redraws the overlay region of the tool (call after changing handles etc.).
    func overlayChanged(_ imageRect: CGRect? = nil) {
        if let r = imageRect {
            setNeedsDisplay(toView(r).insetBy(dx: -12, dy: -12))
        } else {
            needsDisplay = true
        }
    }

    // MARK: - Handles (shared by tools)

    static let handleSize: CGFloat = 9

    func drawHandle(_ ctx: CGContext, at imagePoint: CGPoint, round: Bool = false, highlighted: Bool = false) {
        let c = toView(imagePoint)
        let s = CanvasView.handleSize
        let r = CGRect(x: c.x - s / 2, y: c.y - s / 2, width: s, height: s)
        ctx.saveGState()
        ctx.setFillColor((highlighted ? NSColor.systemYellow : Theme.handleFill).cgColor)
        ctx.setStrokeColor(Theme.handleStroke.cgColor)
        ctx.setLineWidth(1.2)
        if round {
            ctx.fillEllipse(in: r)
            ctx.strokeEllipse(in: r)
        } else {
            ctx.fill(r)
            ctx.stroke(r)
        }
        ctx.restoreGState()
    }

    /// Whether a view-space point is over a handle at image point `p`.
    func hitHandle(_ viewPoint: CGPoint, _ p: CGPoint) -> Bool {
        let c = toView(p)
        return abs(c.x - viewPoint.x) <= CanvasView.handleSize && abs(c.y - viewPoint.y) <= CanvasView.handleSize
    }

    // MARK: - Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        // Active in the whole app so hovering keeps working after clicking a floating window.
        let t = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp,
                                                      .inVisibleRect, .cursorUpdate], owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingArea = t
    }

    private func makeEvent(_ e: NSEvent, button: ToolEvent.Button) -> ToolEvent {
        let vp = convert(e.locationInWindow, from: nil)
        var mods = e.modifierFlags
        mods.remove(.control)
        let pressure = (e.type == .leftMouseDragged || e.type == .leftMouseDown) && e.subtype == .tabletPoint ? CGFloat(e.pressure) : 1
        return ToolEvent(point: toImage(vp), viewPoint: vp, button: button, modifiers: mods,
                         clickCount: e.clickCount, pressure: pressure)
    }

    private var isPanMode: Bool { spaceDown }

    override func mouseDown(with e: NSEvent) {
        window?.makeFirstResponder(self)
        guard workspace != nil else { return }
        if isPanMode {
            beginPan(e)
            return
        }
        // Control-click is the Mac right click.
        let button: ToolEvent.Button = e.modifierFlags.contains(.control) ? .right : .left
        activeButton = button
        tool?.mouseDown(makeEvent(e, button: button))
    }

    override func mouseDragged(with e: NSEvent) {
        if panStart != nil {
            continuePan(e)
            return
        }
        guard let b = activeButton else { return }
        autoscroll(with: e)
        let ev = makeEvent(e, button: b)
        updateMouse(ev.point)
        tool?.mouseDragged(ev)
    }

    override func mouseUp(with e: NSEvent) {
        if panStart != nil {
            panStart = nil
            refreshCursor()
            return
        }
        guard let b = activeButton else { return }
        activeButton = nil
        tool?.mouseUp(makeEvent(e, button: b))
    }

    override func rightMouseDown(with e: NSEvent) {
        window?.makeFirstResponder(self)
        guard workspace != nil, !isPanMode else { return }
        activeButton = .right
        tool?.mouseDown(makeEvent(e, button: .right))
    }

    override func rightMouseDragged(with e: NSEvent) {
        guard activeButton == .right else { return }
        let ev = makeEvent(e, button: .right)
        updateMouse(ev.point)
        tool?.mouseDragged(ev)
    }

    override func rightMouseUp(with e: NSEvent) {
        guard activeButton == .right else { return }
        activeButton = nil
        tool?.mouseUp(makeEvent(e, button: .right))
    }

    override func otherMouseDown(with e: NSEvent) { beginPan(e) }
    override func otherMouseDragged(with e: NSEvent) { continuePan(e) }
    override func otherMouseUp(with e: NSEvent) {
        panStart = nil
        refreshCursor()
    }

    override func mouseMoved(with e: NSEvent) {
        guard workspace != nil else { return }
        let ev = makeEvent(e, button: .left)
        updateMouse(ev.point)
        tool?.mouseMoved(ev)
        refreshCursor(at: ev)
    }

    override func mouseExited(with event: NSEvent) {
        let old = mouseImagePoint
        mouseImagePoint = nil
        host?.cursorMoved(nil)
        if tool?.showsBrushOutline == true, let old { brushOutlineDirty(old) }
    }

    private func updateMouse(_ p: CGPoint) {
        let old = mouseImagePoint
        mouseImagePoint = p
        host?.cursorMoved(p)
        if tool?.showsBrushOutline == true {
            if let old { brushOutlineDirty(old) }
            brushOutlineDirty(p)
        }
    }

    private func brushOutlineDirty(_ p: CGPoint) {
        let w = env.tools.brushWidth * zoom + 6
        let c = toView(p)
        setNeedsDisplay(CGRect(x: c.x - w / 2, y: c.y - w / 2, width: w, height: w))
    }

    private func beginPan(_ e: NSEvent) {
        guard let clip = clipView else { return }
        panStart = (e.locationInWindow, clip.bounds.origin)
        NSCursor.closedHand.set()
    }

    private func continuePan(_ e: NSEvent) {
        guard let start = panStart, let clip = clipView else { return }
        let dx = e.locationInWindow.x - start.mouse.x, dy = e.locationInWindow.y - start.mouse.y
        pan(to: NSPoint(x: start.origin.x - dx, y: start.origin.y + dy), clip: clip)
    }

    func pan(to origin: NSPoint, clip: NSClipView) {
        var o = origin
        o.x = clampDouble(o.x, 0, max(0, bounds.width - clip.bounds.width))
        o.y = clampDouble(o.y, 0, max(0, bounds.height - clip.bounds.height))
        clip.scroll(to: o)
        enclosingScrollView?.reflectScrolledClipView(clip)
    }

    override func scrollWheel(with e: NSEvent) {
        if e.modifierFlags.contains(.command) || e.modifierFlags.contains(.control) {
            let p = convert(e.locationInWindow, from: nil)
            let delta = e.hasPreciseScrollingDeltas ? e.scrollingDeltaY / 30 : e.scrollingDeltaY
            if delta > 0.05 { zoomIn(anchorView: p) } else if delta < -0.05 { zoomOut(anchorView: p) }
            return
        }
        super.scrollWheel(with: e)
    }

    override func magnify(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        setZoom(zoom * (1 + e.magnification), anchorView: p)
    }

    override func smartMagnify(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        if zoom < 1 { setZoom(1, anchorView: p) } else { zoomToWindow() }
    }

    // MARK: - Cursor

    override func cursorUpdate(with event: NSEvent) {
        refreshCursor()
    }

    func refreshCursor(at ev: ToolEvent? = nil) {
        if spaceDown || panStart != nil {
            (panStart != nil ? NSCursor.closedHand : NSCursor.openHand).set()
            return
        }
        guard let tool, NSApp.isActive else { return }
        let point: CGPoint
        if let ev { point = ev.viewPoint } else {
            guard let w = window else { return }
            point = convert(w.mouseLocationOutsideOfEventStream, from: nil)
        }
        guard visibleRect.contains(point) else { return }
        tool.cursor(atView: point).set()
    }

    // MARK: - Keyboard

    override func keyDown(with e: NSEvent) {
        if tool?.keyDown(e) == true { return }
        let mods = e.modifierFlags.intersection([.command, .control, .option])
        if mods.isEmpty, let ch = e.charactersIgnoringModifiers?.lowercased().first {
            let shift = e.modifierFlags.contains(.shift)
            switch ch {
            case " ":
                if !spaceDown {
                    spaceDown = true
                    refreshCursor()
                }
                return
            case "x":
                env.swapColors()
                return
            case "[":
                env.tools.brushWidth = max(1, env.tools.brushWidth - (e.modifierFlags.contains(.shift) ? 10 : 1))
                return
            case "]":
                env.tools.brushWidth = min(2000, env.tools.brushWidth + (e.modifierFlags.contains(.shift) ? 10 : 1))
                return
            default:
                if host?.selectTool(byShortcut: ch, backwards: shift) == true { return }
            }
        }
        switch e.keyCode {
        case 53: tool?.cancel(); return
        case 36, 76: host?.commitOrDeselect(); return
        default: break
        }
        super.keyDown(with: e)
    }

    override func keyUp(with e: NSEvent) {
        if e.charactersIgnoringModifiers == " " && spaceDown {
            spaceDown = false
            refreshCursor()
            return
        }
        if tool?.keyUp(e) == true { return }
        super.keyUp(with: e)
    }

    override func flagsChanged(with e: NSEvent) {
        tool?.flagsChanged(e.modifierFlags)
        refreshCursor()
        super.flagsChanged(with: e)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateFrame()
    }
}
