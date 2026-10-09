import AppKit
import BrushwoodCore

/// Tiny command language to drive the app for automated visual checks (used with `BRUSHWOOD_SNAPSHOT`).
/// Example: `tool:paintbrush; color:FF0000; width:12; drag:50,50,300,200; key:return`
enum DebugScript {
    private static var lastMark = CFAbsoluteTimeGetCurrent()

    static func run(_ script: String, controller c: MainWindowController) {
        for raw in script.components(separatedBy: ";") {
            let cmd = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cmd.isEmpty else { continue }
            let parts = cmd.split(separator: ":", maxSplits: 1).map(String.init)
            let name = parts[0], arg = parts.count > 1 ? parts[1] : ""
            let nums = arg.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            let flags = Set(arg.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            let right = flags.contains("right")
            var mods: NSEvent.ModifierFlags = []
            if flags.contains("cmd") { mods.insert(.command) }
            if flags.contains("shift") { mods.insert(.shift) }
            if flags.contains("opt") { mods.insert(.option) }
            switch name {
            case "tool":
                if let k = ToolKind.allCases.first(where: { "\($0)".lowercased() == arg.lowercased() }) { c.selectTool(k) }
            case "color":
                let fields = arg.split(separator: ",")
                if let col = ColorBgra(hex: String(fields[0])) {
                    if fields.count > 1 { AppEnvironment.shared.secondaryColor = col } else { AppEnvironment.shared.primaryColor = col }
                }
            case "width": AppEnvironment.shared.tools.brushWidth = CGFloat(nums.first ?? 2)
            case "shape": AppEnvironment.shared.tools.shapeType = ShapeKind(rawValue: Int(nums.first ?? 0)) ?? .rectangle
            case "drawtype": AppEnvironment.shared.tools.shapeDrawType = ShapeDrawType(rawValue: Int(nums.first ?? 0)) ?? .outline
            case "gradient": AppEnvironment.shared.tools.gradientType = GradientType(rawValue: Int(nums.first ?? 0)) ?? .linear
            case "zoom": c.canvas.setZoom(CGFloat(nums.first ?? 1))
            case "click" where nums.count >= 2:
                let p = CGPoint(x: nums[0], y: nums[1])
                send(c, .down, p, right, mods)
                send(c, .up, p, right, mods)
            case "drag" where nums.count >= 4:
                let a = CGPoint(x: nums[0], y: nums[1]), b = CGPoint(x: nums[2], y: nums[3])
                send(c, .down, a, right, mods)
                for i in 1...12 {
                    let t = CGFloat(i) / 12
                    send(c, .drag, CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), right, mods)
                }
                send(c, .up, b, right, mods)
            case "type":
                (c.canvas.tool as? TextTool)?.insert(arg.replacingOccurrences(of: "\\n", with: "\n"))
            case "key":
                if arg == "return" { c.canvas.tool?.commit() } else if arg == "escape" { c.canvas.tool?.cancel() }
            case "menu":
                if c.responds(to: Selector(arg)) {
                    NSApp.sendAction(Selector(arg), to: c, from: nil)
                } else if let d = NSApp.delegate as? NSObject, d.responds(to: Selector(arg)) {
                    NSApp.sendAction(Selector(arg), to: d, from: nil)
                } else {
                    report(false, "unknown action \(arg)")
                }
            case "effect":
                let all = EffectsCatalog.adjustments + EffectsCatalog.effects.flatMap(\.1)
                if let f = all.first(where: { $0().name.lowercased() == arg.lowercased() }) {
                    c.runEffect(factory: f, repeatValues: EffectValues(f().parameters))
                }
            case "dialog":
                // dialog:Effect Name[|id=value...] opens the effect's dialog, starting from the given values.
                if let (factory, values) = effectValues(arg) {
                    if arg.contains("|") { EffectDialog.remembered[factory().id] = values }
                    performOnMain { c.runEffect(factory: factory) }
                }
            case "press":
                // press:Title clicks a visible button with that title in any window (dialogs, sheets, Software Update).
                let button = NSApp.windows.filter(\.isVisible).lazy.compactMap { $0.contentView.flatMap { findButton(titled: arg, in: $0) } }.first
                if let button { button.performClick(nil) } else { report(false, "no visible button '\(arg)'") }
            case "colorsmore": c.colorsPanel.debugToggleExpanded()
            case "expect" where nums.count >= 2:
                // expect:x,y,RRGGBB[AA][,tolerance] on the flattened image.
                let fields = arg.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                guard let doc = c.active?.document, fields.count >= 3, let want = ColorBgra(hex: fields[2]) else { break }
                let tol = fields.count > 3 ? Int(fields[3]) ?? 3 : 3
                let got = doc.flattened()[Int(nums[0]), Int(nums[1])]
                let ok = abs(Int(got.r) - Int(want.r)) <= tol && abs(Int(got.g) - Int(want.g)) <= tol
                    && abs(Int(got.b) - Int(want.b)) <= tol && abs(Int(got.a) - Int(want.a)) <= tol
                report(ok, "pixel \(fields[0]),\(fields[1]) = \(got.hexString), expected \(want.hexString)")
            case "expectactivelayer": report(c.active?.document.activeLayerIndex == Int(nums.first ?? -1),
                                             "active layer = \(c.active?.document.activeLayerIndex ?? -1), expected \(arg)")
            case "wait":
                // Lets timers fire (deferred refreshes such as layer thumbnails) before the next command.
                RunLoop.current.run(until: Date(timeIntervalSinceNow: nums.first ?? 0.5))
            case "expectlayers": report(c.active?.document.layers.count == Int(nums.first ?? -1),
                                        "layers = \(c.active?.document.layers.count ?? -1), expected \(arg)")
            case "expectsize": report(c.active?.document.width == Int(nums.first ?? -1) && c.active?.document.height == Int(nums.last ?? -1),
                                      "size = \(c.active?.document.width ?? 0)x\(c.active?.document.height ?? 0), expected \(arg)")
            case "expecthistory": report(c.active?.document.history.currentIndex == Int(nums.first ?? -1),
                                         "history index = \(c.active?.document.history.currentIndex ?? -1), expected \(arg); items: "
                                            + (c.active?.document.history.items.map(\.name).joined(separator: " | ") ?? ""))
            case "expectselection":
                let b = c.active?.document.selection?.intBounds
                if arg == "none" {
                    report(b == nil, "selection = \(b.map { "\($0)" } ?? "none"), expected none")
                } else {
                    report(b == IntRect(x: Int(nums[0]), y: Int(nums[1]), width: Int(nums[2]), height: Int(nums[3])),
                           "selection = \(b.map { "\($0)" } ?? "none"), expected \(arg)")
                }
            case "log": print("LOG \(arg)")
            case "widthcombo":
                // widthcombo:select,25 | widthcombo:type,40 | widthcombo:wheel,up|down | widthcombo:blur
                guard let combo = c.optionsBar.brushWidthCombo else {
                    report(false, "no brush width combo")
                    break
                }
                let f = arg.split(separator: ",").map(String.init)
                switch f[0] {
                case "select":
                    let i = combo.indexOfItem(withObjectValue: f[1])
                    combo.selectItem(at: i)
                case "type":
                    // Real typing path: focus the field, replace its text through the field editor.
                    c.window?.makeFirstResponder(combo)
                    if let editor = combo.currentEditor() as? NSTextView {
                        editor.selectAll(nil)
                        editor.insertText(f[1], replacementRange: editor.selectedRange())
                    }
                case "wheel":
                    if let cg = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: f[1] == "up" ? 3 : -3,
                                        wheel2: 0, wheel3: 0), let e = NSEvent(cgEvent: cg) {
                        combo.scrollWheel(with: e)
                    }
                case "blur":
                    c.window?.makeFirstResponder(c.canvas)
                default: break
                }
            case "scrollby" where nums.count >= 2:
                // Same effect as dragging with the Pan tool by (-dx, -dy).
                if let clip = c.canvas.clipView {
                    c.canvas.pan(to: NSPoint(x: clip.bounds.origin.x + nums[0], y: clip.bounds.origin.y + nums[1]), clip: clip)
                }
            case "expectonscreen":
                // expectonscreen:minX,minY — where the image's top-left corner sits inside the viewport (view points).
                if let clip = c.canvas.clipView {
                    let r = c.canvas.imageRectInView.offsetBy(dx: -clip.bounds.minX, dy: -clip.bounds.minY)
                    let ok = abs(r.minX - nums[0]) <= 2 && abs(r.minY - nums[1]) <= 2
                    report(ok, "image top-left in viewport = (\(Int(r.minX)), \(Int(r.minY))), expected \(arg)")
                }
            case "expectfreescroll":
                report(!c.scrollView.usesPredominantAxisScrolling, "trackpad scrolling is not locked to one axis")
            case "expectpanlimits":
                // Pans to both extremes: the image can leave the viewport until only `keepVisible` points remain.
                guard let clip = c.canvas.clipView else { break }
                let k = c.canvas.keepVisible
                c.canvas.pan(to: NSPoint(x: -1e9, y: -1e9), clip: clip)
                var r = c.canvas.imageRectInView.offsetBy(dx: -clip.bounds.minX, dy: -clip.bounds.minY)
                report(abs(r.minX - (clip.bounds.width - k)) <= 1 && abs(r.minY - (clip.bounds.height - k)) <= 1,
                       "pushed to bottom-right: image top-left at (\(Int(r.minX)), \(Int(r.minY))) in a \(Int(clip.bounds.width))×\(Int(clip.bounds.height)) viewport")
                c.canvas.pan(to: NSPoint(x: 1e9, y: 1e9), clip: clip)
                r = c.canvas.imageRectInView.offsetBy(dx: -clip.bounds.minX, dy: -clip.bounds.minY)
                report(abs(r.maxX - k) <= 1 && abs(r.maxY - k) <= 1,
                       "pushed to top-left: image bottom-right at (\(Int(r.maxX)), \(Int(r.maxY)))")
                c.canvas.centerImage()
                r = c.canvas.imageRectInView.offsetBy(dx: -clip.bounds.minX, dy: -clip.bounds.minY)
                report(abs(r.midX - clip.bounds.width / 2) <= 1 && abs(r.midY - clip.bounds.height / 2) <= 1, "re-centered")
            case "expectwidth":
                let w = AppEnvironment.shared.tools.brushWidth
                report(abs(w - CGFloat(nums.first ?? -1)) < 0.01, "brush width = \(w), expected \(arg)")
            case "keyeq":
                // keyeq:z,cmd[,shift] sends a real key event through NSApp (menu key equivalents, validation,
                // responder chain), the same path as typing on the keyboard.
                let f = arg.split(separator: ",").map(String.init)
                var flags: NSEvent.ModifierFlags = []
                if f.contains("cmd") { flags.insert(.command) }
                if f.contains("shift") { flags.insert(.shift) }
                if f.contains("opt") { flags.insert(.option) }
                let key = f[0] == "delete" ? "\u{8}" : f[0]
                let codes: [String: UInt16] = ["z": 6, "y": 16, "a": 0, "d": 2, "\u{8}": 51, "=": 24, "+": 24, "-": 27, "n": 45,
                                               "i": 34, "s": 1, "c": 8, "v": 9, "x": 7, "f": 3, "b": 11, "l": 37]
                for type in [NSEvent.EventType.keyDown, .keyUp] {
                    if let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                                windowNumber: c.window?.windowNumber ?? 0, context: nil,
                                                characters: flags.contains(.shift) ? key.uppercased() : key,
                                                // Like a real keyboard: Shift still applies to charactersIgnoringModifiers.
                                                charactersIgnoringModifiers: flags.contains(.shift) ? key.uppercased() : key,
                                                isARepeat: false, keyCode: codes[key] ?? 0) {
                        NSApp.sendEvent(e)
                    }
                }
            case "setting":
                // setting:name=value for a few tool options (exercises live re-rendering of pending edits).
                let kv = arg.split(separator: "=").map(String.init)
                guard kv.count == 2 else { break }
                let t = AppEnvironment.shared.tools
                switch kv[0] {
                case "tolerance": t.tolerance = Double(kv[1]) ?? 0.5
                case "antialias": t.antialiasing = kv[1] == "1"
                case "fill": t.fillStyle = FillStyle(rawValue: Int(kv[1]) ?? 0) ?? .solid
                case "flood": t.floodMode = FloodMode(rawValue: Int(kv[1]) ?? 0) ?? .contiguous
                case "blend": t.blendMode = BlendMode(rawValue: Int(kv[1]) ?? 0) ?? .normal
                case "overwrite": t.overwrite = kv[1] == "1"
                case "endcap": t.endCap = LineCap(rawValue: Int(kv[1]) ?? 0) ?? .flat
                case "align": t.textAlignment = TextAlignmentOption(rawValue: Int(kv[1]) ?? 0) ?? .left
                case "fontsize": t.fontSize = CGFloat(Double(kv[1]) ?? 12)
                case "pickafter": t.colorPickerAfterClick = ColorPickerAfterClick(rawValue: Int(kv[1]) ?? 0) ?? .doNotSwitch
                case "transparency": t.gradientTransparencyMode = kv[1] == "1"
                default: print("FAIL unknown setting \(kv[0])")
                }
            case "expecttext":
                let got = (c.canvas.tool as? TextTool)?.debugText ?? "<no text tool>"
                let want = arg.replacingOccurrences(of: "|", with: "\n")
                report(got == want, "text = \(got.debugDescription), expected \(want.debugDescription)")
            case "textcmd":
                (c.canvas.tool as? TextTool)?.perform(Selector(arg))
            case "expectcolor":
                // expectcolor:primary|secondary,RRGGBB
                let f = arg.split(separator: ",").map(String.init)
                let got = f[0] == "secondary" ? AppEnvironment.shared.secondaryColor : AppEnvironment.shared.primaryColor
                report(ColorBgra(hex: f[1]) == got, "\(f[0]) color = \(got.hexString), expected \(f[1])")
            case "expecttool":
                report("\(AppEnvironment.shared.activeTool)".lowercased() == arg.lowercased(),
                       "tool = \(AppEnvironment.shared.activeTool), expected \(arg)")
            case "expectzoom":
                report(abs(c.canvas.zoom - CGFloat(nums.first ?? 0)) < 0.001, "zoom = \(c.canvas.zoom), expected \(arg)")
            case "expectimages":
                report(c.workspaces.count == Int(nums.first ?? -1), "images = \(c.workspaces.count), expected \(arg)")
            case "layerprops":
                // layerprops:opacity,blendRaw,visible(0/1)
                if let ws = c.active, nums.count >= 3 {
                    var p = ws.document.activeLayer.properties
                    p.opacity = UInt8(nums[0])
                    p.blendMode = BlendMode(rawValue: Int(nums[1])) ?? .normal
                    p.isVisible = nums[2] != 0
                    ws.setLayerProperties(ws.document.activeLayerIndex, p)
                }
            case "effectvalues":
                // effectvalues:Effect Name|id=value|id=value (repeat with explicit values)
                if let (factory, values) = effectValues(arg) { c.runEffect(factory: factory, repeatValues: values) }
            case "resize" where nums.count >= 2:
                c.active?.resizeImage(to: IntSize(width: Int(nums[0]), height: Int(nums[1])), mode: .bestQuality, dpi: 96)
            case "canvassize" where nums.count >= 4:
                c.active?.resizeCanvas(to: IntSize(width: Int(nums[0]), height: Int(nums[1])), anchor: (Int(nums[2]), Int(nums[3])), dpi: 96)
            case "activate" where !nums.isEmpty:
                let i = Int(nums[0])
                if i < c.workspaces.count { c.activate(c.workspaces[i]) }
            case "time":
                let now = CFAbsoluteTimeGetCurrent()
                print(String(format: "TIME %@: %.0f ms", arg, (now - lastMark) * 1000))
                fflush(stdout)
                lastMark = now
            case "open": c.open(urls: [URL(fileURLWithPath: arg)])
            case "new" where nums.count >= 2: c.newImage(width: Int(nums[0]), height: Int(nums[1]), background: .white, dpi: 96)
            case "save":
                if let ws = c.active, let t = FileType.forExtension((arg as NSString).pathExtension) {
                    try? ImageCodec.save(ws.document, to: URL(fileURLWithPath: arg), type: t, options: SaveOptions())
                }
            case "select" where nums.count >= 4:
                c.active?.changeSelection(to: Selection.rect(CGRect(x: nums[0], y: nums[1], width: nums[2], height: nums[3])),
                                          name: "Select")
            case "fitreport":
                // Localization check: lists controls too narrow for their text, for every tool's options and every window.
                for t in ToolKind.allCases {
                    c.selectTool(t)
                    c.window?.contentView?.layoutSubtreeIfNeeded()
                    reportFit(c.optionsBar, context: "tool \(t)")
                    if c.optionsBar.contentWidth > c.optionsBar.bounds.width {
                        print("WRAPS tool \(t) needs \(Int(c.optionsBar.contentWidth)) of \(Int(c.optionsBar.bounds.width))")
                    }
                }
                for w in NSApp.windows where w.isVisible {
                    guard let v = w.contentView else { continue }
                    v.layoutSubtreeIfNeeded()
                    reportFit(v, context: "window '\(w.title)'")
                    if v.fittingSize.width > v.bounds.width + 1 {
                        print("OVERFLOW window '\(w.title)' needs \(Int(v.fittingSize.width)) of \(Int(v.bounds.width))")
                    }
                }
                fflush(stdout)
            case "panel":
                let f = c.window!.frame
                c.window?.setFrame(NSRect(x: f.minX, y: f.minY, width: nums.first ?? f.width, height: nums.count > 1 ? nums[1] : f.height),
                                   display: true)
            default:
                NSLog("DebugScript: unknown command \(cmd)")
            }
        }
    }

    private enum Phase { case down, drag, up }

    private static func findButton(titled title: String, in view: NSView) -> NSButton? {
        if let b = view as? NSButton, b.title == title, !b.isHidden { return b }
        for sub in view.subviews { if let b = findButton(titled: title, in: sub) { return b } }
        return nil
    }

    /// Parses `Effect Name|id=value|id=value` into the effect's factory and its values (defaults for the others).
    private static func effectValues(_ arg: String) -> (() -> Effect, EffectValues)? {
        let f = arg.split(separator: "|").map(String.init)
        let all = EffectsCatalog.adjustments + EffectsCatalog.effects.flatMap(\.1) + [{ RotateZoomLayerEffect() }]
        guard let factory = all.first(where: { $0().name.lowercased() == f[0].lowercased() }) else { return nil }
        var v = EffectValues(factory().parameters)
        for kv in f.dropFirst() {
            let p = kv.split(separator: "=").map(String.init)
            if p.count == 2, let d = Double(p[1]) {
                if case .int = v[p[0]] { v[p[0]] = .int(Int(d)) } else if case .bool = v[p[0]] { v[p[0]] = .bool(d != 0) } else { v[p[0]] = .double(d) }
            }
        }
        return (factory, v)
    }

    private static func reportFit(_ v: NSView, context: String) {
        for sub in v.subviews where !sub.isHidden {
            if let ctl = sub as? NSControl, !(ctl is NSSlider), !(ctl is NSStepper),
               (ctl as? NSPopUpButton)?.imagePosition != .imageOnly {
                var need = ctl.intrinsicContentSize.width
                if let p = ctl as? NSPopUpButton, let font = p.font, p.imagePosition != .imageOnly {
                    // A pop-up's intrinsic width fits its widest item; only the selected one is shown.
                    func w(_ s: String) -> CGFloat { (s as NSString).size(withAttributes: [.font: font]).width }
                    let chrome = need - (p.itemTitles.map(w).max() ?? 0)
                    need = chrome + w(p.titleOfSelectedItem ?? "")
                    let long = p.itemTitles.filter { !$0.isEmpty && chrome + w($0) > p.frame.width + 1 }
                    if !long.isEmpty { print("ITEMS \(context) [\(Int(p.frame.width))] " + long.joined(separator: " | ")) }
                }
                if need != NSView.noIntrinsicMetric, need > ctl.frame.width + 1 {
                    let text = (ctl as? NSPopUpButton)?.titleOfSelectedItem ?? (ctl as? NSButton)?.title ?? ctl.stringValue
                    print("TRUNC \(context) \(type(of: ctl)) '\(text)' needs \(Int(need)) of \(Int(ctl.frame.width))")
                }
            }
            reportFit(sub, context: context)
        }
    }

    private static func report(_ ok: Bool, _ message: String) {
        print("\(ok ? "PASS" : "FAIL") \(message)")
        fflush(stdout)
    }

    private static func send(_ c: MainWindowController, _ phase: Phase, _ p: CGPoint, _ right: Bool,
                             _ mods: NSEvent.ModifierFlags = []) {
        guard let tool = c.canvas.tool else { return }
        let e = ToolEvent(point: p, viewPoint: c.canvas.toView(p), button: right ? .right : .left, modifiers: mods, clickCount: 1,
                          pressure: 1)
        switch phase {
        case .down: tool.mouseDown(e)
        case .drag: tool.mouseDragged(e)
        case .up: tool.mouseUp(e)
        }
    }
}
