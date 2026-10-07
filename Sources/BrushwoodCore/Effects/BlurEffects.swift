import CoreGraphics
import Foundation

/// Accumulates alpha-weighted color samples (Paint.NET's `ColorBgra.Blend`).
struct SampleAccumulator {
    var r = 0.0, g = 0.0, b = 0.0, a = 0.0, n = 0.0

    @inline(__always) mutating func add(_ c: ColorBgra, weight: Double = 1) {
        let aw = Double(c.a) * weight
        r += Double(c.r) * aw
        g += Double(c.g) * aw
        b += Double(c.b) * aw
        a += aw
        n += weight
    }

    var color: ColorBgra {
        if a <= 0 || n <= 0 { return .transparent }
        return ColorBgra(b: clampToByte(b / a), g: clampToByte(g / a), r: clampToByte(r / a), a: clampToByte(a / n))
    }
}

public final class GaussianBlurEffect: Effect {
    public override var name: String { "Gaussian Blur" }
    public override var category: EffectCategory { .blurs }
    public override var parameters: [EffectParameter] {
        [.integer(id: "radius", label: "Radius", range: 0...200, defaultValue: 2)]
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let radius = values.int("radius")
        return ClosureRenderer(wholeRegion: true) { dst, rect in
            EffectHelpers.gaussianBlur(src: src, dst: dst, rect: rect, radius: radius)
        }
    }
}

public final class MotionBlurEffect: Effect {
    public override var name: String { "Motion Blur" }
    public override var category: EffectCategory { .blurs }
    public override var parameters: [EffectParameter] {
        [
            .angle(id: "angle", label: "Angle", range: -180...180, defaultValue: 25),
            .checkbox(id: "centered", label: "Centered", defaultValue: true),
            .integer(id: "distance", label: "Distance", range: 1...200, defaultValue: 10),
        ]
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let theta = values.double("angle") * Double.pi / 180
        let distance = Double(values.int("distance"))
        let centered = values.bool("centered")
        let dx = cos(theta) * distance, dy = -sin(theta) * distance
        let n = max(2, Int(distance.rounded()) + 1)
        var offsets: [(Double, Double)] = []
        for i in 0..<n {
            let t = Double(i) / Double(n - 1)
            let k = centered ? t - 0.5 : t
            offsets.append((dx * k, dy * k))
        }
        return ClosureRenderer { dst, rect in
            let w = src.width, h = src.height
            for y in rect.top..<rect.bottom {
                let d = dst.row(y)
                for x in rect.left..<rect.right {
                    var acc = SampleAccumulator()
                    for (ox, oy) in offsets {
                        let sx = Int((Double(x) + ox).rounded()), sy = Int((Double(y) + oy).rounded())
                        if sx >= 0 && sy >= 0 && sx < w && sy < h { acc.add(src[sx, sy]) }
                    }
                    d[x] = acc.n > 0 ? acc.color : src[x, y]
                }
            }
        }
    }
}

public final class RadialBlurEffect: Effect {
    public override var name: String { "Radial Blur" }
    public override var category: EffectCategory { .blurs }
    public override var parameters: [EffectParameter] {
        [
            .angle(id: "angle", label: "Angle", range: 0...360, defaultValue: 2),
            .offset(id: "offset", label: "Offset", defaultValue: .zero),
            .integer(id: "quality", label: "Quality", range: 1...5, defaultValue: 2),
        ]
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let angle = values.double("angle") * Double.pi / 180
        let off = values.point("offset")
        let b = env.selectionBounds
        let cx = Double(b.x) + Double(b.width) * (0.5 + Double(off.x) / 2)
        let cy = Double(b.y) + Double(b.height) * (0.5 + Double(off.y) / 2)
        let quality = values.int("quality")
        return ClosureRenderer { dst, rect in
            for y in rect.top..<rect.bottom {
                let d = dst.row(y)
                for x in rect.left..<rect.right {
                    let px = Double(x) + 0.5 - cx, py = Double(y) + 0.5 - cy
                    let r = sqrt(px * px + py * py)
                    let arc = r * angle
                    let n = max(1, min(256, Int(arc * Double(quality) / 2) + 1))
                    if n == 1 {
                        d[x] = src[x, y]
                        continue
                    }
                    var acc = SampleAccumulator()
                    let base = atan2(py, px)
                    for i in 0..<n {
                        let a = base + angle * (Double(i) / Double(n - 1) - 0.5)
                        acc.add(src.bilinearSample(cx + r * cos(a), cy + r * sin(a)))
                    }
                    d[x] = acc.color
                }
            }
        }
    }
}

