import CoreGraphics
import Foundation

// MARK: - Artistic

public final class OilPaintingEffect: Effect {
    public override var name: String { "Oil Painting" }
    public override var category: EffectCategory { .artistic }
    public override var parameters: [EffectParameter] {
        [
            .integer(id: "brushSize", label: "Brush size", range: 1...8, defaultValue: 3),
            .integer(id: "coarseness", label: "Coarseness", range: 3...255, defaultValue: 50),
        ]
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let size = values.int("brushSize"), levels = values.int("coarseness")
        return ClosureRenderer { dst, rect in
            let w = src.width, h = src.height
            var count = [Int](repeating: 0, count: levels)
            var sr = [Int](repeating: 0, count: levels), sg = sr, sb = sr, sa = sr
            for y in rect.top..<rect.bottom {
                let d = dst.row(y)
                let y0 = max(0, y - size), y1 = min(h - 1, y + size)
                for x in rect.left..<rect.right {
                    for i in 0..<levels { count[i] = 0; sr[i] = 0; sg[i] = 0; sb[i] = 0; sa[i] = 0 }
                    let x0 = max(0, x - size), x1 = min(w - 1, x + size)
                    for yy in y0...y1 {
                        let row = src.row(yy)
                        for xx in x0...x1 {
                            let c = row[xx]
                            let bin = Int(c.intensityByte) * (levels - 1) / 255
                            count[bin] += 1
                            sr[bin] += Int(c.r); sg[bin] += Int(c.g); sb[bin] += Int(c.b); sa[bin] += Int(c.a)
                        }
                    }
                    var best = 0
                    for i in 1..<levels where count[i] > count[best] { best = i }
                    let n = max(1, count[best])
                    d[x] = ColorBgra(b: UInt8(sb[best] / n), g: UInt8(sg[best] / n), r: UInt8(sr[best] / n), a: UInt8(sa[best] / n))
                }
            }
        }
    }
}

public final class PencilSketchEffect: Effect {
    public override var name: String { "Pencil Sketch" }
    public override var category: EffectCategory { .artistic }
    public override var parameters: [EffectParameter] {
        [
            .integer(id: "tipSize", label: "Pencil tip size", range: 1...20, defaultValue: 2),
            .integer(id: "colorRange", label: "Color range", range: -20...20, defaultValue: 0),
        ]
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let tip = values.int("tipSize"), range = values.int("colorRange")
        let bac = BrightnessContrastAdjustment.makeOp(brightness: range, contrast: -range)
        return ClosureRenderer(wholeRegion: true) { dst, rect in
            EffectHelpers.gaussianBlur(src: src, dst: dst, rect: rect, radius: tip)
            EffectHelpers.parallelRows(rect) { y in
                let s = src.row(y), d = dst.row(y)
                for x in rect.left..<rect.right {
                    var blurred = bac(d[x])
                    blurred = ColorBgra(b: 255 - blurred.b, g: 255 - blurred.g, r: 255 - blurred.r, a: 255)
                    let bi = Int(blurred.intensityByte)
                    let gi = Int(s[x].intensityByte)
                    // Color dodge of the grey source with the inverted blurred copy.
                    let v = bi == 255 ? 255 : min(255, gi * 255 / (255 - bi))
                    d[x] = ColorBgra(b: UInt8(v), g: UInt8(v), r: UInt8(v), a: s[x].a)
                }
            }
        }
    }
}

public final class InkSketchEffect: Effect {
    public override var name: String { "Ink Sketch" }
    public override var category: EffectCategory { .artistic }
    public override var parameters: [EffectParameter] {
        [
            .integer(id: "ink", label: "Ink outline", range: 0...99, defaultValue: 50),
            .integer(id: "coloring", label: "Coloring", range: 0...100, defaultValue: 50),
        ]
    }

