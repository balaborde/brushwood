import Foundation

/// Layer and tool blend modes. The first fourteen match Paint.NET's classic `UserBlendOps`.
public enum BlendMode: Int, CaseIterable, Codable {
    case normal
    case multiply
    case additive
    case colorBurn
    case colorDodge
    case reflect
    case glow
    case overlay
    case difference
    case negation
    case lighten
    case darken
    case screen
    case xor
    case hardLight
    case softLight
    case color
    case luminosity
    case hue
    case saturation

    public var displayName: String {
        switch self {
        case .normal: return "Normal"
        case .multiply: return "Multiply"
        case .additive: return "Additive"
        case .colorBurn: return "Color Burn"
        case .colorDodge: return "Color Dodge"
        case .reflect: return "Reflect"
        case .glow: return "Glow"
        case .overlay: return "Overlay"
        case .difference: return "Difference"
        case .negation: return "Negation"
        case .lighten: return "Lighten"
        case .darken: return "Darken"
        case .screen: return "Screen"
        case .xor: return "Xor"
        case .hardLight: return "Hard Light"
        case .softLight: return "Soft Light"
        case .color: return "Color"
        case .luminosity: return "Luminosity"
        case .hue: return "Hue"
        case .saturation: return "Saturation"
        }
    }

    /// Name used by the OpenRaster format (`svg:` composite-op).
    public var oraName: String {
        switch self {
        case .normal: return "svg:src-over"
        case .multiply: return "svg:multiply"
        case .additive: return "svg:plus"
        case .colorBurn: return "svg:color-burn"
        case .colorDodge: return "svg:color-dodge"
        case .reflect: return "brushwood:reflect"
        case .glow: return "brushwood:glow"
        case .overlay: return "svg:overlay"
        case .difference: return "svg:difference"
        case .negation: return "brushwood:negation"
        case .lighten: return "svg:lighten"
        case .darken: return "svg:darken"
        case .screen: return "svg:screen"
        case .xor: return "brushwood:xor"
        case .hardLight: return "svg:hard-light"
        case .softLight: return "svg:soft-light"
        case .color: return "svg:color"
        case .luminosity: return "svg:luminosity"
        case .hue: return "svg:hue"
        case .saturation: return "svg:saturation"
        }
    }

    public init(oraName: String) {
        self = BlendMode.allCases.first { $0.oraName == oraName } ?? .normal
    }

    /// Whether the mode works per channel (fast integer path).
    var isSeparable: Bool {
        switch self {
        case .color, .luminosity, .hue, .saturation: return false
        default: return true
        }
    }
}

/// Per-channel blend function F(lhs = bottom, rhs = top).
@inline(__always) func separableBlend(_ mode: BlendMode, _ l: Int, _ r: Int) -> Int {
    switch mode {
    case .normal: return r
    case .multiply: return mul255(l, r)
    case .additive: return min(255, l + r)
    case .colorBurn:
        if r == 0 { return 0 }
        return max(0, 255 - ((255 - l) * 255) / r)
    case .colorDodge:
        if r == 255 { return 255 }
        return min(255, (l * 255) / (255 - r))
    case .reflect:
        if r == 255 { return 255 }
        return min(255, (l * l) / (255 - r))
    case .glow:
        if l == 255 { return 255 }
        return min(255, (r * r) / (255 - l))
    case .overlay:
        if l < 128 { return mul255(2 * l, r) }
        return 255 - mul255(2 * (255 - l), 255 - r)
    case .difference: return abs(l - r)
    case .negation: return 255 - abs(255 - l - r)
    case .lighten: return max(l, r)
    case .darken: return min(l, r)
    case .screen: return 255 - mul255(255 - l, 255 - r)
    case .xor: return l ^ r
    case .hardLight:
        if r < 128 { return mul255(2 * r, l) }
        return 255 - mul255(2 * (255 - r), 255 - l)
    case .softLight:
        let cb = Double(l) / 255, cs = Double(r) / 255
        var res: Double
        if cs <= 0.5 {
            res = cb - (1 - 2 * cs) * cb * (1 - cb)
        } else {
            let d = cb <= 0.25 ? ((16 * cb - 12) * cb + 4) * cb : sqrt(cb)
            res = cb + (2 * cs - 1) * (d - cb)
        }
        return Int(res * 255 + 0.5)
    default:
        return r
    }
}

