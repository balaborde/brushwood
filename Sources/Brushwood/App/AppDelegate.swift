import AppKit
import BrushwoodCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private(set) var main: MainWindowController!
    private var pendingURLs: [URL] = []
    private var settingsWindow: SettingsWindow?
    private var launched = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build(delegate: self)
        UserDefaults.standard.register(defaults: ["NSApplicationCrashOnExceptions": true])
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Bundle.main.bundleURL.pathExtension != "app" { NSApp.applicationIconImage = AppIcon.image }
        AppearanceSetting.apply()
        if let a = ProcessInfo.processInfo.environment["BRUSHWOOD_APPEARANCE"] {
            NSApp.appearance = NSAppearance(named: a == "dark" ? .darkAqua : .aqua)
        }
        main = MainWindowController()
        main.window?.center()
        main.showWindow(nil)
        main.placePanels()
        launched = true
        let args = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
        let urls = pendingURLs + args.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        pendingURLs = []
        if urls.isEmpty {
            // Paint.NET starts with a new blank image.
            let d = UserDefaults.standard
            let w = d.integer(forKey: "newImageWidth") > 0 ? d.integer(forKey: "newImageWidth") : 800
            let h = d.integer(forKey: "newImageHeight") > 0 ? d.integer(forKey: "newImageHeight") : 600
            main.newImage(width: w, height: h, background: .white, dpi: 96)
        } else {
            main.open(urls: urls)
        }
        NSApp.activate(ignoringOtherApps: true)
        if let snapshot = ProcessInfo.processInfo.environment["BRUSHWOOD_SNAPSHOT"] {
            DebugSnapshot.schedule(path: snapshot, controller: main)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if launched { main.open(urls: urls) } else { pendingURLs += urls }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let main, main.hasDirtyDocuments else { return .terminateNow }
        main.closeAll { ok in NSApp.reply(toApplicationShouldTerminate: ok) }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppEnvironment.shared.save()
        main?.savePanelVisibility()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: - Menus needing live content

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu.title == L("Open Recent") {
            menu.removeAllItems()
            let urls = RecentFiles.urls
            for url in urls {
                let item = NSMenuItem(title: url.lastPathComponent, action: #selector(MainWindowController.openRecent(_:)), keyEquivalent: "")
                item.representedObject = url
                item.image = NSWorkspace.shared.icon(forFile: url.path)
                item.image?.size = NSSize(width: 16, height: 16)
                item.toolTip = url.path
                menu.addItem(item)
            }
            if !urls.isEmpty { menu.addItem(.separator()) }
            let clear = NSMenuItem(title: L("Clear Menu"), action: #selector(clearRecent(_:)), keyEquivalent: "")
            clear.target = self
            menu.addItem(clear)
        } else if menu.title == L("Window") {
            while let last = menu.items.last, last.representedObject is DocumentWorkspace { menu.removeItem(last) }
            for ws in main?.workspaces ?? [] {
                let item = NSMenuItem(title: ws.displayName, action: #selector(MainWindowController.selectImageTab(_:)), keyEquivalent: "")
                item.representedObject = ws
                menu.addItem(item)
            }
        }
    }

    @objc func clearRecent(_ sender: Any?) {
        RecentFiles.clear()
        NSDocumentController.shared.clearRecentDocuments(nil)
    }

    // MARK: - App-level windows

    @objc func showSettings(_ sender: Any?) {
        if settingsWindow == nil { settingsWindow = SettingsWindow() }
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func showAbout(_ sender: Any?) {
        let credits = NSAttributedString(string: L("A free, open-source image editor for macOS, modeled on the workflow of Paint.NET.\n\nLicensed under the MIT License.\nNot affiliated with or endorsed by dotPDN LLC. Paint.NET is a trademark of its respective owner."),
                                         attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor])
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Brushwood",
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
            .credits: credits,
            .applicationIcon: AppIcon.image,
        ])
    }

    @objc func showHelp(_ sender: Any?) {
        HelpWindow.shared.show(section: .guide)
    }

    @objc func showShortcuts(_ sender: Any?) {
        HelpWindow.shared.show(section: .shortcuts)
    }
}
