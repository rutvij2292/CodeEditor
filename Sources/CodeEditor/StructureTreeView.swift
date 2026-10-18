import AppKit

/// Collapsible tree of a JSON / YAML document (shared by both viewers): typed, coloured values, array lengths, filter box,
/// path breadcrumb with copy actions and click-to-jump. Children are created lazily from the StructTape, so a 10 MB file
/// costs rows only for what is expanded.
final class StructureTreeView: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate, NSSearchFieldDelegate, NSMenuDelegate {
    /// A row: a tape node (`idx` >= 0) or a bucket of consecutive children ("[0 … 99]", idx -1) used to keep huge arrays small.
    final class Item: NSObject {
        let idx: Int32
        let pos: Int
        weak var up: Item?
        var members: [Int32]?          // buckets only
        var offset = 0                 // buckets: index of the first member among the parent's children (unfiltered)
        var arrayIndex = 0             // nodes: index among the parent's children (unfiltered)
        var kids: [Item]?
        init(idx: Int32, pos: Int, up: Item?, members: [Int32]? = nil) { self.idx = idx; self.pos = pos; self.up = up; self.members = members }
        var isBucket: Bool { members != nil }
    }
    static let bucketThreshold = 200

    private final class RowView: NSTableRowView {
        override func drawSelection(in dirtyRect: NSRect) {
            (isEmphasized ? Theme.palette.treeSelectionActive : Theme.palette.treeSelectionInactive).setFill()
            bounds.fill()
        }
    }