/// Non-separable blend (W3C compositing spec) for hue / saturation / color / luminosity.
@inline(__always) func nonSeparableBlend(_ mode: BlendMode, _ lr: Int, _ lg: Int, _ lb: Int,
                                         _ rr: Int, _ rg: Int, _ rb: Int) -> (Int, Int, Int) {
    let cb = (Double(lr) / 255, Double(lg) / 255, Double(lb) / 255)
    let cs = (Double(rr) / 255, Double(rg) / 255, Double(rb) / 255)
    func lum(_ c: (Double, Double, Double)) -> Double { 0.3 * c.0 + 0.59 * c.1 + 0.11 * c.2 }
    func clip(_ c: (Double, Double, Double)) -> (Double, Double, Double) {
        let l = lum(c)
        let n = min(c.0, c.1, c.2), x = max(c.0, c.1, c.2)
        var r = c
        if n < 0 {
            r = (l + (r.0 - l) * l / (l - n), l + (r.1 - l) * l / (l - n), l + (r.2 - l) * l / (l - n))
        }
        if x > 1 {
            r = (l + (r.0 - l) * (1 - l) / (x - l), l + (r.1 - l) * (1 - l) / (x - l), l + (r.2 - l) * (1 - l) / (x - l))
        }
        return r
    }
    func setLum(_ c: (Double, Double, Double), _ l: Double) -> (Double, Double, Double) {
        let d = l - lum(c)
        return clip((c.0 + d, c.1 + d, c.2 + d))
    }
    func sat(_ c: (Double, Double, Double)) -> Double { max(c.0, c.1, c.2) - min(c.0, c.1, c.2) }
    func setSat(_ c: (Double, Double, Double), _ s: Double) -> (Double, Double, Double) {
        var v = [c.0, c.1, c.2]
        let idx = [0, 1, 2].sorted { v[$0] < v[$1] }
        let mn = idx[0], md = idx[1], mx = idx[2]
        if v[mx] > v[mn] {
            v[md] = (v[md] - v[mn]) * s / (v[mx] - v[mn])
            v[mx] = s
        } else {
            v[md] = 0
            v[mx] = 0
        }
        v[mn] = 0
        return (v[0], v[1], v[2])
    }
    var res: (Double, Double, Double)
    switch mode {
    case .hue: res = setLum(setSat(cs, sat(cb)), lum(cb))
    case .saturation: res = setLum(setSat(cb, sat(cs)), lum(cb))
    case .color: res = setLum(cs, lum(cb))
    case .luminosity: res = setLum(cb, lum(cs))
    default: res = cs
    }
    return (Int(clampDouble(res.0, 0, 1) * 255 + 0.5), Int(clampDouble(res.1, 0, 1) * 255 + 0.5),
            Int(clampDouble(res.2, 0, 1) * 255 + 0.5))
}

public enum Blender {
    /// Composites `rhs` over `lhs` using `mode`, with an extra opacity factor (0...255) applied to rhs alpha.
    /// Straight alpha math identical to Paint.NET's generated `UserBlendOps`.
    @inline(__always)
    public static func blend(_ mode: BlendMode, _ lhs: ColorBgra, _ rhs: ColorBgra, opacity: Int = 255) -> ColorBgra {
        let rhsA = opacity == 255 ? Int(rhs.a) : mul255(Int(rhs.a), opacity)
        if rhsA == 0 { return lhs }
        let lhsA = Int(lhs.a)
        if lhsA == 0 { return ColorBgra(b: rhs.b, g: rhs.g, r: rhs.r, a: UInt8(rhsA)) }
        if mode == .normal && rhsA == 255 { return rhs }
        let y = mul255(lhsA, 255 - rhsA)
        let totalA = y + rhsA
        if totalA == 0 { return .transparent }
        let x = mul255(lhsA, rhsA)
        let z = rhsA - x
        let half = totalA / 2
        var fr: Int, fg: Int, fb: Int
        if mode.isSeparable {
            fr = separableBlend(mode, Int(lhs.r), Int(rhs.r))
            fg = separableBlend(mode, Int(lhs.g), Int(rhs.g))
            fb = separableBlend(mode, Int(lhs.b), Int(rhs.b))
        } else {
            (fr, fg, fb) = nonSeparableBlend(mode, Int(lhs.r), Int(lhs.g), Int(lhs.b), Int(rhs.r), Int(rhs.g), Int(rhs.b))
        }
        let r = (Int(lhs.r) * y + Int(rhs.r) * z + fr * x + half) / totalA
        let g = (Int(lhs.g) * y + Int(rhs.g) * z + fg * x + half) / totalA
        let b = (Int(lhs.b) * y + Int(rhs.b) * z + fb * x + half) / totalA
        return ColorBgra(b: UInt8(min(255, b)), g: UInt8(min(255, g)), r: UInt8(min(255, r)), a: UInt8(min(255, totalA)))
    }

    /// Blends a row of source pixels onto a row of destination pixels in place.
    public static func blendRow(_ mode: BlendMode, dst: UnsafeMutablePointer<ColorBgra>, src: UnsafePointer<ColorBgra>,
                                count: Int, opacity: Int) {
        if opacity <= 0 { return }
        if mode == .normal {
            for i in 0..<count {
                let s = src[i]
                if s.a == 0 { continue }
                if s.a == 255 && opacity == 255 { dst[i] = s; continue }
                dst[i] = blend(.normal, dst[i], s, opacity: opacity)
            }
        } else {
            for i in 0..<count where src[i].a != 0 {
                dst[i] = blend(mode, dst[i], src[i], opacity: opacity)
            }
        }
    }

    /// Blends a solid color through a coverage mask row onto a destination row.
    public static func blendRow(_ mode: BlendMode, dst: UnsafeMutablePointer<ColorBgra>, color: ColorBgra,
                                coverage: UnsafePointer<UInt8>, count: Int) {
        for i in 0..<count {
            let c = Int(coverage[i])
            if c == 0 { continue }
            dst[i] = blend(mode, dst[i], color, opacity: c)
        }
    }

    /// Like Paint.NET's "Overwrite" behaviour: lerp toward the source by coverage (used by eraser & clone).
    @inline(__always)
    public static func lerpTo(_ lhs: ColorBgra, _ rhs: ColorBgra, coverage: Int) -> ColorBgra {
        if coverage >= 255 { return rhs }
        if coverage <= 0 { return lhs }
        let la = Int(lhs.a), ra = Int(rhs.a)
        let a = la + mul255(ra - la, coverage)
        if a <= 0 { return ColorBgra(b: lhs.b, g: lhs.g, r: lhs.r, a: 0) }
        @inline(__always) func ch(_ l: UInt8, _ r: UInt8) -> UInt8 {
            let pl = Int(l) * la, pr = Int(r) * ra
            let v = pl + ((pr - pl) * coverage + 127) / 255
            return UInt8(clampInt((v + a / 2) / a, 0, 255))
        }
        return ColorBgra(b: ch(lhs.b, rhs.b), g: ch(lhs.g, rhs.g), r: ch(lhs.r, rhs.r), a: UInt8(a))
    }
}
