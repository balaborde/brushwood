import CoreGraphics

/// Integer pixel rectangle (origin top-left, y grows downward), like Paint.NET's `Rectangle`.
public struct IntRect: Equatable, Hashable, CustomStringConvertible {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(left: Int, top: Int, right: Int, bottom: Int) {
        self.init(x: left, y: top, width: right - left, height: bottom - top)
    }

    public static let zero = IntRect(x: 0, y: 0, width: 0, height: 0)

    public var left: Int { x }
    public var top: Int { y }
    public var right: Int { x + width }
    public var bottom: Int { y + height }
    public var isEmpty: Bool { width <= 0 || height <= 0 }
    public var area: Int { isEmpty ? 0 : width * height }
    public var size: IntSize { IntSize(width: width, height: height) }

    public var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    public func intersection(_ o: IntRect) -> IntRect {
        let l = max(left, o.left), t = max(top, o.top)
        let r = min(right, o.right), b = min(bottom, o.bottom)
        if r <= l || b <= t { return .zero }
        return IntRect(left: l, top: t, right: r, bottom: b)
    }

    public func union(_ o: IntRect) -> IntRect {
        if isEmpty { return o }
        if o.isEmpty { return self }
        return IntRect(left: min(left, o.left), top: min(top, o.top),
                       right: max(right, o.right), bottom: max(bottom, o.bottom))
    }

    public func intersects(_ o: IntRect) -> Bool { !intersection(o).isEmpty }

    public func contains(x px: Int, y py: Int) -> Bool {
        px >= left && px < right && py >= top && py < bottom
    }

    public func insetBy(_ d: Int) -> IntRect {
        IntRect(x: x + d, y: y + d, width: width - 2 * d, height: height - 2 * d)
    }

    public func offsetBy(dx: Int, dy: Int) -> IntRect {
        IntRect(x: x + dx, y: y + dy, width: width, height: height)
    }

    /// Smallest integer rectangle that fully contains a floating rect.
    public init(enclosing r: CGRect) {
        if r.isNull || r.isInfinite {
            self = .zero
            return
        }
        let l = Int(floor(r.minX)), t = Int(floor(r.minY))
        let rr = Int(ceil(r.maxX)), b = Int(ceil(r.maxY))
        self.init(left: l, top: t, right: rr, bottom: b)
    }

    public var description: String { "{\(x), \(y), \(width)×\(height)}" }
}

public struct IntSize: Equatable, Hashable {
    public var width: Int
    public var height: Int
    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public struct IntPoint: Equatable, Hashable {
    public var x: Int
    public var y: Int
    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

@inline(__always) public func clampInt(_ v: Int, _ lo: Int, _ hi: Int) -> Int {
    v < lo ? lo : (v > hi ? hi : v)
}

@inline(__always) public func clampDouble(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
    v < lo ? lo : (v > hi ? hi : v)
}

@inline(__always) public func clampToByte(_ v: Int) -> UInt8 {
    v < 0 ? 0 : (v > 255 ? 255 : UInt8(v))
}

@inline(__always) public func clampToByte(_ v: Double) -> UInt8 {
    v < 0 ? 0 : (v > 255 ? 255 : UInt8(v + 0.5))
}

@inline(__always) public func clampToByte(_ v: Float) -> UInt8 {
    v < 0 ? 0 : (v > 255 ? 255 : UInt8(v + 0.5))
}

/// Fast (a * b) / 255 with rounding, as in Paint.NET's `Utility.FastScaleByteByByte`.
@inline(__always) public func mul255(_ a: Int, _ b: Int) -> Int {
    let t = a * b + 0x80
    return ((t >> 8) + t) >> 8
}

public extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, s: CGFloat) -> CGPoint { CGPoint(x: a.x * s, y: a.y * s) }
    func distance(to p: CGPoint) -> CGFloat { hypot(p.x - x, p.y - y) }
    var length: CGFloat { hypot(x, y) }
}

public extension CGRect {
    /// Rectangle spanning two arbitrary corner points.
    init(corner a: CGPoint, corner b: CGPoint) {
        self.init(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
