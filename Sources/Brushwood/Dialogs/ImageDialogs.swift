import AppKit
import BrushwoodCore
import UniformTypeIdentifiers

/// Width/height/resolution/print-size form with aspect-ratio lock, shared by New, Resize and Canvas Size.
final class SizeForm {
    let widthField = numberField(800, width: 80)
    let heightField = numberField(600, width: 80)
    let resolutionField = numberField(96, decimals: 2, width: 80)
    let printWidthField = numberField(0, decimals: 2, width: 80)
    let printHeightField = numberField(0, decimals: 2, width: 80)
    let aspectCheck = NSButton(checkboxWithTitle: L("Maintain aspect ratio"), target: nil, action: nil)
    let printUnit = NSPopUpButton(frame: .zero, pullsDown: false)
    private var aspect: Double
    private var updating = false
    var onChange: (() -> Void)?

    init(width: Int, height: Int, dpi: Double, aspectLocked: Bool = true) {
        aspect = Double(width) / Double(max(1, height))
        widthField.doubleValue = Double(width)
        heightField.doubleValue = Double(height)
        resolutionField.doubleValue = dpi
        aspectCheck.state = aspectLocked ? .on : .off
        printUnit.addItems(withTitles: [L("inches"), L("centimeters")])
        printUnit.selectItem(at: AppEnvironment.shared.units == .centimeters ? 1 : 0)
        printUnit.onAction { [weak self] _ in self?.syncPrint() }
        widthField.onLiveChange { [weak self] _ in self?.pixelsChanged(width: true) }
        heightField.onLiveChange { [weak self] _ in self?.pixelsChanged(width: false) }
        resolutionField.onLiveChange { [weak self] _ in self?.syncPrint() }
        printWidthField.onLiveChange { [weak self] _ in self?.printChanged(width: true) }
        printHeightField.onLiveChange { [weak self] _ in self?.printChanged(width: false) }
        syncPrint()
    }

    var pixelWidth: Int { max(1, min(65535, Int(widthField.doubleValue.rounded()))) }
    var pixelHeight: Int { max(1, min(65535, Int(heightField.doubleValue.rounded()))) }
    var dpi: Double { max(1, resolutionField.doubleValue) }
    private var unitFactor: Double { printUnit.indexOfSelectedItem == 1 ? 2.54 : 1 }

    func setPixels(width: Int, height: Int) {
        updating = true
        widthField.doubleValue = Double(width)
        heightField.doubleValue = Double(height)
        updating = false
        syncPrint()
    }

    private func pixelsChanged(width: Bool) {
        guard !updating else { return }
        updating = true
        if aspectCheck.state == .on {
            if width {
                heightField.doubleValue = max(1, (widthField.doubleValue / aspect).rounded())
            } else {
                widthField.doubleValue = max(1, (heightField.doubleValue * aspect).rounded())
            }
        }
        updating = false
        syncPrint()
    }

    private func printChanged(width: Bool) {
        guard !updating else { return }
        updating = true
        let d = dpi / unitFactor
        if width {
            widthField.doubleValue = max(1, (printWidthField.doubleValue * d).rounded())
            if aspectCheck.state == .on { heightField.doubleValue = max(1, (widthField.doubleValue / aspect).rounded()) }
        } else {
            heightField.doubleValue = max(1, (printHeightField.doubleValue * d).rounded())
            if aspectCheck.state == .on { widthField.doubleValue = max(1, (heightField.doubleValue * aspect).rounded()) }
        }
        let pw = printWidthField.currentEditor() != nil, ph = printHeightField.currentEditor() != nil
        if !pw { printWidthField.doubleValue = Double(pixelWidth) / d }
        if !ph { printHeightField.doubleValue = Double(pixelHeight) / d }
        updating = false
        onChange?()
    }

    private func syncPrint() {
        guard !updating else { return }
        updating = true
        let d = dpi / unitFactor
        printWidthField.doubleValue = (Double(pixelWidth) / d * 100).rounded() / 100
        printHeightField.doubleValue = (Double(pixelHeight) / d * 100).rounded() / 100
        updating = false
        onChange?()
    }

