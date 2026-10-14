import AppKit

/// Keeps the floating windows attached to the corner of the canvas area they sit in, like Paint.NET: when the main
/// window is resized (or the tool bar wraps onto another row) they follow their corner, stay inside the canvas area,
/// and the resizable ones (History, Layers) get shorter when there is not enough room, then grow back.
/// Moving or resizing a floating window by hand attaches it to its new nearest corner.
final class PanelLayout {
    private struct Anchor {
        var right: Bool
        var top: Bool
        /// Distance from the anchored vertical / horizontal edge of the canvas area.
        var dx: CGFloat
        var dy: CGFloat
        /// Placed inside the canvas area: kept inside it when the window shrinks.
        var inside: Bool
        /// Height chosen for a resizable window, restored when there is room again.
        var height: CGFloat
    }

    private let panels: [FloatingPanel]
    private let canvasFrame: () -> NSRect
    private var anchors: [ObjectIdentifier: Anchor] = [:]
    private var applying = false
    private var observers: [NSObjectProtocol] = []
    /// Room kept between a window and the opposite edge, or between two windows on the same side.
    private let gap: CGFloat = 8

    /// `canvasFrame` returns the canvas area in screen coordinates.
    init(panels: [FloatingPanel], canvasFrame: @escaping () -> NSRect) {
        self.panels = panels
        self.canvasFrame = canvasFrame
        let nc = NotificationCenter.default
        for p in panels {
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
                observers.append(nc.addObserver(forName: name, object: p, queue: .main) { [weak self, weak p] _ in
                    // Only the user's own dragging re-anchors a window: moves made by AppKit when the main window
                    // changes (zoom, full screen, its own live resize) or by `apply` must not.
                    guard let self, let p, !applying, NSEvent.pressedMouseButtons & 1 != 0,
                          p.parent?.inLiveResize != true else { return }
                    anchor(p)
                })
            }
        }
    }

    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    /// Attaches every window to its nearest corner, from where it is now.
    func anchorAll() {
        for p in panels { anchor(p) }
    }

    private func anchor(_ p: FloatingPanel) {
        let c = canvasFrame(), f = p.frame
        guard c.width > 0, c.height > 0 else { return }
        let right = f.midX > c.midX, top = f.midY > c.midY
        anchors[ObjectIdentifier(p)] = Anchor(right: right, top: top,
                                              dx: right ? c.maxX - f.maxX : f.minX - c.minX,
                                              dy: top ? c.maxY - f.maxY : f.minY - c.minY,
                                              inside: c.insetBy(dx: -2, dy: -2).contains(f), height: f.height)
    }

    /// Puts every window back at its corner of the current canvas area.
    func apply() {
        let c = canvasFrame()
        guard c.width > 0, c.height > 0 else { return }
        var frames: [(panel: FloatingPanel, anchor: Anchor, frame: NSRect)] = []
        for p in panels {
            guard let a = anchors[ObjectIdentifier(p)] else { continue }
            var f = p.frame
            if p.styleMask.contains(.resizable) {
                let room = a.inside ? c.height - a.dy - gap : a.height
                f.size.height = max(p.minSize.height, min(a.height, room))
            }
            f.origin.x = a.right ? c.maxX - a.dx - f.width : c.minX + a.dx
            f.origin.y = a.top ? c.maxY - a.dy - f.height : c.minY + a.dy
            if a.inside {
                // Inside the canvas area, but at its anchored edge when the window is too small for it.
                f.origin.x = a.right ? max(c.minX, min(f.minX, c.maxX - f.width)) : min(max(f.minX, c.minX), c.maxX - f.width)
                f.origin.y = a.top ? max(c.minY, min(f.minY, c.maxY - f.height)) : min(max(f.minY, c.minY), c.maxY - f.height)
            }
            frames.append((p, a, f))
        }
        separateStacked(&frames)
        applying = true
        defer { applying = false }
        for (p, _, f) in frames where f != p.frame { p.setFrame(f, display: true) }
    }

    /// A window at the top of a side and one at the bottom of the same side (History above Layers) must not overlap:
    /// the resizable ones get shorter, down to their minimum height.
    private func separateStacked(_ frames: inout [(panel: FloatingPanel, anchor: Anchor, frame: NSRect)]) {
        for i in frames.indices where frames[i].anchor.top && frames[i].anchor.inside {
            for j in frames.indices where !frames[j].anchor.top && frames[j].anchor.inside
                && frames[j].anchor.right == frames[i].anchor.right {
                let upper = frames[i].frame, lower = frames[j].frame
                guard upper.minX < lower.maxX, lower.minX < upper.maxX else { continue }
                var overlap = lower.maxY + gap - upper.minY
                guard overlap > 0 else { continue }
                if frames[i].panel.styleMask.contains(.resizable) {
                    let s = min(overlap, upper.height - frames[i].panel.minSize.height)
                    if s > 0 {
                        frames[i].frame.origin.y += s
                        frames[i].frame.size.height -= s
                        overlap -= s
                    }
                }
                if overlap > 0, frames[j].panel.styleMask.contains(.resizable) {
                    let s = min(overlap, lower.height - frames[j].panel.minSize.height)
                    if s > 0 { frames[j].frame.size.height -= s }
                }
            }
        }
    }

    /// Offsets of a window from its anchored corner as laid out now, and where they should be (for tests).
    func debugCheck(_ p: FloatingPanel) -> (actual: CGSize, expected: CGSize, inside: Bool)? {
        guard let a = anchors[ObjectIdentifier(p)] else { return nil }
        let c = canvasFrame(), f = p.frame
        let actual = CGSize(width: a.right ? c.maxX - f.maxX : f.minX - c.minX, height: a.top ? c.maxY - f.maxY : f.minY - c.minY)
        return (actual, CGSize(width: a.dx, height: a.dy), c.insetBy(dx: -2, dy: -2).contains(f))
    }
}
