import AppKit
import BrushwoodCore

/// Records an in-place pixel edit of one layer so it can be committed as a single history step.
final class PixelEditSession {
    let layer: BitmapLayer
    let original: Surface
    private(set) var dirty: IntRect = .zero

    init(layer: BitmapLayer) {
        self.layer = layer
        original = layer.surface.clone()
    }

    func touch(_ r: IntRect) {
        dirty = dirty.union(r.intersection(layer.surface.bounds))
    }

    /// Puts original pixels back in a region (used before re-rendering live previews).
    func restore(_ r: IntRect) {
        let rr = r.intersection(layer.surface.bounds)
        if !rr.isEmpty { layer.surface.copy(from: original, rect: rr) }
    }

    func cancel(_ doc: Document) {
        if !dirty.isEmpty {
            restore(dirty)
            doc.invalidate(dirty)
        }
        dirty = .zero
    }

    /// Builds the history item (nil if nothing changed).
    func makeHistoryItem(name: String, icon: String, selectionBefore: Selection? = nil, selectionAfter: Selection? = nil,
                         changesSelection: Bool = false) -> HistoryItem? {
        if dirty.isEmpty {
            if changesSelection {
                return SelectionHistoryItem(name: name, icon: icon, before: selectionBefore, after: selectionAfter)
            }
            return nil
        }
        guard let before = original.copy(rect: dirty), let after = layer.surface.copy(rect: dirty) else { return nil }
        return PixelHistoryItem(name: name, icon: icon, layer: layer, rect: dirty, before: before, after: after,
                                selectionBefore: selectionBefore, selectionAfter: selectionAfter,
                                changesSelection: changesSelection)
    }

    func commit(_ doc: Document, name: String, icon: String) {
        if let item = makeHistoryItem(name: name, icon: icon) { doc.history.push(item) }
    }
}

/// One open image (a tab in the image list): the document plus its file and view state.
final class DocumentWorkspace {
    let document: Document
    var fileURL: URL?
    var fileType: FileType?
    var saveOptions = SaveOptions()
    let untitledNumber: Int
    var zoom: CGFloat = 1
    /// Image-space point shown at the center of the viewport (restored when switching tabs).
    var viewCenter: CGPoint?
    var thumbnail: NSImage?

    private static var untitledCounter = 0

    init(document: Document, url: URL? = nil) {
        self.document = document
        fileURL = url
        if let url { fileType = FileType.forExtension(url.pathExtension) }
        if url == nil {
            DocumentWorkspace.untitledCounter += 1
            untitledNumber = DocumentWorkspace.untitledCounter
        } else {
            untitledNumber = 0
        }
    }

    var displayName: String {
        if let fileURL { return fileURL.lastPathComponent }
        return untitledNumber > 1 ? "\(L("Untitled")) \(untitledNumber)" : L("Untitled")
    }

    var env: AppEnvironment { .shared }

    // MARK: - History helpers

    /// Runs a structural change (layers/size) and records it as one history step.
    func structural(_ name: String, icon: String, _ body: () -> Void) {
        let before = DocumentState(document)
        body()
        document.history.push(DocumentHistoryItem(name: name, icon: icon, before: before, after: DocumentState(document)))
        document.post(.documentLayersChanged)
        document.invalidate()
    }

    func changeSelection(to s: Selection?, name: String, icon: String = "history.selection") {
        let before = document.selection
        document.setSelection(s)
        document.history.push(SelectionHistoryItem(name: name, icon: icon, before: before, after: document.selection))
    }

    /// Applies `body` to the active layer pixels within `rect` and records it.
    func editPixels(_ name: String, icon: String, rect: IntRect, _ body: (Surface) -> Void) {
        let layer = document.activeLayer
        let r = rect.intersection(document.bounds)
        guard !r.isEmpty, let before = layer.surface.copy(rect: r) else { return }
        body(layer.surface)
        guard let after = layer.surface.copy(rect: r) else { return }
        document.history.push(PixelHistoryItem(name: name, icon: icon, layer: layer, rect: r, before: before, after: after))
        document.invalidate(r)
    }

