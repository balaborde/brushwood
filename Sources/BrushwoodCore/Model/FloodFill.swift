import Foundation

public enum FloodMode: Int, CaseIterable, Codable {
    case contiguous
    case global

    public var displayName: String {
        switch self {
        case .contiguous: return "Contiguous"
        case .global: return "Global"
        }
    }
}

public enum FloodFill {
    /// Paint.NET's tolerance check. `tolerance` is the slider value in 0...1.
    @inline(__always)
    public static func colorsMatch(_ a: ColorBgra, _ b: ColorBgra, toleranceSquared4: Int) -> Bool {
        var sum = 0
        var diff = Int(a.r) - Int(b.r)
        sum += (1 + diff * diff) * Int(a.a) / 256
        diff = Int(a.g) - Int(b.g)
        sum += (1 + diff * diff) * Int(a.a) / 256
        diff = Int(a.b) - Int(b.b)
        sum += (1 + diff * diff) * Int(a.a) / 256
        diff = Int(a.a) - Int(b.a)
        sum += diff * diff
        return sum <= toleranceSquared4
    }

    public static func toleranceThreshold(_ tolerance: Double) -> Int {
        let t = Int(tolerance * tolerance * 256)
        return t * t * 4
    }

    /// Computes the region matching the color at `seed` (0/255 mask).
    /// - Parameters:
    ///   - limit: optional mask; pixels with zero coverage are never included (selection clip).
    public static func fillMask(surface: Surface, seed: IntPoint, tolerance: Double, mode: FloodMode,
                                limit: MaskSurface? = nil) -> MaskSurface {
        let w = surface.width, h = surface.height
        let mask = MaskSurface(width: w, height: h)
        guard surface.bounds.contains(x: seed.x, y: seed.y) else { return mask }
        let cmp = surface[seed.x, seed.y]
        let tol = toleranceThreshold(tolerance)
        @inline(__always) func ok(_ x: Int, _ y: Int) -> Bool {
            if let limit, limit.data[y * w + x] == 0 { return false }
            return colorsMatch(cmp, surface.pixels[y * w + x], toleranceSquared4: tol)
        }

        if mode == .global {
            DispatchQueue.concurrentPerform(iterations: h) { y in
                let m = mask.row(y)
                for x in 0..<w where ok(x, y) { m[x] = 255 }
            }
            return mask
        }

        if !ok(seed.x, seed.y) { return mask }
        // Scanline flood fill.
        var stack: [IntPoint] = [seed]
        let md = mask.data
        while let p = stack.popLast() {
            let y = p.y
            var x = p.x
            if md[y * w + x] != 0 { continue }
            while x > 0 && md[y * w + x - 1] == 0 && ok(x - 1, y) { x -= 1 }
            var spanAbove = false, spanBelow = false
            while x < w && md[y * w + x] == 0 && ok(x, y) {
                md[y * w + x] = 255
                if y > 0 {
                    let o = md[(y - 1) * w + x] == 0 && ok(x, y - 1)
                    if o && !spanAbove { stack.append(IntPoint(x: x, y: y - 1)); spanAbove = true } else if !o { spanAbove = false }
                }
                if y < h - 1 {
                    let o = md[(y + 1) * w + x] == 0 && ok(x, y + 1)
                    if o && !spanBelow { stack.append(IntPoint(x: x, y: y + 1)); spanBelow = true } else if !o { spanBelow = false }
                }
                x += 1
            }
        }
        return mask
    }
}

/// Fill styles of the paint bucket / shapes (Paint.NET's hatch brushes).
public enum FillStyle: Int, CaseIterable, Codable {
    case solid
    case horizontal
    case vertical
    case forwardDiagonal
    case backwardDiagonal
    case cross
    case diagonalCross
    case percent05
    case percent10
    case percent20
    case percent25
    case percent50
    case percent75
    case percent90
    case lightHorizontal
    case lightVertical
    case darkHorizontal
    case darkVertical
    case dashedHorizontal
    case dashedVertical
    case smallGrid
    case largeGrid
    case smallCheckerBoard
    case largeCheckerBoard
    case dottedGrid
    case dottedDiamond
    case diagonalBrick
    case horizontalBrick
    case weave
    case plaid
    case divot
    case shingle
    case trellis
    case sphere
    case zigZag
    case wave
    case outlinedDiamond
    case solidDiamond

    public var displayName: String {
        switch self {
        case .solid: return "Solid Color"
        case .horizontal: return "Horizontal"
        case .vertical: return "Vertical"
        case .forwardDiagonal: return "Forward Diagonal"
        case .backwardDiagonal: return "Backward Diagonal"
        case .cross: return "Cross"
        case .diagonalCross: return "Diagonal Cross"
        case .percent05: return "5 Percent"
        case .percent10: return "10 Percent"
        case .percent20: return "20 Percent"
        case .percent25: return "25 Percent"
        case .percent50: return "50 Percent"
        case .percent75: return "75 Percent"
        case .percent90: return "90 Percent"
        case .lightHorizontal: return "Light Horizontal"
        case .lightVertical: return "Light Vertical"
        case .darkHorizontal: return "Dark Horizontal"
        case .darkVertical: return "Dark Vertical"
        case .dashedHorizontal: return "Dashed Horizontal"
        case .dashedVertical: return "Dashed Vertical"
        case .smallGrid: return "Small Grid"
        case .largeGrid: return "Large Grid"
        case .smallCheckerBoard: return "Small Checker Board"
        case .largeCheckerBoard: return "Large Checker Board"
        case .dottedGrid: return "Dotted Grid"
        case .dottedDiamond: return "Dotted Diamond"
        case .diagonalBrick: return "Diagonal Brick"
        case .horizontalBrick: return "Horizontal Brick"
        case .weave: return "Weave"
        case .plaid: return "Plaid"
        case .divot: return "Divot"
        case .shingle: return "Shingle"
        case .trellis: return "Trellis"
        case .sphere: return "Sphere"
        case .zigZag: return "Zig Zag"
        case .wave: return "Wave"
        case .outlinedDiamond: return "Outlined Diamond"
        case .solidDiamond: return "Solid Diamond"
        }
    }

