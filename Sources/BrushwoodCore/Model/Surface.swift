import CoreGraphics
import Foundation

/// A 32-bit straight-alpha BGRA bitmap, the Swift counterpart of Paint.NET's `Surface`.
/// Memory is owned manually for fast pointer access from tools and effects.
public final class Surface {
    public let width: Int
    public let height: Int
    public let pixels: UnsafeMutablePointer<ColorBgra>

    public init(width: Int, height: Int, fill: ColorBgra = .transparent) {
        precondition(width > 0 && height > 0, "Surface dimensions must be positive")
        self.width = width
        self.height = height
        pixels = .allocate(capacity: width * height)
        pixels.initialize(repeating: fill, count: width * height)
    }

    public convenience init(size: IntSize, fill: ColorBgra = .transparent) {
        self.init(width: size.width, height: size.height, fill: fill)
    }

    deinit {
        pixels.deallocate()
    }

    public var bounds: IntRect { IntRect(x: 0, y: 0, width: width, height: height) }
    public var size: IntSize { IntSize(width: width, height: height) }
    public var byteCount: Int { width * height * 4 }

    @inline(__always) public func row(_ y: Int) -> UnsafeMutablePointer<ColorBgra> {
        pixels + y * width
    }

    @inline(__always) public subscript(x: Int, y: Int) -> ColorBgra {
        get { pixels[y * width + x] }
        set { pixels[y * width + x] = newValue }
    }

    /// Clamped pixel read (edge pixels repeat outside the bounds).
    @inline(__always) public func getClamped(_ x: Int, _ y: Int) -> ColorBgra {
        pixels[clampInt(y, 0, height - 1) * width + clampInt(x, 0, width - 1)]
    }

    public func clone() -> Surface {
        let s = Surface(uninitializedWidth: width, height: height)
        s.pixels.update(from: pixels, count: width * height)
        return s
    }

    /// Internal fast allocation without initialization.
    init(uninitializedWidth w: Int, height h: Int) {
        width = w
        height = h
        pixels = .allocate(capacity: w * h)
    }

    public func clear(_ color: ColorBgra = .transparent) {
        pixels.update(repeating: color, count: width * height)
    }

    public func clear(_ color: ColorBgra, rect: IntRect) {
        let r = rect.intersection(bounds)
        if r.isEmpty { return }
        for y in r.top..<r.bottom {
            (row(y) + r.left).update(repeating: color, count: r.width)
        }
    }

    /// Returns a copy of the given region (clipped to bounds).
    public func copy(rect: IntRect) -> Surface? {
        let r = rect.intersection(bounds)
        if r.isEmpty { return nil }
        let s = Surface(uninitializedWidth: r.width, height: r.height)
        for y in 0..<r.height {
            s.row(y).update(from: row(r.top + y) + r.left, count: r.width)
        }
        return s
    }

    /// Copies `src` pixels so that src(0,0) lands at `at`. Clipped to both surfaces.
    public func copy(from src: Surface, to at: IntPoint) {
        copy(from: src, srcRect: src.bounds, to: at)
    }

    public func copy(from src: Surface, srcRect: IntRect, to at: IntPoint) {
        var sr = srcRect.intersection(src.bounds)
        var dst = IntRect(x: at.x, y: at.y, width: sr.width, height: sr.height)
        let clipped = dst.intersection(bounds)
        if clipped.isEmpty { return }
        sr.x += clipped.x - dst.x
        sr.y += clipped.y - dst.y
        dst = clipped
        for y in 0..<dst.height {
            (row(dst.top + y) + dst.left).update(from: src.row(sr.top + y) + sr.left, count: dst.width)
        }
    }

    /// Copies the same rectangle from another surface of identical size.
    public func copy(from src: Surface, rect: IntRect) {
        copy(from: src, srcRect: rect, to: IntPoint(x: rect.x, y: rect.y))
    }

