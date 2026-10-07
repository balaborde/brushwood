import Foundation

// MARK: - Noise

public final class AddNoiseEffect: Effect {
    public override var name: String { "Add Noise" }
    public override var category: EffectCategory { .noise }
    public override var parameters: [EffectParameter] {
        [
            .integer(id: "intensity", label: "Intensity", range: 0...100, defaultValue: 64),
            .integer(id: "saturation", label: "Color Saturation", range: 0...400, defaultValue: 100),
            .double(id: "coverage", label: "Coverage", range: 0...100, defaultValue: 100, decimals: 2),
            .seed(id: "seed", label: "Random Noise"),
        ]
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let intensity = values.int("intensity")
        let dev = intensity * intensity / 4
        let sat = values.int("saturation") * 4096 / 100
        let coverage = values.double("coverage") * 0.01
        let seed = values.int("seed")
        return ClosureRenderer { dst, rect in
            for y in rect.top..<rect.bottom {
                let s = src.row(y), d = dst.row(y)
                for x in rect.left..<rect.right {
                    var rng = SeededRandom(seed: Int(truncatingIfNeeded: SeededRandom.hash(x, y, seed)))
                    if rng.nextDouble() > coverage {
                        d[x] = s[x]
                        continue
                    }
                    // Gaussian samples scaled like Paint.NET's lookup table (1 sigma = 4096).
                    var r = Int(rng.nextGaussian() * 4096)
                    var g = Int(rng.nextGaussian() * 4096)
                    var b = Int(rng.nextGaussian() * 4096)
                    let i = (4899 * r + 9618 * g + 1867 * b) >> 14
                    r = i + (((r - i) * sat) >> 12)
                    g = i + (((g - i) * sat) >> 12)
                    b = i + (((b - i) * sat) >> 12)
                    let c = s[x]
                    d[x] = ColorBgra(b: clampToByte(Int(c.b) + ((b * dev + 32768) >> 16)),
                                     g: clampToByte(Int(c.g) + ((g * dev + 32768) >> 16)),
                                     r: clampToByte(Int(c.r) + ((r * dev + 32768) >> 16)), a: c.a)
                }
            }
        }
    }
}

public final class MedianEffect: Effect {
    public override var name: String { "Median" }
    public override var category: EffectCategory { .noise }
    public override var parameters: [EffectParameter] {
        [
            .integer(id: "radius", label: "Radius", range: 1...200, defaultValue: 10),
            .integer(id: "percentile", label: "Percentile", range: 0...100, defaultValue: 50),
        ]
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let radius = values.int("radius"), pct = values.int("percentile")
        return ClosureRenderer(wholeRegion: true) { dst, rect in
            LocalHistogram.run(src: src, dst: dst, rect: rect, radius: radius) { _, area, hb, hg, hr, ha in
                LocalHistogram.percentile(pct, area: area, hb, hg, hr, ha)
            }
        }
    }
}

public final class ReduceNoiseEffect: Effect {
    public override var name: String { "Reduce Noise" }
    public override var category: EffectCategory { .noise }
    public override var parameters: [EffectParameter] {
        [
            .integer(id: "radius", label: "Radius", range: 0...200, defaultValue: 6),
            .double(id: "strength", label: "Strength", range: 0...1, defaultValue: 0.4, decimals: 2),
        ]
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let radius = values.int("radius"), strength = values.double("strength")
        return ClosureRenderer(wholeRegion: true) { dst, rect in
            LocalHistogram.run(src: src, dst: dst, rect: rect, radius: radius) { c, area, hb, hg, hr, _ in
                var rc = 0, gc = 0, bc = 0
                for i in 0..<Int(c.r) { rc += Int(hr[i]) }
                for i in 0..<Int(c.g) { gc += Int(hg[i]) }
                for i in 0..<Int(c.b) { bc += Int(hb[i]) }
                let a = max(1, area)
                let normalized = ColorBgra(b: clampToByte(bc * 255 / a), g: clampToByte(gc * 255 / a),
                                           r: clampToByte(rc * 255 / a), a: c.a)
                let lerp = strength * (1 - 0.75 * c.intensity)
                return ColorBgra.lerp(c, normalized, lerp)
            }
        }
    }
}

