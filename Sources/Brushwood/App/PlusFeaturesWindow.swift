import AppKit
import BrushwoodCore

/// Brushwood Plus › Plus Features…: turns each Plus feature, or a whole category, on or off, right away. Opens by
/// itself at the first launch and after each update, with the features the update brought marked New.
final class PlusFeaturesWindow: NSWindow {
    /// Called once, when the window closes.
    var onClose: (() -> Void)?
    private var categoryBoxes: [(PlusCategory, NSButton)] = []
    private var featureBoxes: [(PlusFeature, NSButton)] = []
    private var observer: NSObjectProtocol?
    private static let width: CGFloat = 520

    init(occasion: PlusFeaturesPrompt.Occasion) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 400), styleMask: [.titled, .closable],
                   backing: .buffered, defer: false)
        title = L("Plus Features")
        isReleasedWhenClosed = false
        let margin: CGFloat = 20

        let icon = NSImageView(image: NSApp.applicationIconImage ?? AppIcon.image)
        icon.imageScaling = .scaleProportionallyUpOrDown
        let heading: String, intro: String
        switch occasion {
        case .firstLaunch:
            heading = L("Welcome to Brushwood")
            intro = L("Brushwood Plus adds features that Paint.NET does not have. Choose the ones you want to use.")
        case .update:
            heading = L("What's New in Brushwood Plus")
            intro = LF("Brushwood Plus has been updated to version %@. What this update brings is marked New. Choose the features you want to use.",
                       AppVersion.current?.description ?? "?")
        case .menu:
            heading = L("Plus Features")
            intro = L("Choose the Brushwood Plus features you want to use.")
        }
        let textWidth = Self.width - 2 * margin - 64 - 14
        let headingLabel = NSTextField(wrappingLabelWithString: heading)
        headingLabel.font = .boldSystemFont(ofSize: 15)
        headingLabel.preferredMaxLayoutWidth = textWidth
        let introLabel = NSTextField(wrappingLabelWithString: intro)
        introLabel.textColor = .secondaryLabelColor
        introLabel.preferredMaxLayoutWidth = textWidth
        let headerText = NSStackView(views: [headingLabel, introLabel])
        headerText.orientation = .vertical
        headerText.alignment = .leading
        headerText.spacing = 4

        // The list scrolls once there are more features than the screen has room for.
        let list = NSStackView()
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 8
        let detailsWidth = Self.width - 2 * margin - 40
        for (i, category) in PlusCategory.allCases.enumerated() {
            let box = NSButton(checkboxWithTitle: category.title, target: nil, action: nil)
            box.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
            // On, off, or mixed when only some of its features are on; a click turns them all on, or all off.
            box.allowsMixedState = true
            box.onAction { _ in PlusFeature.set(category.features, enabled: !category.features.allSatisfy(\.isEnabled)) }
            categoryBoxes.append((category, box))
            if i > 0 { list.setCustomSpacing(16, after: list.arrangedSubviews.last!) }
            list.addArrangedSubview(box)
            for feature in category.features {
                let check = NSButton(checkboxWithTitle: feature.name, target: nil, action: nil)
                check.onAction { _ in PlusFeature.set([feature], enabled: check.state == .on) }
                featureBoxes.append((feature, check))
                let line = NSStackView(views: feature.isNew ? [check, TagPill(L("NEW"))] : [check])
                line.spacing = 6
                let details = NSTextField(wrappingLabelWithString: feature.details)
                details.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
                details.textColor = .secondaryLabelColor
                details.preferredMaxLayoutWidth = detailsWidth
                let item = NSStackView(views: [line, details])
                item.orientation = .vertical
                item.alignment = .leading
                item.spacing = 2
                list.addArrangedSubview(item)
                // Features under their category; descriptions under their names.
                item.leadingAnchor.constraint(equalTo: list.leadingAnchor, constant: 20).isActive = true
                details.leadingAnchor.constraint(equalTo: line.leadingAnchor, constant: 20).isActive = true
            }
        }
        let document = FlippedView()
        list.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(list)
        NSLayoutConstraint.activate([
            list.topAnchor.constraint(equalTo: document.topAnchor, constant: 14),
            list.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: margin),
            list.trailingAnchor.constraint(lessThanOrEqualTo: document.trailingAnchor, constant: -margin),
            list.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -14),
        ])
        let scroll = NSScrollView()
        scroll.documentView = document
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        document.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
        ])

        let note = NSTextField(wrappingLabelWithString: L("Changes apply right away. To come back here later, choose Brushwood Plus › Plus Features…"))
        note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        note.textColor = .secondaryLabelColor
        note.preferredMaxLayoutWidth = Self.width - 2 * margin - 110
        let done = NSButton(title: L("Done"), target: nil, action: nil)
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        done.onAction { [weak self] _ in self?.close() }

        let content = NSView()
        let top = NSBox(), bottom = NSBox()
        top.boxType = .separator
        bottom.boxType = .separator
        for v in [icon, headerText, top, scroll, bottom, note, done] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }
        document.layoutSubtreeIfNeeded()
        // Room left on the screen once the header, the bottom bar and the title bar are counted.
        let room = max(300, (NSScreen.main?.visibleFrame.height ?? 800) - 260)
        let listHeight = min(room, list.fittingSize.height + 28)
        NSLayoutConstraint.activate([
            content.widthAnchor.constraint(equalToConstant: Self.width),
            icon.topAnchor.constraint(equalTo: content.topAnchor, constant: margin),
            icon.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: margin),
            icon.widthAnchor.constraint(equalToConstant: 64),
            icon.heightAnchor.constraint(equalToConstant: 64),
            headerText.topAnchor.constraint(equalTo: content.topAnchor, constant: margin + 4),
            headerText.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 14),
            headerText.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -margin),
            top.topAnchor.constraint(greaterThanOrEqualTo: icon.bottomAnchor, constant: 16),
            top.topAnchor.constraint(greaterThanOrEqualTo: headerText.bottomAnchor, constant: 16),
            top.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            top.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: top.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.heightAnchor.constraint(equalToConstant: listHeight),
            bottom.topAnchor.constraint(equalTo: scroll.bottomAnchor),
            bottom.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bottom.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            note.topAnchor.constraint(equalTo: bottom.bottomAnchor, constant: 14),
            note.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: margin),
            note.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -margin),
            done.leadingAnchor.constraint(greaterThanOrEqualTo: note.trailingAnchor, constant: 12),
            done.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -margin),
            done.topAnchor.constraint(equalTo: bottom.bottomAnchor, constant: 12),
            done.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -margin),
        ])
        contentView = content
        setContentSize(content.fittingSize)
        refresh()
        // Also follows changes made elsewhere.
        observer = NotificationCenter.default.addObserver(forName: .plusFeaturesChanged, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit { observer.map(NotificationCenter.default.removeObserver) }

    private func refresh() {
        for (feature, box) in featureBoxes { box.state = feature.isEnabled ? .on : .off }
        for (category, box) in categoryBoxes {
            let on = category.features.filter(\.isEnabled).count
            box.state = on == category.features.count ? .on : on == 0 ? .off : .mixed
        }
    }

    /// Clicks a category's or a feature's checkbox, named like `painting` or `smoothing` (UI tests).
    func debugClick(_ name: String) {
        let box = categoryBoxes.first { "\($0.0)" == name }?.1 ?? featureBoxes.first { $0.0.rawValue == name }?.1
        box?.performClick(nil)
    }

    override func close() {
        super.close()
        let done = onClose
        onClose = nil
        done?()
    }
}

/// A small orange tag: "NEW" next to the features brought by the last update, "PLUS" on the tutorial's steps about
/// Brushwood Plus features.
final class TagPill: NSView {
    private let text: NSAttributedString

    init(_ string: String) {
        text = NSAttributedString(string: string, attributes: [
            .font: NSFont.systemFont(ofSize: 9.5, weight: .bold), .foregroundColor: NSColor.white,
        ])
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: ceil(text.size().width) + 12, height: 16) }

    override func draw(_ dirtyRect: NSRect) {
        // The orange of the "+" on the app icon.
        NSColor(srgbRed: 0.95, green: 0.45, blue: 0.12, alpha: 1).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
        let size = text.size()
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }
}
