import AppKit
import BrushwoodCore

/// Adjustments > Curves: luminosity or per-channel RGB spline curves with draggable control points.
final class CurvesDialog: ModalDialog {
    private let effect: CurvesAdjustment
    private let session: EffectPreviewSession
    private let graph: CurveGraphView
    private var version = 0
    private var channelChecks: [NSButton] = []

    init(effect: CurvesAdjustment, session: EffectPreviewSession) {
        self.effect = effect
        self.session = session
        graph = CurveGraphView(histogram: HistogramRGB(surface: session.src, rect: session.env.selectionBounds,
                                                       mask: session.env.selectionMask))
        super.init(title: L("Curves"))
        build()
    }

    var currentValues: EffectValues {
        var v = EffectValues()
        v["_v"] = .int(version)
        return v
    }

    static func run(effect: CurvesAdjustment, session: EffectPreviewSession, parent: NSWindow?,
                    completion: (EffectValues?) -> Void) {
        let d = CurvesDialog(effect: effect, session: session)
        d.push()
        let ok = d.runModal(parent: parent, beside: true)
        completion(ok ? d.currentValues : nil)
    }

    private func push() {
        effect.mode = graph.rgbMode ? .rgb : .luminosity
        effect.luminosity = graph.curves[3]
        effect.red = graph.curves[0]
        effect.green = graph.curves[1]
        effect.blue = graph.curves[2]
        version += 1
        session.update(currentValues)
    }

    private func build() {
        let mode = NSPopUpButton(frame: .zero, pullsDown: false)
        mode.addItems(withTitles: [L("Luminosity"), L("RGB")])
        let row = NSStackView(views: [NSTextField(labelWithString: L("Transfer Map:")), mode])
        row.orientation = .horizontal
        body.addArrangedSubview(row)
        graph.translatesAutoresizingMaskIntoConstraints = false
        graph.widthAnchor.constraint(equalToConstant: 280).isActive = true
        graph.heightAnchor.constraint(equalToConstant: 280).isActive = true
        graph.onChange = { [weak self] in self?.push() }
        body.addArrangedSubview(graph)
        let coords = NSTextField(labelWithString: "")
        coords.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        coords.textColor = .secondaryLabelColor
        graph.onHover = { p in coords.stringValue = p.map { "(\(Int($0.x)), \(Int($0.y)))" } ?? "" }
        var checks: [NSView] = []
        for (i, name) in [L("Red"), L("Green"), L("Blue")].enumerated() {
            let b = NSButton(checkboxWithTitle: name, target: nil, action: nil)
            b.state = .on
            b.onAction { [weak self] _ in
                self?.graph.editMask[i] = b.state == .on
                self?.graph.needsDisplay = true
            }
            channelChecks.append(b)
            checks.append(b)
        }
        let checkRow = NSStackView(views: checks + [NSView(), coords])
        checkRow.orientation = .horizontal
        body.addArrangedSubview(checkRow)
        checkRow.isHidden = true
        mode.onAction { [weak self] _ in
            guard let self else { return }
            self.graph.rgbMode = mode.indexOfSelectedItem == 1
            checkRow.isHidden = !self.graph.rgbMode
            self.push()
        }
        let reset = NSButton(title: L("Reset"), target: nil, action: nil)
        reset.bezelStyle = .rounded
        reset.onAction { [weak self] _ in
            self?.graph.curves = Array(repeating: SplineCurve(), count: 4)
            self?.graph.needsDisplay = true
            self?.push()
        }
        let hint = NSTextField(wrappingLabelWithString: L("Click to add a point, drag to move it, right-click to remove it."))
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hint.preferredMaxLayoutWidth = 280
        body.addArrangedSubview(hint)
        body.addArrangedSubview(reset)
    }
}

final class CurveGraphView: NSView {
    /// R, G, B, luminosity.
    var curves: [SplineCurve] = Array(repeating: SplineCurve(), count: 4)
    var rgbMode = false { didSet { needsDisplay = true } }
    var editMask = [true, true, true]
    var onChange: (() -> Void)?
    var onHover: ((CGPoint?) -> Void)?
    private let histogram: HistogramRGB
    private var dragging: (curve: [Int], index: [Int])?
    private var tracking: NSTrackingArea?

