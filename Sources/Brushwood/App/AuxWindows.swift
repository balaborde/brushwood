import AppKit
import BrushwoodCore

/// Application icon drawn in code (also exported to .icns by `scripts/build-app.sh`).
enum AppIcon {
    static var image: NSImage { render(size: 512) }

    static func render(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
            let s = r.width / 1024
            let base = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
            let shape = NSBezierPath(roundedRect: base, xRadius: 185 * s, yRadius: 185 * s)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
            shadow.shadowBlurRadius = 24 * s
            shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
            shadow.set()
            NSColor.white.setFill()
            shape.fill()
            NSGraphicsContext.restoreGraphicsState()
            // Canvas: warm paper with a checker corner to suggest transparency.
            NSGradient(starting: NSColor(srgbRed: 0.99, green: 0.97, blue: 0.93, alpha: 1),
                       ending: NSColor(srgbRed: 0.93, green: 0.89, blue: 0.82, alpha: 1))?.draw(in: shape, angle: -90)
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            // Color strokes.
            let strokes: [(NSColor, CGFloat)] = [(Icons.red, 640), (Icons.yellow, 520), (Icons.blue, 400), (Icons.green, 280)]
            for (c, y) in strokes {
                let p = NSBezierPath()
                p.move(to: NSPoint(x: 170 * s, y: y * s))
                p.curve(to: NSPoint(x: 700 * s, y: (y + 40) * s), controlPoint1: NSPoint(x: 330 * s, y: (y + 110) * s),
                        controlPoint2: NSPoint(x: 520 * s, y: (y - 70) * s))
                p.lineWidth = 78 * s
                p.lineCapStyle = .round
                c.withAlphaComponent(0.92).setStroke()
                p.stroke()
            }
            NSGraphicsContext.restoreGraphicsState()
            // Brush.
            NSGraphicsContext.saveGraphicsState()
            let t = NSAffineTransform()
            t.translateX(by: 640 * s, yBy: 420 * s)
            t.rotate(byDegrees: 40)
            t.concat()
            let handle = NSBezierPath(roundedRect: NSRect(x: -36 * s, y: 40 * s, width: 72 * s, height: 420 * s), xRadius: 36 * s,
                                      yRadius: 36 * s)
            NSGradient(starting: NSColor(srgbRed: 0.55, green: 0.33, blue: 0.16, alpha: 1),
                       ending: NSColor(srgbRed: 0.78, green: 0.55, blue: 0.3, alpha: 1))?.draw(in: handle, angle: 0)
            let ferrule = NSBezierPath(rect: NSRect(x: -40 * s, y: -40 * s, width: 80 * s, height: 90 * s))
            NSGradient(starting: NSColor(white: 0.55, alpha: 1), ending: NSColor(white: 0.9, alpha: 1))?.draw(in: ferrule, angle: 0)
            let tip = NSBezierPath()
            tip.move(to: NSPoint(x: -40 * s, y: -40 * s))
            tip.curve(to: NSPoint(x: 0, y: -230 * s), controlPoint1: NSPoint(x: -50 * s, y: -120 * s), controlPoint2: NSPoint(x: -20 * s, y: -190 * s))
            tip.curve(to: NSPoint(x: 40 * s, y: -40 * s), controlPoint1: NSPoint(x: 20 * s, y: -190 * s), controlPoint2: NSPoint(x: 50 * s, y: -120 * s))
            tip.close()
            Icons.blue.setFill()
            tip.fill()
            NSGraphicsContext.restoreGraphicsState()
            NSColor.black.withAlphaComponent(0.12).setStroke()
            shape.lineWidth = 3 * s
            shape.stroke()
            return true
        }
    }

    /// Writes an .iconset folder (used by the build script).
    static func writeIconset(to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let px = base * scale
                let img = render(size: CGFloat(px))
                guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                                 bytesPerRow: 0, bitsPerPixel: 0) else { continue }
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                img.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
                NSGraphicsContext.restoreGraphicsState()
                let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                try rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(name))
            }
        }
    }
}

