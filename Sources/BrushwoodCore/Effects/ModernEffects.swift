import CoreGraphics
import Foundation

// Effects introduced in Paint.NET 5: Sketch Blur, Square Blur, Quantize, Crystalize, Morphology, Straighten, Turbulence.

public final class SketchBlurEffect: Effect {
    public override var name: String { "Sketch Blur" }
    public override var category: EffectCategory { .blurs }
    public override var parameters: [EffectParameter] {
        [
            .integer(id: "radius", label: "Radius", range: 1...100, defaultValue: 10),
            .integer(id: "percentile", label: "Percentile", range: 0...100, defaultValue: 50),
            .integer(id: "smoothness", label: "Smoothness", range: 1...10, defaultValue: 3),
        ]
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let radius = values.int("radius"), pct = values.int("percentile"), iterations = values.int("smoothness")
        return ClosureRenderer(wholeRegion: true) { dst, rect in
            // Repeated small percentile filters approximate a large one with softer, brush-like transitions.
            let step = max(1, Int((Double(radius) / Double(iterations)).rounded()))
            let pad = radius + 2
            let work = IntRect(x: rect.x - pad, y: rect.y - pad, width: rect.width + 2 * pad, height: rect.height + 2 * pad)
                .intersection(src.bounds)
            var a = src.clone()
            let b = src.clone()
            for _ in 0..<iterations {
                LocalHistogram.run(src: a, dst: b, rect: work, radius: step) { _, area, hb, hg, hr, ha in
                    LocalHistogram.percentile(pct, area: area, hb, hg, hr, ha)
                }
                a = b.clone()
            }
            dst.copy(from: a, rect: rect)
        }
    }
}

public final class SquareBlurEffect: Effect {
    public override var name: String { "Square Blur" }
    public override var category: EffectCategory { .blurs }
    public override var parameters: [EffectParameter] {
        [
            .integer(id: "radius", label: "Radius", range: 0...200, defaultValue: 10),
            .double(id: "gamma", label: "Gamma Boost", range: 0.25...4, defaultValue: 1, decimals: 2),
        ]
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let radius = values.int("radius"), gamma = Float(values.double("gamma"))
        let toLinear = (0..<256).map { Float(pow(Double($0) / 255, Double(gamma))) }
        return ClosureRenderer(wholeRegion: true) { dst, rect in
            if radius == 0 {
                dst.copy(from: src, rect: rect)
                return
            }
            // Separable box filter (running sums) in gamma-boosted, premultiplied space.
            let w = src.width, h = src.height
            let y0 = max(0, rect.top - radius), y1 = min(h, rect.bottom + radius)
            let cols = rect.width, rows = y1 - y0
            let tmp = UnsafeMutablePointer<SIMD4<Float>>.allocate(capacity: cols * rows)
            defer { tmp.deallocate() }
            DispatchQueue.concurrentPerform(iterations: rows) { i in
                let s = src.row(y0 + i)
                var sum = SIMD4<Float>(repeating: 0)
                var n: Float = 0
                @inline(__always) func value(_ x: Int) -> SIMD4<Float> {
                    let c = s[x]
                    let a = Float(c.a) / 255
                    return SIMD4(toLinear[Int(c.b)] * a, toLinear[Int(c.g)] * a, toLinear[Int(c.r)] * a, a)
                }
                let start = max(0, rect.left - radius)
                for x in start..<min(w, rect.left + radius + 1) { sum += value(x); n += 1 }
                for cx in 0..<cols {
                    let x = rect.left + cx
                    if cx > 0 {
                        let add = x + radius, rem = x - radius - 1
                        if add < w { sum += value(add); n += 1 }
                        if rem >= 0 { sum -= value(rem); n -= 1 }
                    }
                    tmp[i * cols + cx] = sum / max(1, n)
                }
            }
            DispatchQueue.concurrentPerform(iterations: rect.height) { i in
                let y = rect.top + i
                let d = dst.row(y)
                let lo = max(0, y - radius) - y0, hi = min(h - 1, y + radius) - y0
                for cx in 0..<cols {
                    var sum = SIMD4<Float>(repeating: 0)
                    for r in lo...hi { sum += tmp[r * cols + cx] }
                    let v = sum / Float(hi - lo + 1)
                    if v.w <= 0.0001 { d[rect.left + cx] = .transparent; continue }
                    let inv = 1 / gamma
                    func enc(_ c: Float) -> UInt8 { clampToByte(Double(pow(max(0, c / v.w), inv) * 255)) }
                    d[rect.left + cx] = ColorBgra(b: enc(v.x), g: enc(v.y), r: enc(v.z), a: clampToByte(Double(v.w * 255)))
                }
            }
        }
    }
}

