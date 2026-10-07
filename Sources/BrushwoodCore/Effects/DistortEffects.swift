import CoreGraphics
import Foundation

/// What warp effects do with samples that fall outside the image (Paint.NET's `WarpEdgeBehavior`).
public enum WarpEdgeBehavior: Int, CaseIterable {
    case clamp, reflect, primary, secondary, transparent, wrap, original

    public static var displayNames: [String] {
        ["Clamp", "Reflect", "Primary", "Secondary", "Transparent", "Wrap", "Original"]
    }
}

/// Supersampled inverse-mapping renderer shared by the warp effects.
final class WarpRenderer: EffectRenderer {
    let src: Surface
    let edge: WarpEdgeBehavior
    let quality: Int
    let cx: Double, cy: Double
    let env: EffectEnvironment
    /// Maps a destination point (relative to center) to a source point (relative to center); nil = keep source.
    let inverse: (Double, Double) -> (Double, Double)?
    let aaPoints: [(Double, Double)]

    init(src: Surface, env: EffectEnvironment, offset: CGPoint, quality: Int, edge: WarpEdgeBehavior,
         inverse: @escaping (Double, Double) -> (Double, Double)?) {
        self.src = src
        self.env = env
        self.edge = edge
        self.quality = max(1, quality)
        self.inverse = inverse
        let b = env.selectionBounds
        cx = Double(b.x) + Double(b.width) * (1 + Double(offset.x)) / 2
        cy = Double(b.y) + Double(b.height) * (1 + Double(offset.y)) / 2
        var pts: [(Double, Double)] = []
        let q = self.quality
        if q == 1 {
            pts = [(0.5, 0.5)]
        } else {
            for i in 0..<(q * q) {
                pts.append(((Double(i % q) + 0.5) / Double(q), (Double(i / q) + 0.5) / Double(q)))
            }
        }
        aaPoints = pts
    }

    @inline(__always) func sample(_ x: Double, _ y: Double, origX: Int, origY: Int) -> ColorBgra {
        let w = Double(src.width), h = Double(src.height)
        var sx = x, sy = y
        if sx < 0 || sy < 0 || sx >= w || sy >= h {
            switch edge {
            case .clamp:
                sx = clampDouble(sx, 0, w - 0.001)
                sy = clampDouble(sy, 0, h - 0.001)
            case .reflect:
                sx = reflect(sx, w)
                sy = reflect(sy, h)
            case .wrap:
                sx = sx.truncatingRemainder(dividingBy: w)
                if sx < 0 { sx += w }
                sy = sy.truncatingRemainder(dividingBy: h)
                if sy < 0 { sy += h }
            case .primary: return env.primaryColor
            case .secondary: return env.secondaryColor
            case .transparent: return .transparent
            case .original: return src[origX, origY]
            }
        }
        return src.bilinearSample(sx, sy)
    }

    @inline(__always) func reflect(_ v: Double, _ size: Double) -> Double {
        var t = v.truncatingRemainder(dividingBy: 2 * size)
        if t < 0 { t += 2 * size }
        if t >= size { t = 2 * size - t - 0.001 }
        return max(0, t)
    }

    func render(into dst: Surface, rect: IntRect) {
        for y in rect.top..<rect.bottom {
            let d = dst.row(y)
            for x in rect.left..<rect.right {
                var acc = SampleAccumulator()
                var keep = false
                for (ax, ay) in aaPoints {
                    let rx = Double(x) + ax - cx, ry = Double(y) + ay - cy
                    guard let (tx, ty) = inverse(rx, ry) else {
                        keep = true
                        break
                    }
                    acc.add(sample(tx + cx, ty + cy, origX: x, origY: y))
                }
                d[x] = keep ? src[x, y] : acc.color
            }
        }
    }
}