public final class ZoomBlurEffect: Effect {
    public override var name: String { "Zoom Blur" }
    public override var category: EffectCategory { .blurs }
    public override var parameters: [EffectParameter] {
        [
            .integer(id: "amount", label: "Zoom Amount", range: 0...100, defaultValue: 10),
            .offset(id: "offset", label: "Offset", defaultValue: .zero),
        ]
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let amount = Double(values.int("amount")) / 100
        let off = values.point("offset")
        let b = env.selectionBounds
        let cx = Double(b.x) + Double(b.width) * (0.5 + Double(off.x) / 2)
        let cy = Double(b.y) + Double(b.height) * (0.5 + Double(off.y) / 2)
        return ClosureRenderer { dst, rect in
            for y in rect.top..<rect.bottom {
                let d = dst.row(y)
                for x in rect.left..<rect.right {
                    let px = Double(x) + 0.5 - cx, py = Double(y) + 0.5 - cy
                    let len = sqrt(px * px + py * py) * amount
                    let n = max(1, min(128, Int(len / 2) + 1))
                    if n == 1 || amount == 0 {
                        d[x] = src[x, y]
                        continue
                    }
                    var acc = SampleAccumulator()
                    for i in 0..<n {
                        let f = 1 - amount * Double(i) / Double(n)
                        acc.add(src.bilinearSample(cx + px * f, cy + py * f))
                    }
                    d[x] = acc.color
                }
            }
        }
    }
}

public final class SurfaceBlurEffect: Effect {
    public override var name: String { "Surface Blur" }
    public override var category: EffectCategory { .blurs }
    public override var parameters: [EffectParameter] {
        [
            .integer(id: "radius", label: "Radius", range: 1...100, defaultValue: 6),
            .integer(id: "threshold", label: "Threshold", range: 1...100, defaultValue: 15),
        ]
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let radius = values.int("radius")
        let threshold = Double(values.int("threshold")) * 2.5
        // Weight table indexed by |difference|.
        let weights = (0..<256).map { max(0, 1 - Double($0) / threshold) }
        return ClosureRenderer(wholeRegion: true) { dst, rect in
            LocalHistogram.run(src: src, dst: dst, rect: rect, radius: radius) { c, _, hb, hg, hr, _ in
                @inline(__always) func channel(_ hist: UnsafeMutablePointer<Int32>, _ center: UInt8) -> UInt8 {
                    let cc = Int(center)
                    var sum = 0.0, wsum = 0.0
                    let lo = max(0, cc - Int(threshold)), hi = min(255, cc + Int(threshold))
                    for i in lo...hi {
                        let n = hist[i]
                        if n == 0 { continue }
                        let wt = weights[abs(i - cc)] * Double(n)
                        sum += wt * Double(i)
                        wsum += wt
                    }
                    return wsum > 0 ? clampToByte(sum / wsum) : center
                }
                return ColorBgra(b: channel(hb, c.b), g: channel(hg, c.g), r: channel(hr, c.r), a: c.a)
            }
        }
    }
}

