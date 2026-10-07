import AppKit
import BrushwoodCore

/// First toolbar row: common commands on the left, image tabs (thumbnails) on the right,
/// and floating-window toggles at the far right — Paint.NET's main toolbar layout.
final class MainToolbar: NSView {
    weak var host: MainWindowController?
    let tabs = ImageTabsView()
    private let leftStack = NSStackView()
    private let rightStack = NSStackView()
    private(set) var gridButton: ToolbarButton!
    private(set) var rulersButton: ToolbarButton!
    private(set) var windowButtons: [ToolbarButton] = []
    private var commandButtons: [(ToolbarButton, Selector)] = []

    init(host: MainWindowController) {
        self.host = host
        super.init(frame: .zero)
        if #available(macOS 14.0, *) { clipsToBounds = true }
        leftStack.orientation = .horizontal
        leftStack.spacing = 1
        leftStack.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)
        rightStack.orientation = .horizontal
        rightStack.spacing = 1
        rightStack.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 6)
        for v in [leftStack, tabs, rightStack] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            leftStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            leftStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            tabs.leadingAnchor.constraint(equalTo: leftStack.trailingAnchor, constant: 8),
            tabs.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            tabs.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            tabs.trailingAnchor.constraint(equalTo: rightStack.leadingAnchor, constant: -4),
            rightStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            rightStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        leftStack.setContentHuggingPriority(.required, for: .horizontal)
        rightStack.setContentHuggingPriority(.required, for: .horizontal)

        func button(_ icon: String, _ tip: String, _ sel: Selector) -> ToolbarButton {
            let b = ToolbarButton(icon: icon, tooltip: tip, target: host, action: sel)
            commandButtons.append((b, sel))
            return b
        }
        let groups: [[ToolbarButton]] = [
            [button("cmd.new", L("New (⌘N)"), #selector(MainWindowController.newDocument(_:))),
             button("cmd.open", L("Open (⌘O)"), #selector(MainWindowController.openDocument(_:))),
             button("cmd.save", L("Save (⌘S)"), #selector(MainWindowController.saveDocument(_:))),
             button("cmd.print", L("Print (⌘P)"), #selector(MainWindowController.printDocument(_:)))],
            [button("cmd.cut", L("Cut (⌘X)"), #selector(MainWindowController.cut(_:))),
             button("cmd.copy", L("Copy (⌘C)"), #selector(MainWindowController.copy(_:))),
             button("cmd.paste", L("Paste (⌘V)"), #selector(MainWindowController.paste(_:)))],
            [button("cmd.crop", L("Crop to Selection (⇧⌘X)"), #selector(MainWindowController.cropToSelection(_:))),
             button("cmd.deselect", L("Deselect (⌘D)"), #selector(MainWindowController.deselect(_:)))],
            [button("cmd.undo", L("Undo (⌘Z)"), #selector(MainWindowController.undo(_:))),
             button("cmd.redo", L("Redo (⇧⌘Z)"), #selector(MainWindowController.redo(_:)))],
        ]
        for (i, g) in groups.enumerated() {
            if i > 0 { leftStack.addArrangedSubview(ToolbarSeparator()) }
            g.forEach { leftStack.addArrangedSubview($0) }
        }
        leftStack.addArrangedSubview(ToolbarSeparator())
        gridButton = ToolbarButton(icon: "cmd.grid", tooltip: L("Pixel Grid (⌘')"), target: host,
                                   action: #selector(MainWindowController.togglePixelGrid(_:)))
        rulersButton = ToolbarButton(icon: "cmd.rulers", tooltip: L("Rulers (⌥⌘R)"), target: host,
                                     action: #selector(MainWindowController.toggleRulers(_:)))
        leftStack.addArrangedSubview(gridButton)
        leftStack.addArrangedSubview(rulersButton)

        let toggles: [(String, String, Selector)] = [
            ("window.tools", L("Tools (F5)"), #selector(MainWindowController.toggleToolsWindow(_:))),
            ("window.history", L("History (F6)"), #selector(MainWindowController.toggleHistoryWindow(_:))),
            ("window.layers", L("Layers (F7)"), #selector(MainWindowController.toggleLayersWindow(_:))),
            ("window.colors", L("Colors (F8)"), #selector(MainWindowController.toggleColorsWindow(_:))),
        ]
        for (icon, tip, sel) in toggles {
            let b = ToolbarButton(icon: icon, tooltip: tip, target: host, action: sel)
            windowButtons.append(b)
            rightStack.addArrangedSubview(b)
        }
        rightStack.addArrangedSubview(ToolbarSeparator())
        rightStack.addArrangedSubview(ToolbarButton(icon: "cmd.settings", tooltip: L("Settings (⌘,)"), target: NSApp.delegate,
                                                    action: #selector(AppDelegate.showSettings(_:))))
        rightStack.addArrangedSubview(ToolbarButton(icon: "cmd.help", tooltip: L("Help"), target: NSApp.delegate,
                                                    action: #selector(AppDelegate.showHelp(_:))))
        tabs.host = host
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        // Since macOS 14 views don't clip to their bounds and dirtyRect can extend past them.
        dirtyRect.intersection(bounds).fill()
    }

    /// Enables/disables buttons using the same validation as the menus.
    func validate() {
        guard let host else { return }
        for (b, sel) in commandButtons {
            let item = NSMenuItem(title: "", action: sel, keyEquivalent: "")
            b.isEnabled = host.validateMenuItem(item)
        }
        gridButton.isToggled = AppEnvironment.shared.showPixelGrid
        rulersButton.isToggled = AppEnvironment.shared.showRulers
        let vis = host.panelVisibility
        for (i, b) in windowButtons.enumerated() { b.isToggled = vis[i] }
    }
}

/// Horizontal strip of image thumbnails (Paint.NET's image list).
final class ImageTabsView: NSView {
    weak var host: MainWindowController?
    private let scroll = NSScrollView()
    private let stack = NSStackView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.horizontalScrollElasticity = .allowed
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.alignment = .centerY
        let flip = FlippedView()
        flip.translatesAutoresizingMaskIntoConstraints = false
        flip.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: flip.leadingAnchor),
            stack.topAnchor.constraint(equalTo: flip.topAnchor),
            stack.bottomAnchor.constraint(equalTo: flip.bottomAnchor),
            stack.trailingAnchor.constraint(equalTo: flip.trailingAnchor),
        ])
        scroll.documentView = flip
        flip.heightAnchor.constraint(equalTo: scroll.contentView.heightAnchor).isActive = true
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError() }

    func reload(_ workspaces: [DocumentWorkspace], active: DocumentWorkspace?) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for ws in workspaces {
            let tab = ImageTab(workspace: ws, active: ws === active)
            tab.host = host
            tab.onSelect = { [weak self] in self?.host?.activate(ws) }
            tab.onClose = { [weak self] in self?.host?.close(ws) }
            tab.onDragReorder = { [weak self] windowX in
                guard let self else { return }
                // Drop position → index among the tabs (52 pt per tab including spacing).
                let local = self.stack.convert(NSPoint(x: windowX, y: 0), from: nil).x
                self.host?.moveWorkspace(ws, to: max(0, Int(local / 52)))
            }
            stack.addArrangedSubview(tab)
        }
    }

    func refreshThumbnails() {
        stack.arrangedSubviews.forEach { $0.needsDisplay = true }
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class ImageTab: NSView {
    let workspace: DocumentWorkspace
    let isActive: Bool
    weak var host: MainWindowController?
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?
    private var hovering = false
    private var tracking: NSTrackingArea?

    init(workspace: DocumentWorkspace, active: Bool) {
        self.workspace = workspace
        isActive = active
        super.init(frame: NSRect(x: 0, y: 0, width: 48, height: 36))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 48).isActive = true
        heightAnchor.constraint(equalToConstant: 36).isActive = true
        toolTip = workspace.displayName + (workspace.document.isDirty ? " *" : "")
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }

    private var closeRect: NSRect { NSRect(x: bounds.maxX - 14, y: bounds.maxY - 14, width: 12, height: 12) }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 1, dy: 1)
        let bg = NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4)
        if isActive {
            NSColor.controlAccentColor.withAlphaComponent(0.25).setFill()
            bg.fill()
            NSColor.controlAccentColor.setStroke()
            bg.lineWidth = 1.5
            bg.stroke()
        } else if hovering {
            NSColor.labelColor.withAlphaComponent(0.08).setFill()
            bg.fill()
        }
        if let thumb = workspace.thumbnail {
            let inner = r.insetBy(dx: 3, dy: 3)
            let s = thumb.size
            let scale = min(inner.width / max(1, s.width), inner.height / max(1, s.height))
            let w = s.width * scale, h = s.height * scale
            let tr = NSRect(x: inner.midX - w / 2, y: inner.midY - h / 2, width: w, height: h)
            Checkerboard.draw(in: tr, cell: 3)
            thumb.draw(in: tr)
            NSColor.black.withAlphaComponent(0.3).setStroke()
            NSBezierPath(rect: tr.insetBy(dx: -0.5, dy: -0.5)).stroke()
        }
        if workspace.document.isDirty {
            // Unsaved images get an asterisk, as in Paint.NET's image list.
            let star = NSAttributedString(string: "*", attributes: [.font: NSFont.boldSystemFont(ofSize: 14),
                                                                     .foregroundColor: NSColor.systemOrange,
                                                                     .strokeColor: NSColor.white, .strokeWidth: -3])
            star.draw(at: NSPoint(x: 2, y: -2))
        }
        if hovering {
            NSColor.black.withAlphaComponent(0.6).setFill()
            NSBezierPath(ovalIn: closeRect).fill()
            let p = NSBezierPath()
            let c = closeRect.insetBy(dx: 3.5, dy: 3.5)
            p.move(to: NSPoint(x: c.minX, y: c.minY)); p.line(to: NSPoint(x: c.maxX, y: c.maxY))
            p.move(to: NSPoint(x: c.minX, y: c.maxY)); p.line(to: NSPoint(x: c.maxX, y: c.minY))
            p.lineWidth = 1.4
            NSColor.white.setStroke()
            p.stroke()
        }
    }

    var onDragReorder: ((CGFloat) -> Void)?
    private var dragStart: NSPoint?

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if hovering && closeRect.insetBy(dx: -2, dy: -2).contains(p) {
            onClose?()
        } else {
            dragStart = event.locationInWindow
            onSelect?()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let s = dragStart, abs(event.locationInWindow.x - s.x) > 6 else { return }
        onDragReorder?(event.locationInWindow.x)
    }

    override func mouseUp(with event: NSEvent) { dragStart = nil }

    override func otherMouseDown(with event: NSEvent) { onClose?() }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let host else { return nil }
        let m = NSMenu()
        let ws = workspace
        m.addItem(withTitle: L("Save"), action: nil, keyEquivalent: "").onAction { _ in host.save(ws, saveAs: false) }
        m.addItem(withTitle: L("Save As…"), action: nil, keyEquivalent: "").onAction { _ in host.save(ws, saveAs: true) }
        if let url = ws.fileURL {
            m.addItem(withTitle: L("Show in Finder"), action: nil, keyEquivalent: "").onAction { _ in
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
        m.addItem(.separator())
        m.addItem(withTitle: L("Close"), action: nil, keyEquivalent: "").onAction { _ in host.close(ws) }
        m.addItem(withTitle: L("Close Others"), action: nil, keyEquivalent: "").onAction { _ in host.closeOthers(than: ws) }
        return m
    }
}
