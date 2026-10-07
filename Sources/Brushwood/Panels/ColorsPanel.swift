import AppKit
import BrushwoodCore
import UniformTypeIdentifiers

/// Paint.NET-style Colors window: primary/secondary selector, HSV color wheel, 96-color palette and,
/// when expanded ("More"), hex/RGB/HSV/alpha controls.
final class ColorsPanel: FloatingPanel {
    private let content = FlippedView()
    private let targetPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let swatches = PrimarySecondaryView()
    private let wheel = ColorWheelView()
    private let valueSlider = ColorComponentSlider()
    private let paletteView = PaletteView()
    private let moreButton = NSButton(title: "", target: nil, action: nil)
    private let paletteMenuButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private let expanded = FlippedView()
    private let hexField = NSTextField()
    private var sliders: [(ColorComponentSlider, NSTextField)] = []
    private var editingSecondary = false
    private var isExpanded = false
    private var observers: [NSObjectProtocol] = []
    private var updating = false
    /// Last hue/saturation chosen, kept when the color becomes gray/black (so the wheel doesn't jump).
    private var lastHSV = HsvColor(hue: 0, saturation: 0, value: 0)

    private let compactWidth: CGFloat = 420
    private let expandedWidth: CGFloat = 660
    private let height: CGFloat = 196

    var env: AppEnvironment { .shared }

