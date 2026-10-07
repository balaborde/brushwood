import AppKit
import BrushwoodCore
import CoreText

/// Text tool: click to place a caret and type. The text stays editable (font, size, style, alignment, color)
/// until it is committed, like Paint.NET.
final class TextTool: Tool {
    private var session: PixelEditSession?
    private var mask: MaskSurface?
    private var clip: MaskSurface?
    private var origin = CGPoint.zero
    private var lines: [String] = [""]
    private var caretLine = 0
    private var caretCol = 0
    private var marked = ""
    private var lastDirty = IntRect.zero
    private var textBounds = CGRect.zero
    private var caretRect = CGRect.zero
    private var caretVisible = true
    private var blinkTimer: Timer?
    private var moveStart: (mouse: CGPoint, origin: CGPoint)?

    override var hasPendingEdits: Bool { session != nil }

    deinit { blinkTimer?.invalidate() }

    private var font: NSFont {
        let px = settings.fontSize * 96 / 72
        var f = NSFont(name: settings.fontName, size: px) ?? NSFont.systemFont(ofSize: px)
        let fm = NSFontManager.shared
        if settings.bold { f = fm.convert(f, toHaveTrait: .boldFontMask) }
        if settings.italic { f = fm.convert(f, toHaveTrait: .italicFontMask) }
        return f
    }

    private func attributed(_ s: String) -> NSAttributedString {
        // CoreText draws with the context's fill color (white into the coverage mask).
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        if settings.underline { attrs[NSAttributedString.Key(kCTUnderlineStyleAttributeName as String)] = CTUnderlineStyle.single.rawValue }
        return NSAttributedString(string: s, attributes: attrs)
    }

    private func begin(at p: CGPoint) {
        session = PixelEditSession(layer: doc.activeLayer)
        mask = MaskSurface(width: doc.width, height: doc.height)
        clip = selectionClip
        origin = p
        lines = [""]
        caretLine = 0
        caretCol = 0
        marked = ""
        lastDirty = .zero
        startBlink()
        render()
    }

