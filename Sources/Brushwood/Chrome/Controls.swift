import AppKit
import BrushwoodCore

/// Flat toolbar button with an icon, tooltip and hover highlight (Paint.NET-style).
final class ToolbarButton: NSButton {
    private var hovering = false
    private var tracking: NSTrackingArea?
    var isToggled = false { didSet { needsDisplay = true } }

    init(icon: String, tooltip: String, target: AnyObject?, action: Selector?, size: CGFloat = 24) {
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        image = Icons.image(icon, size: 16)
        imagePosition = .imageOnly
        isBordered = false
        bezelStyle = .regularSquare
        toolTip = tooltip
        self.target = target
        self.action = action
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: size).isActive = true
        heightAnchor.constraint(equalToConstant: size).isActive = true
        setAccessibilityLabel(tooltip)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 1, dy: 1)
        if isToggled || (hovering && isEnabled) || (isHighlighted && isEnabled) {
            let p = NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4)
            (isToggled ? NSColor.controlAccentColor.withAlphaComponent(isHighlighted ? 0.4 : 0.25)
                : NSColor.labelColor.withAlphaComponent(isHighlighted ? 0.18 : 0.09)).setFill()
            p.fill()
            if isToggled {
                NSColor.controlAccentColor.withAlphaComponent(0.6).setStroke()
                p.lineWidth = 1
                p.stroke()
            }
        }
        if let image {
            let s = image.size
            let ir = NSRect(x: bounds.midX - s.width / 2, y: bounds.midY - s.height / 2, width: s.width, height: s.height)
            image.draw(in: ir, from: .zero, operation: .sourceOver, fraction: isEnabled ? 1 : 0.35, respectFlipped: true, hints: nil)
        }
    }
}

/// Vertical separator line for toolbars.
final class ToolbarSeparator: NSBox {
    init() {
        super.init(frame: .zero)
        boxType = .separator
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 1).isActive = true
        heightAnchor.constraint(equalToConstant: 20).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }
}

func toolbarLabel(_ s: String) -> NSTextField {
    let l = NSTextField(labelWithString: s)
    l.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    l.textColor = .secondaryLabelColor
    l.setContentCompressionResistancePriority(.required, for: .horizontal)
    return l
}

/// Closure-based target for controls built in code.
final class ActionTrampoline: NSObject {
    let handler: (Any) -> Void

    init(_ handler: @escaping (Any) -> Void) {
        self.handler = handler
    }

    @objc func fire(_ sender: Any) { handler(sender) }
}

private var trampolineKey: UInt8 = 0

extension NSControl {
    /// Attaches a closure as the control's action (retained by the control).
    func onAction(_ handler: @escaping (Any) -> Void) {
        let t = ActionTrampoline(handler)
        objc_setAssociatedObject(self, &trampolineKey, t, .OBJC_ASSOCIATION_RETAIN)
        target = t
        action = #selector(ActionTrampoline.fire(_:))
    }
}

extension NSMenuItem {
    func onAction(_ handler: @escaping (Any) -> Void) {
        let t = ActionTrampoline(handler)
        objc_setAssociatedObject(self, &trampolineKey, t, .OBJC_ASSOCIATION_RETAIN)
        target = t
        action = #selector(ActionTrampoline.fire(_:))
    }
}

/// Slider + editable number field + optional reset, used by dialogs and option bars.
final class NumericSliderControl: NSStackView {
    let slider = NSSlider()
    let field = NSTextField()
    private let stepper = NSStepper()
    private var resetButton: NSButton?
    let defaultValue: Double
    let decimals: Int
    var onChange: ((Double) -> Void)?
    /// Non-linear mapping for wide ranges (slider acts on sqrt scale).
    private let curved: Bool
    private let range: ClosedRange<Double>

    init(range: ClosedRange<Double>, value: Double, decimals: Int = 0, defaultValue: Double? = nil, showReset: Bool = true,
         sliderWidth: CGFloat = 200, curved: Bool = false) {
        self.range = range
        self.defaultValue = defaultValue ?? value
        self.decimals = decimals
        self.curved = curved
        super.init(frame: .zero)
        orientation = .horizontal
        spacing = 6
        slider.minValue = 0
        slider.maxValue = 1
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: sliderWidth).isActive = true
        slider.controlSize = .small
        slider.isContinuous = true
        slider.onAction { [weak self] _ in self?.sliderMoved() }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = decimals
        f.maximumFractionDigits = decimals
        f.minimum = NSNumber(value: range.lowerBound)
        f.maximum = NSNumber(value: range.upperBound)
        f.usesGroupingSeparator = false
        field.formatter = f
        field.alignment = .right
        field.controlSize = .small
        field.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 58).isActive = true
        field.onAction { [weak self] _ in self?.fieldEdited() }
        stepper.minValue = range.lowerBound
        stepper.maxValue = range.upperBound
        stepper.increment = decimals == 0 ? 1 : pow(10, -Double(decimals))
        stepper.valueWraps = false
        stepper.controlSize = .small
        stepper.onAction { [weak self] _ in
            guard let self else { return }
            self.setValue(self.stepper.doubleValue, notify: true)
        }
        addArrangedSubview(slider)
        addArrangedSubview(field)
        addArrangedSubview(stepper)
        if showReset {
            let b = NSButton(image: NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: L("Reset"))!,
                             target: nil, action: nil)
            b.isBordered = false
            b.toolTip = L("Reset")
            b.onAction { [weak self] _ in
                guard let self else { return }
                self.setValue(self.defaultValue, notify: true)
            }
            addArrangedSubview(b)
            resetButton = b
        }
        setValue(value, notify: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    private(set) var value: Double = 0

    private func toSlider(_ v: Double) -> Double {
        let t = (v - range.lowerBound) / max(1e-9, range.upperBound - range.lowerBound)
        return curved ? sqrt(max(0, t)) : t
    }

    private func fromSlider(_ s: Double) -> Double {
        let t = curved ? s * s : s
        return range.lowerBound + t * (range.upperBound - range.lowerBound)
    }

    func setValue(_ v: Double, notify: Bool) {
        let scale = pow(10, Double(decimals))
        value = (clampDouble(v, range.lowerBound, range.upperBound) * scale).rounded() / scale
        slider.doubleValue = toSlider(value)
        field.doubleValue = value
        stepper.doubleValue = value
        if notify { onChange?(value) }
    }

    private func sliderMoved() {
        setValue(fromSlider(slider.doubleValue), notify: true)
    }

    private func fieldEdited() {
        setValue(field.doubleValue, notify: true)
    }
}

/// A square color swatch that opens a color picker on click.
final class ColorSwatchButton: NSView {
    var color: ColorBgra { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?

    init(color: ColorBgra) {
        self.color = color
        super.init(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 1, dy: 1)
        Checkerboard.draw(in: r, cell: 4)
        color.nsColor.setFill()
        r.fill(using: .sourceOver)
        NSColor.separatorColor.setStroke()
        NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)).stroke()
    }

    override func mouseDown(with event: NSEvent) { onClick?() }
}