final class SettingsWindow: NSWindow {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 440, height: 260), styleMask: [.titled, .closable], backing: .buffered,
                   defer: false)
        title = L("Settings")
        isReleasedWhenClosed = false
        let env = AppEnvironment.shared
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)

        func header(_ s: String) -> NSTextField {
            let l = NSTextField(labelWithString: s)
            l.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
            return l
        }
        stack.addArrangedSubview(header(L("Appearance")))
        let appearance = NSPopUpButton(frame: .zero, pullsDown: false)
        appearance.addItems(withTitles: [L("Use System Setting"), L("Light"), L("Dark")])
        appearance.selectItem(at: UserDefaults.standard.integer(forKey: "appearance"))
        appearance.onAction { _ in
            UserDefaults.standard.set(appearance.indexOfSelectedItem, forKey: "appearance")
            AppearanceSetting.apply()
        }
        stack.addArrangedSubview(appearance)

        stack.addArrangedSubview(header(L("Selection")))
        let aa = NSButton(checkboxWithTitle: L("Antialias selection edges when clipping"), target: nil, action: nil)
        aa.state = env.tools.selectionClippingAntialiased ? .on : .off
        aa.onAction { _ in env.tools.selectionClippingAntialiased = aa.state == .on }
        stack.addArrangedSubview(aa)

        stack.addArrangedSubview(header(L("Units")))
        let units = NSPopUpButton(frame: .zero, pullsDown: false)
        units.addItems(withTitles: MeasurementUnit.allCases.map(\.name))
        units.selectItem(at: env.units.rawValue)
        units.onAction { _ in env.units = MeasurementUnit(rawValue: units.indexOfSelectedItem) ?? .pixels }
        stack.addArrangedSubview(units)

        stack.addArrangedSubview(header(L("Reset")))
        let resetPalette = NSButton(title: L("Reset Palette to Default"), target: nil, action: nil)
        resetPalette.bezelStyle = .rounded
        resetPalette.onAction { _ in env.palette = AppEnvironment.defaultPalette }
        let resetWindows = NSButton(title: L("Reset Window Positions"), target: nil, action: nil)
        resetWindows.bezelStyle = .rounded
        resetWindows.onAction { _ in
            for k in ["Tools", "Colors", "History", "Layers"] { UserDefaults.standard.removeObject(forKey: "panelHidden.\(k)") }
            UserDefaults.standard.removeObject(forKey: "NSWindow Frame BrushwoodMainWindow")
        }
        let row = NSStackView(views: [resetPalette, resetWindows])
        stack.addArrangedSubview(row)
        let note = NSTextField(wrappingLabelWithString: L("The interface language follows the macOS system language (English and French are included)."))
        note.textColor = .secondaryLabelColor
        note.preferredMaxLayoutWidth = 400
        stack.addArrangedSubview(note)
        contentView = stack
    }
}

/// Light / dark / system appearance chosen in Settings.
enum AppearanceSetting {
    static func apply() {
        switch UserDefaults.standard.integer(forKey: "appearance") {
        case 1: NSApp.appearance = NSAppearance(named: .aqua)
        case 2: NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }
}

/// Built-in user guide and shortcut reference.
final class HelpWindow: NSWindow {
    enum Section { case guide, shortcuts }
    static let shared = HelpWindow()
    private let textView = NSTextView()
    private let segmented = NSSegmentedControl(labels: [L("Guide"), L("Keyboard Shortcuts")], trackingMode: .selectOne, target: nil,
                                               action: nil)

