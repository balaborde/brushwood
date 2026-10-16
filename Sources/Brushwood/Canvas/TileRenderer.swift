import AppKit
import BrushwoodCore

/// Lazily composites the document into 256×256 display tiles (premultiplied CGImages).
/// Invalidations just drop tiles; they are rebuilt when they become visible.
final class TileRenderer {
    static let tileSize = 256
    let document: Document
    private var tiles: [Int: CGImage] = [:]
    /// Reduced copies of tiles (half, quarter… size) for drawing zoomed out, so that each redraw resamples about as
    /// many pixels as the screen shows instead of the whole image.
    private var reduced: [Int: CGImage] = [:]
    static let maxLevel = 6
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
            reduced.removeAll(keepingCapacity: true)
            return
        }
        let r = rect.intersection(document.bounds)
        if r.isEmpty { return }
        let s = TileRenderer.tileSize
        for ty in (r.top / s)...((r.bottom - 1) / s) {
            for tx in (r.left / s)...((r.right - 1) / s) {
                tiles.removeValue(forKey: key(tx, ty))
                for level in 1...TileRenderer.maxLevel { reduced.removeValue(forKey: key(tx, ty) * 8 + level) }
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

    /// The tile reduced by 2^level (level 0 is the tile itself).
    func image(_ tx: Int, _ ty: Int, level: Int) -> CGImage? {
        guard level > 0 else { return image(tx, ty) }
        let k = key(tx, ty) * 8 + level
        if let img = reduced[k] { return img }
        guard let full = image(tx, ty) else { return nil }
        let d = 1 << level
        let w = max(1, (full.width + d - 1) / d), h = max(1, (full.height + d - 1) / d)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: full.colorSpace ?? Surface.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return full }
        ctx.interpolationQuality = .high
        ctx.draw(full, in: CGRect(x: 0, y: 0, width: w, height: h))
        let img = ctx.makeImage()
        reduced[k] = img
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