    func install(in dialog: ModalDialog) {
        dialog.addSection(L("Pixel size"))
        dialog.addRow([formLabel(L("Width:")), widthField, NSTextField(labelWithString: L("pixels"))])
        dialog.addRow([formLabel(L("Height:")), heightField, NSTextField(labelWithString: L("pixels"))])
        dialog.addRow([formLabel(""), aspectCheck])
        dialog.addSection(L("Print size"))
        dialog.addRow([formLabel(L("Resolution:")), resolutionField, NSTextField(labelWithString: L("pixels/inch"))])
        dialog.addRow([formLabel(L("Width:")), printWidthField, printUnit])
        dialog.addRow([formLabel(L("Height:")), printHeightField])
    }

    func setEnabled(_ on: Bool) {
        for c in [widthField, heightField, resolutionField, printWidthField, printHeightField] as [NSControl] { c.isEnabled = on }
        aspectCheck.isEnabled = on
        printUnit.isEnabled = on
    }
}

private func memoryString(_ w: Int, _ h: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(w) * Int64(h) * 4, countStyle: .memory)
}

enum NewImageDialog {
    static func run(parent: NSWindow?, completion: (Int, Int, ColorBgra, Double) -> Void) {
        let d = UserDefaults.standard
        var w = d.integer(forKey: "newImageWidth"), h = d.integer(forKey: "newImageHeight")
        if w <= 0 || h <= 0 { w = 800; h = 600 }
        if let clip = Clipboard.imageSize { (w, h) = (clip.width, clip.height) }
        let dlg = ModalDialog(title: L("New Image"))
        let form = SizeForm(width: w, height: h, dpi: d.double(forKey: "newImageDPI") > 0 ? d.double(forKey: "newImageDPI") : 96)
        let estimate = NSTextField(labelWithString: "")
        estimate.textColor = .secondaryLabelColor
        form.onChange = { estimate.stringValue = LF("New size: %@", memoryString(form.pixelWidth, form.pixelHeight)) }
        dlg.body.addArrangedSubview(estimate)
        form.install(in: dlg)
        dlg.addSection(L("Background"))
        let bg = NSPopUpButton(frame: .zero, pullsDown: false)
        bg.addItems(withTitles: [L("White"), L("Secondary color"), L("Transparent")])
        bg.selectItem(at: d.integer(forKey: "newImageBackground"))
        dlg.addRow([formLabel(""), bg])
        form.onChange?()
        guard dlg.runModal(parent: parent) else { return }
        d.set(form.pixelWidth, forKey: "newImageWidth")
        d.set(form.pixelHeight, forKey: "newImageHeight")
        d.set(form.dpi, forKey: "newImageDPI")
        d.set(bg.indexOfSelectedItem, forKey: "newImageBackground")
        let color: ColorBgra
        switch bg.indexOfSelectedItem {
        case 1: color = AppEnvironment.shared.secondaryColor
        case 2: color = .transparent
        default: color = .white
        }
        completion(form.pixelWidth, form.pixelHeight, color, form.dpi)
    }
}

enum ResizeDialog {
    static func run(ws: DocumentWorkspace, parent: NSWindow?, completion: (IntSize, ResamplingMode, Double) -> Void) {
        let doc = ws.document
        let dlg = ModalDialog(title: L("Resize Image"))
        let estimate = NSTextField(labelWithString: "")
        estimate.textColor = .secondaryLabelColor
        dlg.body.addArrangedSubview(estimate)
        let mode = NSPopUpButton(frame: .zero, pullsDown: false)
        mode.addItems(withTitles: ResamplingMode.allCases.map { L($0.displayName) })
        mode.selectItem(at: UserDefaults.standard.integer(forKey: "resizeMode"))
        dlg.addRow([formLabel(L("Resampling:")), mode])
        dlg.addSeparator()
        let byPercent = NSButton(radioButtonWithTitle: L("By percentage:"), target: nil, action: nil)
        let byAbsolute = NSButton(radioButtonWithTitle: L("By absolute size"), target: nil, action: nil)
        let percent = numberField(100, width: 70)
        let form = SizeForm(width: doc.width, height: doc.height, dpi: doc.dpi)
        byPercent.state = .on
        dlg.addRow([byPercent, percent, NSTextField(labelWithString: "%")])
        dlg.addRow([byAbsolute])
        form.install(in: dlg)
        let update = {
            form.setEnabled(byAbsolute.state == .on)
            percent.isEnabled = byPercent.state == .on
            estimate.stringValue = LF("New size: %d × %d (%@)", form.pixelWidth, form.pixelHeight,
                                      memoryString(form.pixelWidth, form.pixelHeight))
        }
        form.onChange = update
        percent.onLiveChange { _ in
            let p = max(1, percent.doubleValue) / 100
            form.setPixels(width: max(1, Int((Double(doc.width) * p).rounded())), height: max(1, Int((Double(doc.height) * p).rounded())))
        }
        byPercent.onAction { _ in byAbsolute.state = .off; update() }
        byAbsolute.onAction { _ in byPercent.state = .off; update() }
        update()
        guard dlg.runModal(parent: parent) else { return }
        UserDefaults.standard.set(mode.indexOfSelectedItem, forKey: "resizeMode")
        let size = IntSize(width: form.pixelWidth, height: form.pixelHeight)
        guard size != doc.size || form.dpi != doc.dpi else { return }
        completion(size, ResamplingMode(rawValue: mode.indexOfSelectedItem) ?? .bestQuality, form.dpi)
    }
}

