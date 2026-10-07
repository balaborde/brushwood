import AppKit
import BrushwoodCore

/// The second toolbar row: tool chooser plus the options of the active tool (Paint.NET's tool bar).
final class ToolOptionsBar: NSView {
    private let stack = NSStackView()
    private let toolPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    weak var host: MainWindowController?
    private var observers: [NSObjectProtocol] = []
    private var updating = false
    private var refreshers: [() -> Void] = []

    var env: AppEnvironment { .shared }
    var s: ToolSettings { env.tools }

    override init(frame: NSRect) {
        super.init(frame: frame)
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        toolPopup.controlSize = .small
        toolPopup.isBordered = true
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

    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }

    private func refresh() {
        updating = true
        refreshers.forEach { $0() }
        updating = false
    }

    private func add(_ v: NSView) { stack.addArrangedSubview(v) }

    func rebuild() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
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
        refresh()
    }

    // MARK: - Option builders

    private func popup(_ items: [(String, NSImage?)], get: @escaping () -> Int, set: @escaping (Int) -> Void,
                       tooltip: String) -> NSPopUpButton {
        let p = NSPopUpButton(frame: .zero, pullsDown: false)
        p.controlSize = .small
        p.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        for (i, item) in items.enumerated() {
            p.addItem(withTitle: item.0)
            p.lastItem?.image = item.1
            p.lastItem?.tag = i
        }
        p.toolTip = tooltip
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
        let b = NSButton(checkboxWithTitle: L("Antialiasing"), target: nil, action: nil)
        b.controlSize = .small
        b.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        b.onAction { [weak self] _ in self?.s.antialiasing = b.state == .on }
        refreshers.append { [weak self] in b.state = self?.s.antialiasing == true ? .on : .off }
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
        let combo = NSComboBox()
        combo.controlSize = .small
        combo.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        combo.addItems(withObjectValues: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60,
                                          65, 70, 75, 80, 85, 90, 95, 100, 125, 150, 175, 200, 225, 250, 275, 300, 350, 400, 450,
                                          500, 750, 1000, 1500, 2000].map { "\($0)" })
        combo.numberOfVisibleItems = 16
        combo.translatesAutoresizingMaskIntoConstraints = false
        combo.widthAnchor.constraint(equalToConstant: 64).isActive = true
        combo.onAction { [weak self] _ in
            let v = combo.doubleValue
            if v >= 1 { self?.s.brushWidth = CGFloat(min(2000, v)) }
        }
        refreshers.append { [weak self] in combo.stringValue = "\(Int(self?.s.brushWidth ?? 2))" }
        add(combo)
        let stepper = NSStepper()
        stepper.controlSize = .small
        stepper.minValue = 1
        stepper.maxValue = 2000
        stepper.onAction { [weak self] _ in self?.s.brushWidth = CGFloat(stepper.doubleValue) }
        refreshers.append { [weak self] in stepper.doubleValue = Double(self?.s.brushWidth ?? 2) }
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
                  set: { self.s.fillStyle = FillStyle(rawValue: $0) ?? .solid }, tooltip: L("Fill style")))
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
                  set: { self.s.gradientRepeat = GradientRepeat(rawValue: $0) ?? .none }, tooltip: L("Repeat")))
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
                  tooltip: L("After click")))
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
        fontPopup.widthAnchor.constraint(lessThanOrEqualToConstant: 170).isActive = true
        add(fontPopup)
        let size = NSComboBox()
        size.controlSize = .small
        size.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        size.addItems(withObjectValues: [8, 9, 10, 11, 12, 14, 16, 18, 20, 22, 24, 26, 28, 36, 48, 72, 96, 144, 288].map { "\($0)" })
        size.translatesAutoresizingMaskIntoConstraints = false
        size.widthAnchor.constraint(equalToConstant: 56).isActive = true
        size.onAction { [weak self] _ in
            if size.doubleValue > 0 { self?.s.fontSize = CGFloat(size.doubleValue) }
        }
        refreshers.append { [weak self] in size.stringValue = "\(Int(self?.s.fontSize ?? 12))" }
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
                  set: { self.s.dashStyle = LineDashStyle(rawValue: $0) ?? .solid }, tooltip: L("Dash style")))
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
        for cat in ShapeKind.Category.allCases {
            let header = NSMenuItem(title: cat.name, action: nil, keyEquivalent: "")
            header.isEnabled = false
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