    init() {
        super.init(title: L("Colors"), size: NSSize(width: 420, height: 196), resizable: false)
        contentView = content
        build()
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: .colorsChanged, object: nil, queue: .main) { [weak self] _ in self?.sync() })
        observers.append(nc.addObserver(forName: .paletteChanged, object: nil, queue: .main) { [weak self] _ in
            self?.paletteView.needsDisplay = true
        })
        sync()
    }

    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    private var currentColor: ColorBgra {
        get { editingSecondary ? env.secondaryColor : env.primaryColor }
        set {
            if editingSecondary { env.secondaryColor = newValue } else { env.primaryColor = newValue }
        }
    }

    private func build() {
        targetPopup.addItems(withTitles: [L("Primary"), L("Secondary")])
        targetPopup.controlSize = .small
        targetPopup.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        targetPopup.frame = NSRect(x: 8, y: 8, width: 96, height: 22)
        targetPopup.onAction { [weak self] _ in
            self?.editingSecondary = self?.targetPopup.indexOfSelectedItem == 1
            self?.sync()
        }
        content.addSubview(targetPopup)

        swatches.frame = NSRect(x: 14, y: 40, width: 84, height: 84)
        swatches.onSelect = { [weak self] secondary in
            self?.editingSecondary = secondary
            self?.targetPopup.selectItem(at: secondary ? 1 : 0)
            self?.sync()
        }
        content.addSubview(swatches)

        moreButton.bezelStyle = .rounded
        moreButton.controlSize = .small
        moreButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        moreButton.frame = NSRect(x: 8, y: 160, width: 96, height: 24)
        moreButton.onAction { [weak self] _ in self?.toggleExpanded() }
        content.addSubview(moreButton)

        wheel.frame = NSRect(x: 112, y: 8, width: 150, height: 150)
        wheel.onChange = { [weak self] h, s, inactive in
            guard let self else { return }
            var hsv = self.lastHSV
            hsv.hue = h
            hsv.saturation = s
            if hsv.value == 0 { hsv.value = 100 }
            if inactive {
                // Right-click loads the color into the inactive slot.
                let target = !self.editingSecondary
                let c = hsv.toColor(alpha: (target ? self.env.secondaryColor : self.env.primaryColor).a)
                if target { self.env.secondaryColor = c } else { self.env.primaryColor = c }
                return
            }
            self.lastHSV = hsv
            self.currentColor = hsv.toColor(alpha: self.currentColor.a)
        }
        content.addSubview(wheel)

        valueSlider.frame = NSRect(x: 112, y: 166, width: 150, height: 18)
        valueSlider.onChange = { [weak self] v in
            guard let self else { return }
            var hsv = self.lastHSV
            hsv.value = v * 100
            self.lastHSV = hsv
            self.currentColor = hsv.toColor(alpha: self.currentColor.a)
        }
        valueSlider.toolTip = L("Value")
        content.addSubview(valueSlider)

        layoutPalette()
        paletteView.onPick = { [weak self] color, inactive in
            guard let self else { return }
            let secondary = inactive ? !self.editingSecondary : self.editingSecondary
            if secondary { self.env.secondaryColor = color } else { self.env.primaryColor = color }
        }
        paletteView.onStore = { [weak self] index in
            guard let self else { return }
            var p = self.env.palette
            p[index] = self.currentColor
            self.env.palette = p
        }
        content.addSubview(paletteView)

        paletteMenuButton.controlSize = .small
        paletteMenuButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        paletteMenuButton.addItem(withTitle: L("Palette"))
        paletteMenuButton.lastItem?.image = Icons.image("cmd.paletteOpen", size: 14)
        let load = NSMenuItem(title: L("Open Palette…"), action: nil, keyEquivalent: "")
        load.onAction { [weak self] _ in self?.loadPalette() }
        let save = NSMenuItem(title: L("Save Palette As…"), action: nil, keyEquivalent: "")
        save.onAction { [weak self] _ in self?.savePalette() }
        let reset = NSMenuItem(title: L("Reset to Default"), action: nil, keyEquivalent: "")
        reset.onAction { [weak self] _ in self?.env.palette = AppEnvironment.defaultPalette }
        paletteMenuButton.menu?.addItem(load)
        paletteMenuButton.menu?.addItem(save)
        paletteMenuButton.menu?.addItem(.separator())
        paletteMenuButton.menu?.addItem(reset)
        paletteMenuButton.frame = NSRect(x: 272, y: 168, width: 137, height: 20)
        paletteMenuButton.toolTip = L("Left-click a swatch to set the primary color, right-click for the secondary color. Shift-click stores the current color.")
        content.addSubview(paletteMenuButton)

        buildExpanded()
    }

    private func buildExpanded() {
        expanded.frame = NSRect(x: compactWidth - 4, y: 0, width: expandedWidth - compactWidth + 4, height: height)
        expanded.isHidden = true
        content.addSubview(expanded)
        let hexLabel = NSTextField(labelWithString: L("Hex:"))
        hexLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hexLabel.frame = NSRect(x: 8, y: 10, width: 40, height: 16)
        expanded.addSubview(hexLabel)
        hexField.controlSize = .small
        hexField.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        hexField.frame = NSRect(x: 48, y: 8, width: 80, height: 20)
        hexField.onAction { [weak self] _ in
            guard let self, let c = ColorBgra(hex: self.hexField.stringValue) else { return }
            self.currentColor = c
        }
        expanded.addSubview(hexField)
        let rows: [(String, Int)] = [("R", 0), ("G", 1), ("B", 2), ("H", 3), ("S", 4), ("V", 5), ("A", 6)]
        for (label, idx) in rows {
            let y = CGFloat(36 + idx * 22)
            let l = NSTextField(labelWithString: label)
            l.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
            l.frame = NSRect(x: 8, y: y + 1, width: 14, height: 16)
            expanded.addSubview(l)
            let slider = ColorComponentSlider()
            slider.frame = NSRect(x: 24, y: y, width: 150, height: 18)
            expanded.addSubview(slider)
            let field = NSTextField()
            field.controlSize = .small
            field.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
            field.alignment = .right
            field.frame = NSRect(x: 180, y: y - 1, width: 44, height: 20)
            expanded.addSubview(field)
            let maxV: Double = idx == 3 ? 360 : (idx == 4 || idx == 5 ? 100 : 255)
            slider.onChange = { [weak self] v in self?.componentChanged(idx, v * maxV) }
            field.onAction { [weak self] _ in self?.componentChanged(idx, clampDouble(field.doubleValue, 0, maxV)) }
            sliders.append((slider, field))
        }
    }

    private func componentChanged(_ idx: Int, _ v: Double) {
        guard !updating else { return }
        var c = currentColor
        switch idx {
        case 0: c.r = clampToByte(v)
        case 1: c.g = clampToByte(v)
        case 2: c.b = clampToByte(v)
        case 6: c.a = clampToByte(v)
        default:
            var hsv = lastHSV
            if idx == 3 { hsv.hue = v } else if idx == 4 { hsv.saturation = v } else { hsv.value = v }
            lastHSV = hsv
            c = hsv.toColor(alpha: c.a)
        }
        currentColor = c
    }

    func debugToggleExpanded() { toggleExpanded() }

    /// Compact mode shows the first 32 palette colors; the expanded window shows all 96 (Paint.NET behaviour).
    private func layoutPalette() {
        if isExpanded {
            paletteView.rowHeight = 13
            paletteView.visibleCount = 96
        } else {
            paletteView.rowHeight = 39
            paletteView.visibleCount = 32
        }
        let rows = CGFloat(paletteView.visibleCount / paletteView.columns)
        paletteView.frame = NSRect(x: 272, y: 8, width: 8 * 17 + 1, height: rows * paletteView.rowHeight + 1)
        paletteView.needsDisplay = true
    }

    private func toggleExpanded() {
        isExpanded.toggle()
        expanded.isHidden = !isExpanded
        var f = frame
        let newWidth = isExpanded ? expandedWidth : compactWidth
        let contentRect = contentRect(forFrameRect: f)
        let newContent = NSRect(x: contentRect.minX, y: contentRect.minY, width: newWidth, height: contentRect.height)
        f = frameRect(forContentRect: newContent)
        setFrame(f, display: true, animate: false)
        layoutPalette()
        sync()
    }

    private func sync() {
        updating = true
        defer { updating = false }
        moreButton.title = isExpanded ? L("Less «") : L("More »")
        swatches.primary = env.primaryColor
        swatches.secondary = env.secondaryColor
        swatches.editingSecondary = editingSecondary
        let c = currentColor
        let hsv = HsvColor(c)
        // Keep hue/saturation stable for achromatic colors.
        if hsv.saturation > 0 && hsv.value > 0 {
            lastHSV = hsv
        } else {
            lastHSV.value = hsv.value
            if hsv.value > 0 { lastHSV.saturation = hsv.saturation }
        }
        wheel.hue = lastHSV.hue
        wheel.saturation = lastHSV.saturation
        wheel.value = lastHSV.value
        valueSlider.gradient = [HsvColor(hue: lastHSV.hue, saturation: lastHSV.saturation, value: 0).toColor(),
                                HsvColor(hue: lastHSV.hue, saturation: lastHSV.saturation, value: 100).toColor()]
        valueSlider.value = lastHSV.value / 100
        hexField.stringValue = c.hexString
        guard sliders.count == 7 else { return }
        let vals: [Double] = [Double(c.r), Double(c.g), Double(c.b), lastHSV.hue, lastHSV.saturation, lastHSV.value, Double(c.a)]
        let maxes: [Double] = [255, 255, 255, 360, 100, 100, 255]
        let grads: [[ColorBgra]] = [
            [ColorBgra(r: 0, g: c.g, b: c.b), ColorBgra(r: 255, g: c.g, b: c.b)],
            [ColorBgra(r: c.r, g: 0, b: c.b), ColorBgra(r: c.r, g: 255, b: c.b)],
            [ColorBgra(r: c.r, g: c.g, b: 0), ColorBgra(r: c.r, g: c.g, b: 255)],
            stride(from: 0.0, through: 360, by: 30).map { HsvColor(hue: $0, saturation: 100, value: 100).toColor() },
            [HsvColor(hue: lastHSV.hue, saturation: 0, value: lastHSV.value).toColor(),
             HsvColor(hue: lastHSV.hue, saturation: 100, value: lastHSV.value).toColor()],
            [HsvColor(hue: lastHSV.hue, saturation: lastHSV.saturation, value: 0).toColor(),
             HsvColor(hue: lastHSV.hue, saturation: lastHSV.saturation, value: 100).toColor()],
            [c.withAlpha(0), c.withAlpha(255)],
        ]
        for (i, (slider, field)) in sliders.enumerated() {
            slider.gradient = grads[i]
            slider.value = vals[i] / maxes[i]
            field.stringValue = "\(Int(vals[i].rounded()))"
        }
    }

    // MARK: Palette files (Paint.NET .txt format: one AARRGGBB per line, ';' comments)

    private func loadPalette() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url, let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        var colors: [ColorBgra] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.components(separatedBy: ";")[0].trimmingCharacters(in: .whitespaces)
            guard line.count == 8, let v = UInt32(line, radix: 16) else { continue }
            colors.append(ColorBgra(argb: v))
        }
        guard !colors.isEmpty else { return }
        while colors.count < 96 { colors.append(.white) }
        env.palette = Array(colors.prefix(96))
    }

    private func savePalette() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "Palette.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var text = "; Brushwood palette (Paint.NET compatible)\n; Colors are AARRGGBB hex values\n"
        for c in env.palette { text += String(format: "%08X\n", c.argb) }
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}