enum CanvasSizeDialog {
    static func run(ws: DocumentWorkspace, parent: NSWindow?, completion: (IntSize, (Int, Int), Double) -> Void) {
        let doc = ws.document
        let dlg = ModalDialog(title: L("Canvas Size"))
        let estimate = NSTextField(labelWithString: "")
        estimate.textColor = .secondaryLabelColor
        dlg.body.addArrangedSubview(estimate)
        let byPercent = NSButton(radioButtonWithTitle: L("By percentage:"), target: nil, action: nil)
        let byAbsolute = NSButton(radioButtonWithTitle: L("By absolute size"), target: nil, action: nil)
        let percent = numberField(100, width: 70)
        let form = SizeForm(width: doc.width, height: doc.height, dpi: doc.dpi, aspectLocked: false)
        byAbsolute.state = .on
        dlg.addRow([byPercent, percent, NSTextField(labelWithString: "%")])
        dlg.addRow([byAbsolute])
        form.install(in: dlg)
        dlg.addSection(L("Anchor"))
        let anchor = AnchorGridView()
        dlg.addRow([formLabel(""), anchor])
        let update = {
            form.setEnabled(byAbsolute.state == .on)
            percent.isEnabled = byPercent.state == .on
            estimate.stringValue = LF("New size: %d × %d (%@)", form.pixelWidth, form.pixelHeight,
                                      memoryString(form.pixelWidth, form.pixelHeight))
        }
        form.onChange = update
        percent.onLiveChange { _ in
            let p = max(1, percent.doubleValue) / 100
            form.setPixels(width: max(1, Int((Double(doc.width) * p).rounded())), height: max(1, Int((Double(doc.height) * p).rounded())))
        }
        byPercent.onAction { _ in byAbsolute.state = .off; update() }
        byAbsolute.onAction { _ in byPercent.state = .off; update() }
        update()
        guard dlg.runModal(parent: parent) else { return }
        let size = IntSize(width: form.pixelWidth, height: form.pixelHeight)
        guard size != doc.size || form.dpi != doc.dpi else { return }
        completion(size, anchor.anchor, form.dpi)
    }
}

/// 3×3 anchor selector with arrows pointing away from the anchor.
final class AnchorGridView: NSView {
    var anchor = (1, 1) { didSet { needsDisplay = true } }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 96, height: 96))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 96).isActive = true
        heightAnchor.constraint(equalToConstant: 96).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let s = bounds.width / 3
        for row in 0..<3 {
            for col in 0..<3 {
                let r = NSRect(x: CGFloat(col) * s, y: CGFloat(row) * s, width: s, height: s).insetBy(dx: 2, dy: 2)
                let selected = anchor == (col, row)
                (selected ? NSColor.controlAccentColor : NSColor.controlBackgroundColor).setFill()
                NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3).fill()
                NSColor.separatorColor.setStroke()
                NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3).stroke()
                let dx = col - anchor.0, dy = row - anchor.1
                if !selected && abs(dx) <= 1 && abs(dy) <= 1 {
                    let c = NSPoint(x: r.midX, y: r.midY)
                    let len = r.width * 0.3
                    let n = hypot(Double(dx), Double(dy))
                    let ux = CGFloat(Double(dx) / n), uy = CGFloat(Double(dy) / n)
                    let p = NSBezierPath()
                    p.move(to: NSPoint(x: c.x - ux * len, y: c.y - uy * len))
                    p.line(to: NSPoint(x: c.x + ux * len, y: c.y + uy * len))
                    p.lineWidth = 1.5
                    NSColor.secondaryLabelColor.setStroke()
                    p.stroke()
                }
            }
        }
    }

    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        let s = bounds.width / 3
        anchor = (clampInt(Int(p.x / s), 0, 2), clampInt(Int(p.y / s), 0, 2))
    }
}

