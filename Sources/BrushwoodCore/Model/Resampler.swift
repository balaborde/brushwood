import CoreGraphics
import Foundation

/// Resampling algorithms offered by Image > Resize.
public enum ResamplingMode: Int, CaseIterable, Codable {
    case bestQuality
    case supersampling
    case bicubic
    case bilinear
    case lanczos3
    case nearestNeighbor

    public var displayName: String {
        switch self {
        case .bestQuality: return "Best Quality"
        case .supersampling: return "Supersampling"
        case .bicubic: return "Bicubic"
        case .bilinear: return "Bilinear"
        case .lanczos3: return "Lanczos 3"
        case .nearestNeighbor: return "Nearest Neighbor"
        }
    }
}

public enum Resampler {
    // MARK: Kernels

    private static func cubic(_ x0: Double) -> Double {
        // Catmull-Rom (a = -0.5), the usual "bicubic".
        let a = -0.5, x = abs(x0)
        if x < 1 { return (a + 2) * x * x * x - (a + 3) * x * x + 1 }
        if x < 2 { return a * x * x * x - 5 * a * x * x + 8 * a * x - 4 * a }
        return 0
    }

    private static func sinc(_ x: Double) -> Double {
        if x == 0 { return 1 }
        let px = Double.pi * x
        return sin(px) / px
    }

    private static func lanczos3(_ x: Double) -> Double {
        abs(x) < 3 ? sinc(x) * sinc(x / 3) : 0
    }

    private static func triangle(_ x: Double) -> Double { max(0, 1 - abs(x)) }

    private static func box(_ x: Double) -> Double { (x >= -0.5 && x < 0.5) ? 1 : 0 }

    private struct Kernel {
        let fn: (Double) -> Double
        let support: Double
    }

    private static func kernel(for mode: ResamplingMode, downscaling: Bool) -> Kernel {
        switch mode {
        case .bestQuality:
            return downscaling ? Kernel(fn: box, support: 0.5) : Kernel(fn: cubic, support: 2)
        case .supersampling:
            return Kernel(fn: box, support: 0.5)
        case .bicubic: return Kernel(fn: cubic, support: 2)
        case .bilinear: return Kernel(fn: triangle, support: 1)
        case .lanczos3: return Kernel(fn: lanczos3, support: 3)
        case .nearestNeighbor: return Kernel(fn: box, support: 0.5)
        }
    }

    private struct Contrib {
        let start: Int
        let weights: [Float]
    }

    private static func contributions(srcSize: Int, dstSize: Int, kernel: Kernel, isBox: Bool) -> [Contrib] {
        let scale = Double(dstSize) / Double(srcSize)
        let filterScale = max(1.0, 1.0 / scale)
        let support = kernel.support * filterScale
        var result: [Contrib] = []
        result.reserveCapacity(dstSize)
        for i in 0..<dstSize {
            let center = (Double(i) + 0.5) / scale
            if isBox && scale < 1 {
                // Exact area coverage for supersampling.
                let left = Double(i) / scale, right = Double(i + 1) / scale
                let s = max(0, Int(floor(left))), e = min(srcSize - 1, Int(ceil(right)) - 1)
                var w: [Float] = []
                var total: Float = 0
                if e >= s {
                    for j in s...e {
                        let cov = Float(min(right, Double(j + 1)) - max(left, Double(j)))
                        w.append(max(0, cov))
                        total += max(0, cov)
                    }
                }
                if total > 0 { w = w.map { $0 / total } }
                result.append(Contrib(start: s, weights: w))
                continue
            }
            let s = Int(floor(center - support)), e = Int(ceil(center + support))
            var w: [Float] = []
            var total: Float = 0
            let start = max(0, s)
            let end = min(srcSize - 1, e)
            if end >= start {
                for j in start...end {
                    let v = Float(kernel.fn((Double(j) + 0.5 - center) / filterScale))
                    w.append(v)
                    total += v
                }
            }
            if total != 0 { w = w.map { $0 / total } }
            if w.isEmpty {
                result.append(Contrib(start: clampInt(Int(center), 0, srcSize - 1), weights: [1]))
            } else {
                result.append(Contrib(start: start, weights: w))
            }
        }
        return result
    }

