import CoreGraphics
import Foundation

// MARK: - Simple pixel adjustments

public final class InvertColorsAdjustment: Effect {
    public override var name: String { "Invert Colors" }
    public override var shortcut: String? { "⇧⌘I" }
    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        PixelOpRenderer(src: src) { c in ColorBgra(b: 255 - c.b, g: 255 - c.g, r: 255 - c.r, a: c.a) }
    }
}

public final class BlackAndWhiteAdjustment: Effect {
    public override var name: String { "Black and White" }
    public override var shortcut: String? { "⇧⌘G" }
    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        PixelOpRenderer(src: src) { c in
            let i = c.intensityByte
            return ColorBgra(b: i, g: i, r: i, a: c.a)
        }
    }
}

public final class SepiaAdjustment: Effect {
    public override var name: String { "Sepia" }
    public override var shortcut: String? { "⇧⌘E" }
    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        // Desaturate, then Level(black, white, gamma {B 1.2, G 1.0, R 0.8}) exactly like Paint.NET.
        let level = LevelsOp(inLow: .black, inHigh: .white, gamma: (1.2, 1.0, 0.8), outLow: .black, outHigh: .white)
        return PixelOpRenderer(src: src) { c in
            let i = c.intensityByte
            return level.apply(ColorBgra(b: i, g: i, r: i, a: c.a))
        }
    }
}

public final class PosterizeAdjustment: Effect {
    public override var name: String { "Posterize" }
    public override var shortcut: String? { "⇧⌘P" }
    public override var parameters: [EffectParameter] {
        [
            .integer(id: "red", label: "Red", range: 2...64, defaultValue: 16),
            .integer(id: "green", label: "Green", range: 2...64, defaultValue: 16),
            .integer(id: "blue", label: "Blue", range: 2...64, defaultValue: 16),
            .checkbox(id: "linked", label: "Linked", defaultValue: true),
        ]
    }

    static func table(_ levels: Int) -> [UInt8] {
        let n = Double(max(2, levels) - 1)
        return (0..<256).map { v in clampToByte((Double(v) * n / 255).rounded() * 255 / n) }
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let rt = Self.table(values.int("red")), gt = Self.table(values.int("green")), bt = Self.table(values.int("blue"))
        return PixelOpRenderer(src: src) { c in
            ColorBgra(b: bt[Int(c.b)], g: gt[Int(c.g)], r: rt[Int(c.r)], a: c.a)
        }
    }
}

public final class BrightnessContrastAdjustment: Effect {
    public override var name: String { "Brightness / Contrast" }
    public override var parameters: [EffectParameter] {
        [
            .integer(id: "brightness", label: "Brightness", range: -100...100, defaultValue: 0),
            .integer(id: "contrast", label: "Contrast", range: -100...100, defaultValue: 0),
        ]
    }

    /// Paint.NET's lookup-table based brightness/contrast.
    public static func makeOp(brightness: Int, contrast: Int) -> (ColorBgra) -> ColorBgra {
        var multiply = 1, divide = 1
        if contrast < 0 {
            multiply = contrast + 100
            divide = 100
        } else if contrast > 0 {
            multiply = 100
            divide = 100 - contrast
        }
        var table = [UInt8](repeating: 0, count: 65536)
        if divide == 0 {
            for intensity in 0..<256 {
                table[intensity] = intensity + brightness < 128 ? 0 : 255
            }
            return { c in
                let v = table[Int(c.intensityByte)]
                return ColorBgra(b: v, g: v, r: v, a: c.a)
            }
        }
        for intensity in 0..<256 {
            let shift: Int
            if divide == 100 {
                shift = (intensity - 127) * multiply / divide + 127 - intensity + brightness
            } else {
                shift = (intensity - 127 + brightness) * multiply / divide + 127 - intensity
            }
            for col in 0..<256 {
                table[intensity * 256 + col] = clampToByte(col + shift)
            }
        }
        return { c in
            let base = Int(c.intensityByte) * 256
            return ColorBgra(b: table[base + Int(c.b)], g: table[base + Int(c.g)], r: table[base + Int(c.r)], a: c.a)
        }
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        PixelOpRenderer(src: src, Self.makeOp(brightness: values.int("brightness"), contrast: values.int("contrast")))
    }
}

