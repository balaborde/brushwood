import CoreGraphics
import Foundation

public enum EffectCategory: String, CaseIterable {
    case adjustment = "Adjustments"
    case artistic = "Artistic"
    case blurs = "Blurs"
    case distort = "Distort"
    case noise = "Noise"
    case object = "Object"
    case photo = "Photo"
    case render = "Render"
    case stylize = "Stylize"
}

/// Declarative effect parameters; the UI builds the dialog from these (like Paint.NET's IndirectUI).
public enum EffectParameter {
    case integer(id: String, label: String, range: ClosedRange<Int>, defaultValue: Int)
    case double(id: String, label: String, range: ClosedRange<Double>, defaultValue: Double, decimals: Int)
    case angle(id: String, label: String, range: ClosedRange<Double>, defaultValue: Double)
    case offset(id: String, label: String, defaultValue: CGPoint)
    case checkbox(id: String, label: String, defaultValue: Bool)
    case choice(id: String, label: String, options: [String], defaultValue: Int, radio: Bool)
    case seed(id: String, label: String)
    case color(id: String, label: String, defaultValue: ColorBgra)

    public var id: String {
        switch self {
        case .integer(let id, _, _, _), .double(let id, _, _, _, _), .angle(let id, _, _, _), .offset(let id, _, _),
             .checkbox(let id, _, _), .choice(let id, _, _, _, _), .seed(let id, _), .color(let id, _, _):
            return id
        }
    }

    public var label: String {
        switch self {
        case .integer(_, let l, _, _), .double(_, let l, _, _, _), .angle(_, let l, _, _), .offset(_, let l, _),
             .checkbox(_, let l, _), .choice(_, let l, _, _, _), .seed(_, let l), .color(_, let l, _):
            return l
        }
    }

    public var defaultValue: EffectValue {
        switch self {
        case .integer(_, _, _, let d): return .int(d)
        case .double(_, _, _, let d, _): return .double(d)
        case .angle(_, _, _, let d): return .double(d)
        case .offset(_, _, let d): return .point(d)
        case .checkbox(_, _, let d): return .bool(d)
        case .choice(_, _, _, let d, _): return .int(d)
        case .seed: return .int(Int(arc4random_uniform(UInt32(Int32.max))))
        case .color(_, _, let d): return .color(d)
        }
    }
}

public enum EffectValue: Equatable {
    case int(Int)
    case double(Double)
    case bool(Bool)
    case point(CGPoint)
    case color(ColorBgra)
}

public struct EffectValues: Equatable {
    public var values: [String: EffectValue] = [:]

    public init(_ params: [EffectParameter]) {
        for p in params { values[p.id] = p.defaultValue }
    }

    public init() {}

    public subscript(id: String) -> EffectValue? {
        get { values[id] }
        set { values[id] = newValue }
    }

    public func int(_ id: String) -> Int {
        switch values[id] {
        case .int(let v): return v
        case .double(let v): return Int(v.rounded())
        case .bool(let b): return b ? 1 : 0
        default: return 0
        }
    }

    public func double(_ id: String) -> Double {
        switch values[id] {
        case .int(let v): return Double(v)
        case .double(let v): return v
        default: return 0
        }
    }

    public func bool(_ id: String) -> Bool {
        if case .bool(let b) = values[id] { return b }
        return false
    }

    public func point(_ id: String) -> CGPoint {
        if case .point(let p) = values[id] { return p }
        return .zero
    }

    public func color(_ id: String) -> ColorBgra {
        if case .color(let c) = values[id] { return c }
        return .black
    }
}

/// Information an effect gets about the document and app state.
public struct EffectEnvironment {
    public var primaryColor: ColorBgra
    public var secondaryColor: ColorBgra
    /// Bounds of the selection (or the canvas).
    public var selectionBounds: IntRect
    public var selectionMask: MaskSurface?

    public init(primaryColor: ColorBgra, secondaryColor: ColorBgra, selectionBounds: IntRect, selectionMask: MaskSurface?) {
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
        self.selectionBounds = selectionBounds
        self.selectionMask = selectionMask
    }
}

/// Renders an effect for a prepared configuration. Must be safe to call concurrently on disjoint rects.
public protocol EffectRenderer: AnyObject {
    func render(into dst: Surface, rect: IntRect)
    /// When true the runner calls `render` once for the whole region (renderer parallelizes internally).
    var rendersWholeRegion: Bool { get }
}

public extension EffectRenderer {
    var rendersWholeRegion: Bool { false }
}

/// Simple renderer wrapping a closure.
public final class ClosureRenderer: EffectRenderer {
    let body: (Surface, IntRect) -> Void
    public let rendersWholeRegion: Bool

