import AppKit
import BrushwoodCore

/// Lazily composites the document into 256×256 display tiles (premultiplied CGImages).
/// Invalidations just drop tiles; they are rebuilt when they become visible.
final class TileRenderer {
    static let tileSize = 256
    let document: Document
    private var tiles: [Int: CGImage] = [:]
    private let scratch = Surface(width: TileRenderer.tileSize, height: TileRenderer.tileSize)
    /// Live replacement surfaces for layers (effect previews render here instead of touching the layer).
    var overrides: [Int: Surface] = [:] {
        didSet { invalidate(nil) }
    }

    init(document: Document) {
        self.document = document
    }

    var columns: Int { (document.width + TileRenderer.tileSize - 1) / TileRenderer.tileSize }
    var rows: Int { (document.height + TileRenderer.tileSize - 1) / TileRenderer.tileSize }

    private func key(_ tx: Int, _ ty: Int) -> Int { ty * 100_000 + tx }

    func tileRect(_ tx: Int, _ ty: Int) -> IntRect {
        let s = TileRenderer.tileSize
        return IntRect(x: tx * s, y: ty * s, width: s, height: s).intersection(document.bounds)
    }

    func invalidate(_ rect: IntRect?) {
        guard let rect else {
            tiles.removeAll(keepingCapacity: true)
            return
        }
        let r = rect.intersection(document.bounds)
        if r.isEmpty { return }
        let s = TileRenderer.tileSize
        for ty in (r.top / s)...((r.bottom - 1) / s) {
            for tx in (r.left / s)...((r.right - 1) / s) {
                tiles.removeValue(forKey: key(tx, ty))
            }
        }
    }

    func image(_ tx: Int, _ ty: Int) -> CGImage? {
        let k = key(tx, ty)
        if let img = tiles[k] { return img }
        let r = tileRect(tx, ty)
        if r.isEmpty { return nil }
        // Render into the scratch surface at (0,0) by compositing with an offset view of the layers.
        compose(rect: r)
        let img = scratch.makePremultipliedCGImage(rect: IntRect(x: 0, y: 0, width: r.width, height: r.height))
        tiles[k] = img
        return img
    }

    private func compose(rect r: IntRect) {
        for y in 0..<r.height {
            let d = scratch.row(y)
            d.update(repeating: .transparent, count: r.width)
            var first = true
            for (i, layer) in document.layers.enumerated() where layer.isVisible && layer.opacity > 0 {
                let surf = overrides[i] ?? layer.surface
                let s = surf.row(r.top + y) + r.left
                if first && layer.blendMode == .normal && layer.opacity == 255 {
                    d.update(from: s, count: r.width)
                } else {
                    Blender.blendRow(layer.blendMode, dst: d, src: s, count: r.width, opacity: Int(layer.opacity))
                }
                first = false
            }
        }
    }
}