public final class HueSaturationAdjustment: Effect {
    public override var name: String { "Hue / Saturation" }
    public override var shortcut: String? { "⇧⌘U" }
    public override var parameters: [EffectParameter] {
        [
            .integer(id: "hue", label: "Hue", range: -180...180, defaultValue: 0),
            .integer(id: "saturation", label: "Saturation", range: 0...200, defaultValue: 100),
            .integer(id: "lightness", label: "Lightness", range: -100...100, defaultValue: 0),
        ]
    }

    /// Paint.NET's `UnaryPixelOps.HueSaturationLightness`.
    public static func makeOp(hue: Int, saturation: Int, lightness: Int) -> (ColorBgra) -> ColorBgra {
        let satFactor = saturation * 1024 / 100
        let blendColor: ColorBgra = lightness < 0
            ? ColorBgra(b: 0, g: 0, r: 0, a: UInt8(lightness * -255 / 100))
            : ColorBgra(b: 255, g: 255, r: 255, a: UInt8(lightness * 255 / 100))
        return { c in
            let i = Int(c.intensityByte)
            var col = ColorBgra(b: clampToByte((i * 1024 + (Int(c.b) - i) * satFactor) >> 10),
                                g: clampToByte((i * 1024 + (Int(c.g) - i) * satFactor) >> 10),
                                r: clampToByte((i * 1024 + (Int(c.r) - i) * satFactor) >> 10), a: 255)
            if hue != 0 {
                var hsv = HsvColor(col)
                var h = Int(hsv.hue.rounded()) + hue
                while h < 0 { h += 360 }
                while h > 360 { h -= 360 }
                hsv.hue = Double(h)
                col = hsv.toColor()
            }
            if blendColor.a != 0 { col = Blender.blend(.normal, col, blendColor) }
            col.a = c.a
            return col
        }
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        PixelOpRenderer(src: src, Self.makeOp(hue: values.int("hue"), saturation: values.int("saturation"),
                                              lightness: values.int("lightness")))
    }
}

// MARK: - Levels

/// Paint.NET's `UnaryPixelOps.Level`. Gamma is the exponent applied to the normalized input.
public struct LevelsOp: Equatable {
    public var inLow: ColorBgra
    public var inHigh: ColorBgra
    /// (B, G, R) exponents.
    public var gamma: (Double, Double, Double)
    public var outLow: ColorBgra
    public var outHigh: ColorBgra

    public init(inLow: ColorBgra, inHigh: ColorBgra, gamma: (Double, Double, Double), outLow: ColorBgra, outHigh: ColorBgra) {
        self.inLow = inLow
        self.inHigh = inHigh
        self.gamma = gamma
        self.outLow = outLow
        self.outHigh = outHigh
    }

    public static let identity = LevelsOp(inLow: .black, inHigh: .white, gamma: (1, 1, 1), outLow: .black, outHigh: .white)

    public static func == (a: LevelsOp, b: LevelsOp) -> Bool {
        a.inLow == b.inLow && a.inHigh == b.inHigh && a.outLow == b.outLow && a.outHigh == b.outHigh
            && a.gamma.0 == b.gamma.0 && a.gamma.1 == b.gamma.1 && a.gamma.2 == b.gamma.2
    }

    @inline(__always) func channel(_ v: UInt8, _ lo: UInt8, _ hi: UInt8, _ g: Double, _ olo: UInt8, _ ohi: UInt8) -> UInt8 {
        let fv = Double(v) - Double(lo)
        if fv < 0 { return olo }
        if Double(v) >= Double(hi) { return ohi }
        let n = fv / max(1, Double(hi) - Double(lo))
        return clampToByte(Double(olo) + (Double(ohi) - Double(olo)) * pow(n, g))
    }

    /// Precomputed per-channel lookup tables.
    public func tables() -> ([UInt8], [UInt8], [UInt8]) {
        let bt = (0..<256).map { channel(UInt8($0), inLow.b, inHigh.b, gamma.0, outLow.b, outHigh.b) }
        let gt = (0..<256).map { channel(UInt8($0), inLow.g, inHigh.g, gamma.1, outLow.g, outHigh.g) }
        let rt = (0..<256).map { channel(UInt8($0), inLow.r, inHigh.r, gamma.2, outLow.r, outHigh.r) }
        return (bt, gt, rt)
    }