    static let kernel: [[Int]] = [
        [-1, -1, -1, -1, -1],
        [-1, -1, -1, -1, -1],
        [-1, -1, 30, -1, -1],
        [-1, -1, -1, -1, -1],
        [-1, -1, -5, -1, -1],
    ]

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let ink = values.int("ink"), coloring = values.int("coloring")
        let glowBC = BrightnessContrastAdjustment.makeOp(brightness: -(coloring - 50) * 2, contrast: -(coloring - 50) * 2)
        return ClosureRenderer(wholeRegion: true) { dst, rect in
            // Glow pass gives the soft colored base.
            EffectHelpers.gaussianBlur(src: src, dst: dst, rect: rect, radius: 6)
            let w = src.width, h = src.height
            EffectHelpers.parallelRows(rect) { y in
                let d = dst.row(y)
                for x in rect.left..<rect.right {
                    let c = src[x, y]
                    let adj = glowBC(d[x])
                    let glow = ColorBgra(b: UInt8(255 - mul255(255 - Int(c.b), 255 - Int(adj.b))),
                                         g: UInt8(255 - mul255(255 - Int(c.g), 255 - Int(adj.g))),
                                         r: UInt8(255 - mul255(255 - Int(c.r), 255 - Int(adj.r))), a: c.a)
                    var sum = 0
                    for ky in 0..<5 {
                        let yy = clampInt(y + ky - 2, 0, h - 1)
                        for kx in 0..<5 {
                            let xx = clampInt(x + kx - 2, 0, w - 1)
                            sum += InkSketchEffect.kernel[ky][kx] * Int(src[xx, yy].intensityByte)
                        }
                    }
                    // Strong negative response = dark line. Ink amount scales the threshold.
                    let edge = clampInt(-sum, 0, 255)
                    let threshold = 255 - ink * 255 / 100
                    let inkAlpha = edge > threshold / 2 ? min(255, (edge - threshold / 2) * 4) : 0
                    let base = ColorBgra.lerp(.white, glow.withAlpha(255), Double(coloring) / 100 + 0.25)
                    var out = Blender.lerpTo(base, .black, coverage: inkAlpha)
                    out.a = c.a
                    d[x] = out
                }
            }
        }
    }
}

// MARK: - Render

public final class CloudsEffect: Effect {
    public override var name: String { "Clouds" }
    public override var category: EffectCategory { .render }
    public override var parameters: [EffectParameter] {
        [
            .choice(id: "blendMode", label: "Blend mode", options: BlendMode.allCases.map(\.displayName),
                    defaultValue: BlendMode.normal.rawValue, radio: false),
            .integer(id: "scale", label: "Scale", range: 2...1000, defaultValue: 250),
            .double(id: "power", label: "Roughness", range: 0...1, defaultValue: 0.5, decimals: 2),
            .seed(id: "seed", label: "Seed"),
        ]
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let scale = Double(values.int("scale")), power = values.double("power")
        let mode = BlendMode(rawValue: values.int("blendMode")) ?? .normal
        let noise = PerlinNoise(seed: values.int("seed"))
        var octaves = 0
        var s = Int(scale)
        while s > 1 { octaves += 1; s /= 2 }
        octaves = max(1, octaves)
        let from = env.primaryColor, to = env.secondaryColor
        return ClosureRenderer { dst, rect in
            for y in rect.top..<rect.bottom {
                let d = dst.row(y), sr = src.row(y)
                for x in rect.left..<rect.right {
                    var val = 0.0, amp = 1.0, freq = 1.0 / scale
                    for _ in 0..<octaves {
                        val += noise.noise(Double(x) * freq, Double(y) * freq) * amp
                        amp *= power
                        freq *= 2
                    }
                    let t = clampDouble((val + 1) / 2, 0, 1)
                    let c = ColorBgra.lerp(from, to, t)
                    d[x] = Blender.blend(mode, sr[x], c)
                }
            }
        }
    }
}

public final class JuliaFractalEffect: Effect {
    public override var name: String { "Julia Fractal" }
    public override var category: EffectCategory { .render }
    public override var parameters: [EffectParameter] {
        [
            .double(id: "factor", label: "Factor", range: 1...10, defaultValue: 4, decimals: 2),
            .integer(id: "quality", label: "Quality", range: 1...5, defaultValue: 2),
            .double(id: "zoom", label: "Zoom", range: 0...50, defaultValue: 1, decimals: 2),
            .angle(id: "angle", label: "Angle", range: -180...180, defaultValue: 0),
        ]
    }

