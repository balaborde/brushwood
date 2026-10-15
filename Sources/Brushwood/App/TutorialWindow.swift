import AppKit
import BrushwoodCore

/// Help › Tutorial… and Brushwood Plus › Tutorial…: the tours, by section (Brushwood's first, then Brushwood Plus's).
/// Pick one and Start; when it is done, the window comes back with the next one selected. At the first launch it opens
/// by itself, as an offer.
final class TutorialWindow: NSWindow, NSTableViewDataSource, NSTableViewDelegate {
    private enum Row {
        case section(String)
        case tour(TutorialScenario)
    }

    /// Starts a tour (the app delegate hides this window and runs it).
    var onStart: ((TutorialScenario) -> Void)?
    private var rows: [Row] = []
    private let table = NSTableView()
    private let headingLabel = NSTextField(wrappingLabelWithString: "")
    private let introLabel = NSTextField(wrappingLabelWithString: "")
    private let closeButton = NSButton(title: "", target: nil, action: nil)
    private let startButton = NSButton(title: L("Start"), target: nil, action: nil)
    private static let width: CGFloat = 520

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 560), styleMask: [.titled, .closable],
                   backing: .buffered, defer: false)
        title = L("Tutorial")
        isReleasedWhenClosed = false
        let margin: CGFloat = 20

        let icon = NSImageView(image: NSApp.applicationIconImage ?? AppIcon.image)
        icon.imageScaling = .scaleProportionallyUpOrDown
        headingLabel.font = .boldSystemFont(ofSize: 15)
        headingLabel.preferredMaxLayoutWidth = Self.width - 2 * margin - 78
        introLabel.textColor = .secondaryLabelColor
        introLabel.preferredMaxLayoutWidth = headingLabel.preferredMaxLayoutWidth
        let header = NSStackView(views: [headingLabel, introLabel])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 4

        let column = NSTableColumn(identifier: .init("tour"))
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .inset
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(startSelected)
        table.allowsEmptySelection = true
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        closeButton.bezelStyle = .rounded
        closeButton.keyEquivalent = "\u{1b}"
        closeButton.onAction { [weak self] _ in self?.close() }
        startButton.bezelStyle = .rounded
        startButton.keyEquivalent = "\r"
        startButton.onAction { [weak self] _ in self?.startSelected() }

        let content = NSView()
        let line = NSBox()
        line.boxType = .separator
        for v in [icon, header, line, scroll, closeButton, startButton] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }
        NSLayoutConstraint.activate([
            content.widthAnchor.constraint(equalToConstant: Self.width),
            icon.topAnchor.constraint(equalTo: content.topAnchor, constant: margin),
            icon.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: margin),
            icon.widthAnchor.constraint(equalToConstant: 64),
            icon.heightAnchor.constraint(equalToConstant: 64),
            header.topAnchor.constraint(equalTo: content.topAnchor, constant: margin + 4),
            header.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 14),
            header.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -margin),
            line.topAnchor.constraint(greaterThanOrEqualTo: icon.bottomAnchor, constant: 14),
            line.topAnchor.constraint(greaterThanOrEqualTo: header.bottomAnchor, constant: 14),
            line.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: line.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 380),
            startButton.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 14),
            startButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -margin),
            startButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -margin),
            closeButton.centerYAnchor.constraint(equalTo: startButton.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: startButton.leadingAnchor, constant: -10),
        ])
        contentView = content
        // Tours of Plus features follow their features being turned on or off.
        NotificationCenter.default.addObserver(forName: .plusFeaturesChanged, object: nil, queue: .main) { [weak self] _ in
            self?.reload(selecting: self?.selectedTour?.id)
        }
    }

    /// At the first launch the window is an offer ("Not Now"); otherwise a plain list ("Close").
    func configure(welcome: Bool) {
        headingLabel.stringValue = welcome ? L("Take a Quick Tour?") : L("Tutorial")
        introLabel.stringValue = welcome
            ? L("Short guided tours show where things are and what each tool and its settings do. Pick one to start; the others stay in Help › Tutorial…")
            : L("Pick a tour and click Start. Each one points at the parts of the window it explains.")
        closeButton.title = welcome ? L("Not Now") : L("Close")
        contentView?.layoutSubtreeIfNeeded()
        setContentSize(contentView?.fittingSize ?? frame.size)
    }

    /// Lists the tours again (to show which are done), selecting `id`, or the first tour not done yet.
    func reload(selecting id: String? = nil) {
        rows = Tutorial.sections.flatMap { [Row.section($0.title)] + $0.scenarios.map(Row.tour) }
        table.reloadData()
        let tours = rows.enumerated().compactMap { i, r -> (Int, TutorialScenario)? in
            if case .tour(let s) = r, s.isAvailable { return (i, s) }
            return nil
        }
        let pick = tours.first { $0.1.id == id } ?? tours.first { !$0.1.isCompleted } ?? tours.first
        if let pick {
            table.selectRowIndexes(IndexSet(integer: pick.0), byExtendingSelection: false)
            table.scrollRowToVisible(pick.0)
        }
        startButton.isEnabled = selectedTour != nil
    }

    /// The tour after `id` that can be followed, if any.
    static func tour(after id: String) -> String? {
        let tours = Tutorial.sections.flatMap(\.scenarios).filter(\.isAvailable)
        guard let i = tours.firstIndex(where: { $0.id == id }), i + 1 < tours.count else { return nil }
        return tours[i + 1].id
    }

    private var selectedTour: TutorialScenario? {
        guard table.selectedRow >= 0, table.selectedRow < rows.count, case .tour(let s) = rows[table.selectedRow] else { return nil }
        return s
    }

    @objc private func startSelected() {
        guard let tour = selectedTour, tour.isAvailable else { return }
        onStart?(tour)
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        if case .section = rows[row] { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard case .tour(let tour) = rows[row] else { return 28 }
        // Room for the title and the summary, which wraps onto a second line when it is long.
        let summary = TourCell.summary(of: tour) as NSString
        let height = summary.boundingRect(with: NSSize(width: tableView.bounds.width - 80, height: 200),
                                          options: .usesLineFragmentOrigin, attributes: [.font: TourCell.summaryFont]).height
        return 30 + ceil(height)
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if case .tour(let s) = rows[row] { return s.isAvailable }
        return false
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        startButton.isEnabled = selectedTour != nil
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .section(let title):
            let label = NSTextField(labelWithString: title)
            label.font = .boldSystemFont(ofSize: NSFont.smallSystemFontSize)
            label.textColor = .secondaryLabelColor
            return label
        case .tour(let tour):
            return TourCell(tour, summaryWidth: tableView.bounds.width - 80)
        }
    }
}

