import AppKit
import BrushwoodCore

/// The second toolbar row: tool chooser plus the options of the active tool (Paint.NET's tool bar).
/// Like Paint.NET's, it wraps onto more rows when the window is too narrow for all the options.
final class ToolOptionsBar: NSView {
    private let flow = WrappingRow()
    private let toolPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    weak var host: MainWindowController?
    private var observers: [NSObjectProtocol] = []
    private var updating = false
    private var refreshers: [() -> Void] = []
    /// Exposed for the scripted UI tests.
    private(set) weak var brushWidthCombo: NumberComboBox?

    var env: AppEnvironment { .shared }
    var s: ToolSettings { env.tools }

    override init(frame: NSRect) {
        super.init(frame: frame)
        if #available(macOS 14.0, *) { clipsToBounds = true }
        flow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(flow)
        NSLayoutConstraint.activate([
            flow.leadingAnchor.constraint(equalTo: leadingAnchor),
            flow.trailingAnchor.constraint(equalTo: trailingAnchor),
            flow.topAnchor.constraint(equalTo: topAnchor),
            flow.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
        ])
        toolPopup.controlSize = .small
        toolPopup.isBordered = true
        toolPopup.translatesAutoresizingMaskIntoConstraints = false
        toolPopup.widthAnchor.constraint(lessThanOrEqualToConstant: 260).isActive = true
        for t in ToolKind.allCases {
            let item = NSMenuItem(title: t.name, action: nil, keyEquivalent: "")
            item.image = Icons.image(t.icon, size: 16)
            item.tag = t.rawValue
            toolPopup.menu?.addItem(item)
        }
        toolPopup.onAction { [weak self] _ in
            guard let self, let t = ToolKind(rawValue: self.toolPopup.selectedTag()) else { return }
            self.host?.selectTool(t)
        }
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: .toolChanged, object: nil, queue: .main) { [weak self] _ in self?.rebuild() })
        observers.append(nc.addObserver(forName: .toolSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        })
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Width the current options need on a single row (they wrap when it exceeds the bar's width).
    var contentWidth: CGFloat { flow.singleRowWidth }

    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        // Since macOS 14 views don't clip to their bounds and dirtyRect can extend past them.
        dirtyRect.intersection(bounds).fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }

    private func refresh() {
        updating = true
        refreshers.forEach { $0() }
        updating = false
    }

    private func add(_ v: NSView) { flow.append(v) }

    func rebuild() {
        flow.removeAll()
        refreshers.removeAll()
        let tool = env.activeTool
        add(toolbarLabel(L("Tool:")))
        toolPopup.selectItem(withTag: tool.rawValue)
        add(toolPopup)
        add(ToolbarSeparator())
        switch tool {
        case .rectangleSelect, .ellipseSelect:
            selectionMode()
            add(ToolbarSeparator())
            selectionDrawMode()
        case .lassoSelect:
            selectionMode()
        case .magicWand:
            selectionMode()
            add(ToolbarSeparator())
            floodMode()
            tolerance()
            sampling(\.floodSampling)
        case .moveSelectedPixels:
            resampling()
        case .moveSelection, .zoom, .pan:
            break
        case .paintBucket:
            floodMode()
            fillStyle()
            tolerance()
            sampling(\.floodSampling)
            add(ToolbarSeparator())
            antialiasing()
            blendMode()
        case .gradient:
            gradientTypes()
            add(ToolbarSeparator())
            gradientColorMode()
            gradientRepeat()
            add(ToolbarSeparator())
            blendMode()
        case .paintbrush:
            brushWidth()
            hardness()
            add(ToolbarSeparator())
            antialiasing()
            blendMode()
        case .eraser:
            brushWidth()
            hardness()
            add(ToolbarSeparator())
            antialiasing()
        case .pencil:
            blendMode()
        case .colorPicker:
            colorPickerOptions()
        case .cloneStamp:
            brushWidth()
            hardness()
            add(ToolbarSeparator())
            antialiasing()
            blendMode()
        case .recolor:
            brushWidth()
            hardness()
            tolerance()
            add(ToolbarSeparator())
            antialiasing()
        case .text:
            fontOptions()
            add(ToolbarSeparator())
            antialiasing()
            blendMode()
        case .lineCurve:
            brushWidth()
            add(ToolbarSeparator())
            dashStyle()
            caps()
            add(ToolbarSeparator())
            antialiasing()
            blendMode()
        case .shapes:
            shapePicker()
            shapeDrawType()
            if s.shapeType == .roundedRectangle || s.shapeType == .calloutRoundedRectangle {
                add(toolbarLabel(L("Radius:")))
                let c = NumericSliderControl(range: 0...200, value: Double(s.cornerRadius), showReset: false, sliderWidth: 80)
                c.onChange = { [weak self] v in self?.s.cornerRadius = CGFloat(v) }
                refreshers.append { [weak self] in c.setValue(Double(self?.s.cornerRadius ?? 20), notify: false) }
                add(c)
            }
            add(ToolbarSeparator())
            brushWidth()
            dashStyle()
            fillStyle()
            add(ToolbarSeparator())
            antialiasing()
            blendMode()
        }
        if [.paintBucket, .gradient, .paintbrush, .eraser, .pencil, .cloneStamp, .recolor, .text, .lineCurve, .shapes].contains(tool) {
            selectionClipping()
        }
        if [.rectangleSelect, .ellipseSelect, .magicWand, .moveSelectedPixels, .paintBucket, .gradient, .text, .lineCurve,
            .shapes].contains(tool) {
            add(ToolbarSeparator())
            let finish = NSButton(title: L("Finish"), image: NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)!,
                                  target: nil, action: nil)
            finish.controlSize = .small
            finish.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            finish.bezelStyle = .rounded
            finish.toolTip = L("Finish (Return)")
            finish.onAction { [weak self] _ in self?.host?.commitPendingTool() }
            add(finish)
        }
        refresh()
    }

    // MARK: - Option builders

    private func selectionClipping() {
        add(toolbarLabel(L("Clipping:")))
        add(popup([(L("Antialiased"), nil), (L("Aliased"), nil)], get: { self.s.selectionClippingAntialiased ? 0 : 1 },
                  set: { self.s.selectionClippingAntialiased = $0 == 0 }, tooltip: L("Selection clipping")))
    }

    private func popup(_ items: [(String, NSImage?)], get: @escaping () -> Int, set: @escaping (Int) -> Void,
                       tooltip: String, imageOnly: Bool = false, maxWidth: CGFloat = 200) -> NSPopUpButton {
        let p = NSPopUpButton(frame: .zero, pullsDown: false)
        p.controlSize = .small
        p.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        for (i, item) in items.enumerated() {
            p.addItem(withTitle: item.0)
            p.lastItem?.image = item.1
            p.lastItem?.tag = i
        }
        p.toolTip = tooltip
        p.translatesAutoresizingMaskIntoConstraints = false
        p.widthAnchor.constraint(lessThanOrEqualToConstant: imageOnly ? 62 : maxWidth).isActive = true
        // Swatch-only pickers (dash, fill) show just the selected pattern, like Paint.NET.
        if imageOnly { p.imagePosition = .imageOnly }
        p.onAction { [weak self] _ in
            guard self?.updating == false else { return }
            set(p.selectedTag())
        }
        refreshers.append { p.selectItem(withTag: get()) }
        return p
    }

    private func segmented(_ icons: [(String, String)], get: @escaping () -> Int, set: @escaping (Int) -> Void) -> NSSegmentedControl {
        let seg = NSSegmentedControl()
        seg.segmentCount = icons.count
        seg.controlSize = .small
        seg.trackingMode = .selectOne
        seg.segmentStyle = .texturedRounded
        for (i, (icon, tip)) in icons.enumerated() {
            seg.setImage(Icons.image(icon, size: 14), forSegment: i)
            seg.setToolTip(tip, forSegment: i)
            seg.setWidth(26, forSegment: i)
        }
        seg.onAction { [weak self] _ in
            guard self?.updating == false else { return }
            set(seg.selectedSegment)
        }
        refreshers.append { seg.selectedSegment = get() }
        return seg
    }

    private func selectionMode() {
        add(toolbarLabel(L("Selection mode:")))
        let icons = SelectionCombineMode.allCases.map { ("selmode.\($0)", L($0.displayName)) }
        add(segmented(icons, get: { self.s.selectionMode.rawValue },
                      set: { self.s.selectionMode = SelectionCombineMode(rawValue: $0) ?? .replace }))
    }

    private func selectionDrawMode() {
        add(toolbarLabel(L("Mode:")))
        let p = popup(SelectionDrawMode.allCases.map { ($0.name, nil) }, get: { self.s.selectionDrawMode.rawValue },
                                     set: { self.s.selectionDrawMode = SelectionDrawMode(rawValue: $0) ?? .normal; self.rebuild() },
                                     tooltip: L("Selection drawing mode"))
        add(p)
        if s.selectionDrawMode != .normal {
            for (label, kp) in [(L("Width:"), \ToolSettings.selectionFixedWidth), (L("Height:"), \ToolSettings.selectionFixedHeight)] {
                add(toolbarLabel(label))
                let f = NSTextField()
                f.controlSize = .small
                f.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
                f.translatesAutoresizingMaskIntoConstraints = false
                f.widthAnchor.constraint(equalToConstant: 50).isActive = true
                f.doubleValue = s[keyPath: kp]
                f.onAction { [weak self] _ in self?.s[keyPath: kp] = max(1, f.doubleValue) }
                add(f)
            }
        }
    }

    private func floodMode() {
        add(toolbarLabel(L("Flood mode:")))
        add(segmented([("flood.contiguous", L("Contiguous")), ("flood.global", L("Global"))],
                      get: { self.s.floodMode.rawValue }, set: { self.s.floodMode = FloodMode(rawValue: $0) ?? .contiguous }))
    }

    private func tolerance() {
        add(toolbarLabel(L("Tolerance:")))
        let c = NumericSliderControl(range: 0...100, value: s.tolerance * 100, showReset: false, sliderWidth: 110)
        c.onChange = { [weak self] v in self?.s.tolerance = v / 100 }
        refreshers.append { [weak self] in c.setValue((self?.s.tolerance ?? 0.5) * 100, notify: false) }
        add(c)
        add(toolbarLabel("%"))
    }

    private func sampling(_ kp: ReferenceWritableKeyPath<ToolSettings, SamplingSource>) {
        add(toolbarLabel(L("Sampling:")))
        add(popup(SamplingSource.allCases.map { ($0.name, nil) }, get: { self.s[keyPath: kp].rawValue },
                  set: { self.s[keyPath: kp] = SamplingSource(rawValue: $0) ?? .layer }, tooltip: L("Sampling")))
    }

    private func antialiasing() {
        // Paint.NET's "Rasterization" toggle: smooth vs. jagged edges.
        let b = ToolbarButton(icon: "opt.antialias", tooltip: L("Antialiasing"), target: nil, action: nil, size: 24)
        b.onAction { [weak self] _ in self?.s.antialiasing.toggle() }
        refreshers.append { [weak self] in
            let on = self?.s.antialiasing == true
            b.isToggled = on
            b.image = Icons.image(on ? "opt.antialias" : "opt.aliased", size: 16)
            b.toolTip = on ? L("Antialiasing enabled") : L("Antialiasing disabled")
        }
        add(b)
    }

    private func blendMode() {
        add(toolbarLabel(L("Blending:")))
        // Last entry is Paint.NET's "Overwrite" (alpha blending off).
        let overwriteTag = BlendMode.allCases.count
        add(popup(BlendMode.allCases.map { (L($0.displayName), nil) } + [(L("Overwrite"), nil)],
                  get: { self.s.overwrite ? overwriteTag : self.s.blendMode.rawValue },
                  set: {
                      if $0 == overwriteTag {
                          self.s.overwrite = true
                      } else {
                          self.s.overwrite = false
                          self.s.blendMode = BlendMode(rawValue: $0) ?? .normal
                      }
                  }, tooltip: L("Blend mode")))
    }

    private func brushWidth() {
        add(toolbarLabel(L("Brush width:")))
        let combo = NumberComboBox(presets: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60,
                                             65, 70, 75, 80, 85, 90, 95, 100, 125, 150, 175, 200, 225, 250, 275, 300, 350, 400,
                                             450, 500, 750, 1000, 1500, 2000], range: 1...2000)
        combo.controlSize = .small
        combo.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        combo.translatesAutoresizingMaskIntoConstraints = false
        combo.widthAnchor.constraint(equalToConstant: 64).isActive = true
        combo.toolTip = L("Brush width (mouse wheel, [ and ] also change it)")
        combo.onValue = { [weak self] v in self?.s.brushWidth = CGFloat(v) }
        refreshers.append { [weak self, weak combo] in combo?.show(Double(self?.s.brushWidth ?? 2)) }
        add(combo)
        brushWidthCombo = combo
        let stepper = NSStepper()
        stepper.controlSize = .small
        stepper.minValue = 1
        stepper.maxValue = 2000
        stepper.onAction { [weak self, weak stepper] _ in
            guard let stepper else { return }
            self?.s.brushWidth = CGFloat(stepper.doubleValue)
        }
        refreshers.append { [weak self, weak stepper] in stepper?.doubleValue = Double(self?.s.brushWidth ?? 2) }
        add(stepper)
    }

    private func hardness() {
        add(toolbarLabel(L("Hardness:")))
        let c = NumericSliderControl(range: 0...100, value: s.hardness, showReset: false, sliderWidth: 90)
        c.onChange = { [weak self] v in self?.s.hardness = v }
        refreshers.append { [weak self] in c.setValue(self?.s.hardness ?? 75, notify: false) }
        add(c)
        add(toolbarLabel("%"))
    }

    private func fillStyle() {
        add(toolbarLabel(L("Fill:")))
        add(popup(FillStyle.allCases.map { (L($0.displayName), Self.patternSwatch($0)) }, get: { self.s.fillStyle.rawValue },
                  set: { self.s.fillStyle = FillStyle(rawValue: $0) ?? .solid }, tooltip: L("Fill style"), imageOnly: true))
    }

    static func patternSwatch(_ style: FillStyle) -> NSImage {
        NSImage(size: NSSize(width: 16, height: 16), flipped: true) { r in
            NSColor.white.setFill()
            r.fill()
            NSColor.black.setFill()
            let pat = style.pattern
            for y in 0..<16 {
                for x in 0..<16 where FillStyle.isForeground(pat, x: x, y: y) {
                    NSRect(x: x, y: y, width: 1, height: 1).fill()
                }
            }
            NSColor.gray.setStroke()
            NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)).stroke()
            return true
        }
    }

    private func gradientTypes() {
        add(toolbarLabel(L("Gradient:")))
        let icons = GradientType.allCases.map { ("gradient.\($0)", $0.name) }
        add(segmented(icons, get: { self.s.gradientType.rawValue }, set: { self.s.gradientType = GradientType(rawValue: $0) ?? .linear }))
    }

    private func gradientColorMode() {
        add(toolbarLabel(L("Mode:")))
        add(segmented([("gradient.colorMode", L("Color Mode")), ("gradient.transparencyMode", L("Transparency Mode"))],
                      get: { self.s.gradientTransparencyMode ? 1 : 0 }, set: { self.s.gradientTransparencyMode = $0 == 1 }))
    }

    private func gradientRepeat() {
        add(popup(GradientRepeat.allCases.map { ($0.name, nil) }, get: { self.s.gradientRepeat.rawValue },
                  set: { self.s.gradientRepeat = GradientRepeat(rawValue: $0) ?? .none }, tooltip: L("Repeat"), maxWidth: 230))
    }

    private func resampling() {
        add(toolbarLabel(L("Quality:")))
        add(popup([(L("Bilinear"), nil), (L("Nearest Neighbor"), nil)], get: { self.s.bilinearResampling ? 0 : 1 },
                  set: { self.s.bilinearResampling = $0 == 0 }, tooltip: L("Resampling")))
    }

    private func colorPickerOptions() {
        add(toolbarLabel(L("Sampling:")))
        add(popup(ColorPickerSampleSize.allCases.map { ($0.name, nil) },
                  get: { ColorPickerSampleSize.allCases.firstIndex(of: self.s.colorPickerSampleSize) ?? 0 },
                  set: { self.s.colorPickerSampleSize = ColorPickerSampleSize.allCases[$0] }, tooltip: L("Sample size")))
        add(popup(SamplingSource.allCases.map { ($0.name, nil) }, get: { self.s.colorPickerSampling.rawValue },
                  set: { self.s.colorPickerSampling = SamplingSource(rawValue: $0) ?? .layer }, tooltip: L("Sampling")))
        add(ToolbarSeparator())
        add(toolbarLabel(L("After click:")))
        add(popup(ColorPickerAfterClick.allCases.map { ($0.name, nil) }, get: { self.s.colorPickerAfterClick.rawValue },
                  set: { self.s.colorPickerAfterClick = ColorPickerAfterClick(rawValue: $0) ?? .doNotSwitch },
                  tooltip: L("After click"), maxWidth: 230))
    }

    private func fontOptions() {
        add(toolbarLabel(L("Font:")))
        let families = NSFontManager.shared.availableFontFamilies
        let fontPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        fontPopup.controlSize = .small
        fontPopup.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        fontPopup.addItems(withTitles: families)
        fontPopup.onAction { [weak self] _ in
            if let t = fontPopup.titleOfSelectedItem { self?.s.fontName = t }
        }
        refreshers.append { [weak self] in
            guard let self else { return }
            let family = NSFont(name: self.s.fontName, size: 12)?.familyName ?? self.s.fontName
            fontPopup.selectItem(withTitle: family)
        }
        fontPopup.translatesAutoresizingMaskIntoConstraints = false
        fontPopup.widthAnchor.constraint(lessThanOrEqualToConstant: 150).isActive = true
        add(fontPopup)
        let size = NumberComboBox(presets: [8, 9, 10, 11, 12, 14, 16, 18, 20, 22, 24, 26, 28, 36, 48, 72, 96, 144, 288],
                                  range: 1...2000)
        size.controlSize = .small
        size.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        size.translatesAutoresizingMaskIntoConstraints = false
        size.widthAnchor.constraint(equalToConstant: 56).isActive = true
        size.onValue = { [weak self] v in self?.s.fontSize = CGFloat(v) }
        refreshers.append { [weak self, weak size] in size?.show(Double(self?.s.fontSize ?? 12)) }
        add(size)
        let styles: [(String, ReferenceWritableKeyPath<ToolSettings, Bool>, String)] = [
            ("bold", \.bold, L("Bold")), ("italic", \.italic, L("Italic")), ("underline", \.underline, L("Underline")),
            ("strikethrough", \.strikethrough, L("Strikethrough")),
        ]
        for (sym, kp, tip) in styles {
            let b = ToolbarButton(icon: "sym.\(sym)", tooltip: tip, target: nil, action: nil, size: 22)
            b.onAction { [weak self] _ in self?.s[keyPath: kp].toggle() }
            refreshers.append { [weak self] in b.isToggled = self?.s[keyPath: kp] == true }
            add(b)
        }
        add(ToolbarSeparator())
        add(segmented([("sym.text.alignleft", L("Left")), ("sym.text.aligncenter", L("Center")),
                       ("sym.text.alignright", L("Right"))],
                      get: { self.s.textAlignment.rawValue }, set: { self.s.textAlignment = TextAlignmentOption(rawValue: $0) ?? .left }))
    }

    private func dashStyle() {
        add(toolbarLabel(L("Dash:")))
        add(popup(LineDashStyle.allCases.map { ($0.name, Self.dashSwatch($0)) }, get: { self.s.dashStyle.rawValue },
                  set: { self.s.dashStyle = LineDashStyle(rawValue: $0) ?? .solid }, tooltip: L("Dash style"), imageOnly: true))
    }

    static func dashSwatch(_ d: LineDashStyle) -> NSImage {
        NSImage(size: NSSize(width: 28, height: 12), flipped: false) { r in
            let p = NSBezierPath()
            p.move(to: NSPoint(x: 1, y: r.midY))
            p.line(to: NSPoint(x: r.maxX - 1, y: r.midY))
            p.lineWidth = 2
            let pat = d.pattern(width: 2)
            if !pat.isEmpty { p.setLineDash(pat, count: pat.count, phase: 0) }
            NSColor.labelColor.setStroke()
            p.stroke()
            return true
        }
    }

    private func caps() {
        add(toolbarLabel(L("Start:")))
        add(popup(LineCap.allCases.map { ($0.name, nil) }, get: { self.s.startCap.rawValue },
                  set: { self.s.startCap = LineCap(rawValue: $0) ?? .flat }, tooltip: L("Start cap")))
        add(toolbarLabel(L("End:")))
        add(popup(LineCap.allCases.map { ($0.name, nil) }, get: { self.s.endCap.rawValue },
                  set: { self.s.endCap = LineCap(rawValue: $0) ?? .flat }, tooltip: L("End cap")))
    }

    private func shapePicker() {
        add(toolbarLabel(L("Shape:")))
        let p = NSPopUpButton(frame: .zero, pullsDown: false)
        p.controlSize = .small
        p.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        p.translatesAutoresizingMaskIntoConstraints = false
        p.widthAnchor.constraint(lessThanOrEqualToConstant: 260).isActive = true
        p.autoenablesItems = false
        for cat in ShapeKind.Category.allCases {
            let header = NSMenuItem(title: cat.name, action: nil, keyEquivalent: "")
            header.isEnabled = false
            header.tag = -1
            p.menu?.addItem(header)
            for shape in ShapeKind.allCases where shape.category == cat {
                let item = NSMenuItem(title: shape.name, action: nil, keyEquivalent: "")
                item.tag = shape.rawValue
                item.image = Self.shapeSwatch(shape)
                item.indentationLevel = 1
                p.menu?.addItem(item)
            }
        }
        p.onAction { [weak self] _ in
            guard self?.updating == false, let k = ShapeKind(rawValue: p.selectedTag()) else { return }
            let hadRadius = [.roundedRectangle, .calloutRoundedRectangle].contains(self?.s.shapeType)
            self?.s.shapeType = k
            // Show or hide the radius control.
            if hadRadius != [.roundedRectangle, .calloutRoundedRectangle].contains(k) { self?.rebuild() }
        }
        refreshers.append { [weak self] in p.selectItem(withTag: self?.s.shapeType.rawValue ?? 0) }
        add(p)
    }

    static func shapeSwatch(_ k: ShapeKind) -> NSImage {
        NSImage(size: NSSize(width: 16, height: 16), flipped: true) { r in
            let path = k.path(in: r.insetBy(dx: 1.5, dy: 1.5))
            guard let ctx = NSGraphicsContext.current?.cgContext else { return true }
            ctx.addPath(path)
            ctx.setFillColor(Icons.lightBlue.cgColor)
            ctx.fillPath(using: .evenOdd)
            ctx.addPath(path)
            ctx.setStrokeColor(Icons.blue.cgColor)
            ctx.setLineWidth(1)
            ctx.strokePath()
            return true
        }
    }

    private func shapeDrawType() {
        add(segmented(ShapeDrawType.allCases.map { ("drawtype.\($0)", $0.name) }, get: { self.s.shapeDrawType.rawValue },
                      set: { self.s.shapeDrawType = ShapeDrawType(rawValue: $0) ?? .outline }))
    }
}