    /// Resizes a surface to a new size using the chosen algorithm.
    public static func resize(_ src: Surface, to size: IntSize, mode: ResamplingMode) -> Surface {
        let dw = max(1, size.width), dh = max(1, size.height)
        if dw == src.width && dh == src.height { return src.clone() }
        let dst = Surface(width: dw, height: dh)
        if mode == .nearestNeighbor {
            for y in 0..<dh {
                let sy = min(src.height - 1, Int((Double(y) + 0.5) * Double(src.height) / Double(dh)))
                let d = dst.row(y), s = src.row(sy)
                for x in 0..<dw {
                    let sx = min(src.width - 1, Int((Double(x) + 0.5) * Double(src.width) / Double(dw)))
                    d[x] = s[sx]
                }
            }
            return dst
        }
        let downX = dw < src.width, downY = dh < src.height
        let kx = kernel(for: mode, downscaling: downX)
        let ky = kernel(for: mode, downscaling: downY)
        let isBoxX = mode == .supersampling || (mode == .bestQuality && downX)
        let isBoxY = mode == .supersampling || (mode == .bestQuality && downY)
        let cx = contributions(srcSize: src.width, dstSize: dw, kernel: kx, isBox: isBoxX)
        let cy = contributions(srcSize: src.height, dstSize: dh, kernel: ky, isBox: isBoxY)

        // Horizontal pass into premultiplied float buffer (dw x srcHeight).
        let tmp = UnsafeMutablePointer<SIMD4<Float>>.allocate(capacity: dw * src.height)
        defer { tmp.deallocate() }
        DispatchQueue.concurrentPerform(iterations: src.height) { y in
            let s = src.row(y)
            let t = tmp + y * dw
            for x in 0..<dw {
                let c = cx[x]
                var acc = SIMD4<Float>(repeating: 0)
                for (k, w) in c.weights.enumerated() {
                    let p = s[c.start + k]
                    let a = Float(p.a)
                    acc += SIMD4<Float>(Float(p.b) * a, Float(p.g) * a, Float(p.r) * a, a) * w
                }
                t[x] = acc
            }
        }
        // Vertical pass.
        DispatchQueue.concurrentPerform(iterations: dh) { y in
            let c = cy[y]
            let d = dst.row(y)
            for x in 0..<dw {
                var acc = SIMD4<Float>(repeating: 0)
                for (k, w) in c.weights.enumerated() {
                    acc += tmp[(c.start + k) * dw + x] * w
                }
                let a = acc.w
                if a <= 0.5 {
                    d[x] = .transparent
                } else {
                    d[x] = ColorBgra(b: clampToByte(acc.x / a), g: clampToByte(acc.y / a), r: clampToByte(acc.z / a),
                                     a: clampToByte(a))
                }
            }
        }
        return dst
    }

    /// Downscaled copy that fits in `maxSize` × `maxSize`.
    public static func thumbnail(of src: Surface, maxSize: Int) -> Surface? {
        let scale = min(1.0, Double(maxSize) / Double(max(src.width, src.height)))
        let w = max(1, Int((Double(src.width) * scale).rounded()))
        let h = max(1, Int((Double(src.height) * scale).rounded()))
        if w == src.width && h == src.height { return src.clone() }
        return resize(src, to: IntSize(width: w, height: h), mode: .supersampling)
    }

    /// Renders `src` through an affine transform (image→destination space) with bilinear sampling.
    /// Pixels mapping outside `src` become transparent.
    public static func transform(_ src: Surface, _ t: CGAffineTransform, into dst: Surface, rect: IntRect? = nil,
                                 bilinear: Bool = true) {
        let inv = t.inverted()
        let r = (rect ?? dst.bounds).intersection(dst.bounds)
        if r.isEmpty { return }
        DispatchQueue.concurrentPerform(iterations: r.height) { i in
            let y = r.top + i
            let d = dst.row(y)
            for x in r.left..<r.right {
                let p = CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5).applying(inv)
                if bilinear {
                    d[x] = src.bilinearSampleTransparentEdges(Double(p.x), Double(p.y))
                } else {
                    let sx = Int(floor(p.x)), sy = Int(floor(p.y))
                    d[x] = (sx >= 0 && sy >= 0 && sx < src.width && sy < src.height) ? src[sx, sy] : .transparent
                }
            }
        }
    }

    // MARK: Simple orthogonal transforms

    public static func flipHorizontal(_ s: Surface) -> Surface {
        let d = Surface(width: s.width, height: s.height)
        for y in 0..<s.height {
            let sr = s.row(y), dr = d.row(y)
            for x in 0..<s.width { dr[x] = sr[s.width - 1 - x] }
        }
        return d
    }

    public static func flipVertical(_ s: Surface) -> Surface {
        let d = Surface(width: s.width, height: s.height)
        for y in 0..<s.height { d.row(y).update(from: s.row(s.height - 1 - y), count: s.width) }
        return d
    }

    public static func rotate90CW(_ s: Surface) -> Surface {
        let d = Surface(width: s.height, height: s.width)
        for y in 0..<s.height {
            let sr = s.row(y)
            for x in 0..<s.width { d[s.height - 1 - y, x] = sr[x] }
        }
        return d
    }

    public static func rotate90CCW(_ s: Surface) -> Surface {
        let d = Surface(width: s.height, height: s.width)
        for y in 0..<s.height {
            let sr = s.row(y)
            for x in 0..<s.width { d[y, s.width - 1 - x] = sr[x] }
        }
        return d
    }

    public static func rotate180(_ s: Surface) -> Surface {
        let d = Surface(width: s.width, height: s.height)
        let n = s.width * s.height
        for i in 0..<n { d.pixels[n - 1 - i] = s.pixels[i] }
        return d
    }
}