    public init(wholeRegion: Bool = false, _ body: @escaping (Surface, IntRect) -> Void) {
        self.body = body
        rendersWholeRegion = wholeRegion
    }

    public func render(into dst: Surface, rect: IntRect) { body(dst, rect) }
}

/// Per-pixel renderer for effects that only depend on the source pixel.
public final class PixelOpRenderer: EffectRenderer {
    let src: Surface
    let op: (ColorBgra) -> ColorBgra

    public init(src: Surface, _ op: @escaping (ColorBgra) -> ColorBgra) {
        self.src = src
        self.op = op
    }

    public func render(into dst: Surface, rect: IntRect) {
        for y in rect.top..<rect.bottom {
            let s = src.row(y), d = dst.row(y)
            for x in rect.left..<rect.right { d[x] = op(s[x]) }
        }
    }
}

/// Base class of every adjustment and effect.
open class Effect {
    public init() {}

    /// Stable identifier (used for "Repeat" and settings).
    open var id: String { String(describing: type(of: self)) }
    open var name: String { "" }
    open var category: EffectCategory { .adjustment }
    open var parameters: [EffectParameter] { [] }
    /// Adjustments/effects with a hand-written dialog (Curves, Levels).
    open var hasCustomDialog: Bool { false }
    /// Name of a default menu key equivalent hint (e.g. "⇧⌘I"); UI only.
    open var shortcut: String? { nil }
    /// Effects like Red Eye Removal warn when there is no selection.
    open var requiresSelectionHint: String? { nil }
    /// Ellipsis shown in menu when a dialog opens.
    public var showsDialog: Bool { !parameters.isEmpty || hasCustomDialog }

    /// Prepares a renderer. `src` is an immutable snapshot of the layer.
    open func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        ClosureRenderer { dst, rect in dst.copy(from: src, rect: rect) }
    }
}

/// Runs effects over a region, in parallel bands, with cancellation and progress.
public final class EffectRunner {
    public final class Token {
        private let lock = NSLock()
        private var cancelled = false
        public init() {}
        public var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }
        public func cancel() {
            lock.lock()
            cancelled = true
            lock.unlock()
        }
    }

    /// Renders synchronously on the calling thread (parallelized). Returns false if cancelled.
    /// `bandDone` is called (from worker threads) with each finished band.
    @discardableResult
    public static func run(effect: Effect, src: Surface, dst: Surface, values: EffectValues, env: EffectEnvironment,
                           token: Token? = nil, bandDone: ((IntRect) -> Void)? = nil) -> Bool {
        let region = env.selectionBounds.intersection(src.bounds)
        if region.isEmpty { return true }
        let renderer = effect.makeRenderer(src: src, values: values, env: env)
        if token?.isCancelled == true { return false }
        if renderer.rendersWholeRegion {
            renderer.render(into: dst, rect: region)
            if token?.isCancelled == true { return false }
            applySelectionClip(src: src, dst: dst, rect: region, mask: env.selectionMask)
            bandDone?(region)
            return true
        }
        let bandHeight = max(1, min(64, 65536 / max(1, region.width)))
        let bands = (region.height + bandHeight - 1) / bandHeight
        DispatchQueue.concurrentPerform(iterations: bands) { i in
            if token?.isCancelled == true { return }
            let top = region.top + i * bandHeight
            let r = IntRect(x: region.x, y: top, width: region.width, height: min(bandHeight, region.bottom - top))
            renderer.render(into: dst, rect: r)
            applySelectionClip(src: src, dst: dst, rect: r, mask: env.selectionMask)
            bandDone?(r)
        }
        return token?.isCancelled != true
    }

    /// Restores unselected pixels and blends antialiased selection edges.
    public static func applySelectionClip(src: Surface, dst: Surface, rect: IntRect, mask: MaskSurface?) {
        guard let mask else { return }
        for y in rect.top..<rect.bottom {
            let m = mask.row(y), s = src.row(y), d = dst.row(y)
            for x in rect.left..<rect.right {
                let c = Int(m[x])
                if c == 255 { continue }
                d[x] = c == 0 ? s[x] : Blender.lerpTo(s[x], d[x], coverage: c)
            }
        }
    }
}

// MARK: - Shared helpers used by many effects

public enum EffectHelpers {
    /// Runs `body(y)` over the rows of `rect` concurrently.
    public static func parallelRows(_ rect: IntRect, _ body: (Int) -> Void) {
        if rect.isEmpty { return }
        DispatchQueue.concurrentPerform(iterations: rect.height) { i in body(rect.top + i) }
    }