// MARK: - Stylize

/// 3×3 directional kernels shared by Edge Detect / Relief (Paint.NET's `ColorDifferenceEffect`).
enum ColorDifference {
    static func weights(angleDegrees: Double) -> [[Double]] {
        let r = angleDegrees * Double.pi / 180
        let dr = Double.pi / 4
        return [
            [cos(r + dr), cos(r + 2 * dr), cos(r + 3 * dr)],
            [cos(r), 0, cos(r + 4 * dr)],
            [cos(r - dr), cos(r - 2 * dr), cos(r - 3 * dr)],
        ]
    }

    static func render(src: Surface, dst: Surface, rect: IntRect, weights: [[Double]], offset: Double, keepAlpha: Bool) {
        let w = src.width, h = src.height
        for y in rect.top..<rect.bottom {
            let d = dst.row(y)
            for x in rect.left..<rect.right {
                var rs = 0.0, gs = 0.0, bs = 0.0
                for fy in 0..<3 {
                    let yy = y - 1 + fy
                    if yy < 0 || yy >= h { continue }
                    let row = src.row(yy)
                    for fx in 0..<3 {
                        let xx = x - 1 + fx
                        if xx < 0 || xx >= w { continue }
                        let wt = weights[fy][fx]
                        let c = row[xx]
                        rs += wt * Double(c.r)
                        gs += wt * Double(c.g)
                        bs += wt * Double(c.b)
                    }
                }
                let a = keepAlpha ? src[x, y].a : 255
                d[x] = ColorBgra(b: clampToByte(Int(bs + offset)), g: clampToByte(Int(gs + offset)),
                                 r: clampToByte(Int(rs + offset)), a: a)
            }
        }
    }
}

public final class EdgeDetectEffect: Effect {
    public override var name: String { "Edge Detect" }
    public override var category: EffectCategory { .stylize }
    public override var parameters: [EffectParameter] {
        [.angle(id: "angle", label: "Angle", range: -180...180, defaultValue: 45)]
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let w = ColorDifference.weights(angleDegrees: values.double("angle"))
        return ClosureRenderer { dst, rect in
            ColorDifference.render(src: src, dst: dst, rect: rect, weights: w, offset: 128, keepAlpha: true)
        }
    }
}

public final class ReliefEffect: Effect {
    public override var name: String { "Relief" }
    public override var category: EffectCategory { .stylize }
    public override var parameters: [EffectParameter] {
        [.angle(id: "angle", label: "Angle", range: -180...180, defaultValue: 45)]
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        var w = ColorDifference.weights(angleDegrees: values.double("angle"))
        w[1][1] = 1
        return ClosureRenderer { dst, rect in
            ColorDifference.render(src: src, dst: dst, rect: rect, weights: w, offset: 0, keepAlpha: true)
        }
    }
}

public final class EmbossEffect: Effect {
    public override var name: String { "Emboss" }
    public override var category: EffectCategory { .stylize }
    public override var parameters: [EffectParameter] {
        [.angle(id: "angle", label: "Angle", range: 0...360, defaultValue: 0)]
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let wts = ColorDifference.weights(angleDegrees: values.double("angle"))
        return ClosureRenderer { dst, rect in
            let w = src.width, h = src.height
            for y in rect.top..<rect.bottom {
                let d = dst.row(y)
                for x in rect.left..<rect.right {
                    var sum = 0.0
                    for fy in 0..<3 {
                        let yy = clampInt(y - 1 + fy, 0, h - 1)
                        for fx in 0..<3 {
                            let xx = clampInt(x - 1 + fx, 0, w - 1)
                            sum += wts[fy][fx] * Double(src[xx, yy].intensityByte)
                        }
                    }
                    let v = clampToByte(Int(sum + 128))
                    d[x] = ColorBgra(b: v, g: v, r: v, a: src[x, y].a)
                }
            }
        }
    }
}

