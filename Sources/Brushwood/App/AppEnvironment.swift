import AppKit
import BrushwoodCore

/// The tools in the Tools window, in Paint.NET's order.
enum ToolKind: Int, CaseIterable {
    case moveSelectedPixels
    case moveSelection
    case rectangleSelect
    case lassoSelect
    case ellipseSelect
    case magicWand
    case zoom
    case pan
    case paintBucket
    case gradient
    case paintbrush
    case eraser
    case pencil
    case colorPicker
    case cloneStamp
    case recolor
    case text
    case lineCurve
    case shapes

    var name: String {
        switch self {
        case .moveSelectedPixels: return L("Move Selected Pixels")
        case .moveSelection: return L("Move Selection")
        case .rectangleSelect: return L("Rectangle Select")
        case .lassoSelect: return L("Lasso Select")
        case .ellipseSelect: return L("Ellipse Select")
        case .magicWand: return L("Magic Wand")
        case .zoom: return L("Zoom")
        case .pan: return L("Pan")
        case .paintBucket: return L("Paint Bucket")
        case .gradient: return L("Gradient")
        case .paintbrush: return L("Paintbrush")
        case .eraser: return L("Eraser")
        case .pencil: return L("Pencil")
        case .colorPicker: return L("Color Picker")
        case .cloneStamp: return L("Clone Stamp")
        case .recolor: return L("Recolor")
        case .text: return L("Text")
        case .lineCurve: return L("Line / Curve")
        case .shapes: return L("Shapes")
        }
    }

    var icon: String { "tool.\(self)" }

    /// Keyboard letter; pressing it repeatedly cycles tools sharing it (Paint.NET behaviour).
    var shortcutKey: Character {
        switch self {
        case .moveSelectedPixels, .moveSelection: return "m"
        case .rectangleSelect, .lassoSelect, .ellipseSelect, .magicWand: return "s"
        case .zoom: return "z"
        case .pan: return "h"
        case .paintBucket: return "f"
        case .gradient: return "g"
        case .paintbrush: return "b"
        case .eraser: return "e"
        case .pencil: return "p"
        case .colorPicker: return "k"
        case .cloneStamp: return "l"
        case .recolor: return "r"
        case .text: return "t"
        case .lineCurve, .shapes: return "o"
        }
    }

    var helpText: String {
        switch self {
        case .moveSelectedPixels:
            return L("Drag the selection to move it. Drag the handles to scale. Drag with the right mouse button to rotate. Hold ⌘ while dragging to leave a copy behind.")
        case .moveSelection:
            return L("Drag the selection outline to move it. Drag the handles to scale. Drag with the right mouse button to rotate.")
        case .rectangleSelect:
            return L("Click and drag to draw a rectangular selection. Hold Shift to constrain to a square. ⌘ adds, ⌥ subtracts, right-click inverts.")
        case .lassoSelect:
            return L("Click and drag to draw the outline of a selection area. ⌘ adds, ⌥ subtracts, right-click inverts.")
        case .ellipseSelect:
            return L("Click and drag to draw an elliptical selection. Hold Shift to constrain to a circle. ⌘ adds, ⌥ subtracts, right-click inverts.")
        case .magicWand:
            return L("Click to select a region of similar color. ⌘ adds, ⌥ subtracts, right-click inverts. Shift-click for global selection.")
        case .zoom:
            return L("Left click to zoom in. Right click to zoom out. Click and drag to zoom in on a rectangle.")
        case .pan:
            return L("Click and drag to navigate the image.")
        case .paintBucket:
            return L("Left click to fill a region with the primary color, right click to fill with the secondary color.")
        case .gradient:
            return L("Click and drag to draw a gradient from the primary to the secondary color. Right mouse button reverses the colors.")
        case .paintbrush:
            return L("Left click to draw with the primary color, right click to draw with the secondary color.")
        case .eraser:
            return L("Click and drag to erase a portion of the image.")
        case .pencil:
            return L("Left click to draw freehand one-pixel wide lines with the primary color, right click to use the secondary color.")
        case .colorPicker:
            return L("Left click to set the primary color. Right click to set the secondary color.")
        case .cloneStamp:
            return L("⌘-click to set the origin, then click and drag to paint with the cloned pixels.")
        case .recolor:
            return L("Left click to replace the secondary color with the primary color.")
        case .text:
            return L("Left click to place the cursor, then type the desired text. The text color is the primary color.")
        case .lineCurve:
            return L("Click and drag to draw a line. Then drag the handles to bend it into a curve. Press Enter to finish.")
        case .shapes:
            return L("Click and drag to draw a shape. Drag the handles to adjust it. Press Enter to finish.")
        }
    }
}