    init(histogram: HistogramRGB) {
        self.histogram = histogram
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }

    private var plot: NSRect { bounds.insetBy(dx: 6, dy: 6) }

    private func toView(_ p: CGPoint) -> NSPoint {
        NSPoint(x: plot.minX + p.x / 255 * plot.width, y: plot.minY + p.y / 255 * plot.height)
    }

    private func toValue(_ p: NSPoint) -> CGPoint {
        CGPoint(x: clampDouble(((p.x - plot.minX) / plot.width * 255).rounded(), 0, 255),
                y: clampDouble(((p.y - plot.minY) / plot.height * 255).rounded(), 0, 255))
    }

    private var activeCurves: [Int] {
        rgbMode ? (0..<3).filter { editMask[$0] } : [3]
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        // Histogram backdrop.
        // Square-root scale so a single dominant value doesn't flatten the rest.
        let lum: [Double] = (0..<256).map { sqrt(Double(histogram.r[$0] + histogram.g[$0] + histogram.b[$0]) / 3) }
        if let mx = lum.max(), mx > 0 {
            NSColor.secondaryLabelColor.withAlphaComponent(0.18).setFill()
            for i in 0..<256 {
                let h = CGFloat(lum[i] / mx) * plot.height
                NSRect(x: plot.minX + CGFloat(i) / 256 * plot.width, y: plot.minY, width: plot.width / 256 + 0.5, height: h).fill()
            }
        }
        NSColor.separatorColor.setStroke()
        for i in 0...4 {
            let x = plot.minX + CGFloat(i) / 4 * plot.width, y = plot.minY + CGFloat(i) / 4 * plot.height
            NSBezierPath.strokeLine(from: NSPoint(x: x, y: plot.minY), to: NSPoint(x: x, y: plot.maxY))
            NSBezierPath.strokeLine(from: NSPoint(x: plot.minX, y: y), to: NSPoint(x: plot.maxX, y: y))
        }
        let colors: [NSColor] = [.systemRed, .systemGreen, .systemBlue, .labelColor]
        let shown = rgbMode ? [0, 1, 2] : [3]
        for ci in shown {
            let t = curves[ci].table()
            let p = NSBezierPath()
            for x in 0..<256 {
                let pt = toView(CGPoint(x: x, y: Int(t[x])))
                if x == 0 { p.move(to: pt) } else { p.line(to: pt) }
            }
            p.lineWidth = activeCurves.contains(ci) ? 2 : 1
            colors[ci].withAlphaComponent(activeCurves.contains(ci) ? 1 : 0.4).setStroke()
            p.stroke()
            if activeCurves.contains(ci) {
                for cp in curves[ci].points {
                    let v = toView(cp)
                    let r = NSRect(x: v.x - 4, y: v.y - 4, width: 8, height: 8)
                    NSColor.white.setFill()
                    NSBezierPath(rect: r).fill()
                    colors[ci].setStroke()
                    NSBezierPath(rect: r).stroke()
                }
            }
        }
        NSColor.separatorColor.setStroke()
        NSBezierPath(rect: plot).stroke()
    }

    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        let v = toValue(p)
        var curveIdx: [Int] = [], pointIdx: [Int] = []
        for ci in activeCurves {
            if let i = curves[ci].points.firstIndex(where: { toView($0).distance(to: p) <= 7 }) {
                curveIdx.append(ci)
                pointIdx.append(i)
            } else {
                var pts = curves[ci].points
                pts.removeAll { abs($0.x - v.x) < 1 }
                pts.append(v)
                curves[ci] = SplineCurve(points: pts)
                curveIdx.append(ci)
                pointIdx.append(curves[ci].points.firstIndex(of: v) ?? 0)
            }
        }
        dragging = (curveIdx, pointIdx)
        needsDisplay = true
        onChange?()
    }

    override func mouseDragged(with e: NSEvent) {
        guard let d = dragging else { return }
        let v = toValue(convert(e.locationInWindow, from: nil))
        var newIdx: [Int] = []
        for (k, ci) in d.curve.enumerated() {
            var pts = curves[ci].points
            let i = d.index[k]
            guard i < pts.count else { newIdx.append(i); continue }
            // Keep x ordering: clamp between neighbours.
            let lo = i > 0 ? pts[i - 1].x + 1 : 0
            let hi = i < pts.count - 1 ? pts[i + 1].x - 1 : 255
            pts[i] = CGPoint(x: clampDouble(v.x, lo, hi), y: v.y)
            curves[ci] = SplineCurve(points: pts)
            newIdx.append(i)
        }
        dragging = (d.curve, newIdx)
        onHover?(v)
        needsDisplay = true
        onChange?()
    }

    override func mouseUp(with e: NSEvent) { dragging = nil }

    override func rightMouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        var changed = false
        for ci in activeCurves {
            var pts = curves[ci].points
            if let i = pts.firstIndex(where: { toView($0).distance(to: p) <= 7 }), pts.count > 2 {
                pts.remove(at: i)
                curves[ci] = SplineCurve(points: pts)
                changed = true
            }
        }
        if changed {
            needsDisplay = true
            onChange?()
        }
    }

    override func mouseMoved(with e: NSEvent) { onHover?(toValue(convert(e.locationInWindow, from: nil))) }
    override func mouseExited(with e: NSEvent) { onHover?(nil) }
}