public final class OutlineEffect: Effect {
    public override var name: String { "Outline" }
    public override var category: EffectCategory { .stylize }
    public override var parameters: [EffectParameter] {
        [
            .integer(id: "thickness", label: "Thickness", range: 1...200, defaultValue: 3),
            .integer(id: "intensity", label: "Intensity", range: 0...100, defaultValue: 50),
        ]
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let thickness = values.int("thickness"), intensity = values.int("intensity")
        return ClosureRenderer(wholeRegion: true) { dst, rect in
            LocalHistogram.run(src: src, dst: dst, rect: rect, radius: thickness) { _, area, hb, hg, hr, ha in
                let minCount1 = Int32(area * (100 - intensity) / 200)
                let minCount2 = Int32(area * (100 + intensity) / 200)
                @inline(__always) func span(_ hist: UnsafeMutablePointer<Int32>) -> (Int, Int) {
                    var count: Int32 = 0
                    var v1 = 0
                    while v1 < 255 && hist[v1] == 0 { v1 += 1 }
                    while v1 < 255 && count < minCount1 {
                        count += hist[v1]
                        v1 += 1
                    }
                    var v2 = v1
                    while v2 < 255 && count < minCount2 {
                        count += hist[v2]
                        v2 += 1
                    }
                    return (v1, v2)
                }
                let (b1, b2) = span(hb), (g1, g2) = span(hg), (r1, r2) = span(hr), (_, a2) = span(ha)
                return ColorBgra(b: UInt8(255 - (b2 - b1)), g: UInt8(255 - (g2 - g1)), r: UInt8(255 - (r2 - r1)),
                                 a: UInt8(a2))
            }
        }
    }
}

// MARK: - Photo

public final class SharpenEffect: Effect {
    public override var name: String { "Sharpen" }
    public override var category: EffectCategory { .photo }
    public override var parameters: [EffectParameter] {
        [.integer(id: "amount", label: "Amount", range: 1...20, defaultValue: 10)]
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let amount = values.int("amount")
        return ClosureRenderer(wholeRegion: true) { dst, rect in
            LocalHistogram.run(src: src, dst: dst, rect: rect, radius: amount) { c, area, hb, hg, hr, ha in
                let median = LocalHistogram.percentile(50, area: area, hb, hg, hr, ha)
                // ColorBgra.Lerp(src, median, -0.5)
                return ColorBgra(b: clampToByte(Int(c.b) + (Int(c.b) - Int(median.b)) / 2),
                                 g: clampToByte(Int(c.g) + (Int(c.g) - Int(median.g)) / 2),
                                 r: clampToByte(Int(c.r) + (Int(c.r) - Int(median.r)) / 2),
                                 a: clampToByte(Int(c.a) + (Int(c.a) - Int(median.a)) / 2))
            }
        }
    }
}

public final class GlowEffect: Effect {
    public override var name: String { "Glow" }
    public override var category: EffectCategory { .photo }
    public override var parameters: [EffectParameter] {
        [
            .integer(id: "radius", label: "Radius", range: 1...20, defaultValue: 6),
            .integer(id: "brightness", label: "Brightness", range: -100...100, defaultValue: 10),
            .integer(id: "contrast", label: "Contrast", range: -100...100, defaultValue: 10),
        ]
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let radius = values.int("radius")
        let bac = BrightnessContrastAdjustment.makeOp(brightness: values.int("brightness"), contrast: values.int("contrast"))
        return ClosureRenderer(wholeRegion: true) { dst, rect in
            EffectHelpers.gaussianBlur(src: src, dst: dst, rect: rect, radius: radius)
            EffectHelpers.parallelRows(rect) { y in
                let s = src.row(y), d = dst.row(y)
                for x in rect.left..<rect.right {
                    let adjusted = bac(d[x])
                    let c = s[x]
                    d[x] = ColorBgra(b: UInt8(255 - mul255(255 - Int(c.b), 255 - Int(adjusted.b))),
                                     g: UInt8(255 - mul255(255 - Int(c.g), 255 - Int(adjusted.g))),
                                     r: UInt8(255 - mul255(255 - Int(c.r), 255 - Int(adjusted.r))), a: c.a)
                }
            }
        }
    }
}

