import Foundation

/// One undoable step shown in the History window.
open class HistoryItem {
    public let name: String
    /// Icon identifier resolved by the UI (tool or menu command icon).
    public let icon: String

    public init(name: String, icon: String) {
        self.name = name
        self.icon = icon
    }

    open func undo(_ doc: Document) {}
    open func redo(_ doc: Document) {}
    open var memoryFootprint: Int { 0 }
}

/// Placeholder first entry ("New Image" / "Open Image").
public final class BaseHistoryItem: HistoryItem {}

/// Replaces a rectangle of one layer's pixels, optionally also swapping the selection.
public final class PixelHistoryItem: HistoryItem {
    let layer: BitmapLayer
    let origin: IntPoint
    let before: Surface
    let after: Surface
    let selectionBefore: Selection?
    let selectionAfter: Selection?
    let changesSelection: Bool

    public init(name: String, icon: String, layer: BitmapLayer, rect: IntRect, before: Surface, after: Surface,
                selectionBefore: Selection? = nil, selectionAfter: Selection? = nil, changesSelection: Bool = false) {
        self.layer = layer
        origin = IntPoint(x: rect.x, y: rect.y)
        self.before = before
        self.after = after
        self.selectionBefore = selectionBefore
        self.selectionAfter = selectionAfter
        self.changesSelection = changesSelection
        super.init(name: name, icon: icon)
    }

    public override func undo(_ doc: Document) {
        layer.surface.copy(from: before, to: origin)
        if changesSelection { doc.setSelection(selectionBefore) }
        doc.invalidate(IntRect(x: origin.x, y: origin.y, width: before.width, height: before.height))
    }

    public override func redo(_ doc: Document) {
        layer.surface.copy(from: after, to: origin)
        if changesSelection { doc.setSelection(selectionAfter) }
        doc.invalidate(IntRect(x: origin.x, y: origin.y, width: after.width, height: after.height))
    }

    public override var memoryFootprint: Int { before.byteCount + after.byteCount }
}

public final class SelectionHistoryItem: HistoryItem {
    let before: Selection?
    let after: Selection?

    public init(name: String, icon: String, before: Selection?, after: Selection?) {
        self.before = before
        self.after = after
        super.init(name: name, icon: icon)
    }

    public override func undo(_ doc: Document) { doc.setSelection(before) }
    public override func redo(_ doc: Document) { doc.setSelection(after) }
}

public final class LayerPropertiesHistoryItem: HistoryItem {
    let layer: BitmapLayer
    let before: LayerProperties
    let after: LayerProperties

    public init(name: String, icon: String, layer: BitmapLayer, before: LayerProperties, after: LayerProperties) {
        self.layer = layer
        self.before = before
        self.after = after
        super.init(name: name, icon: icon)
    }

    public override func undo(_ doc: Document) {
        layer.properties = before
        doc.post(.documentLayersChanged)
        doc.invalidate()
    }

    public override func redo(_ doc: Document) {
        layer.properties = after
        doc.post(.documentLayersChanged)
        doc.invalidate()
    }
}

/// Captures the document structure by object identity. Because every in-place pixel edit is
/// recorded as its own reversible item, swapping layer/surface references back is always consistent.
public struct DocumentState {
    struct LayerState {
        let layer: BitmapLayer
        let surface: Surface
        let properties: LayerProperties
    }

    let width: Int
    let height: Int
    let layers: [LayerState]
    let selection: Selection?
    let activeLayerIndex: Int
    let dpi: Double

    public init(_ doc: Document) {
        width = doc.width
        height = doc.height
        layers = doc.layers.map { LayerState(layer: $0, surface: $0.surface, properties: $0.properties) }
        selection = doc.selection
        activeLayerIndex = doc.activeLayerIndex
        dpi = doc.dpi
    }

    func restore(into doc: Document) {
        for ls in layers {
            ls.layer.surface = ls.surface
            ls.layer.properties = ls.properties
        }
        let sizeChanged = doc.width != width || doc.height != height
        doc.dpi = dpi
        doc.replaceAll(width: width, height: height, layers: layers.map { $0.layer })
        doc.activeLayerIndex = activeLayerIndex
        doc.setSelection(selection)
        if sizeChanged { doc.post(.documentSizeChanged) }
    }
}

/// Structural change (layers added/removed/reordered, image resized/rotated, flatten...).
public final class DocumentHistoryItem: HistoryItem {
    let before: DocumentState
    let after: DocumentState

    public init(name: String, icon: String, before: DocumentState, after: DocumentState) {
        self.before = before
        self.after = after
        super.init(name: name, icon: icon)
    }

    public override func undo(_ doc: Document) { before.restore(into: doc) }
    public override func redo(_ doc: Document) { after.restore(into: doc) }
}

/// Several items applied as one step.
public final class CompoundHistoryItem: HistoryItem {
    let items: [HistoryItem]

    public init(name: String, icon: String, items: [HistoryItem]) {
        self.items = items
        super.init(name: name, icon: icon)
    }

    public override func undo(_ doc: Document) { items.reversed().forEach { $0.undo(doc) } }
    public override func redo(_ doc: Document) { items.forEach { $0.redo(doc) } }
    public override var memoryFootprint: Int { items.reduce(0) { $0 + $1.memoryFootprint } }
}

/// Linear undo stack with a movable cursor, like Paint.NET's History window.
public final class HistoryStack {
    weak var document: Document?
    public private(set) var items: [HistoryItem] = []
    /// Index of the current state; items after it are "redo" steps.
    public private(set) var currentIndex = -1

    init() {}

    public var currentItem: HistoryItem? { currentIndex >= 0 && currentIndex < items.count ? items[currentIndex] : nil }
    public var canUndo: Bool { currentIndex > 0 }
    public var canRedo: Bool { currentIndex < items.count - 1 }
    public var undoName: String? { canUndo ? items[currentIndex].name : nil }
    public var redoName: String? { canRedo ? items[currentIndex + 1].name : nil }

    /// Sets the base entry; clears all history.
    public func reset(baseName: String, icon: String) {
        items = [BaseHistoryItem(name: baseName, icon: icon)]
        currentIndex = 0
        notify()
    }

    /// Records an action that has already been applied to the document.
    public func push(_ item: HistoryItem) {
        if currentIndex < items.count - 1 {
            items.removeSubrange((currentIndex + 1)...)
        }
        items.append(item)
        currentIndex = items.count - 1
        notify()
    }

    public func undo() {
        guard canUndo, let doc = document else { return }
        items[currentIndex].undo(doc)
        currentIndex -= 1
        notify()
    }

    public func redo() {
        guard canRedo, let doc = document else { return }
        currentIndex += 1
        items[currentIndex].redo(doc)
        notify()
    }

    /// Moves the state to just after item `index` (clicking a History row).
    public func step(to index: Int) {
        let target = clampInt(index, 0, items.count - 1)
        while currentIndex > target { undo() }
        while currentIndex < target { redo() }
    }

    public var memoryFootprint: Int { items.reduce(0) { $0 + $1.memoryFootprint } }

    private func notify() {
        document?.post(.documentHistoryChanged)
    }
}
