import AppKit

/// All UI icons. Drawn in code (or tinted SF Symbols) so the app ships without image assets.
enum Icons {
    private static var cache: [String: NSImage] = [:]

    static func image(_ name: String, size: CGFloat = 16) -> NSImage {
        let key = "\(name)@\(size)"
        if let img = cache[key] { return img }
        let img = make(name, size: size)
        cache[key] = img
        return img
    }

    // MARK: Palette

    static let blue = NSColor(srgbRed: 0.16, green: 0.45, blue: 0.85, alpha: 1)
    static let lightBlue = NSColor(srgbRed: 0.55, green: 0.75, blue: 0.98, alpha: 1)
    static let red = NSColor(srgbRed: 0.86, green: 0.2, blue: 0.18, alpha: 1)
    static let green = NSColor(srgbRed: 0.2, green: 0.65, blue: 0.25, alpha: 1)
    static let yellow = NSColor(srgbRed: 0.98, green: 0.78, blue: 0.15, alpha: 1)
    static let orange = NSColor(srgbRed: 0.96, green: 0.55, blue: 0.12, alpha: 1)
    static let purple = NSColor(srgbRed: 0.55, green: 0.3, blue: 0.8, alpha: 1)
    static let gray = NSColor(srgbRed: 0.45, green: 0.47, blue: 0.5, alpha: 1)
    static let dark = NSColor(srgbRed: 0.2, green: 0.22, blue: 0.25, alpha: 1)
    static let wood = NSColor(srgbRed: 0.72, green: 0.5, blue: 0.28, alpha: 1)