/// A tour in the list: a check when it was followed to the end, its title and what it shows.
private final class TourCell: NSTableCellView {
    static let summaryFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

    /// What the tour shows, or why it cannot be followed.
    static func summary(of tour: TutorialScenario) -> String {
        tour.isAvailable ? tour.summary : L("Turn its features on in Plus Features to follow this tour.")
    }

    init(_ tour: TutorialScenario, summaryWidth: CGFloat) {
        super.init(frame: .zero)
        let available = tour.isAvailable
        let mark = NSImageView(image: NSImage(systemSymbolName: tour.isCompleted ? "checkmark.circle.fill" : "circle",
                                              accessibilityDescription: tour.isCompleted ? L("Done") : nil) ?? NSImage())
        mark.contentTintColor = tour.isCompleted ? .controlAccentColor : .tertiaryLabelColor
        let title = NSTextField(labelWithString: tour.title)
        title.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        title.textColor = available ? .labelColor : .tertiaryLabelColor
        let summary = NSTextField(wrappingLabelWithString: Self.summary(of: tour))
        summary.font = Self.summaryFont
        summary.textColor = available ? .secondaryLabelColor : .tertiaryLabelColor
        summary.preferredMaxLayoutWidth = summaryWidth
        title.lineBreakMode = .byTruncatingTail
        for v in [mark, title, summary] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            mark.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            mark.centerYAnchor.constraint(equalTo: centerYAnchor),
            mark.widthAnchor.constraint(equalToConstant: 16),
            mark.heightAnchor.constraint(equalToConstant: 16),
            title.leadingAnchor.constraint(equalTo: mark.trailingAnchor, constant: 10),
            title.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            summary.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            summary.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            summary.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 1),
        ])
        toolTip = available ? tour.summary : nil
    }

    required init?(coder: NSCoder) { fatalError() }
}