    private(set) var tape: StructTape?
    var onJump: ((NSRange) -> Void)?
    let outline = NSOutlineView()
    private let scroll = NSScrollView()
    private let search = NSSearchField()
    private let status = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let copyPathButton = NSButton(title: "Copy Path", target: nil, action: nil)
    private let copyValueButton = NSButton(title: "Copy Value", target: nil, action: nil)
    private let expandButton = NSButton()
    private let collapseButton = NSButton()
    private let topLine = NSView(), bottomLine = NSView()
    private var rootItem: Item?
    private var visible: Set<Int32>?              // non-nil while filtering: matches + their ancestors
    private var query = ""
    private var searchWork: DispatchWorkItem?
    private var searchGen = 0
    private var suppressJump = false
    private(set) var matchCount = 0
    private let font = { Theme.font.withSize(max(11, Theme.font.pointSize - 1)) }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        search.placeholderString = "Filter keys and values"
        search.controlSize = .small
        search.font = .systemFont(ofSize: 11)
        search.delegate = self
        search.sendsSearchStringImmediately = false
        for (b, sym, tip, sel) in [(expandButton, "arrow.down.right.and.arrow.up.left", "Expand all", #selector(expandAllTapped)),
                                   (collapseButton, "arrow.up.left.and.arrow.down.right", "Collapse all", #selector(collapseAllTapped))] as [(NSButton, String, String, Selector)] {
            b.isBordered = false
            b.image = NSImage(systemSymbolName: sym, accessibilityDescription: tip)
            b.toolTip = tip
            b.target = self; b.action = sel
            b.imagePosition = .imageOnly
        }
        expandButton.image = NSImage(systemSymbolName: "chevron.down.2", accessibilityDescription: "Expand all")
        collapseButton.image = NSImage(systemSymbolName: "chevron.up.2", accessibilityDescription: "Collapse all")
        for b in [copyPathButton, copyValueButton] {
            b.bezelStyle = .rounded; b.controlSize = .small; b.font = .systemFont(ofSize: 11); b.target = self
        }
        copyPathButton.action = #selector(copyPathTapped); copyValueButton.action = #selector(copyValueTapped)
        status.font = .systemFont(ofSize: 11)
        status.lineBreakMode = .byTruncatingTail
        pathLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        pathLabel.lineBreakMode = .byTruncatingHead

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.rowHeight = 20
        outline.indentationPerLevel = 14
        outline.usesAlternatingRowBackgroundColors = false
        outline.selectionHighlightStyle = .regular
        outline.dataSource = self
        outline.delegate = self
        outline.autoresizesOutlineColumn = false
        outline.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        outline.gridStyleMask = []
        outline.intercellSpacing = NSSize(width: 0, height: 0)
        let menu = NSMenu()
        menu.delegate = self
        outline.menu = menu
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.drawsBackground = true
        scroll.autohidesScrollers = true

        let header = NSStackView(views: [search, expandButton, collapseButton])
        header.spacing = 6
        header.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        let footer = NSStackView(views: [pathLabel, copyPathButton, copyValueButton])
        footer.spacing = 6
        footer.edgeInsets = NSEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)
        pathLabel.setContentHuggingPriority(.init(1), for: .horizontal)
        pathLabel.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        status.setContentHuggingPriority(.init(1), for: .horizontal)
        status.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        let statusRow = NSStackView(views: [status])
        statusRow.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 3, right: 10)
        for v in [header, scroll, footer, statusRow, topLine, bottomLine] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        topLine.wantsLayer = true; bottomLine.wantsLayer = true
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor), header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            topLine.topAnchor.constraint(equalTo: header.bottomAnchor), topLine.leadingAnchor.constraint(equalTo: leadingAnchor),
            topLine.trailingAnchor.constraint(equalTo: trailingAnchor), topLine.heightAnchor.constraint(equalToConstant: 1),
            scroll.topAnchor.constraint(equalTo: topLine.bottomAnchor), scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomLine.topAnchor.constraint(equalTo: scroll.bottomAnchor), bottomLine.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomLine.trailingAnchor.constraint(equalTo: trailingAnchor), bottomLine.heightAnchor.constraint(equalToConstant: 1),
            footer.topAnchor.constraint(equalTo: bottomLine.bottomAnchor), footer.leadingAnchor.constraint(equalTo: leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: trailingAnchor),
            statusRow.topAnchor.constraint(equalTo: footer.bottomAnchor), statusRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            statusRow.trailingAnchor.constraint(equalTo: trailingAnchor), statusRow.bottomAnchor.constraint(equalTo: bottomAnchor),
            search.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
        ])
        restyle()
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: Theme.didChange, object: nil)
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func themeChanged() { restyle(); outline.reloadData(); restoreAfterReload() }

    private func restyle() {
        layer?.backgroundColor = Theme.background.cgColor
        scroll.backgroundColor = Theme.background
        outline.backgroundColor = Theme.background
        let line = Theme.foreground.withAlphaComponent(0.12).cgColor
        topLine.layer?.backgroundColor = line; bottomLine.layer?.backgroundColor = line
        status.textColor = Theme.gutter
        pathLabel.textColor = Theme.foreground
        for b in [expandButton, collapseButton] { b.contentTintColor = Theme.gutter }
    }

    // MARK: Content

    /// Replaces the document. Expansion state survives live updates (by child positions).
    func show(tape new: StructTape?, message: String? = nil) {
        let saved = expandedChains()
        let hadTape = tape != nil
        tape = new
        visible = nil
        rootItem = new.flatMap { $0.isEmpty ? nil : Item(idx: 0, pos: 0, up: nil) }
        outline.reloadData()
        if let root = rootItem {
            outline.expandItem(root)
            if hadTape, !saved.isEmpty { expand(chains: saved) } else { autoExpand(root) }
        }
        var parts: [String] = []
        if let t = new {
            parts.append(t.isEmpty ? "Empty document" : "\(t.nodeCount.formatted()) values")
            if t.truncated { parts.append("showing the first \(t.nodeCount.formatted())") }
        }
        if let message { parts.insert(message, at: 0) }
        status.stringValue = parts.joined(separator: " · ")
        status.textColor = new?.issues.contains { $0.severity == 1 } == true ? .systemRed : Theme.gutter
        updateFooter()
        if !query.isEmpty { applyFilter(query) }
    }

    private func autoExpand(_ root: Item) {
        guard let t = tape else { return }
        let kids = items(of: root)
        if kids.count <= 40 { for k in kids where k.idx >= 0 && t.isContainer(k.idx) && t.childCount(k.idx) <= 60 { outline.expandItem(k) } }
    }

    private func expandedChains() -> [[Int]] {
        guard rootItem != nil else { return [] }
        var out: [[Int]] = []
        for row in 0..<min(outline.numberOfRows, 4000) {
            guard let item = outline.item(atRow: row) as? Item, outline.isItemExpanded(item) else { continue }
            var chain: [Int] = [], cur: Item? = item
            while let c = cur, c.up != nil { chain.append(c.pos); cur = c.up }
            out.append(chain.reversed())
            if out.count >= 600 { break }
        }
        return out
    }

    private func expand(chains: [[Int]]) {
        guard let root = rootItem else { return }
        for chain in chains.sorted(by: { $0.count < $1.count }) {
            var cur = root
            var ok = true
            for p in chain {
                let kids = items(of: cur)
                guard kids.indices.contains(p) else { ok = false; break }
                cur = kids[p]
            }
            if ok, cur.isBucket || tape?.isContainer(cur.idx) == true { outline.expandItem(cur) }
        }
    }

    private func restoreAfterReload() {
        guard let root = rootItem else { return }
        outline.expandItem(root)
    }

    // MARK: Data source

    /// Child rows of `item`, built once: the node's children (filtered while searching), bucketed when there are very many.
    private func kidsOf(_ item: Item) -> [Item] {
        if let k = item.kids { return k }
        guard let t = tape else { return [] }
        var base = item.members ?? (t.isContainer(item.idx) ? t.children(of: item.idx) : [])
        if let v = visible { base = base.filter { v.contains($0) } }
        var kids: [Item] = []
        if base.count > Self.bucketThreshold {
            var size = 100
            while base.count / size > Self.bucketThreshold { size *= 100 }
            var a = 0
            while a < base.count {
                let slice = Array(base[a..<min(base.count, a + size)])
                let b = Item(idx: -1, pos: kids.count, up: item, members: slice)
                b.offset = item.offset + a
                kids.append(b)
                a += size
            }
        } else {
            kids = base.enumerated().map { e in
                let n = Item(idx: e.element, pos: e.offset, up: item)
                n.arrayIndex = (item.isBucket ? item.offset : 0) + e.offset
                return n
            }
        }
        item.kids = kids
        return kids
    }

    private func items(of item: Item) -> [Item] { kidsOf(item) }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let item = item as? Item else { return rootItem == nil ? 0 : 1 }
        return kidsOf(item).count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let item = item as? Item else { return rootItem! }
        return kidsOf(item)[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let item = item as? Item, let t = tape else { return false }
        if item.isBucket { return true }
        return t.isContainer(item.idx) && (visible != nil ? !kidsOf(item).isEmpty : t.childCount(item.idx) > 0)
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? { RowView() }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let item = item as? Item else { return nil }
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = (outlineView.makeView(withIdentifier: id, owner: self) as? NSTableCellView) ?? {
            let c = NSTableCellView()
            c.identifier = id
            let t = NSTextField(labelWithString: "")
            t.lineBreakMode = .byTruncatingTail
            t.translatesAutoresizingMaskIntoConstraints = false
            c.addSubview(t)
            c.textField = t
            NSLayoutConstraint.activate([t.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 2),
                                         t.trailingAnchor.constraint(equalTo: c.trailingAnchor), t.centerYAnchor.constraint(equalTo: c.centerYAnchor)])
            return c
        }()
        cell.textField?.attributedStringValue = item.isBucket ? bucketLabel(item) : label(for: item.idx, position: visible == nil ? item.arrayIndex : nil)
        return cell
    }

    // MARK: Row text

    private func color(_ capture: String) -> NSColor { Theme.color(for: capture) ?? Theme.foreground }

    func label(for i: Int32, position: Int? = nil) -> NSAttributedString {
        guard let t = tape else { return NSAttributedString() }
        let f = font()
        let out = NSMutableAttributedString()
        func add(_ s: String, _ c: NSColor) { out.append(NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: c])) }
        let dim = Theme.gutter
        if let key = t.keyText(i) {
            add(key.count > 120 ? String(key.prefix(120)) + "…" : key, color("string.special.key"))
            add(": ", dim)
        } else if i != 0, t.parentOf(i) >= 0, t.kindOf(t.parentOf(i)) == .array {
            add("[\(position ?? (t.children(of: t.parentOf(i)).firstIndex(of: i) ?? 0))] ", dim)
        }
        switch t.kindOf(i) {
        case .object: add("{ \(t.childCount(i)) }", dim)
        case .array: add("[ \(t.childCount(i)) ]", dim)
        case .string: add("\"" + oneLine(t.scalarText(i)) + "\"", color("string"))
        case .number: add(oneLine(t.scalarText(i)), color("number"))
        case .bool, .null: add(oneLine(t.scalarText(i)).isEmpty ? "null" : oneLine(t.scalarText(i)), color("constant.builtin"))
        }
        if !query.isEmpty {
            let s = out.string as NSString
            var r = NSRange(location: 0, length: s.length)
            let bg = NSColor.systemYellow.withAlphaComponent(Theme.isDark ? 0.35 : 0.5)
            while r.length > 0 {
                let hit = s.range(of: query, options: .caseInsensitive, range: r)
                if hit.location == NSNotFound { break }
                out.addAttribute(.backgroundColor, value: bg, range: hit)
                r = NSRange(location: NSMaxRange(hit), length: s.length - NSMaxRange(hit))
            }
        }
        return out
    }

    private func bucketLabel(_ item: Item) -> NSAttributedString {
        guard let t = tape, let m = item.members, let first = m.first, let last = m.last else { return NSAttributedString() }
        func index(_ n: Int32) -> Int { let p = t.parentOf(n); return p >= 0 ? (t.children(of: p).firstIndex(of: n) ?? 0) : 0 }
        let text = visible == nil ? "[\(index(first)) … \(index(last))]" : "\(m.count) matches"
        return NSAttributedString(string: text, attributes: [.font: font(), .foregroundColor: Theme.gutter])
    }

    private func oneLine(_ s: String) -> String {
        s.contains("\n") || s.contains("\r") ? s.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "⏎") : s
    }

    // MARK: Selection

    func outlineViewSelectionDidChange(_ notification: Notification) {
        updateFooter()
        guard !suppressJump, let item = selectedItem, item.idx >= 0, let t = tape else { return }
        onJump?(t.editorRange(item.idx))
    }

    private var selectedItem: Item? { outline.selectedRow >= 0 ? outline.item(atRow: outline.selectedRow) as? Item : nil }

    private func updateFooter() {
        if let item = selectedItem, item.idx >= 0, let t = tape {
            pathLabel.stringValue = t.path(item.idx)
            copyPathButton.isEnabled = true; copyValueButton.isEnabled = true
        } else {
            pathLabel.stringValue = tape == nil ? "" : "$"
            copyPathButton.isEnabled = false; copyValueButton.isEnabled = false
        }
    }

    var selectedPath: String { pathLabel.stringValue }

    /// Selects (and expands to) the deepest node containing `offset`, without jumping the editor.
    func reveal(offset: Int) {
        guard let t = tape, let root = rootItem, visible == nil else { return }
        let chain = t.chain(at: offset)
        guard chain.count >= 1 else { return }
        var cur = root
        for idx in chain.dropFirst() {
            outline.expandItem(cur)
            // descend through buckets to the row holding `idx`
            var level = cur
            var found: Item?
            for _ in 0..<6 {
                let kids = kidsOf(level)
                if let hit = kids.first(where: { !$0.isBucket && $0.idx == idx }) { found = hit; break }
                guard let bucket = kids.first(where: { $0.members?.contains(idx) == true }) else { break }
                outline.expandItem(bucket)
                level = bucket
            }
            guard let next = found else { break }
            cur = next
        }
        let row = outline.row(forItem: cur)
        guard row >= 0 else { return }
        suppressJump = true
        outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        suppressJump = false
        outline.scrollRowToVisible(row)
    }

    /// Test/automation hook: selects the node at `path` index chain (child positions from the root).
    func select(positions: [Int], jump: Bool = true) {
        guard let root = rootItem else { return }
        var cur = root
        for p in positions {
            outline.expandItem(cur)
            let kids = items(of: cur)
            guard kids.indices.contains(p) else { return }
            cur = kids[p]
        }
        let row = outline.row(forItem: cur)
        guard row >= 0 else { return }
        suppressJump = !jump
        outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        suppressJump = false
        outline.scrollRowToVisible(row)
    }

    // MARK: Filter

    func controlTextDidChange(_ obj: Notification) {
        searchWork?.cancel()
        let q = search.stringValue
        let w = DispatchWorkItem { [weak self] in self?.applyFilter(q) }
        searchWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: w)
    }

    func setFilter(_ q: String) { search.stringValue = q; applyFilter(q) }

    private func applyFilter(_ q: String) {
        query = q
        searchGen += 1
        let gen = searchGen
        guard let t = tape else { return }
        if q.isEmpty {
            visible = nil; matchCount = 0
            rootItem = t.isEmpty ? nil : Item(idx: 0, pos: 0, up: nil)
            outline.reloadData()
            if let r = rootItem { outline.expandItem(r); autoExpand(r) }
            status.stringValue = "\(t.nodeCount.formatted()) values"
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let res = t.search(q)
            DispatchQueue.main.async {
                guard let self, gen == self.searchGen, self.tape === t else { return }
                self.matchCount = res.matches.count
                self.visible = res.visible
                self.rootItem = res.visible.contains(0) ? Item(idx: 0, pos: 0, up: nil) : nil
                self.outline.reloadData()
                if let r = self.rootItem { self.outline.expandItem(r, expandChildren: true) }
                self.status.stringValue = res.matches.isEmpty ? "No matches" : "\(res.matches.count)\(res.matches.count >= 2000 ? "+" : "") match\(res.matches.count == 1 ? "" : "es")"
            }
        }
    }

    // MARK: Actions

    @objc private func expandAllTapped() {
        guard let root = rootItem, let t = tape else { return }
        if t.nodeCount <= 20_000 { outline.expandItem(root, expandChildren: true) }
        else {
            outline.expandItem(root)
            for k in items(of: root).prefix(200) where k.idx >= 0 && t.isContainer(k.idx) { outline.expandItem(k) }
            status.stringValue = "Large document: expanded two levels"
        }
    }

    @objc private func collapseAllTapped() {
        guard let root = rootItem else { return }
        outline.collapseItem(root, collapseChildren: true)
        outline.expandItem(root)
    }

    @objc private func copyPathTapped() { copyPath() }
    @objc private func copyValueTapped() { copyValue() }

    func copyPath() {
        guard let item = rowItem() else { return }
        copy(tape?.path(item.idx) ?? "")
    }

    func copyKey() {
        guard let item = rowItem() else { return }
        copy(tape?.keyText(item.idx) ?? "")
    }

    func copyValue() {
        guard let item = rowItem(), let t = tape else { return }
        if t.isContainer(item.idx) {
            let s = Int(t.start[Int(item.idx)]), e = min(Int(t.end[Int(item.idx)]), s + 2_000_000)
            copy(t.slice(s, e))
        } else { copy(t.fullScalarText(item.idx)) }
    }

    private func rowItem() -> Item? {
        let i = outline.clickedRow >= 0 ? outline.item(atRow: outline.clickedRow) as? Item : selectedItem
        guard let i, i.idx >= 0 else { return nil }
        return i
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard outline.clickedRow >= 0 else { return }
        for (title, sel) in [("Copy Path", #selector(copyPathMenu)), ("Copy Key", #selector(copyKeyMenu)), ("Copy Value", #selector(copyValueMenu))] {
            let i = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            i.target = self
            menu.addItem(i)
        }
        menu.addItem(.separator())
        let jump = NSMenuItem(title: "Jump to Source", action: #selector(jumpMenu), keyEquivalent: "")
        jump.target = self
        menu.addItem(jump)
    }

    @objc private func copyPathMenu() { copyPath() }
    @objc private func copyKeyMenu() { copyKey() }
    @objc private func copyValueMenu() { copyValue() }
    @objc private func jumpMenu() {
        guard let item = rowItem(), let t = tape else { return }
        onJump?(t.editorRange(item.idx))
    }
}
