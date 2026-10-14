import CoreGraphics
import Foundation

/// Magnetic closing (Brushwood Plus): a stroke released near where it started is joined to its start by a curve that
/// carries on from both ends, so a circle or any closed outline drawn by hand closes cleanly. The stroke must first go
/// well away from its start, so a short scribble near it stays as drawn.
public struct StrokeCloser {
    public let start: CGPoint
    /// Distance from the start under which the end is joined to it, in image pixels.
    public let radius: Double
    /// The stroke went far enough from its start to be closed.
    public private(set) var armed = false
    /// The painted path, from the start.
    private var path: [CGPoint]

    public init(start: CGPoint, radius: Double) {
        self.start = start
        self.radius = max(0, radius)
        path = [start]
    }

    /// Records the painted path as it grows.
    public mutating func add(_ points: [CGPoint]) {
        path += points
        if !armed { armed = points.contains { StrokeStabilizer.distance($0, start) > 1.5 * radius } }
    }

    /// Whether the stroke would be joined to its start if it ended now: its end, or the pointer (which a smoothed stroke
    /// trails behind), is near the start.
    public func joins(pointer: CGPoint? = nil) -> Bool {
        guard armed, let end = path.last else { return false }
        return [end, pointer].contains { $0.map { StrokeStabilizer.distance($0, start) <= radius } ?? false }
    }

    /// The path from the end of the stroke back to its start (empty when the stroke does not close).
    public func closingPath(spacing: Double, pointer: CGPoint? = nil) -> [CGPoint] {
        guard let end = path.last, joins(pointer: pointer) else { return [] }
        let gap = StrokeStabilizer.distance(end, start)
        guard gap > 0.5 else { return [] }
        // Tangents: the direction of the path about one gap back from the end and one gap on from the start.
        let before = path.reversed().first { StrokeStabilizer.distance($0, end) >= gap }
        let after = path.first { StrokeStabilizer.distance($0, start) >= gap }
        return StrokeStabilizer.spline(before, end, start, after, spacing: max(0.1, spacing))
    }
}
