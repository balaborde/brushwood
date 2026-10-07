import CoreGraphics
import Foundation

/// How a new selection shape combines with the existing selection (Paint.NET selection modes).
public enum SelectionCombineMode: Int, CaseIterable, Codable {
    case replace
    case union
    case exclude
    case intersect
    case xor

    public var displayName: String {
        switch self {
        case .replace: return "Replace"
        case .union: return "Add (union)"
        case .exclude: return "Subtract"
        case .intersect: return "Intersect"
        case .xor: return "Invert (xor)"
        }
    }
}

/// An immutable geometric selection stored as a path in image coordinates (even-odd fill),
/// like Paint.NET's `PdnGraphicsPath`-based selection.
public final class Selection {
    public let path: CGPath
    public let bounds: CGRect
    private var maskCache: [String: MaskSurface] = [:]
    private let lock = NSLock()

    public init(path: CGPath) {
        self.path = path
        let b = path.boundingBoxOfPath
        bounds = b.isNull ? .zero : b
    }

    public static func rect(_ r: CGRect) -> Selection {
        Selection(path: CGPath(rect: r.standardized, transform: nil))
    }

    public static func ellipse(_ r: CGRect) -> Selection {
        Selection(path: CGPath(ellipseIn: r.standardized, transform: nil))
    }

    public var isEmpty: Bool { path.isEmpty || bounds.width <= 0 || bounds.height <= 0 }

    /// Integer bounds that cover all selected pixels.
    public var intBounds: IntRect { IntRect(enclosing: bounds) }

    public func contains(_ p: CGPoint) -> Bool {
        path.contains(p, using: .evenOdd)
    }

    public func transformed(_ t: CGAffineTransform) -> Selection {
        var tt = t
        guard let p = path.copy(using: &tt) else { return self }
        return Selection(path: p)
    }

    /// Combines this selection with another shape using a Paint.NET selection mode.
    public func combined(with shape: CGPath, mode: SelectionCombineMode) -> Selection {
        switch mode {
        case .replace: return Selection(path: shape)
        case .union: return Selection(path: path.union(shape, using: .evenOdd))
        case .exclude: return Selection(path: path.subtracting(shape, using: .evenOdd))
        case .intersect: return Selection(path: path.intersection(shape, using: .evenOdd))
        case .xor: return Selection(path: path.symmetricDifference(shape, using: .evenOdd))
        }
    }

    /// Applies a combine mode to an optional current selection. A nil result means "no selection".
    public static func combine(_ current: Selection?, with shape: CGPath, mode: SelectionCombineMode) -> Selection? {
        let result: Selection
        if let current, !current.isEmpty {
            result = current.combined(with: shape, mode: mode)
        } else {
            switch mode {
            case .exclude, .intersect:
                return nil
            default:
                result = Selection(path: shape)
            }
        }
        return result.isEmpty ? nil : result
    }

    /// Inverts the selection against the canvas rectangle.
    public func inverted(canvas: CGRect) -> Selection {
        Selection(path: CGPath(rect: canvas, transform: nil).subtracting(path, using: .evenOdd))
    }

    /// Coverage mask of the selection for a canvas size (cached).
    public func mask(width: Int, height: Int, antialias: Bool) -> MaskSurface {
        let key = "\(width)x\(height)\(antialias ? "a" : "n")"
        lock.lock()
        defer { lock.unlock() }
        if let m = maskCache[key] { return m }
        let m = MaskSurface.rasterize(path: path, width: width, height: height, antialias: antialias, fillRule: .evenOdd)
        maskCache[key] = m
        return m
    }

    /// Builds a pixel-exact selection from a coverage mask (magic wand, select by alpha...).
    public static func fromMask(_ mask: MaskSurface, threshold: UInt8 = 128) -> Selection? {
        let p = ContourTracer.path(from: mask, threshold: threshold)
        let s = Selection(path: p)
        return s.isEmpty ? nil : s
    }
}

/// Converts a binary mask into a polygon path whose edges follow pixel boundaries.
public enum ContourTracer {
    /// Traces outlines of pixels with coverage >= threshold. Outer boundaries and holes are emitted as
    /// separate closed polygons, so the path renders correctly with the even-odd rule.
    public static func path(from mask: MaskSurface, threshold: UInt8 = 128) -> CGPath {
        // Work only inside the bounding box of selected pixels to keep the vertex tables small.
        var minX = mask.width, minY = mask.height, maxX = -1, maxY = -1
        for y in 0..<mask.height {
            let p = mask.row(y)
            for x in 0..<mask.width where p[x] >= threshold {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        let path = CGMutablePath()
        if maxX < 0 { return path }
        let ox = minX, oy = minY, w = maxX - minX + 1, h = maxY - minY + 1
        let mw = mask.width
        @inline(__always) func inside(_ x: Int, _ y: Int) -> Bool {
            x >= 0 && y >= 0 && x < w && y < h && mask.data[(y + oy) * mw + x + ox] >= threshold
        }
        // Directed boundary edges between lattice vertices with the inside on the right (y down).
        // Vertex id = y * (w + 1) + x; a saddle vertex can have two outgoing edges.
        let vw = w + 1
        var next = [Int32](repeating: -1, count: (w + 1) * (h + 1))
        var next2 = [Int32](repeating: -1, count: (w + 1) * (h + 1))
        @inline(__always) func addEdge(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) {
            let a = y0 * vw + x0, b = Int32(y1 * vw + x1)
            if next[a] < 0 { next[a] = b } else { next2[a] = b }
        }
        for y in 0...h {
            for x in 0..<w {
                // Horizontal edge (x,y)-(x+1,y): pixel above is (x, y-1), below is (x, y).
                let above = inside(x, y - 1), below = inside(x, y)
                if above != below {
                    if below { addEdge(x, y, x + 1, y) } else { addEdge(x + 1, y, x, y) }
                }
            }
        }
        for y in 0..<h {
            for x in 0...w {
                let left = inside(x - 1, y), right = inside(x, y)
                if left != right {
                    if left { addEdge(x, y, x, y + 1) } else { addEdge(x, y + 1, x, y) }
                }
            }
        }
        for start in 0..<next.count {
            while next[start] >= 0 || next2[start] >= 0 {
                var cur = start
                var points: [CGPoint] = []
                var prevDir = (0, 0)
                repeat {
                    var nxt: Int32
                    if next[cur] >= 0 && next2[cur] >= 0 {
                        // Saddle vertex: prefer the right turn so diagonal pixels stay separate loops.
                        let c1 = Int(next[cur])
                        let d1 = (c1 % vw - cur % vw, c1 / vw - cur / vw)
                        if prevDir.0 * d1.1 - prevDir.1 * d1.0 > 0 {
                            nxt = next[cur]; next[cur] = -1
                        } else {
                            nxt = next2[cur]; next2[cur] = -1
                        }
                    } else if next[cur] >= 0 {
                        nxt = next[cur]; next[cur] = -1
                    } else if next2[cur] >= 0 {
                        nxt = next2[cur]; next2[cur] = -1
                    } else {
                        break
                    }
                    let n = Int(nxt)
                    let dir = (n % vw - cur % vw, n / vw - cur / vw)
                    if dir != prevDir {
                        points.append(CGPoint(x: cur % vw + ox, y: cur / vw + oy))
                        prevDir = dir
                    }
                    cur = n
                } while cur != start
                if points.count >= 3 {
                    path.addLines(between: points)
                    path.closeSubpath()
                }
            }
        }
        return path
    }
}
