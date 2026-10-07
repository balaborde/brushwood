import CoreGraphics

/// 32-bit straight-alpha pixel stored in BGRA byte order, the same layout Paint.NET uses.
public struct ColorBgra: Equatable, Hashable {
    public var b: UInt8
    public var g: UInt8
    public var r: UInt8
    public var a: UInt8

    @inline(__always) public init(b: UInt8, g: UInt8, r: UInt8, a: UInt8) {
        self.b = b
        self.g = g
        self.r = r
        self.a = a
    }

    @inline(__always) public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.b = b
        self.g = g
        self.r = r
        self.a = a
    }

    public init(r: Int, g: Int, b: Int, a: Int = 255) {
        self.init(r: clampToByte(r), g: clampToByte(g), b: clampToByte(b), a: clampToByte(a))
    }

    public static let transparent = ColorBgra(b: 0, g: 0, r: 0, a: 0)
    public static let transparentWhite = ColorBgra(b: 255, g: 255, r: 255, a: 0)
    public static let black = ColorBgra(r: 0, g: 0, b: 0)
    public static let white = ColorBgra(r: 255, g: 255, b: 255)

    /// 0xAARRGGBB
    public init(argb: UInt32) {
        self.init(b: UInt8(argb & 0xFF), g: UInt8((argb >> 8) & 0xFF),
                  r: UInt8((argb >> 16) & 0xFF), a: UInt8((argb >> 24) & 0xFF))
    }

    public var argb: UInt32 {
        let hi: UInt32 = (UInt32(a) << 24) | (UInt32(r) << 16)
        let lo: UInt32 = (UInt32(g) << 8) | UInt32(b)
        return hi | lo
    }

    /// Luma used by Paint.NET's desaturate op: (7471 B + 38470 G + 19595 R) >> 16.
    @inline(__always) public var intensityByte: UInt8 {
        let bb: Int = 7471 * Int(b)
        let gg: Int = 38470 * Int(g)
        let rr: Int = 19595 * Int(r)
        return UInt8((bb + gg + rr) >> 16)
    }

    @inline(__always) public var intensity: Double {
        let bb: Double = 0.114 * Double(b)
        let gg: Double = 0.587 * Double(g)
        let rr: Double = 0.299 * Double(r)
        return (bb + gg + rr) / 255.0
    }

    @inline(__always) public func withAlpha(_ alpha: UInt8) -> ColorBgra {
        ColorBgra(b: b, g: g, r: r, a: alpha)
    }

    /// Hex string like Paint.NET's color window ("RRGGBBAA" when alpha differs from 255).
    public var hexString: String {
        String(format: "%02X%02X%02X", r, g, b) + (a == 255 ? "" : String(format: "%02X", a))
    }

    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard let v = UInt32(s, radix: 16) else { return nil }
        switch s.count {
        case 3:
            let r = (v >> 8) & 0xF, g = (v >> 4) & 0xF, b = v & 0xF
            self.init(r: UInt8(r * 17), g: UInt8(g * 17), b: UInt8(b * 17))
        case 6:
            self.init(r: UInt8((v >> 16) & 0xFF), g: UInt8((v >> 8) & 0xFF), b: UInt8(v & 0xFF))
        case 8:
            self.init(r: UInt8((v >> 24) & 0xFF), g: UInt8((v >> 16) & 0xFF),
                      b: UInt8((v >> 8) & 0xFF), a: UInt8(v & 0xFF))
        default:
            return nil
        }
    }

    /// Linear interpolation between two colors with straight alpha handled correctly.
    public static func lerp(_ from: ColorBgra, _ to: ColorBgra, _ t: Double) -> ColorBgra {
        let t = clampDouble(t, 0, 1)
        let a = Double(from.a) + (Double(to.a) - Double(from.a)) * t
        if a <= 0 { return .transparent }
        // Interpolate premultiplied values so transparent endpoints don't bleed black.
        let fa = Double(from.a), ta = Double(to.a)
        func ch(_ f: UInt8, _ g: UInt8) -> UInt8 {
            let pf = Double(f) * fa, pt = Double(g) * ta
            return clampToByte((pf + (pt - pf) * t) / a)
        }
        return ColorBgra(b: ch(from.b, to.b), g: ch(from.g, to.g), r: ch(from.r, to.r), a: clampToByte(a))
    }

    /// Straight blend of colors weighted by `weights` (sum need not be 1), alpha-weighted like Paint.NET's `ColorBgra.Blend`.
    public static func blend(_ colors: [ColorBgra], weights: [Double]) -> ColorBgra {
        var wa = 0.0, wr = 0.0, wg = 0.0, wb = 0.0, wsum = 0.0
        for i in 0..<colors.count {
            let c = colors[i], w = weights[i]
            let aw = Double(c.a) * w
            wa += aw
            wr += Double(c.r) * aw
            wg += Double(c.g) * aw
            wb += Double(c.b) * aw
            wsum += w
        }
        if wa <= 0 || wsum <= 0 { return .transparent }
        return ColorBgra(b: clampToByte(wb / wa), g: clampToByte(wg / wa), r: clampToByte(wr / wa), a: clampToByte(wa / wsum))
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }

    public init(cgColor: CGColor) {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let c = cgColor.converted(to: srgb, intent: .defaultIntent, options: nil) ?? cgColor
        let comps = c.components ?? [0, 0, 0, 1]
        if comps.count >= 4 {
            self.init(r: clampToByte(Double(comps[0]) * 255), g: clampToByte(Double(comps[1]) * 255),
                      b: clampToByte(Double(comps[2]) * 255), a: clampToByte(Double(comps[3]) * 255))
        } else if comps.count == 2 {
            let v = clampToByte(Double(comps[0]) * 255)
            self.init(r: v, g: v, b: v, a: clampToByte(Double(comps[1]) * 255))
        } else {
            self = .black
        }
    }
}

