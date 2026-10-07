import Foundation

/// Localized UI string. Keys are the English text; translations live in `<lang>.lproj/Localizable.strings`.
@inline(__always) func L(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: key, table: nil)
}

/// Localized format string.
func LF(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), arguments: args)
}

/// Runs a block on the main thread in all run-loop modes, including while a modal dialog is open
/// (`DispatchQueue.main` is not serviced inside `NSApp.runModal`).
func performOnMain(_ block: @escaping () -> Void) {
    RunLoop.main.perform(inModes: [.common, .modalPanel, .eventTracking], block: block)
    CFRunLoopWakeUp(CFRunLoopGetMain())
}

/// Delayed variant of `performOnMain`.
func performOnMain(after seconds: TimeInterval, _ block: @escaping () -> Void) {
    let timer = Timer(timeInterval: seconds, repeats: false) { _ in block() }
    RunLoop.main.add(timer, forMode: .common)
    RunLoop.main.add(timer, forMode: .modalPanel)
}
