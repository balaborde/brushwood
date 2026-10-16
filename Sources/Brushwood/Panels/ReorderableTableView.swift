import AppKit

/// Table whose rows are reordered by dragging them within the list. The lifted row follows the pointer from the point
/// where it was grabbed, the other rows slide apart to show where it will land, and the pointer is a closed hand while
/// a row is lifted. (NSTableView's own drag and drop drew the lifted row away from the pointer, closed the gap while
/// the pointer was over the middle of a row, and let the system choose the pointer.)
final class ReorderableTableView: NSTableView {
    /// Called on release with the dragged row and the row it lands on, both counted in the order before the move.
    var onMoveRow: ((_ from: Int, _ to: Int) -> Void)?
    /// Called when a lifted row is released, after `onMoveRow`.
    var onEndReorder: (() -> Void)?
    /// True while a row is lifted.
    var isReordering: Bool { lift != nil }

    private struct Lift {
        let row: Int
        /// Pointer position below the top of the lifted row when it was grabbed.
        let grabOffset: CGFloat
        let overlay: LiftedRowView
        var target: Int
        var pointer: NSPoint
    }

    private var press: (row: Int, point: NSPoint)?
    private var lift: Lift?
    private var lastDrag: NSEvent?
    private var scrollTimer: Timer?
    /// The pointer must move this far before the row lifts, so that clicks stay clicks.
    private let threshold: CGFloat = 4

    override init(frame: NSRect) {
        super.init(frame: frame)
        // Layer-backed rows take their new place at once in `frame` while sliding on screen.
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let r = row(at: p)
        guard event.clickCount == 1, r >= 0, onMoveRow != nil, !event.modifierFlags.contains(.control) else {
            press = nil
            super.mouseDown(with: event)
            return
        }
        press = (r, p)
        if !selectedRowIndexes.contains(r) { selectRowIndexes(IndexSet(integer: r), byExtendingSelection: false) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let press else {
            super.mouseDragged(with: event)
            return
        }
        let p = convert(event.locationInWindow, from: nil)
        if lift == nil {
            guard abs(p.x - press.point.x) >= threshold || abs(p.y - press.point.y) >= threshold else { return }
            beginLift(row: press.row, grabbedAt: press.point)
        }
        lastDrag = event
        if autoscroll(with: event) {
            moveLift(to: convert(event.locationInWindow, from: nil))
        } else {
            moveLift(to: p)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard press != nil else {
            super.mouseUp(with: event)
            return
        }
        press = nil
        endLift()
    }

    // MARK: Lifting

    /// Distance between the tops of two consecutive rows.
    private var pitch: CGFloat {
        numberOfRows > 1 ? rect(ofRow: 1).minY - rect(ofRow: 0).minY : rect(ofRow: 0).height + intercellSpacing.height
    }

    private func beginLift(row: Int, grabbedAt p: NSPoint) {
        // Rows reloaded by the click (it can change the selection) are only created at the next layout.
        layoutSubtreeIfNeeded()
        guard row < numberOfRows, let rowView = rowView(atRow: row, makeIfNecessary: true),
              let rep = rowView.bitmapImageRepForCachingDisplay(in: rowView.bounds) else { return }
        rowView.cacheDisplay(in: rowView.bounds, to: rep)
        let image = NSImage(size: rowView.bounds.size)
        image.addRepresentation(rep)
        let slot = rect(ofRow: row)
        let overlay = LiftedRowView(frame: slot, image: image)
        overlay.wantsLayer = true
        overlay.layer?.zPosition = 10
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 8
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        overlay.shadow = shadow
        addSubview(overlay)
        lift = Lift(row: row, grabOffset: p.y - slot.minY, overlay: overlay, target: row, pointer: p)
        window?.disableCursorRects()
        NSCursor.closedHand.push()
        // Keeps scrolling while the pointer rests beyond the top or bottom of the list.
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let e = lastDrag, autoscroll(with: e) else { return }
            moveLift(to: convert(e.locationInWindow, from: nil))
        }
        RunLoop.main.add(timer, forMode: .common)
        scrollTimer = timer
        layoutRows()
    }

    private func moveLift(to p: NSPoint) {
        guard var lift else { return }
        let slot = rect(ofRow: lift.row)
        let top = min(max(p.y - lift.grabOffset, 0), max(0, bounds.height - slot.height))
        lift.overlay.setFrameOrigin(NSPoint(x: slot.minX, y: top))
        if lift.overlay !== subviews.last { addSubview(lift.overlay) }
        // The row lands in the slot under the middle of the lifted row.
        let middle = top + slot.height / 2 - rect(ofRow: 0).minY
        lift.target = min(max(Int((middle / pitch).rounded(.down)), 0), numberOfRows - 1)
        lift.pointer = p
        self.lift = lift
        layoutRows()
    }

    /// Vertical shift of `row` while the lifted row is over its target: the rows in between move by one place.
    private func shift(ofRow row: Int) -> CGFloat {
        guard let lift, row != lift.row else { return 0 }
        if lift.row < lift.target, row > lift.row, row <= lift.target { return -pitch }
        if lift.target < lift.row, row >= lift.target, row < lift.row { return pitch }
        return 0
    }

    private func layoutRows() {
        enumerateAvailableRowViews { rowView, row in
            rowView.alphaValue = row == lift?.row ? 0 : 1
            let y = rect(ofRow: row).minY + shift(ofRow: row)
            guard abs(rowView.frame.minY - y) > 0.5 else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                ctx.allowsImplicitAnimation = true
                rowView.animator().setFrameOrigin(NSPoint(x: rowView.frame.minX, y: y))
            }
        }
    }