    private func startBlink() {
        blinkTimer?.invalidate()
        caretVisible = true
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.53, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.caretVisible.toggle()
            self.canvas.overlayChanged(self.caretRect)
        }
    }

    // MARK: Layout & rendering

    private struct LineLayout {
        let line: CTLine
        let x: CGFloat
        let baseline: CGFloat
        let width: CGFloat
    }

    private func layout() -> [LineLayout] {
        let f = font
        let lineHeight = ceil(f.ascender - f.descender + f.leading)
        var result: [LineLayout] = []
        for (i, text) in lines.enumerated() {
            var s = text
            if i == caretLine && !marked.isEmpty {
                let idx = s.index(s.startIndex, offsetBy: min(caretCol, s.count))
                s.insert(contentsOf: marked, at: idx)
            }
            let line = CTLineCreateWithAttributedString(attributed(s))
            let w = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            let x: CGFloat
            switch settings.textAlignment {
            case .left: x = origin.x
            case .center: x = origin.x - w / 2
            case .right: x = origin.x - w
            }
            result.append(LineLayout(line: line, x: x, baseline: origin.y + f.ascender + CGFloat(i) * lineHeight, width: w))
        }
        return result
    }

    private func render() {
        guard let session, let mask else { return }
        let f = font
        let lineHeight = ceil(f.ascender - f.descender + f.leading)
        let layouts = layout()
        var bounds = CGRect.null
        for l in layouts {
            bounds = bounds.union(CGRect(x: l.x, y: l.baseline - f.ascender, width: max(1, l.width), height: lineHeight))
        }
        textBounds = bounds
        let newDirty = IntRect(enclosing: bounds.insetBy(dx: -lineHeight, dy: -4)).intersection(doc.bounds)
        let dirty = lastDirty.union(newDirty)
        session.restore(dirty)
        PathRasterizer.clear(mask, rect: dirty)
        let aa = settings.antialiasing
        mask.draw(antialias: aa) { ctx in
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.setShouldSmoothFonts(false)
            for l in layouts {
                ctx.saveGState()
                ctx.translateBy(x: l.x, y: l.baseline)
                ctx.scaleBy(x: 1, y: -1)
                ctx.textPosition = .zero
                CTLineDraw(l.line, ctx)
                if self.settings.strikethrough {
                    // CoreText has no strikethrough; draw it like the underline, at half the x-height.
                    let y = f.xHeight / 2
                    let t = max(1, f.underlineThickness)
                    ctx.fill(CGRect(x: 0, y: y - t / 2, width: l.width, height: t))
                }
                ctx.restoreGState()
            }
        }
        Compositor.apply(color: env.primaryColor, mask: mask, rect: newDirty, src: session.original, dst: session.layer.surface,
                         mode: settings.blendMode, clip: clip)
        session.touch(dirty)
        lastDirty = newDirty
        doc.invalidate(dirty)
        // Caret.
        if caretLine < layouts.count {
            let l = layouts[caretLine]
            let text = lines[caretLine]
            let idx = text.index(text.startIndex, offsetBy: min(caretCol, text.count))
            let utf16Offset = text[..<idx].utf16.count + marked.utf16.count
            let cx = l.x + CTLineGetOffsetForStringIndex(l.line, utf16Offset, nil)
            caretRect = CGRect(x: cx, y: l.baseline - f.ascender, width: 1, height: lineHeight)
        }
        canvas.needsDisplay = true
    }

    // MARK: Input

    override func mouseDown(_ e: ToolEvent) {
        if session != nil {
            let handle = CGPoint(x: textBounds.maxX + 6 / canvas.zoom, y: textBounds.maxY + 6 / canvas.zoom)
            if canvas.hitHandle(e.viewPoint, handle) {
                moveStart = (e.point, origin)
                return
            }
            if textBounds.insetBy(dx: -4, dy: -4).contains(e.point) {
                placeCaret(at: e.point)
                return
            }
            commit()
        }
        begin(at: e.point)
    }

    override func mouseDragged(_ e: ToolEvent) {
        guard let m = moveStart else { return }
        origin = CGPoint(x: m.origin.x + e.point.x - m.mouse.x, y: m.origin.y + e.point.y - m.mouse.y)
        render()
    }

    override func mouseUp(_ e: ToolEvent) {
        moveStart = nil
    }

    private func placeCaret(at p: CGPoint) {
        let layouts = layout()
        let f = font
        let lineHeight = ceil(f.ascender - f.descender + f.leading)
        let li = clampInt(Int((p.y - origin.y) / lineHeight), 0, lines.count - 1)
        let l = layouts[li]
        let utf16 = CTLineGetStringIndexForPosition(l.line, CGPoint(x: p.x - l.x, y: 0))
        let text = lines[li]
        var count = 0, col = 0
        for ch in text {
            if count >= utf16 { break }
            count += String(ch).utf16.count
            col += 1
        }
        caretLine = li
        caretCol = col
        startBlink()
        render()
    }

    override func keyDown(_ e: NSEvent) -> Bool {
        guard session != nil else { return false }
        if e.modifierFlags.contains(.command) { return false }
        if e.keyCode == 53 {
            // Escape finishes the text.
            commit()
            return true
        }
        canvas.interpretKeyEvents([e])
        return true
    }

    func insert(_ text: String) {
        guard session != nil else { return }
        marked = ""
        let parts = text.replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        for (i, part) in parts.enumerated() {
            if i > 0 { newline() }
            var line = lines[caretLine]
            let idx = line.index(line.startIndex, offsetBy: min(caretCol, line.count))
            line.insert(contentsOf: part, at: idx)
            lines[caretLine] = line
            caretCol += part.count
        }
        startBlink()
        render()
    }

    func setMarked(_ text: String) {
        marked = text
        render()
    }

    private func newline() {
        let line = lines[caretLine]
        let idx = line.index(line.startIndex, offsetBy: min(caretCol, line.count))
        lines[caretLine] = String(line[..<idx])
        lines.insert(String(line[idx...]), at: caretLine + 1)
        caretLine += 1
        caretCol = 0
    }

    /// Editing commands from the input system (`doCommand(by:)`).
    func perform(_ selector: Selector) {
        guard session != nil else { return }
        switch selector {
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertLineBreak(_:)):
            newline()
        case #selector(NSResponder.deleteBackward(_:)):
            if caretCol > 0 {
                var line = lines[caretLine]
                line.remove(at: line.index(line.startIndex, offsetBy: caretCol - 1))
                lines[caretLine] = line
                caretCol -= 1
            } else if caretLine > 0 {
                let line = lines.remove(at: caretLine)
                caretLine -= 1
                caretCol = lines[caretLine].count
                lines[caretLine] += line
            }
        case #selector(NSResponder.deleteForward(_:)):
            let line = lines[caretLine]
            if caretCol < line.count {
                var l = line
                l.remove(at: l.index(l.startIndex, offsetBy: caretCol))
                lines[caretLine] = l
            } else if caretLine < lines.count - 1 {
                lines[caretLine] += lines.remove(at: caretLine + 1)
            }
        case #selector(NSResponder.moveLeft(_:)):
            if caretCol > 0 { caretCol -= 1 } else if caretLine > 0 { caretLine -= 1; caretCol = lines[caretLine].count }
        case #selector(NSResponder.moveRight(_:)):
            if caretCol < lines[caretLine].count { caretCol += 1 } else if caretLine < lines.count - 1 { caretLine += 1; caretCol = 0 }
        case #selector(NSResponder.moveUp(_:)):
            if caretLine > 0 { caretLine -= 1; caretCol = min(caretCol, lines[caretLine].count) }
        case #selector(NSResponder.moveDown(_:)):
            if caretLine < lines.count - 1 { caretLine += 1; caretCol = min(caretCol, lines[caretLine].count) }
        case #selector(NSResponder.moveToBeginningOfLine(_:)), #selector(NSResponder.moveToLeftEndOfLine(_:)):
            caretCol = 0
        case #selector(NSResponder.moveToEndOfLine(_:)), #selector(NSResponder.moveToRightEndOfLine(_:)):
            caretCol = lines[caretLine].count
        case #selector(NSResponder.cancelOperation(_:)):
            commit()
            return
        default:
            return
        }
        startBlink()
        render()
    }

    override func settingsChanged() { if session != nil { render() } }
    override func colorsChanged() { if session != nil { render() } }

    override func commit() {
        guard let session else { return }
        blinkTimer?.invalidate()
        blinkTimer = nil
        if lines.joined().isEmpty {
            session.cancel(doc)
        } else {
            session.commit(doc, name: L("Text"), icon: kind.icon)
        }
        self.session = nil
        mask = nil
        canvas.needsDisplay = true
    }

    override func cancel() {
        blinkTimer?.invalidate()
        session?.cancel(doc)
        session = nil
        canvas.needsDisplay = true
    }

    override func deactivate() {
        commit()
    }

    override func drawOverlay(_ ctx: CGContext) {
        guard session != nil else { return }
        let r = canvas.toView(textBounds.insetBy(dx: -2, dy: -2))
        ctx.saveGState()
        ctx.setLineWidth(1)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.stroke(r)
        ctx.setLineDash(phase: 0, lengths: [3, 3])
        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.stroke(r)
        ctx.restoreGState()
        if caretVisible {
            let c = canvas.toView(caretRect)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fill(CGRect(x: round(c.minX), y: c.minY, width: 1.5, height: c.height))
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(CGRect(x: round(c.minX) + 1.5, y: c.minY, width: 1, height: c.height))
        }
        canvas.drawHandle(ctx, at: CGPoint(x: textBounds.maxX + 6 / canvas.zoom, y: textBounds.maxY + 6 / canvas.zoom))
    }

    override func cursor(atView p: CGPoint) -> NSCursor {
        if session != nil {
            let handle = CGPoint(x: textBounds.maxX + 6 / canvas.zoom, y: textBounds.maxY + 6 / canvas.zoom)
            if canvas.hitHandle(p, handle) { return .openHand }
        }
        return .iBeam
    }
}

// MARK: - Text input bridging (dead keys, IME) for the text tool

extension CanvasView: NSTextInputClient {
    private var textTool: TextTool? { tool as? TextTool }

    func insertText(_ string: Any, replacementRange: NSRange) {
        let s = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        textTool?.insert(s)
    }

    override func doCommand(by selector: Selector) {
        textTool?.perform(selector)
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let s = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        textTool?.setMarked(s)
    }

    func unmarkText() { textTool?.setMarked("") }
    func selectedRange() -> NSRange { NSRange(location: 0, length: 0) }
    func markedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
    func hasMarkedText() -> Bool { false }
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let w = window else { return .zero }
        let r = convert(NSRect(origin: mouseImagePoint.map { toView($0) } ?? .zero, size: NSSize(width: 1, height: 20)), to: nil)
        return w.convertToScreen(r)
    }

    func characterIndex(for point: NSPoint) -> Int { 0 }
}
