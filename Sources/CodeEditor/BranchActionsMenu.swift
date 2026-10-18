import AppKit

/// One entry of the floating per-branch actions menu.
struct BranchMenuItem {
    var title: String = ""
    var shortcut = ""
    var enabled = true
    var separator = false
    var key: String?                       // "delete" / "rename": reachable with ⌫ / F2 while the menu is focused
    var children: [BranchMenuItem]?        // non-nil: a submenu (shown with ›)
    var run: (() -> Void)?

    static var sep: BranchMenuItem { BranchMenuItem(separator: true) }
}

private final class MenuPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class MenuTable: NSTableView {
    override var acceptsFirstResponder: Bool { false }
    var onHover: ((Int) -> Void)?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseMoved(with event: NSEvent) { onHover?(row(at: convert(event.locationInWindow, from: nil))) }
}

private final class MenuRowBackground: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.controlAccentColor.withAlphaComponent(Theme.isDark ? 0.40 : 0.85).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 1), xRadius: 6, yRadius: 6).fill()
    }
}

private final class MenuCell: NSView {
    let title = NSTextField(labelWithString: "")
    let trailing = NSTextField(labelWithString: "")
    var separator = false
    override init(frame: NSRect) {
        super.init(frame: frame)
        title.lineBreakMode = .byTruncatingTail
        trailing.alignment = .right
        addSubview(title); addSubview(trailing)
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ item: BranchMenuItem, selected: Bool) {
        separator = item.separator
        title.isHidden = item.separator; trailing.isHidden = item.separator
        needsDisplay = true
        guard !item.separator else { return }
        let onAccent = selected && item.enabled && !Theme.isDark
        let color: NSColor = !item.enabled ? Theme.gutter : (onAccent ? .white : Theme.foreground)
        title.attributedStringValue = NSAttributedString(string: item.title, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: color])
        trailing.attributedStringValue = NSAttributedString(string: item.children != nil ? "›" : item.shortcut,
                                                            attributes: [.font: NSFont.systemFont(ofSize: item.children != nil ? 15 : 12),
                                                                         .foregroundColor: onAccent ? NSColor.white.withAlphaComponent(0.85) : Theme.gutter])
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        let tw = ceil(trailing.attributedStringValue.size().width) + 6
        trailing.frame = NSRect(x: bounds.width - 14 - tw, y: (h - 18) / 2, width: tw, height: 18)
        title.frame = NSRect(x: 16, y: (h - 18) / 2, width: max(10, bounds.width - 16 - 14 - tw - 10), height: 18)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard separator else { return }
        Theme.gutter.withAlphaComponent(0.3).setFill()
        NSRect(x: 12, y: bounds.midY, width: bounds.width - 24, height: 1).fill()
    }
}

