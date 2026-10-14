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

/// A History row: icon, name and, at the right, when the step was made.
private final class HistoryCell: NSTableCellView {
    let icon = NSImageView()
    let name = NSTextField(labelWithString: "")
    let time = NSTextField(labelWithString: "")
    var date: Date?

    init() {
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
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            name.trailingAnchor.constraint(lessThanOrEqualTo: time.leadingAnchor, constant: -6),
            name.centerYAnchor.constraint(equalTo: centerYAnchor),
            time.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            time.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func showTime(_ display: HistoryTimeDisplay, now: Date) {
        time.stringValue = date.map { display.text(for: $0, now: now) } ?? ""
        toolTip = date.map { name.stringValue + "\n" + HistoryTimeDisplay.fullText(for: $0) }
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
        // Paint.NET 5 has just Undo and Redo here.
        let bar = NSStackView(views: [undoButton, redoButton])
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
        for d in HistoryTimeDisplay.allCases {
            let item = NSMenuItem(title: d.title, action: nil, keyEquivalent: "")
            item.state = d == .current ? .on : .off
            item.onAction { _ in HistoryTimeDisplay.current = d }
            menu.addItem(item)
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
        let cell = HistoryCell()
        cell.icon.image = Icons.image(item.icon, size: 16)
        cell.name.stringValue = item.name
        cell.date = item.date
        let undone = row > h.currentIndex
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
        if clickChangedSelection {
            clickChangedSelection = false
            toggledFrom = nil
            return
        }
        let row = table.clickedRow
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
        guard !reloading, table.selectedRow >= 0 else { return }
        clickChangedSelection = true
        host?.historyStep(to: table.selectedRow)
    }
}