    // MARK: - Edit menu

    func selectAll() {
        changeSelection(to: Selection.rect(document.bounds.cgRect), name: L("Select All"), icon: "cmd.selectAll")
    }

    func deselect() {
        guard document.selection != nil else { return }
        changeSelection(to: nil, name: L("Deselect"), icon: "cmd.deselect")
    }

    func invertSelection() {
        let canvas = document.bounds.cgRect
        let inv: Selection? = document.selection.map { $0.inverted(canvas: canvas) } ?? nil
        changeSelection(to: inv, name: L("Invert Selection"), icon: "cmd.invertSelection")
    }

    func eraseSelection() {
        let mask = document.selectionMask(antialias: env.tools.selectionClippingAntialiased)
        let rect = document.selectionBoundsOrCanvas
        let layer = document.activeLayer
        guard !rect.isEmpty, let before = layer.surface.copy(rect: rect) else { return }
        for y in rect.top..<rect.bottom {
            let row = layer.surface.row(y)
            let m = mask?.row(y)
            for x in rect.left..<rect.right {
                let c = Int(m?[x] ?? 255)
                if c == 0 { continue }
                row[x] = Blender.lerpTo(row[x], row[x].withAlpha(0), coverage: c)
            }
        }
        let after = layer.surface.copy(rect: rect)!
        // Erasing also deselects, as in Paint.NET.
        let selectionBefore = document.selection
        document.setSelection(nil)
        document.history.push(PixelHistoryItem(name: L("Erase Selection"), icon: "cmd.eraseSelection", layer: layer,
                                               rect: rect, before: before, after: after, selectionBefore: selectionBefore,
                                               selectionAfter: nil, changesSelection: selectionBefore != nil))
        document.invalidate(rect)
    }

    func fillSelection(with color: ColorBgra) {
        let mask = document.selectionMask(antialias: env.tools.selectionClippingAntialiased)
        let rect = document.selectionBoundsOrCanvas
        editPixels(L("Fill Selection"), icon: "cmd.fillSelection", rect: rect) { s in
            for y in rect.top..<rect.bottom {
                let row = s.row(y)
                let m = mask?.row(y)
                for x in rect.left..<rect.right {
                    let c = Int(m?[x] ?? 255)
                    if c == 0 { continue }
                    row[x] = Blender.lerpTo(row[x], color, coverage: c)
                }
            }
        }
    }

    /// Pixels of the active layer (or flattened image) inside the selection, cropped to its bounds.
    func selectedPixels(merged: Bool) -> (Surface, IntRect)? {
        let rect = document.selectionBoundsOrCanvas
        guard !rect.isEmpty else { return nil }
        let source = merged ? document.flattened() : document.activeLayer.surface
        guard let out = source.copy(rect: rect) else { return nil }
        if let mask = document.selectionMask(antialias: env.tools.selectionClippingAntialiased) {
            for y in 0..<out.height {
                let row = out.row(y), m = mask.row(y + rect.top)
                for x in 0..<out.width {
                    let c = Int(m[x + rect.left])
                    if c < 255 { row[x].a = UInt8(mul255(Int(row[x].a), c)) }
                }
            }
        }
        return (out, rect)
    }

    // MARK: - Image menu

    func cropToSelection() {
        guard let sel = document.selection else { return }
        let rect = sel.intBounds.intersection(document.bounds)
        guard !rect.isEmpty else { return }
        let mask = sel.mask(width: document.width, height: document.height, antialias: env.tools.selectionClippingAntialiased)
        let isRect = sel.path.isRect(nil)
        structural(L("Crop to Selection"), icon: "cmd.crop") {
            let newLayers: [BitmapLayer] = document.layers.map { layer in
                let s = layer.surface.copy(rect: rect)!
                if !isRect {
                    for y in 0..<s.height {
                        let row = s.row(y), m = mask.row(y + rect.top)
                        for x in 0..<s.width {
                            let c = Int(m[x + rect.left])
                            if c < 255 { row[x].a = UInt8(mul255(Int(row[x].a), c)) }
                        }
                    }
                }
                layer.surface = s
                return layer
            }
            document.replaceAll(width: rect.width, height: rect.height, layers: newLayers)
            document.setSelection(nil)
        }
    }

