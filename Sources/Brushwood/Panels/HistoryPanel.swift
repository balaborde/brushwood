import AppKit
import BrushwoodCore

extension Notification.Name {
    static let historyTimeDisplayChanged = Notification.Name("BrushwoodHistoryTimeDisplayChanged")
}

/// What the History window shows at the right of each step (Brushwood Plus): when it was made, how long ago, or nothing.
enum HistoryTimeDisplay: Int, CaseIterable {
    case timeOfDay, elapsed, hidden

    private static let key = "historyTimeDisplay"

    static var current: HistoryTimeDisplay {
        get { HistoryTimeDisplay(rawValue: UserDefaults.standard.integer(forKey: key)) ?? .timeOfDay }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
            NotificationCenter.default.post(name: .historyTimeDisplayChanged, object: nil)
        }
    }

    var title: String {
        switch self {
        case .timeOfDay: return L("Show Time of Day")
        case .elapsed: return L("Show Time Elapsed")
        case .hidden: return L("Hide Times")
        }
    }

    /// "14:32" (with the day when it is not today) or "12 min ago", by minute; empty when hidden.
    func text(for date: Date, now: Date) -> String {
        switch self {
        case .hidden:
            return ""
        case .timeOfDay:
            return (Calendar.current.isDateInToday(date) ? Self.time : Self.dayAndTime).string(from: date)
        case .elapsed:
            let s = max(0, now.timeIntervalSince(date))
            let ago = s < 60 ? DateComponents(second: 0) : s < 3600 ? DateComponents(minute: -Int(s / 60))
                : s < 86400 ? DateComponents(hour: -Int(s / 3600)) : DateComponents(day: -Int(s / 86400))
            return Self.relative.localizedString(from: ago)
        }
    }

    /// Date and time in full, for tooltips.
    static func fullText(for date: Date) -> String { full.string(from: date) }

    /// The user's formats, in the interface language when it differs from the system's.
    private static let locale: Locale = {
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        var c = Locale.Components(identifier: language)
        if c.languageComponents.languageCode == Locale.current.language.languageCode { return .current }
        c.region = Locale.current.region
        return Locale(components: c)
    }()

    private static func formatter(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }

    private static let time = formatter("jmm")
    private static let dayAndTime = formatter("MMMdjmm")
    private static let full: DateFormatter = {
        let f = DateFormatter()
        f.locale = locale
        f.dateStyle = .full
        f.timeStyle = .medium
        return f
    }()
    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = locale
        f.dateTimeStyle = .named
        f.unitsStyle = .short
        return f
    }()
}

/// A History row: icon, name and, at the right, when the step was made. Snapshot rows show a thumbnail instead of
/// the icon, and the last one has a line under it.
private final class HistoryCell: NSTableCellView {
    let icon = NSImageView()
    let name = NSTextField(labelWithString: "")
    let time = NSTextField(labelWithString: "")
    var date: Date?
    /// Extra tooltip line.
    var note: String?

    init(iconSize: CGFloat = 16, separator: Bool = false) {
        super.init(frame: .zero)
        name.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        name.lineBreakMode = .byTruncatingTail
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        time.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        time.alignment = .right
        time.setContentHuggingPriority(.required, for: .horizontal)
        time.setContentCompressionResistancePriority(.required, for: .horizontal)
        for v in [icon, name, time] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: iconSize),
            icon.heightAnchor.constraint(equalToConstant: iconSize),
            name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            name.trailingAnchor.constraint(lessThanOrEqualTo: time.leadingAnchor, constant: -6),
            name.centerYAnchor.constraint(equalTo: centerYAnchor),
            time.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            time.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        if separator {
            let line = NSBox()
            line.boxType = .separator
            line.translatesAutoresizingMaskIntoConstraints = false
            addSubview(line)
            NSLayoutConstraint.activate([
                line.leadingAnchor.constraint(equalTo: leadingAnchor),
                line.trailingAnchor.constraint(equalTo: trailingAnchor),
                line.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func showTime(_ display: HistoryTimeDisplay, now: Date) {
        time.stringValue = date.map { display.text(for: $0, now: now) } ?? ""
        toolTip = date.map { ([name.stringValue, HistoryTimeDisplay.fullText(for: $0)] + [note].compactMap { $0 }).joined(separator: "\n") }
    }

    /// The image fitted in a `side`-point square, over a checkerboard, with a thin frame.
    static func thumbnail(_ cg: CGImage?, side: CGFloat) -> NSImage? {
        guard let cg else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height), k = side / max(w, h)
        let r = NSRect(x: (side - w * k) / 2, y: (side - h * k) / 2, width: w * k, height: h * k)
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            Checkerboard.draw(in: r, cell: 3)
            NSGraphicsContext.current?.cgContext.draw(cg, in: r)
            NSColor.separatorColor.setStroke()
            NSBezierPath(rect: r.insetBy(dx: -0.5, dy: -0.5)).stroke()
            return true
        }
    }
}

final class HistoryPanel: FloatingPanel, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    private let table = NSTableView()
    private var document: Document?
    private var observer: NSObjectProtocol?
    /// Refreshes "… min ago" while times elapsed are shown.
    private var clock: Timer?
    private var undoButton: ToolbarButton!
    private var redoButton: ToolbarButton!
    private var rewindButton: ToolbarButton!
    private var forwardButton: ToolbarButton!
    private var snapshotButton: ToolbarButton!
    private var reloading = false
    /// Snapshots are listed first, then the steps.
    private var snapshotCount: Int { document?.history.snapshots.count ?? 0 }