/// Overlapping primary/secondary squares with swap and reset glyphs.
final class PrimarySecondaryView: NSView {
    var primary: ColorBgra = .black { didSet { needsDisplay = true } }
    var secondary: ColorBgra = .white { didSet { needsDisplay = true } }
    var editingSecondary = false { didSet { needsDisplay = true } }
    var onSelect: ((Bool) -> Void)?

    override var isFlipped: Bool { true }

    private var primaryRect: NSRect { NSRect(x: 0, y: 0, width: bounds.width * 0.62, height: bounds.height * 0.62) }
    private var secondaryRect: NSRect {
        NSRect(x: bounds.width * 0.38, y: bounds.height * 0.38, width: bounds.width * 0.62, height: bounds.height * 0.62)
    }
    private var swapRect: NSRect { NSRect(x: bounds.width * 0.66, y: 0, width: bounds.width * 0.34, height: bounds.height * 0.34) }
    private var resetRect: NSRect { NSRect(x: 0, y: bounds.height * 0.66, width: bounds.width * 0.34, height: bounds.height * 0.34) }

    override func draw(_ dirtyRect: NSRect) {
        func square(_ r: NSRect, _ c: ColorBgra, selected: Bool) {
            Checkerboard.draw(in: r, cell: 5)
            c.nsColor.setFill()
            r.fill(using: .sourceOver)
            NSColor.black.setStroke()
            NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)).stroke()
            NSColor.white.setStroke()
            NSBezierPath(rect: r.insetBy(dx: 1.5, dy: 1.5)).stroke()
            if selected {
                NSColor.controlAccentColor.setStroke()
                let p = NSBezierPath(rect: r.insetBy(dx: -1.5, dy: -1.5))
                p.lineWidth = 2
                p.stroke()
            }
        }
        square(secondaryRect, secondary, selected: editingSecondary)
        square(primaryRect, primary, selected: !editingSecondary)
        // Swap arrow.
        let sr = swapRect.insetBy(dx: 4, dy: 4)
        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: sr.minX, y: sr.minY + 2))
        arrow.curve(to: NSPoint(x: sr.maxX - 2, y: sr.maxY), controlPoint1: NSPoint(x: sr.maxX - 2, y: sr.minY + 2),
                    controlPoint2: NSPoint(x: sr.maxX - 2, y: sr.minY + 2))
        arrow.lineWidth = 1.3
        NSColor.labelColor.setStroke()
        arrow.stroke()
        for (tip, dx, dy) in [(NSPoint(x: sr.minX, y: sr.minY + 2), 1.0, 0.0), (NSPoint(x: sr.maxX - 2, y: sr.maxY), 0.0, -1.0)] {
            let h = NSBezierPath()
            h.move(to: tip)
            h.line(to: NSPoint(x: tip.x + 4 * dx + 3 * dy, y: tip.y + 4 * dy - 3 * dx))
            h.line(to: NSPoint(x: tip.x + 4 * dx - 3 * dy, y: tip.y + 4 * dy + 3 * dx))
            h.close()
            NSColor.labelColor.setFill()
            h.fill()
        }
        // Reset (small black over white squares).
        let rr = resetRect.insetBy(dx: 4, dy: 4)
        let s = rr.width * 0.6
        NSColor.white.setFill()
        NSRect(x: rr.maxX - s, y: rr.maxY - s, width: s, height: s).fill()
        NSColor.black.setStroke()
        NSBezierPath(rect: NSRect(x: rr.maxX - s, y: rr.maxY - s, width: s, height: s)).stroke()
        NSColor.black.setFill()
        NSRect(x: rr.minX, y: rr.minY, width: s, height: s).fill()
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if swapRect.contains(p) {
            AppEnvironment.shared.swapColors()
        } else if resetRect.contains(p) {
            AppEnvironment.shared.resetColors()
        } else if primaryRect.contains(p) {
            onSelect?(false)
            if event.clickCount == 2 { openSystemPicker(secondary: false) }
        } else if secondaryRect.contains(p) {
            onSelect?(true)
            if event.clickCount == 2 { openSystemPicker(secondary: true) }
        }
    }

    private func openSystemPicker(secondary: Bool) {
        let panel = NSColorPanel.shared
        panel.showsAlpha = true
        panel.color = (secondary ? AppEnvironment.shared.secondaryColor : AppEnvironment.shared.primaryColor).nsColor
        panel.setTarget(nil)
        let t = ColorPanelTarget(secondary: secondary)
        ColorPanelTarget.current = t
        panel.setTarget(t)
        panel.setAction(#selector(ColorPanelTarget.changed(_:)))
        panel.orderFront(nil)
    }
}