public final class FragmentEffect: Effect {
    public override var name: String { "Fragment Blur" }
    public override var category: EffectCategory { .blurs }
    public override var parameters: [EffectParameter] {
        [
            .integer(id: "fragments", label: "Fragments", range: 2...50, defaultValue: 4),
            .integer(id: "distance", label: "Distance", range: 0...100, defaultValue: 8),
            .angle(id: "rotation", label: "Rotation", range: 0...360, defaultValue: 0),
        ]
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let n = values.int("fragments"), dist = Double(values.int("distance"))
        let rot = values.double("rotation") * Double.pi / 180
        let offsets: [(Int, Int)] = (0..<n).map { i in
            let a = rot + 2 * Double.pi * Double(i) / Double(n)
            return (Int((cos(a) * dist).rounded()), Int((sin(a) * dist).rounded()))
        }
        return ClosureRenderer { dst, rect in
            let w = src.width, h = src.height
            for y in rect.top..<rect.bottom {
                let d = dst.row(y)
                for x in rect.left..<rect.right {
                    var acc = SampleAccumulator()
                    for (ox, oy) in offsets {
                        let sx = x - ox, sy = y - oy
                        if sx >= 0 && sy >= 0 && sx < w && sy < h { acc.add(src[sx, sy]) }
                    }
                    d[x] = acc.n > 0 ? acc.color : .transparent
                }
            }
        }
    }
}

public final class BokehEffect: Effect {
    public override var name: String { "Bokeh Blur" }
    public override var category: EffectCategory { .blurs }
    public override var parameters: [EffectParameter] {
        [
            .integer(id: "radius", label: "Radius", range: 1...25, defaultValue: 8),
            .double(id: "exposure", label: "Exposure", range: -4...4, defaultValue: 0, decimals: 2),
            .double(id: "highlights", label: "Highlight boost", range: 0...10, defaultValue: 3, decimals: 2),
        ]
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let radius = values.int("radius")
        let exposure = pow(2, values.double("exposure"))
        let boost = values.double("highlights")
        var offsets: [(Int, Int)] = []
        for dy in -radius...radius {
            for dx in -radius...radius where dx * dx + dy * dy <= radius * radius { offsets.append((dx, dy)) }
        }
        let toLinear = (0..<256).map { Float(pow(Double($0) / 255, 2.2)) }
        return ClosureRenderer(wholeRegion: true) { dst, rect in
            let w = src.width, h = src.height
            // Linear-light premultiplied samples weighted to make highlights bloom into discs.
            let y0 = max(0, rect.top - radius), y1 = min(h, rect.bottom + radius)
            let x0 = max(0, rect.left - radius), x1 = min(w, rect.right + radius)
            let bw = x1 - x0
            let buf = UnsafeMutablePointer<SIMD4<Float>>.allocate(capacity: bw * (y1 - y0))
            defer { buf.deallocate() }
            EffectHelpers.parallelRows(IntRect(x: x0, y: y0, width: bw, height: y1 - y0)) { y in
                let s = src.row(y)
                for x in x0..<x1 {
                    let c = s[x]
                    let lr = toLinear[Int(c.r)], lg = toLinear[Int(c.g)], lb = toLinear[Int(c.b)]
                    let l = 0.299 * lr + 0.587 * lg + 0.114 * lb
                    let wgt = 1 + Float(boost) * l * l
                    let aw = Float(c.a) / 255 * wgt
                    buf[(y - y0) * bw + x - x0] = SIMD4(lb * aw, lg * aw, lr * aw, aw)
                }
            }
            EffectHelpers.parallelRows(rect) { y in
                let d = dst.row(y)
                for x in rect.left..<rect.right {
                    var acc = SIMD4<Float>(repeating: 0)
                    var n: Float = 0
                    for (ox, oy) in offsets {
                        let sx = clampInt(x + ox, x0, x1 - 1), sy = clampInt(y + oy, y0, y1 - 1)
                        acc += buf[(sy - y0) * bw + sx - x0]
                        n += 1
                    }
                    let a = acc.w
                    if a <= 0 { d[x] = .transparent; continue }
                    func enc(_ v: Float) -> UInt8 { clampToByte(pow(min(1, Double(v / a) * exposure), 1 / 2.2) * 255) }
                    d[x] = ColorBgra(b: enc(acc.x), g: enc(acc.y), r: enc(acc.z), a: clampToByte(min(255, a / n * 255)))
                }
            }
        }
    }
}
