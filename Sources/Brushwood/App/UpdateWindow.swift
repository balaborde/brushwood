import AppKit
import BrushwoodCore

/// The Software Update window: checking, result, release notes, download progress and errors.
final class UpdateWindow: NSWindow, NSWindowDelegate {
    enum State {
        case checking
        case upToDate
        case checkFailed
        case available(Release)
        case downloading(Release, Int64, Int64)
        case installing(Release)
        case installFailed(String, Release)
    }

    var onInstall: ((Release) -> Void)?
    /// Called when the window closes or Cancel is pressed during a download.
    var onCancel: (() -> Void)?

    private let titleLabel = NSTextField(wrappingLabelWithString: "")
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let extras = NSStackView()
    private let buttons = NSStackView()
    private let progress = NSProgressIndicator()
    private let progressLabel = NSTextField(labelWithString: "")
    private var downloading = false

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 480, height: 160), styleMask: [.titled, .closable], backing: .buffered,
                   defer: false)
        title = L("Software Update")
        isReleasedWhenClosed = false
        delegate = self

        let icon = NSImageView(image: NSApp.applicationIconImage ?? AppIcon.image)
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 64), icon.heightAnchor.constraint(equalToConstant: 64)])
        titleLabel.font = .boldSystemFont(ofSize: 14)
        titleLabel.preferredMaxLayoutWidth = 360
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.preferredMaxLayoutWidth = 360
        extras.orientation = .vertical
        extras.alignment = .leading
        extras.spacing = 6
        progress.style = .bar
        progress.minValue = 0
        progress.maxValue = 1
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.widthAnchor.constraint(equalToConstant: 360).isActive = true
        progressLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        progressLabel.textColor = .secondaryLabelColor

        let text = NSStackView(views: [titleLabel, messageLabel, extras])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 6
        text.widthAnchor.constraint(equalToConstant: 360).isActive = true
        let top = NSStackView(views: [icon, text])
        top.alignment = .top
        top.spacing = 16
        buttons.spacing = 8
        buttons.addArrangedSubview(NSView()) // pushes the buttons to the right
        let root = NSStackView(views: [top, buttons])
        root.orientation = .vertical
        root.alignment = .width
        root.spacing = 16
        root.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 18, right: 20)
        root.widthAnchor.constraint(equalToConstant: 480).isActive = true
        contentView = root
    }

    func show(_ state: State) {
        if case .downloading(_, let done, let total) = state, downloading {
            updateProgress(done, total)
            return
        }
        downloading = false
        extras.arrangedSubviews.forEach { $0.removeFromSuperview() }
        buttons.arrangedSubviews.dropFirst().forEach { $0.removeFromSuperview() }
        let current = AppVersion.current?.description ?? "?"
        switch state {
        case .checking:
            set(L("Checking for updates…"), "")
            progress.isIndeterminate = true
            progress.startAnimation(nil)
            extras.addArrangedSubview(progress)
            addButton(L("Cancel"), key: "\u{1b}") { [weak self] in self?.close() }
        case .upToDate:
            set(L("Brushwood is up to date"), LF("Version %@ is the latest version.", current))
            addButton(L("OK"), key: "\r") { [weak self] in self?.close() }
        case .checkFailed:
            set(L("Could not check for updates"), L("Check your internet connection and try again."))
            addButton(L("OK"), key: "\r") { [weak self] in self?.close() }
        case .available(let release):
            set(L("A new version of Brushwood is available"),
                LF("Brushwood %@ is available. You have version %@.", release.version.description, current))
            let notes = Self.notesText(release.notes)
            if notes.length > 0 {
                let header = NSTextField(labelWithString: L("What's New"))
                header.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
                extras.addArrangedSubview(header)
                extras.addArrangedSubview(notesView(notes))
            }
            addButton(L("Later"), key: "\u{1b}") { [weak self] in self?.close() }
            addButton(L("Install and Relaunch"), key: "\r") { [weak self] in self?.onInstall?(release) }
        case .downloading(let release, let done, let total):
            downloading = true
            set(L("Downloading…"), LF("Brushwood %@ is available. You have version %@.", release.version.description, current))
            progress.isIndeterminate = false
            extras.addArrangedSubview(progress)
            extras.addArrangedSubview(progressLabel)
            updateProgress(done, total)
            addButton(L("Cancel"), key: "\u{1b}") { [weak self] in
                self?.onCancel?()
                self?.show(.available(release))
            }
        case .installing:
            set(L("Installing…"), "")
            progress.isIndeterminate = true
            progress.startAnimation(nil)
            extras.addArrangedSubview(progress)
        case .installFailed(let message, let release):
            set(L("The update could not be installed"), message)
            addButton(L("Close"), key: "\u{1b}") { [weak self] in self?.close() }
            addButton(L("Download from GitHub"), key: "\r") { [weak self] in
                NSWorkspace.shared.open(release.page)
                self?.close()
            }
        }
        let top = frame.maxY
        layoutIfNeeded()
        setContentSize(contentView!.fittingSize)
        setFrameTopLeftPoint(NSPoint(x: frame.minX, y: top))
    }

    func windowWillClose(_ notification: Notification) {
        if downloading { onCancel?() }
        downloading = false
    }

    private func set(_ title: String, _ message: String) {
        titleLabel.stringValue = title
        messageLabel.stringValue = message
        messageLabel.isHidden = message.isEmpty
    }

    /// `key` is Return for the default button, Escape for the one that dismisses.
    private func addButton(_ title: String, key: String, _ action: @escaping () -> Void) {
        let b = NSButton(title: title, target: nil, action: nil)
        b.bezelStyle = .rounded
        b.keyEquivalent = key
        b.onAction { _ in action() }
        b.widthAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true
        buttons.addArrangedSubview(b)
    }

    private func updateProgress(_ done: Int64, _ total: Int64) {
        progress.doubleValue = total > 0 ? Double(done) / Double(total) : 0
        let f = ByteCountFormatter()
        f.countStyle = .file
        progressLabel.stringValue = total > 0 ? LF("%@ of %@", f.string(fromByteCount: done), f.string(fromByteCount: total)) : ""
    }

    private func notesView(_ text: NSAttributedString) -> NSView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([scroll.widthAnchor.constraint(equalToConstant: 360), scroll.heightAnchor.constraint(equalToConstant: 170)])
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 360, height: 170))
        tv.isEditable = false
        tv.textContainerInset = NSSize(width: 6, height: 6)
        tv.autoresizingMask = [.width]
        tv.textStorage?.setAttributedString(text)
        scroll.documentView = tv
        return scroll
    }

    /// Release notes are Markdown. Shows headings in bold, list items with bullets and inline bold, italic, code and
    /// links, joining hard-wrapped lines. Stops at an "Install…" heading: those steps are for downloading by hand.
    static func notesText(_ markdown: String) -> NSAttributedString {
        var blocks: [(text: String, heading: Bool)] = []
        var open = false
        for raw in markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                open = false
            } else if let r = line.range(of: "^#{1,6}\\s+", options: .regularExpression) {
                let title = String(line[r.upperBound...])
                if title.lowercased().hasPrefix("install") { break }
                blocks.append((title, true))
                open = false
            } else if let r = line.range(of: "^[-*+]\\s+", options: .regularExpression) {
                blocks.append(("•\u{00a0}" + line[r.upperBound...], false))
                open = true
            } else if open, let last = blocks.popLast() {
                blocks.append((last.text + " " + line, false))
            } else {
                blocks.append((line, false))
                open = true
            }
        }
        let out = NSMutableAttributedString()
        let size = NSFont.smallSystemFontSize + 1
        for (i, block) in blocks.enumerated() {
            let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            let piece = (try? NSMutableAttributedString(AttributedString(markdown: block.text, options: options)))
                ?? NSMutableAttributedString(string: block.text)
            let whole = NSRange(location: 0, length: piece.length)
            piece.addAttributes([.font: block.heading ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size),
                                 .foregroundColor: NSColor.labelColor], range: whole)
            piece.enumerateAttribute(.inlinePresentationIntent, in: whole) { value, range, _ in
                guard let raw = value as? UInt else { return }
                let intent = InlinePresentationIntent(rawValue: raw)
                var traits: NSFontDescriptor.SymbolicTraits = []
                if intent.contains(.stronglyEmphasized) { traits.insert(.bold) }
                if intent.contains(.emphasized) { traits.insert(.italic) }
                if intent.contains(.code) {
                    piece.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: size - 1, weight: .regular), range: range)
                } else if !traits.isEmpty {
                    let d = NSFont.systemFont(ofSize: size).fontDescriptor.withSymbolicTraits(traits)
                    piece.addAttribute(.font, value: NSFont(descriptor: d, size: size) ?? NSFont.boldSystemFont(ofSize: size), range: range)
                }
            }
            let para = NSMutableParagraphStyle()
            para.paragraphSpacing = 4
            para.paragraphSpacingBefore = block.heading && i > 0 ? 6 : 0
            if block.text.hasPrefix("•") { para.headIndent = 10 }
            piece.addAttribute(.paragraphStyle, value: para, range: whole)
            if i < blocks.count - 1 { piece.append(NSAttributedString(string: "\n")) }
            out.append(piece)
        }
        return out
    }
}