    init() {
        super.init(title: L("History"), size: NSSize(width: 210, height: 240), resizable: true)
        minSize = NSSize(width: 160, height: 120)
        let col = NSTableColumn(identifier: .init("item"))
        table.addTableColumn(col)
        table.headerView = nil
        table.rowHeight = 20
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(rowClicked)
        table.style = .plain
        table.allowsEmptySelection = false
        // Letters must reach the canvas as tool shortcuts, not type-select rows, and ⌘A / ⌘Z must reach the image:
        // the list never takes keyboard focus (clicking still selects rows).
        table.allowsTypeSelect = false
        table.refusesFirstResponder = true
        let menu = NSMenu()
        menu.delegate = self
        table.menu = menu
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
        snapshotButton = ToolbarButton(icon: "cmd.snapshot", tooltip: L("New Snapshot"), target: nil, action: nil)
        snapshotButton.onAction { [weak self] _ in self?.takeSnapshot() }
        // Paint.NET 5 has just Undo and Redo here; Brushwood Plus adds snapshots at the right.
        let bar = NSStackView(views: [undoButton, redoButton])
        bar.spacing = 2
        bar.edgeInsets = NSEdgeInsets(top: 2, left: 4, bottom: 2, right: 4)

        let content = NSView()
        for v in [scroll, bar, snapshotButton] as [NSView] {
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
            snapshotButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -4),
            snapshotButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
        contentView = content
        NotificationCenter.default.addObserver(forName: .historyTimeDisplayChanged, object: nil, queue: .main) { [weak self] _ in
            self?.startClock()
            self?.refreshTimes()
        }
        startClock()
    }

