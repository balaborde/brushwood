import AppKit
import BrushwoodCore

/// Auto-generated effect dialog (Paint.NET's IndirectUI equivalent) with live preview.
final class EffectDialog: ModalDialog {
    private var values: EffectValues
    private let effect: Effect
    private let session: EffectPreviewSession
    private var resetters: [() -> Void] = []
    /// Last settings per effect, remembered for the app session like Paint.NET.
    private static var remembered: [String: EffectValues] = [:]

    init(effect: Effect, session: EffectPreviewSession) {
        self.effect = effect
        self.session = session
        var v = EffectValues(effect.parameters)
        if let last = EffectDialog.remembered[effect.id] {
            for (k, val) in last.values where v.values[k] != nil { v.values[k] = val }
        }
        values = v
        super.init(title: L(effect.name))
        build()
    }

    static func run(effect: Effect, session: EffectPreviewSession, parent: NSWindow?, completion: (EffectValues?) -> Void) {
        let d = EffectDialog(effect: effect, session: session)
        d.session.update(d.values)
        let ok = d.runModal(parent: parent, beside: true)
        if ok { remembered[effect.id] = d.values }
        completion(ok ? d.values : nil)
    }

    private func changed() {
        session.update(values)
    }

    private func build() {
        if let hint = effect.requiresSelectionHint, session.workspace.document.selection == nil {
            let l = NSTextField(wrappingLabelWithString: L(hint))
            l.textColor = .secondaryLabelColor
            l.preferredMaxLayoutWidth = 340
            body.addArrangedSubview(l)
        }
        for p in effect.parameters {
            switch p {
            case .integer(let id, let label, let range, let def):
                addSection(L(label))
                let span = Double(range.upperBound - range.lowerBound)
                let c = NumericSliderControl(range: Double(range.lowerBound)...Double(range.upperBound), value: values.double(id),
                                             decimals: 0, defaultValue: Double(def), curved: span > 300 && range.lowerBound >= 0)
                c.onChange = { [weak self] v in
                    self?.values[id] = .int(Int(v))
                    self?.changed()
                }
                body.addArrangedSubview(c)
            case .double(let id, let label, let range, let def, let decimals):
                addSection(L(label))
                let c = NumericSliderControl(range: range, value: values.double(id), decimals: decimals, defaultValue: def,
                                             curved: range.upperBound - range.lowerBound > 300 && range.lowerBound >= 0)
                c.onChange = { [weak self] v in
                    self?.values[id] = .double(v)
                    self?.changed()
                }
                body.addArrangedSubview(c)
            case .angle(let id, let label, let range, let def):
                addSection(L(label))
                let chooser = AngleChooserView()
                chooser.angle = values.double(id)
                let c = NumericSliderControl(range: range, value: values.double(id), decimals: 2, defaultValue: def, sliderWidth: 140)
                chooser.onChange = { [weak self] a in
                    var v = a
                    if range.lowerBound >= 0 && v < 0 { v += 360 }
                    if range.lowerBound < 0 && v > 180 { v -= 360 }
                    c.setValue(v, notify: false)
                    self?.values[id] = .double(c.value)
                    self?.changed()
                }
                c.onChange = { [weak self] v in
                    chooser.angle = v
                    self?.values[id] = .double(v)
                    self?.changed()
                }
                addRow([chooser, c])
            case .offset(let id, let label, let def):
                addSection(L(label))
                let pan = PanChooserView(surface: session.src)
                pan.point = values.point(id)
                let fx = numberField(Double(pan.point.x), decimals: 2, width: 60)
                let fy = numberField(Double(pan.point.y), decimals: 2, width: 60)
                let apply: (CGPoint) -> Void = { [weak self] pt in
                    pan.point = pt
                    fx.doubleValue = Double(pt.x)
                    fy.doubleValue = Double(pt.y)
                    self?.values[id] = .point(pt)
                    self?.changed()
                }
                pan.onChange = apply
                fx.onAction { _ in apply(CGPoint(x: clampDouble(fx.doubleValue, -2, 2), y: pan.point.y)) }
                fy.onAction { _ in apply(CGPoint(x: pan.point.x, y: clampDouble(fy.doubleValue, -2, 2))) }
                let reset = NSButton(image: NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: L("Reset"))!,
                                     target: nil, action: nil)
                reset.isBordered = false
                reset.onAction { _ in apply(def) }
                let fields = NSStackView(views: [NSTextField(labelWithString: "X"), fx, NSTextField(labelWithString: "Y"), fy, reset])
                fields.orientation = .horizontal
                let col = NSStackView(views: [pan, fields])
                col.orientation = .vertical
                col.alignment = .leading
                body.addArrangedSubview(col)
            case .checkbox(let id, let label, _):
                let b = NSButton(checkboxWithTitle: L(label), target: nil, action: nil)
                b.state = values.bool(id) ? .on : .off
                b.onAction { [weak self] _ in
                    self?.values[id] = .bool(b.state == .on)
                    self?.changed()
                }
                body.addArrangedSubview(b)
            case .choice(let id, let label, let options, _, _):
                addSection(L(label))
                let pop = NSPopUpButton(frame: .zero, pullsDown: false)
                pop.addItems(withTitles: options.map { L($0) })
                pop.selectItem(at: values.int(id))
                pop.onAction { [weak self] _ in
                    self?.values[id] = .int(pop.indexOfSelectedItem)
                    self?.changed()
                }
                body.addArrangedSubview(pop)
            case .seed(let id, let label):
                addSection(L(label))
                let b = NSButton(title: L("Reseed"), target: nil, action: nil)
                b.bezelStyle = .rounded
                b.onAction { [weak self] _ in
                    self?.values[id] = .int(Int(arc4random_uniform(UInt32(Int32.max))))
                    self?.changed()
                }
                body.addArrangedSubview(b)
            case .color(let id, let label, _):
                addSection(L(label))
                let swatch = ColorSwatchButton(color: values.color(id))
                swatch.widthAnchor.constraint(equalToConstant: 40).isActive = true
                swatch.heightAnchor.constraint(equalToConstant: 24).isActive = true
                let set: (ColorBgra) -> Void = { [weak self] c in
                    swatch.color = c
                    self?.values[id] = .color(c)
                    self?.changed()
                }
                let primary = NSButton(title: L("Primary"), target: nil, action: nil)
                primary.bezelStyle = .rounded
                primary.controlSize = .small
                primary.onAction { _ in set(AppEnvironment.shared.primaryColor) }
                let secondary = NSButton(title: L("Secondary"), target: nil, action: nil)
                secondary.bezelStyle = .rounded
                secondary.controlSize = .small
                secondary.onAction { _ in set(AppEnvironment.shared.secondaryColor) }
                swatch.onClick = {
                    let panel = NSColorPanel.shared
                    panel.showsAlpha = true
                    panel.color = swatch.color.nsColor
                    let target = ClosureColorTarget { set(ColorBgra(nsColor: $0)) }
                    ClosureColorTarget.current = target
                    panel.setTarget(target)
                    panel.setAction(#selector(ClosureColorTarget.changed(_:)))
                    panel.orderFront(nil)
                }
                addRow([swatch, primary, secondary])
            }
        }
    }
}