    /// Paint.NET style triangle-weighted blur (equivalent to `CreateGaussianBlurRow`), alpha-weighted and
    /// normalized at the edges. Renders `rect` of `dst` from `src`.
    public static func gaussianBlur(src: Surface, dst: Surface, rect: IntRect, radius: Int) {
        let r = rect.intersection(src.bounds)
        if r.isEmpty { return }
        if radius <= 0 {
            dst.copy(from: src, rect: r)
            return
        }
        let w = src.width, h = src.height
        // Rows needed for the vertical pass.
        let y0 = max(0, r.top - radius), y1 = min(h, r.bottom + radius)
        let rows = y1 - y0
        let cols = r.width
        // Horizontal pass: premultiplied, normalized by in-bounds weight sum.
        let tmp = UnsafeMutablePointer<SIMD4<Float>>.allocate(capacity: rows * cols)
        defer { tmp.deallocate() }
        let weights = (0...(2 * radius)).map { Float(radius + 1 - abs($0 - radius)) }
        DispatchQueue.concurrentPerform(iterations: rows) { i in
            let s = src.row(y0 + i)
            let t = tmp + i * cols
            for cx in 0..<cols {
                let x = r.left + cx
                let lo = max(0, x - radius), hi = min(w - 1, x + radius)
                var acc = SIMD4<Float>(repeating: 0)
                var wsum: Float = 0
                var k = lo - (x - radius)
                for sx in lo...hi {
                    let p = s[sx]
                    let wt = weights[k]
                    let a = Float(p.a) * wt
                    acc += SIMD4<Float>(Float(p.b) * a, Float(p.g) * a, Float(p.r) * a, a)
                    wsum += wt
                    k += 1
                }
                t[cx] = acc / wsum
            }
        }
        DispatchQueue.concurrentPerform(iterations: r.height) { i in
            let y = r.top + i
            let d = dst.row(y)
            let lo = max(0, y - radius), hi = min(h - 1, y + radius)
            for cx in 0..<cols {
                var acc = SIMD4<Float>(repeating: 0)
                var wsum: Float = 0
                var k = lo - (y - radius)
                for sy in lo...hi {
                    let wt = weights[k]
                    acc += tmp[(sy - y0) * cols + cx] * wt
                    wsum += wt
                    k += 1
                }
                let a = acc.w
                if a <= 0.001 {
                    d[r.left + cx] = .transparent
                } else {
                    d[r.left + cx] = ColorBgra(b: clampToByte(acc.x / a), g: clampToByte(acc.y / a),
                                               r: clampToByte(acc.z / a), a: clampToByte(a / wsum))
                }
            }
        }
    }

    /// Box-filtered fast blur used by object effects (radius can be large). Operates on all channels.
    public static func fastBlur(src: Surface, dst: Surface, rect: IntRect, radius: Int) {
        // Three-pass approach is unnecessary here; a gaussian with clamped radius is fine for UI ranges.
        gaussianBlur(src: src, dst: dst, rect: rect, radius: radius)
    }
}

/// Deterministic pseudo random numbers for seeded effects.
public struct SeededRandom {
    private var state: UInt64

    public init(seed: Int) {
        state = UInt64(bitPattern: Int64(seed)) &* 0x9E3779B97F4A7C15 &+ 0x2545F4914F6CDD1D
        if state == 0 { state = 0xDEADBEEF }
    }

    public mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    /// Uniform double in [0, 1).
    public mutating func nextDouble() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    public mutating func nextInt(_ upper: Int) -> Int {
        upper <= 0 ? 0 : Int(next() % UInt64(upper))
    }

    /// Standard normal via Box-Muller.
    public mutating func nextGaussian() -> Double {
        let u1 = max(1e-12, nextDouble()), u2 = nextDouble()
        return sqrt(-2 * log(u1)) * cos(2 * Double.pi * u2)
    }

    /// Hash-based value for a pixel, so tiles render identically regardless of order.
    public static func hash(_ x: Int, _ y: Int, _ seed: Int) -> UInt64 {
        var h = UInt64(bitPattern: Int64(x)) &* 0x9E3779B185EBCA87
        h ^= UInt64(bitPattern: Int64(y)) &* 0xC2B2AE3D27D4EB4F
        h ^= UInt64(bitPattern: Int64(seed)) &* 0x165667B19E3779F9
        h ^= h >> 33
        h = h &* 0xFF51AFD7ED558CCD
        h ^= h >> 33
        h = h &* 0xC4CEB9FE1A85EC53
        h ^= h >> 33
        return h
    }

    public static func hashDouble(_ x: Int, _ y: Int, _ seed: Int) -> Double {
        Double(hash(x, y, seed) >> 11) / Double(1 << 53)
    }
}
