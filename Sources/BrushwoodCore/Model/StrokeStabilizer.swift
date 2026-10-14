import CoreGraphics
import Foundation

/// Brush smoothing (Brushwood Plus), the "pulled string" of Photoshop's Smoothing: the brush follows the pointer at the
/// end of a string and only moves when the string is taut, which takes out hand tremor and wobble. The path through the
/// brush's positions is a centripetal Catmull-Rom spline, so curves stay round even when pointer events are far apart.
///
/// Each call returns the next points of the painted path, to join with straight segments from the previous point. The
/// path lags one spline segment behind the brush, since drawing a segment takes the position after it; the segment is
/// finished early when the pointer stops pulling or pauses. The stroke ends where the brush is, not at the pointer: the
/// string's length would otherwise add a straight tail.
public struct StrokeStabilizer {
    /// String length, in image pixels.
    public let length: Double
    /// Distance between the returned points, in image pixels.
    public let spacing: Double
    /// Where the brush is.
    public private(set) var brush: CGPoint

    /// The spline goes through knots: `start` is where the painted path ends, `next` the knot after it (not painted
    /// yet) and `previous` the one before, which sets the tangent at `start`.
    private var previous: CGPoint?
    private var start: CGPoint
    private var next: CGPoint?

    public init(at point: CGPoint, length: Double, spacing: Double) {
        self.length = max(0, length)
        self.spacing = max(0.1, spacing)
        brush = point
        start = point
    }

    /// The pointer moved: returns the new points of the painted path (often none).
    public mutating func move(to pointer: CGPoint) -> [CGPoint] {
        let dx = Double(pointer.x - brush.x), dy = Double(pointer.y - brush.y)
        let d = (dx * dx + dy * dy).squareRoot()
        guard d > length else { return flush() }
        let k = (d - length) / d
        brush = CGPoint(x: Double(brush.x) + dx * k, y: Double(brush.y) + dy * k)
        // Knots closer than this would only add noise to the spline.
        guard distance(brush, next ?? start) >= max(0.5, length / 4) else { return [] }
        return add(brush)
    }

    /// The pointer has not moved for a moment, or the stroke ends: returns the path up to the brush.
    public mutating func pause() -> [CGPoint] {
        var points = distance(brush, next ?? start) > 0.01 ? add(brush) : []
        points += flush()
        return points
    }

    /// Adds a knot; paints the segment before the previous knot, now that its end tangent is known.
    private mutating func add(_ knot: CGPoint) -> [CGPoint] {
        guard let n = next else {
            next = knot
            return []
        }
        let points = Self.spline(previous, start, n, knot, spacing: spacing)
        previous = start
        start = n
        next = knot
        return points
    }

    /// Paints the pending segment, as if the path went straight on after it.
    private mutating func flush() -> [CGPoint] {
        guard let n = next else { return [] }
        let points = Self.spline(previous, start, n, nil, spacing: spacing)
        previous = start
        start = n
        next = nil
        return points
    }

    private func distance(_ p: CGPoint, _ q: CGPoint) -> Double { Self.distance(p, q) }

    /// Points `spacing` apart along the spline from p1 (excluded) to p2 (included). Missing outer knots continue the
    /// line p1-p2.
    static func spline(_ p0: CGPoint?, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint?, spacing: Double) -> [CGPoint] {
        let a = p0 ?? CGPoint(x: 2 * p1.x - p2.x, y: 2 * p1.y - p2.y)
        let b = p3 ?? CGPoint(x: 2 * p2.x - p1.x, y: 2 * p2.y - p1.y)
        // Centripetal parametrization: no cusps or loops when knots are unevenly spaced.
        let t0 = 0.0
        let t1 = t0 + max(1e-4, distance(a, p1).squareRoot())
        let t2 = t1 + max(1e-4, distance(p1, p2).squareRoot())
        let t3 = t2 + max(1e-4, distance(p2, b).squareRoot())
        func lerp(_ p: CGPoint, _ q: CGPoint, _ u: Double, _ v: Double, _ t: Double) -> CGPoint {
            let w = (t - u) / (v - u)
            return CGPoint(x: Double(p.x) + (Double(q.x) - Double(p.x)) * w, y: Double(p.y) + (Double(q.y) - Double(p.y)) * w)
        }
        let steps = min(64, max(1, Int((distance(p1, p2) / spacing).rounded(.up))))
        var points: [CGPoint] = []
        points.reserveCapacity(steps)
        for i in 1...steps {
            let t = t1 + (t2 - t1) * Double(i) / Double(steps)
            let a1 = lerp(a, p1, t0, t1, t), a2 = lerp(p1, p2, t1, t2, t), a3 = lerp(p2, b, t2, t3, t)
            let b1 = lerp(a1, a2, t0, t2, t), b2 = lerp(a2, a3, t1, t3, t)
            points.append(i == steps ? p2 : lerp(b1, b2, t1, t2, t))
        }
        return points
    }

    static func distance(_ p: CGPoint, _ q: CGPoint) -> Double {
        let dx = Double(p.x - q.x), dy = Double(p.y - q.y)
        return (dx * dx + dy * dy).squareRoot()
    }
}