    /// 8×8 hatch pattern rows (MSB = leftmost pixel), matching GDI+ HatchStyle bitmaps.
    public var pattern: [UInt8] {
        switch self {
        case .solid: return [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]
        case .horizontal: return [0xFF, 0, 0, 0, 0, 0, 0, 0]
        case .vertical: return [0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80]
        case .forwardDiagonal: return [0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01]
        case .backwardDiagonal: return [0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80]
        case .cross: return [0xFF, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80]
        case .diagonalCross: return [0x81, 0x42, 0x24, 0x18, 0x18, 0x24, 0x42, 0x81]
        case .percent05: return [0x80, 0, 0, 0, 0x08, 0, 0, 0]
        case .percent10: return [0x80, 0, 0x08, 0, 0x80, 0, 0x08, 0]
        case .percent20: return [0x88, 0, 0x22, 0, 0x88, 0, 0x22, 0]
        case .percent25: return [0x88, 0x22, 0x88, 0x22, 0x88, 0x22, 0x88, 0x22]
        case .percent50: return [0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55]
        case .percent75: return [0xEE, 0xBB, 0xEE, 0xBB, 0xEE, 0xBB, 0xEE, 0xBB]
        case .percent90: return [0xFF, 0x7F, 0xFF, 0xF7, 0xFF, 0x7F, 0xFF, 0xF7]
        case .lightHorizontal: return [0xFF, 0, 0, 0, 0xFF, 0, 0, 0]
        case .lightVertical: return [0x88, 0x88, 0x88, 0x88, 0x88, 0x88, 0x88, 0x88]
        case .darkHorizontal: return [0xFF, 0xFF, 0, 0, 0xFF, 0xFF, 0, 0]
        case .darkVertical: return [0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC]
        case .dashedHorizontal: return [0xF0, 0, 0, 0, 0x0F, 0, 0, 0]
        case .dashedVertical: return [0x80, 0x80, 0x80, 0x80, 0x08, 0x08, 0x08, 0x08]
        case .smallGrid: return [0xFF, 0x88, 0x88, 0x88, 0xFF, 0x88, 0x88, 0x88]
        case .largeGrid: return [0xFF, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80]
        case .smallCheckerBoard: return [0x99, 0x66, 0x66, 0x99, 0x99, 0x66, 0x66, 0x99]
        case .largeCheckerBoard: return [0xF0, 0xF0, 0xF0, 0xF0, 0x0F, 0x0F, 0x0F, 0x0F]
        case .dottedGrid: return [0xAA, 0, 0x80, 0, 0x80, 0, 0x80, 0]
        case .dottedDiamond: return [0x80, 0, 0x22, 0, 0x08, 0, 0x22, 0]
        case .diagonalBrick: return [0x01, 0x02, 0x04, 0x08, 0x18, 0x24, 0x42, 0x81]
        case .horizontalBrick: return [0xFF, 0x80, 0x80, 0x80, 0xFF, 0x08, 0x08, 0x08]
        case .weave: return [0x88, 0x54, 0x22, 0x45, 0x88, 0x14, 0x22, 0x51]
        case .plaid: return [0xAA, 0x55, 0xAA, 0x55, 0xF0, 0xF0, 0xF0, 0xF0]
        case .divot: return [0x00, 0x10, 0x08, 0x10, 0x00, 0x01, 0x80, 0x01]
        case .shingle: return [0x03, 0x84, 0x48, 0x30, 0x0C, 0x02, 0x01, 0x01]
        case .trellis: return [0xFF, 0x66, 0xFF, 0x99, 0xFF, 0x66, 0xFF, 0x99]
        case .sphere: return [0x77, 0x89, 0x8F, 0x8F, 0x77, 0x98, 0xF8, 0xF8]
        case .zigZag: return [0x81, 0x42, 0x24, 0x18, 0x81, 0x42, 0x24, 0x18]
        case .wave: return [0x00, 0x18, 0xA4, 0x03, 0x00, 0x18, 0xA4, 0x03]
        case .outlinedDiamond: return [0x41, 0x22, 0x14, 0x08, 0x14, 0x22, 0x41, 0x80]
        case .solidDiamond: return [0x08, 0x1C, 0x3E, 0x7F, 0x3E, 0x1C, 0x08, 0x00]
        }
    }

    /// Whether a hatch pattern (from `pattern`) is "on" (primary color) at a pixel.
    @inline(__always) public static func isForeground(_ pattern: [UInt8], x: Int, y: Int) -> Bool {
        let row = pattern[y & 7]
        return (row >> (7 - UInt8(x & 7))) & 1 == 1
    }
}