public final class QuantizeEffect: Effect {
    public override var name: String { "Quantize" }
    public override var category: EffectCategory { .color }
    public override var parameters: [EffectParameter] {
        [
            .integer(id: "colors", label: "Color count", range: 2...256, defaultValue: 256),
            .choice(id: "algorithm", label: "Algorithm", options: ["Octree", "Median Cut"], defaultValue: 0, radio: true),
            .integer(id: "dither", label: "Dithering", range: 0...8, defaultValue: 8),
            .checkbox(id: "alpha", label: "Preserve transparency", defaultValue: true),
        ]
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let count = values.int("colors"), octree = values.int("algorithm") == 0
        let dither = Float(values.int("dither")) / 8, keepAlpha = values.bool("alpha")
        let region = env.selectionBounds
        // Gather opaque-ish sample colors (subsampled for large areas).
        var samples: [SIMD3<Float>] = []
        let stepPx = max(1, Int(sqrt(Double(region.area) / 200_000)))
        for y in stride(from: region.top, to: region.bottom, by: stepPx) {
            for x in stride(from: region.left, to: region.right, by: stepPx) {
                let c = src[x, y]
                if c.a >= 16 { samples.append(SIMD3(Float(c.r), Float(c.g), Float(c.b))) }
            }
        }
        let palette = octree ? Quantizer.octree(samples, maxColors: count) : Quantizer.medianCut(samples, maxColors: count)
        return ClosureRenderer(wholeRegion: true) { dst, rect in
            guard !palette.isEmpty else {
                dst.copy(from: src, rect: rect)
                return
            }
            // Floyd–Steinberg error diffusion scaled by the dithering level.
            var errCur = [SIMD3<Float>](repeating: .zero, count: rect.width + 2)
            var errNext = errCur
            for y in rect.top..<rect.bottom {
                let s = src.row(y), d = dst.row(y)
                for i in 0..<errNext.count { errNext[i] = .zero }
                for x in rect.left..<rect.right {
                    let c = s[x]
                    let k = x - rect.left + 1
                    let want = SIMD3(Float(c.r), Float(c.g), Float(c.b)) + errCur[k]
                    let p = Quantizer.nearest(palette, want)
                    var a = c.a
                    if !keepAlpha { a = c.a >= 128 ? 255 : 0 }
                    d[x] = ColorBgra(b: UInt8(p.z), g: UInt8(p.y), r: UInt8(p.x), a: a)
                    if dither > 0 && c.a > 0 {
                        let e = (want - p) * dither
                        errCur[k + 1] += e * (7.0 / 16)
                        errNext[k - 1] += e * (3.0 / 16)
                        errNext[k] += e * (5.0 / 16)
                        errNext[k + 1] += e * (1.0 / 16)
                    }
                }
                swap(&errCur, &errNext)
            }
        }
    }
}

/// Palette builders for Quantize.
enum Quantizer {
    static func nearest(_ palette: [SIMD3<Float>], _ c: SIMD3<Float>) -> SIMD3<Float> {
        var best = palette[0], bestD = Float.greatestFiniteMagnitude
        for p in palette {
            let d = p - c
            let dist = (d * d).sum()
            if dist < bestD { bestD = dist; best = p }
        }
        return best
    }

