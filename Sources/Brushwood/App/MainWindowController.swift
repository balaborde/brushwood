import AppKit
import BrushwoodCore
import UniformTypeIdentifiers

/// The single main window: toolbars, image tabs, canvas, status bar and the four floating windows.
final class MainWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    let canvas = CanvasView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    let scrollView = NSScrollView()
    private(set) var mainToolbar: MainToolbar!
    let optionsBar = ToolOptionsBar()
    let statusBar = StatusBar()
    let toolsPanel = ToolsPanel()
    let colorsPanel = ColorsPanel()
    let layersPanel = LayersPanel()
    let historyPanel = HistoryPanel()

    private(set) var workspaces: [DocumentWorkspace] = []
    private(set) var active: DocumentWorkspace?
    private var tool: Tool?
    private var docObservers: [NSObjectProtocol] = []
    private var thumbTimer: Timer?
    private var panelsPlaced = false
    var lastEffect: (factory: () -> Effect, values: EffectValues, configure: ((Effect) -> Void)?)?

    var env: AppEnvironment { .shared }

    init() {
        let window = DropWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.minSize = NSSize(width: 760, height: 480)
        window.title = "Brushwood"
        window.setFrameAutosaveName("BrushwoodMainWindow")
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.fullScreenPrimary]
        super.init(window: window)
        window.delegate = self
        buildLayout()
        window.registerForDraggedTypes([.fileURL])
        for p in [toolsPanel, colorsPanel, layersPanel, historyPanel] as [FloatingPanel] {
            p.host = self
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: p, queue: .main) {
                [weak self] _ in
                DispatchQueue.main.async { self?.mainToolbar.validate() }
            }
        }
        let nc = NotificationCenter.default
        nc.addObserver(forName: .toolChanged, object: nil, queue: .main) { [weak self] _ in self?.toolDidChange() }
        nc.addObserver(forName: .viewSettingsChanged, object: nil, queue: .main) { [weak self] _ in self?.viewSettingsDidChange() }
        nc.addObserver(forName: .toolSettingsChanged, object: nil, queue: .main) { [weak self] _ in self?.updateStatusHint() }
        toolDidChange()
        viewSettingsDidChange()
        updateTitle()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildLayout() {
        guard let content = window?.contentView else { return }
        mainToolbar = MainToolbar(host: self)
        optionsBar.host = self
        statusBar.host = self
        canvas.host = self
        scrollView.documentView = canvas
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Theme.canvasBackground
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.contentView.postsFrameChangedNotifications = true
        scrollView.allowsMagnification = false
        // Two-finger trackpad scrolling moves the image diagonally too, instead of locking to one axis.
        scrollView.usesPredominantAxisScrolling = false
        scrollView.hasHorizontalRuler = true
        scrollView.hasVerticalRuler = true
        NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: scrollView.contentView,
                                               queue: .main) { [weak self] _ in
            self?.canvas.updateFrame()
        }
        NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scrollView.contentView,
                                               queue: .main) { [weak self] _ in
            if let ws = self?.active { ws.viewCenter = self?.canvas.visibleImageCenter }
        }
        for v in [mainToolbar!, optionsBar, scrollView, statusBar] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }
        NSLayoutConstraint.activate([
            mainToolbar.topAnchor.constraint(equalTo: content.topAnchor),
            mainToolbar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            mainToolbar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            mainToolbar.heightAnchor.constraint(equalToConstant: 42),
            optionsBar.topAnchor.constraint(equalTo: mainToolbar.bottomAnchor),
            optionsBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            optionsBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            optionsBar.heightAnchor.constraint(equalToConstant: 32),
            scrollView.topAnchor.constraint(equalTo: optionsBar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            statusBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 26),
        ])
    }

    /// Positions the floating windows around the canvas like Paint.NET's defaults.
    func placePanels() {
        guard let window, !panelsPlaced else { return }
        panelsPlaced = true
        let canvasFrame = window.convertToScreen(scrollView.convert(scrollView.bounds, to: nil))
        let inset: CGFloat = 12
        func place(_ p: NSPanel, x: CGFloat, y: CGFloat) {
            p.setFrameOrigin(NSPoint(x: x, y: y))
            window.addChildWindow(p, ordered: .above)
            p.orderFront(nil)
        }
        let d = UserDefaults.standard
        place(toolsPanel, x: canvasFrame.minX + inset, y: canvasFrame.maxY - toolsPanel.frame.height - inset)
        place(colorsPanel, x: canvasFrame.minX + inset, y: canvasFrame.minY + inset)
        place(historyPanel, x: canvasFrame.maxX - historyPanel.frame.width - inset - 16,
              y: canvasFrame.maxY - historyPanel.frame.height - inset)
        place(layersPanel, x: canvasFrame.maxX - layersPanel.frame.width - inset - 16, y: canvasFrame.minY + inset + 16)
        for (p, key) in [(toolsPanel, "Tools"), (colorsPanel, "Colors"), (historyPanel, "History"), (layersPanel, "Layers")]
            as [(NSPanel, String)] where d.object(forKey: "panelHidden.\(key)") as? Bool == true {
            p.orderOut(nil)
        }
        mainToolbar.validate()
    }

    var panelVisibility: [Bool] {
        [toolsPanel.isVisible, historyPanel.isVisible, layersPanel.isVisible, colorsPanel.isVisible]
    }

    func savePanelVisibility() {
        let d = UserDefaults.standard
        for (p, key) in [(toolsPanel, "Tools"), (colorsPanel, "Colors"), (historyPanel, "History"), (layersPanel, "Layers")]
            as [(NSPanel, String)] {
            d.set(!p.isVisible, forKey: "panelHidden.\(key)")
        }
    }

    // MARK: - Workspaces

    func add(_ ws: DocumentWorkspace) {
        workspaces.append(ws)
        activate(ws)
        if ws.zoom == 1 && (ws.document.width > 0) {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.active === ws else { return }
                // Fit large images to the window, like Paint.NET does when opening.
                let vis = self.scrollView.contentView.bounds.size
                if CGFloat(ws.document.width) > vis.width - 40 || CGFloat(ws.document.height) > vis.height - 40 {
                    self.canvas.zoomToWindow()
                }
            }
        }
    }

    func activate(_ ws: DocumentWorkspace) {
        if active === ws { return }
        tool?.deactivate()
        if let a = active { a.viewCenter = canvas.visibleImageCenter }
        active = ws
        docObservers.forEach { NotificationCenter.default.removeObserver($0) }
        docObservers.removeAll()
        let nc = NotificationCenter.default
        let doc = ws.document
        docObservers.append(nc.addObserver(forName: .documentHistoryChanged, object: doc, queue: .main) { [weak self] _ in
            self?.documentDidChange()
        })
        docObservers.append(nc.addObserver(forName: .documentSelectionChanged, object: doc, queue: .main) { [weak self] _ in
            self?.updateSelectionStatus()
        })
        docObservers.append(nc.addObserver(forName: .documentInvalidated, object: doc, queue: .main) { [weak self] _ in
            self?.scheduleThumbnail()
        })
        docObservers.append(nc.addObserver(forName: .documentSizeChanged, object: doc, queue: .main) { [weak self] _ in
            self?.updateRulers()
            self?.updateSelectionStatus()
        })
        canvas.setWorkspace(ws)
        makeTool()
        layersPanel.bind(ws)
        historyPanel.bind(doc)
        updateThumbnail(ws)
        mainToolbar.tabs.reload(workspaces, active: active)
        statusBar.setZoom(canvas.zoom)
        updateSelectionStatus()
        updateTitle()
        updateRulers()
        mainToolbar.validate()
        window?.makeFirstResponder(canvas)
    }

    func close(_ ws: DocumentWorkspace, completion: ((Bool) -> Void)? = nil) {
        if ws === active { tool?.commit() }
        confirmClose(ws) { [weak self] ok in
            guard let self, ok else {
                completion?(false)
                return
            }
            let idx = self.workspaces.firstIndex { $0 === ws } ?? 0
            self.workspaces.removeAll { $0 === ws }
            if self.active === ws {
                self.active = nil
                self.tool?.deactivate()
                self.tool = nil
                if self.workspaces.isEmpty {
                    self.canvas.setWorkspace(nil)
                    self.layersPanel.bind(nil)
                    self.historyPanel.bind(nil)
                    self.docObservers.forEach { NotificationCenter.default.removeObserver($0) }
                    self.docObservers.removeAll()
                    self.updateTitle()
                } else {
                    self.activate(self.workspaces[min(idx, self.workspaces.count - 1)])
                }
            }
            self.mainToolbar.tabs.reload(self.workspaces, active: self.active)
            self.mainToolbar.validate()
            completion?(true)
        }
    }

    private func confirmClose(_ ws: DocumentWorkspace, completion: @escaping (Bool) -> Void) {
        guard ws.document.isDirty else {
            completion(true)
            return
        }
        activate(ws)
        let alert = NSAlert()
        alert.messageText = LF("Save changes to \"%@\"?", ws.displayName)
        alert.informativeText = L("If you don't save, your changes will be lost.")
        alert.addButton(withTitle: L("Save"))
        alert.addButton(withTitle: L("Cancel"))
        alert.addButton(withTitle: L("Don't Save"))
        alert.alertStyle = .warning
        alert.beginSheetModal(for: window!) { [weak self] r in
            switch r {
            case .alertFirstButtonReturn:
                self?.save(ws, saveAs: false) { completion($0) }
            case .alertThirdButtonReturn:
                completion(true)
            default:
                completion(false)
            }
        }
    }

    /// Closes every document, asking about unsaved ones. Used when quitting.
    func closeAll(completion: @escaping (Bool) -> Void) {
        guard let ws = workspaces.first(where: { $0.document.isDirty }) ?? workspaces.first else {
            completion(true)
            return
        }
        close(ws) { [weak self] ok in
            if ok { self?.closeAll(completion: completion) } else { completion(false) }
        }
    }

    /// Reorders the image list (drag in the thumbnails strip).
    func moveWorkspace(_ ws: DocumentWorkspace, to index: Int) {
        guard let from = workspaces.firstIndex(where: { $0 === ws }) else { return }
        let to = min(index, workspaces.count - 1)
        guard from != to else { return }
        workspaces.remove(at: from)
        workspaces.insert(ws, at: to)
        mainToolbar.tabs.reload(workspaces, active: active)
    }

    /// Closes every image except `keep`, one at a time (each may ask to save).
    func closeOthers(than keep: DocumentWorkspace) {
        guard let next = workspaces.first(where: { $0 !== keep }) else {
            activate(keep)
            return
        }
        close(next) { [weak self] ok in
            if ok { self?.closeOthers(than: keep) }
        }
    }

    var hasDirtyDocuments: Bool { workspaces.contains { $0.document.isDirty } }

    private func documentDidChange() {
        updateTitle()
        mainToolbar.validate()
        layersPanel.validateButtons()
        scheduleThumbnail()
        if let ws = active, let tab = mainToolbar.tabs.subviews.first?.subviews.first {
            _ = tab
            mainToolbar.tabs.reload(workspaces, active: ws)
        }
    }

    private func scheduleThumbnail() {
        thumbTimer?.invalidate()
        let t = Timer(timeInterval: 0.6, repeats: false) { [weak self] _ in
            guard let self, let ws = self.active else { return }
            self.updateThumbnail(ws)
            self.mainToolbar.tabs.refreshThumbnails()
        }
        RunLoop.main.add(t, forMode: .common)
        thumbTimer = t
    }

    private func updateThumbnail(_ ws: DocumentWorkspace) {
        if let cg = ws.document.thumbnail(maxSize: 96) {
            ws.thumbnail = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
    }

    func updateTitle() {
        guard let window else { return }
        if let ws = active {
            window.title = ws.displayName
            window.representedURL = ws.fileURL
            window.isDocumentEdited = ws.document.isDirty
            window.subtitle = "\(ws.document.width) × \(ws.document.height)"
        } else {
            window.title = "Brushwood"
            window.subtitle = ""
            window.representedURL = nil
            window.isDocumentEdited = false
        }
    }

    // MARK: - Tools

    private func makeTool() {
        tool?.deactivate()
        guard active != nil else {
            tool = nil
            canvas.tool = nil
            return
        }
        let k = env.activeTool
        let t: Tool
        switch k {
        case .moveSelectedPixels: t = MoveSelectedPixelsTool(kind: k, canvas: canvas)
        case .moveSelection: t = MoveSelectionTool(kind: k, canvas: canvas)
        case .rectangleSelect, .ellipseSelect: t = ShapeSelectTool(kind: k, canvas: canvas)
        case .lassoSelect: t = LassoSelectTool(kind: k, canvas: canvas)
        case .magicWand: t = MagicWandTool(kind: k, canvas: canvas)
        case .zoom: t = ZoomTool(kind: k, canvas: canvas)
        case .pan: t = PanTool(kind: k, canvas: canvas)
        case .paintBucket: t = PaintBucketTool(kind: k, canvas: canvas)
        case .gradient: t = GradientTool(kind: k, canvas: canvas)
        case .paintbrush: t = PaintbrushTool(kind: k, canvas: canvas)
        case .eraser: t = EraserTool(kind: k, canvas: canvas)
        case .pencil: t = PencilTool(kind: k, canvas: canvas)
        case .colorPicker: t = ColorPickerTool(kind: k, canvas: canvas)
        case .cloneStamp: t = CloneStampTool(kind: k, canvas: canvas)
        case .recolor: t = RecolorTool(kind: k, canvas: canvas)
        case .text: t = TextTool(kind: k, canvas: canvas)
        case .lineCurve: t = LineCurveTool(kind: k, canvas: canvas)
        case .shapes: t = ShapesTool(kind: k, canvas: canvas)
        }
        tool = t
        canvas.tool = t
        t.activate()
    }

    func selectTool(_ k: ToolKind) {
        env.setActiveTool(k)
    }

    /// Paint.NET shortcut behaviour: pressing a letter again cycles through tools sharing it.
    /// Shift cycles in the opposite direction (Shift+S goes straight to the Magic Wand).
    @discardableResult
    func selectTool(byShortcut ch: Character, backwards: Bool = false) -> Bool {
        let matches = ToolKind.allCases.filter { $0.shortcutKey == ch }
        guard !matches.isEmpty else { return false }
        let n = matches.count
        if let i = matches.firstIndex(of: env.activeTool) {
            selectTool(matches[(i + (backwards ? n - 1 : 1)) % n])
        } else {
            selectTool(backwards ? matches[n - 1] : matches[0])
        }
        return true
    }

    /// Return finishes the current edit; with nothing pending it deselects (Paint.NET behaviour).
    func commitOrDeselect() {
        if tool?.hasPendingEdits == true {
            tool?.commit()
        } else {
            active?.deselect()
        }
    }

    private func toolDidChange() {
        makeTool()
        updateStatusHint()
        canvas.refreshCursor()
        canvas.needsDisplay = true
    }

    private func updateStatusHint() {
        let k = env.activeTool
        statusBar.setHint(icon: Icons.image(k.icon, size: 16), text: "\(k.name): \(k.helpText)")
    }

    func setToolStatus(_ s: String?) {
        if let s {
            statusBar.setHint(icon: Icons.image(env.activeTool.icon, size: 16), text: s)
        } else {
            updateStatusHint()
        }
    }

    /// Finishes pending tool edits before running a command.
    func commitPendingTool() {
        tool?.commit()
    }

    // MARK: - Canvas callbacks

    func canvasGeometryChanged() {
        updateRulers()
    }

    func zoomChanged() {
        statusBar.setZoom(canvas.zoom)
        updateRulers()
    }

    func cursorMoved(_ p: CGPoint?) {
        guard let p, let doc = active?.document else {
            statusBar.setCursor("")
            return
        }
        let u = env.units
        let x = u.fromPixels(Double(floor(p.x)), dpi: doc.dpi), y = u.fromPixels(Double(floor(p.y)), dpi: doc.dpi)
        statusBar.setCursor(u == .pixels ? "\(Int(x)), \(Int(y))" : String(format: "%.2f, %.2f", x, y))
    }

    func updateSelectionStatus() {
        guard let doc = active?.document else {
            statusBar.setSelection("")
            return
        }
        let r = doc.selection?.intBounds.intersection(doc.bounds) ?? doc.bounds
        let u = env.units
        let w = u.fromPixels(Double(r.width), dpi: doc.dpi), h = u.fromPixels(Double(r.height), dpi: doc.dpi)
        statusBar.setSelection(u == .pixels ? "\(Int(w)) × \(Int(h))" : String(format: "%.2f × %.2f", w, h))
        mainToolbar.validate()
    }

    private func viewSettingsDidChange() {
        scrollView.rulersVisible = env.showRulers
        updateRulers()
        statusBar.syncUnits()
        updateSelectionStatus()
        mainToolbar.validate()
    }

    func updateRulers() {
        guard env.showRulers, active != nil else { return }
        let dpi = active?.document.dpi ?? 96
        let unitPoints: CGFloat
        switch env.units {
        case .pixels: unitPoints = canvas.zoom
        case .inches: unitPoints = canvas.zoom * CGFloat(dpi)
        case .centimeters: unitPoints = canvas.zoom * CGFloat(dpi) / 2.54
        }
        let name = "Brushwood-\(env.units.rawValue)-\(Int(unitPoints * 10000))"
        NSRulerView.registerUnit(withName: NSRulerView.UnitName(name), abbreviation: env.units.abbreviation,
                                 unitToPointsConversionFactor: unitPoints, stepUpCycle: [2, 5], stepDownCycle: [0.5, 0.2])
        for ruler in [scrollView.horizontalRulerView, scrollView.verticalRulerView].compactMap({ $0 }) {
            ruler.measurementUnits = NSRulerView.UnitName(name)
            ruler.originOffset = ruler.orientation == .horizontalRuler ? canvas.imageOrigin.x : canvas.imageOrigin.y
            ruler.needsDisplay = true
        }
    }

    // MARK: - Window delegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.terminate(nil)
        return false
    }

    func windowDidBecomeKey(_ notification: Notification) {
        mainToolbar.validate()
    }

    func windowDidResize(_ notification: Notification) {
        canvas.updateFrame()
    }

    // MARK: - Opening & saving

    func newImage(width: Int, height: Int, background: ColorBgra, dpi: Double) {
        let doc = Document(width: width, height: height, background: background)
        doc.layers[0].name = L("Background")
        doc.dpi = dpi
        doc.history.reset(baseName: L("New Image"), icon: "history.new")
        add(DocumentWorkspace(document: doc))
    }

    func open(urls: [URL]) {
        for url in urls {
            if let existing = workspaces.first(where: { $0.fileURL?.standardizedFileURL == url.standardizedFileURL }) {
                activate(existing)
                continue
            }
            do {
                let doc = try ImageCodec.load(url: url)
                if doc.layers.count == 1 && doc.layers[0].name == "Background" { doc.layers[0].name = L("Background") }
                doc.history.reset(baseName: L("Open Image"), icon: "history.open")
                doc.markSaved()
                let ws = DocumentWorkspace(document: doc, url: url)
                // Single untouched untitled image gets replaced, like Paint.NET.
                if workspaces.count == 1, let only = workspaces.first, only.fileURL == nil, !only.document.isDirty,
                   only.document.history.items.count <= 1 {
                    workspaces.removeAll()
                    active = nil
                }
                add(ws)
                RecentFiles.add(url)
            } catch {
                presentError(error, title: LF("Could not open \"%@\"", url.lastPathComponent))
            }
        }
    }

    func presentError(_ error: Error, title: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }

    func save(_ ws: DocumentWorkspace, saveAs: Bool, completion: ((Bool) -> Void)? = nil) {
        if ws === active { commitPendingTool() }
        if !saveAs, let url = ws.fileURL, let type = ws.fileType, type.canWrite {
            write(ws, to: url, type: type, completion: completion)
            return
        }
        let panel = NSSavePanel()
        panel.title = L("Save As")
        panel.nameFieldStringValue = (ws.fileURL?.deletingPathExtension().lastPathComponent ?? ws.displayName)
        panel.canSelectHiddenExtension = true
        // Like Paint.NET, layered images default to .pdn (OpenRaster when a blend mode isn't representable in .pdn).
        let layeredDefault: FileType = PdnWriter.unsupportedBlendModes(in: ws.document).isEmpty ? .paintDotNet : .openRaster
        let accessory = SaveFormatAccessory(current: ws.fileType?.canWrite == true ? ws.fileType! : (ws.document.layers.count > 1 ? layeredDefault : .png),
                                            panel: panel)
        panel.accessoryView = accessory.view
        panel.beginSheetModal(for: window!) { [weak self] r in
            guard r == .OK, let url = panel.url else {
                completion?(false)
                return
            }
            let type = accessory.selected
            var final = url
            if !type.extensions.contains(url.pathExtension.lowercased()) {
                final = url.deletingPathExtension().appendingPathExtension(type.primaryExtension)
            }
            self?.write(ws, to: final, type: type, completion: completion)
        }
    }

    private func write(_ ws: DocumentWorkspace, to url: URL, type: FileType, completion: ((Bool) -> Void)?) {
        let proceed = { [weak self] (options: SaveOptions) in
            guard let self else { return }
            do {
                try ImageCodec.save(ws.document, to: url, type: type, options: options)
                ws.fileURL = url
                ws.fileType = type
                ws.saveOptions = options
                ws.document.markSaved()
                RecentFiles.add(url)
                self.updateTitle()
                self.mainToolbar.tabs.reload(self.workspaces, active: self.active)
                completion?(true)
            } catch {
                self.presentError(error, title: LF("Could not save \"%@\"", url.lastPathComponent))
                completion?(false)
            }
        }
        if (type.hasQuality || type.hasBitDepth) && (ws.fileType != type || ws.fileURL != url) {
            SaveOptionsDialog.run(for: ws, type: type, parent: window) { options in
                if let options { proceed(options) } else { completion?(false) }
            }
        } else if type == .paintDotNet, !PdnWriter.unsupportedBlendModes(in: ws.document).isEmpty {
            let modes = Set(PdnWriter.unsupportedBlendModes(in: ws.document)).map { L($0.displayName) }.sorted()
            let alert = NSAlert()
            alert.messageText = L("Blend modes not supported by Paint.NET")
            alert.informativeText = LF("These blend modes will be saved as Normal in the .pdn file: %@. Save as OpenRaster (.ora) to keep them.",
                                       modes.joined(separator: ", "))
            alert.addButton(withTitle: L("Save Anyway"))
            alert.addButton(withTitle: L("Cancel"))
            alert.beginSheetModal(for: window!) { r in
                if r == .alertFirstButtonReturn { proceed(ws.saveOptions) } else { completion?(false) }
            }
        } else if !type.supportsLayers && ws.document.layers.count > 1 && (ws.fileType != type || ws.fileURL != url) {
            let alert = NSAlert()
            alert.messageText = L("Flatten image")
            alert.informativeText = L("This file format does not support layers. The saved file will contain a flattened copy of the image; your layers are kept in Brushwood.")
            alert.addButton(withTitle: L("Flatten"))
            alert.addButton(withTitle: L("Cancel"))
            alert.beginSheetModal(for: window!) { r in
                if r == .alertFirstButtonReturn { proceed(ws.saveOptions) } else { completion?(false) }
            }
        } else {
            proceed(ws.saveOptions)
        }
    }

    // MARK: - Menu validation

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard let action = item.action else { return true }
        // Typing undo in a text field (dialogs included) goes to that field.
        if let tv = editingTextView, action == #selector(undo(_:)) || action == #selector(redo(_:)) {
            let um = tv.undoManager
            item.title = action == #selector(undo(_:)) ? L("Undo") : L("Redo")
            return action == #selector(undo(_:)) ? um?.canUndo == true : um?.canRedo == true
        }
        // Nothing may change the image while a dialog (effect, resize, properties…) is open.
        if NSApp.modalWindow != nil { return false }
        let doc = active?.document
        let hasDoc = doc != nil
        let hasSel = doc?.selection != nil
        switch action {
        case #selector(newDocument(_:)), #selector(openDocument(_:)), #selector(pasteIntoNewImage(_:)):
            return action == #selector(pasteIntoNewImage(_:)) ? Clipboard.hasImage : true
        case #selector(undo(_:)):
            item.title = doc?.history.undoName.map { LF("Undo %@", $0) } ?? L("Undo")
            return (doc?.history.canUndo ?? false) || tool?.hasPendingEdits == true
        case #selector(redo(_:)):
            item.title = doc?.history.redoName.map { LF("Redo %@", $0) } ?? L("Redo")
            return doc?.history.canRedo ?? false
        case #selector(eraseSelection(_:)), #selector(fillSelection(_:)):
            // Let Delete reach the text tool while typing.
            return hasDoc && !(tool is TextTool && tool?.hasPendingEdits == true)
        case #selector(cropToSelection(_:)), #selector(deselect(_:)), #selector(invertSelection(_:)),
             #selector(zoomToSelection(_:)):
            return hasSel
        case #selector(copySelection(_:)):
            return hasSel
        case #selector(pasteSelection(_:)):
            return hasDoc && MainWindowController.copiedSelection != nil
        case #selector(paste(_:)), #selector(pasteIntoNewLayer(_:)):
            return hasDoc && Clipboard.hasImage
        case #selector(deleteLayer(_:)):
            return (doc?.layers.count ?? 0) > 1
        case #selector(mergeLayerDown(_:)):
            return (doc?.activeLayerIndex ?? 0) > 0
        case #selector(moveLayerDown(_:)), #selector(moveLayerToBottom(_:)), #selector(selectLayerBelow(_:)),
             #selector(moveLayerDownOrBottom(_:)),
             #selector(selectBottomLayer(_:)):
            return (doc?.activeLayerIndex ?? 0) > 0
        case #selector(moveLayerUp(_:)), #selector(moveLayerToTop(_:)), #selector(selectLayerAbove(_:)), #selector(selectTopLayer(_:)),
             #selector(moveLayerUpOrTop(_:)):
            guard let doc else { return false }
            return doc.activeLayerIndex < doc.layers.count - 1
        case #selector(flatten(_:)):
            return (doc?.layers.count ?? 0) > 1
        case #selector(togglePixelGrid(_:)):
            item.state = env.showPixelGrid ? .on : .off
            return true
        case #selector(toggleRulers(_:)):
            item.state = env.showRulers ? .on : .off
            return true
        case #selector(setUnits(_:)):
            item.state = env.units.rawValue == item.tag ? .on : .off
            return true
        case #selector(toggleToolsWindow(_:)):
            item.state = toolsPanel.isVisible ? .on : .off
            return true
        case #selector(toggleHistoryWindow(_:)):
            item.state = historyPanel.isVisible ? .on : .off
            return true
        case #selector(toggleLayersWindow(_:)):
            item.state = layersPanel.isVisible ? .on : .off
            return true
        case #selector(toggleColorsWindow(_:)):
            item.state = colorsPanel.isVisible ? .on : .off
            return true
        case #selector(repeatLastEffect(_:)):
            if let last = lastEffect {
                item.title = LF("Repeat %@", L(last.factory().name))
                return hasDoc
            }
            item.title = L("Repeat")
            return false
        case #selector(selectImageTab(_:)):
            item.state = (item.representedObject as? DocumentWorkspace) === active ? .on : .off
            return true
        case #selector(nextImage(_:)), #selector(previousImage(_:)):
            return workspaces.count > 1
        default:
            return hasDoc
        }
    }

    // MARK: - File actions

    @objc func newDocument(_ sender: Any?) {
        NewImageDialog.run(parent: window) { [weak self] w, h, bg, dpi in
            self?.newImage(width: w, height: h, background: bg, dpi: dpi)
        }
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = FileType.readable.flatMap { t in t.extensions.compactMap { UTType(filenameExtension: $0) } }
        panel.beginSheetModal(for: window!) { [weak self] r in
            if r == .OK { self?.open(urls: panel.urls) }
        }
    }

    @objc func saveDocument(_ sender: Any?) {
        guard let ws = active else { return }
        save(ws, saveAs: false)
    }

    @objc func saveDocumentAs(_ sender: Any?) {
        guard let ws = active else { return }
        save(ws, saveAs: true)
    }

    @objc func saveAllDocuments(_ sender: Any?) {
        for ws in workspaces where ws.document.isDirty {
            if ws.fileURL != nil, ws.fileType?.canWrite == true { save(ws, saveAs: false) }
        }
    }

    @objc func closeDocument(_ sender: Any?) {
        guard let ws = active else { return }
        close(ws)
    }

    @objc func printDocument(_ sender: Any?) {
        guard let ws = active else { return }
        commitPendingTool()
        guard let cg = ws.document.flattened().makeCGImage() else { return }
        let image = NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) * 72 / ws.document.dpi,
                                                      height: CGFloat(cg.height) * 72 / ws.document.dpi))
        let view = NSImageView(frame: NSRect(origin: .zero, size: image.size))
        view.image = image
        view.imageScaling = .scaleProportionallyUpOrDown
        let info = NSPrintInfo.shared
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = true
        let op = NSPrintOperation(view: view, printInfo: info)
        op.jobTitle = ws.displayName
        op.runModal(for: window!, delegate: nil, didRun: nil, contextInfo: nil)
    }

    @objc func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        open(urls: [url])
    }

    // MARK: - Edit actions

    /// Text field being edited in the key window (dialogs, Colors hex field), whose own typing undo should win.
    private var editingTextView: NSTextView? {
        guard let tv = NSApp.keyWindow?.firstResponder as? NSTextView, tv.isEditable else { return nil }
        return tv
    }

    // NSWindow itself implements `undo:` / `redo:` (backed by its own, empty NSUndoManager) and sits before this
    // controller in the responder chain, so the image history uses its own selectors or ⌘Z would just beep.
    @objc(brushwoodUndo:) func undo(_ sender: Any?) {
        if let tv = editingTextView {
            tv.undoManager?.undo()
            return
        }
        guard let doc = active?.document else { return }
        if tool?.hasPendingEdits == true {
            // Undoing while editing discards the uncommitted edit (Paint.NET behaviour).
            tool?.cancel()
            return
        }
        doc.history.undo()
    }

    @objc(brushwoodRedo:) func redo(_ sender: Any?) {
        if let tv = editingTextView {
            tv.undoManager?.redo()
            return
        }
        commitPendingTool()
        active?.document.history.redo()
    }

    func historyStep(to index: Int) {
        guard let doc = active?.document else { return }
        if tool?.hasPendingEdits == true { tool?.cancel() }
        doc.history.step(to: min(index, doc.history.items.count - 1))
    }

    @objc func cut(_ sender: Any?) {
        guard let ws = active else { return }
        commitPendingTool()
        guard let (pixels, _) = ws.selectedPixels(merged: false) else { return }
        Clipboard.write(pixels)
        ws.eraseSelection()
        mainToolbar.validate()
    }

    @objc func copy(_ sender: Any?) {
        guard let ws = active else { return }
        commitPendingTool()
        if let (pixels, _) = ws.selectedPixels(merged: false) { Clipboard.write(pixels) }
        mainToolbar.validate()
    }

    @objc func copyMerged(_ sender: Any?) {
        guard let ws = active else { return }
        commitPendingTool()
        if let (pixels, _) = ws.selectedPixels(merged: true) { Clipboard.write(pixels) }
        mainToolbar.validate()
    }

    @objc func paste(_ sender: Any?) {
        guard let ws = active, let img = Clipboard.read() else { return }
        commitPendingTool()
        let doc = ws.document
        if img.width > doc.width || img.height > doc.height {
            let alert = NSAlert()
            alert.messageText = L("Image larger than canvas")
            alert.informativeText = L("The image being pasted is larger than the canvas size. What would you like to do?")
            alert.addButton(withTitle: L("Expand canvas"))
            alert.addButton(withTitle: L("Keep canvas size"))
            alert.addButton(withTitle: L("Cancel"))
            let r = alert.runModal()
            if r == .alertThirdButtonReturn { return }
            if r == .alertFirstButtonReturn {
                ws.resizeCanvas(to: IntSize(width: max(doc.width, img.width), height: max(doc.height, img.height)),
                                anchor: (0, 0), dpi: doc.dpi)
            }
        }
        beginPaste(img, in: ws)
    }

    private func beginPaste(_ img: Surface, in ws: DocumentWorkspace) {
        // Paste at the top-left of the visible area, like Paint.NET.
        let vis = canvas.visibleImageRect
        let origin = IntPoint(x: max(0, Int(vis.minX.rounded(.up))), y: max(0, Int(vis.minY.rounded(.up))))
        selectTool(.moveSelectedPixels)
        (tool as? MoveSelectedPixelsTool)?.beginPaste(img, at: origin.x + img.width <= ws.document.width ? origin : IntPoint(x: 0, y: 0))
    }

    @objc func pasteIntoNewLayer(_ sender: Any?) {
        guard let ws = active, Clipboard.hasImage else { return }
        commitPendingTool()
        ws.addLayer()
        paste(sender)
    }

    @objc func pasteIntoNewImage(_ sender: Any?) {
        guard let img = Clipboard.read() else { return }
        commitPendingTool()
        let doc = Document(width: img.width, height: img.height, background: .transparent)
        doc.layers[0].name = L("Background")
        doc.layers[0].surface.copy(from: img, to: IntPoint(x: 0, y: 0))
        doc.history.reset(baseName: L("Paste Into New Image"), icon: "history.paste")
        add(DocumentWorkspace(document: doc))
    }

    @objc override func selectAll(_ sender: Any?) {
        commitPendingTool()
        active?.selectAll()
    }

    @objc func deselect(_ sender: Any?) {
        commitPendingTool()
        active?.deselect()
    }

    @objc func invertSelection(_ sender: Any?) {
        commitPendingTool()
        active?.invertSelection()
    }

    /// Edit > Copy Selection: remembers the selection outline (not the pixels).
    static var copiedSelection: Selection?

    @objc func copySelection(_ sender: Any?) {
        commitPendingTool()
        if let s = active?.document.selection { MainWindowController.copiedSelection = s }
    }

    @objc func pasteSelection(_ sender: Any?) {
        guard let ws = active, let s = MainWindowController.copiedSelection else { return }
        commitPendingTool()
        ws.changeSelection(to: s, name: L("Paste Selection"), icon: "cmd.paste")
    }

    @objc func eraseSelection(_ sender: Any?) {
        commitPendingTool()
        active?.eraseSelection()
    }

    @objc func fillSelection(_ sender: Any?) {
        commitPendingTool()
        active?.fillSelection(with: env.primaryColor)
    }

    // MARK: - View actions

    @objc func zoomIn(_ sender: Any?) { canvas.zoomIn() }
    @objc func zoomOut(_ sender: Any?) { canvas.zoomOut() }
    @objc func zoomToWindow(_ sender: Any?) { canvas.zoomToWindow() }
    @objc func actualSize(_ sender: Any?) { canvas.setZoom(1) }

    @objc func zoomToSelection(_ sender: Any?) {
        guard let sel = active?.document.selection else { return }
        canvas.zoomToRect(sel.bounds)
    }

    @objc func togglePixelGrid(_ sender: Any?) { env.showPixelGrid.toggle() }
    @objc func toggleRulers(_ sender: Any?) { env.showRulers.toggle() }

    @objc func setUnits(_ sender: NSMenuItem) {
        env.units = MeasurementUnit(rawValue: sender.tag) ?? .pixels
    }

    // MARK: - Image actions

    @objc func cropToSelection(_ sender: Any?) {
        commitPendingTool()
        active?.cropToSelection()
    }

    @objc func resizeImage(_ sender: Any?) {
        guard let ws = active else { return }
        commitPendingTool()
        ResizeDialog.run(ws: ws, parent: window) { size, mode, dpi in ws.resizeImage(to: size, mode: mode, dpi: dpi) }
    }

    @objc func resizeCanvas(_ sender: Any?) {
        guard let ws = active else { return }
        commitPendingTool()
        CanvasSizeDialog.run(ws: ws, parent: window) { size, anchor, dpi in ws.resizeCanvas(to: size, anchor: anchor, dpi: dpi) }
    }

    @objc func flipImageHorizontal(_ sender: Any?) {
        commitPendingTool()
        active?.transformImage(L("Flip Horizontal"), icon: "cmd.flipH", Resampler.flipHorizontal)
    }

    @objc func flipImageVertical(_ sender: Any?) {
        commitPendingTool()
        active?.transformImage(L("Flip Vertical"), icon: "cmd.flipV", Resampler.flipVertical)
    }

    @objc func rotateImageCW(_ sender: Any?) {
        commitPendingTool()
        active?.transformImage(L("Rotate 90° Clockwise"), icon: "cmd.rotateCW", Resampler.rotate90CW)
    }

    @objc func rotateImageCCW(_ sender: Any?) {
        commitPendingTool()
        active?.transformImage(L("Rotate 90° Counter-clockwise"), icon: "cmd.rotateCCW", Resampler.rotate90CCW)
    }

    @objc func rotateImage180(_ sender: Any?) {
        commitPendingTool()
        active?.transformImage(L("Rotate 180°"), icon: "cmd.rotate180", Resampler.rotate180)
    }

    @objc func flatten(_ sender: Any?) {
        commitPendingTool()
        active?.flatten()
    }

    // MARK: - Layer actions

    @objc func addLayer(_ sender: Any?) {
        commitPendingTool()
        active?.addLayer()
    }

    @objc func deleteLayer(_ sender: Any?) {
        commitPendingTool()
        active?.deleteLayer()
    }

    @objc func duplicateLayer(_ sender: Any?) {
        commitPendingTool()
        active?.duplicateLayer()
    }

    @objc func mergeLayerDown(_ sender: Any?) {
        commitPendingTool()
        active?.mergeLayerDown()
    }

    @objc func moveLayerUp(_ sender: Any?) {
        commitPendingTool()
        active?.moveLayer(up: true)
    }

    @objc func moveLayerDown(_ sender: Any?) {
        commitPendingTool()
        active?.moveLayer(up: false)
    }

    func moveLayer(from: Int, to: Int) {
        commitPendingTool()
        active?.moveLayer(from: from, to: to)
    }

    @objc func moveLayerUpOrTop(_ sender: Any?) {
        if NSApp.currentEvent?.modifierFlags.contains(.command) == true { moveLayerToTop(sender) } else { moveLayerUp(sender) }
    }

    @objc func moveLayerDownOrBottom(_ sender: Any?) {
        if NSApp.currentEvent?.modifierFlags.contains(.command) == true { moveLayerToBottom(sender) } else { moveLayerDown(sender) }
    }

    @objc func rotateLayer180(_ sender: Any?) {
        commitPendingTool()
        active?.rotateLayer180()
    }

    @objc func moveLayerToTop(_ sender: Any?) {
        commitPendingTool()
        active?.moveLayerToEnd(top: true)
    }

    @objc func moveLayerToBottom(_ sender: Any?) {
        commitPendingTool()
        active?.moveLayerToEnd(top: false)
    }

    @objc func flipLayerHorizontal(_ sender: Any?) {
        commitPendingTool()
        active?.flipLayer(horizontal: true)
    }

    @objc func flipLayerVertical(_ sender: Any?) {
        commitPendingTool()
        active?.flipLayer(horizontal: false)
    }

    @objc func importFromFile(_ sender: Any?) {
        guard let ws = active else { return }
        commitPendingTool()
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = FileType.readable.flatMap { t in t.extensions.compactMap { UTType(filenameExtension: $0) } }
        panel.beginSheetModal(for: window!) { [weak self] r in
            guard r == .OK else { return }
            for url in panel.urls {
                do {
                    let d = try ImageCodec.load(url: url)
                    ws.addLayer(surface: d.flattened(), name: url.deletingPathExtension().lastPathComponent)
                } catch {
                    self?.presentError(error, title: LF("Could not open \"%@\"", url.lastPathComponent))
                }
            }
        }
    }

    @objc func layerProperties(_ sender: Any?) {
        guard let ws = active else { return }
        commitPendingTool()
        LayerPropertiesDialog.run(ws: ws, parent: window)
    }

    @objc func layerRotateZoom(_ sender: Any?) {
        guard active != nil else { return }
        runEffect(factory: { RotateZoomLayerEffect() }, historyIcon: "layer.rotateZoom")
    }

    @objc func selectLayerAbove(_ sender: Any?) {
        guard let doc = active?.document else { return }
        setActiveLayer(min(doc.layers.count - 1, doc.activeLayerIndex + 1))
    }

    @objc func selectLayerBelow(_ sender: Any?) {
        guard let doc = active?.document else { return }
        setActiveLayer(max(0, doc.activeLayerIndex - 1))
    }

    @objc func selectTopLayer(_ sender: Any?) {
        guard let doc = active?.document else { return }
        setActiveLayer(doc.layers.count - 1)
    }

    @objc func selectBottomLayer(_ sender: Any?) { setActiveLayer(0) }

    @objc func toggleActiveLayerVisibility(_ sender: Any?) {
        guard let doc = active?.document else { return }
        toggleLayerVisibility(doc.activeLayerIndex)
    }

    func setActiveLayer(_ i: Int) {
        guard let doc = active?.document, i >= 0, i < doc.layers.count, i != doc.activeLayerIndex else { return }
        commitPendingTool()
        doc.activeLayerIndex = i
        layersPanel.validateButtons()
        mainToolbar.validate()
    }

    func toggleLayerVisibility(_ i: Int) {
        commitPendingTool()
        active?.toggleLayerVisibility(i)
    }

    // MARK: - Window actions

    private func toggle(_ p: NSPanel) {
        if p.isVisible {
            p.orderOut(nil)
        } else {
            if p.parent == nil { window?.addChildWindow(p, ordered: .above) }
            p.orderFront(nil)
        }
        savePanelVisibility()
        mainToolbar.validate()
    }

    @objc func toggleToolsWindow(_ sender: Any?) { toggle(toolsPanel) }
    @objc func toggleHistoryWindow(_ sender: Any?) { toggle(historyPanel) }
    @objc func toggleLayersWindow(_ sender: Any?) { toggle(layersPanel) }
    @objc func toggleColorsWindow(_ sender: Any?) { toggle(colorsPanel) }

    @objc func selectImageTab(_ sender: NSMenuItem) {
        if let ws = sender.representedObject as? DocumentWorkspace { activate(ws) }
    }

    @objc func nextImage(_ sender: Any?) {
        guard let a = active, let i = workspaces.firstIndex(where: { $0 === a }) else { return }
        activate(workspaces[(i + 1) % workspaces.count])
    }

    @objc func previousImage(_ sender: Any?) {
        guard let a = active, let i = workspaces.firstIndex(where: { $0 === a }) else { return }
        activate(workspaces[(i + workspaces.count - 1) % workspaces.count])
    }

    // MARK: - Tools & colors from menus

    @objc func selectToolFromMenu(_ sender: NSMenuItem) {
        if let k = ToolKind(rawValue: sender.tag) { selectTool(k) }
    }

    @objc func swapColors(_ sender: Any?) { env.swapColors() }
    @objc func resetColors(_ sender: Any?) { env.resetColors() }
}

/// Main window accepting dropped image files (opened as new images, like Paint.NET).
final class DropWindow: NSWindow {
    private var droppedURLs: [URL] = []

    private func urls(_ info: NSDraggingInfo) -> [URL] {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter { FileType.forExtension($0.pathExtension)?.canRead == true }
    }

    @objc func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        urls(sender).isEmpty ? [] : .copy
    }

    @objc func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        urls(sender).isEmpty ? [] : .copy
    }

    @objc func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let list = urls(sender)
        guard !list.isEmpty, let c = windowController as? MainWindowController else { return false }
        c.open(urls: list)
        return true
    }
}
