import AppKit
import BrushwoodCore

/// Runs a tutorial tour: each step brings its part of the window on screen, rings it, and explains it in a popover
/// with Back and Next. The popover stays while you try things out.
final class TutorialGuide: NSObject, NSPopoverDelegate {
    static let shared = TutorialGuide()

    private(set) var scenario: TutorialScenario?
    private(set) var index = 0
    private var steps: [TutorialStep] = []
    private weak var host: MainWindowController?
    private var popover: NSPopover?
    private let card = StepCard()
    private let ring = TutorialRing()
    private var observers: [NSObjectProtocol] = []
    /// Set while the guide itself closes the popover.
    private var closingPopover = false
    /// Called after the last step of a tour (not when it is ended early).
    var onFinish: ((TutorialScenario) -> Void)?

    var isRunning: Bool { scenario != nil }
    var stepCount: Int { steps.count }

    override init() {
        super.init()
        card.onBack = { [weak self] in self?.back() }
        card.onNext = { [weak self] in self?.next() }
        card.onClose = { [weak self] in self?.end() }
    }

    func start(_ scenario: TutorialScenario, host: MainWindowController) {
        end()
        steps = scenario.availableSteps
        guard !steps.isEmpty else { return }
        self.scenario = scenario
        self.host = host
        index = 0
        let nc = NotificationCenter.default
        // Follow the part when windows move or the tool bar changes.
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] n in
                if (n.object as? NSWindow) !== self?.ring { self?.placeRing() }
            })
        }
        for name in [Notification.Name.toolChanged, .plusFeaturesChanged] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.async { self?.placeRing() }
            })
        }
        show()
    }

    func next() {
        guard isRunning else { return }
        if index < steps.count - 1 {
            index += 1
            show()
        } else {
            let done = scenario
            done?.markCompleted()
            end()
            if let done { onFinish?(done) }
        }
    }

    func back() {
        guard isRunning, index > 0 else { return }
        index -= 1
        show()
    }

    func end() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        closingPopover = true
        popover?.close()
        closingPopover = false
        popover = nil
        ring.orderOut(nil)
        scenario = nil
        steps = []
    }

    /// Brings the step's part on screen, then points at it once AppKit has laid it out.
    private func show() {
        guard let host else { return }
        steps[index].prepare(host)
        DispatchQueue.main.async { [weak self] in self?.point() }
    }

    private func point() {
        guard isRunning, let host else { return }
        let step = steps[index]
        guard let target = step.target(host), target.view.window?.isVisible == true else {
            // The part is not there (a window that could not be shown): go on without it.
            index < steps.count - 1 ? next() : end()
            return
        }
        card.show(step, number: index + 1, of: steps.count)
        let p = popover ?? makePopover()
        p.contentSize = card.view.fittingSize
        p.show(relativeTo: target.rect, of: target.view, preferredEdge: step.side.edge(in: target.view))
        placeRing()
    }

    private func makePopover() -> NSPopover {
        let p = NSPopover()
        p.contentViewController = card
        p.behavior = .applicationDefined
        p.animates = true
        p.delegate = self
        popover = p
        return p
    }

    /// Rings the current part, or hides the ring when the part is gone.
    private func placeRing() {
        guard isRunning, let host, let target = steps[index].target(host), let window = target.view.window,
              window.isVisible else {
            ring.orderOut(nil)
            return
        }
        ring.show(around: window.convertToScreen(target.view.convert(target.rect, to: nil)))
    }

    func popoverDidClose(_ notification: Notification) {
        // Closed by AppKit (its part left the screen): end the tour rather than leave the ring alone.
        if !closingPopover, isRunning { end() }
    }

    /// For UI tests: whether the current step's part is on screen.
    var currentTargetFound: Bool {
        guard isRunning, let host else { return false }
        return steps[index].target(host)?.view.window?.isVisible == true
    }
}

/// The popover's content: title, explanation, progress, and Back / Next.
private final class StepCard: NSViewController {
    var onBack: (() -> Void)?
    var onNext: (() -> Void)?
    var onClose: (() -> Void)?
    private let titleLabel = NSTextField(labelWithString: "")
    private let textLabel = NSTextField(wrappingLabelWithString: "")
    private let progress = NSTextField(labelWithString: "")
    private let backButton = NSButton(title: L("Back"), target: nil, action: nil)
    private let nextButton = NSButton(title: L("Next"), target: nil, action: nil)
    private let closeButton = NSButton()

    override func loadView() {
        let width: CGFloat = 300
        titleLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.maximumNumberOfLines = 0
        titleLabel.preferredMaxLayoutWidth = width - 24
        textLabel.preferredMaxLayoutWidth = width
        textLabel.textColor = .secondaryLabelColor
        progress.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        progress.textColor = .tertiaryLabelColor
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: L("End Tutorial"))
        closeButton.isBordered = false
        closeButton.toolTip = L("End Tutorial")
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.onAction { [weak self] _ in self?.onClose?() }
        for b in [backButton, nextButton] {
            b.bezelStyle = .rounded
            b.controlSize = .small
        }
        backButton.onAction { [weak self] _ in self?.onBack?() }
        nextButton.onAction { [weak self] _ in self?.onNext?() }
        nextButton.keyEquivalent = "\r"

        let view = NSView()
        for v in [titleLabel, closeButton, textLabel, progress, backButton, nextButton] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: width + 32),
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -8),
            closeButton.centerYAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor, constant: -4),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            textLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            textLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            textLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            nextButton.topAnchor.constraint(equalTo: textLabel.bottomAnchor, constant: 14),
            nextButton.trailingAnchor.constraint(equalTo: textLabel.trailingAnchor),
            nextButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            backButton.centerYAnchor.constraint(equalTo: nextButton.centerYAnchor),
            backButton.trailingAnchor.constraint(equalTo: nextButton.leadingAnchor, constant: -8),
            progress.centerYAnchor.constraint(equalTo: nextButton.centerYAnchor),
            progress.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            progress.trailingAnchor.constraint(lessThanOrEqualTo: backButton.leadingAnchor, constant: -8),
        ])
        self.view = view
    }

    func show(_ step: TutorialStep, number: Int, of count: Int) {
        _ = view
        titleLabel.stringValue = step.title
        textLabel.stringValue = step.text
        progress.stringValue = LF("%d of %d", number, count)
        backButton.isEnabled = number > 1
        nextButton.title = number == count ? L("Done") : L("Next")
        view.layoutSubtreeIfNeeded()
    }
}

/// A ring around the part a tutorial step explains, above every window, softly pulsing; clicks go through it.
private final class TutorialRing: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = true
        isReleasedWhenClosed = false
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        collectionBehavior = [.fullScreenAuxiliary, .transient]
        let ringView = RingView()
        ringView.wantsLayer = true
        contentView = ringView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(around rect: NSRect) {
        setFrame(rect.insetBy(dx: -6, dy: -6), display: true)
        orderFront(nil)
        // Animations stop while the window is off screen.
        guard let layer = contentView?.layer, layer.animation(forKey: "pulse") == nil else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1
        pulse.toValue = 0.45
        pulse.duration = 0.9
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        layer.add(pulse, forKey: "pulse")
    }
}

private final class RingView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 7, yRadius: 7)
        NSColor.controlAccentColor.withAlphaComponent(0.1).setFill()
        path.fill()
        path.lineWidth = 3
        NSColor.controlAccentColor.setStroke()
        path.stroke()
    }
}