/// HSV color with hue in degrees [0, 360), saturation and value in [0, 100], as in Paint.NET's `HsvColor`.
public struct HsvColor: Equatable {
    public var hue: Double
    public var saturation: Double
    public var value: Double

    public init(hue: Double, saturation: Double, value: Double) {
        self.hue = hue
        self.saturation = saturation
        self.value = value
    }

    public init(_ c: ColorBgra) {
        let r = Double(c.r) / 255, g = Double(c.g) / 255, b = Double(c.b) / 255
        let mx = max(r, g, b), mn = min(r, g, b)
        let delta = mx - mn
        var h = 0.0
        if delta > 0 {
            if mx == r { h = 60 * ((g - b) / delta) }
            else if mx == g { h = 60 * ((b - r) / delta + 2) }
            else { h = 60 * ((r - g) / delta + 4) }
        }
        if h < 0 { h += 360 }
        self.hue = h
        self.saturation = mx == 0 ? 0 : delta / mx * 100
        self.value = mx * 100
    }

    public func toColor(alpha: UInt8 = 255) -> ColorBgra {
        let s = clampDouble(saturation, 0, 100) / 100
        let v = clampDouble(value, 0, 100) / 100
        var h = hue.truncatingRemainder(dividingBy: 360)
        if h < 0 { h += 360 }
        let c = v * s
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = v - c
        var r = 0.0, g = 0.0, b = 0.0
        switch h {
        case 0..<60: (r, g, b) = (c, x, 0)
        case 60..<120: (r, g, b) = (x, c, 0)
        case 120..<180: (r, g, b) = (0, c, x)
        case 180..<240: (r, g, b) = (0, x, c)
        case 240..<300: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        return ColorBgra(r: clampToByte((r + m) * 255), g: clampToByte((g + m) * 255), b: clampToByte((b + m) * 255), a: alpha)
    }
}

/// HSL helpers used by hue/saturation style blend modes and adjustments.
public enum HSL {
    public static func fromRGB(_ r: Double, _ g: Double, _ b: Double) -> (h: Double, s: Double, l: Double) {
        let mx = max(r, g, b), mn = min(r, g, b)
        let l = (mx + mn) / 2
        if mx == mn { return (0, 0, l) }
        let d = mx - mn
        let s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
        var h: Double
        if mx == r { h = (g - b) / d + (g < b ? 6 : 0) }
        else if mx == g { h = (b - r) / d + 2 }
        else { h = (r - g) / d + 4 }
        h /= 6
        return (h, s, l)
    }

    public static func toRGB(_ h: Double, _ s: Double, _ l: Double) -> (r: Double, g: Double, b: Double) {
        if s == 0 { return (l, l, l) }
        func hue2rgb(_ p: Double, _ q: Double, _ t0: Double) -> Double {
            var t = t0
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 1.0 / 2 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        return (hue2rgb(p, q, h + 1.0 / 3), hue2rgb(p, q, h), hue2rgb(p, q, h - 1.0 / 3))
    }
}