    /// Bilinear sample at floating point coordinate (pixel centers at +0.5). Alpha-weighted.
    public func bilinearSample(_ fx: Double, _ fy: Double) -> ColorBgra {
        let x = fx - 0.5, y = fy - 0.5
        let x0 = Int(floor(x)), y0 = Int(floor(y))
        let tx = x - Double(x0), ty = y - Double(y0)
        let c00 = getClamped(x0, y0), c10 = getClamped(x0 + 1, y0)
        let c01 = getClamped(x0, y0 + 1), c11 = getClamped(x0 + 1, y0 + 1)
        let w00 = (1 - tx) * (1 - ty), w10 = tx * (1 - ty), w01 = (1 - tx) * ty, w11 = tx * ty
        let a = Double(c00.a) * w00 + Double(c10.a) * w10 + Double(c01.a) * w01 + Double(c11.a) * w11
        if a <= 0.001 { return .transparent }
        func ch(_ k: KeyPath<ColorBgra, UInt8>) -> UInt8 {
            let v = Double(c00[keyPath: k]) * Double(c00.a) * w00 + Double(c10[keyPath: k]) * Double(c10.a) * w10
                + Double(c01[keyPath: k]) * Double(c01.a) * w01 + Double(c11[keyPath: k]) * Double(c11.a) * w11
            return clampToByte(v / a)
        }
        return ColorBgra(b: ch(\.b), g: ch(\.g), r: ch(\.r), a: clampToByte(a))
    }

    /// Bilinear sample treating outside pixels as transparent.
    public func bilinearSampleTransparentEdges(_ fx: Double, _ fy: Double) -> ColorBgra {
        let x = fx - 0.5, y = fy - 0.5
        let x0 = Int(floor(x)), y0 = Int(floor(y))
        if x0 < -1 || y0 < -1 || x0 >= width || y0 >= height { return .transparent }
        let tx = x - Double(x0), ty = y - Double(y0)
        @inline(__always) func px(_ xx: Int, _ yy: Int) -> ColorBgra {
            (xx < 0 || yy < 0 || xx >= width || yy >= height) ? .transparent : pixels[yy * width + xx]
        }
        let c00 = px(x0, y0), c10 = px(x0 + 1, y0), c01 = px(x0, y0 + 1), c11 = px(x0 + 1, y0 + 1)
        let w00 = (1 - tx) * (1 - ty), w10 = tx * (1 - ty), w01 = (1 - tx) * ty, w11 = tx * ty
        let a00 = Double(c00.a) * w00, a10 = Double(c10.a) * w10, a01 = Double(c01.a) * w01, a11 = Double(c11.a) * w11
        let a = a00 + a10 + a01 + a11
        if a <= 0.001 { return .transparent }
        let r = (Double(c00.r) * a00 + Double(c10.r) * a10 + Double(c01.r) * a01 + Double(c11.r) * a11) / a
        let g = (Double(c00.g) * a00 + Double(c10.g) * a10 + Double(c01.g) * a01 + Double(c11.g) * a11) / a
        let b = (Double(c00.b) * a00 + Double(c10.b) * a10 + Double(c01.b) * a01 + Double(c11.b) * a11) / a
        return ColorBgra(b: clampToByte(b), g: clampToByte(g), r: clampToByte(r), a: clampToByte(a))
    }

    // MARK: - CoreGraphics interop

    public static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Creates a straight-alpha CGImage of the whole surface (copy).
    public func makeCGImage() -> CGImage? {
        makeCGImage(rect: bounds)
    }