enum ShapeDrawType: Int, CaseIterable {
    case outline, filled, filledWithOutline

    var name: String {
        switch self {
        case .outline: return L("Draw Shape Outline")
        case .filled: return L("Draw Filled Shape")
        case .filledWithOutline: return L("Draw Filled Shape With Outline")
        }
    }
}

enum GradientType: Int, CaseIterable {
    case linear, linearReflected, linearDiamond, radial, conical, spiralClockwise, spiralCounterclockwise

    var name: String {
        switch self {
        case .linear: return L("Linear")
        case .linearReflected: return L("Linear (Reflected)")
        case .linearDiamond: return L("Linear (Diamond)")
        case .radial: return L("Radial")
        case .conical: return L("Conical")
        case .spiralClockwise: return L("Spiral (Clockwise)")
        case .spiralCounterclockwise: return L("Spiral (Counter-clockwise)")
        }
    }
}

enum GradientRepeat: Int, CaseIterable {
    case none, sawtooth, triangle

    var name: String {
        switch self {
        case .none: return L("No Repeat")
        case .sawtooth: return L("Sawtooth Repeat")
        case .triangle: return L("Triangle Repeat")
        }
    }
}

enum SamplingSource: Int, CaseIterable {
    case layer, image

    var name: String { self == .layer ? L("Layer") : L("Image") }
}

enum ColorPickerSampleSize: Int, CaseIterable {
    case single = 1, r3 = 3, r5 = 5, r7 = 7, r9 = 9, r11 = 11, r13 = 13, r15 = 15, r17 = 17, r19 = 19, r21 = 21, r31 = 31, r51 = 51

    var name: String { self == .single ? L("Single Pixel") : LF("%d x %d Region", rawValue, rawValue) }
}

enum ColorPickerAfterClick: Int, CaseIterable {
    case doNotSwitch, switchToPrevious, switchToPencil

    var name: String {
        switch self {
        case .doNotSwitch: return L("Do not switch tool")
        case .switchToPrevious: return L("Switch to previous tool")
        case .switchToPencil: return L("Switch to Pencil tool")
        }
    }
}

enum SelectionDrawMode: Int, CaseIterable {
    case normal, fixedRatio, fixedSize

    var name: String {
        switch self {
        case .normal: return L("Normal")
        case .fixedRatio: return L("Fixed Ratio")
        case .fixedSize: return L("Fixed Size")
        }
    }
}

enum TextAlignmentOption: Int, CaseIterable {
    case left, center, right

    var name: String {
        switch self {
        case .left: return L("Left")
        case .center: return L("Center")
        case .right: return L("Right")
        }
    }
}

enum LineDashStyle: Int, CaseIterable {
    case solid, dash, dot, dashDot, dashDotDot

    var name: String {
        switch self {
        case .solid: return L("Solid")
        case .dash: return L("Dash")
        case .dot: return L("Dot")
        case .dashDot: return L("Dash Dot")
        case .dashDotDot: return L("Dash Dot Dot")
        }
    }

    func pattern(width: CGFloat) -> [CGFloat] {
        let w = max(1, width)
        switch self {
        case .solid: return []
        case .dash: return [3 * w, w]
        case .dot: return [w, w]
        case .dashDot: return [3 * w, w, w, w]
        case .dashDotDot: return [3 * w, w, w, w, w, w]
        }
    }
}

enum LineCap: Int, CaseIterable {
    case flat, arrow, filledArrow, rounded

    var name: String {
        switch self {
        case .flat: return L("Flat")
        case .arrow: return L("Arrow")
        case .filledArrow: return L("Filled Arrow")
        case .rounded: return L("Rounded")
        }
    }
}

enum MeasurementUnit: Int, CaseIterable {
    case pixels, inches, centimeters

    var name: String {
        switch self {
        case .pixels: return L("Pixels")
        case .inches: return L("Inches")
        case .centimeters: return L("Centimeters")
        }
    }

    var abbreviation: String {
        switch self {
        case .pixels: return L("px")
        case .inches: return L("in")
        case .centimeters: return L("cm")
        }
    }

    func fromPixels(_ px: Double, dpi: Double) -> Double {
        switch self {
        case .pixels: return px
        case .inches: return px / dpi
        case .centimeters: return px / dpi * 2.54
        }
    }

    func toPixels(_ v: Double, dpi: Double) -> Double {
        switch self {
        case .pixels: return v
        case .inches: return v * dpi
        case .centimeters: return v / 2.54 * dpi
        }
    }
}