    public func apply(_ c: ColorBgra) -> ColorBgra {
        ColorBgra(b: channel(c.b, inLow.b, inHigh.b, gamma.0, outLow.b, outHigh.b),
                  g: channel(c.g, inLow.g, inHigh.g, gamma.1, outLow.g, outHigh.g),
                  r: channel(c.r, inLow.r, inHigh.r, gamma.2, outLow.r, outHigh.r), a: c.a)
    }

    /// Paint.NET's `Level.AutoFromLoMdHi`.
    public static func auto(lo: ColorBgra, md: ColorBgra, hi: ColorBgra) -> LevelsOp {
        func g(_ l: UInt8, _ m: UInt8, _ h: UInt8) -> Double {
            let lo = Double(l), mid = Double(m), hi = Double(h)
            if hi <= lo || mid <= lo || mid >= hi { return 1 }
            let v = log(0.5) / log((mid - lo) / (hi - lo))
            return clampDouble(v, 0.1, 10)
        }
        return LevelsOp(inLow: lo, inHigh: hi, gamma: (g(lo.b, md.b, hi.b), g(lo.g, md.g, hi.g), g(lo.r, md.r, hi.r)),
                        outLow: .black, outHigh: .white)
    }
}

/// RGB histogram of a region, used by Levels, Curves and Auto-Level.
public struct HistogramRGB {
    public var b = [Int](repeating: 0, count: 256)
    public var g = [Int](repeating: 0, count: 256)
    public var r = [Int](repeating: 0, count: 256)
    public var total = 0

    public init() {}

    public init(surface: Surface, rect: IntRect, mask: MaskSurface?) {
        let rr = rect.intersection(surface.bounds)
        for y in rr.top..<rr.bottom {
            let p = surface.row(y)
            let m = mask?.row(y)
            for x in rr.left..<rr.right {
                if let m, m[x] < 128 { continue }
                let c = p[x]
                if c.a == 0 { continue }
                b[Int(c.b)] += 1
                g[Int(c.g)] += 1
                r[Int(c.r)] += 1
                total += 1
            }
        }
    }

    /// Value at a percentile (0...1) per channel.
    public func percentileColor(_ fraction: Double) -> ColorBgra {
        func p(_ h: [Int]) -> UInt8 {
            let target = Double(total) * fraction
            var sum = 0
            for i in 0..<256 {
                sum += h[i]
                if Double(sum) >= target { return UInt8(i) }
            }
            return 255
        }
        return ColorBgra(b: p(b), g: p(g), r: p(r), a: 255)
    }

    public func meanColor() -> ColorBgra {
        if total == 0 { return ColorBgra(r: 128, g: 128, b: 128) }
        func m(_ h: [Int]) -> UInt8 {
            var s = 0
            for i in 0..<256 { s += h[i] * i }
            return clampToByte(Double(s) / Double(total))
        }
        return ColorBgra(b: m(b), g: m(g), r: m(r), a: 255)
    }
}

public final class AutoLevelAdjustment: Effect {
    public override var name: String { "Auto-Level" }
    public override var shortcut: String? { "⇧⌘L" }
    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let hist = HistogramRGB(surface: src, rect: env.selectionBounds, mask: env.selectionMask)
        let op = LevelsOp.auto(lo: hist.percentileColor(0.005), md: hist.meanColor(), hi: hist.percentileColor(0.995))
        let (bt, gt, rt) = op.tables()
        return PixelOpRenderer(src: src) { c in ColorBgra(b: bt[Int(c.b)], g: gt[Int(c.g)], r: rt[Int(c.r)], a: c.a) }
    }
}

/// Levels with a custom dialog; values are passed via `configure`.
public final class LevelsAdjustment: Effect {
    public var levels = LevelsOp.identity
    public override var name: String { "Levels" }
    public override var shortcut: String? { "⌘L" }
    public override var hasCustomDialog: Bool { true }
    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let (bt, gt, rt) = levels.tables()
        return PixelOpRenderer(src: src) { c in ColorBgra(b: bt[Int(c.b)], g: gt[Int(c.g)], r: rt[Int(c.r)], a: c.a) }
    }
}

