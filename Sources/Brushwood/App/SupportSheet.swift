import AppKit
import BrushwoodCore

/// "Help Brushwood keep growing": shown once after an update, and from Brushwood › Support Brushwood….
final class SupportSheet: NSWindow {
    static let donateURL = URL(string: "https://buymeacoffee.com/balaborde")!
    static let repositoryURL = URL(string: "https://github.com/balaborde/brushwood")!
    private static var shown: SupportSheet?

    /// Attaches the sheet to `parent`, or shows it as a window when there is none.
    static func present(over parent: NSWindow?) {
        guard shown == nil else {
            shown?.makeKeyAndOrderFront(nil)
            return
        }
        let sheet = SupportSheet()
        shown = sheet
        if let parent, parent.isVisible {
            parent.beginSheet(sheet) { _ in shown = nil }
        } else {
            sheet.center()
            sheet.makeKeyAndOrderFront(nil)
        }
    }

    private init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 560, height: 440), styleMask: [.titled, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { standardWindowButton(b)?.isHidden = true }

        let title = NSTextField(wrappingLabelWithString: L("Help Brushwood keep growing"))
        title.font = .systemFont(ofSize: 20, weight: .bold)
        title.alignment = .center
        title.preferredMaxLayoutWidth = 480
        let message = NSTextField(wrappingLabelWithString: Self.keepBrandTogether(
            L("If you would like to support development financially, Buy Me a Coffee is the one place to do it.")))
        message.font = .systemFont(ofSize: 14)
        message.textColor = .secondaryLabelColor
        message.alignment = .center
        message.preferredMaxLayoutWidth = 480
        let donate = CapsuleButton(title: L("Support on Buy Me a Coffee"), symbol: "cup.and.saucer.fill")
        donate.onAction { _ in NSWorkspace.shared.open(SupportSheet.donateURL) }
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let thanks = NSTextField(labelWithString: L("Thank you for being here.") + (dark ? " 🤍" : " 🖤"))
        thanks.font = .systemFont(ofSize: 11.5)
        thanks.textColor = .tertiaryLabelColor
        let star = LinkLabel(text: L("A star on GitHub also helps more people find Brushwood, and it means a lot."), symbol: "star",
                             url: SupportSheet.repositoryURL)

        let stack = NSStackView(views: [HeartBadge(), title, message, donate, thanks, star])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.setCustomSpacing(18, after: stack.arrangedSubviews[0])
        stack.setCustomSpacing(18, after: message)
        stack.setCustomSpacing(16, after: donate)
        stack.setCustomSpacing(26, after: thanks)
        stack.edgeInsets = NSEdgeInsets(top: 64, left: 40, bottom: 44, right: 40)

        let done = NSButton(title: L("Done"), target: nil, action: nil)
        done.bezelStyle = .rounded
        done.controlSize = .large
        done.keyEquivalent = "\r"
        done.onAction { [weak self] _ in self?.dismiss() }
        done.widthAnchor.constraint(greaterThanOrEqualToConstant: 72).isActive = true
        let separator = NSBox()
        separator.boxType = .separator
        let bottom = NSStackView(views: [NSView(), done])
        bottom.edgeInsets = NSEdgeInsets(top: 14, left: 20, bottom: 16, right: 16)

        let root = NSStackView(views: [stack, separator, bottom])
        root.orientation = .vertical
        root.spacing = 0
        for v in [stack, separator, bottom] { v.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true }
        root.widthAnchor.constraint(equalToConstant: 560).isActive = true
        contentView = root
        setContentSize(root.fittingSize)
    }

    override func cancelOperation(_ sender: Any?) { dismiss() }

    /// Keeps "Buy Me a Coffee" on one line wherever the translation puts it.
    private static func keepBrandTogether(_ s: String) -> String {
        s.replacingOccurrences(of: "Buy Me a Coffee", with: "Buy\u{a0}Me\u{a0}a\u{a0}Coffee")
    }

    private func dismiss() {
        if let parent = sheetParent {
            parent.endSheet(self)
        } else {
            close()
            SupportSheet.shown = nil
        }
    }
}

/// Decides at launch whether to thank people for updating: the first launch of a newer version shows the support sheet
/// (not the very first launch after installing).
enum SupportPrompt {
    private static let lastVersionKey = "lastRunVersion"
    private(set) static var due = false