enum LayerPropertiesDialog {
    static func run(ws: DocumentWorkspace, parent: NSWindow?) {
        let doc = ws.document
        let index = doc.activeLayerIndex
        let layer = doc.layers[index]
        let original = layer.properties
        let dlg = ModalDialog(title: L("Layer Properties"))
        dlg.addSection(L("General"))
        let name = NSTextField(string: original.name)
        name.translatesAutoresizingMaskIntoConstraints = false
        name.widthAnchor.constraint(equalToConstant: 220).isActive = true
        dlg.addRow([formLabel(L("Name:"), width: 80), name])
        let visible = NSButton(checkboxWithTitle: L("Visible"), target: nil, action: nil)
        visible.state = original.isVisible ? .on : .off
        dlg.addRow([formLabel("", width: 80), visible])
        dlg.addSection(L("Blending"))
        let mode = NSPopUpButton(frame: .zero, pullsDown: false)
        mode.addItems(withTitles: BlendMode.allCases.map { L($0.displayName) })
        mode.selectItem(at: original.blendMode.rawValue)
        dlg.addRow([formLabel(L("Mode:"), width: 80), mode])
        let opacity = NumericSliderControl(range: 0...255, value: Double(original.opacity), defaultValue: 255, sliderWidth: 160)
        dlg.addRow([formLabel(L("Opacity:"), width: 80), opacity])
        // Live preview of property changes.
        let preview = {
            layer.properties = LayerProperties(name: name.stringValue, isVisible: visible.state == .on,
                                               opacity: UInt8(opacity.value), blendMode: BlendMode(rawValue: mode.indexOfSelectedItem) ?? .normal)
            doc.invalidate()
            doc.post(.documentLayersChanged)
        }
        visible.onAction { _ in preview() }
        mode.onAction { _ in preview() }
        opacity.onChange = { _ in preview() }
        dlg.initialFirstResponder = name
        let ok = dlg.runModal(parent: parent)
        let final = LayerProperties(name: name.stringValue.isEmpty ? original.name : name.stringValue,
                                    isVisible: visible.state == .on, opacity: UInt8(opacity.value),
                                    blendMode: BlendMode(rawValue: mode.indexOfSelectedItem) ?? .normal)
        layer.properties = original
        if ok { ws.setLayerProperties(index, final) } else {
            doc.invalidate()
            doc.post(.documentLayersChanged)
        }
    }
}

/// Format-specific save options (JPEG/HEIC/AVIF quality, bit depth, TGA compression) with a size estimate.
enum SaveOptionsDialog {
    static func run(for ws: DocumentWorkspace, type: FileType, parent: NSWindow?, completion: (SaveOptions?) -> Void) {
        var options = ws.saveOptions
        let dlg = ModalDialog(title: LF("Save Configuration — %@", type.name))
        let flat = ws.document.flattened()
        let sizeLabel = NSTextField(labelWithString: "")
        sizeLabel.textColor = .secondaryLabelColor
        var timer: Timer?
        let estimate = {
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { _ in
                if let ut = type.utType, let data = try? ImageCodec.encode(flat, type: ut, options: options,
                                                                           supportsAlpha: type.supportsAlpha) {
                    sizeLabel.stringValue = LF("File size: %@", ByteCountFormatter.string(fromByteCount: Int64(data.count),
                                                                                           countStyle: .file))
                }
            }
            RunLoop.main.add(timer!, forMode: .modalPanel)
        }
        if type.hasQuality {
            dlg.addSection(L("Quality"))
            let q = NumericSliderControl(range: 1...100, value: Double(options.quality), defaultValue: 95, sliderWidth: 200)
            q.onChange = { v in
                options.quality = Int(v)
                estimate()
            }
            dlg.body.addArrangedSubview(q)
        }
        if type.hasBitDepth {
            dlg.addSection(L("Bit Depth"))
            let p = NSPopUpButton(frame: .zero, pullsDown: false)
            p.addItems(withTitles: [L("Auto-detect"), L("32-bit"), L("24-bit")])
            p.selectItem(at: options.bitDepth == 32 ? 1 : (options.bitDepth == 24 ? 2 : 0))
            p.onAction { _ in
                options.bitDepth = [0, 32, 24][p.indexOfSelectedItem]
                estimate()
            }
            dlg.body.addArrangedSubview(p)
            if type == .tga {
                let rle = NSButton(checkboxWithTitle: L("RLE compression"), target: nil, action: nil)
                rle.state = options.rleCompress ? .on : .off
                rle.onAction { _ in options.rleCompress = rle.state == .on }
                dlg.body.addArrangedSubview(rle)
            }
        }
        dlg.addSeparator()
        dlg.body.addArrangedSubview(sizeLabel)
        estimate()
        let ok = dlg.runModal(parent: parent)
        timer?.invalidate()
        completion(ok ? options : nil)
    }
}