    private static func symbol(_ name: String, size: CGFloat, colors: [NSColor], weight: NSFont.Weight = .regular) -> NSImage {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            return drawn(size) { _ in }
        }
        let cfg = NSImage.SymbolConfiguration(pointSize: size * 0.82, weight: weight)
            .applying(NSImage.SymbolConfiguration(paletteColors: colors))
        let img = base.withSymbolConfiguration(cfg) ?? base
        // Center in a square canvas so every icon has the same footprint.
        return drawn(size) { r in
            let s = img.size
            let scale = min(r.width / max(s.width, 1), r.height / max(s.height, 1), 1)
            let w = s.width * scale, h = s.height * scale
            img.draw(in: NSRect(x: (r.width - w) / 2, y: (r.height - h) / 2, width: w, height: h))
        }
    }

    /// Custom icon drawn in a 16×16 design space (y up), scaled to `size`.
    private static func drawn(_ size: CGFloat, _ body: @escaping (NSRect) -> Void) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
            body(r)
            return true
        }
    }

    private static func vector(_ size: CGFloat, _ body: @escaping () -> Void) -> NSImage {
        drawn(size) { r in
            NSGraphicsContext.saveGraphicsState()
            let t = NSAffineTransform()
            t.scale(by: r.width / 16)
            t.concat()
            body()
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private static func dashedRect(_ r: NSRect, color: NSColor = dark) {
        let p = NSBezierPath(rect: r)
        p.lineWidth = 1.2
        NSColor.white.setStroke()
        p.stroke()
        p.setLineDash([2, 1.5], count: 2, phase: 0)
        color.setStroke()
        p.stroke()
    }

    private static func dashedOval(_ r: NSRect) {
        let p = NSBezierPath(ovalIn: r)
        p.lineWidth = 1.2
        NSColor.white.setStroke()
        p.stroke()
        p.setLineDash([2, 1.5], count: 2, phase: 0)
        dark.setStroke()
        p.stroke()
    }

    private static func arrowCross(center c: NSPoint, radius r: CGFloat, color: NSColor) {
        let p = NSBezierPath()
        p.lineWidth = 1.3
        p.move(to: NSPoint(x: c.x - r, y: c.y)); p.line(to: NSPoint(x: c.x + r, y: c.y))
        p.move(to: NSPoint(x: c.x, y: c.y - r)); p.line(to: NSPoint(x: c.x, y: c.y + r))
        color.setStroke()
        p.stroke()
        let a: CGFloat = 2.2
        let heads = NSBezierPath()
        for (dx, dy) in [(1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0)] {
            let tip = NSPoint(x: c.x + r * dx, y: c.y + r * dy)
            heads.move(to: tip)
            heads.line(to: NSPoint(x: tip.x - a * dx - a * dy, y: tip.y - a * dy - a * dx))
            heads.line(to: NSPoint(x: tip.x - a * dx + a * dy, y: tip.y - a * dy + a * dx))
            heads.close()
        }
        color.setFill()
        heads.fill()
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private static func make(_ name: String, size: CGFloat) -> NSImage {
        switch name {
        // MARK: Tools
        case "tool.moveSelectedPixels":
            return vector(size) {
                NSColor(srgbRed: 0.62, green: 0.8, blue: 1, alpha: 1).setFill()
                NSBezierPath(rect: NSRect(x: 1.5, y: 1.5, width: 9, height: 9)).fill()
                dashedRect(NSRect(x: 1.5, y: 1.5, width: 9, height: 9))
                arrowCross(center: NSPoint(x: 10.5, y: 10.5), radius: 5, color: blue)
            }
        case "tool.moveSelection":
            return vector(size) {
                dashedRect(NSRect(x: 1.5, y: 1.5, width: 9, height: 9))
                arrowCross(center: NSPoint(x: 10.5, y: 10.5), radius: 5, color: dark)
            }
        case "tool.rectangleSelect":
            return vector(size) { dashedRect(NSRect(x: 1.5, y: 3.5, width: 13, height: 9)) }
        case "tool.ellipseSelect":
            return vector(size) { dashedOval(NSRect(x: 1.5, y: 3, width: 13, height: 10)) }
        case "tool.lassoSelect":
            return vector(size) {
                let p = NSBezierPath()
                p.move(to: NSPoint(x: 4, y: 4))
                p.curve(to: NSPoint(x: 2, y: 11), controlPoint1: NSPoint(x: 0.5, y: 5), controlPoint2: NSPoint(x: 0.5, y: 9))
                p.curve(to: NSPoint(x: 13, y: 12), controlPoint1: NSPoint(x: 4, y: 15), controlPoint2: NSPoint(x: 11, y: 15))
                p.curve(to: NSPoint(x: 8, y: 5), controlPoint1: NSPoint(x: 15, y: 9), controlPoint2: NSPoint(x: 12, y: 5))
                p.curve(to: NSPoint(x: 4, y: 1), controlPoint1: NSPoint(x: 5, y: 5), controlPoint2: NSPoint(x: 3, y: 3))
                p.lineWidth = 1.2
                NSColor.white.setStroke(); p.stroke()
                p.setLineDash([2, 1.5], count: 2, phase: 0)
                dark.setStroke(); p.stroke()
            }
        case "tool.magicWand":
            return vector(size) {
                let wand = NSBezierPath()
                wand.move(to: NSPoint(x: 2, y: 2)); wand.line(to: NSPoint(x: 10, y: 10))
                wand.lineWidth = 2.4
                wand.lineCapStyle = .round
                dark.setStroke(); wand.stroke()
                let tip = NSBezierPath()
                tip.move(to: NSPoint(x: 8.5, y: 8.5)); tip.line(to: NSPoint(x: 10.5, y: 10.5))
                tip.lineWidth = 2.4; tip.lineCapStyle = .round
                NSColor.white.setStroke(); tip.stroke()
                yellow.setFill()
                star(center: NSPoint(x: 12.5, y: 12.5), outer: 3.4, inner: 1.4, points: 4).fill()
                lightBlue.setFill()
                star(center: NSPoint(x: 13.5, y: 5.5), outer: 2, inner: 0.8, points: 4).fill()
                star(center: NSPoint(x: 5.5, y: 13.5), outer: 1.8, inner: 0.7, points: 4).fill()
            }
        case "tool.zoom": return symbol("magnifyingglass", size: size, colors: [blue])
        case "tool.pan": return symbol("hand.raised.fill", size: size, colors: [NSColor(srgbRed: 0.95, green: 0.78, blue: 0.62, alpha: 1)])
        case "tool.paintBucket":
            return vector(size) {
                let bucket = NSBezierPath()
                bucket.move(to: NSPoint(x: 2, y: 9))
                bucket.line(to: NSPoint(x: 7.5, y: 14.5))
                bucket.line(to: NSPoint(x: 13, y: 9))
                bucket.line(to: NSPoint(x: 7.5, y: 3.5))
                bucket.close()
                NSColor(srgbRed: 0.85, green: 0.87, blue: 0.9, alpha: 1).setFill(); bucket.fill()
                gray.setStroke(); bucket.lineWidth = 1; bucket.stroke()
                let paint = NSBezierPath()
                paint.move(to: NSPoint(x: 2, y: 9)); paint.line(to: NSPoint(x: 13, y: 9))
                paint.line(to: NSPoint(x: 7.5, y: 3.5)); paint.close()
                blue.setFill(); paint.fill()
                let drop = NSBezierPath()
                drop.move(to: NSPoint(x: 13.8, y: 8))
                drop.curve(to: NSPoint(x: 13.8, y: 2.5), controlPoint1: NSPoint(x: 15.6, y: 5), controlPoint2: NSPoint(x: 15.6, y: 2.5))
                drop.curve(to: NSPoint(x: 13.8, y: 8), controlPoint1: NSPoint(x: 12, y: 2.5), controlPoint2: NSPoint(x: 12, y: 5))
                blue.setFill(); drop.fill()
            }
        case "tool.gradient":
            return vector(size) {
                let r = NSRect(x: 1.5, y: 2.5, width: 13, height: 11)
                NSGradient(starting: dark, ending: NSColor.white)?.draw(in: NSBezierPath(rect: r), angle: 0)
                gray.setStroke()
                NSBezierPath(rect: r).stroke()
            }
        case "tool.paintbrush":
            return vector(size) {
                let handle = NSBezierPath()
                handle.move(to: NSPoint(x: 14.5, y: 14.5)); handle.line(to: NSPoint(x: 7, y: 7))
                handle.lineWidth = 2.6; handle.lineCapStyle = .round
                wood.setStroke(); handle.stroke()
                let ferrule = NSBezierPath()
                ferrule.move(to: NSPoint(x: 7.8, y: 7.8)); ferrule.line(to: NSPoint(x: 5.8, y: 5.8))
                ferrule.lineWidth = 3; gray.setStroke(); ferrule.stroke()
                let tip = NSBezierPath()
                tip.move(to: NSPoint(x: 6.5, y: 4.5))
                tip.curve(to: NSPoint(x: 1, y: 1), controlPoint1: NSPoint(x: 3, y: 6), controlPoint2: NSPoint(x: 1.5, y: 4))
                tip.curve(to: NSPoint(x: 4.5, y: 6.5), controlPoint1: NSPoint(x: 4, y: 1.5), controlPoint2: NSPoint(x: 6, y: 3))
                tip.close()
                red.setFill(); tip.fill()
            }
        case "tool.eraser":
            return vector(size) {
                let body = NSBezierPath()
                body.move(to: NSPoint(x: 2, y: 7)); body.line(to: NSPoint(x: 8, y: 13))
                body.line(to: NSPoint(x: 14, y: 7)); body.line(to: NSPoint(x: 8, y: 1)); body.close()
                NSColor(srgbRed: 0.98, green: 0.6, blue: 0.68, alpha: 1).setFill(); body.fill()
                let band = NSBezierPath()
                band.move(to: NSPoint(x: 2, y: 7)); band.line(to: NSPoint(x: 5, y: 10))
                band.line(to: NSPoint(x: 11, y: 4)); band.line(to: NSPoint(x: 8, y: 1)); band.close()
                NSColor(srgbRed: 0.35, green: 0.55, blue: 0.95, alpha: 1).setFill(); band.fill()
                gray.setStroke(); body.lineWidth = 0.8; body.stroke()
            }
        case "tool.pencil":
            return vector(size) {
                let body = NSBezierPath()
                body.move(to: NSPoint(x: 4, y: 3)); body.line(to: NSPoint(x: 13.5, y: 12.5))
                body.lineWidth = 3.4
                yellow.setStroke(); body.stroke()
                let tip = NSBezierPath()
                tip.move(to: NSPoint(x: 1, y: 1)); tip.line(to: NSPoint(x: 5.4, y: 2.4)); tip.line(to: NSPoint(x: 2.4, y: 5.4)); tip.close()
                NSColor(srgbRed: 0.95, green: 0.85, blue: 0.7, alpha: 1).setFill(); tip.fill()
                let lead = NSBezierPath()
                lead.move(to: NSPoint(x: 1, y: 1)); lead.line(to: NSPoint(x: 2.6, y: 1.5)); lead.line(to: NSPoint(x: 1.5, y: 2.6)); lead.close()
                dark.setFill(); lead.fill()
                let end = NSBezierPath()
                end.move(to: NSPoint(x: 12.4, y: 11.4)); end.line(to: NSPoint(x: 14.6, y: 13.6))
                end.lineWidth = 3.4; red.setStroke(); end.stroke()
            }
        case "tool.colorPicker": return symbol("eyedropper.halffull", size: size, colors: [dark, blue])
        case "tool.cloneStamp":
            return vector(size) {
                let handle = NSBezierPath(roundedRect: NSRect(x: 6, y: 7, width: 4, height: 6), xRadius: 1.5, yRadius: 1.5)
                wood.setFill(); handle.fill()
                let knob = NSBezierPath(ovalIn: NSRect(x: 5, y: 11.5, width: 6, height: 4))
                wood.setFill(); knob.fill()
                let base = NSBezierPath(roundedRect: NSRect(x: 2, y: 3, width: 12, height: 4.5), xRadius: 1, yRadius: 1)
                gray.setFill(); base.fill()
                let pad = NSBezierPath(rect: NSRect(x: 2, y: 1.5, width: 12, height: 1.8))
                red.setFill(); pad.fill()
            }
        case "tool.recolor":
            return vector(size) {
                let a = NSBezierPath(ovalIn: NSRect(x: 1, y: 6, width: 8, height: 8))
                red.setFill(); a.fill()
                let b = NSBezierPath(ovalIn: NSRect(x: 7, y: 2, width: 8, height: 8))
                blue.setFill(); b.fill()
                let arrow = NSBezierPath()
                arrow.move(to: NSPoint(x: 3, y: 4)); arrow.curve(to: NSPoint(x: 6, y: 1.5), controlPoint1: NSPoint(x: 3, y: 2.5), controlPoint2: NSPoint(x: 4, y: 1.5))
                arrow.lineWidth = 1.2; dark.setStroke(); arrow.stroke()
                let head = NSBezierPath()
                head.move(to: NSPoint(x: 7, y: 1.5)); head.line(to: NSPoint(x: 5, y: 3)); head.line(to: NSPoint(x: 5, y: 0)); head.close()
                dark.setFill(); head.fill()
            }
        case "tool.text":
            return drawn(size) { r in
                let font = NSFont(name: "Times New Roman Bold", size: r.height * 0.95) ?? NSFont.boldSystemFont(ofSize: r.height * 0.9)
                let s = NSAttributedString(string: "A", attributes: [.font: font, .foregroundColor: dark])
                let sz = s.size()
                s.draw(at: NSPoint(x: (r.width - sz.width) / 2, y: (r.height - sz.height) / 2))
            }
        case "tool.lineCurve":
            return vector(size) {
                let p = NSBezierPath()
                p.move(to: NSPoint(x: 1.5, y: 2))
                p.curve(to: NSPoint(x: 14.5, y: 14), controlPoint1: NSPoint(x: 12, y: 0), controlPoint2: NSPoint(x: 3, y: 16))
                p.lineWidth = 1.6
                blue.setStroke(); p.stroke()
                for pt in [NSPoint(x: 1.5, y: 2), NSPoint(x: 14.5, y: 14)] {
                    let h = NSBezierPath(rect: NSRect(x: pt.x - 1.3, y: pt.y - 1.3, width: 2.6, height: 2.6))
                    NSColor.white.setFill(); h.fill(); dark.setStroke(); h.lineWidth = 0.7; h.stroke()
                }
            }
        case "tool.shapes":
            return vector(size) {
                let rect = NSBezierPath(rect: NSRect(x: 1.5, y: 5.5, width: 8, height: 8))
                blue.setFill(); rect.fill()
                let oval = NSBezierPath(ovalIn: NSRect(x: 6, y: 1.5, width: 9, height: 9))
                yellow.withAlphaComponent(0.9).setFill(); oval.fill()
                orange.setStroke(); oval.lineWidth = 0.8; oval.stroke()
            }

        // MARK: Commands
        case "cmd.new": return symbol("doc.badge.plus", size: size, colors: [green, gray])
        case "cmd.open": return symbol("folder.fill", size: size, colors: [yellow])
        case "cmd.save": return symbol("square.and.arrow.down", size: size, colors: [blue], weight: .semibold)
        case "cmd.saveAs": return symbol("square.and.arrow.down.on.square", size: size, colors: [blue])
        case "cmd.print": return symbol("printer.fill", size: size, colors: [gray])
        case "cmd.cut": return symbol("scissors", size: size, colors: [red])
        case "cmd.copy": return symbol("doc.on.doc", size: size, colors: [blue])
        case "cmd.copyMerged": return symbol("square.on.square", size: size, colors: [purple])
        case "cmd.paste": return symbol("doc.on.clipboard", size: size, colors: [wood])
        case "cmd.crop": return symbol("crop", size: size, colors: [dark])
        case "cmd.deselect":
            return vector(size) {
                dashedRect(NSRect(x: 1.5, y: 3.5, width: 11, height: 9))
                let x = NSBezierPath()
                x.move(to: NSPoint(x: 9, y: 1)); x.line(to: NSPoint(x: 15, y: 7))
                x.move(to: NSPoint(x: 15, y: 1)); x.line(to: NSPoint(x: 9, y: 7))
                x.lineWidth = 1.8; red.setStroke(); x.stroke()
            }
        case "cmd.selectAll":
            return vector(size) {
                NSColor(srgbRed: 0.62, green: 0.8, blue: 1, alpha: 1).setFill()
                NSBezierPath(rect: NSRect(x: 1.5, y: 1.5, width: 13, height: 13)).fill()
                dashedRect(NSRect(x: 1.5, y: 1.5, width: 13, height: 13))
            }
        case "cmd.invertSelection":
            return vector(size) {
                NSColor(srgbRed: 0.62, green: 0.8, blue: 1, alpha: 1).setFill()
                NSBezierPath(rect: NSRect(x: 1.5, y: 1.5, width: 13, height: 13)).fill()
                NSColor.white.setFill()
                NSBezierPath(rect: NSRect(x: 5, y: 5, width: 6, height: 6)).fill()
                dashedRect(NSRect(x: 1.5, y: 1.5, width: 13, height: 13))
                dashedRect(NSRect(x: 5, y: 5, width: 6, height: 6))
            }
        case "cmd.eraseSelection":
            return vector(size) {
                dashedRect(NSRect(x: 1.5, y: 1.5, width: 13, height: 13))
                let x = NSBezierPath()
                x.move(to: NSPoint(x: 4.5, y: 4.5)); x.line(to: NSPoint(x: 11.5, y: 11.5))
                x.move(to: NSPoint(x: 11.5, y: 4.5)); x.line(to: NSPoint(x: 4.5, y: 11.5))
                x.lineWidth = 2; red.setStroke(); x.stroke()
            }
        case "cmd.fillSelection":
            return vector(size) {
                blue.setFill()
                NSBezierPath(rect: NSRect(x: 1.5, y: 1.5, width: 13, height: 13)).fill()
                dashedRect(NSRect(x: 1.5, y: 1.5, width: 13, height: 13))
            }
        case "cmd.undo": return symbol("arrow.uturn.backward", size: size, colors: [blue], weight: .semibold)
        case "cmd.redo": return symbol("arrow.uturn.forward", size: size, colors: [blue], weight: .semibold)
        case "cmd.grid": return symbol("grid", size: size, colors: [gray])
        case "cmd.rulers": return symbol("ruler", size: size, colors: [wood])
        case "cmd.resize": return symbol("arrow.up.left.and.arrow.down.right", size: size, colors: [blue])
        case "cmd.canvasSize": return symbol("aspectratio", size: size, colors: [blue])
        case "cmd.flipH": return symbol("arrow.left.and.right.righttriangle.left.righttriangle.right", size: size, colors: [blue, gray])
        case "cmd.flipV": return symbol("arrow.up.and.down.righttriangle.up.righttriangle.down", size: size, colors: [blue, gray])
        case "cmd.rotateCW": return symbol("rotate.right", size: size, colors: [blue])
        case "cmd.rotateCCW": return symbol("rotate.left", size: size, colors: [blue])
        case "cmd.rotate180": return symbol("arrow.triangle.2.circlepath", size: size, colors: [blue])
        case "cmd.flatten": return symbol("square.3.layers.3d.down.right", size: size, colors: [blue, gray])
        case "cmd.zoomIn": return symbol("plus.magnifyingglass", size: size, colors: [blue])
        case "cmd.zoomOut": return symbol("minus.magnifyingglass", size: size, colors: [blue])
        case "cmd.zoomFit": return symbol("arrow.up.left.and.down.right.and.arrow.up.right.and.down.left", size: size, colors: [blue])
        case "cmd.actualSize": return symbol("1.magnifyingglass", size: size, colors: [blue])
        case "cmd.settings": return symbol("gearshape", size: size, colors: [gray])
        case "cmd.help": return symbol("questionmark.circle.fill", size: size, colors: [.white, blue])
        case "cmd.adjustments": return symbol("circle.lefthalf.filled", size: size, colors: [orange])
        case "cmd.effects": return symbol("sparkles", size: size, colors: [purple])
        case "cmd.paletteOpen": return symbol("swatchpalette", size: size, colors: [orange])
        case "cmd.swapColors": return symbol("arrow.left.arrow.right", size: size, colors: [dark])

        // MARK: Layers
        case "layer.add": return layerIcon(size, badge: "plus", badgeColor: green)
        case "layer.delete": return layerIcon(size, badge: "xmark", badgeColor: red)
        case "layer.duplicate": return layerIcon(size, badge: "square.on.square", badgeColor: blue)
        case "layer.merge": return layerIcon(size, badge: "arrow.down", badgeColor: blue)
        case "layer.up": return layerIcon(size, badge: "arrow.up", badgeColor: blue)
        case "layer.down": return layerIcon(size, badge: "arrow.down", badgeColor: purple)
        case "layer.properties": return layerIcon(size, badge: "slider.horizontal.3", badgeColor: gray)
        case "layer.import": return layerIcon(size, badge: "folder", badgeColor: yellow)
        case "layer.rotateZoom": return layerIcon(size, badge: "rotate.right", badgeColor: blue)
        case "layer.flipH": return layerIcon(size, badge: "arrow.left.and.right", badgeColor: blue)
        case "layer.flipV": return layerIcon(size, badge: "arrow.up.and.down", badgeColor: blue)
        case "layer.generic": return layerIcon(size, badge: nil, badgeColor: blue)

        // MARK: Windows & history
        case "window.tools": return symbol("paintbrush.pointed.fill", size: size, colors: [red])
        case "window.history": return symbol("clock.arrow.circlepath", size: size, colors: [blue])
        case "window.layers": return symbol("square.3.layers.3d", size: size, colors: [blue])
        case "window.colors": return symbol("paintpalette.fill", size: size, colors: [orange])
        case "history.new": return symbol("doc.badge.plus", size: size, colors: [green, gray])
        case "history.open": return symbol("folder.fill", size: size, colors: [yellow])
        case "history.selection": return image("tool.rectangleSelect", size: size)
        case "history.paste": return image("cmd.paste", size: size)
        case "history.effect": return symbol("sparkles", size: size, colors: [purple])
        case "history.adjustment": return symbol("circle.lefthalf.filled", size: size, colors: [orange])

        // MARK: Option bar glyphs
        case "selmode.replace", "selmode.union", "selmode.exclude", "selmode.intersect", "selmode.xor":
            return selectionModeIcon(String(name.dropFirst(8)), size: size)
        case "flood.contiguous":
            return vector(size) {
                blue.setFill()
                NSBezierPath(roundedRect: NSRect(x: 2, y: 3, width: 12, height: 10), xRadius: 4, yRadius: 4).fill()
            }
        case "flood.global":
            return vector(size) {
                blue.setFill()
                for (x, y) in [(1.5, 9.5), (9.5, 10.0), (5.0, 2.5), (11.0, 3.0)] {
                    NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 4.5, height: 4.5)).fill()
                }
            }
        case "drawtype.outline":
            return vector(size) {
                let p = NSBezierPath(rect: NSRect(x: 2.5, y: 3.5, width: 11, height: 9))
                p.lineWidth = 1.6; blue.setStroke(); p.stroke()
            }
        case "drawtype.filled":
            return vector(size) {
                blue.setFill(); NSBezierPath(rect: NSRect(x: 2, y: 3, width: 12, height: 10)).fill()
            }
        case "drawtype.filledWithOutline":
            return vector(size) {
                let p = NSBezierPath(rect: NSRect(x: 2.5, y: 3.5, width: 11, height: 9))
                lightBlue.setFill(); p.fill()
                p.lineWidth = 1.6; blue.setStroke(); p.stroke()
            }
        case "gradient.colorMode":
            return vector(size) {
                NSGradient(starting: red, ending: blue)?.draw(in: NSRect(x: 1.5, y: 3, width: 13, height: 10), angle: 0)
            }
        case "gradient.transparencyMode":
            return drawn(size) { r in
                let rr = r.insetBy(dx: r.width * 0.1, dy: r.height * 0.2)
                Checkerboard.draw(in: rr, cell: 3)
                NSGradient(starting: dark, ending: dark.withAlphaComponent(0))?.draw(in: rr, angle: 0)
            }

        default:
            if name.hasPrefix("gradient."), let t = GradientType.allCases.first(where: { "gradient.\($0)" == name }) {
                return gradientIcon(t, size: size)
            }
            if name.hasPrefix("sym.") {
                return symbol(String(name.dropFirst(4)), size: size, colors: [NSColor.labelColor])
            }
            if name.hasPrefix("effect.") {
                return symbol("sparkles", size: size, colors: [purple])
            }
            return symbol("questionmark.square.dashed", size: size, colors: [gray])
        }
    }

    private static func layerIcon(_ size: CGFloat, badge: String?, badgeColor: NSColor) -> NSImage {
        drawn(size) { r in
            NSGraphicsContext.saveGraphicsState()
            let t = NSAffineTransform()
            t.scale(by: r.width / 16)
            t.concat()
            for (i, alpha) in [(0, 0.55), (1, 1.0)] {
                let y = CGFloat(i) * 3.5 + 2
                let p = NSBezierPath()
                p.move(to: NSPoint(x: 1, y: y + 3))
                p.line(to: NSPoint(x: 7, y: y + 6))
                p.line(to: NSPoint(x: 13, y: y + 3))
                p.line(to: NSPoint(x: 7, y: y))
                p.close()
                lightBlue.withAlphaComponent(alpha).setFill(); p.fill()
                blue.setStroke(); p.lineWidth = 0.8; p.stroke()
            }
            NSGraphicsContext.restoreGraphicsState()
            if let badge, let sym = NSImage(systemSymbolName: badge, accessibilityDescription: nil) {
                let cfg = NSImage.SymbolConfiguration(pointSize: r.width * 0.5, weight: .bold)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [badgeColor]))
                let img = sym.withSymbolConfiguration(cfg) ?? sym
                let s = r.width * 0.55
                NSColor.white.withAlphaComponent(0.9).setFill()
                NSBezierPath(ovalIn: NSRect(x: r.width - s - 0.5, y: 0, width: s + 0.5, height: s + 0.5)).fill()
                img.draw(in: NSRect(x: r.width - s, y: 0.25, width: s * 0.95, height: s * 0.95))
            }
        }
    }

    private static func selectionModeIcon(_ mode: String, size: CGFloat) -> NSImage {
        vector(size) {
            let a = NSRect(x: 1.5, y: 5.5, width: 8, height: 8), b = NSRect(x: 6.5, y: 2.5, width: 8, height: 8)
            let overlap = a.intersection(b)
            let fill = NSColor(srgbRed: 0.45, green: 0.7, blue: 1, alpha: 1)
            fill.setFill()
            switch mode {
            case "replace": b.fill()
            case "union": a.fill(); b.fill()
            case "exclude":
                a.fill()
                NSColor.clear.setFill()
                overlap.fill(using: .copy)
            case "intersect": overlap.fill()
            default:
                a.fill(); b.fill()
                NSColor.clear.setFill()
                overlap.fill(using: .copy)
            }
            for r in mode == "replace" ? [b] : [a, b] {
                let p = NSBezierPath(rect: r)
                p.lineWidth = 1
                dark.setStroke()
                p.stroke()
            }
        }
    }

    private static func gradientIcon(_ t: GradientType, size: CGFloat) -> NSImage {
        let n = Int(size * 2)
        let img = NSImage(size: NSSize(width: size, height: size))
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: n, pixelsHigh: n, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let c = Double(n) / 2
        for y in 0..<n {
            for x in 0..<n {
                let dx = (Double(x) + 0.5 - c) / c, dy = (Double(y) + 0.5 - c) / c
                var v: Double
                switch t {
                case .linear: v = (dx + 1) / 2
                case .linearReflected: v = abs(dx)
                case .linearDiamond: v = min(1, abs(dx) + abs(dy))
                case .radial: v = min(1, sqrt(dx * dx + dy * dy))
                case .conical: v = abs(atan2(dy, dx)) / .pi
                case .spiralClockwise, .spiralCounterclockwise:
                    let a = atan2(dy, dx) * (t == .spiralClockwise ? 1 : -1)
                    let r = sqrt(dx * dx + dy * dy) * 2 + a / (2 * .pi)
                    v = r - floor(r)
                }
                let g = 0.15 + 0.85 * v
                rep.setColor(NSColor(deviceRed: g, green: g, blue: g, alpha: 1), atX: x, y: y)
            }
        }
        img.addRepresentation(rep)
        return img
    }

    static func star(center c: NSPoint, outer: CGFloat, inner: CGFloat, points: Int) -> NSBezierPath {
        let p = NSBezierPath()
        for i in 0..<(points * 2) {
            let r = i % 2 == 0 ? outer : inner
            let a = CGFloat(i) * .pi / CGFloat(points) + .pi / 2
            let pt = NSPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            if i == 0 { p.move(to: pt) } else { p.line(to: pt) }
        }
        p.close()
        return p
    }

    /// Small square swatch showing a color over a checkerboard.
    static func swatch(_ color: NSColor, size: NSSize) -> NSImage {
        NSImage(size: size, flipped: false) { r in
            Checkerboard.draw(in: r, cell: 4)
            color.setFill()
            r.fill(using: .sourceOver)
            NSColor.black.withAlphaComponent(0.5).setStroke()
            NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)).stroke()
            return true
        }
    }
}

/// Transparent-pixel checkerboard used everywhere (canvas, thumbnails, swatches).
enum Checkerboard {
    static let light = NSColor.white
    static let dark = NSColor(white: 0.8, alpha: 1)

    static func draw(in rect: NSRect, cell: CGFloat = 8) {
        light.setFill()
        rect.fill()
        dark.setFill()
        let cols = Int(ceil(rect.width / cell)), rows = Int(ceil(rect.height / cell))
        let path = NSBezierPath()
        for y in 0..<rows {
            for x in 0..<cols where (x + y) % 2 == 1 {
                path.appendRect(NSRect(x: rect.minX + CGFloat(x) * cell, y: rect.minY + CGFloat(y) * cell,
                                       width: cell, height: cell).intersection(rect))
            }
        }
        path.fill()
    }

    /// Pattern color for large areas (aligned to the view's origin).
    static let patternColor: NSColor = {
        let img = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { r in
            draw(in: r, cell: 8)
            return true
        }
        return NSColor(patternImage: img)
    }()
}