    static func julia(_ x0: Double, _ y0: Double, _ r: Double, _ i: Double) -> Double {
        var x = x0, y = y0, c = 0.0
        while c < 256 && x * x + y * y < 10000 {
            let t = x
            x = x * x - y * y + r
            y = 2 * t * y + i
            c += 1
        }
        return c - (2 - 2 * log(max(1e-9, x * x + y * y)) / log(10000.0))
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let factor = values.double("factor"), quality = values.int("quality")
        let zoom = max(0.0001, values.double("zoom")), angle = values.double("angle") * Double.pi / 180
        let b = env.selectionBounds
        let w = Double(b.width), h = Double(b.height)
        let invH = 1 / h, invZoom = 1 / zoom, invQuality = 1 / Double(quality)
        let count = quality * quality + 1
        let invCount = 1 / Double(count)
        let aspect = h / w
        return ClosureRenderer { dst, rect in
            for y in rect.top..<rect.bottom {
                let d = dst.row(y)
                for x in rect.left..<rect.right {
                    var r = 0, g = 0, bl = 0, a = 0
                    let fx = Double(x - b.x), fy = Double(y - b.y)
                    for i in 0..<count {
                        let di = Double(i)
                        let u = (2 * fx - w + di * invCount) * invH
                        let v = (2 * fy - h + (di * invQuality).truncatingRemainder(dividingBy: 1)) * invH
                        let radius = sqrt(u * u + v * v)
                        let theta = atan2(v, u) + angle
                        let uP = radius * cos(theta), vP = radius * sin(theta)
                        let jX = (uP - vP * aspect) * invZoom
                        let jY = (vP + uP * aspect) * invZoom
                        let j = JuliaFractalEffect.julia(jX, jY, 0.3125, 0.03125)
                        let c = Int(factor * j)
                        bl += Int(clampToByte(c - 768))
                        g += Int(clampToByte(c - 512))
                        r += Int(clampToByte(c - 256))
                        a += Int(clampToByte(c))
                    }
                    d[x] = ColorBgra(b: UInt8(bl / count), g: UInt8(g / count), r: UInt8(r / count), a: UInt8(a / count))
                }
            }
        }
    }
}

public final class MandelbrotFractalEffect: Effect {
    public override var name: String { "Mandelbrot Fractal" }
    public override var category: EffectCategory { .render }
    public override var parameters: [EffectParameter] {
        [
            .integer(id: "factor", label: "Factor", range: 1...10, defaultValue: 1),
            .integer(id: "quality", label: "Quality", range: 1...5, defaultValue: 2),
            .integer(id: "zoom", label: "Zoom", range: 0...50, defaultValue: 10),
            .angle(id: "angle", label: "Angle", range: -180...180, defaultValue: 0),
            .checkbox(id: "invert", label: "Invert Colors", defaultValue: false),
        ]
    }

    static func mandelbrot(_ r: Double, _ i: Double, factor: Double) -> Double {
        var c = 0, x = 0.0, y = 0.0
        while c < 1024 && x * x + y * y < 4 {
            let t = x
            x = x * x - y * y + r
            y = 2 * t * y + i
            c += 1
        }
        return Double(c) - log(y * y + x * x + 1e-12) * (1 / log(factor + 1.5))
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let factor = Double(values.int("factor")), quality = values.int("quality")
        let zoom = Double(values.int("zoom")) + 1
        let angle = values.double("angle") * Double.pi / 180
        let invert = values.bool("invert")
        let b = env.selectionBounds
        let w = Double(b.width), h = Double(b.height)
        let count = quality * quality + 1
        let invCount = 1 / Double(count)
        let invH = 1 / h, invZoom = 1 / zoom, invQuality = 1 / Double(quality)
        return ClosureRenderer { dst, rect in
            for y in rect.top..<rect.bottom {
                let d = dst.row(y)
                for x in rect.left..<rect.right {
                    var r = 0, g = 0, bl = 0, a = 0
                    let fx = Double(x - b.x), fy = Double(y - b.y)
                    for i in 0..<count {
                        let di = Double(i)
                        let u = (2 * fx - w + di * invCount) * invH
                        let v = (2 * fy - h + (di * invQuality).truncatingRemainder(dividingBy: 1)) * invH
                        let radius = sqrt(u * u + v * v)
                        let theta = atan2(v, u) + angle
                        let uP = radius * cos(theta) * invZoom * 1.5 - 0.6, vP = radius * sin(theta) * invZoom * 1.5
                        let m = MandelbrotFractalEffect.mandelbrot(uP, vP, factor: factor)
                        let c = Int(64 + factor * m)
                        r += Int(clampToByte(c - 768))
                        g += Int(clampToByte(c - 512))
                        bl += Int(clampToByte(c - 256))
                        a += Int(clampToByte(c))
                    }
                    var col = ColorBgra(b: UInt8(bl / count), g: UInt8(g / count), r: UInt8(r / count), a: UInt8(a / count))
                    if invert { col = ColorBgra(b: 255 - col.b, g: 255 - col.g, r: 255 - col.r, a: col.a) }
                    d[x] = col
                }
            }
        }
    }
}