    func resizeImage(to size: IntSize, mode: ResamplingMode, dpi: Double) {
        structural(L("Resize Image"), icon: "cmd.resize") {
            for layer in document.layers {
                layer.surface = Resampler.resize(layer.surface, to: size, mode: mode)
            }
            document.dpi = dpi
            document.replaceAll(width: size.width, height: size.height, layers: document.layers)
            document.setSelection(nil)
        }
    }

    /// `anchor` is (0...2, 0...2): column and row of the anchor grid.
    func resizeCanvas(to size: IntSize, anchor: (Int, Int), dpi: Double) {
        let dx: Int, dy: Int
        switch anchor.0 {
        case 0: dx = 0
        case 1: dx = (size.width - document.width) / 2
        default: dx = size.width - document.width
        }
        switch anchor.1 {
        case 0: dy = 0
        case 1: dy = (size.height - document.height) / 2
        default: dy = size.height - document.height
        }
        let bg = env.secondaryColor
        structural(L("Canvas Size"), icon: "cmd.canvasSize") {
            for (i, layer) in document.layers.enumerated() {
                // The bottom layer is filled with the secondary color like Paint.NET's background layer.
                let fill: ColorBgra = (i == 0 && layer.surface.isOpaque(rect: layer.surface.bounds)) ? bg : .transparent
                let s = Surface(width: size.width, height: size.height, fill: fill)
                s.copy(from: layer.surface, to: IntPoint(x: dx, y: dy))
                layer.surface = s
            }
            document.dpi = dpi
            document.replaceAll(width: size.width, height: size.height, layers: document.layers)
            document.setSelection(nil)
        }
    }

    func transformImage(_ name: String, icon: String, _ t: (Surface) -> Surface) {
        structural(name, icon: icon) {
            for layer in document.layers { layer.surface = t(layer.surface) }
            let w = document.layers[0].surface.width, h = document.layers[0].surface.height
            document.replaceAll(width: w, height: h, layers: document.layers)
            document.setSelection(nil)
        }
    }

    func flatten() {
        guard document.layers.count > 1 else { return }
        structural(L("Flatten"), icon: "cmd.flatten") {
            let flat = document.flattened()
            let layer = BitmapLayer(surface: flat, properties: LayerProperties(name: document.layers[0].name))
            document.replaceAll(width: document.width, height: document.height, layers: [layer])
            document.activeLayerIndex = 0
        }
    }

    // MARK: - Layers menu

    func nextLayerName() -> String {
        var n = document.layers.count + 1
        let names = Set(document.layers.map(\.name))
        while names.contains(LF("Layer %d", n)) { n += 1 }
        return LF("Layer %d", n)
    }

    func addLayer() {
        structural(L("Add New Layer"), icon: "layer.add") {
            let layer = BitmapLayer(width: document.width, height: document.height, name: nextLayerName())
            let idx = document.activeLayerIndex + 1
            document.layers.insert(layer, at: idx)
            document.activeLayerIndex = idx
        }
    }

    /// Layers > Import From File. Like Paint.NET, the canvas grows when the imported image is larger.
    func addLayer(surface: Surface, name: String) {
        structural(L("Import From File"), icon: "layer.import") {
            let w = max(document.width, surface.width), h = max(document.height, surface.height)
            if w != document.width || h != document.height {
                for layer in document.layers {
                    let grown = Surface(width: w, height: h)
                    grown.copy(from: layer.surface, to: IntPoint(x: 0, y: 0))
                    layer.surface = grown
                }
                document.replaceAll(width: w, height: h, layers: document.layers)
            }
            let s = Surface(width: w, height: h)
            s.copy(from: surface, to: IntPoint(x: 0, y: 0))
            let idx = document.activeLayerIndex + 1
            document.layers.insert(BitmapLayer(surface: s, properties: LayerProperties(name: name)), at: idx)
            document.activeLayerIndex = idx
        }
    }

