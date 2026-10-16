import AppKit
import BrushwoodCore

/// One step of a guided project: what to do, and a check of the image that tells when it is done.
struct ProjectStep {
    let title: String
    let text: String
    /// Shows the finished picture, the goal of the project.
    var showsGoal = false
    /// Colors that "Use These Colors" makes the primary and secondary colors.
    var colors: (primary: ColorBgra, secondary: ColorBgra)?
    /// A Brushwood Plus tip, shown while its feature is on.
    var plusTip: (feature: PlusFeature, text: String)?
    /// The Brushwood Plus feature the step is about: skipped while it is off.
    var requires: PlusFeature?
    /// The part of the window to ring.
    var target: ((MainWindowController) -> NSView?)?
    /// Notes how the image is when the step begins, for checks that look at what changed.
    var onBegin: ((ProjectContext) -> Void)?
    var check: (ProjectContext) -> Bool = { _ in true }
    /// Remembers what later steps need (a layer, an area), once the step is done.
    var onDone: ((ProjectContext) -> Void)?

    var isAvailable: Bool { requires?.isEnabled ?? true }
    /// The Plus tip to show, if its feature is on.
    var activePlusTip: String? { plusTip.flatMap { $0.feature.isEnabled ? $0.text : nil } }
}

/// What a step's check sees: the project's image as it is now, and as it was when the step began.
struct ProjectContext {
    let host: MainWindowController
    let workspace: DocumentWorkspace
    let project: ProjectGuide
    var doc: Document { workspace.document }

    /// A layer created during the step (the active one when there are several).
    var newLayer: BitmapLayer? {
        let new = doc.layers.filter { !project.baselineLayers.contains(ObjectIdentifier($0)) }
        return new.first { $0 === doc.activeLayer } ?? new.last
    }

    /// Whether the layer's name differs from the one it had when it appeared.
    func renamed(_ layer: BitmapLayer?) -> Bool {
        guard let layer else { return false }
        let first = project.firstNames[ObjectIdentifier(layer)] ?? layer.name
        return !layer.name.trimmingCharacters(in: .whitespaces).isEmpty && layer.name != first
    }

    /// A layer remembered by an earlier step, if it is still in the image.
    func layer(_ role: String) -> BitmapLayer? {
        guard let l = project.roles[role]?.layer, doc.layers.contains(where: { $0 === l }) else { return nil }
        return l
    }

    func remember(_ layer: BitmapLayer?, as role: String) {
        if let layer { project.roles[role] = WeakLayer(layer: layer) }
    }

    /// The names of the history steps made since the step began.
    var newHistoryNames: [String] {
        let items = doc.history.items
        let start = items.firstIndex { $0 === project.baselineHistoryItem }.map { $0 + 1 } ?? 0
        let end = min(doc.history.currentIndex, items.count - 1)
        return start <= end ? items[start...end].map(\.name) : []
    }

    var currentHistoryName: String? { doc.history.currentItem?.name }

    /// How many pixels of the layer, sampled every `step` pixels in `rect`, match.
    func count(_ layer: BitmapLayer?, _ rect: IntRect, step: Int = 4, _ match: (ColorBgra) -> Bool) -> Int {
        guard let s = layer?.surface else { return 0 }
        let r = rect.intersection(s.bounds)
        guard !r.isEmpty else { return 0 }
        var n = 0
        for y in stride(from: r.top, to: r.bottom, by: step) {
            let row = s.row(y)
            for x in stride(from: r.left, to: r.right, by: step) where match(row[x]) { n += 1 }
        }
        return n
    }