    private init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 620, height: 640), styleMask: [.titled, .closable, .resizable],
                   backing: .buffered, defer: false)
        title = L("Brushwood Help")
        isReleasedWhenClosed = false
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.documentView = textView
        textView.isEditable = false
        textView.textContainerInset = NSSize(width: 16, height: 14)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        segmented.onAction { [weak self] _ in self?.render(self?.segmented.selectedSegment == 1 ? .shortcuts : .guide) }
        let stack = NSStackView(views: [segmented, scroll])
        stack.orientation = .vertical
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 0, bottom: 0, right: 0)
        contentView = stack
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    func show(section: Section) {
        segmented.selectedSegment = section == .guide ? 0 : 1
        render(section)
        center()
        makeKeyAndOrderFront(nil)
    }

    private func render(_ section: Section) {
        let out = NSMutableAttributedString()
        func h(_ s: String) {
            out.append(NSAttributedString(string: s + "\n", attributes: [.font: NSFont.systemFont(ofSize: 17, weight: .bold),
                                                                          .foregroundColor: NSColor.labelColor]))
        }
        func p(_ s: String) {
            out.append(NSAttributedString(string: s + "\n\n", attributes: [.font: NSFont.systemFont(ofSize: 13),
                                                                            .foregroundColor: NSColor.labelColor]))
        }
        func row(_ k: String, _ v: String) {
            out.append(NSAttributedString(string: k + "\t", attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
                                                                          .foregroundColor: NSColor.labelColor]))
            out.append(NSAttributedString(string: v + "\n", attributes: [.font: NSFont.systemFont(ofSize: 12),
                                                                          .foregroundColor: NSColor.secondaryLabelColor]))
        }
        switch section {
        case .guide:
            h(L("Welcome to Brushwood"))
            p(L("Brushwood is a free image editor for macOS whose workflow follows Paint.NET: one main window with image tabs, floating Tools, History, Layers and Colors windows, layers with blend modes, unlimited history, and a large set of adjustments and effects with live preview."))
            h(L("Tools"))
            for t in ToolKind.allCases { p("\(t.name) (\(String(t.shortcutKey).uppercased())) — \(t.helpText)") }
            h(L("Selections"))
            p(L("Selection tools combine with the existing selection: ⌘ adds (union), ⌥ subtracts, right-click inverts (xor) and ⌥+right-click intersects. The mode can also be chosen in the tool bar."))
            h(L("Editable shapes"))
            p(L("Shapes, lines, gradients, text and paint bucket fills stay editable after you draw them: drag their handles or change options in the tool bar. Press Return or switch tools to finish, Escape or ⌘Z to cancel."))
            h(L("Files"))
            p(L("Layered images are saved as Paint.NET files (.pdn) or in the OpenRaster format (.ora), which Krita, GIMP and MyPaint also open. PNG, JPEG, BMP, GIF, TIFF, TGA, DDS, HEIC, AVIF and ICO can be saved; WebP, JPEG XL and PSD can be opened."))
        case .shortcuts:
            h(L("Tools"))
            for t in ToolKind.allCases { row(String(t.shortcutKey).uppercased(), t.name) }
            row("X", L("Swap primary and secondary colors"))
            row("[ ]", L("Decrease / increase brush width (Shift: ×10)"))
            row(L("Space"), L("Hold to pan"))
            row("⇧ + " + L("letter"), L("Cycle tools sharing a letter in reverse (⇧S = Magic Wand)"))
            row("⏎ / ⎋", L("Finish / cancel the current edit (⏎ again deselects)"))
            out.append(NSAttributedString(string: "\n"))
            h(L("Commands"))
            let cmds: [(String, String)] = [
                ("⌘N", L("New")), ("⌘O", L("Open")), ("⌘S", L("Save")), ("⇧⌘S", L("Save As")), ("⌘W", L("Close")),
                ("⌘Z", L("Undo")), ("⇧⌘Z / ⌘Y", L("Redo")), ("⌘X ⌘C ⌘V", L("Cut, Copy, Paste")), ("⇧⌘C", L("Copy Merged")),
                ("⇧⌘V", L("Paste Into New Layer")), ("⌥⌘V", L("Paste Into New Image")), ("⌘A / ⌘D", L("Select All / Deselect")),
                ("⌘I", L("Invert Selection")), ("⌫", L("Erase Selection")), ("⇧⌫", L("Fill Selection")),
                ("⌥⇧⌘C / ⌥⇧⌘V", L("Copy / paste the selection outline")),
                ("⇧⌘X", L("Crop to Selection")), ("⌘R", L("Resize")), ("⇧⌘R", L("Canvas Size")),
                ("⌃⌘H / ⌘G / ⌘J", L("Rotate 90° CW / 90° CCW / 180°")), ("⇧⌘F", L("Flatten")),
                ("⇧⌘N", L("Add New Layer")), ("⇧⌘⌫", L("Delete Layer")), ("⇧⌘D", L("Duplicate Layer")),
                ("⌃⌘M", L("Merge Layer Down")), ("F4", L("Layer Properties")),
                ("⌥PgUp / ⌥PgDn", L("Go to the layer above / below")), ("⌃⌘,", L("Toggle Layer Visibility")),
                ("⇧⌘L ⇧⌘G ⇧⌘T ⇧⌘M", L("Auto-Level, Black and White, Brightness / Contrast, Curves")),
                ("⇧⌘U ⌥⌘I ⇧⌘I ⌘L", L("Hue / Saturation, Invert Alpha, Invert Colors, Levels")),
                ("⇧⌘P ⇧⌘E", L("Posterize, Sepia")), ("⌘+ / ⌘-", L("Zoom In / Out")),
                ("⌘B", L("Zoom to Window")), ("⌘0", L("Actual Size")), ("⌘'", L("Pixel Grid")), ("⌥⌘R", L("Rulers")),
                ("⌘F", L("Repeat last effect")), ("F5–F8", L("Tools, History, Layers, Colors windows")),
                ("⌃⇥", L("Next image")), ("F1", L("Help")),
            ]
            for (k, v) in cmds { row(k, v) }
        }
        let para = NSMutableParagraphStyle()
        para.tabStops = [NSTextTab(textAlignment: .left, location: 150)]
        para.defaultTabInterval = 150
        out.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: out.length))
        textView.textStorage?.setAttributedString(out)
        textView.scrollToBeginningOfDocument(nil)
    }
}