final class ColorPanelTarget: NSObject {
    static var current: ColorPanelTarget?
    let secondary: Bool

    init(secondary: Bool) { self.secondary = secondary }

    @objc func changed(_ sender: NSColorPanel) {
        let c = ColorBgra(nsColor: sender.color)
        if secondary { AppEnvironment.shared.secondaryColor = c } else { AppEnvironment.shared.primaryColor = c }
    }
}

/// Hue/saturation disk.
final class ColorWheelView: NSView {
    var hue: Double = 0 { didSet { needsDisplay = true } }
    var saturation: Double = 0 { didSet { needsDisplay = true } }
    var value: Double = 100
    /// (hue, saturation, toInactiveSlot)
    var onChange: ((Double, Double, Bool) -> Void)?
    private var wheelImage: NSImage?
    private var dragStart: (hue: Double, sat: Double)?
    private var cachedSize: CGSize = .zero

    override var isFlipped: Bool { true }

    private var radius: CGFloat { min(bounds.width, bounds.height) / 2 - 3 }
    private var center: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY) }

    private func renderWheel() -> NSImage {
        let scale = window?.backingScaleFactor ?? 2
        let n = Int(min(bounds.width, bounds.height) * scale)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: n, pixelsHigh: n, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: n * 4,
                                   bitsPerPixel: 32)!
        let data = rep.bitmapData!
        let c = Double(n) / 2, r = c - 3 * Double(scale)
        for y in 0..<n {
            for x in 0..<n {
                let dx = Double(x) + 0.5 - c, dy = Double(y) + 0.5 - c
                let d = sqrt(dx * dx + dy * dy)
                let i = (y * n + x) * 4
                if d > r + 1 {
                    data[i + 3] = 0
                    continue
                }
                var h = atan2(-dy, dx) * 180 / .pi
                if h < 0 { h += 360 }
                let col = HsvColor(hue: h, saturation: min(100, d / r * 100), value: 100).toColor()
                let a = d > r ? (r + 1 - d) : 1
                // Premultiplied storage.
                data[i] = UInt8(Double(col.r) * a)
                data[i + 1] = UInt8(Double(col.g) * a)
                data[i + 2] = UInt8(Double(col.b) * a)
                data[i + 3] = UInt8(255 * a)
            }
        }
        let img = NSImage(size: NSSize(width: min(bounds.width, bounds.height), height: min(bounds.width, bounds.height)))
        img.addRepresentation(rep)
        return img
    }

    override func draw(_ dirtyRect: NSRect) {
        if wheelImage == nil || cachedSize != bounds.size {
            wheelImage = renderWheel()
            cachedSize = bounds.size
        }
        let s = min(bounds.width, bounds.height)
        wheelImage?.draw(in: NSRect(x: bounds.midX - s / 2, y: bounds.midY - s / 2, width: s, height: s), from: .zero,
                         operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        // Marker.
        let a = hue * .pi / 180
        let rr = saturation / 100 * Double(radius)
        let p = CGPoint(x: center.x + CGFloat(cos(a) * rr), y: center.y - CGFloat(sin(a) * rr))
        let m = NSRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)
        NSColor.white.setStroke()
        let o = NSBezierPath(ovalIn: m)
        o.lineWidth = 2
        o.stroke()
        NSColor.black.setStroke()
        let o2 = NSBezierPath(ovalIn: m.insetBy(dx: -1.5, dy: -1.5))
        o2.lineWidth = 1
        o2.stroke()
    }

    /// ⌘ keeps the saturation (same circle), ⌥ keeps the hue (same spoke), ⇧ snaps the hue to 15° spokes.
    private func pick(_ e: NSEvent, inactive: Bool) {
        let p = convert(e.locationInWindow, from: nil)
        let dx = Double(p.x - center.x), dy = Double(center.y - p.y)
        var h = atan2(dy, dx) * 180 / .pi
        if h < 0 { h += 360 }
        var s = min(100, sqrt(dx * dx + dy * dy) / Double(radius) * 100)
        let f = e.modifierFlags
        if let start = dragStart {
            if f.contains(.command) { s = start.sat }
            if f.contains(.option) { h = start.hue }
        }
        if f.contains(.shift) { h = ((h / 15).rounded() * 15).truncatingRemainder(dividingBy: 360) }
        onChange?(h, s, inactive)
    }

    override func mouseDown(with e: NSEvent) {
        dragStart = (hue, saturation)
        pick(e, inactive: e.modifierFlags.contains(.control))
    }

    override func mouseDragged(with e: NSEvent) { pick(e, inactive: e.modifierFlags.contains(.control)) }

    override func rightMouseDown(with e: NSEvent) {
        dragStart = (hue, saturation)
        pick(e, inactive: true)
    }

    override func rightMouseDragged(with e: NSEvent) { pick(e, inactive: true) }
    override func viewDidChangeBackingProperties() { wheelImage = nil }
}