/// PhpStorm-style floating actions menu attached to the right of a popup row. Never takes key focus: the popup forwards keys.
final class BranchActionsMenu: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    static let rowH: CGFloat = 26, sepH: CGFloat = 9

    private(set) var items: [BranchMenuItem]
    private let panel: MenuPanel
    private let root = NSView()
    private let table = MenuTable()
    private weak var parentWindow: NSWindow?
    private(set) var child: BranchActionsMenu?
    private weak var parentMenu: BranchActionsMenu?
    private var closed = false
    var onClose: (() -> Void)?

    var width: CGFloat { panel.frame.width }
    var height: CGFloat { panel.frame.height }
    var deepest: BranchActionsMenu { child?.deepest ?? self }
    var selectedRow: Int { table.selectedRow }
    var selectedTitle: String { table.selectedRow >= 0 ? items[table.selectedRow].title : "" }

    /// `anchor` is the screen rect of the row the menu belongs to; the menu opens to its right (or left when it would leave the screen).
    init(items: [BranchMenuItem], over window: NSWindow, anchor: NSRect, parent: BranchActionsMenu? = nil) {
        self.items = items
        self.parentWindow = window
        self.parentMenu = parent
        panel = MenuPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.contentView = root
        root.wantsLayer = true
        root.layer?.cornerRadius = 9
        root.layer?.masksToBounds = true
        root.layer?.borderWidth = 0.5
        root.layer?.backgroundColor = Theme.background.cgColor
        root.layer?.borderColor = Theme.gutter.withAlphaComponent(0.4).cgColor
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c"))
        table.addTableColumn(col)
        table.headerView = nil
        table.style = .plain
        table.intercellSpacing = .zero
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .regular
        table.allowsEmptySelection = false
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(clicked)
        table.onHover = { [weak self] row in
            guard let self, row >= 0, row < self.items.count, self.selectable(row), row != self.table.selectedRow else { return }
            self.child?.close(); self.child = nil
            self.table.selectRowIndexes([row], byExtendingSelection: false)
        }
        root.addSubview(table)

        let w = max(250, ceil(items.map { Self.textWidth($0) }.max() ?? 0) + 60)
        let h = items.reduce(CGFloat(8)) { $0 + ($1.separator ? Self.sepH : Self.rowH) }
        var origin = NSPoint(x: anchor.maxX + 4, y: anchor.maxY + 5 - h)
        if let screen = window.screen?.visibleFrame {
            if origin.x + w > screen.maxX { origin.x = anchor.minX - w - 4 }
            origin.y = max(screen.minY + 4, origin.y)
        }
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: w, height: h)), display: false)
        root.frame = NSRect(x: 0, y: 0, width: w, height: h)
        table.frame = NSRect(x: 0, y: 4, width: w, height: h - 8)
        table.tableColumns[0].width = w
        table.reloadData()
        if let first = items.indices.first(where: { selectable($0) }) { table.selectRowIndexes([first], byExtendingSelection: false) }
        window.addChildWindow(panel, ordered: .above)
        if !AppEnv.headless { panel.orderFront(nil) }
    }

    private static func textWidth(_ i: BranchMenuItem) -> CGFloat {
        i.title.size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width
            + (i.shortcut.isEmpty ? 0 : i.shortcut.size(withAttributes: [.font: NSFont.systemFont(ofSize: 12)]).width + 30)
    }

    private func selectable(_ row: Int) -> Bool { !items[row].separator }

    func close() {
        guard !closed else { return }
        closed = true
        child?.close(); child = nil
        parentWindow?.removeChildWindow(panel)
        panel.orderOut(nil)
        onClose?()
    }

    // MARK: keys (called on the deepest menu by the popup)

    func move(_ delta: Int) {
        var i = table.selectedRow + delta
        while i >= 0, i < items.count, !selectable(i) { i += delta }
        if i >= 0, i < items.count { table.selectRowIndexes([i], byExtendingSelection: false); table.scrollRowToVisible(i) }
    }

    /// Runs the selected item, or opens its submenu. Returns true when an action ran (the popup then closes).
    @discardableResult
    func activate() -> Bool {
        let r = table.selectedRow
        guard r >= 0, r < items.count else { return false }
        let it = items[r]
        guard it.enabled else { return false }
        if it.children != nil { openChild(); return false }
        it.run?()
        return true
    }

    func openChild() {
        let r = table.selectedRow
        guard r >= 0, r < items.count, items[r].enabled, let kids = items[r].children, child == nil, let window = parentWindow else { return }
        let rowRect = table.convert(table.rect(ofRow: r), to: nil)
        let screenRect = panel.convertToScreen(rowRect)
        child = BranchActionsMenu(items: kids, over: window, anchor: screenRect, parent: self)
    }

    /// Closes the deepest open submenu; false when this menu is the root (nothing nested to close).
    func closeDeepestChild() -> Bool {
        if let c = child { if c.child != nil { return c.closeDeepestChild() }; c.close(); child = nil; return true }
        return false
    }

    /// Runs the item carrying `key` (⌫ / F2) from this menu or any open ancestor.
    func runKeyed(_ key: String) -> Bool {
        for menu in sequence(first: Optional(self.deepest), next: { $0?.parentMenu }) {
            guard let m = menu else { break }
            if let it = m.items.first(where: { $0.key == key }), it.enabled { it.run?(); return true }
        }
        return false
    }

    @objc private func clicked() {
        let r = table.clickedRow
        guard r >= 0, r < items.count, selectable(r) else { return }
        table.selectRowIndexes([r], byExtendingSelection: false)
        activate()
    }

    // MARK: snapshot

    func renderImage() -> NSImage? {
        root.layoutSubtreeIfNeeded()
        guard let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { return nil }
        root.cacheDisplay(in: root.bounds, to: rep)
        let img = NSImage(size: root.bounds.size)
        img.addRepresentation(rep)
        return img
    }

    var allTitles: [String] { items.map { $0.separator ? "---" : $0.title } }
    var panelFrame: NSRect { panel.frame }

    // MARK: table

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { items[row].separator ? Self.sepH : Self.rowH }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { selectable(row) }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { MenuRowBackground() }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = MenuCell(frame: .zero)
        cell.configure(items[row], selected: row == tableView.selectedRow)
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        for i in 0..<items.count { (table.view(atColumn: 0, row: i, makeIfNecessary: false) as? MenuCell)?.configure(items[i], selected: i == table.selectedRow) }
    }
}