    /// The share of `of`'s opaque samples that `layer` matches at `map(x, y)` (a duplicate: identity; a flipped copy).
    func matchRatio(_ layer: BitmapLayer?, _ of: BitmapLayer?, map: (Int, Int) -> (Int, Int)) -> Double {
        guard let a = layer?.surface, let b = of?.surface, a.width == b.width, a.height == b.height else { return 0 }
        var total = 0, same = 0
        for y in stride(from: 0, to: b.height, by: 6) {
            for x in stride(from: 0, to: b.width, by: 6) where b[x, y].a > 128 {
                total += 1
                let (mx, my) = map(x, y)
                let p = a[mx, my], q = b[x, y]
                if abs(Int(p.r) - Int(q.r)) + abs(Int(p.g) - Int(q.g)) + abs(Int(p.b) - Int(q.b)) + abs(Int(p.a) - Int(q.a)) < 24 {
                    same += 1
                }
            }
        }
        return total < 50 ? 0 : Double(same) / Double(total)
    }
}

struct WeakLayer {
    weak var layer: BitmapLayer?
}

extension ColorBgra {
    /// Perceived brightness, 0…1.
    var luminance: Double { (0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b)) / 255 }
    var isOpaque: Bool { a > 200 }
    /// Near the color, channel by channel.
    func near(_ c: ColorBgra, _ tolerance: Int = 60) -> Bool {
        abs(Int(r) - Int(c.r)) + abs(Int(g) - Int(c.g)) + abs(Int(b) - Int(c.b)) <= tolerance
    }

    init(rgb value: UInt32) {
        self.init(r: UInt8(value >> 16 & 0xFF), g: UInt8(value >> 8 & 0xFF), b: UInt8(value & 0xFF))
    }
}

/// Evening Lake: a guided project that paints the README's picture of a lake at sunset, layer by layer — sky, sun,
/// mountains, lake, reflection, forest, birds, clouds and a title — with most of the tools. Each step checks the image
/// with generous margins, since everything is drawn by hand.
enum EveningLake {
    static let size = IntSize(width: 1200, height: 800)

    /// The finished picture (Resources/EveningLake.png, made by scripts/make-project-image.sh) with its title in the
    /// interface language; nil when the app runs outside its bundle.
    static let goalImage: NSImage? = {
        guard let url = Bundle.main.url(forResource: "EveningLake", withExtension: "png"),
              let picture = NSImage(contentsOf: url) else { return nil }
        return NSImage(size: picture.size, flipped: false) { r in
            picture.draw(in: r)
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
            shadow.shadowBlurRadius = 6
            let title = NSAttributedString(string: L("Evening Lake"), attributes: [
                .font: NSFont.systemFont(ofSize: r.height * 0.09, weight: .bold), .foregroundColor: NSColor.white, .shadow: shadow,
            ])
            let size = title.size()
            title.draw(at: NSPoint(x: (r.width - size.width) / 2, y: r.height * 0.93 - size.height))
            return true
        }
    }()

    private static func menu(_ parts: String...) -> String { parts.joined(separator: " › ") }
    private static func label(_ s: String) -> String { s.trimmingCharacters(in: CharacterSet(charactersIn: ":：").union(.whitespaces)) }
    private static func tool(_ kind: ToolKind) -> (MainWindowController) -> NSView? {
        { c in
            if !c.toolsPanel.isVisible { c.toggleToolsWindow(nil) }
            return c.toolsPanel.button(for: kind)
        }
    }
    private static let layersWindow: (MainWindowController) -> NSView? = { c in
        if !c.layersPanel.isVisible { c.toggleLayersWindow(nil) }
        return c.layersPanel.contentView
    }
    private static func layerButton(_ action: Selector) -> (MainWindowController) -> NSView? {
        { c in
            if !c.layersPanel.isVisible { c.toggleLayersWindow(nil) }
            return c.layersPanel.button(for: action)
        }
    }