private func warpParameters(_ extra: [EffectParameter], edgeDefault: WarpEdgeBehavior = .reflect,
                            offset: Bool = true) -> [EffectParameter] {
    var p = extra
    if offset { p.append(.offset(id: "offset", label: "Offset", defaultValue: .zero)) }
    p.append(.choice(id: "edge", label: "Edge Behavior", options: WarpEdgeBehavior.displayNames,
                     defaultValue: edgeDefault.rawValue, radio: false))
    p.append(.integer(id: "quality", label: "Quality", range: 1...5, defaultValue: 2))
    return p
}

public final class BulgeEffect: Effect {
    public override var name: String { "Bulge" }
    public override var category: EffectCategory { .distort }
    public override var parameters: [EffectParameter] {
        [
            .integer(id: "amount", label: "Bulge", range: -200...100, defaultValue: 45),
            .offset(id: "offset", label: "Offset", defaultValue: .zero),
        ]
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let amt = Double(values.int("amount")) / 100
        let b = env.selectionBounds
        let maxrad = Double(min(b.width, b.height)) / 2
        return WarpRenderer(src: src, env: env, offset: values.point("offset"), quality: 2, edge: .clamp) { u, v in
            let r = sqrt(u * u + v * v)
            let rscale1 = 1 - r / maxrad
            if rscale1 <= 0 { return (u, v) }
            let rscale2 = 1 - amt * rscale1 * rscale1
            return (u * rscale2, v * rscale2)
        }
    }
}

public final class TwistEffect: Effect {
    public override var name: String { "Twist" }
    public override var category: EffectCategory { .distort }
    public override var parameters: [EffectParameter] {
        warpParameters([
            .integer(id: "amount", label: "Amount", range: -200...200, defaultValue: 45),
            .double(id: "size", label: "Size", range: 0.01...2, defaultValue: 1, decimals: 2),
        ], edgeDefault: .clamp)
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        var twist = Double(values.int("amount"))
        twist = twist * twist * (twist < 0 ? -1 : 1)
        let b = env.selectionBounds
        let maxrad = Double(min(b.width, b.height)) / 2 * values.double("size")
        let edge = WarpEdgeBehavior(rawValue: values.int("edge")) ?? .clamp
        return WarpRenderer(src: src, env: env, offset: values.point("offset"), quality: values.int("quality"), edge: edge) { u, v in
            let rad = sqrt(u * u + v * v)
            if rad > maxrad { return (u, v) }
            var theta = atan2(v, u)
            var t = 1 - rad / maxrad
            t = t < 0 ? 0 : t * t * t
            theta += t * twist / 100
            return (rad * cos(theta), rad * sin(theta))
        }
    }
}

public final class PolarInversionEffect: Effect {
    public override var name: String { "Polar Inversion" }
    public override var category: EffectCategory { .distort }
    public override var parameters: [EffectParameter] {
        warpParameters([.double(id: "amount", label: "Amount", range: -4...4, defaultValue: 1, decimals: 2)])
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let amount = values.double("amount")
        let b = env.selectionBounds
        let r = Double(min(b.width, b.height)) / 2
        let r2 = r * r
        let edge = WarpEdgeBehavior(rawValue: values.int("edge")) ?? .reflect
        return WarpRenderer(src: src, env: env, offset: values.point("offset"), quality: values.int("quality"), edge: edge) { x, y in
            let d = x * x + y * y
            if d < 1e-9 { return (x, y) }
            let inv = 1 + (r2 / d - 1) * amount
            return (x * inv, y * inv)
        }
    }
}