// MARK: - Curves

/// Natural cubic spline through control points in [0,255]², like Paint.NET's `SplineInterpolator`.
public struct SplineCurve: Equatable {
    public var points: [CGPoint]

    public init(points: [CGPoint] = [CGPoint(x: 0, y: 0), CGPoint(x: 255, y: 255)]) {
        self.points = points.sorted { $0.x < $1.x }
    }

    public var isIdentity: Bool {
        points.count == 2 && points[0] == CGPoint(x: 0, y: 0) && points[1] == CGPoint(x: 255, y: 255)
    }

    /// Evaluates the spline at 256 positions.
    public func table() -> [UInt8] {
        let pts = points.sorted { $0.x < $1.x }
        let n = pts.count
        if n == 0 { return (0..<256).map { UInt8($0) } }
        if n == 1 { return [UInt8](repeating: clampToByte(Double(pts[0].y)), count: 256) }
        let xs = pts.map { Double($0.x) }, ys = pts.map { Double($0.y) }
        // Second derivatives for a natural spline.
        var y2 = [Double](repeating: 0, count: n)
        var u = [Double](repeating: 0, count: n)
        for i in 1..<(n - 1) {
            let sig = (xs[i] - xs[i - 1]) / (xs[i + 1] - xs[i - 1])
            let p = sig * y2[i - 1] + 2
            y2[i] = (sig - 1) / p
            let d1 = (ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i])
            let d0 = (ys[i] - ys[i - 1]) / (xs[i] - xs[i - 1])
            u[i] = (6 * (d1 - d0) / (xs[i + 1] - xs[i - 1]) - sig * u[i - 1]) / p
        }
        y2[n - 1] = 0
        if n >= 3 {
            for k in stride(from: n - 2, through: 0, by: -1) { y2[k] = y2[k] * y2[k + 1] + u[k] }
        }
        var out = [UInt8](repeating: 0, count: 256)
        for xi in 0..<256 {
            let x = Double(xi)
            if x <= xs[0] { out[xi] = clampToByte(ys[0]); continue }
            if x >= xs[n - 1] { out[xi] = clampToByte(ys[n - 1]); continue }
            var klo = 0, khi = n - 1
            while khi - klo > 1 {
                let k = (khi + klo) >> 1
                if xs[k] > x { khi = k } else { klo = k }
            }
            let h = xs[khi] - xs[klo]
            if h == 0 { out[xi] = clampToByte(ys[klo]); continue }
            let a = (xs[khi] - x) / h, b = (x - xs[klo]) / h
            let y = a * ys[klo] + b * ys[khi] + ((a * a * a - a) * y2[klo] + (b * b * b - b) * y2[khi]) * (h * h) / 6
            out[xi] = clampToByte(y)
        }
        return out
    }
}

public final class CurvesAdjustment: Effect {
    public enum Mode: Int { case luminosity, rgb }
    public var mode: Mode = .luminosity
    public var luminosity = SplineCurve()
    public var red = SplineCurve()
    public var green = SplineCurve()
    public var blue = SplineCurve()

    public override var name: String { "Curves" }
    public override var shortcut: String? { "⇧⌘M" }
    public override var hasCustomDialog: Bool { true }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        switch mode {
        case .luminosity:
            let t = luminosity.table()
            return PixelOpRenderer(src: src) { c in
                let l = Int(c.intensityByte)
                let diff = Int(t[l]) - l
                return ColorBgra(b: clampToByte(Int(c.b) + diff), g: clampToByte(Int(c.g) + diff),
                                 r: clampToByte(Int(c.r) + diff), a: c.a)
            }
        case .rgb:
            let rt = red.table(), gt = green.table(), bt = blue.table()
            return PixelOpRenderer(src: src) { c in ColorBgra(b: bt[Int(c.b)], g: gt[Int(c.g)], r: rt[Int(c.r)], a: c.a) }
        }
    }
}