final class ClosureColorTarget: NSObject {
    static var current: ClosureColorTarget?
    let handler: (NSColor) -> Void
    init(_ h: @escaping (NSColor) -> Void) { handler = h }
    @objc func changed(_ sender: NSColorPanel) { handler(sender.color) }
}

/// Circular angle picker (0° = east, counter-clockwise positive).
final class AngleChooserView: NSView {
    var angle: Double = 0 { didSet { needsDisplay = true } }
    var onChange: ((Double) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 56, height: 56))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 56).isActive = true
        heightAnchor.constraint(equalToConstant: 56).isActive = true
    }

    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 3, dy: 3)
        let circle = NSBezierPath(ovalIn: r)
        NSColor.controlBackgroundColor.setFill()
        circle.fill()
        NSColor.separatorColor.setStroke()
        circle.stroke()
        let c = NSPoint(x: r.midX, y: r.midY)
        let a = angle * .pi / 180
        let p = NSPoint(x: c.x + cos(a) * r.width / 2, y: c.y + sin(a) * r.height / 2)
        let line = NSBezierPath()
        line.move(to: c)
        line.line(to: p)
        line.lineWidth = 2
        NSColor.controlAccentColor.setStroke()
        line.stroke()
        NSColor.controlAccentColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)).fill()
    }

    private func pick(_ e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        var a = atan2(Double(p.y - bounds.midY), Double(p.x - bounds.midX)) * 180 / .pi
        if e.modifierFlags.contains(.shift) { a = (a / 15).rounded() * 15 }
        angle = a
        onChange?(a)
    }

    override func mouseDown(with e: NSEvent) { pick(e) }
    override func mouseDragged(with e: NSEvent) { pick(e) }
}

/// Offset picker over a thumbnail of the layer; point coordinates are in [-1, 1] relative to the image.
final class PanChooserView: NSView {
    var point: CGPoint = .zero { didSet { needsDisplay = true } }
    var onChange: ((CGPoint) -> Void)?
    private let thumb: NSImage?

    init(surface: Surface) {
        if let t = Resampler.thumbnail(of: surface, maxSize: 180), let cg = t.makeCGImage() {
            thumb = NSImage(cgImage: cg, size: NSSize(width: t.width, height: t.height))
        } else {
            thumb = nil
        }
        super.init(frame: .zero)
        let s = thumb?.size ?? NSSize(width: 160, height: 120)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: max(60, s.width)).isActive = true
        heightAnchor.constraint(equalToConstant: max(45, s.height)).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        Checkerboard.draw(in: bounds, cell: 5)
        thumb?.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 0.85, respectFlipped: true, hints: nil)
        NSColor.separatorColor.setStroke()
        NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)).stroke()
        let c = NSPoint(x: bounds.midX + point.x * bounds.width / 2, y: bounds.midY + point.y * bounds.height / 2)
        let p = NSBezierPath()
        p.move(to: NSPoint(x: c.x - 8, y: c.y)); p.line(to: NSPoint(x: c.x + 8, y: c.y))
        p.move(to: NSPoint(x: c.x, y: c.y - 8)); p.line(to: NSPoint(x: c.x, y: c.y + 8))
        p.lineWidth = 3
        NSColor.white.setStroke()
        p.stroke()
        p.lineWidth = 1
        NSColor.black.setStroke()
        p.stroke()
    }

    private func pick(_ e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        let pt = CGPoint(x: clampDouble((p.x - bounds.midX) / (bounds.width / 2), -2, 2),
                         y: clampDouble((p.y - bounds.midY) / (bounds.height / 2), -2, 2))
        point = CGPoint(x: (pt.x * 100).rounded() / 100, y: (pt.y * 100).rounded() / 100)
        onChange?(point)
    }

    override func mouseDown(with e: NSEvent) { pick(e) }
    override func mouseDragged(with e: NSEvent) { pick(e) }
}
