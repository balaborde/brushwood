import AppKit
import BrushwoodCore

final class LayersPanel: FloatingPanel, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    private let table = NSTableView()
    private var workspace: DocumentWorkspace?
    private var observers: [NSObjectProtocol] = []
    private var thumbnails: [ObjectIdentifier: NSImage] = [:]
    private var thumbTimer: Timer?
    private var reloading = false
    private var buttons: [(ToolbarButton, Selector)] = []
    private static let dragType = NSPasteboard.PasteboardType("app.brushwood.layer-row")

    init() {
        super.init(title: L("Layers"), size: NSSize(width: 230, height: 230), resizable: true)
        minSize = NSSize(width: 180, height: 120)
        let col = NSTableColumn(identifier: .init("layer"))
        table.addTableColumn(col)
        table.headerView = nil
        table.rowHeight = 44
        table.dataSource = self
        table.delegate = self
        table.style = .plain
        table.allowsEmptySelection = false
        // Letters must reach the canvas as tool shortcuts, not type-select rows.
        table.allowsTypeSelect = false
        table.doubleAction = #selector(doubleClicked)
        table.target = self
        table.registerForDraggedTypes([LayersPanel.dragType])
        let menu = NSMenu()
        let items: [(String, Selector)] = [
            (L("Add New Layer"), #selector(MainWindowController.addLayer(_:))),
            (L("Duplicate Layer"), #selector(MainWindowController.duplicateLayer(_:))),
            (L("Delete Layer"), #selector(MainWindowController.deleteLayer(_:))),
            (L("Merge Layer Down"), #selector(MainWindowController.mergeLayerDown(_:))),
            (L("Flatten"), #selector(MainWindowController.flatten(_:))),
            (L("Layer Properties…"), #selector(MainWindowController.layerProperties(_:))),
        ]
        for (title, sel) in items { menu.addItem(withTitle: title, action: sel, keyEquivalent: "") }
        menu.delegate = self
        table.menu = menu
        table.draggingDestinationFeedbackStyle = .gap
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        let bar = NSStackView()
        bar.spacing = 1
        bar.edgeInsets = NSEdgeInsets(top: 2, left: 4, bottom: 2, right: 4)
        let specs: [(String, String, Selector)] = [
            ("layer.add", L("Add New Layer"), #selector(MainWindowController.addLayer(_:))),
            ("layer.delete", L("Delete Layer"), #selector(MainWindowController.deleteLayer(_:))),
            ("layer.duplicate", L("Duplicate Layer"), #selector(MainWindowController.duplicateLayer(_:))),
            ("layer.merge", L("Merge Layer Down"), #selector(MainWindowController.mergeLayerDown(_:))),
            ("layer.up", L("Move Layer Up"), #selector(MainWindowController.moveLayerUp(_:))),
            ("layer.down", L("Move Layer Down"), #selector(MainWindowController.moveLayerDown(_:))),
            ("layer.properties", L("Layer Properties"), #selector(MainWindowController.layerProperties(_:))),
        ]
        for (icon, tip, sel) in specs {
            let b = ToolbarButton(icon: icon, tooltip: tip, target: nil, action: sel)
            buttons.append((b, sel))
            bar.addArrangedSubview(b)
        }

        let content = NSView()
        for v in [scroll, bar] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bar.topAnchor),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            bar.heightAnchor.constraint(equalToConstant: 28),
        ])
        contentView = content
    }

    override var host: MainWindowController? {
        didSet { for (b, _) in buttons { b.target = host } }
    }

    func bind(_ ws: DocumentWorkspace?) {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        workspace = ws
        thumbnails.removeAll()
        if let doc = ws?.document {
            let nc = NotificationCenter.default
            for name in [Notification.Name.documentLayersChanged, .documentActiveLayerChanged, .documentSizeChanged] {
                observers.append(nc.addObserver(forName: name, object: doc, queue: .main) { [weak self] _ in
                    self?.thumbnails.removeAll()
                    self?.reload()
                })
            }
            observers.append(nc.addObserver(forName: .documentInvalidated, object: doc, queue: .main) { [weak self] _ in
                self?.scheduleThumbnails()
            })
        }
        reload()
    }

    private func scheduleThumbnails() {
        thumbTimer?.invalidate()
        let t = Timer(timeInterval: 0.4, repeats: false) { [weak self] _ in
            self?.thumbnails.removeAll()
            self?.table.reloadData()
            self?.selectActive()
        }
        RunLoop.main.add(t, forMode: .common)
        thumbTimer = t
    }

    private var doc: Document? { workspace?.document }

    /// Table rows show the top-most layer first.
    private func layerIndex(forRow row: Int) -> Int { (doc?.layers.count ?? 0) - 1 - row }
    private func row(forLayer i: Int) -> Int { (doc?.layers.count ?? 0) - 1 - i }

    func reload() {
        reloading = true
        table.reloadData()
        selectActive()
        reloading = false
        validateButtons()
    }

    private func selectActive() {
        guard let doc else { return }
        reloading = true
        table.selectRowIndexes(IndexSet(integer: row(forLayer: doc.activeLayerIndex)), byExtendingSelection: false)
        reloading = false
    }

    func validateButtons() {
        guard let host else { return }
        for (b, sel) in buttons {
            b.isEnabled = host.validateMenuItem(NSMenuItem(title: "", action: sel, keyEquivalent: ""))
        }
    }

    private func thumbnail(_ layer: BitmapLayer) -> NSImage? {
        let key = ObjectIdentifier(layer)
        if let t = thumbnails[key] { return t }
        guard let s = Resampler.thumbnail(of: layer.surface, maxSize: 72), let cg = s.makeCGImage() else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: s.width, height: s.height))
        thumbnails[key] = img
        return img
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { doc?.layers.count ?? 0 }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let doc else { return nil }
        let li = layerIndex(forRow: row)
        guard li >= 0 && li < doc.layers.count else { return nil }
        let layer = doc.layers[li]
        let cell = NSTableCellView()
        let thumbView = LayerThumbView(image: thumbnail(layer))
        let name = NSTextField(labelWithString: layer.name)
        name.lineBreakMode = .byTruncatingTail
        name.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
        let check = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        check.state = layer.isVisible ? .on : .off
        check.toolTip = L("Visible")
        check.onAction { [weak self] _ in self?.host?.toggleLayerVisibility(li) }
        var detail = ""
        if layer.blendMode != .normal { detail += L(layer.blendMode.displayName) }
        if layer.opacity != 255 { detail += (detail.isEmpty ? "" : ", ") + "\(Int((Double(layer.opacity) / 2.55).rounded()))%" }
        let sub = NSTextField(labelWithString: detail)
        sub.font = .systemFont(ofSize: 9)
        sub.textColor = .secondaryLabelColor
        for v in [thumbView, name, sub, check] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(v)
        }
        NSLayoutConstraint.activate([
            thumbView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            thumbView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            thumbView.widthAnchor.constraint(equalToConstant: 38),
            thumbView.heightAnchor.constraint(equalToConstant: 38),
            name.leadingAnchor.constraint(equalTo: thumbView.trailingAnchor, constant: 8),
            name.trailingAnchor.constraint(lessThanOrEqualTo: check.leadingAnchor, constant: -4),
            name.centerYAnchor.constraint(equalTo: cell.centerYAnchor, constant: detail.isEmpty ? 0 : -6),
            sub.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            sub.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 1),
            check.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            check.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !reloading, let doc, table.selectedRow >= 0 else { return }
        let li = layerIndex(forRow: table.selectedRow)
        host?.setActiveLayer(li)
        _ = doc
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        // Right-clicking a row makes it the active layer first.
        if table.clickedRow >= 0 { host?.setActiveLayer(layerIndex(forRow: table.clickedRow)) }
        for item in menu.items { item.target = host }
    }

    @objc private func doubleClicked() {
        guard table.clickedRow >= 0 else { return }
        host?.setActiveLayer(layerIndex(forRow: table.clickedRow))
        host?.layerProperties(nil)
    }

    // Drag to reorder.
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        item.setString("\(row)", forType: LayersPanel.dragType)
        return item
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
                   proposedDropOperation op: NSTableView.DropOperation) -> NSDragOperation {
        op == .above ? .move : []
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let doc, let s = info.draggingPasteboard.pasteboardItems?.first?.string(forType: LayersPanel.dragType),
              let fromRow = Int(s) else { return false }
        let toRow = fromRow < row ? row - 1 : row
        let from = layerIndex(forRow: fromRow)
        let to = doc.layers.count - 1 - toRow
        host?.moveLayer(from: from, to: to)
        return true
    }
}

private final class LayerThumbView: NSView {
    let image: NSImage?

    init(image: NSImage?) {
        self.image = image
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let image else { return }
        let s = image.size
        let scale = min(bounds.width / max(1, s.width), bounds.height / max(1, s.height))
        let w = s.width * scale, h = s.height * scale
        let r = NSRect(x: bounds.midX - w / 2, y: bounds.midY - h / 2, width: w, height: h)
        Checkerboard.draw(in: r, cell: 4)
        image.draw(in: r)
        NSColor.black.withAlphaComponent(0.35).setStroke()
        NSBezierPath(rect: r.insetBy(dx: -0.5, dy: -0.5)).stroke()
    }
}