// MARK: - Paint.NET 5 adjustments

public final class ExposureAdjustment: Effect {
    public override var name: String { "Exposure" }
    public override var parameters: [EffectParameter] {
        [.double(id: "ev", label: "Exposure", range: -5...5, defaultValue: 0, decimals: 2)]
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        // Scale linear light by 2^EV (sRGB transfer curve both ways).
        let gain = pow(2, values.double("ev"))
        let table: [UInt8] = (0..<256).map { v in
            let c = Double(v) / 255
            let lin = c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            let out = min(1, lin * gain)
            let s = out <= 0.0031308 ? out * 12.92 : 1.055 * pow(out, 1 / 2.4) - 0.055
            return clampToByte(s * 255)
        }
        return PixelOpRenderer(src: src) { c in ColorBgra(b: table[Int(c.b)], g: table[Int(c.g)], r: table[Int(c.r)], a: c.a) }
    }
}

public final class HighlightsShadowsAdjustment: Effect {
    public override var name: String { "Highlights / Shadows" }
    public override var parameters: [EffectParameter] {
        [
            .integer(id: "shadows", label: "Shadows", range: -100...100, defaultValue: 0),
            .integer(id: "highlights", label: "Highlights", range: -100...100, defaultValue: 0),
            .integer(id: "radius", label: "Radius", range: 0...100, defaultValue: 20),
        ]
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let shadows = Double(values.int("shadows")) / 100, highlights = Double(values.int("highlights")) / 100
        let radius = values.int("radius")
        return ClosureRenderer(wholeRegion: true) { dst, rect in
            // A blurred luminance map decides which areas count as shadows or highlights (keeps local contrast).
            let blurred = Surface(width: src.width, height: src.height)
            EffectHelpers.gaussianBlur(src: src, dst: blurred, rect: rect, radius: radius)
            EffectHelpers.parallelRows(rect) { y in
                let s = src.row(y), b = blurred.row(y), d = dst.row(y)
                for x in rect.left..<rect.right {
                    let c = s[x]
                    let l = b[x].intensity
                    let ws = (1 - l) * (1 - l), wh = l * l
                    // Positive shadows lighten dark areas; positive highlights darken bright areas.
                    let lift = shadows * ws * 0.6, cut = highlights * wh * 0.6
                    func adj(_ v: UInt8) -> UInt8 {
                        var f = Double(v) / 255
                        f = lift >= 0 ? f + (1 - f) * lift : f * (1 + lift)
                        f = cut >= 0 ? f * (1 - cut) : f + (1 - f) * -cut
                        return clampToByte(f * 255)
                    }
                    d[x] = ColorBgra(b: adj(c.b), g: adj(c.g), r: adj(c.r), a: c.a)
                }
            }
        }
    }
}

public final class InvertAlphaAdjustment: Effect {
    public override var name: String { "Invert Alpha" }
    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        PixelOpRenderer(src: src) { c in c.withAlpha(255 - c.a) }
    }
}

public final class TemperatureTintAdjustment: Effect {
    public override var name: String { "Temperature and Tint" }
    public override var parameters: [EffectParameter] {
        [
            .integer(id: "temperature", label: "Temperature", range: -100...100, defaultValue: 0),
            .integer(id: "tint", label: "Tint", range: -100...100, defaultValue: 0),
        ]
    }

    public override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        // Channel gains in linear light: warm = more red / less blue; tint = magenta (+) vs green (−).
        let t = Double(values.int("temperature")) / 100, n = Double(values.int("tint")) / 100
        let gr = 1 + 0.25 * t + 0.1 * n, gg = 1 - 0.2 * n, gb = 1 - 0.25 * t + 0.1 * n
        func table(_ gain: Double) -> [UInt8] {
            (0..<256).map { v in
                let lin = pow(Double(v) / 255, 2.2) * gain
                return clampToByte(pow(min(1, lin), 1 / 2.2) * 255)
            }
        }
        let rt = table(gr), gt = table(gg), bt = table(gb)
        return PixelOpRenderer(src: src) { c in ColorBgra(b: bt[Int(c.b)], g: gt[Int(c.g)], r: rt[Int(c.r)], a: c.a) }
    }
}