/// Gradient-track slider used for color components.
final class ColorComponentSlider: NSView {
    var gradient: [ColorBgra] = [.black, .white] { didSet { needsDisplay = true } }
    var value: Double = 0 { didSet { needsDisplay = true } }
    var onChange: ((Double) -> Void)?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let track = NSRect(x: 4, y: 2, width: bounds.width - 8, height: bounds.height - 8)
        Checkerboard.draw(in: track, cell: 4)
        if gradient.count >= 2, let g = NSGradient(colors: gradient.map(\.nsColor)) {
            g.draw(in: track, angle: 0)
        }
        NSColor.separatorColor.setStroke()
        NSBezierPath(rect: track.insetBy(dx: 0.5, dy: 0.5)).stroke()
        let x = track.minX + CGFloat(value) * track.width
        let tri = NSBezierPath()
        tri.move(to: NSPoint(x: x, y: track.maxY - 2))
        tri.line(to: NSPoint(x: x - 4, y: bounds.maxY))
        tri.line(to: NSPoint(x: x + 4, y: bounds.maxY))
        tri.close()
        NSColor.labelColor.setFill()
        tri.fill()
        NSColor.labelColor.setStroke()
        NSBezierPath(rect: NSRect(x: x - 1, y: track.minY - 1, width: 2, height: track.height + 2)).stroke()
    }

    private func pick(_ e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        let v = clampDouble(Double((p.x - 4) / (bounds.width - 8)), 0, 1)
        value = v
        onChange?(v)
    }

    override func mouseDown(with e: NSEvent) { pick(e) }
    override func mouseDragged(with e: NSEvent) { pick(e) }
}

