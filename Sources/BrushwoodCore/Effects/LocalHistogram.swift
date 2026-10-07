import Foundation

/// Circular-neighborhood sliding histograms, the engine behind Paint.NET's `LocalHistogramEffect`
/// (Median, Reduce Noise, Sharpen, Outline, Unfocus, Surface Blur).
public enum LocalHistogram {
    public typealias Apply = (_ src: ColorBgra, _ area: Int,
                              _ hb: UnsafeMutablePointer<Int32>, _ hg: UnsafeMutablePointer<Int32>,
                              _ hr: UnsafeMutablePointer<Int32>, _ ha: UnsafeMutablePointer<Int32>) -> ColorBgra

    public static func run(src: Surface, dst: Surface, rect: IntRect, radius rad: Int, apply: Apply) {
        let r = max(0, rad)
        let rect = rect.intersection(src.bounds)
        if rect.isEmpty { return }
        let halfWidths = (0...(2 * r)).map { i -> Int in
            let dy = i - r
            return Int(Double(r * r - dy * dy).squareRoot())
        }
        let w = src.width, h = src.height
        DispatchQueue.concurrentPerform(iterations: rect.height) { iy in
            let y = rect.top + iy
            let hist = UnsafeMutablePointer<Int32>.allocate(capacity: 1024)
            defer { hist.deallocate() }
            hist.initialize(repeating: 0, count: 1024)
            let hb = hist, hg = hist + 256, hr = hist + 512, ha = hist + 768
            var area = 0
            @inline(__always) func add(_ c: ColorBgra) {
                hb[Int(c.b)] += 1; hg[Int(c.g)] += 1; hr[Int(c.r)] += 1; ha[Int(c.a)] += 1
            }
            @inline(__always) func remove(_ c: ColorBgra) {
                hb[Int(c.b)] -= 1; hg[Int(c.g)] -= 1; hr[Int(c.r)] -= 1; ha[Int(c.a)] -= 1
            }
            let x0 = rect.left
            for i in 0...(2 * r) {
                let yy = y + i - r
                if yy < 0 || yy >= h { continue }
                let hw = halfWidths[i]
                let row = src.row(yy)
                let lo = max(0, x0 - hw), hi = min(w - 1, x0 + hw)
                if lo > hi { continue }
                for xx in lo...hi { add(row[xx]); area += 1 }
            }
            let d = dst.row(y), s = src.row(y)
            d[x0] = apply(s[x0], area, hb, hg, hr, ha)
            if rect.width < 2 { return }
            for x in (x0 + 1)..<rect.right {
                for i in 0...(2 * r) {
                    let yy = y + i - r
                    if yy < 0 || yy >= h { continue }
                    let hw = halfWidths[i]
                    let row = src.row(yy)
                    let outX = x - 1 - hw, inX = x + hw
                    if outX >= 0 && outX < w { remove(row[outX]); area -= 1 }
                    if inX >= 0 && inX < w { add(row[inX]); area += 1 }
                }
                d[x] = apply(s[x], area, hb, hg, hr, ha)
            }
        }
    }

    /// Paint.NET's `GetPercentile`.
    @inline(__always)
    public static func percentile(_ percentile: Int, area: Int, _ hb: UnsafeMutablePointer<Int32>,
                                  _ hg: UnsafeMutablePointer<Int32>, _ hr: UnsafeMutablePointer<Int32>,
                                  _ ha: UnsafeMutablePointer<Int32>) -> ColorBgra {
        let minCount = Int32(area * percentile / 100)
        @inline(__always) func p(_ hist: UnsafeMutablePointer<Int32>) -> UInt8 {
            var v = 0, count: Int32 = 0
            while v < 255 && hist[v] == 0 { v += 1 }
            while v < 255 && count < minCount {
                count += hist[v]
                v += 1
            }
            return UInt8(v)
        }
        return ColorBgra(b: p(hb), g: p(hg), r: p(hr), a: p(ha))
    }
}