    static func medianCut(_ colors: [SIMD3<Float>], maxColors: Int) -> [SIMD3<Float>] {
        guard !colors.isEmpty else { return [] }
        var boxes: [[SIMD3<Float>]] = [colors]
        while boxes.count < maxColors {
            // Split the box with the widest channel range.
            var bestIndex = -1, bestRange: Float = 0, bestChannel = 0
            for (i, box) in boxes.enumerated() where box.count > 1 {
                let mn = box.reduce(SIMD3<Float>(repeating: 255)) { pointwiseMin($0, $1) }
                let mx = box.reduce(SIMD3<Float>(repeating: 0)) { pointwiseMax($0, $1) }
                let r = mx - mn
                let ch = r.x >= r.y && r.x >= r.z ? 0 : (r.y >= r.z ? 1 : 2)
                if r[ch] > bestRange { bestRange = r[ch]; bestIndex = i; bestChannel = ch }
            }
            if bestIndex < 0 || bestRange <= 0 { break }
            let sorted = boxes[bestIndex].sorted { $0[bestChannel] < $1[bestChannel] }
            let mid = sorted.count / 2
            boxes[bestIndex] = Array(sorted[..<mid])
            boxes.append(Array(sorted[mid...]))
        }
        return boxes.map { box in (box.reduce(SIMD3<Float>(repeating: 0), +) / Float(box.count)).rounded(.toNearestOrEven) }
    }

    /// Octree reduction: insert all colors (depth 8), then merge the deepest nodes until few enough leaves remain.
    static func octree(_ colors: [SIMD3<Float>], maxColors: Int) -> [SIMD3<Float>] {
        guard !colors.isEmpty else { return [] }
        final class Node {
            var children = [Node?](repeating: nil, count: 8)
            var sum = SIMD3<Float>(repeating: 0)
            var count: Float = 0
            var isLeaf = false
        }
        let root = Node()
        var levels = [[Node]](repeating: [], count: 9)
        for c in colors {
            var node = root
            let r = Int(c.x), g = Int(c.y), b = Int(c.z)
            for depth in 0..<8 {
                let shift = 7 - depth
                let idx = ((r >> shift) & 1) << 2 | ((g >> shift) & 1) << 1 | ((b >> shift) & 1)
                if node.children[idx] == nil {
                    let n = Node()
                    node.children[idx] = n
                    levels[depth + 1].append(n)
                }
                node = node.children[idx]!
            }
            node.isLeaf = true
            node.sum += c
            node.count += 1
        }
        var leafCount = levels[8].count
        var depth = 7
        while leafCount > maxColors && depth >= 0 {
            // Merge nodes at this depth, smallest first, until under budget.
            let nodes = levels[depth].sorted { a, b in
                a.children.compactMap { $0?.count }.reduce(0, +) < b.children.compactMap { $0?.count }.reduce(0, +)
            }
            for n in nodes where leafCount > maxColors && !n.isLeaf {
                var merged = 0
                for case let child? in n.children where child.isLeaf {
                    n.sum += child.sum
                    n.count += child.count
                    merged += 1
                }
                n.children = [Node?](repeating: nil, count: 8)
                n.isLeaf = true
                leafCount -= merged - 1
            }
            depth -= 1
        }
        var out: [SIMD3<Float>] = []
        func collect(_ n: Node) {
            if n.isLeaf {
                if n.count > 0 { out.append((n.sum / n.count).rounded(.toNearestOrEven)) }
                return
            }
            for case let c? in n.children { collect(c) }
        }
        collect(root)
        return out
    }
}

public final class CrystalizeEffect: Effect {
    public override var name: String { "Crystalize" }
    public override var category: EffectCategory { .distort }
    public override var parameters: [EffectParameter] {
        [
            .integer(id: "cellSize", label: "Cell Size", range: 2...250, defaultValue: 20),
            .integer(id: "quality", label: "Quality", range: 1...5, defaultValue: 2),
            .seed(id: "seed", label: "Randomize"),
        ]
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let cell = Double(values.int("cellSize")), q = values.int("quality"), seed = values.int("seed")
        // Jittered grid of cell centers: deterministic per grid cell, so tiles render consistently.
        @inline(__always) func center(_ gx: Int, _ gy: Int) -> (Double, Double) {
            let h1 = SeededRandom.hashDouble(gx, gy, seed), h2 = SeededRandom.hashDouble(gx, gy, seed &+ 911)
            return ((Double(gx) + h1) * cell, (Double(gy) + h2) * cell)
        }
        return ClosureRenderer { dst, rect in
            for y in rect.top..<rect.bottom {
                let d = dst.row(y)
                for x in rect.left..<rect.right {
                    var acc = SampleAccumulator()
                    for sy in 0..<q {
                        for sx in 0..<q {
                            let px = Double(x) + (Double(sx) + 0.5) / Double(q), py = Double(y) + (Double(sy) + 0.5) / Double(q)
                            let gx = Int(floor(px / cell)), gy = Int(floor(py / cell))
                            var best = Double.greatestFiniteMagnitude, bc = (0.0, 0.0)
                            for oy in -1...1 {
                                for ox in -1...1 {
                                    let c = center(gx + ox, gy + oy)
                                    let dd = (c.0 - px) * (c.0 - px) + (c.1 - py) * (c.1 - py)
                                    if dd < best { best = dd; bc = c }
                                }
                            }
                            acc.add(src.getClamped(Int(bc.0), Int(bc.1)))
                        }
                    }
                    d[x] = acc.color
                }
            }
        }
    }
}

