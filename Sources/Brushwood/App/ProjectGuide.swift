import AppKit
import BrushwoodCore

/// Runs a guided project: makes its image, shows the current step in a floating panel, rings the part of the window it
/// is about, and checks the image (on every change, and twice a second) until the step is done. Next goes on once it
/// is; Skip goes on anyway. A step that is done stays done, even if it is undone later.
final class ProjectGuide {
    static let shared = ProjectGuide()

    private(set) var steps: [ProjectStep] = []
    private(set) var index = 0
    /// Whether the current step is done (or was skipped).
    private(set) var isDone = false
    private var completed: Set<Int> = []
    private weak var host: MainWindowController?
    private(set) weak var workspace: DocumentWorkspace?
    private var tour: TutorialScenario?
    /// Called after the last step (not when the project is ended early).
    var onFinish: (() -> Void)?

    // What the steps' checks compare with, noted when the step began.
    private(set) var baselineLayers: Set<ObjectIdentifier> = []
    private(set) var baselineHistoryItem: HistoryItem?
    private(set) var baselineSnapshots = 0
    /// Each layer's name when it first appeared, to tell when it is renamed.
    private(set) var firstNames: [ObjectIdentifier: String] = [:]
    // What steps remember for later ones.
    var roles: [String: WeakLayer] = [:]
    var areas: [String: IntRect] = [:]
    var numbers: [String: Int] = [:]

    private lazy var panel = ProjectPanel(guide: self)
    private let ring = TutorialRing()
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    var isRunning: Bool { workspace != nil && !steps.isEmpty }
    var current: ProjectStep? { isRunning ? steps[index] : nil }

    private var context: ProjectContext? {
        guard let host, let workspace else { return nil }
        return ProjectContext(host: host, workspace: workspace, project: self)
    }

    /// Starts the project in a new white image of `size`.
    func start(_ tour: TutorialScenario, steps: [ProjectStep], size: IntSize, host: MainWindowController) {
        end()
        TutorialGuide.shared.end()
        host.newImage(width: size.width, height: size.height, background: .white, dpi: 96)
        guard let ws = host.active else { return }
        self.tour = tour
        self.host = host
        workspace = ws
        self.steps = steps.filter(\.isAvailable)
        index = 0
        completed = []
        firstNames = [:]
        roles = [:]
        areas = [:]
        numbers = [:]
        let nc = NotificationCenter.default
        for name in [Notification.Name.documentHistoryChanged, .documentLayersChanged, .documentSelectionChanged,
                     .documentActiveLayerChanged] {
            observers.append(nc.addObserver(forName: name, object: ws.document, queue: .main) { [weak self] _ in self?.evaluate() })
        }
        observers.append(nc.addObserver(forName: .colorsChanged, object: nil, queue: .main) { [weak self] _ in self?.evaluate() })
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] n in
                if (n.object as? NSWindow) !== self?.ring { self?.placeRing() }
            })
        }
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.evaluate() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        panel.place(over: host.window)
        begin()
    }

    private func begin() {
        guard let ctx = context else { return end() }
        let doc = ctx.doc
        baselineLayers = Set(doc.layers.map(ObjectIdentifier.init))
        baselineHistoryItem = doc.history.currentItem
        baselineSnapshots = doc.history.snapshots.count
        noteNames(doc)
        isDone = completed.contains(index)
        steps[index].onBegin?(ctx)
        panel.show(steps[index], number: index + 1, of: steps.count, done: isDone)
        evaluate()
        placeRing()
    }

    /// Checks the current step (and notes the names of new layers).
    func evaluate() {
        guard isRunning else { return }
        // The project's image was closed.
        guard let ctx = context, host?.workspaces.contains(where: { $0 === workspace }) == true else { return end() }
        noteNames(ctx.doc)
        guard !isDone, steps[index].check(ctx) else { return }
        isDone = true
        completed.insert(index)
        steps[index].onDone?(ctx)
        panel.setDone(true)
    }

    func next() {
        guard isRunning, isDone else { return }
        if index < steps.count - 1 {
            index += 1
            begin()
        } else {
            tour?.markCompleted()
            end()
            onFinish?()
        }
    }

    func skip() {
        guard isRunning else { return }
        if !isDone, let ctx = context {
            steps[index].onDone?(ctx)
            isDone = true
            completed.insert(index)
        }
        next()
    }

    func back() {
        guard isRunning, index > 0 else { return }
        index -= 1
        begin()
    }

    /// "Use These Colors".
    func useColors() {
        guard let colors = current?.colors else { return }
        AppEnvironment.shared.primaryColor = colors.primary
        AppEnvironment.shared.secondaryColor = colors.secondary
    }

    func end() {
        timer?.invalidate()
        timer = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        ring.orderOut(nil)
        panel.orderOut(nil)
        steps = []
        workspace = nil
        host = nil
        tour = nil
    }

    private func noteNames(_ doc: Document) {
        for layer in doc.layers where firstNames[ObjectIdentifier(layer)] == nil {
            firstNames[ObjectIdentifier(layer)] = layer.name
        }
    }

    private func placeRing() {
        guard isRunning, let host, let view = steps[index].target?(host), let window = view.window, window.isVisible else {
            ring.orderOut(nil)
            return
        }
        ring.show(around: window.convertToScreen(view.convert(view.bounds, to: nil)))
    }
}