/// Adjustments > Levels: input/output ranges and gamma per channel, with Auto.
final class LevelsDialog: ModalDialog {
    private let effect: LevelsAdjustment
    private let session: EffectPreviewSession
    private var version = 0
    private var mask = [true, true, true]  // R, G, B
    private var controls: [NumericSliderControl] = []
    private let histogramView: LevelsHistogramView
    private var updating = false

    init(effect: LevelsAdjustment, session: EffectPreviewSession) {
        self.effect = effect
        self.session = session
        histogramView = LevelsHistogramView(histogram: HistogramRGB(surface: session.src, rect: session.env.selectionBounds,
                                                                    mask: session.env.selectionMask))
        super.init(title: L("Levels"))
        build()
    }

    var currentValues: EffectValues {
        var v = EffectValues()
        v["_v"] = .int(version)
        return v
    }

    static func run(effect: LevelsAdjustment, session: EffectPreviewSession, parent: NSWindow?,
                    completion: (EffectValues?) -> Void) {
        let d = LevelsDialog(effect: effect, session: session)
        d.push()
        let ok = d.runModal(parent: parent, beside: true)
        completion(ok ? d.currentValues : nil)
    }

    private func push() {
        version += 1
        histogramView.levels = effect.levels
        session.update(currentValues)
    }

    /// Reads a component of the first edited channel.
    private func read(_ k: Int) -> Double {
        let l = effect.levels
        let ch = mask.firstIndex(of: true) ?? 0
        func pick(_ c: ColorBgra) -> Double { Double([c.r, c.g, c.b][ch]) }
        switch k {
        case 0: return pick(l.inLow)
        case 1: return pick(l.inHigh)
        case 2: return pick(l.outLow)
        case 3: return pick(l.outHigh)
        default: return 1 / [l.gamma.2, l.gamma.1, l.gamma.0][ch]
        }
    }

    private func write(_ k: Int, _ v: Double) {
        var l = effect.levels
        func set(_ c: inout ColorBgra) {
            let b = clampToByte(v)
            if mask[0] { c.r = b }
            if mask[1] { c.g = b }
            if mask[2] { c.b = b }
        }
        switch k {
        case 0: set(&l.inLow)
        case 1: set(&l.inHigh)
        case 2: set(&l.outLow)
        case 3: set(&l.outHigh)
        default:
            let g = 1 / max(0.1, v)
            if mask[0] { l.gamma.2 = g }
            if mask[1] { l.gamma.1 = g }
            if mask[2] { l.gamma.0 = g }
        }
        effect.levels = l
        push()
    }

