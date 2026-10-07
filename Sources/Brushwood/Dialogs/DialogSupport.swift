import AppKit
import BrushwoodCore

/// Base for app-modal dialogs built in code. Runs with `NSApp.runModal` so the canvas keeps redrawing previews.
class ModalDialog: NSWindow, NSWindowDelegate {
    let body = NSStackView()
    private(set) var okButton: NSButton!
    private(set) var cancelButton: NSButton!
    private var result: NSApplication.ModalResponse = .cancel

    init(title: String, okTitle: String = L("OK")) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 360, height: 200), styleMask: [.titled, .closable],
                   backing: .buffered, defer: false)
        self.title = title
        isReleasedWhenClosed = false
        delegate = self
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 8
        body.edgeInsets = NSEdgeInsets(top: 16, left: 18, bottom: 12, right: 18)
        okButton = NSButton(title: okTitle, target: self, action: #selector(okPressed))
        okButton.keyEquivalent = "\r"
        okButton.bezelStyle = .rounded
        cancelButton = NSButton(title: L("Cancel"), target: self, action: #selector(cancelPressed))
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.bezelStyle = .rounded
        let buttons = NSStackView(views: [NSView(), cancelButton, okButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        okButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true
        cancelButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true
        let root = NSStackView(views: [body, buttons])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 0
        root.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 14, right: 0)
        buttons.translatesAutoresizingMaskIntoConstraints = false
        root.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            root.topAnchor.constraint(equalTo: container.topAnchor),
            root.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            buttons.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            buttons.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            body.widthAnchor.constraint(equalTo: root.widthAnchor),
        ])
        contentView = container
    }

    @objc func okPressed() {
        makeFirstResponder(nil)
        result = .OK
        NSApp.stopModal(withCode: .OK)
    }

    @objc func cancelPressed() {
        result = .cancel
        NSApp.stopModal(withCode: .cancel)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.stopModal(withCode: result)
    }

    /// Shows the dialog modally. Positions it beside `parent` (so previews stay visible) or centered.
    func runModal(parent: NSWindow?, beside: Bool = false) -> Bool {
        layoutIfNeeded()
        setContentSize(contentView!.fittingSize)
        if let parent {
            let pf = parent.frame
            if beside {
                setFrameOrigin(NSPoint(x: pf.maxX - frame.width - 40, y: pf.maxY - frame.height - 120))
            } else {
                setFrameOrigin(NSPoint(x: pf.midX - frame.width / 2, y: pf.midY - frame.height / 2 + pf.height / 6))
            }
        } else {
            center()
        }
        let r = NSApp.runModal(for: self)
        orderOut(nil)
        return r == .OK
    }

    // MARK: Layout helpers

    func addSection(_ title: String) {
        let l = NSTextField(labelWithString: title)
        l.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        body.addArrangedSubview(l)
    }

    func addRow(_ views: [NSView], spacing: CGFloat = 8) {
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.spacing = spacing
        row.alignment = .centerY
        body.addArrangedSubview(row)
    }

    func addSeparator() {
        let s = NSBox()
        s.boxType = .separator
        s.translatesAutoresizingMaskIntoConstraints = false
        body.addArrangedSubview(s)
        s.widthAnchor.constraint(equalTo: body.widthAnchor, constant: -36).isActive = true
    }
}

func formLabel(_ s: String, width: CGFloat = 110) -> NSTextField {
    let l = NSTextField(labelWithString: s)
    l.alignment = .right
    l.translatesAutoresizingMaskIntoConstraints = false
    l.widthAnchor.constraint(equalToConstant: width).isActive = true
    return l
}

func numberField(_ value: Double, decimals: Int = 0, width: CGFloat = 80) -> NSTextField {
    let f = NSTextField()
    let fmt = NumberFormatter()
    fmt.numberStyle = .decimal
    fmt.minimumFractionDigits = 0
    fmt.maximumFractionDigits = decimals
    fmt.usesGroupingSeparator = false
    f.formatter = fmt
    f.doubleValue = value
    f.alignment = .right
    f.translatesAutoresizingMaskIntoConstraints = false
    f.widthAnchor.constraint(equalToConstant: width).isActive = true
    return f
}

/// Live-updating text field: calls `handler` on every edit, not only on Return.
final class LiveFieldDelegate: NSObject, NSTextFieldDelegate {
    let handler: (NSTextField) -> Void
    init(_ h: @escaping (NSTextField) -> Void) { handler = h }

    func controlTextDidChange(_ obj: Notification) {
        if let f = obj.object as? NSTextField { handler(f) }
    }
}

private var liveKey: UInt8 = 0

extension NSTextField {
    func onLiveChange(_ handler: @escaping (NSTextField) -> Void) {
        let d = LiveFieldDelegate(handler)
        objc_setAssociatedObject(self, &liveKey, d, .OBJC_ASSOCIATION_RETAIN)
        delegate = d
    }
}
