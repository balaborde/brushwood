import AppKit

/// Brushwood Plus: Brushwood with extra features that depart from Paint.NET. It installs beside Brushwood (its own
/// bundle identifier, so its own settings) and only updates to Plus releases, tagged like v1.0.3-plus.1.
enum Edition {
    static let name = "Brushwood Plus"
    /// The edition part of release tags.
    static let tag = "plus"

    /// Puts the edition's name in interface text, which says "Brushwood" in every language.
    static func brand(_ s: String) -> String {
        s.replacingOccurrences(of: "Brushwood", with: name)
    }

    /// The "+" badge at the top right of the app icon (`scale` = icon size / 1024), so the two apps differ in the Dock.
    /// It stays inside the icon's rounded square, shadow included: macOS 26 shrinks an icon whose drawing goes past
    /// that shape onto a gray plate.
    static func drawBadge(scale s: CGFloat) {
        let c = 765 * s
        func circle(_ r: CGFloat) -> NSBezierPath { NSBezierPath(ovalIn: NSRect(x: c - r * s, y: c - r * s, width: 2 * r * s, height: 2 * r * s)) }
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowBlurRadius = 14 * s
        shadow.shadowOffset = NSSize(width: 0, height: -5 * s)
        shadow.set()
        NSColor.white.setFill()
        circle(110).fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(starting: NSColor(srgbRed: 1, green: 0.62, blue: 0.2, alpha: 1),
                   ending: NSColor(srgbRed: 0.93, green: 0.38, blue: 0.1, alpha: 1))?.draw(in: circle(94), angle: -90)
        NSColor.white.setFill()
        let bar = 44 * s, arm = 120 * s
        NSBezierPath(roundedRect: NSRect(x: c - arm / 2, y: c - bar / 2, width: arm, height: bar), xRadius: bar / 2, yRadius: bar / 2).fill()
        NSBezierPath(roundedRect: NSRect(x: c - bar / 2, y: c - arm / 2, width: bar, height: arm), xRadius: bar / 2, yRadius: bar / 2).fill()
    }
}