public final class TileReflectionEffect: Effect {
    public override var name: String { "Tile Reflection" }
    public override var category: EffectCategory { .distort }
    public override var parameters: [EffectParameter] {
        [
            .angle(id: "angle", label: "Angle", range: -180...180, defaultValue: 30),
            .integer(id: "tileSize", label: "Tile Size", range: 2...200, defaultValue: 40),
            .integer(id: "curvature", label: "Curvature", range: -100...100, defaultValue: 8),
            .integer(id: "quality", label: "Quality", range: 1...5, defaultValue: 2),
            .choice(id: "edge", label: "Edge Behavior", options: WarpEdgeBehavior.displayNames,
                    defaultValue: WarpEdgeBehavior.wrap.rawValue, radio: false),
        ]
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let r = values.double("angle") * Double.pi / 180
        let sinA = sin(r), cosA = cos(r)
        let tile = Double(values.int("tileSize"))
        let scale = Double.pi / tile
        let curvature = Double(values.int("curvature"))
        let edge = WarpEdgeBehavior(rawValue: values.int("edge")) ?? .wrap
        return WarpRenderer(src: src, env: env, offset: .zero, quality: values.int("quality"), edge: edge) { u, v in
            var s = cosA * u + sinA * v
            var t = -sinA * u + cosA * v
            s += curvature * tan(s * scale)
            t += curvature * tan(t * scale)
            return (cosA * s - sinA * t, sinA * s + cosA * t)
        }
    }
}

public final class DentsEffect: Effect {
    public override var name: String { "Dents" }
    public override var category: EffectCategory { .distort }
    public override var parameters: [EffectParameter] {
        warpParameters([
            .double(id: "scale", label: "Scale", range: 1...200, defaultValue: 25, decimals: 1),
            .double(id: "refraction", label: "Refraction", range: 0...200, defaultValue: 50, decimals: 1),
            .double(id: "roughness", label: "Roughness", range: 0...100, defaultValue: 10, decimals: 1),
            .double(id: "tension", label: "Tension", range: 0...100, defaultValue: 10, decimals: 1),
            .seed(id: "seed", label: "Random Noise"),
        ], offset: false)
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let scale = values.double("scale")
        let refraction = values.double("refraction")
        let roughness = values.double("roughness") / 100
        let tension = values.double("tension") / 10
        let seed = values.int("seed")
        let noise = PerlinNoise(seed: seed)
        let noise2 = PerlinNoise(seed: seed &+ 7919)
        let octaves = max(1, Int(2 + roughness * 6))
        let edge = WarpEdgeBehavior(rawValue: values.int("edge")) ?? .reflect
        return WarpRenderer(src: src, env: env, offset: .zero, quality: values.int("quality"), edge: edge) { x, y in
            let nx = x / scale, ny = y / scale
            var dx = noise.fbm(nx, ny, octaves: octaves, persistence: 0.5 + roughness * 0.4)
            var dy = noise2.fbm(nx, ny, octaves: octaves, persistence: 0.5 + roughness * 0.4)
            // Tension sharpens the dents.
            dx = tanh(dx * (1 + tension)) / tanh(1 + tension)
            dy = tanh(dy * (1 + tension)) / tanh(1 + tension)
            return (x + dx * refraction, y + dy * refraction)
        }
    }
}

public final class FrostedGlassEffect: Effect {
    public override var name: String { "Frosted Glass" }
    public override var category: EffectCategory { .distort }
    public override var parameters: [EffectParameter] {
        [
            .double(id: "maxScatter", label: "Maximum scatter radius", range: 0...200, defaultValue: 3, decimals: 2),
            .double(id: "minScatter", label: "Minimum scatter radius", range: 0...200, defaultValue: 0, decimals: 2),
            .integer(id: "smoothness", label: "Smoothness", range: 1...16, defaultValue: 2),
            .seed(id: "seed", label: "Random Noise"),
        ]
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let maxR = values.double("maxScatter"), minR = min(values.double("minScatter"), maxR)
        let smooth = values.int("smoothness")
        let seed = values.int("seed")
        return ClosureRenderer { dst, rect in
            let w = src.width, h = src.height
            for y in rect.top..<rect.bottom {
                let d = dst.row(y)
                for x in rect.left..<rect.right {
                    var rng = SeededRandom(seed: Int(truncatingIfNeeded: SeededRandom.hash(x, y, seed)))
                    var acc = SampleAccumulator()
                    for _ in 0..<smooth {
                        let a = rng.nextDouble() * 2 * Double.pi
                        let r = minR + (maxR - minR) * sqrt(rng.nextDouble())
                        let sx = clampInt(Int((Double(x) + cos(a) * r).rounded()), 0, w - 1)
                        let sy = clampInt(Int((Double(y) + sin(a) * r).rounded()), 0, h - 1)
                        acc.add(src[sx, sy])
                    }
                    d[x] = acc.color
                }
            }
        }
    }
}