extension Notification.Name {
    static let colorsChanged = Notification.Name("BrushwoodColorsChanged")
    static let toolChanged = Notification.Name("BrushwoodToolChanged")
    static let toolSettingsChanged = Notification.Name("BrushwoodToolSettingsChanged")
    static let paletteChanged = Notification.Name("BrushwoodPaletteChanged")
    static let viewSettingsChanged = Notification.Name("BrushwoodViewSettingsChanged")
}

/// Shared tool options; every option bar control edits these (Paint.NET's `AppEnvironment`).
final class ToolSettings {
    var brushWidth: CGFloat = 2 { didSet { changed() } }
    var hardness: Double = 75 { didSet { changed() } }
    var antialiasing = true { didSet { changed() } }
    var blendMode: BlendMode = .normal { didSet { changed() } }
    /// Paint.NET's "Overwrite" mode: replace pixels (including alpha) instead of blending.
    var overwrite = false { didSet { changed() } }
    var fillStyle: FillStyle = .solid { didSet { changed() } }
    var shapeDrawType: ShapeDrawType = .outline { didSet { changed() } }
    var shapeType: ShapeKind = .rectangle { didSet { changed() } }
    var tolerance: Double = 0.5 { didSet { changed() } }
    var floodMode: FloodMode = .contiguous { didSet { changed() } }
    var floodSampling: SamplingSource = .layer { didSet { changed() } }
    var selectionMode: SelectionCombineMode = .replace { didSet { changed() } }
    var selectionDrawMode: SelectionDrawMode = .normal { didSet { changed() } }
    var selectionFixedWidth: Double = 100 { didSet { changed() } }
    var selectionFixedHeight: Double = 100 { didSet { changed() } }
    var gradientType: GradientType = .linear { didSet { changed() } }
    var gradientTransparencyMode = false { didSet { changed() } }
    var gradientRepeat: GradientRepeat = .none { didSet { changed() } }
    var colorPickerSampleSize: ColorPickerSampleSize = .single { didSet { changed() } }
    var colorPickerSampling: SamplingSource = .layer { didSet { changed() } }
    var colorPickerAfterClick: ColorPickerAfterClick = .doNotSwitch { didSet { changed() } }
    var fontName = "Helvetica" { didSet { changed() } }
    var fontSize: CGFloat = 12 { didSet { changed() } }
    var bold = false { didSet { changed() } }
    var italic = false { didSet { changed() } }
    var underline = false { didSet { changed() } }
    var strikethrough = false { didSet { changed() } }
    var textAlignment: TextAlignmentOption = .left { didSet { changed() } }
    var dashStyle: LineDashStyle = .solid { didSet { changed() } }
    var startCap: LineCap = .flat { didSet { changed() } }
    var endCap: LineCap = .flat { didSet { changed() } }
    var bilinearResampling = true { didSet { changed() } }
    var selectionClippingAntialiased = true { didSet { changed() } }

    private var suppress = false

    private func changed() {
        if !suppress { NotificationCenter.default.post(name: .toolSettingsChanged, object: self) }
    }

    func load(from d: UserDefaults) {
        suppress = true
        defer { suppress = false }
        if d.object(forKey: "brushWidth") != nil { brushWidth = CGFloat(d.double(forKey: "brushWidth")) }
        if d.object(forKey: "hardness") != nil { hardness = d.double(forKey: "hardness") }
        if d.object(forKey: "antialiasing") != nil { antialiasing = d.bool(forKey: "antialiasing") }
        if d.object(forKey: "tolerance") != nil { tolerance = d.double(forKey: "tolerance") }
        if let f = d.string(forKey: "fontName") { fontName = f }
        if d.object(forKey: "fontSize") != nil { fontSize = CGFloat(d.double(forKey: "fontSize")) }
    }

    func save(to d: UserDefaults) {
        d.set(Double(brushWidth), forKey: "brushWidth")
        d.set(hardness, forKey: "hardness")
        d.set(antialiasing, forKey: "antialiasing")
        d.set(tolerance, forKey: "tolerance")
        d.set(fontName, forKey: "fontName")
        d.set(Double(fontSize), forKey: "fontSize")
    }
}

/// Global application state: colors, palette, active tool and view options.
final class AppEnvironment {
    static let shared = AppEnvironment()

    var primaryColor: ColorBgra = .black { didSet { postColors() } }
    var secondaryColor: ColorBgra = .white { didSet { postColors() } }
    let tools = ToolSettings()
    var palette: [ColorBgra] = AppEnvironment.defaultPalette { didSet { NotificationCenter.default.post(name: .paletteChanged, object: self) } }