/// The guided project's floating panel: the step, what to do, its colors, whether it is done, and Skip / Back / Next.
final class ProjectPanel: NSPanel, NSWindowDelegate {
    private unowned let guide: ProjectGuide
    private let progress = NSTextField(labelWithString: "")
    private let plusTag = TagPill("PLUS")
    private let titleLabel = NSTextField(wrappingLabelWithString: "")
    /// The finished picture, on the steps that show the goal.
    private let goalView = NSImageView()
    private let textLabel = NSTextField(wrappingLabelWithString: "")
    private let tipLabel = NSTextField(wrappingLabelWithString: "")
    private let tipRow = NSStackView()
    private let primarySwatch = ColorSwatch()
    private let secondarySwatch = ColorSwatch()
    private let colorsButton = NSButton(title: L("Use These Colors"), target: nil, action: nil)
    private let colorsRow = NSStackView()
    private let statusIcon = NSImageView()
    private var statusRow: NSView?
    private let statusLabel = NSTextField(labelWithString: "")
    private let skipButton = NSButton(title: L("Skip"), target: nil, action: nil)
    private let backButton = NSButton(title: L("Back"), target: nil, action: nil)
    private let nextButton = NSButton(title: L("Next"), target: nil, action: nil)
    private static let width: CGFloat = 380

    init(guide: ProjectGuide) {
        self.guide = guide
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 300),
                   styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        title = L("Evening Lake")
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = true
        isReleasedWhenClosed = false
        delegate = self
        let textWidth = Self.width - 32
        progress.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        progress.textColor = .tertiaryLabelColor
        titleLabel.font = .boldSystemFont(ofSize: 14)
        titleLabel.preferredMaxLayoutWidth = textWidth
        textLabel.preferredMaxLayoutWidth = textWidth
        tipLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        tipLabel.textColor = .secondaryLabelColor
        tipLabel.preferredMaxLayoutWidth = textWidth - 50
        tipRow.setViews([TagPill("PLUS"), tipLabel], in: .leading)
        tipRow.alignment = .top
        tipRow.spacing = 6
        colorsButton.bezelStyle = .rounded
        colorsButton.controlSize = .small
        colorsButton.onAction { [weak guide] _ in guide?.useColors() }
        colorsRow.setViews([primarySwatch, secondarySwatch, colorsButton], in: .leading)
        colorsRow.spacing = 6
        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        for b in [skipButton, backButton, nextButton] {
            b.bezelStyle = .rounded
            b.controlSize = .small
        }
        skipButton.onAction { [weak guide] _ in guide?.skip() }
        backButton.onAction { [weak guide] _ in guide?.back() }
        nextButton.onAction { [weak guide] _ in guide?.next() }
        nextButton.keyEquivalent = "\r"