public final class MorphologyEffect: Effect {
    public override var name: String { "Morphology" }
    public override var category: EffectCategory { .distort }
    public override var parameters: [EffectParameter] {
        [
            .choice(id: "mode", label: "Mode", options: ["Dilate", "Erode"], defaultValue: 0, radio: true),
            .integer(id: "width", label: "Width", range: 0...100, defaultValue: 3),
            .integer(id: "height", label: "Height", range: 0...100, defaultValue: 3),
            .checkbox(id: "linked", label: "Linked", defaultValue: true),
        ]
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let dilate = values.int("mode") == 0
        let rx = values.int("width"), ry = values.bool("linked") ? values.int("width") : values.int("height")
        return ClosureRenderer(wholeRegion: true) { dst, rect in
            // Separable rectangular min/max filter. Dilate grows bright and opaque areas; erode shrinks them.
            let w = src.width, h = src.height
            let y0 = max(0, rect.top - ry), y1 = min(h, rect.bottom + ry)
            let tmp = Surface(width: rect.width, height: y1 - y0)
            @inline(__always) func pick(_ a: ColorBgra, _ b: ColorBgra) -> ColorBgra {
                dilate ? ColorBgra(b: max(a.b, b.b), g: max(a.g, b.g), r: max(a.r, b.r), a: max(a.a, b.a))
                    : ColorBgra(b: min(a.b, b.b), g: min(a.g, b.g), r: min(a.r, b.r), a: min(a.a, b.a))
            }
            DispatchQueue.concurrentPerform(iterations: y1 - y0) { i in
                let s = src.row(y0 + i), t = tmp.row(i)
                for cx in 0..<rect.width {
                    let x = rect.left + cx
                    var v = s[x]
                    for xx in max(0, x - rx)...min(w - 1, x + rx) { v = pick(v, s[xx]) }
                    t[cx] = v
                }
            }
            DispatchQueue.concurrentPerform(iterations: rect.height) { i in
                let y = rect.top + i
                let d = dst.row(y)
                for cx in 0..<rect.width {
                    var v = tmp[cx, y - y0]
                    for yy in max(0, y - ry)...min(h - 1, y + ry) { v = pick(v, tmp[cx, yy - y0]) }
                    d[rect.left + cx] = v
                }
            }
        }
    }
}

public final class StraightenEffect: Effect {
    public override var name: String { "Straighten" }
    public override var category: EffectCategory { .photo }
    public override var parameters: [EffectParameter] {
        [
            .angle(id: "angle", label: "Angle", range: -45...45, defaultValue: 0),
            .choice(id: "sampling", label: "Sampling", options: ["Bicubic", "Nearest Neighbor", "Bilinear"], defaultValue: 0,
                    radio: false),
        ]
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let b = env.selectionBounds
        let angle = values.double("angle") * .pi / 180
        let sampling = values.int("sampling")
        let w = Double(b.width), h = Double(b.height)
        // Scale so the rotated image covers the whole area (no transparent corners), like straightening a photo.
        let ca = abs(cos(angle)), sa = abs(sin(angle))
        let scale = max((w * ca + h * sa) / w, (w * sa + h * ca) / h)
        let cx = Double(b.x) + w / 2, cy = Double(b.y) + h / 2
        let cosA = cos(-angle) / scale, sinA = sin(-angle) / scale
        return ClosureRenderer { dst, rect in
            for y in rect.top..<rect.bottom {
                let d = dst.row(y)
                for x in rect.left..<rect.right {
                    let dx = Double(x) + 0.5 - cx, dy = Double(y) + 0.5 - cy
                    let sx = cx + dx * cosA - dy * sinA, sy = cy + dx * sinA + dy * cosA
                    switch sampling {
                    case 1: d[x] = src.getClamped(Int(floor(sx)), Int(floor(sy)))
                    case 2: d[x] = src.bilinearSample(sx, sy)
                    default: d[x] = src.bicubicSample(sx, sy)
                    }
                }
            }
        }
    }
}