    private func endLift() {
        guard let lift else { return }
        self.lift = nil
        scrollTimer?.invalidate()
        scrollTimer = nil
        lastDrag = nil
        NSCursor.pop()
        window?.enableCursorRects()
        window?.invalidateCursorRects(for: self)
        if lift.target != lift.row {
            // The move reloads the table, which puts every row at its new place.
            enumerateAvailableRowViews { rowView, _ in rowView.alphaValue = 1 }
            onMoveRow?(lift.row, lift.target)
        } else {
            layoutRows()
        }
        onEndReorder?()
        // The lifted row settles into its slot, then the row underneath shows again.
        let slot = rect(ofRow: lift.target)
        let overlay = lift.overlay
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            overlay.animator().setFrameOrigin(slot.origin)
        }, completionHandler: { [weak self] in
            overlay.removeFromSuperview()
            self?.enumerateAvailableRowViews { rowView, _ in rowView.alphaValue = 1 }
        })
    }

    // MARK: Checks (DebugScript)

    /// While a row is lifted: the top of the lifted row, the row it would land on, whether the pointer is a closed
    /// hand, and the rows that are not where they should have slid to (or the lifted row's own place, not hidden).
    func debugLiftState() -> (top: CGFloat, target: Int, closedHand: Bool, misplacedRows: [Int])? {
        guard let lift else { return nil }
        var misplaced: [Int] = []
        enumerateAvailableRowViews { rowView, row in
            let y = rect(ofRow: row).minY + shift(ofRow: row)
            if abs(rowView.frame.minY - y) > 0.5 || (row == lift.row) != (rowView.alphaValue == 0) { misplaced.append(row) }
        }
        return (lift.overlay.frame.minY, lift.target, NSCursor.current === NSCursor.closedHand, misplaced)
    }
}

/// The lifted row: the row's picture on an opaque background, so the rows it passes over don't show through. The
/// picture of a row leaves out its selection highlight, which is drawn here (the lifted row is the selected one).
private final class LiftedRowView: NSView {
    private let image: NSImage

    init(frame: NSRect, image: NSImage) {
        self.image = image
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()
        NSColor.unemphasizedSelectedContentBackgroundColor.setFill()
        bounds.fill()
        image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}
