import AppKit
import BrushwoodCore

/// Bottom status bar: tool hint, selection size, cursor position, units and zoom (Paint.NET layout).
final class StatusBar: NSView {
    weak var host: MainWindowController?
    private let hintIcon = NSImageView()
    private let hint = NSTextField(labelWithString: "")
    private let selectionIcon = NSImageView()
    private let selectionLabel = NSTextField(labelWithString: "")
    private let cursorIcon = NSImageView()
    private let cursorLabel = NSTextField(labelWithString: "")
    private let unitsPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let zoomSlider = NSSlider()
    private let zoomCombo = NSComboBox()
    private let progress = NSProgressIndicator()

    override init(frame: NSRect) {
        super.init(frame: frame)
        let small = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        for l in [hint, selectionLabel, cursorLabel] {
            l.font = small
            l.textColor = .secondaryLabelColor
            l.lineBreakMode = .byTruncatingTail
        }
        hint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        selectionIcon.image = Icons.image("tool.rectangleSelect", size: 14)
        cursorIcon.image = NSImage(systemSymbolName: "cursorarrow", accessibilityDescription: nil)
        for l in [selectionLabel, cursorLabel] {
            l.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
            l.translatesAutoresizingMaskIntoConstraints = false
            l.widthAnchor.constraint(greaterThanOrEqualToConstant: 90).isActive = true
        }
        unitsPopup.controlSize = .small
        unitsPopup.font = small
        for u in MeasurementUnit.allCases { unitsPopup.addItem(withTitle: u.name) }
        unitsPopup.selectItem(at: AppEnvironment.shared.units.rawValue)
        unitsPopup.onAction { [weak self] _ in
            AppEnvironment.shared.units = MeasurementUnit(rawValue: self?.unitsPopup.indexOfSelectedItem ?? 0) ?? .pixels
        }
        zoomSlider.controlSize = .small
        zoomSlider.minValue = log(0.01)
        zoomSlider.maxValue = log(36)
        zoomSlider.translatesAutoresizingMaskIntoConstraints = false
        zoomSlider.widthAnchor.constraint(equalToConstant: 120).isActive = true
        zoomSlider.onAction { [weak self] _ in
            guard let self else { return }
            var z = exp(self.zoomSlider.doubleValue)
            // Snap to presets near the thumb.
            if let near = CanvasView.zoomLevels.min(by: { abs(log($0) - log(z)) < abs(log($1) - log(z)) }),
               abs(log(near) - log(z)) < 0.06 { z = near }
            self.host?.canvas.setZoom(z)
        }
        zoomCombo.controlSize = .small
        zoomCombo.font = small
        zoomCombo.addItems(withObjectValues: ["3600%", "2400%", "1600%", "1200%", "800%", "400%", "300%", "200%", "175%", "150%",
                                              "125%", "100%", "66%", "50%", "33%", "25%", "16%", "12%", "8%", "6%", "4%", "3%",
                                              "2%", "1%", L("Window")])
        zoomCombo.numberOfVisibleItems = 14
        zoomCombo.translatesAutoresizingMaskIntoConstraints = false
        zoomCombo.widthAnchor.constraint(equalToConstant: 76).isActive = true
        zoomCombo.onAction { [weak self] _ in self?.zoomEntered() }
        progress.style = .bar
        progress.controlSize = .small
        progress.isIndeterminate = false
        progress.isHidden = true
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.widthAnchor.constraint(equalToConstant: 120).isActive = true

        let stack = NSStackView(views: [hintIcon, hint, progress, NSView(), selectionIcon, selectionLabel, cursorIcon, cursorLabel,
                                        unitsPopup, zoomSlider, zoomCombo])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        for v in [hintIcon, selectionIcon, cursorIcon] {
            v.translatesAutoresizingMaskIntoConstraints = false
            v.widthAnchor.constraint(equalToConstant: 16).isActive = true
            v.heightAnchor.constraint(equalToConstant: 16).isActive = true
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }

    private func zoomEntered() {
        let text = zoomCombo.stringValue.trimmingCharacters(in: CharacterSet(charactersIn: "% "))
        if text == L("Window") {
            host?.canvas.zoomToWindow()
        } else if let v = Double(text.replacingOccurrences(of: ",", with: ".")), v > 0 {
            host?.canvas.setZoom(v / 100)
        }
    }

    func setHint(icon: NSImage?, text: String) {
        hintIcon.image = icon
        hint.stringValue = text
        hint.toolTip = text
    }

    func setZoom(_ z: CGFloat) {
        zoomSlider.doubleValue = log(Double(z))
        let pct = z * 100
        zoomCombo.stringValue = pct >= 10 ? "\(Int(pct.rounded()))%" : String(format: "%.1f%%", pct)
    }

    func setCursor(_ text: String) { cursorLabel.stringValue = text }
    func setSelection(_ text: String) { selectionLabel.stringValue = text }

    func setProgress(_ value: Double?) {
        if let value {
            progress.isHidden = false
            progress.doubleValue = value * 100
        } else {
            progress.isHidden = true
        }
    }

    func syncUnits() { unitsPopup.selectItem(at: AppEnvironment.shared.units.rawValue) }
}