    private func refreshControls() {
        updating = true
        for (i, c) in controls.enumerated() { c.setValue(read(i), notify: false) }
        updating = false
    }

    private func build() {
        histogramView.translatesAutoresizingMaskIntoConstraints = false
        histogramView.widthAnchor.constraint(equalToConstant: 300).isActive = true
        histogramView.heightAnchor.constraint(equalToConstant: 110).isActive = true
        body.addArrangedSubview(histogramView)
        let specs: [(String, ClosedRange<Double>, Double, Int)] = [
            (L("Input black"), 0...255, 0, 0), (L("Input white"), 0...255, 255, 0), (L("Output black"), 0...255, 0, 0),
            (L("Output white"), 0...255, 255, 0), (L("Gamma"), 0.1...10, 1, 2),
        ]
        for (i, (label, range, def, dec)) in specs.enumerated() {
            let c = NumericSliderControl(range: range, value: def, decimals: dec, defaultValue: def, sliderWidth: 170)
            c.onChange = { [weak self] v in
                guard let self, !self.updating else { return }
                self.write(i, v)
            }
            controls.append(c)
            addRow([formLabel(label, width: 90), c])
        }
        var checks: [NSView] = []
        for (i, name) in [L("Red"), L("Green"), L("Blue")].enumerated() {
            let b = NSButton(checkboxWithTitle: name, target: nil, action: nil)
            b.state = .on
            b.onAction { [weak self] _ in
                self?.mask[i] = b.state == .on
                self?.refreshControls()
            }
            checks.append(b)
        }
        addRow(checks)
        let auto = NSButton(title: L("Auto"), target: nil, action: nil)
        auto.bezelStyle = .rounded
        auto.onAction { [weak self] _ in
            guard let self else { return }
            let h = self.histogramView.histogram
            self.effect.levels = LevelsOp.auto(lo: h.percentileColor(0.005), md: h.meanColor(), hi: h.percentileColor(0.995))
            self.refreshControls()
            self.push()
        }
        let reset = NSButton(title: L("Reset"), target: nil, action: nil)
        reset.bezelStyle = .rounded
        reset.onAction { [weak self] _ in
            self?.effect.levels = .identity
            self?.refreshControls()
            self?.push()
        }
        addRow([auto, reset])
    }
}

final class LevelsHistogramView: NSView {
    let histogram: HistogramRGB
    var levels = LevelsOp.identity { didSet { needsDisplay = true } }

    init(histogram: HistogramRGB) {
        self.histogram = histogram
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        let mx = sqrt(Double(max(1, (histogram.r + histogram.g + histogram.b).max() ?? 1)))
        for (hist, color) in [(histogram.r, NSColor.systemRed), (histogram.g, .systemGreen), (histogram.b, .systemBlue)] {
            let p = NSBezierPath()
            p.move(to: NSPoint(x: 0, y: 0))
            for i in 0..<256 {
                p.line(to: NSPoint(x: CGFloat(i) / 255 * bounds.width, y: CGFloat(sqrt(Double(hist[i])) / mx) * bounds.height * 0.95))
            }
            p.line(to: NSPoint(x: bounds.width, y: 0))
            p.close()
            color.withAlphaComponent(0.3).setFill()
            p.fill()
        }
        // Input range markers.
        let lo = CGFloat(Int(levels.inLow.r) + Int(levels.inLow.g) + Int(levels.inLow.b)) / 765 * bounds.width
        let hi = CGFloat(Int(levels.inHigh.r) + Int(levels.inHigh.g) + Int(levels.inHigh.b)) / 765 * bounds.width
        NSColor.labelColor.setStroke()
        NSBezierPath.strokeLine(from: NSPoint(x: lo, y: 0), to: NSPoint(x: lo, y: bounds.height))
        NSBezierPath.strokeLine(from: NSPoint(x: hi, y: 0), to: NSPoint(x: hi, y: bounds.height))
        NSColor.separatorColor.setStroke()
        NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)).stroke()
    }
}
