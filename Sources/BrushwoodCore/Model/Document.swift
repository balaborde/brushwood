import CoreGraphics
import Foundation

public struct LayerProperties: Equatable {
    public var name: String
    public var isVisible: Bool
    public var opacity: UInt8
    public var blendMode: BlendMode

    public init(name: String, isVisible: Bool = true, opacity: UInt8 = 255, blendMode: BlendMode = .normal) {
        self.name = name
        self.isVisible = isVisible
        self.opacity = opacity
        self.blendMode = blendMode
    }
}

/// A raster layer, like Paint.NET's `BitmapLayer`.
public final class BitmapLayer {
    public var surface: Surface
    public var properties: LayerProperties

    public var name: String {
        get { properties.name }
        set { properties.name = newValue }
    }
    public var isVisible: Bool {
        get { properties.isVisible }
        set { properties.isVisible = newValue }
    }
    public var opacity: UInt8 {
        get { properties.opacity }
        set { properties.opacity = newValue }
    }
    public var blendMode: BlendMode {
        get { properties.blendMode }
        set { properties.blendMode = newValue }
    }

    public init(surface: Surface, properties: LayerProperties) {
        self.surface = surface
        self.properties = properties
    }

    public convenience init(width: Int, height: Int, name: String, fill: ColorBgra = .transparent) {
        self.init(surface: Surface(width: width, height: height, fill: fill), properties: LayerProperties(name: name))
    }

    public func clone() -> BitmapLayer {
        BitmapLayer(surface: surface.clone(), properties: properties)
    }
}

public extension Notification.Name {
    /// userInfo["rect"] = NSValue(rect:) in image coordinates, absent = everything.
    static let documentInvalidated = Notification.Name("BrushwoodDocumentInvalidated")
    /// Layers were added/removed/reordered or properties changed.
    static let documentLayersChanged = Notification.Name("BrushwoodDocumentLayersChanged")
    static let documentSelectionChanged = Notification.Name("BrushwoodDocumentSelectionChanged")
    static let documentSizeChanged = Notification.Name("BrushwoodDocumentSizeChanged")
    static let documentHistoryChanged = Notification.Name("BrushwoodDocumentHistoryChanged")
    static let documentActiveLayerChanged = Notification.Name("BrushwoodDocumentActiveLayerChanged")
}

/// The image being edited: a stack of layers plus the current selection.
public final class Document {
    public private(set) var width: Int
    public private(set) var height: Int
    public var layers: [BitmapLayer]
    /// Index into `layers` (0 = bottom).
    public var activeLayerIndex: Int {
        didSet {
            activeLayerIndex = clampInt(activeLayerIndex, 0, max(0, layers.count - 1))
            if oldValue != activeLayerIndex { post(.documentActiveLayerChanged) }
        }
    }
    /// nil means "nothing selected" (whole canvas is editable).
    public private(set) var selection: Selection?
    /// Dots per inch; used for rulers/units and saved into files.
    public var dpi: Double = 96
    public let history: HistoryStack
    /// History entry that matched the file on disk; any other current entry means unsaved edits.
    private weak var savedHistoryItem: HistoryItem?
    private var savedMarkerSet = false

    public var isDirty: Bool {
        guard savedMarkerSet else { return history.currentIndex > 0 }
        return history.currentItem !== savedHistoryItem
    }

    public func markSaved() {
        savedHistoryItem = history.currentItem
        savedMarkerSet = true
        post(.documentHistoryChanged)
    }

    public init(width: Int, height: Int, layers: [BitmapLayer]) {
        precondition(!layers.isEmpty)
        self.width = width
        self.height = height
        self.layers = layers
        activeLayerIndex = layers.count - 1
        history = HistoryStack()
        history.document = self
    }

    /// New image with a white background layer, as Paint.NET's File > New.
    public convenience init(width: Int, height: Int, background: ColorBgra = .white) {
        self.init(width: width, height: height,
                  layers: [BitmapLayer(width: width, height: height, name: "Background", fill: background)])
    }

    public var bounds: IntRect { IntRect(x: 0, y: 0, width: width, height: height) }
    public var size: IntSize { IntSize(width: width, height: height) }
    public var activeLayer: BitmapLayer { layers[activeLayerIndex] }

    // MARK: - Notifications

    public func post(_ name: Notification.Name, rect: IntRect? = nil) {
        var info: [String: Any] = [:]
        if let rect { info["rect"] = rect }
        NotificationCenter.default.post(name: name, object: self, userInfo: info)
    }

    /// Marks pixels as changed (for redraw) and bumps the change counter.
    public func invalidate(_ rect: IntRect? = nil) {
        post(.documentInvalidated, rect: rect)
    }

    // MARK: - Selection

    public func setSelection(_ s: Selection?, notify: Bool = true) {
        if let s, s.isEmpty {
            selection = nil
        } else {
            selection = s
        }
        if notify { post(.documentSelectionChanged) }
    }

    /// Selection mask clipped to the canvas; nil when nothing is selected.
    public func selectionMask(antialias: Bool = true) -> MaskSurface? {
        selection?.mask(width: width, height: height, antialias: antialias)
    }

    /// Bounds affected by an operation: the selection bounds or the whole canvas.
    public var selectionBoundsOrCanvas: IntRect {
        guard let selection else { return bounds }
        return selection.intBounds.intersection(bounds)
    }

    // MARK: - Size changes (used by history snapshots and image operations)

    public func replaceAll(width: Int, height: Int, layers: [BitmapLayer]) {
        self.width = width
        self.height = height
        self.layers = layers
        activeLayerIndex = min(activeLayerIndex, layers.count - 1)
        post(.documentSizeChanged)
        post(.documentLayersChanged)
        invalidate()
    }

    // MARK: - Compositing

    /// Composites all visible layers into `dst` for the given rect.
    /// `override` lets callers substitute a surface for a layer index (live effect previews).
    public func render(into dst: Surface, rect: IntRect, override: [Int: Surface] = [:]) {
        let r = rect.intersection(bounds).intersection(dst.bounds)
        if r.isEmpty { return }
        for y in r.top..<r.bottom {
            let d = dst.row(y) + r.left
            d.update(repeating: .transparent, count: r.width)
            var first = true
            for (i, layer) in layers.enumerated() where layer.isVisible && layer.opacity > 0 {
                let surf = override[i] ?? layer.surface
                let s = surf.row(y) + r.left
                if first && layer.blendMode == .normal && layer.opacity == 255 {
                    d.update(from: s, count: r.width)
                } else {
                    Blender.blendRow(layer.blendMode, dst: d, src: s, count: r.width, opacity: Int(layer.opacity))
                }
                first = false
            }
        }
    }

    /// Flattened copy of the image.
    public func flattened() -> Surface {
        let s = Surface(width: width, height: height)
        render(into: s, rect: bounds)
        return s
    }

    /// Small preview image for tabs and thumbnails.
    public func thumbnail(maxSize: Int) -> CGImage? {
        let flat = flattened()
        return Resampler.thumbnail(of: flat, maxSize: maxSize)?.makeCGImage()
    }
}
