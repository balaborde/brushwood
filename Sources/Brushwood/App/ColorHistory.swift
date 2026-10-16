import AppKit
import BrushwoodCore

extension Notification.Name {
    static let colorHistoryChanged = Notification.Name("BrushwoodColorHistoryChanged")
}

/// Brushwood Plus: the last colors painted with, newest first, shown under the palette of the Colors window and kept
/// between launches. A color joins once a step painted with it is in the History window, so colors only tried in
/// the color wheel, or dragged through, stay out.
enum ColorHistory {
    /// As many as the expanded Colors window shows; the compact one shows the first 16.
    static let limit = 26
    private static let key = "colorHistory"

    private(set) static var colors: [ColorBgra] =
        UserDefaults.standard.stringArray(forKey: key)?.compactMap { ColorBgra(hex: $0) } ?? []

    /// Colors read by the current tool since the last step (the last one of each slot), and since when.
    private static var pending: [(secondary: Bool, color: ColorBgra)] = []
    private static var pendingSince: Date?

    /// A tool paints with the primary (or secondary) color: it joins the history with the step it makes.
    static func noteUse(_ color: ColorBgra, secondary: Bool) {
        guard PlusFeature.colorHistory.isEnabled else { return }
        if pendingSince == nil { pendingSince = Date() }
        pending.removeAll { $0.secondary == secondary }
        pending.append((secondary, color))
    }

    /// Called when the active image's history changes. A new step brings in the colors it was painted with;
    /// undoing and redoing (older steps) do not.
    static func historyChanged(_ history: HistoryStack) {
        guard let since = pendingSince, let item = history.currentItem, item.date >= since,
              history.currentIndex == history.items.count - 1 else { return }
        let used = pending.map(\.color)
        pending = []
        pendingSince = nil
        guard PlusFeature.colorHistory.isEnabled else { return }
        // The first color read leads (the one of the button painted with).
        var list = colors
        for c in used.reversed() {
            list.removeAll { $0 == c }
            list.insert(c, at: 0)
        }
        set(Array(list.prefix(limit)))
    }

    static func clear() { set([]) }

    private static func set(_ list: [ColorBgra]) {
        guard list != colors else { return }
        colors = list
        UserDefaults.standard.set(list.map(\.hexString), forKey: key)
        NotificationCenter.default.post(name: .colorHistoryChanged, object: nil)
    }
}

/// The color history under the palette: a clock, then the colors, newest at the left. Click a color for the color
/// being edited, right-click (or Control-click) it for the other one, as with the palette.
final class ColorHistoryView: NSView {
    /// (color, toInactiveSlot)
    var onPick: ((ColorBgra, Bool) -> Void)?
    static let height: CGFloat = 28
    private let cell = NSSize(width: 23, height: 18)
    private let firstX: CGFloat = 40
    /// Room kept at the right, as at the right of the palette.
    private let rightMargin: CGFloat = 11

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        NotificationCenter.default.addObserver(forName: .colorHistoryChanged, object: nil, queue: .main) { [weak self] _ in
            self?.needsDisplay = true
            self?.updateToolTips()
        }
        updateToolTips()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func rect(_ i: Int) -> NSRect {
        NSRect(x: firstX + CGFloat(i) * cell.width, y: (bounds.height - cell.height) / 2, width: cell.width + 1,
               height: cell.height)
    }

    /// As many colors as the width holds: the bar gets longer with the Colors window when it is expanded.
    var visibleCount: Int { max(0, min(ColorHistory.limit, Int((bounds.width - firstX - rightMargin) / cell.width))) }

    private var iconRect: NSRect { NSRect(x: 14, y: (bounds.height - 16) / 2, width: 16, height: 16) }

    override func draw(_ dirtyRect: NSRect) {
        let icon = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
        if let icon {
            let tinted = NSImage(size: icon.size, flipped: false) { r in
                icon.draw(in: r)
                NSColor.secondaryLabelColor.set()
                r.fill(using: .sourceAtop)
                return true
            }
            let s = tinted.size, r = iconRect
            tinted.draw(in: NSRect(x: r.midX - s.width / 2, y: r.midY - s.height / 2, width: s.width, height: s.height))
        }
        let colors = ColorHistory.colors
        for i in 0..<visibleCount {
            let r = rect(i)
            guard i < colors.count else {
                // Room for colors still to come.
                NSColor.separatorColor.setStroke()
                NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)).stroke()
                continue
            }
            let c = colors[i]
            if c.a < 255 { Checkerboard.draw(in: r, cell: 3) }
            c.nsColor.setFill()
            r.fill(using: .sourceOver)
            NSColor(white: 0.35, alpha: 1).setStroke()
            NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)).stroke()
        }
    }

    private func updateToolTips() {
        removeAllToolTips()
        addToolTip(iconRect, owner: self, userData: nil)
        for i in 0..<visibleCount { addToolTip(rect(i), owner: self, userData: nil) }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateToolTips()
        needsDisplay = true
    }

    private func index(at point: NSPoint) -> Int? {
        let i = Int(floor((point.x - firstX) / cell.width))
        guard point.x >= firstX, i >= 0, i < min(visibleCount, ColorHistory.colors.count), rect(i).insetBy(dx: 0, dy: -2).contains(point)
        else { return nil }
        return i
    }

    override func mouseDown(with e: NSEvent) {
        guard let i = index(at: convert(e.locationInWindow, from: nil)) else { return }
        onPick?(ColorHistory.colors[i], e.modifierFlags.contains(.control))
    }

    override func rightMouseDown(with e: NSEvent) {
        guard let i = index(at: convert(e.locationInWindow, from: nil)) else { return }
        onPick?(ColorHistory.colors[i], true)
    }

    /// For UI tests: the middle of the i-th color, in window coordinates.
    func debugPoint(of i: Int) -> NSPoint { convert(NSPoint(x: rect(i).midX, y: rect(i).midY), to: nil) }
}

extension ColorHistoryView: NSViewToolTipOwner {
    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?)
        -> String {
        if let i = index(at: point) { return "#" + ColorHistory.colors[i].hexString }
        return L("Color History: the last colors you painted with. Click one for the primary color, right-click it for the secondary color.")
    }
}
