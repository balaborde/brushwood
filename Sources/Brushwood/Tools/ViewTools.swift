import AppKit
import BrushwoodCore

final class ZoomTool: Tool {
    private var start: CGPoint?
    private var current: CGPoint?
    private var button: ToolEvent.Button = .left

    override func mouseDown(_ e: ToolEvent) {
        start = e.viewPoint
        current = e.viewPoint
        button = e.button
    }

    override func mouseDragged(_ e: ToolEvent) {
        current = e.viewPoint
        canvas.needsDisplay = true
    }

    override func mouseUp(_ e: ToolEvent) {
        defer {
            start = nil
            current = nil
            canvas.needsDisplay = true
        }
        guard let s = start else { return }
        let r = CGRect(corner: s, corner: e.viewPoint)
        if r.width > 4 && r.height > 4 && button == .left {
            canvas.zoomToRect(CGRect(corner: canvas.toImage(r.origin), corner: canvas.toImage(CGPoint(x: r.maxX, y: r.maxY))))
        } else if button == .left {
            canvas.zoomIn(anchorView: e.viewPoint)
        } else {
            canvas.zoomOut(anchorView: e.viewPoint)
        }
    }

    override func drawOverlay(_ ctx: CGContext) {
        guard let s = start, let c = current else { return }
        let r = CGRect(corner: s, corner: c)
        ctx.saveGState()
        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setLineDash(phase: 0, lengths: [3, 3])
        ctx.stroke(r)
        ctx.restoreGState()
    }
}

final class PanTool: Tool {
    private var start: (mouse: CGPoint, origin: CGPoint)?

    override func mouseDown(_ e: ToolEvent) {
        guard let clip = canvas.clipView, let w = canvas.window else { return }
        let m = w.mouseLocationOutsideOfEventStream
        start = (m, clip.bounds.origin)
        NSCursor.closedHand.set()
    }

    override func mouseDragged(_ e: ToolEvent) {
        guard let s = start, let clip = canvas.clipView, let w = canvas.window else { return }
        let m = w.mouseLocationOutsideOfEventStream
        canvas.pan(to: NSPoint(x: s.origin.x - (m.x - s.mouse.x), y: s.origin.y + (m.y - s.mouse.y)), clip: clip)
    }

    override func mouseUp(_ e: ToolEvent) {
        start = nil
        NSCursor.openHand.set()
    }

    override func cursor(atView p: CGPoint) -> NSCursor { start == nil ? .openHand : .closedHand }
}

final class ColorPickerTool: Tool {
    private var flattened: Surface?

    private func sample(_ e: ToolEvent) {
        let p = e.intPoint
        guard doc.bounds.contains(x: p.x, y: p.y) else { return }
        let surface: Surface
        if settings.colorPickerSampling == .image {
            if flattened == nil { flattened = doc.flattened() }
            surface = flattened!
        } else {
            surface = doc.activeLayer.surface
        }
        let n = settings.colorPickerSampleSize.rawValue
        let c: ColorBgra
        if n == 1 {
            c = surface[p.x, p.y]
        } else {
            var colors: [ColorBgra] = []
            for y in (p.y - n / 2)...(p.y + n / 2) {
                for x in (p.x - n / 2)...(p.x + n / 2) where surface.bounds.contains(x: x, y: y) {
                    colors.append(surface[x, y])
                }
            }
            c = ColorBgra.blend(colors, weights: Array(repeating: 1, count: colors.count))
        }
        if e.button == .left { env.primaryColor = c } else { env.secondaryColor = c }
    }

    override func mouseDown(_ e: ToolEvent) {
        flattened = nil
        sample(e)
    }

    override func mouseDragged(_ e: ToolEvent) {
        sample(e)
    }

    override func mouseUp(_ e: ToolEvent) {
        flattened = nil
        switch settings.colorPickerAfterClick {
        case .doNotSwitch: break
        case .switchToPrevious: canvas.host?.selectTool(env.previousTool)
        case .switchToPencil: canvas.host?.selectTool(.pencil)
        }
    }
}