    public func makeCGImage(rect: IntRect) -> CGImage? {
        let r = rect.intersection(bounds)
        if r.isEmpty { return nil }
        let data = NSMutableData(length: r.width * r.height * 4)!
        let dst = data.mutableBytes.bindMemory(to: ColorBgra.self, capacity: r.width * r.height)
        for y in 0..<r.height {
            (dst + y * r.width).update(from: row(r.top + y) + r.left, count: r.width)
        }
        guard let provider = CGDataProvider(data: data) else { return nil }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.first.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        return CGImage(width: r.width, height: r.height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: r.width * 4, space: Surface.sRGB, bitmapInfo: info, provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Creates a premultiplied CGImage, which CoreGraphics draws faster.
    public func makePremultipliedCGImage(rect: IntRect) -> CGImage? {
        let r = rect.intersection(bounds)
        if r.isEmpty { return nil }
        let data = NSMutableData(length: r.width * r.height * 4)!
        let dst = data.mutableBytes.bindMemory(to: ColorBgra.self, capacity: r.width * r.height)
        for y in 0..<r.height {
            let s = row(r.top + y) + r.left
            let d = dst + y * r.width
            for x in 0..<r.width {
                let c = s[x]
                if c.a == 255 {
                    d[x] = c
                } else if c.a == 0 {
                    d[x] = .transparent
                } else {
                    let a = Int(c.a)
                    d[x] = ColorBgra(b: UInt8(mul255(Int(c.b), a)), g: UInt8(mul255(Int(c.g), a)),
                                     r: UInt8(mul255(Int(c.r), a)), a: c.a)
                }
            }
        }
        guard let provider = CGDataProvider(data: data) else { return nil }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        return CGImage(width: r.width, height: r.height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: r.width * 4, space: Surface.sRGB, bitmapInfo: info, provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Decodes any CGImage into a new straight-alpha surface (sRGB).
    public convenience init?(cgImage: CGImage) {
        let w = cgImage.width, h = cgImage.height
        guard w > 0, h > 0 else { return nil }
        self.init(width: w, height: h)
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(data: pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: Surface.sRGB, bitmapInfo: info) else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        unpremultiply(rect: bounds)
    }

    /// Converts premultiplied data in place to straight alpha.
    public func unpremultiply(rect: IntRect) {
        let r = rect.intersection(bounds)
        for y in r.top..<r.bottom {
            let p = row(y)
            for x in r.left..<r.right {
                let c = p[x]
                if c.a == 255 || c.a == 0 { continue }
                let a = Int(c.a)
                p[x] = ColorBgra(b: UInt8(min(255, (Int(c.b) * 255 + a / 2) / a)),
                                 g: UInt8(min(255, (Int(c.g) * 255 + a / 2) / a)),
                                 r: UInt8(min(255, (Int(c.r) * 255 + a / 2) / a)), a: c.a)
            }
        }
    }

    /// Converts straight data in place to premultiplied alpha.
    public func premultiply(rect: IntRect) {
        let r = rect.intersection(bounds)
        for y in r.top..<r.bottom {
            let p = row(y)
            for x in r.left..<r.right {
                let c = p[x]
                if c.a == 255 { continue }
                let a = Int(c.a)
                p[x] = ColorBgra(b: UInt8(mul255(Int(c.b), a)), g: UInt8(mul255(Int(c.g), a)),
                                 r: UInt8(mul255(Int(c.r), a)), a: c.a)
            }
        }
    }

    /// Runs `body` with a premultiplied CGContext (y-down, origin top-left) that wraps a scratch copy,
    /// then writes the result back as straight alpha.
    public func drawWithCoreGraphics(_ body: (CGContext) -> Void) {
        premultiply(rect: bounds)
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        if let ctx = CGContext(data: pixels, width: width, height: height, bitsPerComponent: 8,
                               bytesPerRow: width * 4, space: Surface.sRGB, bitmapInfo: info) {
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: 1, y: -1)
            body(ctx)
        }
        unpremultiply(rect: bounds)
    }

    /// Fully opaque check over an area.
    public func isOpaque(rect: IntRect) -> Bool {
        let r = rect.intersection(bounds)
        for y in r.top..<r.bottom {
            let p = row(y)
            for x in r.left..<r.right where p[x].a != 255 { return false }
        }
        return true
    }

    /// Exact pixel equality for tests and change detection.
    public func contentEquals(_ o: Surface) -> Bool {
        guard o.width == width, o.height == height else { return false }
        return memcmp(pixels, o.pixels, byteCount) == 0
    }

    /// Bounding rectangle of all pixels with non-zero alpha (nil if fully transparent).
    public func opaqueBounds() -> IntRect? {
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let p = row(y)
            for x in 0..<width where p[x].a != 0 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        if maxX < 0 { return nil }
        return IntRect(left: minX, top: minY, right: maxX + 1, bottom: maxY + 1)
    }
}

/// 8-bit coverage mask, used for selections, brush strokes and flood fills.
public final class MaskSurface {
    public let width: Int
    public let height: Int
    public let data: UnsafeMutablePointer<UInt8>

    public init(width: Int, height: Int, fill: UInt8 = 0) {
        precondition(width > 0 && height > 0)
        self.width = width
        self.height = height
        data = .allocate(capacity: width * height)
        data.initialize(repeating: fill, count: width * height)
    }

    deinit { data.deallocate() }

    public var bounds: IntRect { IntRect(x: 0, y: 0, width: width, height: height) }

    @inline(__always) public func row(_ y: Int) -> UnsafeMutablePointer<UInt8> { data + y * width }

    @inline(__always) public subscript(x: Int, y: Int) -> UInt8 {
        get { data[y * width + x] }
        set { data[y * width + x] = newValue }
    }

    public func clear(_ v: UInt8 = 0) { data.update(repeating: v, count: width * height) }

    public func clone() -> MaskSurface {
        let m = MaskSurface(width: width, height: height)
        m.data.update(from: data, count: width * height)
        return m
    }

    /// Bounds of non-zero coverage.
    public func nonZeroBounds() -> IntRect? {
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let p = row(y)
            for x in 0..<width where p[x] != 0 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        if maxX < 0 { return nil }
        return IntRect(left: minX, top: minY, right: maxX + 1, bottom: maxY + 1)
    }

    /// Rasterizes a path into a fresh mask of the given size (y-down image coordinates).
    public static func rasterize(path: CGPath, width: Int, height: Int, antialias: Bool,
                                 fillRule: CGPathFillRule = .evenOdd) -> MaskSurface {
        let m = MaskSurface(width: width, height: height)
        m.fill(path: path, antialias: antialias, fillRule: fillRule)
        return m
    }

    /// Fills the path with full coverage into this mask (additive, using CoreGraphics).
    public func fill(path: CGPath, antialias: Bool, fillRule: CGPathFillRule = .evenOdd) {
        let gray = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(data: data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                  space: gray, bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.setShouldAntialias(antialias)
        ctx.setAllowsAntialiasing(antialias)
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.addPath(path)
        ctx.fillPath(using: fillRule)
    }

    /// Strokes the path into this mask.
    public func stroke(path: CGPath, width lineWidth: CGFloat, antialias: Bool, cap: CGLineCap = .round,
                       join: CGLineJoin = .round, dash: [CGFloat] = []) {
        let gray = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(data: data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                  space: gray, bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.setShouldAntialias(antialias)
        ctx.setAllowsAntialiasing(antialias)
        ctx.setStrokeColor(gray: 1, alpha: 1)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(cap)
        ctx.setLineJoin(join)
        if !dash.isEmpty { ctx.setLineDash(phase: 0, lengths: dash) }
        ctx.addPath(path)
        ctx.strokePath()
    }

    /// Runs drawing code in an 8-bit gray context mapped onto this mask (y-down).
    public func draw(antialias: Bool, _ body: (CGContext) -> Void) {
        let gray = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(data: data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                  space: gray, bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.setShouldAntialias(antialias)
        ctx.setAllowsAntialiasing(antialias)
        body(ctx)
    }
}
