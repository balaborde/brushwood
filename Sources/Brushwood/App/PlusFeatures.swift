import AppKit
import BrushwoodCore

extension Notification.Name {
    /// A Brushwood Plus feature was turned on or off.
    static let plusFeaturesChanged = Notification.Name("BrushwoodPlusFeaturesChanged")
}

/// Brushwood Plus's features, each of which can be turned off in the Plus Features window. A feature that is off
/// leaves the app as Brushwood is without it: its buttons, menu items and options are gone and it has no effect.
/// Add new features here, with the version that brings them, and check `isEnabled` wherever they show.
enum PlusFeature: String, CaseIterable {
    case historyTimes, snapshots, smoothing, magneticClosing

    var category: PlusCategory {
        switch self {
        case .historyTimes, .snapshots: return .history
        case .smoothing, .magneticClosing: return .painting
        }
    }

    var name: String {
        switch self {
        case .historyTimes: return L("Times in the History window")
        case .snapshots: return L("Snapshots")
        case .smoothing: return L("Brush smoothing")
        case .magneticClosing: return L("Magnetic closing")
        }
    }

    var details: String {
        switch self {
        case .historyTimes: return L("Shows when each step was made, or how long ago.")
        case .snapshots: return L("Keeps copies of the image that you can always go back to, from the History window.")
        case .smoothing:
            return L("Steadies strokes: the brush follows the pointer on a string. For the Paintbrush, Eraser, Clone Stamp and Recolor tools.")
        case .magneticClosing:
            return L("Joins a stroke released near its start to it, so circles and outlines close cleanly. For the same tools.")
        }
    }

    /// The Plus version that brought the feature: it is marked New after an update from an older version.
    var since: AppVersion {
        switch self {
        case .historyTimes, .snapshots, .smoothing, .magneticClosing: return AppVersion("1.0.3-plus.1")!
        }
    }

    private var key: String { "plusFeature.\(rawValue)" }

    /// On unless turned off.
    var isEnabled: Bool {
        let d = UserDefaults.standard
        return d.object(forKey: key) == nil || d.bool(forKey: key)
    }

    /// Turns features on or off, then tells the interface once.
    static func set(_ features: [PlusFeature], enabled: Bool) {
        for f in features { UserDefaults.standard.set(enabled, forKey: f.key) }
        NotificationCenter.default.post(name: .plusFeaturesChanged, object: nil)
    }

    /// Brought by the last update.
    var isNew: Bool { PlusFeaturesPrompt.previousVersion.map { $0 < since } ?? false }
}

/// Groups of features in the Plus Features window.
enum PlusCategory: CaseIterable {
    case history, painting

    var title: String {
        switch self {
        case .history: return L("History")
        case .painting: return L("Painting")
        }
    }

    var features: [PlusFeature] { PlusFeature.allCases.filter { $0.category == self } }
}

/// Shows the Plus Features window at the first launch and after each update.
enum PlusFeaturesPrompt {
    enum Occasion {
        case firstLaunch, update, menu
    }

    private static let seenKey = "plusFeaturesSeenVersion"
    private static let previousKey = "plusFeaturesPreviousVersion"
    /// Set at launch when the window is due.
    private(set) static var due: Occasion?

    /// The version used before the last update (nil before any update): features newer than it are marked New.
    static var previousVersion: AppVersion? { UserDefaults.standard.string(forKey: previousKey).flatMap(AppVersion.init) }

    static func noteLaunch() {
        guard let current = AppVersion.current, ProcessInfo.processInfo.environment["BRUSHWOOD_SNAPSHOT"] == nil else { return }
        let d = UserDefaults.standard
        let seen = d.string(forKey: seenKey).flatMap(AppVersion.init)
        if let seen, !(seen < current) { return }
        due = seen == nil ? .firstLaunch : .update
        if let seen { d.set(seen.description, forKey: previousKey) }
        d.set(current.description, forKey: seenKey)
    }
}
