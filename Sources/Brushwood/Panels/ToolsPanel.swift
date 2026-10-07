import AppKit
import BrushwoodCore

final class ToolsPanel: FloatingPanel {
    private var buttons: [ToolKind: ToolbarButton] = [:]
    private var observer: NSObjectProtocol?

    init() {
        let cols = 2, size: CGFloat = 28
        let rows = (ToolKind.allCases.count + cols - 1) / cols
        super.init(title: L("Tools"), size: NSSize(width: CGFloat(cols) * size + 12, height: CGFloat(rows) * size + 12),
                   resizable: false)
        let grid = NSGridView()
        grid.rowSpacing = 0
        grid.columnSpacing = 0
        var row: [NSView] = []
        for t in ToolKind.allCases {
            let b = ToolbarButton(icon: t.icon, tooltip: "\(t.name) (\(String(t.shortcutKey).uppercased()))", target: nil, action: nil,
                                  size: size)
            b.onAction { [weak self] _ in self?.host?.selectTool(t) }
            buttons[t] = b
            row.append(b)
            if row.count == cols {
                grid.addRow(with: row)
                row = []
            }
        }
        if !row.isEmpty {
            while row.count < cols { row.append(NSGridCell.emptyContentView) }
            grid.addRow(with: row)
        }
        grid.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            grid.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
        contentView = content
        observer = NotificationCenter.default.addObserver(forName: .toolChanged, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func refresh() {
        let active = AppEnvironment.shared.activeTool
        for (k, b) in buttons { b.isToggled = k == active }
    }
}
