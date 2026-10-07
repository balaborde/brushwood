import AppKit
import BrushwoodCore

/// Small floating utility window that stays with the main window (Paint.NET's Tools/History/Layers/Colors windows).
class FloatingPanel: NSPanel {
    weak var host: MainWindowController?

    init(title: String, size: NSSize, resizable: Bool) {
        var style: NSWindow.StyleMask = [.titled, .closable, .utilityWindow]
        if resizable { style.insert(.resizable) }
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
        self.title = title
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = true
        isReleasedWhenClosed = false
        worksWhenModal = false
        titlebarAppearsTransparent = false
        isMovableByWindowBackground = false
        collectionBehavior = [.fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }

    /// Keyboard shortcuts typed while a panel is key go to the canvas (tool letters etc.).
    override func keyDown(with event: NSEvent) {
        if let canvas = host?.canvas {
            canvas.keyDown(with: event)
        } else {
            super.keyDown(with: event)
        }
    }
}
