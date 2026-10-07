// Helper for scripts/screen-check.sh.
//   swift scripts/check-window.swift make <out.png>      writes the test image (magenta block on white)
//   swift scripts/check-window.swift capture <out.png>   captures Brushwood's main window as the screen shows it
//   swift scripts/check-window.swift verify <capture.png> checks that the image and the tool bar are visible
import AppKit
import CoreGraphics

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: check-window.swift make|capture|verify <png>")
    exit(2)
}
let path = args[2]

func pixels(_ rep: NSBitmapImageRep) -> (Int, Int, (Int, Int) -> (Int, Int, Int)) {
    (rep.pixelsWide, rep.pixelsHigh, { x, y in
        let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) ?? .black
        return (Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    })
}

switch args[1] {
case "make":
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 800, pixelsHigh: 600, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: 800, height: 600).fill()
    NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1).setFill()
    NSRect(x: 200, y: 150, width: 400, height: 300).fill()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))

case "capture":
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    let main = list.filter { ($0[kCGWindowOwnerName as String] as? String ?? "").contains("Brushwood") }
        .max { (($0[kCGWindowBounds as String] as? [String: Any])?["Width"] as? Double ?? 0)
            < (($1[kCGWindowBounds as String] as? [String: Any])?["Width"] as? Double ?? 0) }
    guard let id = main?[kCGWindowNumber as String] as? Int else {
        print("no Brushwood window on screen")
        exit(1)
    }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", "-o", "-l\(id)", path]
    try! p.run()
    p.waitUntilExit()
    exit(p.terminationStatus)

case "verify":
    guard let img = NSImage(contentsOfFile: path), let rep = img.representations.first as? NSBitmapImageRep else {
        print("cannot read capture")
        exit(1)
    }
    let (w, h, px) = pixels(rep)
    var magenta = 0, colorfulTop = 0, total = 0
    for y in stride(from: 0, to: h, by: 2) {
        for x in stride(from: 0, to: w, by: 2) {
            let (r, g, b) = px(x, y)
            total += 1
            // Display color management shifts pure magenta a little (green ≈ 90), so the test is loose.
            if r > 190 && b > 190 && g < 140 { magenta += 1 }
            // Tool bar rows sit in the top ~12% of the window: icons are saturated colors.
            if y < h / 8, max(r, g, b) - min(r, g, b) > 80 { colorfulTop += 1 }
        }
    }
    let magentaShare = Double(magenta) / Double(total)
    print(String(format: "image pixels visible: %.1f%%, colored tool bar pixels: %d", magentaShare * 100, colorfulTop))
    if magentaShare < 0.03 { print("FAIL: the opened image is not visible on screen"); exit(1) }
    if colorfulTop < 50 { print("FAIL: the tool bars are not visible on screen"); exit(1) }
    print("PASS: image and tool bars are visible")

default:
    print("unknown command")
    exit(2)
}
