import AppKit
import BrushwoodCore

/// Where a tutorial step's explanation shows, next to the part it points at.
enum TutorialSide {
    case below, above, right, left

    /// The popover edge, which depends on whether the view's coordinates are flipped.
    func edge(in view: NSView) -> NSRectEdge {
        switch self {
        case .below: return view.isFlipped ? .maxY : .minY
        case .above: return view.isFlipped ? .minY : .maxY
        case .right: return .maxX
        case .left: return .minX
        }
    }
}

/// One stop of a tutorial: a part of the window, pointed at, with an explanation.
struct TutorialStep {
    let title: String
    let text: String
    /// Brings the part on screen (selects a tool, shows a window…).
    var prepare: (MainWindowController) -> Void = { _ in }
    /// The part: a view and a rectangle in its coordinates; nil when it is not there.
    let target: (MainWindowController) -> (view: NSView, rect: NSRect)?
    var side: TutorialSide = .below
    /// The Brushwood Plus feature the step shows: skipped while it is off.
    var requires: PlusFeature?

    var isAvailable: Bool { requires?.isEnabled ?? true }

    /// A tool: selects it and points at its button in the Tools window, with its help text.
    static func tool(_ kind: ToolKind) -> TutorialStep {
        TutorialStep(title: kind.nameWithShortcut, text: kind.helpText, prepare: { c in
            if !c.toolsPanel.isVisible { c.toggleToolsWindow(nil) }
            c.selectTool(kind)
        }, target: { c in c.toolsPanel.button(for: kind).map { ($0, $0.bounds) } }, side: .right)
    }

    /// A setting of a tool: selects the tool and points at the setting in the tool bar.
    static func option(_ option: ToolOption, of kind: ToolKind, title: String, text: String,
                       requires: PlusFeature? = nil) -> TutorialStep {
        TutorialStep(title: title, text: text, prepare: { c in c.selectTool(kind) },
                     target: { c in c.optionsBar.area(of: option) }, requires: requires)
    }

    /// A window or a bar, shown if it was hidden.
    static func part(_ title: String, _ text: String, side: TutorialSide, show: ((MainWindowController) -> Void)? = nil,
                     requires: PlusFeature? = nil, view: @escaping (MainWindowController) -> NSView?) -> TutorialStep {
        TutorialStep(title: title, text: text, prepare: { c in show?(c) },
                     target: { c in view(c).map { ($0, $0.bounds) } }, side: side, requires: requires)
    }
}

/// A guided tour of one part of the app.
struct TutorialScenario {
    let id: String
    let title: String
    let summary: String
    let steps: [TutorialStep]

    /// The steps whose Plus features are on.
    var availableSteps: [TutorialStep] { steps.filter(\.isAvailable) }

    private static let completedKey = "tutorialCompleted"

    var isCompleted: Bool { (UserDefaults.standard.stringArray(forKey: Self.completedKey) ?? []).contains(id) }

    func markCompleted() {
        let done = UserDefaults.standard.stringArray(forKey: Self.completedKey) ?? []
        if !done.contains(id) { UserDefaults.standard.set(done + [id], forKey: Self.completedKey) }
    }
}

struct TutorialSection {
    let title: String
    let scenarios: [TutorialScenario]
}

/// Brushwood Plus's tutorial: short guided tours of the window, the tools and their settings. Brushwood Plus features
/// are steps of the tour of the part they belong to (marked Plus in the popover); the last section has the rest.
/// Help › Tutorial… and Brushwood Plus › Tutorial… open it; it is offered at the first launch.
enum Tutorial {
    /// "Brush width:" → "Brush width", for titles taken from tool bar labels.
    private static func label(_ s: String) -> String {
        s.trimmingCharacters(in: CharacterSet(charactersIn: ":：").union(.whitespaces))
    }

    private static let showHistory: (MainWindowController) -> Void = { c in
        if !c.historyPanel.isVisible { c.toggleHistoryWindow(nil) }
    }

