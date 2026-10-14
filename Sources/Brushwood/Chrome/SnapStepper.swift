import AppKit

/// Brushwood Plus: a stepper with double chevrons, next to a value's ordinary stepper, that goes up or down to the next
/// multiple of `step` (1 → 5 → 10 → 15…, and 12 → 10 → 5 → 1). It is drawn like a small NSStepper, a little larger so
/// the double chevrons have room, and repeats while held.
final class SnapStepper: NSView {
    let up: NSButton
    let down: NSButton
    var onStep: ((_ up: Bool) -> Void)?

    init(upTooltip: String, downTooltip: String) {
        up = ChevronButton(pointingUp: true)
        down = ChevronButton(pointingUp: false)
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        for (button, tooltip, isUp) in [(up, upTooltip, true), (down, downTooltip, false)] {
            button.toolTip = tooltip
            button.setAccessibilityLabel(tooltip)
            // Repeats while held, as NSStepper does.
            button.isContinuous = true
            button.setPeriodicDelay(0.4, interval: 0.1)
            button.onAction { [weak self] _ in self?.onStep?(isUp) }
            button.translatesAutoresizingMaskIntoConstraints = false
            addSubview(button)
        }
        NSLayoutConstraint.activate([
            up.topAnchor.constraint(equalTo: topAnchor, constant: 0.5),
            up.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0.5),
            up.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -0.5),
            up.bottomAnchor.constraint(equalTo: centerYAnchor),
            down.topAnchor.constraint(equalTo: centerYAnchor),
            down.leadingAnchor.constraint(equalTo: up.leadingAnchor),
            down.trailingAnchor.constraint(equalTo: up.trailingAnchor),
            down.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -0.5),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    private static let size = NSSize(width: 18, height: 24)

    override var intrinsicContentSize: NSSize { Self.size }

    /// The bezel of a small NSStepper: a rounded tile with a line between its halves.
    override func draw(_ dirtyRect: NSRect) {
        let tile = bounds.insetBy(dx: 0.5, dy: 0.5)
        NSColor.labelColor.withAlphaComponent(0.08).setFill()
        NSBezierPath(roundedRect: tile, xRadius: 5, yRadius: 5).fill()
        NSColor.labelColor.withAlphaComponent(0.12).setFill()
        backingAlignedRect(NSRect(x: tile.minX + 2.5, y: bounds.midY - 0.5, width: tile.width - 5, height: 1),
                           options: .alignAllEdgesNearest).fill()
    }

    /// The next multiple of `step` above `value` (or below it), kept within `range`.
    static func snapped(_ value: Double, step: Double, up: Bool, range: ClosedRange<Double>) -> Double {
        let k = value / step
        let target = up ? ((k + 1e-9).rounded(.down) + 1) * step : ((k - 1e-9).rounded(.up) - 1) * step
        return min(max(target, range.lowerBound), range.upperBound)
    }
}

/// One half of a SnapStepper: two chevrons in the color of text, on a darker tile while pressed.
private final class ChevronButton: NSButton {
    private let pointingUp: Bool

    init(pointingUp: Bool) {
        self.pointingUp = pointingUp
        super.init(frame: .zero)
        isBordered = false
        title = ""
        setButtonType(.momentaryChange)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted {
            NSColor.labelColor.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        }
        // Chevrons 7 points wide and 2.5 high, 3.4 apart (clear of each other), centered in the half.
        let width: CGFloat = 7, height: CGFloat = 2.5, gap: CGFloat = 3.4
        let tip: CGFloat = pointingUp == isFlipped ? -1 : 1
        let chevrons = NSBezierPath()
        for i in 0..<2 {
            let y = bounds.midY + (CGFloat(i) - 0.5) * gap
            chevrons.move(to: NSPoint(x: bounds.midX - width / 2, y: y - tip * height / 2))
            chevrons.line(to: NSPoint(x: bounds.midX, y: y + tip * height / 2))
            chevrons.line(to: NSPoint(x: bounds.midX + width / 2, y: y - tip * height / 2))
        }
        chevrons.lineWidth = 1.3
        chevrons.lineCapStyle = .round
        chevrons.lineJoinStyle = .round
        (isEnabled ? NSColor.labelColor : NSColor.tertiaryLabelColor).setStroke()
        chevrons.stroke()
    }
}