public final class PixelateEffect: Effect {
    public override var name: String { "Pixelate" }
    public override var category: EffectCategory { .distort }
    public override var parameters: [EffectParameter] {
        [.integer(id: "cellSize", label: "Cell size", range: 1...100, defaultValue: 2)]
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let cell = values.int("cellSize")
        return ClosureRenderer { dst, rect in
            let w = src.width, h = src.height
            for y in rect.top..<rect.bottom {
                let d = dst.row(y)
                let cy0 = (y / cell) * cell
                let cy1 = min(h, cy0 + cell) - 1
                var x = rect.left
                while x < rect.right {
                    let cx0 = (x / cell) * cell
                    let cx1 = min(w, cx0 + cell) - 1
                    // Paint.NET averages the four corner pixels of each cell.
                    var acc = SampleAccumulator()
                    acc.add(src[cx0, cy0]); acc.add(src[cx1, cy0]); acc.add(src[cx0, cy1]); acc.add(src[cx1, cy1])
                    let c = acc.color
                    let end = min(rect.right, cx0 + cell)
                    while x < end {
                        d[x] = c
                        x += 1
                    }
                }
            }
        }
    }
}

// MARK: - Noise functions

/// Classic improved Perlin noise with a seeded permutation table.
public struct PerlinNoise {
    private let perm: [Int]

    public init(seed: Int) {
        var p = Array(0..<256)
        var rng = SeededRandom(seed: seed)
        for i in stride(from: 255, to: 0, by: -1) {
            let j = rng.nextInt(i + 1)
            p.swapAt(i, j)
        }
        perm = p + p
    }

    @inline(__always) private func fade(_ t: Double) -> Double { t * t * t * (t * (t * 6 - 15) + 10) }
    @inline(__always) private func lerp(_ t: Double, _ a: Double, _ b: Double) -> Double { a + t * (b - a) }
    @inline(__always) private func grad(_ hash: Int, _ x: Double, _ y: Double) -> Double {
        let h = hash & 7
        let u = h < 4 ? x : y
        let v = h < 4 ? y : x
        return ((h & 1) == 0 ? u : -u) + ((h & 2) == 0 ? 2 * v : -2 * v)
    }

    /// Noise in roughly [-1, 1].
    public func noise(_ x: Double, _ y: Double) -> Double {
        let fx = floor(x), fy = floor(y)
        let X = Int(fx) & 255, Y = Int(fy) & 255
        let xf = x - fx, yf = y - fy
        let u = fade(xf), v = fade(yf)
        let a = perm[X] + Y, b = perm[X + 1] + Y
        let res = lerp(v, lerp(u, grad(perm[a], xf, yf), grad(perm[b], xf - 1, yf)),
                       lerp(u, grad(perm[a + 1], xf, yf - 1), grad(perm[b + 1], xf - 1, yf - 1)))
        return res * 0.5
    }

    /// Fractal sum of octaves.
    public func fbm(_ x: Double, _ y: Double, octaves: Int, persistence: Double) -> Double {
        var total = 0.0, amp = 1.0, freq = 1.0, norm = 0.0
        for _ in 0..<octaves {
            total += noise(x * freq, y * freq) * amp
            norm += amp
            amp *= persistence
            freq *= 2
        }
        return norm > 0 ? total / norm : 0
    }
}
