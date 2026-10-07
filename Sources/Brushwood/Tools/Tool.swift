import AppKit
import BrushwoodCore

/// Base class of all tools. Tools receive mouse/keyboard input from the canvas and edit the active document.
class Tool {
    let kind: ToolKind
    unowned let canvas: CanvasView

    init(kind: ToolKind, canvas: CanvasView) {
        self.kind = kind
        self.canvas = canvas
    }

    var workspace: DocumentWorkspace { canvas.workspace! }
    var doc: Document { workspace.document }
    var env: AppEnvironment { .shared }
    var settings: ToolSettings { env.tools }

    /// True while the tool holds uncommitted, still-editable content (shapes, text, moved pixels...).
    var hasPendingEdits: Bool { false }
    var hidesSelectionOutline: Bool { false }
    var showsBrushOutline: Bool { false }

    func activate() {}

    /// Called when switching away from the tool or document.
    func deactivate() {
        commit()
    }

    /// Finalizes pending edits into the history.
    func commit() {}

    /// Discards pending edits.
    func cancel() {}

    func mouseDown(_ e: ToolEvent) {}
    func mouseDragged(_ e: ToolEvent) {}
    func mouseUp(_ e: ToolEvent) {}
    func mouseMoved(_ e: ToolEvent) {}
    func keyDown(_ e: NSEvent) -> Bool { false }
    func keyUp(_ e: NSEvent) -> Bool { false }
    func flagsChanged(_ flags: NSEvent.ModifierFlags) {}
    func drawOverlay(_ ctx: CGContext) {}
    func settingsChanged() {}
    func colorsChanged() {}

    func cursor(atView p: CGPoint) -> NSCursor { ToolCursors.cursor(for: kind) }

    // MARK: Helpers

    func color(for button: ToolEvent.Button) -> ColorBgra {
        button == .left ? env.primaryColor : env.secondaryColor
    }

    func otherColor(for button: ToolEvent.Button) -> ColorBgra {
        button == .left ? env.secondaryColor : env.primaryColor
    }

    var selectionClip: MaskSurface? {
        doc.selectionMask(antialias: settings.selectionClippingAntialiased)
    }

    func setStatus(_ s: String?) {
        canvas.host?.setToolStatus(s)
    }
}

// MARK: - Cursors

enum ToolCursors {
    private static var cache: [ToolKind: NSCursor] = [:]

    /// Crosshair with the tool icon at the lower right, like Paint.NET's tool cursors.
    static func cursor(for kind: ToolKind) -> NSCursor {
        if let c = cache[kind] { return c }
        let c: NSCursor
        switch kind {
        case .pan: c = .openHand
        case .moveSelectedPixels, .moveSelection: c = .arrow
        case .text: c = .iBeam
        default:
            let size = NSSize(width: 32, height: 32)
            let icon = Icons.image(kind.icon, size: 16)
            let img = NSImage(size: size, flipped: true) { _ in
                let hot = NSPoint(x: 8, y: 8)
                let lines = NSBezierPath()
                lines.move(to: NSPoint(x: hot.x - 6, y: hot.y)); lines.line(to: NSPoint(x: hot.x - 2, y: hot.y))
                lines.move(to: NSPoint(x: hot.x + 2, y: hot.y)); lines.line(to: NSPoint(x: hot.x + 6, y: hot.y))
                lines.move(to: NSPoint(x: hot.x, y: hot.y - 6)); lines.line(to: NSPoint(x: hot.x, y: hot.y - 2))
                lines.move(to: NSPoint(x: hot.x, y: hot.y + 2)); lines.line(to: NSPoint(x: hot.x, y: hot.y + 6))
                lines.lineWidth = 3
                NSColor.white.setStroke()
                lines.stroke()
                lines.lineWidth = 1
                NSColor.black.setStroke()
                lines.stroke()
                icon.draw(in: NSRect(x: 13, y: 13, width: 16, height: 16), from: .zero, operation: .sourceOver,
                          fraction: 1, respectFlipped: true, hints: nil)
                return true
            }
            c = NSCursor(image: img, hotSpot: NSPoint(x: 8, y: 8))
        }
        cache[kind] = c
        return c
    }

    static let move: NSCursor = .openHand
    static let resizeDiagonal: NSCursor = .crosshair

