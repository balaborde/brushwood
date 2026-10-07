import AppKit
import BrushwoodCore

/// Tiny command language to drive the app for automated visual checks (used with `BRUSHWOOD_SNAPSHOT`).
/// Example: `tool:paintbrush; color:FF0000; width:12; drag:50,50,300,200; key:return`
enum DebugScript {
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
                NSApp.sendAction(Selector(arg), to: c, from: nil)
            case "effect":
                let all = EffectsCatalog.adjustments + EffectsCatalog.effects.flatMap(\.1)
                if let f = all.first(where: { $0().name.lowercased() == arg.lowercased() }) {
                    c.runEffect(factory: f, repeatValues: EffectValues(f().parameters))
                }
            case "dialog":
                let all = EffectsCatalog.adjustments + EffectsCatalog.effects.flatMap(\.1)
                if let f = all.first(where: { $0().name.lowercased() == arg.lowercased() }) {
                    performOnMain { c.runEffect(factory: f) }
                }
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
            case "open": c.open(urls: [URL(fileURLWithPath: arg)])
            case "new" where nums.count >= 2: c.newImage(width: Int(nums[0]), height: Int(nums[1]), background: .white, dpi: 96)
            case "save":
                if let ws = c.active, let t = FileType.forExtension((arg as NSString).pathExtension) {
                    try? ImageCodec.save(ws.document, to: URL(fileURLWithPath: arg), type: t, options: SaveOptions())
                }
            case "select" where nums.count >= 4:
                c.active?.changeSelection(to: Selection.rect(CGRect(x: nums[0], y: nums[1], width: nums[2], height: nums[3])),
                                          name: "Select")
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
