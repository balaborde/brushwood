import AppKit
import BrushwoodCore

final class HistoryPanel: FloatingPanel, NSTableViewDataSource, NSTableViewDelegate {
    private let table = NSTableView()
    private var document: Document?
    private var observer: NSObjectProtocol?
    private var undoButton: ToolbarButton!
    private var redoButton: ToolbarButton!
    private var rewindButton: ToolbarButton!
    private var forwardButton: ToolbarButton!
    private var reloading = false

    init() {
        super.init(title: L("History"), size: NSSize(width: 210, height: 240), resizable: true)
        minSize = NSSize(width: 160, height: 120)
        let col = NSTableColumn(identifier: .init("item"))
        table.addTableColumn(col)
        table.headerView = nil
        table.rowHeight = 20
        table.dataSource = self
        table.delegate = self
        table.style = .plain
        table.allowsEmptySelection = false
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        rewindButton = ToolbarButton(icon: "sym.backward.end.fill", tooltip: L("Rewind to the beginning"), target: nil, action: nil)
        rewindButton.onAction { [weak self] _ in self?.host?.historyStep(to: 0) }
        undoButton = ToolbarButton(icon: "cmd.undo", tooltip: L("Undo"), target: nil, action: nil)
        undoButton.onAction { [weak self] _ in self?.host?.undo(nil) }
        redoButton = ToolbarButton(icon: "cmd.redo", tooltip: L("Redo"), target: nil, action: nil)
        redoButton.onAction { [weak self] _ in self?.host?.redo(nil) }
        forwardButton = ToolbarButton(icon: "sym.forward.end.fill", tooltip: L("Fast-forward to the end"), target: nil, action: nil)
        forwardButton.onAction { [weak self] _ in self?.host?.historyStep(to: Int.max) }
        let bar = NSStackView(views: [rewindButton, undoButton, redoButton, forwardButton])
        bar.spacing = 2
        bar.edgeInsets = NSEdgeInsets(top: 2, left: 4, bottom: 2, right: 4)

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

    func bind(_ doc: Document?) {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        document = doc
        if let doc {
            observer = NotificationCenter.default.addObserver(forName: .documentHistoryChanged, object: doc, queue: .main) {
                [weak self] _ in self?.reload()
            }
        }
        reload()
    }

    func reload() {
        reloading = true
        table.reloadData()
        if let h = document?.history, h.currentIndex >= 0 {
            table.selectRowIndexes(IndexSet(integer: h.currentIndex), byExtendingSelection: false)
            table.scrollRowToVisible(min(h.items.count - 1, h.currentIndex + 1))
        }
        reloading = false
        let h = document?.history
        undoButton.isEnabled = h?.canUndo ?? false
        redoButton.isEnabled = h?.canRedo ?? false
        rewindButton.isEnabled = h?.canUndo ?? false
        forwardButton.isEnabled = h?.canRedo ?? false
    }

    func numberOfRows(in tableView: NSTableView) -> Int { document?.history.items.count ?? 0 }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let h = document?.history, row < h.items.count else { return nil }
        let item = h.items[row]
        let cell = NSTableCellView()
        let img = NSImageView(image: Icons.image(item.icon, size: 16))
        let label = NSTextField(labelWithString: item.name)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.lineBreakMode = .byTruncatingTail
        let undone = row > h.currentIndex
        label.textColor = undone ? .tertiaryLabelColor : .labelColor
        img.alphaValue = undone ? 0.4 : 1
        for v in [img, label] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(v)
        }
        NSLayoutConstraint.activate([
            img.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            img.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            img.widthAnchor.constraint(equalToConstant: 16),
            img.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: img.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !reloading, table.selectedRow >= 0 else { return }
        host?.historyStep(to: table.selectedRow)
    }
}