public final class VoronoiEffect: Effect {
    public override var name: String { "Voronoi Diagram" }
    public override var category: EffectCategory { .render }
    public override var parameters: [EffectParameter] {
        [
            .integer(id: "cells", label: "Number of cells", range: 2...1000, defaultValue: 100),
            .choice(id: "distance", label: "Distance metric", options: ["Euclidean", "Manhattan", "Chebyshev"],
                    defaultValue: 0, radio: false),
            .checkbox(id: "showPoints", label: "Show points", defaultValue: false),
            .seed(id: "seed", label: "Random positions and colors"),
        ]
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let n = values.int("cells"), metric = values.int("distance"), show = values.bool("showPoints")
        var rng = SeededRandom(seed: values.int("seed"))
        let b = env.selectionBounds
        var pts: [(Double, Double, ColorBgra)] = []
        for _ in 0..<n {
            let c = HsvColor(hue: rng.nextDouble() * 360, saturation: 40 + rng.nextDouble() * 60,
                             value: 50 + rng.nextDouble() * 50).toColor()
            pts.append((Double(b.x) + rng.nextDouble() * Double(b.width), Double(b.y) + rng.nextDouble() * Double(b.height), c))
        }
        return ClosureRenderer { dst, rect in
            for y in rect.top..<rect.bottom {
                let d = dst.row(y)
                for x in rect.left..<rect.right {
                    var best = Double.greatestFiniteMagnitude, bestC = ColorBgra.black
                    let px = Double(x) + 0.5, py = Double(y) + 0.5
                    for p in pts {
                        let dx = abs(p.0 - px), dy = abs(p.1 - py)
                        let dist: Double
                        switch metric {
                        case 1: dist = dx + dy
                        case 2: dist = max(dx, dy)
                        default: dist = dx * dx + dy * dy
                        }
                        if dist < best { best = dist; bestC = p.2 }
                    }
                    if show && (metric == 0 ? best < 4 : best < 2) { bestC = .black }
                    d[x] = bestC
                }
            }
        }
    }
}

// MARK: - Object (Paint.NET 5)

/// Euclidean distance transform (squared), Felzenszwalb & Huttenlocher.
enum DistanceTransform {
    static func edt1d(_ f: UnsafeMutablePointer<Double>, _ n: Int, _ d: UnsafeMutablePointer<Double>,
                      _ v: UnsafeMutablePointer<Int>, _ z: UnsafeMutablePointer<Double>) {
        var k = 0
        v[0] = 0
        z[0] = -Double.infinity
        z[1] = Double.infinity
        if n > 1 {
            for q in 1..<n {
                var s = ((f[q] + Double(q * q)) - (f[v[k]] + Double(v[k] * v[k]))) / Double(2 * q - 2 * v[k])
                while s <= z[k] {
                    k -= 1
                    s = ((f[q] + Double(q * q)) - (f[v[k]] + Double(v[k] * v[k]))) / Double(2 * q - 2 * v[k])
                }
                k += 1
                v[k] = q
                z[k] = s
                z[k + 1] = Double.infinity
            }
        }
        k = 0
        for q in 0..<n {
            while z[k + 1] < Double(q) { k += 1 }
            let dq = Double(q - v[k])
            d[q] = dq * dq + f[v[k]]
        }
    }

    /// Squared distance from each pixel to the nearest "inside" pixel.
    static func squaredDistances(width w: Int, height h: Int, inside: (Int, Int) -> Bool) -> [Double] {
        let inf = 1e20
        var grid = [Double](repeating: inf, count: w * h)
        for y in 0..<h { for x in 0..<w where inside(x, y) { grid[y * w + x] = 0 } }
        let n = max(w, h)
        let f = UnsafeMutablePointer<Double>.allocate(capacity: n)
        let d = UnsafeMutablePointer<Double>.allocate(capacity: n)
        let v = UnsafeMutablePointer<Int>.allocate(capacity: n)
        let z = UnsafeMutablePointer<Double>.allocate(capacity: n + 1)
        defer { f.deallocate(); d.deallocate(); v.deallocate(); z.deallocate() }
        for x in 0..<w {
            for y in 0..<h { f[y] = grid[y * w + x] }
            edt1d(f, h, d, v, z)
            for y in 0..<h { grid[y * w + x] = d[y] }
        }
        for y in 0..<h {
            for x in 0..<w { f[x] = grid[y * w + x] }
            edt1d(f, w, d, v, z)
            for x in 0..<w { grid[y * w + x] = d[x] }
        }
        return grid
    }
}