/// 96-swatch palette grid (8 × 12).
final class PaletteView: NSView {
    /// (color, toInactiveSlot)
    var onPick: ((ColorBgra, Bool) -> Void)?
    var onStore: ((Int) -> Void)?
    let columns = 8
    let cell: CGFloat = 17
    var rowHeight: CGFloat = 13
    var visibleCount = 96

    override var isFlipped: Bool { true }

    private func rect(_ i: Int) -> NSRect {
        NSRect(x: CGFloat(i % columns) * cell, y: CGFloat(i / columns) * rowHeight, width: cell + 1, height: rowHeight + 1)
    }

    override func draw(_ dirtyRect: NSRect) {
        for (i, c) in AppEnvironment.shared.palette.prefix(visibleCount).enumerated() {
            let r = rect(i)
            if c.a < 255 { Checkerboard.draw(in: r, cell: 3) }
            c.nsColor.setFill()
            r.fill(using: .sourceOver)
            NSColor(white: 0.35, alpha: 1).setStroke()
            NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)).stroke()
        }
    }

    private func index(at e: NSEvent) -> Int? {
        let p = convert(e.locationInWindow, from: nil)
        let i = Int(p.y / rowHeight) * columns + Int(p.x / cell)
        return (i >= 0 && i < min(visibleCount, AppEnvironment.shared.palette.count) && p.x >= 0 && p.y >= 0) ? i : nil
    }

    override func mouseDown(with e: NSEvent) {
        guard let i = index(at: e) else { return }
        if e.modifierFlags.contains(.shift) {
            onStore?(i)
        } else {
            onPick?(AppEnvironment.shared.palette[i], e.modifierFlags.contains(.control))
        }
    }

    override func rightMouseDown(with e: NSEvent) {
        guard let i = index(at: e) else { return }
        onPick?(AppEnvironment.shared.palette[i], true)
    }

    override func mouseMoved(with e: NSEvent) {
        if let i = index(at: e) { toolTip = "#" + AppEnvironment.shared.palette[i].hexString }
    }
}