    /// A new layer, renamed.
    private static func newNamedLayer(_ title: String, _ name: String, role: String) -> ProjectStep {
        ProjectStep(title: title, text: LF("Add a new layer and name it %@.", name),
                    target: layerButton(#selector(MainWindowController.addLayer(_:))),
                    check: { $0.renamed($0.newLayer) }, onDone: { $0.remember($0.newLayer, as: role) })
    }

    private static let dark: (ColorBgra) -> Bool = { $0.isOpaque && $0.luminance < 0.3 }

    /// Whether the layer has a vertical gradient between rows `top` and `bottom`: opaque, and clearly different at
    /// the two rows in most columns (whatever the colors and the direction it was drawn in).
    private static func verticalGradient(_ layer: BitmapLayer?, top: Int, bottom: Int) -> Bool {
        guard let s = layer?.surface else { return false }
        let columns = [size.width / 4, size.width / 2, size.width * 3 / 4]
        return columns.filter { x in
            let a = s[x, top], b = s[x, bottom]
            return a.isOpaque && b.isOpaque && !a.near(b, 80)
        }.count >= 2
    }

    /// Dark pixels above the shore, where the pine trees go.
    private static func treeArea(_ ctx: ProjectContext) -> Int {
        ctx.count(ctx.layer("forest"), IntRect(x: 0, y: size.height / 4, width: size.width * 6 / 10, height: size.height / 2), dark)
    }

    static var steps: [ProjectStep] {
        let W = size.width, H = size.height
        let edit = L("Edit"), deselect = menu(edit, L("Deselect"))
        return [
            ProjectStep(title: L("Evening Lake"),
                        text: L("In this project you paint this evening lake, layer by layer, with most of the tools. A new 1200 × 800 image has been made for it. Each step says what to do and checks your image: once it is done, a check appears and Next goes on. You can skip any step."), showsGoal: true),

            // The sky.
            ProjectStep(title: L("Name the sky layer"),
                        text: LF("In the Layers window, double-click the Background layer and name it %@.", L("Sky")),
                        target: layersWindow, check: { $0.renamed($0.doc.layers.first) },
                        onDone: { $0.remember($0.doc.layers.first, as: "sky") }),
            ProjectStep(title: L("Choose the sky colors"),
                        text: L("Click Use These Colors: the primary color becomes a deep night blue and the secondary a warm orange. You can also click the color squares in the Colors window to pick your own."),
                        colors: (ColorBgra(rgb: 0x141C45), ColorBgra(rgb: 0xEE7E5C)),
                        target: { c in
                            if !c.colorsPanel.isVisible { c.toggleColorsWindow(nil) }
                            return c.colorsPanel.contentView
                        },
                        check: { _ in
                            // A dark blue and a warm color (not the default black and white).
                            let p = AppEnvironment.shared.primaryColor, s = AppEnvironment.shared.secondaryColor
                            return p.luminance < 0.35 && Int(p.b) > Int(p.r) + 10 && s.luminance > 0.4 && Int(s.r) > Int(s.b) + 30
                        }),
            ProjectStep(title: L("Paint the sky"),
                        text: LF("Choose the %@ tool and drag from the top of the image down to about two thirds of its height. Press Return to finish.", ToolKind.gradient.nameWithShortcut),
                        target: tool(.gradient),
                        check: { verticalGradient($0.layer("sky"), top: 6, bottom: H * 13 / 20) }),
            ProjectStep(title: L("Add stars"),
                        text: LF("Click Use These Colors to paint in white, choose the %@ tool with a brush width of 3, and click here and there in the top of the sky: about ten stars.", ToolKind.paintbrush.nameWithShortcut),
                        colors: (ColorBgra(rgb: 0xFFFFFF), ColorBgra(rgb: 0xEE7E5C)), target: tool(.paintbrush),
                        check: { ctx in
                            ctx.count(ctx.layer("sky"), IntRect(x: 0, y: 0, width: W, height: H * 9 / 20), step: 2) {
                                $0.isOpaque && min($0.r, $0.g, $0.b) > 200
                            } >= 6
                        }),

            ProjectStep(title: L("Keep a snapshot"),
                        text: L("Your sky is done: click the camera at the bottom of the History window to keep a snapshot of the image. Take one whenever you like before trying something: you can always come back to it."),
                        requires: .snapshots,
                        target: { c in
                            if !c.historyPanel.isVisible { c.toggleHistoryWindow(nil) }
                            return c.historyPanel.snapshotButton
                        },
                        check: { $0.doc.history.snapshots.count > $0.project.baselineSnapshots }),

            // The sun.
            ProjectStep(title: L("A layer for the sun"),
                        text: LF("Click %@ at the bottom of the Layers window, then double-click the new layer and name it %@.", L("Add New Layer"), L("Sun")),
                        target: layerButton(#selector(MainWindowController.addLayer(_:))),
                        check: { $0.renamed($0.newLayer) }, onDone: { $0.remember($0.newLayer, as: "sun") }),
            ProjectStep(title: L("Select a round sun"),
                        text: LF("Choose the %@ tool and drag a circle about 120 pixels wide above the horizon, on the right; hold Shift to keep it round.", ToolKind.ellipseSelect.nameWithShortcut),
                        target: tool(.ellipseSelect),
                        check: { ctx in
                            guard let b = ctx.doc.selection?.intBounds, b.height > 0 else { return false }
                            let ratio = Double(b.width) / Double(b.height)
                            return b.width >= 40 && b.width <= 500 && ratio > 0.75 && ratio < 1.33
                        },
                        onDone: { ctx in ctx.project.areas["sun"] = ctx.doc.selection?.intBounds }),
            ProjectStep(title: L("Fill the sun"),
                        text: LF("Click Use These Colors for a golden yellow, then choose %@.", menu(edit, L("Fill Selection"))),
                        colors: (ColorBgra(rgb: 0xFFE2A8), ColorBgra(rgb: 0xFFB27A)),
                        check: { ctx in
                            guard let sun = ctx.layer("sun")?.surface, let b = ctx.project.areas["sun"] else { return false }
                            let p = sun[b.left + b.width / 2, b.top + b.height / 2]
                            return p.isOpaque && p.r > 200 && p.g > 140
                        }),
            ProjectStep(title: L("Make it glow"),
                        text: LF("Choose %@, then %@ with a radius of about 30: the blur spreads the sun into a glow.", deselect,
                                 menu(L("Effects"), L("Blurs"), L("Gaussian Blur"))),
                        check: { ctx in
                            guard ctx.doc.selection == nil, let b = ctx.project.areas["sun"],
                                  ctx.newHistoryNames.contains(L("Gaussian Blur")) else { return false }
                            let around = IntRect(x: b.left - 40, y: b.top - 40, width: b.width + 80, height: b.height + 80)
                            return ctx.count(ctx.layer("sun"), around, step: 2) { $0.a > 15 && $0.a < 225 } >= 60
                        }),
            ProjectStep(title: L("Blend it into the sky"),
                        text: LF("Double-click the %@ layer and set its %@ to %@: the glow now lightens the sky instead of covering it.", L("Sun"), label(L("Mode:")), L("Screen")),
                        target: layersWindow, check: { $0.layer("sun")?.blendMode == .screen }),

            // The mountains.
            newNamedLayer(L("A layer for the mountains"), L("Mountains"), role: "mountains"),
            ProjectStep(title: L("Draw the mountains"),
                        text: LF("Choose the %@ tool. Start at the left edge, at about two thirds of the height, draw the peaks across to the right edge, then come back along the foot of the mountains to where you started.", ToolKind.lassoSelect.nameWithShortcut),
                        target: tool(.lassoSelect),
                        check: { ctx in
                            guard let b = ctx.doc.selection?.intBounds else { return false }
                            return b.width >= W * 6 / 10 && b.top < H * 5 / 8 && b.bottom > H * 13 / 20
                        }),
            ProjectStep(title: L("Fill the mountains"),
                        text: LF("Click Use These Colors for a dusky purple, choose %@, then %@.", menu(edit, L("Fill Selection")), deselect),
                        colors: (ColorBgra(rgb: 0x4A3A72), ColorBgra(rgb: 0x6A4A7E)),
                        check: { ctx in
                            ctx.doc.selection == nil
                                && ctx.count(ctx.layer("mountains"), IntRect(x: 0, y: H / 4, width: W, height: H / 2)) {
                                    $0.isOpaque && $0.luminance < 0.5
                                } >= 400
                        }),

            // The lake.
            newNamedLayer(L("A layer for the lake"), L("Lake"), role: "lake"),
            ProjectStep(title: L("Select the water"),
                        text: LF("Choose the %@ tool and select from the foot of the mountains down to the bottom of the image, across its whole width.", ToolKind.rectangleSelect.nameWithShortcut),
                        target: tool(.rectangleSelect),
                        check: { ctx in
                            guard let b = ctx.doc.selection?.intBounds else { return false }
                            return b.top >= H * 9 / 16 && b.top <= H * 17 / 20 && b.bottom >= H - 10 && b.width >= W * 9 / 10
                        },
                        onDone: { ctx in ctx.project.areas["lake"] = ctx.doc.selection?.intBounds }),
            ProjectStep(title: L("Paint the water"),
                        text: LF("Click Use These Colors, then with the %@ tool drag from the top of the selection down to the bottom of the image, and press Return.", ToolKind.gradient.nameWithShortcut),
                        colors: (ColorBgra(rgb: 0xE58A78), ColorBgra(rgb: 0x1F2350)), target: tool(.gradient),
                        check: { ctx in
                            verticalGradient(ctx.layer("lake"), top: (ctx.project.areas["lake"]?.top ?? H * 7 / 10) + 6, bottom: H - 6)
                        }),

            // The reflection.
            ProjectStep(title: L("Copy the mountains"),
                        text: LF("Choose %@, click the %@ layer in the Layers window, then click %@.", deselect, L("Mountains"), L("Duplicate Layer")),
                        target: layerButton(#selector(MainWindowController.duplicateLayer(_:))),
                        check: { ctx in ctx.matchRatio(ctx.newLayer, ctx.layer("mountains")) { ($0, $1) } > 0.9 },
                        onDone: { $0.remember($0.newLayer, as: "reflection") }),
            ProjectStep(title: L("Turn the copy upside down"),
                        text: LF("Choose %@: the copy becomes the reflection of the mountains.", menu(L("Layers"), L("Flip Vertical"))),
                        check: { ctx in ctx.matchRatio(ctx.layer("reflection"), ctx.layer("mountains")) { ($0, H - 1 - $1) } > 0.85 }),
            ProjectStep(title: L("Move it into the water"),
                        text: LF("Choose %@, then with the %@ tool drag the upside-down mountains down until they meet the real ones at the water line. Press Return, then choose %@.", menu(edit, L("Select All")), ToolKind.moveSelectedPixels.nameWithShortcut, deselect),
                        target: tool(.moveSelectedPixels),
                        check: { ctx in
                            let top = (ctx.project.areas["lake"]?.top ?? H * 7 / 10) + 20
                            return ctx.doc.selection == nil
                                && ctx.count(ctx.layer("reflection"), IntRect(x: 0, y: top, width: W, height: H - top)) { $0.isOpaque } >= 300
                        }),
            ProjectStep(title: L("Put the reflection in the water"),
                        text: LF("Click %@ so the copy goes above the %@ layer: the reflection now shows on the water.", L("Move Layer Up"), L("Lake")),
                        target: layerButton(#selector(MainWindowController.moveLayerUp(_:))),
                        check: { ctx in
                            guard let r = ctx.layer("reflection"), let lake = ctx.layer("lake"),
                                  let ri = ctx.doc.layers.firstIndex(where: { $0 === r }),
                                  let li = ctx.doc.layers.firstIndex(where: { $0 === lake }) else { return false }
                            return ri > li
                        }),
            ProjectStep(title: L("Make the reflection fainter"),
                        text: LF("Double-click the copy in the Layers window and lower its %@ to about 100.", label(L("Opacity:"))),
                        target: layersWindow, check: { ($0.layer("reflection")?.opacity ?? 255) <= 200 }),

            // The forest.
            newNamedLayer(L("A layer for the forest"), L("Forest"), role: "forest"),
            ProjectStep(title: L("Draw the shore"),
                        text: LF("Click Use These Colors for a very dark blue. With the %@ tool, draw the line of a low hill in the bottom-left corner, from the left edge down to the bottom edge.", ToolKind.paintbrush.nameWithShortcut),
                        colors: (ColorBgra(rgb: 0x16142C), ColorBgra(rgb: 0x110F24)),
                        plusTip: (.smoothing, L("Turn on Smoothing in the tool bar for a steadier line.")),
                        target: tool(.paintbrush),
                        check: { ctx in
                            ctx.count(ctx.layer("forest"), IntRect(x: 0, y: H * 13 / 20, width: W / 2, height: H * 7 / 20), step: 2,
                                      dark) >= 40
                        }),
            ProjectStep(title: L("Fill the shore"),
                        text: LF("Choose the %@ tool, click under the line, and press Return.", ToolKind.paintBucket.nameWithShortcut),
                        target: tool(.paintBucket),
                        check: { ctx in
                            ctx.count(ctx.layer("forest"), IntRect(x: 0, y: H * 7 / 10, width: W / 2, height: H * 3 / 10), dark) >= 800
                        }),
            ProjectStep(title: L("Plant pine trees"),
                        text: LF("Choose the %@ tool, pick %@ and %@ in the tool bar, then draw a few tall, narrow triangles standing on the shore. Press Return after each.", ToolKind.shapes.nameWithShortcut, L("Triangle"), L("Draw Filled Shape")),
                        target: tool(.shapes),
                        onBegin: { ctx in ctx.project.numbers["shore"] = treeArea(ctx) },
                        check: { ctx in treeArea(ctx) >= (ctx.project.numbers["shore"] ?? 0) + 150 }),

            // Birds, clouds and the title.
            ProjectStep(title: L("Add birds"),
                        text: LF("Add a new layer named %@, click Use These Colors, and with the %@ tool draw two or three small V shapes in the sky.", L("Birds"), ToolKind.paintbrush.nameWithShortcut),
                        colors: (ColorBgra(rgb: 0x231C3A), ColorBgra(rgb: 0xEE7E5C)),
                        plusTip: (.brushWidthSteps, L("The double chevrons next to the brush width jump straight to 5.")),
                        target: layerButton(#selector(MainWindowController.addLayer(_:))),
                        check: { ctx in
                            ctx.renamed(ctx.newLayer)
                                && ctx.count(ctx.newLayer, IntRect(x: 0, y: 0, width: W, height: H * 9 / 16), step: 2) {
                                    $0.isOpaque && $0.luminance < 0.35
                                } >= 15
                        }),
            ProjectStep(title: L("Clouds in the sky"),
                        text: LF("Click the %@ layer, choose %@, set %@ to %@ and click OK.", L("Sky"), menu(L("Effects"), L("Render"), L("Clouds")), L("Blend mode"), L("Soft Light")),
                        check: { $0.newHistoryNames.contains(L("Clouds")) }),
            ProjectStep(title: L("Add a title"),
                        text: LF("Add a new layer named %@ and click Use These Colors for white. Choose the %@ tool, set the size to 64, click near the top and type %@. Click Finish in the tool bar or press ⌘Return (Return alone starts a new line).", L("Title"), ToolKind.text.nameWithShortcut, L("Evening Lake")),
                        colors: (ColorBgra(rgb: 0xFFFFFF), ColorBgra(rgb: 0x141C45)), target: tool(.text),
                        check: { ctx in
                            ctx.renamed(ctx.newLayer) && ctx.currentHistoryName == ToolKind.text.name
                                && ctx.count(ctx.newLayer, IntRect(x: 0, y: 0, width: W, height: H / 2), step: 2) {
                                    $0.isOpaque && min($0.r, $0.g, $0.b) > 200
                                } >= 30
                        }),
            ProjectStep(title: L("Save your work"),
                        text: LF("Choose %@ and pick %@ or %@: these formats keep the layers.", menu(L("File"), L("Save As…")), FileType.openRaster.name, FileType.paintDotNet.name),
                        check: { ["ora", "pdn"].contains($0.workspace.fileURL?.pathExtension.lowercased() ?? "") }),
            ProjectStep(title: L("Your evening lake is ready"),
                        text: L("You used layers and their properties, selections, gradients, effects, blend modes and the History window. Try other blend modes or opacities on the layers to change the mood."), showsGoal: true),
        ]
    }
}