/// Format popup in the Save panel.
final class SaveFormatAccessory {
    let view: NSView
    private let popup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let types = FileType.writable
    private weak var panel: NSSavePanel?

    var selected: FileType { types[max(0, popup.indexOfSelectedItem)] }

    init(current: FileType, panel: NSSavePanel) {
        self.panel = panel
        let label = NSTextField(labelWithString: L("Format:"))
        for t in types { popup.addItem(withTitle: "\(t.name) (*.\(t.extensions.joined(separator: ", *.")))") }
        popup.selectItem(at: types.firstIndex(of: current) ?? 0)
        let stack = NSStackView(views: [label, popup])
        stack.orientation = .horizontal
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        stack.frame = NSRect(x: 0, y: 0, width: 420, height: 44)
        view = stack
        popup.onAction { [weak self] _ in self?.apply() }
        apply()
    }

    private func apply() {
        guard let panel else { return }
        let t = selected
        panel.allowedContentTypes = t.extensions.compactMap { UTType(filenameExtension: $0) }
        let base = (panel.nameFieldStringValue as NSString).deletingPathExtension
        panel.nameFieldStringValue = base + "." + t.primaryExtension
    }
}

// MARK: - Clipboard & recent files

enum Clipboard {
    /// Tests use a private pasteboard so they never touch the user's clipboard.
    static var pasteboard: NSPasteboard {
        if let name = ProcessInfo.processInfo.environment["BRUSHWOOD_PASTEBOARD"] {
            return NSPasteboard(name: NSPasteboard.Name(name))
        }
        return .general
    }

    static func write(_ s: Surface) {
        let pb = pasteboard
        pb.clearContents()
        if let png = ImageCodec.pngData(s) { pb.setData(png, forType: .png) }
        if let cg = s.makeCGImage() {
            let rep = NSBitmapImageRep(cgImage: cg)
            if let tiff = rep.tiffRepresentation { pb.setData(tiff, forType: .tiff) }
        }
    }

    static var hasImage: Bool {
        pasteboard.canReadItem(withDataConformingToTypes: [NSPasteboard.PasteboardType.png.rawValue,
                                                                     NSPasteboard.PasteboardType.tiff.rawValue,
                                                                     "public.jpeg", "public.image"])
    }

    static func read() -> Surface? {
        let pb = pasteboard
        for t in [NSPasteboard.PasteboardType.png, .tiff, NSPasteboard.PasteboardType("public.jpeg")] {
            if let data = pb.data(forType: t), let s = ImageCodec.surface(fromImageData: data) { return s }
        }
        if let img = NSImage(pasteboard: pb), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return Surface(cgImage: cg)
        }
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let url = urls.first, let doc = try? ImageCodec.load(url: url) {
            return doc.flattened()
        }
        return nil
    }

    static var imageSize: IntSize? {
        guard hasImage, let s = read() else { return nil }
        return s.size
    }
}

enum RecentFiles {
    static let key = "recentFiles"

    static var urls: [URL] {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).compactMap { URL(string: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func add(_ url: URL) {
        var list = urls.filter { $0 != url }
        list.insert(url, at: 0)
        UserDefaults.standard.set(Array(list.prefix(10)).map(\.absoluteString), forKey: key)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