    static let rotate: NSCursor = {
        let img = NSImage(size: NSSize(width: 24, height: 24), flipped: false) { r in
            let arc = NSBezierPath()
            arc.appendArc(withCenter: NSPoint(x: 12, y: 12), radius: 7, startAngle: 30, endAngle: 300)
            arc.lineWidth = 3.5
            NSColor.white.setStroke(); arc.stroke()
            arc.lineWidth = 1.5
            NSColor.black.setStroke(); arc.stroke()
            _ = r
            return true
        }
        return NSCursor(image: img, hotSpot: NSPoint(x: 12, y: 12))
    }()
}

// MARK: - Compositing helpers shared by painting tools

enum Compositor {
    /// dst[x] = blend(src[x], color, coverage × clip) over `rect`. `src` may be the same surface as `dst`.
    /// Set while a tool renders with Paint.NET's "Overwrite" option.
    static var overwrite: Bool { AppEnvironment.shared.tools.overwrite }

    static func apply(color: ColorBgra, mask: MaskSurface, rect: IntRect, src: Surface, dst: Surface, mode: BlendMode,
                      clip: MaskSurface?) {
        let r = rect.intersection(dst.bounds)
        if r.isEmpty { return }
        if overwrite {
            for y in r.top..<r.bottom {
                let m = mask.row(y), s = src.row(y), d = dst.row(y)
                let c = clip?.row(y)
                for x in r.left..<r.right {
                    var cov = Int(m[x])
                    if let c { cov = mul255(cov, Int(c[x])) }
                    d[x] = cov == 0 ? s[x] : Blender.lerpTo(s[x], color, coverage: cov)
                }
            }
            return
        }
        for y in r.top..<r.bottom {
            let m = mask.row(y), s = src.row(y), d = dst.row(y)
            let c = clip?.row(y)
            for x in r.left..<r.right {
                var cov = Int(m[x])
                if let c { cov = mul255(cov, Int(c[x])) }
                d[x] = cov == 0 ? s[x] : Blender.blend(mode, s[x], color, opacity: cov)
            }
        }
    }

    /// Pattern fill (hatch): foreground/background chosen per pixel.
    static func apply(style: FillStyle, foreground: ColorBgra, background: ColorBgra, mask: MaskSurface, rect: IntRect,
                      src: Surface, dst: Surface, mode: BlendMode, clip: MaskSurface?) {
        let overwrite = Self.overwrite
        if style == .solid {
            apply(color: foreground, mask: mask, rect: rect, src: src, dst: dst, mode: mode, clip: clip)
            return
        }
        let pat = style.pattern
        let r = rect.intersection(dst.bounds)
        if r.isEmpty { return }
        for y in r.top..<r.bottom {
            let m = mask.row(y), s = src.row(y), d = dst.row(y)
            let c = clip?.row(y)
            for x in r.left..<r.right {
                var cov = Int(m[x])
                if let c { cov = mul255(cov, Int(c[x])) }
                if cov == 0 { d[x] = s[x]; continue }
                let col = FillStyle.isForeground(pat, x: x, y: y) ? foreground : background
                d[x] = overwrite ? Blender.lerpTo(s[x], col, coverage: cov) : Blender.blend(mode, s[x], col, opacity: cov)
            }
        }
    }
}

/// Utility: CGPath helpers for strokes with arrow caps and dashes, rasterized to masks.
enum PathRasterizer {
    /// Renders an outline (stroke) of `path` into `mask` (y-down image space).
    static func stroke(_ path: CGPath, into mask: MaskSurface, width: CGFloat, antialias: Bool, dash: [CGFloat] = [],
                       cap: CGLineCap = .round, join: CGLineJoin = .round) {
        mask.draw(antialias: antialias) { ctx in
            ctx.setStrokeColor(gray: 1, alpha: 1)
            ctx.setLineWidth(width)
            ctx.setLineCap(cap)
            ctx.setLineJoin(join)
            if !dash.isEmpty { ctx.setLineDash(phase: 0, lengths: dash) }
            ctx.addPath(path)
            ctx.strokePath()
        }
    }

    static func fill(_ path: CGPath, into mask: MaskSurface, antialias: Bool, rule: CGPathFillRule = .winding) {
        mask.draw(antialias: antialias) { ctx in
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.addPath(path)
            ctx.fillPath(using: rule)
        }
    }

    static func clear(_ mask: MaskSurface, rect: IntRect) {
        let r = rect.intersection(mask.bounds)
        if r.isEmpty { return }
        for y in r.top..<r.bottom { (mask.row(y) + r.left).update(repeating: 0, count: r.width) }
    }
}