    func rotateLayer180() {
        editPixels(L("Rotate Layer 180°"), icon: "cmd.rotate180", rect: document.bounds) { s in
            s.copy(from: Resampler.rotate180(s), to: IntPoint(x: 0, y: 0))
        }
    }

    func moveLayerToEnd(top: Bool) {
        let idx = document.activeLayerIndex
        let target = top ? document.layers.count - 1 : 0
        guard idx != target else { return }
        structural(top ? L("Move Layer to Top") : L("Move Layer to Bottom"), icon: top ? "layer.up" : "layer.down") {
            let l = document.layers.remove(at: idx)
            document.layers.insert(l, at: target)
            document.activeLayerIndex = target
        }
    }

    func deleteLayer() {
        guard document.layers.count > 1 else { return }
        structural(L("Delete Layer"), icon: "layer.delete") {
            let idx = document.activeLayerIndex
            document.layers.remove(at: idx)
            document.activeLayerIndex = max(0, idx - 1)
        }
    }

    func duplicateLayer() {
        structural(L("Duplicate Layer"), icon: "layer.duplicate") {
            let src = document.activeLayer
            let copy = src.clone()
            copy.name = LF("%@ copy", src.name)
            let idx = document.activeLayerIndex + 1
            document.layers.insert(copy, at: idx)
            document.activeLayerIndex = idx
        }
    }

    func mergeLayerDown() {
        let idx = document.activeLayerIndex
        guard idx > 0 else { return }
        structural(L("Merge Layer Down"), icon: "layer.merge") {
            let top = document.layers[idx], bottom = document.layers[idx - 1]
            let merged = bottom.surface.clone()
            if top.isVisible {
                for y in 0..<merged.height {
                    Blender.blendRow(top.blendMode, dst: merged.row(y), src: top.surface.row(y), count: merged.width,
                                     opacity: Int(top.opacity))
                }
            }
            bottom.surface = merged
            document.layers.remove(at: idx)
            document.activeLayerIndex = idx - 1
        }
    }

    func moveLayer(up: Bool) {
        let idx = document.activeLayerIndex
        let target = up ? idx + 1 : idx - 1
        guard target >= 0 && target < document.layers.count else { return }
        structural(up ? L("Move Layer Up") : L("Move Layer Down"), icon: up ? "layer.up" : "layer.down") {
            document.layers.swapAt(idx, target)
            document.activeLayerIndex = target
        }
    }

    func moveLayer(from: Int, to: Int) {
        guard from != to, from >= 0, to >= 0, from < document.layers.count, to < document.layers.count else { return }
        structural(to > from ? L("Move Layer Up") : L("Move Layer Down"), icon: to > from ? "layer.up" : "layer.down") {
            let l = document.layers.remove(at: from)
            document.layers.insert(l, at: to)
            document.activeLayerIndex = to
        }
    }

    func flipLayer(horizontal: Bool) {
        let layer = document.activeLayer
        let name = horizontal ? L("Flip Layer Horizontal") : L("Flip Layer Vertical")
        editPixels(name, icon: horizontal ? "layer.flipH" : "layer.flipV", rect: document.bounds) { s in
            let flipped = horizontal ? Resampler.flipHorizontal(s) : Resampler.flipVertical(s)
            s.copy(from: flipped, to: IntPoint(x: 0, y: 0))
        }
        _ = layer
    }

    func setLayerProperties(_ index: Int, _ props: LayerProperties, name: String = L("Layer Properties")) {
        let layer = document.layers[index]
        let before = layer.properties
        guard before != props else { return }
        layer.properties = props
        document.history.push(LayerPropertiesHistoryItem(name: name, icon: "layer.properties", layer: layer,
                                                         before: before, after: props))
        document.post(.documentLayersChanged)
        document.invalidate()
    }

    func toggleLayerVisibility(_ index: Int) {
        var p = document.layers[index].properties
        p.isVisible.toggle()
        setLayerProperties(index, p, name: p.isVisible ? L("Layer Shown") : L("Layer Hidden"))
    }
}