public final class RedEyeRemovalEffect: Effect {
    public override var name: String { "Red Eye Removal" }
    public override var category: EffectCategory { .photo }
    public override var requiresSelectionHint: String? {
        "Hint: For best results, first use the selection tools to select each eye."
    }
    public override var parameters: [EffectParameter] {
        [
            .integer(id: "tolerance", label: "Tolerance", range: 0...100, defaultValue: 70),
            .integer(id: "saturation", label: "Saturation percentage", range: 0...100, defaultValue: 90),
        ]
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let tolerance = 100 - values.int("tolerance")
        let setSaturation = Double(values.int("saturation")) / 100
        return PixelOpRenderer(src: src) { c in
            let r = Double(c.r) / 255, g = Double(c.g) / 255, b = Double(c.b) / 255
            let mx = max(r, g, b), mn = min(r, g, b)
            let s = (mx == 0 || mx == mn) ? 0 : (mx - mn) / mx
            let saturation = Int(s * 255)
            let difference = Int(c.r) - Int(max(c.b, c.g))
            if difference > tolerance && saturation > 100 {
                let i = 255 * c.intensity
                return ColorBgra(b: c.b, g: c.g, r: clampToByte(i * setSaturation), a: c.a)
            }
            return c
        }
    }
}

public final class SoftenPortraitEffect: Effect {
    public override var name: String { "Soften Portrait" }
    public override var category: EffectCategory { .photo }
    public override var parameters: [EffectParameter] {
        [
            .integer(id: "softness", label: "Softness", range: 0...10, defaultValue: 5),
            .integer(id: "lighting", label: "Lighting", range: -20...20, defaultValue: 0),
            .integer(id: "warmth", label: "Warmth", range: 0...20, defaultValue: 10),
        ]
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let softness = values.int("softness"), lighting = values.int("lighting"), warmth = values.int("warmth")
        let bac = BrightnessContrastAdjustment.makeOp(brightness: lighting, contrast: -lighting / 2)
        let redAdjust = 1.0 + Double(warmth) / 100, blueAdjust = 1.0 - Double(warmth) / 100
        return ClosureRenderer(wholeRegion: true) { dst, rect in
            EffectHelpers.gaussianBlur(src: src, dst: dst, rect: rect, radius: softness)
            EffectHelpers.parallelRows(rect) { y in
                let s = src.row(y), d = dst.row(y)
                for x in rect.left..<rect.right {
                    let blurred = bac(d[x])
                    let c = s[x]
                    let i = c.intensityByte
                    let grey = ColorBgra(b: clampToByte(Double(i) * blueAdjust), g: i,
                                         r: clampToByte(Double(i) * redAdjust), a: 255)
                    var out = Blender.blend(.overlay, grey, blurred.withAlpha(255))
                    out.a = c.a
                    d[x] = out
                }
            }
        }
    }
}

public final class VignetteEffect: Effect {
    public override var name: String { "Vignette" }
    public override var category: EffectCategory { .photo }
    public override var parameters: [EffectParameter] {
        [
            .offset(id: "center", label: "Center", defaultValue: .zero),
            .double(id: "radius", label: "Radius", range: 0.1...4, defaultValue: 0.5, decimals: 2),
            .double(id: "density", label: "Density", range: 0...1, defaultValue: 1, decimals: 2),
        ]
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let b = env.selectionBounds
        let off = values.point("center")
        let cx = Double(b.x) + Double(b.width) * (0.5 + Double(off.x) / 2)
        let cy = Double(b.y) + Double(b.height) * (0.5 + Double(off.y) / 2)
        let radius = values.double("radius") * Double(max(b.width, b.height))
        let density = values.double("density")
        return ClosureRenderer { dst, rect in
            for y in rect.top..<rect.bottom {
                let s = src.row(y), d = dst.row(y)
                for x in rect.left..<rect.right {
                    let dx = Double(x) + 0.5 - cx, dy = Double(y) + 0.5 - cy
                    let dist = sqrt(dx * dx + dy * dy) / max(1, radius)
                    // cos⁴ falloff like a real lens vignette.
                    let t = min(Double.pi / 2, dist * Double.pi / 2)
                    let c4 = pow(cos(t), 4)
                    let f = 1 - density * (1 - c4)
                    let c = s[x]
                    d[x] = ColorBgra(b: clampToByte(Double(c.b) * f), g: clampToByte(Double(c.g) * f),
                                     r: clampToByte(Double(c.r) * f), a: c.a)
                }
            }
        }
    }
}