    private func startClock() {
        clock?.invalidate()
        clock = nil
        guard HistoryTimeDisplay.current == .elapsed else { return }
        let t = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            if self?.isVisible == true { self?.refreshTimes() }
        }
        RunLoop.main.add(t, forMode: .common)
        clock = t
    }

    private func refreshTimes() {
        let display = HistoryTimeDisplay.current, now = Date()
        table.enumerateAvailableRowViews { row, _ in (row.view(atColumn: 0) as? HistoryCell)?.showTime(display, now: now) }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        func add(_ title: String, _ action: @escaping () -> Void) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.onAction { _ in action() }
            item.isEnabled = document != nil
            menu.addItem(item)
        }
        let row = table.clickedRow
        if row >= 0, row < snapshotCount, let s = document?.history.snapshots[row] {
            add(L("Go Back to This Snapshot")) { [weak self] in self?.goBack(to: s) }
            add(L("Rename Snapshot…")) { [weak self] in self?.rename(s) }
            add(L("Delete Snapshot")) { [weak self] in self?.document?.history.removeSnapshot(s) }
            menu.addItem(.separator())
        }
        add(L("New Snapshot")) { [weak self] in self?.takeSnapshot() }
        menu.addItem(.separator())
        for d in HistoryTimeDisplay.allCases {
            let item = NSMenuItem(title: d.title, action: nil, keyEquivalent: "")
            item.state = d == .current ? .on : .off
            item.onAction { _ in HistoryTimeDisplay.current = d }
            menu.addItem(item)
        }
    }

    // MARK: - Snapshots

    private func name(of s: HistorySnapshot) -> String { s.customName ?? LF("Snapshot %d", s.number) }

    func takeSnapshot() {
        guard let h = document?.history else { return }
        host?.commitPendingTool()
        h.takeSnapshot()
    }

    func goBack(to s: HistorySnapshot) {
        guard let h = document?.history else { return }
        host?.commitPendingTool()
        h.restore(s, name: LF("Back to %@", name(of: s)), icon: "history.snapshot")
    }

    private func rename(_ s: HistorySnapshot) {
        guard let h = document?.history, let window = host?.window else { return }
        let alert = NSAlert()
        alert.messageText = L("Rename Snapshot")
        let field = NSTextField(string: s.customName ?? "")
        field.placeholderString = LF("Snapshot %d", s.number)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 22)
        alert.accessoryView = field
        alert.addButton(withTitle: L("Rename"))
        alert.addButton(withTitle: L("Cancel"))
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { r in
            if r == .alertFirstButtonReturn { h.rename(s, to: field.stringValue.trimmingCharacters(in: .whitespaces)) }
        }
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
            let n = snapshotCount
            table.selectRowIndexes(IndexSet(integer: n + h.currentIndex), byExtendingSelection: false)
            table.scrollRowToVisible(n + min(h.items.count - 1, h.currentIndex + 1))
        }
        reloading = false
        let h = document?.history
        snapshotButton.isEnabled = h != nil
        undoButton.isEnabled = h?.canUndo ?? false
        redoButton.isEnabled = h?.canRedo ?? false
        rewindButton.isEnabled = h?.canUndo ?? false
        forwardButton.isEnabled = h?.canRedo ?? false
    }

    func numberOfRows(in tableView: NSTableView) -> Int { snapshotCount + (document?.history.items.count ?? 0) }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { row < snapshotCount ? 34 : 20 }

    /// Only steps are selected (the current one); clicking a snapshot goes back to it as a new step.
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { row >= snapshotCount }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let h = document?.history else { return nil }
        if row < snapshotCount {
            let s = h.snapshots[row]
            let cell = HistoryCell(iconSize: 28, separator: row == snapshotCount - 1)
            cell.icon.image = HistoryCell.thumbnail(s.thumbnail, side: 28)
            cell.name.stringValue = name(of: s)
            cell.name.textColor = .labelColor
            cell.time.textColor = .secondaryLabelColor
            cell.date = s.date
            cell.note = L("Click to go back to this snapshot. Snapshots are not saved in the file.")
            cell.showTime(.current, now: Date())
            return cell
        }
        let index = row - snapshotCount
        guard index < h.items.count else { return nil }
        let item = h.items[index]
        let cell = HistoryCell()
        cell.icon.image = Icons.image(item.icon, size: 16)
        cell.name.stringValue = item.name
        cell.date = item.date
        let undone = index > h.currentIndex
        cell.name.textColor = undone ? .tertiaryLabelColor : .labelColor
        cell.time.textColor = undone ? .tertiaryLabelColor : .secondaryLabelColor
        cell.icon.alphaValue = undone ? 0.4 : 1
        cell.showTime(.current, now: Date())
        return cell
    }

    private var toggledFrom: Int?
    /// Set when the click already moved the selection (a plain jump, not a toggle).
    private var clickChangedSelection = false

    /// Clicking the current entry again toggles between it and the previous step (quick before/after comparison).
    @objc private func rowClicked() {
        guard let h = document?.history, table.clickedRow >= 0 else { return }
        if table.clickedRow < snapshotCount {
            toggledFrom = nil
            goBack(to: h.snapshots[table.clickedRow])
            return
        }
        if clickChangedSelection {
            clickChangedSelection = false
            toggledFrom = nil
            return
        }
        let row = table.clickedRow - snapshotCount
        if row == h.currentIndex, row > 0, toggledFrom == nil {
            toggledFrom = row
            host?.historyStep(to: row - 1)
        } else if let from = toggledFrom, row == from - 1 || row == from {
            toggledFrom = nil
            host?.historyStep(to: from)
        } else {
            toggledFrom = nil
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !reloading, table.selectedRow >= snapshotCount else { return }
        clickChangedSelection = true
        host?.historyStep(to: table.selectedRow - snapshotCount)
    }
}