    private(set) var activeTool: ToolKind = .paintbrush
    private(set) var previousTool: ToolKind = .paintbrush

    var showPixelGrid = false { didSet { postView() } }
    var showRulers = false { didSet { postView() } }
    var units: MeasurementUnit = .pixels { didSet { postView() } }

    private init() {
        let d = UserDefaults.standard
        tools.load(from: d)
        if let hexes = d.stringArray(forKey: "palette") {
            let p = hexes.compactMap { ColorBgra(hex: $0) }
            if p.count == 96 { palette = p }
        }
        if let raw = d.object(forKey: "units") as? Int, let u = MeasurementUnit(rawValue: raw) { units = u }
        showRulers = d.bool(forKey: "showRulers")
        showPixelGrid = d.bool(forKey: "showPixelGrid")
        if let p = d.string(forKey: "primaryColor").flatMap({ ColorBgra(hex: $0) }) { primaryColor = p }
        if let s = d.string(forKey: "secondaryColor").flatMap({ ColorBgra(hex: $0) }) { secondaryColor = s }
    }

    func save() {
        let d = UserDefaults.standard
        tools.save(to: d)
        d.set(palette.map(\.hexString), forKey: "palette")
        d.set(units.rawValue, forKey: "units")
        d.set(showRulers, forKey: "showRulers")
        d.set(showPixelGrid, forKey: "showPixelGrid")
        d.set(primaryColor.hexString, forKey: "primaryColor")
        d.set(secondaryColor.hexString, forKey: "secondaryColor")
    }

    func setActiveTool(_ t: ToolKind) {
        guard t != activeTool else { return }
        previousTool = activeTool
        activeTool = t
        NotificationCenter.default.post(name: .toolChanged, object: self)
    }

    func swapColors() {
        let p = primaryColor
        primaryColor = secondaryColor
        secondaryColor = p
    }

    func resetColors() {
        primaryColor = .black
        secondaryColor = .white
    }

    private func postColors() { NotificationCenter.default.post(name: .colorsChanged, object: self) }
    private func postView() { NotificationCenter.default.post(name: .viewSettingsChanged, object: self) }

    /// Paint.NET's default 96-color palette.
    static let defaultPalette: [ColorBgra] = {
        let hex = [
            "000000", "404040", "FF0000", "FF6A00", "FFD800", "B6FF00", "4CFF00", "00FF21",
            "00FF90", "00FFFF", "0094FF", "0026FF", "4800FF", "B200FF", "FF00DC", "FF006E",
            "FFFFFF", "808080", "FF7F7F", "FFB27F", "FFE97F", "DAFF7F", "A5FF7F", "7FFF8E",
            "7FFFC5", "7FFFFF", "7FC9FF", "7F92FF", "A17FFF", "D67FFF", "FF7FED", "FF7FB6",
            "A0A0A0", "303030", "7F0000", "7F3300", "7F6A00", "5B7F00", "267F00", "007F0E",
            "007F46", "007F7F", "004A7F", "00137F", "21007F", "57007F", "7F006E", "7F0037",
            "C0C0C0", "606060", "A35151", "A37151", "A39651", "8BA351", "6AA351", "51A35B",
            "51A37E", "51A3A3", "5181A3", "515EA3", "6751A3", "8951A3", "A35197", "A35174",
            "E0E0E0", "202020", "3F0000", "3F1A00", "3F3500", "2D3F00", "133F00", "003F07",
            "003F23", "003F3F", "00253F", "00093F", "10003F", "2B003F", "3F0037", "3F001B",
            "F0F0F0", "101010", "FFBFBF", "FFD8BF", "FFF4BF", "ECFFBF", "D2FFBF", "BFFFC6",
            "BFFFE2", "BFFFFF", "BFE4FF", "BFC8FF", "D0BFFF", "EABFFF", "FFBFF6", "FFBFDA",
        ]
        return hex.compactMap { ColorBgra(hex: $0) }
    }()
}

extension ColorBgra {
    var nsColor: NSColor {
        NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }

    init(nsColor: NSColor) {
        let c = nsColor.usingColorSpace(.sRGB) ?? nsColor
        self.init(r: clampToByte(Double(c.redComponent) * 255), g: clampToByte(Double(c.greenComponent) * 255),
                  b: clampToByte(Double(c.blueComponent) * 255), a: clampToByte(Double(c.alphaComponent) * 255))
    }
}