    /// Call before anything writes to the defaults, so the first launch can be told apart.
    static func noteLaunch() {
        guard let current = AppVersion.current, ProcessInfo.processInfo.environment["BRUSHWOOD_SNAPSHOT"] == nil else { return }
        let d = UserDefaults.standard
        let previous = d.string(forKey: lastVersionKey).flatMap(AppVersion.init)
        // Versions before 1.0.2 did not record their version, but any saved setting means one of them ran before.
        let ranBefore = previous != nil || !(d.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?.isEmpty ?? true)
        due = ranBefore && (previous.map { $0 < current } ?? true)
        d.set(current.description, forKey: lastVersionKey)
    }
}

/// Round badge with a heart: black in Light Mode, white in Dark Mode.
private final class HeartBadge: NSView {
    override var intrinsicContentSize: NSSize { NSSize(width: 74, height: 74) }

    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let circle = NSBezierPath(ovalIn: bounds)
        let colors = dark ? [NSColor.white, NSColor(white: 0.84, alpha: 1)] : [NSColor(white: 0.17, alpha: 1), NSColor.black]
        NSGradient(starting: colors[0], ending: colors[1])?.draw(in: circle, angle: -60)
        guard let heart = NSImage(systemSymbolName: "heart.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 30, weight: .regular)) else { return }
        let tinted = heart.tinted(dark ? .black : .white)
        tinted.draw(in: NSRect(x: bounds.midX - heart.size.width / 2, y: bounds.midY - heart.size.height / 2,
                               width: heart.size.width, height: heart.size.height))
    }
}

/// Blue capsule button with a symbol and white text.
private final class CapsuleButton: NSButton {
    private var symbol: NSImage?

    convenience init(title: String, symbol name: String) {
        self.init(frame: .zero)
        self.title = title
        symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .medium))
        isBordered = false
        font = .systemFont(ofSize: 14, weight: .medium)
        setAccessibilityLabel(title)
    }

    override var intrinsicContentSize: NSSize {
        let text = (title as NSString).size(withAttributes: [.font: font as Any])
        return NSSize(width: ceil(text.width) + (symbol.map { $0.size.width + 10 } ?? 0) + 44, height: 28)
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.height / 2
        let base = NSColor.controlAccentColor
        (isHighlighted ? base.shadow(withLevel: 0.2) ?? base : base).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: r, yRadius: r).fill()
        let attrs: [NSAttributedString.Key: Any] = [.font: font as Any, .foregroundColor: NSColor.white]
        let text = (title as NSString).size(withAttributes: attrs)
        let icon = symbol?.size ?? .zero
        let gap: CGFloat = symbol == nil ? 0 : 10
        var x = (bounds.width - icon.width - gap - text.width) / 2
        if let symbol {
            symbol.tinted(.white).draw(in: NSRect(x: x, y: bounds.midY - icon.height / 2, width: icon.width, height: icon.height),
                                       from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            x += icon.width + gap
        }
        (title as NSString).draw(at: NSPoint(x: x, y: bounds.midY - text.height / 2), withAttributes: attrs)
    }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
    }

    override var focusRingMaskBounds: NSRect { bounds }
}

/// Centered, wrapping text that opens a link when clicked, with a symbol at the start of its first line.
private final class LinkLabel: NSTextField {
    private var url: URL!

    convenience init(text: String, symbol name: String, url: URL) {
        self.init(wrappingLabelWithString: "")
        self.url = url
        let font = NSFont.systemFont(ofSize: 12)
        let s = NSMutableAttributedString()
        if let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)) {
            let attachment = NSTextAttachment()
            attachment.image = image.tinted(.secondaryLabelColor)
            attachment.bounds = NSRect(x: 0, y: (font.capHeight - image.size.height) / 2, width: image.size.width,
                                       height: image.size.height)
            s.append(NSAttributedString(attachment: attachment))
            s.append(NSAttributedString(string: "\u{2002}"))
        }
        s.append(NSAttributedString(string: text))
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        s.addAttributes([.font: font, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: para],
                        range: NSRange(location: 0, length: s.length))
        attributedStringValue = s
        preferredMaxLayoutWidth = 480
        setAccessibilityRole(.link)
        setAccessibilityLabel(text)
        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(open)))
    }

    @objc private func open() { NSWorkspace.shared.open(url) }

    override func accessibilityPerformPress() -> Bool {
        open()
        return true
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

private extension NSImage {
    /// The image (typically a symbol) in one color, keeping its shape's transparency.
    func tinted(_ color: NSColor) -> NSImage {
        NSImage(size: size, flipped: false) { r in
            self.draw(in: r)
            color.set()
            r.fill(using: .sourceIn)
            return true
        }
    }
}