/// Lays its items out left to right and starts a new row when the next one does not fit. A label ending with a colon
/// stays on the same row as the control after it, a label without one (a unit such as "%") stays with the control before
/// it, and a separator that would start or end a row is hidden.
final class WrappingRow: NSView {
    static let rowHeight: CGFloat = 31
    private let spacing: CGFloat = 6
    private let inset: CGFloat = 8
    private var items: [NSView] = []
    private var rows = 1

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    required init?(coder: NSCoder) { fatalError() }

    func append(_ v: NSView) {
        v.translatesAutoresizingMaskIntoConstraints = true
        items.append(v)
        addSubview(v)
        needsLayout = true
    }

    func removeAll() {
        items.forEach { $0.removeFromSuperview() }
        items.removeAll()
        needsLayout = true
    }

    var singleRowWidth: CGFloat {
        items.reduce(inset * 2 - spacing) { $0 + $1.fittingSize.width + spacing }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: CGFloat(rows) * Self.rowHeight)
    }

    private static func isLabel(_ v: NSView) -> Bool {
        guard let l = v as? NSTextField else { return false }
        return !l.isEditable && !l.isBezeled && !l.isBordered
    }

    private static func endsWithColon(_ v: NSView) -> Bool {
        guard let l = v as? NSTextField else { return false }
        return l.stringValue.hasSuffix(":") || l.stringValue.hasSuffix("：")
    }

    /// Items grouped into the pieces that never break apart.
    private func units() -> [[NSView]] {
        var units: [[NSView]] = []
        var joinNext = false
        for v in items {
            if joinNext || (Self.isLabel(v) && !Self.endsWithColon(v) && !units.isEmpty) {
                units[units.count - 1].append(v)
            } else {
                units.append([v])
            }
            joinNext = Self.isLabel(v) && Self.endsWithColon(v)
        }
        return units
    }

    override func layout() {
        super.layout()
        let groups = units()
        let sizes = groups.map { $0.map(\.fittingSize) }
        let widths = sizes.map { $0.reduce(-spacing) { $0 + $1.width + spacing } }
        let maxX = bounds.width - inset
        var x = inset, row = 0
        for (i, group) in groups.enumerated() {
            let isSeparator = group.count == 1 && group[0] is ToolbarSeparator
            if isSeparator {
                // Hidden when it would start a row or when what follows it moves to the next row.
                let next = i + 1 < widths.count ? widths[i + 1] : 0
                let hide = x == inset || x + widths[i] + spacing + next > maxX
                group[0].isHidden = hide
                if hide { continue }
            } else if x > inset && x + widths[i] > maxX {
                row += 1
                x = inset
            }
            for (v, size) in zip(group, sizes[i]) {
                let y = CGFloat(row) * Self.rowHeight + ((Self.rowHeight - size.height) / 2).rounded()
                v.frame = NSRect(x: x, y: y, width: size.width, height: size.height)
                x += size.width + spacing
            }
        }
        if row + 1 != rows {
            rows = row + 1
            invalidateIntrinsicContentSize()
        }
    }
}