    // Texts shared by several tours.
    private static var floodModeText: String {
        L("Contiguous only reaches the similar pixels that touch the one you click; Global reaches them everywhere in the image.")
    }
    private static var toleranceText: String {
        L("How different a color can be and still count as similar. At 0%, only the exact same color counts.")
    }
    private static var finishText: String {
        L("What you draw with this tool keeps its handles, so you can still change it, until you click Finish or press Return.")
    }

    static var sections: [TutorialSection] {
        [
            TutorialSection(title: L("Getting Started"), scenarios: [
                TutorialScenario(id: "window", title: L("The Brushwood Window"),
                                 summary: L("The toolbar, the tool options and the status bar."), steps: [
                    .part(L("Toolbar"), L("Everyday commands: new, open, save, cut, copy, paste, undo and redo. The thumbnails are your open images, and the buttons on the right show or hide the floating windows."),
                          side: .below, view: { $0.mainToolbar }),
                    .part(L("Tool options"), L("The bar under the toolbar shows the settings of the current tool. They change with the tool and are kept for next time."),
                          side: .below, view: { $0.optionsBar }),
                    .part(L("Status bar"), L("Hints for the current tool, the size of the selection, the pointer position, the units and the zoom."),
                          side: .above, view: { $0.statusBar }),
                ]),
                TutorialScenario(id: "floating", title: L("Floating Windows"),
                                 summary: L("Tools, History, Layers and Colors."), steps: [
                    .part(L("Tools"), L("Pick a tool here, or press its letter on the keyboard (the tooltip shows it). Pressing the letter again switches between the tools that share it."),
                          side: .right, show: { if !$0.toolsPanel.isVisible { $0.toggleToolsWindow(nil) } },
                          view: { $0.toolsPanel.contentView }),
                    .part(L("History"), L("Every change is a step. Click a step to go back to it, and click it again to compare before and after. Undo and Redo are at the bottom."),
                          side: .left, show: showHistory, view: { $0.historyPanel.contentView }),
                    .part(L("Times in the History window"), L("Each step shows when it was made. Right-click in the History window to show how long ago instead, or to hide the times."),
                          side: .left, show: showHistory, requires: .historyTimes, view: { $0.historyPanel.contentView }),
                    .part(L("Snapshots"), L("This button keeps a full copy of the image, listed at the top of the History window. Click the snapshot to bring the image back to it at any time, even after undoing or new edits."),
                          side: .left, show: showHistory, requires: .snapshots, view: { $0.historyPanel.snapshotButton }),
                    .part(L("Layers"), L("The image is a stack of layers. Add, delete, duplicate and move them with the buttons at the bottom; double-click a layer for its properties."),
                          side: .left, show: { if !$0.layersPanel.isVisible { $0.toggleLayersWindow(nil) } },
                          view: { $0.layersPanel.contentView }),
                    .part(L("Colors"), L("The left mouse button paints with the primary color, the right one with the secondary color. Click a color of the palette to pick it, or right-click it for the secondary color."),
                          side: .right, show: { if !$0.colorsPanel.isVisible { $0.toggleColorsWindow(nil) } },
                          view: { $0.colorsPanel.contentView }),
                ]),
            ]),
            TutorialSection(title: L("Selection"), scenarios: [
                TutorialScenario(id: "select", title: L("Selection Tools"),
                                 summary: L("Rectangle, lasso, ellipse and magic wand, and how selections combine."), steps: [
                    .tool(.rectangleSelect),
                    .option(.selectionMode, of: .rectangleSelect, title: label(L("Selection mode:")),
                            text: L("How a new selection combines with the current one: replace it, add to it, subtract from it, keep only where they overlap, or invert where they overlap.")),
                    .option(.selectionDrawMode, of: .rectangleSelect, title: L("Selection drawing mode"),
                            text: L("Normal, or a fixed ratio or a fixed size, for a selection with exact proportions or dimensions.")),
                    .tool(.lassoSelect),
                    .tool(.ellipseSelect),
                    .tool(.magicWand),
                    .option(.floodMode, of: .magicWand, title: label(L("Flood mode:")), text: floodModeText),
                    .option(.tolerance, of: .magicWand, title: label(L("Tolerance:")), text: toleranceText),
                    .option(.sampling, of: .magicWand, title: label(L("Sampling:")),
                            text: L("Look at the colors of the current layer only, or of the whole image.")),
                    .option(.finish, of: .magicWand, title: L("Finish"), text: finishText),
                ]),
                TutorialScenario(id: "move", title: L("Moving Pixels and Selections"),
                                 summary: L("Move, scale and rotate a selection or what it contains."), steps: [
                    .tool(.moveSelectedPixels),
                    .option(.resampling, of: .moveSelectedPixels, title: label(L("Quality:")),
                            text: L("Bilinear gives smooth results when scaling or rotating; Nearest Neighbor keeps hard pixel edges.")),
                    .tool(.moveSelection),
                ]),
            ]),
            TutorialSection(title: L("Painting"), scenarios: [
                TutorialScenario(id: "paintbrush", title: L("Paintbrush"), summary: L("The paintbrush and all its settings."), steps: [
                    .tool(.paintbrush),
                    .option(.brushWidth, of: .paintbrush, title: label(L("Brush width:")),
                            text: L("The size of the brush, in pixels. The mouse wheel over the field and the [ and ] keys change it too.")),
                    .option(.widthSnap, of: .paintbrush, title: L("Brush width by fives"),
                            text: L("These buttons go up or down to the next multiple of 5: 1, 5, 10, 15…"), requires: .brushWidthSteps),
                    .option(.hardness, of: .paintbrush, title: label(L("Hardness:")),
                            text: L("At 100%, the brush has a hard edge; lower values make its edge softer.")),
                    .option(.antialiasing, of: .paintbrush, title: L("Antialiasing"),
                            text: L("On, edges are smooth. Off, they are hard and pixelated.")),
                    .option(.smoothing, of: .paintbrush, title: L("Smoothing"),
                            text: L("The brush follows the pointer on a string, which takes out hand tremor. While it is on, the length of the string can be set next to it."),
                            requires: .smoothing),
                    .option(.magneticClosing, of: .paintbrush, title: L("Magnetic Closing"),
                            text: L("A stroke released near where it started is joined to its start, so circles and outlines close cleanly."),
                            requires: .magneticClosing),
                    .option(.blendMode, of: .paintbrush, title: label(L("Blending:")),
                            text: L("How the paint mixes with the pixels below it. Overwrite replaces them, transparency included.")),
                    .option(.clipping, of: .paintbrush, title: label(L("Clipping:")),
                            text: L("When part of the image is selected, painting stays inside the selection. Antialiased softens its edge.")),
                ]),
                TutorialScenario(id: "eraserPencil", title: L("Eraser and Pencil"),
                                 summary: L("Erase, or draw lines one pixel wide."), steps: [
                    .tool(.eraser),
                    .tool(.pencil),
                ]),
                TutorialScenario(id: "retouch", title: L("Clone Stamp and Recolor"),
                                 summary: L("Copy part of the image elsewhere, or replace one color with another."), steps: [
                    .tool(.cloneStamp),
                    .tool(.recolor),
                    .option(.tolerance, of: .recolor, title: label(L("Tolerance:")), text: toleranceText),
                ]),
            ]),
            TutorialSection(title: L("Fill and Color"), scenarios: [
                TutorialScenario(id: "fill", title: L("Paint Bucket and Gradient"),
                                 summary: L("Fill an area with a color, a pattern or a gradient."), steps: [
                    .tool(.paintBucket),
                    .option(.floodMode, of: .paintBucket, title: label(L("Flood mode:")), text: floodModeText),
                    .option(.fillStyle, of: .paintBucket, title: label(L("Fill:")),
                            text: L("Fill with the plain color, or with a pattern of the primary and secondary colors.")),
                    .option(.tolerance, of: .paintBucket, title: label(L("Tolerance:")), text: toleranceText),
                    .tool(.gradient),
                    .option(.gradientType, of: .gradient, title: label(L("Gradient:")),
                            text: L("The shape of the gradient: linear, reflected, diamond, radial, conical or spiral.")),
                    .option(.gradientColorMode, of: .gradient, title: L("Color or transparency"),
                            text: L("Color mode goes from the primary to the secondary color. Transparency mode fades the layer out instead.")),
                    .option(.gradientRepeat, of: .gradient, title: L("Repeat"),
                            text: L("What happens past the ends of the gradient: nothing, or it repeats as a sawtooth or a triangle.")),
                ]),
                TutorialScenario(id: "pick", title: L("Color Picker"), summary: L("Take a color from the image."), steps: [
                    .tool(.colorPicker),
                    .option(.colorSampling, of: .colorPicker, title: label(L("Sampling:")),
                            text: L("Take a single pixel or the average of a square around it, from the current layer or the whole image.")),
                    .option(.afterClick, of: .colorPicker, title: label(L("After click:")),
                            text: L("Stay on the Color Picker after picking, go back to the previous tool, or switch to the Pencil.")),
                ]),
            ]),
            TutorialSection(title: L("Text and Shapes"), scenarios: [
                TutorialScenario(id: "text", title: L("Text"), summary: L("Type text, and choose its font."), steps: [
                    .tool(.text),
                    .option(.font, of: .text, title: label(L("Font:")),
                            text: L("The font, its size and its style: bold, italic, underline and strikethrough.")),
                    .option(.alignment, of: .text, title: L("Alignment"),
                            text: L("Lines of text line up on the left, in the center or on the right.")),
                    .option(.finish, of: .text, title: L("Finish"), text: finishText),
                ]),
                TutorialScenario(id: "shapes", title: L("Lines and Shapes"),
                                 summary: L("Draw lines and curves, and choose among 31 shapes."), steps: [
                    .tool(.lineCurve),
                    .option(.dashStyle, of: .lineCurve, title: label(L("Dash:")),
                            text: L("A solid line, or one of the dash patterns.")),
                    .option(.caps, of: .lineCurve, title: L("Line ends"),
                            text: L("How the line starts and ends: flat, rounded, or with an arrow.")),
                    .tool(.shapes),
                    .option(.shape, of: .shapes, title: label(L("Shape:")),
                            text: L("Rectangles, ellipses, polygons, stars, arrows, callouts and symbols.")),
                    .option(.shapeDrawType, of: .shapes, title: L("Outline or fill"),
                            text: L("Draw the outline, the inside, or both. The primary color draws; with both, the inside takes the secondary color.")),
                    .option(.finish, of: .shapes, title: L("Finish"), text: finishText),
                ]),
            ]),
            TutorialSection(title: L("View"), scenarios: [
                TutorialScenario(id: "view", title: L("Zoom and Pan"), summary: L("Look closer, and move around the image."), steps: [
                    .tool(.zoom),
                    .tool(.pan),
                ]),
            ]),
            TutorialSection(title: L("Brushwood Plus"), scenarios: [
                TutorialScenario(id: "plusFeatures", title: L("Plus Features"),
                                 summary: L("Turn each Brushwood Plus feature on or off."), steps: [
                    .part(L("Plus Features"), L("Each Brushwood Plus feature can be turned on or off here, one by one or by category. This window is also in Brushwood Plus › Plus Features…"),
                          side: .right, show: { _ in (NSApp.delegate as? AppDelegate)?.showPlusFeatures(nil) },
                          view: { _ in NSApp.windows.first { $0 is PlusFeaturesWindow && $0.isVisible }?.contentView }),
                ]),
            ]),
        ]
    }
}
