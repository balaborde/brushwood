import CoreGraphics
import Foundation

/// A full copy of the image kept beside the history (Brushwood Plus, like Photoshop's snapshots). Going back to one adds
/// a history step, so a snapshot is never lost to undo or to new edits, and going back can itself be undone. Snapshots
/// stay with the open image; they are not saved in files.
public final class HistorySnapshot {
    /// Number in the default name ("Snapshot 2"): one more than the highest of the existing snapshots.
    public let number: Int
    /// Name given by the user; nil shows the default name.
    public internal(set) var customName: String?
    public let date = Date()
    public let thumbnail: CGImage?
    let state: DocumentState
    /// The current step when the snapshot was taken: back at that step, the image already looks like the snapshot.
    weak var takenAt: HistoryItem?

    init(document: Document, number: Int) {
        self.number = number
        state = DocumentState(document).copyingPixels()
        thumbnail = document.thumbnail(maxSize: 64)
        takenAt = document.history.currentItem
    }

    public var memoryFootprint: Int { state.memoryFootprint }
}

/// Going back to a snapshot.
final class SnapshotHistoryItem: HistoryItem {
    weak var snapshot: HistorySnapshot?
    let before: DocumentState
    let after: DocumentState

    init(name: String, icon: String, snapshot: HistorySnapshot, before: DocumentState, after: DocumentState) {
        self.snapshot = snapshot
        self.before = before
        self.after = after
        super.init(name: name, icon: icon)
    }

    override func undo(_ doc: Document) { before.restore(into: doc) }
    override func redo(_ doc: Document) { after.restore(into: doc) }
    override var memoryFootprint: Int { after.memoryFootprint }
}

extension DocumentState {
    init(width: Int, height: Int, layers: [LayerState], selection: Selection?, activeLayerIndex: Int, dpi: Double) {
        self.width = width
        self.height = height
        self.layers = layers
        self.selection = selection
        self.activeLayerIndex = activeLayerIndex
        self.dpi = dpi
    }

    /// The same state with its own copy of every layer's pixels, which later in-place edits leave alone.
    func copyingPixels() -> DocumentState {
        DocumentState(width: width, height: height,
                      layers: layers.map { LayerState(layer: $0.layer, surface: $0.surface.clone(), properties: $0.properties) },
                      selection: selection, activeLayerIndex: activeLayerIndex, dpi: dpi)
    }

    var memoryFootprint: Int { layers.reduce(0) { $0 + $1.surface.byteCount } }
}

extension HistoryStack {
    /// Copies the image as it is now into a new snapshot (counted in the memory budget).
    @discardableResult
    public func takeSnapshot() -> HistorySnapshot? {
        guard let doc = document else { return nil }
        let s = HistorySnapshot(document: doc, number: (snapshots.map(\.number).max() ?? 0) + 1)
        snapshots.append(s)
        trimToMemoryLimit()
        notify()
        return s
    }

    public func removeSnapshot(_ s: HistorySnapshot) {
        snapshots.removeAll { $0 === s }
        notify()
    }

    /// nil or an empty name goes back to the default name.
    public func rename(_ s: HistorySnapshot, to name: String?) {
        s.customName = name?.isEmpty == true ? nil : name
        notify()
    }

    /// True when the image already looks like the snapshot (just taken, or just gone back to).
    public func isShowing(_ s: HistorySnapshot) -> Bool {
        guard let current = currentItem else { return false }
        return current === s.takenAt || (current as? SnapshotHistoryItem)?.snapshot === s
    }

    /// Puts the image back as it was in the snapshot, as a new step named `name`.
    public func restore(_ s: HistorySnapshot, name: String, icon: String) {
        guard let doc = document, !isShowing(s) else { return }
        let before = DocumentState(doc)
        let after = s.state.copyingPixels()
        after.restore(into: doc)
        push(SnapshotHistoryItem(name: name, icon: icon, snapshot: s, before: before, after: after))
    }
}