        let header = NSStackView(views: [progress, plusTag])
        header.spacing = 6
        let status = NSStackView(views: [statusIcon, statusLabel])
        status.spacing = 5
        statusRow = status
        let buttons = NSStackView(views: [skipButton, NSView(), backButton, nextButton])
        buttons.spacing = 8
        buttons.distribution = .fill
        goalView.image = EveningLake.goalImage
        goalView.imageScaling = .scaleProportionallyUpOrDown
        goalView.wantsLayer = true
        goalView.layer?.cornerRadius = 6
        goalView.layer?.masksToBounds = true
        goalView.translatesAutoresizingMaskIntoConstraints = false
        goalView.widthAnchor.constraint(equalToConstant: textWidth).isActive = true
        goalView.heightAnchor.constraint(equalToConstant: textWidth * 2 / 3).isActive = true
        let stack = NSStackView(views: [header, titleLabel, goalView, textLabel, tipRow, colorsRow, status, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(4, after: header)
        stack.setCustomSpacing(12, after: status)
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 14, right: 16)
        buttons.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            content.widthAnchor.constraint(equalToConstant: Self.width),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            buttons.widthAnchor.constraint(equalToConstant: textWidth),
        ])
        contentView = content
    }

    /// At the bottom of the main window, centered.
    func place(over window: NSWindow?) {
        guard let f = window?.frame else { return center() }
        setFrameOrigin(NSPoint(x: f.midX - frame.width / 2, y: f.minY + 60))
    }

    func show(_ step: ProjectStep, number: Int, of count: Int, done: Bool) {
        progress.stringValue = LF("%d of %d", number, count)
        titleLabel.stringValue = step.title
        textLabel.stringValue = step.text
        goalView.isHidden = !step.showsGoal || goalView.image == nil
        // The first and last steps only present the project: nothing to check.
        statusRow?.isHidden = step.showsGoal
        let tip = step.activePlusTip
        tipLabel.stringValue = tip ?? ""
        tipRow.isHidden = tip == nil
        plusTag.isHidden = step.requires == nil
        colorsRow.isHidden = step.colors == nil
        if let colors = step.colors {
            primarySwatch.color = colors.primary
            secondarySwatch.color = colors.secondary
        }
        backButton.isEnabled = number > 1
        nextButton.title = number == count ? L("Done") : L("Next")
        setDone(done)
        contentView?.layoutSubtreeIfNeeded()
        let top = frame.maxY
        setContentSize(contentView?.fittingSize ?? frame.size)
        setFrameTopLeftPoint(NSPoint(x: frame.minX, y: top))
        orderFront(nil)
    }

    func setDone(_ done: Bool) {
        statusIcon.image = NSImage(systemSymbolName: done ? "checkmark.circle.fill" : "circle.dotted", accessibilityDescription: nil)
        statusIcon.contentTintColor = done ? .systemGreen : .tertiaryLabelColor
        statusLabel.stringValue = done ? L("Done!") : L("Not done yet")
        statusLabel.textColor = done ? .systemGreen : .secondaryLabelColor
        nextButton.isEnabled = done
        skipButton.isHidden = done
    }

    func windowWillClose(_ notification: Notification) {
        if guide.isRunning { guide.end() }
    }
}

/// A color square, for the colors a step suggests.
private final class ColorSwatch: NSView {
    var color: ColorBgra = .black { didSet { needsDisplay = true } }

    override var intrinsicContentSize: NSSize { NSSize(width: 18, height: 18) }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 1, dy: 1)
        NSColor(srgbRed: CGFloat(color.r) / 255, green: CGFloat(color.g) / 255, blue: CGFloat(color.b) / 255, alpha: 1).setFill()
        NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3).fill()
        NSColor.separatorColor.setStroke()
        NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3).stroke()
    }
}