/// Debug aid: `BRUSHWOOD_SNAPSHOT=/path/prefix` renders the windows to PNG files after launch, then quits.
enum DebugSnapshot {
    static func schedule(path: String, controller: MainWindowController) {
        let script = ProcessInfo.processInfo.environment["BRUSHWOOD_SCRIPT"] ?? ""
        // The capture is scheduled independently so it also fires while a modal dialog opened by the script runs.
        let delay = Double(ProcessInfo.processInfo.environment["BRUSHWOOD_SNAPSHOT_DELAY"] ?? "") ?? 2.5
        performOnMain(after: 1.0 + delay) {
            capture(controller: controller, to: path)
            exit(0)
        }
        performOnMain(after: 1.0) {
            DebugScript.run(script, controller: controller)
        }
    }

    /// Renders a window's content view hierarchy into a bitmap (each view drawn with cacheDisplay).
    static func render(_ window: NSWindow, overlaySubviews: Bool = true) -> NSBitmapImageRep? {
        guard let content = window.contentView else { return nil }
        content.layoutSubtreeIfNeeded()
        guard let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return nil }
        content.cacheDisplay(in: content.bounds, to: rep)
        if !overlaySubviews { return rep }
        // Caching the whole tree skips some layer-backed subviews; draw each top-level subview on top.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        for sub in content.subviews where !sub.isHidden {
            guard let r = sub.bitmapImageRepForCachingDisplay(in: sub.bounds) else { continue }
            sub.cacheDisplay(in: sub.bounds, to: r)
            var f = sub.frame
            if content.isFlipped { f.origin.y = content.bounds.height - f.maxY }
            r.draw(in: f)
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    static func dumpViews(_ v: NSView, prefix: String, depth: Int = 0) {
        guard depth < 3 else { return }
        for (i, sub) in v.subviews.enumerated() {
            NSLog("%@%@ %@ hidden=%d layer=%d", String(repeating: "  ", count: depth), String(describing: type(of: sub)),
                  NSStringFromRect(sub.frame), sub.isHidden ? 1 : 0, sub.layer != nil ? 1 : 0)
            if let rep = sub.bitmapImageRepForCachingDisplay(in: sub.bounds), depth == 0 {
                sub.cacheDisplay(in: sub.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: prefix + "-view\(i).png"))
            }
            dumpViews(sub, prefix: prefix, depth: depth + 1)
        }
    }

    static func capture(controller: MainWindowController, to path: String) {
        guard let window = controller.window, let content = window.contentView, let mainRep = render(window) else { return }
        if ProcessInfo.processInfo.environment["BRUSHWOOD_DUMP"] != nil { dumpViews(content, prefix: path) }
        let size = content.bounds.size
        let img = NSImage(size: size)
        img.lockFocus()
        mainRep.draw(in: NSRect(origin: .zero, size: size))
        // Overlay child panels at their on-screen positions.
        let contentScreen = window.convertToScreen(content.frame)
        for child in window.childWindows ?? [] where child.isVisible {
            guard let cv = child.contentView, let rep = render(child, overlaySubviews: false) else { continue }
            let cf = child.convertToScreen(cv.frame)
            let r = NSRect(x: cf.minX - contentScreen.minX, y: cf.minY - contentScreen.minY, width: cf.width, height: cf.height)
            rep.draw(in: r)
            NSColor.gray.setStroke()
            NSBezierPath(rect: r.insetBy(dx: -1, dy: -1)).stroke()
        }
        img.unlockFocus()
        if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path + "-main.png"))
        }
        for (i, w) in NSApp.windows.enumerated() where w.isVisible && w !== window && !(window.childWindows ?? []).contains(w) {
            guard let rep = render(w) else { continue }
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path + "-window\(i).png"))
        }
    }
}
