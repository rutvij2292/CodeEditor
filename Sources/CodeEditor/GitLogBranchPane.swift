import AppKit

/// Left pane of the Git log (PhpStorm style): a "Branch or tag" filter over HEAD, Local, Remote (per remote, grouped by prefix) and Tags.
/// Clicking a branch or tag points the log at it; clicking a section or folder expands/collapses it.
final class GitLogBranchPane: NSView, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private enum Item { case head, row(BranchTreeRow) }

    var onSelect: ((String) -> Void)?
    private let repo: GitRepo
    private let search = NSSearchField()
    private let table = NSTableView()
    private let queue = DispatchQueue(label: "git.log.branches", qos: .userInitiated)
    private var list = BranchList()
    private var state = BranchCollapseState()
    private var items: [Item] = [.head]
    private var revision = "HEAD"
    private var lastLoad = Date.distantPast
    private var settingSelection = false
    private var favorites: Set<String> { BranchFavorites.all(for: repo.root).union(["main", "master", "origin/main", "origin/master"]) }

    init(repo: GitRepo) {
        self.repo = repo
        super.init(frame: .zero)
        build()
        reload()
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: Theme.didChange, object: nil)
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { NotificationCenter.default.removeObserver(self) }

    private func build() {
        search.placeholderString = "Branch or tag"
        search.controlSize = .regular
        search.font = .systemFont(ofSize: 13)
        search.focusRingType = .none
        search.delegate = self
        search.translatesAutoresizingMaskIntoConstraints = false

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("branch"))
        col.resizingMask = .autoresizingMask
        table.addTableColumn(col)
        table.headerView = nil
        table.rowHeight = 28
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.dataSource = self
        table.delegate = self
        table.backgroundColor = Theme.background
        table.selectionHighlightStyle = .regular
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.scrollerStyle = .overlay
        scroll.translatesAutoresizingMaskIntoConstraints = false

        addSubview(search); addSubview(scroll)
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            search.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            search.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 9),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 170),
        ])
    }

    @objc private func themeChanged() { table.backgroundColor = Theme.background; table.reloadData() }

    // MARK: data

    func reload() {
        lastLoad = Date()
        let repo = repo
        queue.async { [weak self] in
            let l = (try? repo.branchList()) ?? BranchList()
            DispatchQueue.main.async { self?.list = l; self?.rebuild() }
        }
    }

    /// Cheap enough to call whenever the log refreshes: skips the git round trip when the list is only seconds old.
    func reloadIfStale() { if Date().timeIntervalSince(lastLoad) > 3 { reload() } }

    private func rebuild() {
        var keys: [String] = []
        let q = search.stringValue.trimmingCharacters(in: .whitespaces)
        var noRecent = list; noRecent.recent = []   // "Recent" is a popup concept; here it would only repeat Local
        var rows = BranchTree.flatten(noRecent, favorites: favorites, groupByPrefix: true, showTags: true,
                                      state: state, forceExpanded: !q.isEmpty, keys: &keys)
        if !q.isEmpty {
            func name(_ r: BranchTreeRow) -> String { r.key.hasPrefix("b:") || r.key.hasPrefix("t:") ? String(r.key.dropFirst(2)) : r.title }
            var keep = [Bool](repeating: false, count: rows.count)
            for (i, r) in rows.enumerated() {
                switch r.kind {
                case .node: break
                default: keep[i] = Fuzzy.score(query: q, in: name(r)) != nil
                }
            }
            // A section / folder survives when something under it matched.
            for i in stride(from: rows.count - 1, through: 0, by: -1) {
                guard case .node = rows[i].kind else { continue }
                var j = i + 1
                while j < rows.count, rows[j].depth > rows[i].depth { if keep[j] { keep[i] = true; break }; j += 1 }
            }
            rows = rows.enumerated().filter { keep[$0.offset] }.map(\.element)
        }
        items = (q.isEmpty ? [.head] : []) + rows.map { .row($0) }
        table.reloadData()
        select(revision)
    }

    func select(_ rev: String) {
        revision = rev
        settingSelection = true
        defer { settingSelection = false }
        for (i, it) in items.enumerated() {
            switch it {
            case .head: if rev == "HEAD" { table.selectRowIndexes([i], byExtendingSelection: false); return }
            case .row(let r):
                if r.key == "b:" + rev || r.key == "t:" + rev { table.selectRowIndexes([i], byExtendingSelection: false); table.scrollRowToVisible(i); return }
            }
        }
        table.deselectAll(nil)
    }

    // MARK: table

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { true }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !settingSelection, table.selectedRow >= 0, table.selectedRow < items.count else { return }
        switch items[table.selectedRow] {
        case .head: revision = "HEAD"; onSelect?("HEAD")
        case .row(let r):
            switch r.kind {
            case .branch(let e): revision = e.name; onSelect?(e.name)
            case .tag: let t = String(r.key.dropFirst(2)); revision = t; onSelect?(t)
            case .node(_, let collapsed, _):
                BranchTree.toggle(r.key, currentlyCollapsed: collapsed, state: &state)
                rebuild()
            }
        }
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { BranchRowView() }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("branchCell")
        let cell = tableView.makeView(withIdentifier: id, owner: nil) as? NSTextField ?? {
            let f = NSTextField(labelWithString: "")
            f.identifier = id
            f.lineBreakMode = .byTruncatingTail
            return f
        }()
        func glyph(_ symbol: String, _ color: NSColor, size: CGFloat = 12) -> NSAttributedString {
            let att = NSTextAttachment()
            let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: size, weight: .regular).applying(.init(paletteColors: [color])))
            att.image = img
            let w = img?.size.width ?? 14, h = img?.size.height ?? 14
            att.bounds = NSRect(x: 0, y: -(h * 0.2), width: w, height: h)   // natural symbol size, so a chevron stays small
            return NSAttributedString(attachment: att)
        }
        let s = NSMutableAttributedString()
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        let font = NSFont.systemFont(ofSize: 13)
        let boldFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
        switch items[row] {
        case .head:
            para.firstLineHeadIndent = 26
            s.append(NSAttributedString(string: "HEAD ", attributes: [.font: boldFont, .foregroundColor: Theme.foreground]))
            s.append(NSAttributedString(string: "(Current Branch)", attributes: [.font: font, .foregroundColor: Theme.gutter]))
        case .row(let r):
            para.firstLineHeadIndent = 8 + CGFloat(r.depth) * 16
            switch r.kind {
            case .node(let folder, let collapsed, _):
                s.append(glyph(collapsed ? "chevron.right" : "chevron.down", Theme.gutter, size: 10))
                s.append(NSAttributedString(string: " "))
                if folder { s.append(glyph(collapsed ? "folder" : "folder", Theme.gutter)); s.append(NSAttributedString(string: " ")) }
                s.append(NSAttributedString(string: r.title, attributes: [.font: font, .foregroundColor: Theme.foreground]))
            case .branch(let e):
                para.firstLineHeadIndent += 14
                let fav = favorites.contains(e.name)
                s.append(glyph(fav ? "star.fill" : "arrow.triangle.branch", fav ? NSColor.systemOrange : Theme.gutter))
                s.append(NSAttributedString(string: " " + r.title, attributes: [.font: e.isCurrent ? boldFont : font, .foregroundColor: Theme.foreground]))
            case .tag:
                para.firstLineHeadIndent += 14
                s.append(glyph("tag", Theme.gutter))
                s.append(NSAttributedString(string: " " + r.title, attributes: [.font: font, .foregroundColor: Theme.foreground]))
            }
        }
        s.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: s.length))
        cell.attributedStringValue = s
        return cell
    }

    // MARK: search

    func controlTextDidChange(_ obj: Notification) { rebuild() }

    // MARK: test hooks
    func setListForTesting(_ l: BranchList) { list = l; rebuild() }
    var rowTitles: [String] { items.map { if case .row(let r) = $0 { return r.signature } else { return "HEAD" } } }
}

private final class BranchRowView: NSTableRowView {
    override var isEmphasized: Bool { get { false } set {} }
    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.controlAccentColor.withAlphaComponent(0.20).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 1), xRadius: 5, yRadius: 5).fill()
    }
}