public final class DropShadowEffect: Effect {
    public override var name: String { "Drop Shadow" }
    public override var category: EffectCategory { .object }
    public override var parameters: [EffectParameter] {
        [
            .offset(id: "offset", label: "Offset", defaultValue: CGPoint(x: 0.05, y: 0.05)),
            .integer(id: "blur", label: "Blur radius", range: 0...100, defaultValue: 5),
            .integer(id: "opacity", label: "Opacity", range: 0...255, defaultValue: 128),
            .color(id: "color", label: "Color", defaultValue: .black),
            .checkbox(id: "shadowOnly", label: "Shadow only", defaultValue: false),
        ]
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let off = values.point("offset")
        let b = env.selectionBounds
        let ox = Int((Double(off.x) * Double(b.width) / 2).rounded())
        let oy = Int((Double(off.y) * Double(b.height) / 2).rounded())
        let blur = values.int("blur"), opacity = values.int("opacity")
        let color = values.color("color"), shadowOnly = values.bool("shadowOnly")
        return ClosureRenderer(wholeRegion: true) { dst, rect in
            // Shifted alpha in a scratch surface, then blurred.
            let shadowSrc = Surface(width: src.width, height: src.height)
            EffectHelpers.parallelRows(src.bounds) { y in
                let sy = y - oy
                let d = shadowSrc.row(y)
                guard sy >= 0 && sy < src.height else { return }
                let s = src.row(sy)
                for x in 0..<src.width {
                    let sx = x - ox
                    if sx >= 0 && sx < src.width { d[x] = color.withAlpha(UInt8(mul255(Int(s[sx].a), opacity))) }
                }
            }
            let blurred = Surface(width: src.width, height: src.height)
            EffectHelpers.gaussianBlur(src: shadowSrc, dst: blurred, rect: rect, radius: blur)
            EffectHelpers.parallelRows(rect) { y in
                let d = dst.row(y), s = src.row(y), sh = blurred.row(y)
                for x in rect.left..<rect.right {
                    let shadow = color.withAlpha(sh[x].a)
                    d[x] = shadowOnly ? shadow : Blender.blend(.normal, shadow, s[x])
                }
            }
        }
    }
}

public final class FeatherEffect: Effect {
    public override var name: String { "Feather" }
    public override var category: EffectCategory { .object }
    public override var parameters: [EffectParameter] {
        [.integer(id: "radius", label: "Radius", range: 1...100, defaultValue: 4)]
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let radius = values.int("radius")
        return ClosureRenderer(wholeRegion: true) { dst, rect in
            let dist = DistanceTransform.squaredDistances(width: src.width, height: src.height) { x, y in src[x, y].a < 128 }
            EffectHelpers.parallelRows(rect) { y in
                let d = dst.row(y), s = src.row(y)
                for x in rect.left..<rect.right {
                    let c = s[x]
                    let dd = sqrt(dist[y * src.width + x])
                    let f = min(1, dd / Double(radius))
                    d[x] = c.withAlpha(clampToByte(Double(c.a) * f * f * (3 - 2 * f)))
                }
            }
        }
    }
}

public final class OutlineObjectEffect: Effect {
    public override var name: String { "Outline Object" }
    public override var category: EffectCategory { .object }
    public override var parameters: [EffectParameter] {
        [
            .integer(id: "thickness", label: "Thickness", range: 1...100, defaultValue: 3),
            .integer(id: "softness", label: "Softness", range: 0...100, defaultValue: 50),
            .color(id: "color", label: "Color", defaultValue: .black),
        ]
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let thickness = Double(values.int("thickness")), softness = Double(values.int("softness")) / 100
        let color = values.color("color")
        return ClosureRenderer(wholeRegion: true) { dst, rect in
            let dist = DistanceTransform.squaredDistances(width: src.width, height: src.height) { x, y in src[x, y].a >= 128 }
            let edge = max(0.5, softness * thickness)
            EffectHelpers.parallelRows(rect) { y in
                let d = dst.row(y), s = src.row(y)
                for x in rect.left..<rect.right {
                    let dd = sqrt(dist[y * src.width + x])
                    var a = 1.0
                    if dd > thickness - edge { a = max(0, 1 - (dd - (thickness - edge)) / edge) }
                    let outline = color.withAlpha(clampToByte(a * Double(color.a)))
                    d[x] = Blender.blend(.normal, outline, s[x])
                }
            }
        }
    }
}
