import AppKit

// `Brushwood --render-icon <dir.iconset>` writes the app icon PNGs (used by scripts/build-app.sh).
let arguments = CommandLine.arguments
if arguments.count >= 3, arguments[1] == "--render-icon" {
    do {
        try AppIcon.writeIconset(to: URL(fileURLWithPath: arguments[2]))
        exit(0)
    } catch {
        FileHandle.standardError.write("Icon export failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

// Tooltips (tool names and shortcuts, tool bar buttons) appear after 0.5 s instead of macOS's default of about 1 s.
UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 500])

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