public final class TurbulenceEffect: Effect {
    public override var name: String { "Turbulence" }
    public override var category: EffectCategory { .render }
    public override var parameters: [EffectParameter] {
        [
            .integer(id: "octaves", label: "Octaves", range: 1...8, defaultValue: 4),
            .double(id: "period", label: "Period", range: 1...500, defaultValue: 100, decimals: 1),
            .double(id: "size", label: "Size", range: 0.1...4, defaultValue: 1, decimals: 2),
            .choice(id: "noise", label: "Noise", options: ["Turbulence", "Fractal Sum"], defaultValue: 0, radio: true),
            .checkbox(id: "blend", label: "Blend", defaultValue: false),
            .seed(id: "seed", label: "Randomize"),
        ]
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let octaves = values.int("octaves"), period = values.double("period"), size = values.double("size")
        let fractal = values.int("noise") == 1, blend = values.bool("blend")
        let seed = values.int("seed")
        let noises = (0..<3).map { PerlinNoise(seed: seed &+ $0 * 7919) }
        return ClosureRenderer { dst, rect in
            for y in rect.top..<rect.bottom {
                let d = dst.row(y), s = src.row(y)
                for x in rect.left..<rect.right {
                    var rgb = [0.0, 0.0, 0.0]
                    for ch in 0..<3 {
                        var sum = 0.0, amp = 1.0, freq = size / period, norm = 0.0
                        for _ in 0..<octaves {
                            let n = noises[ch].noise(Double(x) * freq, Double(y) * freq)
                            sum += (fractal ? n : abs(n)) * amp
                            norm += amp
                            amp *= 0.5
                            freq *= 2
                        }
                        let v = sum / norm
                        rgb[ch] = fractal ? (v + 1) / 2 * 1.3 : v * 2.2
                    }
                    let c = ColorBgra(b: clampToByte(rgb[2] * 255), g: clampToByte(rgb[1] * 255), r: clampToByte(rgb[0] * 255), a: 255)
                    d[x] = blend ? Blender.blend(.overlay, s[x], c) : c
                }
            }
        }
    }
}

extension Surface {
    /// Catmull-Rom bicubic sample (pixel centers at +0.5), alpha-weighted, clamped at the edges.
    public func bicubicSample(_ fx: Double, _ fy: Double) -> ColorBgra {
        let x = fx - 0.5, y = fy - 0.5
        let x0 = Int(floor(x)), y0 = Int(floor(y))
        let tx = x - Double(x0), ty = y - Double(y0)
        func weights(_ t: Double) -> [Double] {
            let t2 = t * t, t3 = t2 * t
            return [(-t3 + 2 * t2 - t) / 2, (3 * t3 - 5 * t2 + 2) / 2, (-3 * t3 + 4 * t2 + t) / 2, (t3 - t2) / 2]
        }
        let wx = weights(tx), wy = weights(ty)
        var r = 0.0, g = 0.0, b = 0.0, a = 0.0
        for j in 0..<4 {
            for i in 0..<4 {
                let c = getClamped(x0 - 1 + i, y0 - 1 + j)
                let wgt = wx[i] * wy[j]
                let aw = Double(c.a) * wgt
                r += Double(c.r) * aw
                g += Double(c.g) * aw
                b += Double(c.b) * aw
                a += aw
            }
        }
        if a <= 0.5 { return .transparent }
        return ColorBgra(b: clampToByte(b / a), g: clampToByte(g / a), r: clampToByte(r / a), a: clampToByte(a))
    }
}
