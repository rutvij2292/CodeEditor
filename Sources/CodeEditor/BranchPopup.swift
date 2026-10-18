import AppKit

enum BranchAction: String {
    case newBranch, checkoutRevision, fetchUpdate
    case checkout, newFrom, checkoutAndRebase, rebaseOnto, merge, compare
    case pullMerge, pullRebase, push, rename, delete, deleteRemote, favorite
}

private final class BranchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class BranchTable: NSTableView {
    override var acceptsFirstResponder: Bool { false }
}

private final class BranchRowBackground: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.controlAccentColor.withAlphaComponent(Theme.isDark ? 0.35 : 0.22).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 1), xRadius: 6, yRadius: 6).fill()
    }
}

enum BranchAge {
    static func short(_ ts: TimeInterval, now: Date = Date()) -> String {
        guard ts > 0 else { return "" }
        let s = max(0, now.timeIntervalSince1970 - ts)
        switch s {
        case ..<3600: return "\(max(1, Int(s / 60)))m"
        case ..<86_400: return "\(Int(s / 3600))h"
        case ..<(86_400 * 30): return "\(Int(s / 86_400))d"
        case ..<(86_400 * 365): return "\(Int(s / (86_400 * 30)))mo"
        default: return "\(Int(s / (86_400 * 365)))y"
        }
    }
}

/// One row of the popup.
private enum Row {
    case action(id: BranchAction, title: String, symbol: String, enabled: Bool, detail: String)
    case header(title: String, key: String, indent: Int, collapsed: Bool?, count: Int)   // collapsed nil = not collapsible
    case branch(BranchEntry, indent: Int, display: String, favorite: Bool, kind: String)
    case tag(String)
    case back(String)
    case text(String)

    var selectable: Bool { if case .text = self { return false }; return true }
}

private final class BranchRowCell: NSView {
    let icon = NSImageView()
    let title = NSTextField(labelWithString: "")
    let detail = NSTextField(labelWithString: "")
    let star = NSImageView()
    var indent: CGFloat = 0
    var showsStar = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        icon.imageScaling = .scaleProportionallyDown
        title.lineBreakMode = .byTruncatingTail
        detail.lineBreakMode = .byTruncatingTail
        detail.alignment = .right
        detail.font = .systemFont(ofSize: 11.5)
        star.imageScaling = .scaleProportionallyDown
        for v in [icon, title, detail, star] { addSubview(v) }
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ row: Row, matches: Set<Int>, selected: Bool) {
        var text = "", sub = "", symbol = "circle", tint = Theme.gutter, bold = false, titleColor = Theme.foreground
        var size: CGFloat = 13.5
        showsStar = false; indent = 0; star.isHidden = true
        switch row {
        case .action(_, let t, let s, let enabled, let d):
            text = t; symbol = s; sub = d; tint = enabled ? NSColor.controlAccentColor : Theme.gutter
            if !enabled { titleColor = Theme.gutter }
        case .header(let t, _, let ind, let collapsed, let count):
            text = t; indent = CGFloat(ind) * 14; size = 11.5; bold = true; titleColor = Theme.gutter
            symbol = collapsed == nil ? "" : (collapsed! ? "chevron.right" : "chevron.down")
            sub = count > 0 && collapsed == true ? "\(count)" : ""
        case .branch(let e, let ind, let display, let fav, let kind):
            text = display; indent = CGFloat(ind) * 14
            symbol = e.isCurrent ? "checkmark" : (e.isRemote ? "cloud" : "arrow.triangle.branch")
            tint = e.isCurrent ? .controlAccentColor : Theme.gutter
            bold = e.isCurrent
            if e.isCurrent { titleColor = .controlAccentColor }
            var parts: [String] = []
            if e.ahead > 0 || e.behind > 0 { parts.append((e.ahead > 0 ? "↑\(e.ahead)" : "") + (e.ahead > 0 && e.behind > 0 ? " " : "") + (e.behind > 0 ? "↓\(e.behind)" : "")) }
            if !kind.isEmpty { parts.append(kind) }
            if !e.subject.isEmpty { parts.append(e.subject + (e.timestamp > 0 ? " · \(BranchAge.short(e.timestamp))" : "")) }
            sub = parts.joined(separator: "   ")
            showsStar = true
            star.isHidden = !(fav || selected)
            star.image = NSImage(systemSymbolName: fav ? "star.fill" : "star", accessibilityDescription: "Favorite")
            star.contentTintColor = fav ? .systemYellow : Theme.gutter
        case .tag(let t):
            text = t; symbol = "tag"; sub = "tag"
        case .back(let t):
            text = t; symbol = "chevron.left"; bold = true; tint = .controlAccentColor
        case .text(let t):
            text = t; size = 12; titleColor = Theme.gutter; symbol = ""
        }
        icon.image = symbol.isEmpty ? nil : NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.contentTintColor = tint
        let font = NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        let s = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: titleColor])
        if !matches.isEmpty {
            let n = (text as NSString).length
            for i in matches where i < n {
                s.addAttributes([.font: NSFont.systemFont(ofSize: size, weight: .bold), .foregroundColor: NSColor.controlAccentColor], range: NSRange(location: i, length: 1))
            }
        }
        title.attributedStringValue = s
        detail.stringValue = sub
        detail.textColor = Theme.gutter
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let h = bounds.height, pad: CGFloat = 14
        let x0 = pad + indent
        icon.frame = NSRect(x: x0, y: (h - 14) / 2, width: 16, height: 14)
        let tx = x0 + 22
        let right = bounds.width - pad - (showsStar ? 22 : 0)
        star.frame = NSRect(x: bounds.width - pad - 16, y: (h - 14) / 2, width: 16, height: 14)
        let avail = right - tx, gap: CGFloat = 12
        let tNat = ceil(title.attributedStringValue.size().width) + 6
        let dNat = detail.stringValue.isEmpty ? 0 : ceil(detail.attributedStringValue.size().width) + 8
        var tw = min(tNat, avail)
        var dw = max(0, min(dNat, avail - tw - gap))
        if dNat > 0 && dw < avail * 0.35 { dw = min(dNat, avail * 0.35); tw = avail - dw - gap }
        title.frame = NSRect(x: tx, y: (h - 18) / 2, width: tw, height: 18)
        detail.frame = NSRect(x: right - dw, y: (h - 16) / 2, width: dw, height: 16)
    }
}

/// PhpStorm-style branch popup: search field, top actions, Recent / Local / Remote sections, and a per-branch action page (→).
final class BranchPopup: NSObject, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private static var current: BranchPopup?
    private static var collapsedMemory: Set<String> = []     // survives reopening within the session

    static func present(over window: NSWindow, controller: BranchController, anchor: NSView?) {
        dismiss()
        let p = BranchPopup(parent: window, controller: controller, anchor: anchor)
        current = p
        p.show()
    }
    static func dismiss() { current?.close(refocus: true) }
    static var isShown: Bool { current != nil }

    // Test / verification hooks.
    static func snapshot(to path: String) {
        guard let v = current?.panel.contentView else { return }
        Verification.render(v, to: path)
    }
    static func type(_ q: String) { current?.field.stringValue = q; current?.rebuild(keepSelection: false) }
    static var shownTitles: [String] { current?.rows.map(\.title) ?? [] }
    static func pressRight() { current?.openActionsForSelection() }
    static func pressLeft() { current?.goBack() }
    static func selectTitle(_ t: String) { if let c = current, let i = c.rows.firstIndex(where: { $0.title == t }) { c.table.selectRowIndexes([i], byExtendingSelection: false) } }
    static func pressEnter() { current?.activateSelected() }
    static func setList(_ l: BranchList) { current?.apply(list: l) }
    static var statusText: String { current?.status.stringValue ?? "" }

    private static let rowH: CGFloat = 26, headerH: CGFloat = 24, fieldH: CGFloat = 48, statusH: CGFloat = 26, maxRowsHeight: CGFloat = 26 * 14

    private weak var parent: NSWindow?
    private weak var controller: BranchController?
    private weak var anchor: NSView?
    private var list = BranchList()
    private var loaded = false
    private var rows: [Row] = []
    private var matchSets: [Set<Int>] = []
    private var mode: Mode = .main
    private var savedQuery = ""
    private var favorites: Set<String> = []
    private var observers: [NSObjectProtocol] = []
    private var closed = false
    private var fetching = false
    private var errorText: String?

    private enum Mode { case main; case actions(BranchEntry) }

    private let panel: BranchPanel
    private let root = NSView()
    private let field = NSTextField()
    private let divider = NSView()
    private let table = BranchTable()
    private let scroll = NSScrollView()
    private let statusDivider = NSView()
    private let status = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()

    private init(parent: NSWindow, controller: BranchController, anchor: NSView?) {
        self.parent = parent
        self.controller = controller
        self.anchor = anchor
        panel = BranchPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.contentView = root
        root.wantsLayer = true
        root.layer?.cornerRadius = 10
        root.layer?.masksToBounds = true
        root.layer?.borderWidth = 0.5

        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 17)
        field.delegate = self
        field.cell?.isScrollable = true
        field.cell?.usesSingleLineMode = true

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
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsetsZero

        status.font = .systemFont(ofSize: 11)
        status.lineBreakMode = .byTruncatingTail
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        for d in [divider, statusDivider] { d.wantsLayer = true }
        for v in [field, divider, scroll, statusDivider, status, spinner] { root.addSubview(v) }
        panel.initialFirstResponder = field
        restyle()

        observers.append(NotificationCenter.default.addObserver(forName: Theme.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.restyle(); self?.table.reloadData()
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            self?.close(refocus: false)
        })
    }

    private func restyle() {
        root.layer?.backgroundColor = Theme.background.cgColor
        root.layer?.borderColor = Theme.gutter.withAlphaComponent(0.35).cgColor
        divider.layer?.backgroundColor = Theme.gutter.withAlphaComponent(0.3).cgColor
        statusDivider.layer?.backgroundColor = Theme.gutter.withAlphaComponent(0.2).cgColor
        field.textColor = Theme.foreground
        updatePlaceholder()
        updateStatus()
    }

    private func updatePlaceholder() {
        var text = "Search branches, tags and actions"
        if case .actions(let e) = mode { text = "Actions for \(e.name)" }
        field.placeholderAttributedString = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 17), .foregroundColor: Theme.gutter])
    }

    private func updateStatus() {
        if let errorText {
            status.stringValue = errorText
            status.textColor = .systemRed
        } else if fetching {
            status.stringValue = "Fetching remotes…"
            status.textColor = Theme.gutter
        } else if !loaded {
            status.stringValue = "Loading branches…"
            status.textColor = Theme.gutter
        } else {
            switch mode {
            case .main: status.stringValue = "↑↓ navigate   ⏎ checkout   → actions   ⎋ close"
            case .actions: status.stringValue = "↑↓ navigate   ⏎ run   ← back   ⎋ close"
            }
            status.textColor = Theme.gutter
        }
        if fetching || !loaded { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        status.toolTip = errorText
    }

    // MARK: show / close

    private func show() {
        guard let parent, let controller else { return }
        favorites = controller.favorites()
        rebuild(keepSelection: false)
        layoutPanel()
        parent.addChildWindow(panel, ordered: .above)
        if !AppEnv.headless { panel.makeKeyAndOrderFront(nil) }
        panel.makeFirstResponder(field)
        controller.loadBranchList { [weak self] result in
            guard let self, !self.closed else { return }
            switch result {
            case .success(let l): self.apply(list: l)
            case .failure(let e): self.errorText = (e as? GitError)?.message ?? "\(e)"; self.loaded = true; self.updateStatus()
            }
            self.startFetch()
        }
    }

    func apply(list l: BranchList) {
        list = l
        loaded = true
        favorites = controller?.favorites() ?? []
        updateStatus()
        rebuild(keepSelection: true)
    }

    private func startFetch() {
        guard let controller, !closed else { return }
        fetching = true
        updateStatus()
        controller.backgroundFetch { [weak self] fetched, error in
            guard let self, !self.closed else { return }
            self.fetching = false
            if let error { self.errorText = "Fetch failed: " + (error.split(separator: "\n").first.map(String.init) ?? error) }
            self.updateStatus()
            if fetched, error == nil {
                controller.loadBranchList { [weak self] result in
                    if case .success(let l) = result, let self, !self.closed { self.apply(list: l) }
                }
            }
        }
    }

    private func close(refocus: Bool) {
        guard !closed else { return }
        closed = true
        if Self.current === self { Self.current = nil }
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        let parent = self.parent
        parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        if (refocus || parent?.isKeyWindow == false), !AppEnv.headless { parent?.makeKey() }
        field.delegate = nil
        table.dataSource = nil
        table.delegate = nil
        rows = []
    }

    // MARK: rows

    private var query: String { field.stringValue.trimmingCharacters(in: .whitespaces) }

    private func topActions() -> [Row] {
        [.action(id: .newBranch, title: "New Branch…", symbol: "plus", enabled: true, detail: ""),
         .action(id: .checkoutRevision, title: "Checkout Tag or Revision…", symbol: "tag", enabled: true, detail: ""),
         .action(id: .fetchUpdate, title: "Fetch / Update Project", symbol: "arrow.triangle.2.circlepath", enabled: true, detail: "")]
    }

    private func entry(_ e: BranchEntry, indent: Int, display: String, kind: String = "") -> Row {
        .branch(e, indent: indent, display: display, favorite: favorites.contains(e.name), kind: kind)
    }

    private func actionRows(for e: BranchEntry) -> [Row] {
        var out: [Row] = [.back(e.name)]
        let cur = e.isCurrent
        let curName = list.detached ? "HEAD" : list.current
        func a(_ id: BranchAction, _ t: String, _ s: String, _ on: Bool = true, _ d: String = "") {
            out.append(.action(id: id, title: t, symbol: s, enabled: on, detail: d))
        }
        a(.checkout, "Checkout", "arrow.right.circle", !cur)
        a(.newFrom, "New Branch from Selected…", "plus")
        a(.checkoutAndRebase, "Checkout and Rebase onto Current", "arrow.triangle.merge", !cur && !e.isRemote, e.isRemote ? "local branches only" : "")
        a(.rebaseOnto, "Rebase Current onto Selected", "arrow.up.arrow.down", !cur, curName.isEmpty ? "" : "\(curName) onto \(e.name)")
        a(.merge, "Merge Selected into Current", "arrow.triangle.merge", !cur, curName.isEmpty ? "" : "\(e.name) into \(curName)")
        a(.compare, "Compare with Current", "arrow.left.arrow.right", !cur)
        let canPull = e.isRemote || e.upstream != nil
        a(.pullMerge, cur ? "Pull (Merge)" : "Pull into Current using Merge", "arrow.down.circle", canPull, canPull ? "" : "no upstream")
        a(.pullRebase, cur ? "Pull (Rebase)" : "Pull into Current using Rebase", "arrow.down.circle.dotted", canPull, canPull ? "" : "no upstream")
        if !e.isRemote {
            a(.push, e.upstream == nil ? "Push… (set upstream)" : "Push", "arrow.up.circle", true, e.upstream ?? "")
            a(.rename, "Rename…", "pencil")
            a(.delete, "Delete…", "trash", !cur, cur ? "current branch" : "")
        } else {
            a(.deleteRemote, "Delete Remote Branch…", "trash")
        }
        a(.favorite, favorites.contains(e.name) ? "Remove from Favorites" : "Add to Favorites", favorites.contains(e.name) ? "star.slash" : "star")
        return out
    }

    private func groupRows(_ entries: [BranchEntry], keyPrefix: String, indent: Int, display: (BranchEntry) -> String) -> [Row] {
        var folders: [String: [BranchEntry]] = [:]
        var plain: [BranchEntry] = []
        for e in entries {
            let d = display(e)
            if let slash = d.firstIndex(of: "/") { folders[String(d[..<slash]), default: []].append(e) } else { plain.append(e) }
        }
        var out: [Row] = []
        for name in folders.keys.sorted() {
            let items = folders[name]!
            let key = keyPrefix + "/" + name
            let hasCurrent = items.contains { $0.isCurrent }
            let collapsed = Self.collapsedMemory.contains(key) || (!Self.expandedMemory.contains(key) && !hasCurrent && keyPrefix.hasPrefix("remote"))
            out.append(.header(title: name + "/", key: key, indent: indent, collapsed: collapsed, count: items.count))
            if !collapsed {
                for e in items.sorted(by: { display($0) < display($1) }) {
                    out.append(entry(e, indent: indent + 1, display: String(display(e).dropFirst(name.count + 1))))
                }
            }
        }
        for e in plain.sorted(by: { $0.isCurrent != $1.isCurrent ? $0.isCurrent : display($0) < display($1) }) {
            out.append(entry(e, indent: indent, display: display(e)))
        }
        return out
    }
    private static var expandedMemory: Set<String> = []

    private func buildMain() -> ([Row], [Set<Int>]) {
        let q = query
        var out: [Row] = []
        var matches: [Set<Int>] = []
        if q.isEmpty {
            out += topActions()
            if !loaded { out.append(.text("Loading…")) }
            let favs = (list.local + list.remote).filter { favorites.contains($0.name) }
            if !favs.isEmpty {
                out.append(.header(title: "Favorites", key: "fav", indent: 0, collapsed: nil, count: favs.count))
                out += favs.map { entry($0, indent: 0, display: $0.name) }
            }
            let recents = list.recent.compactMap { n in list.local.first { $0.name == n } }
            if !recents.isEmpty {
                out.append(.header(title: "Recent", key: "recent", indent: 0, collapsed: nil, count: recents.count))
                out += recents.map { entry($0, indent: 0, display: $0.name) }
            }
            if !list.local.isEmpty || loaded {
                let collapsed = Self.collapsedMemory.contains("local")
                out.append(.header(title: "Local", key: "local", indent: 0, collapsed: collapsed, count: list.local.count))
                if !collapsed { out += groupRows(list.local, keyPrefix: "local", indent: 0) { $0.name } }
            }
            if !list.remote.isEmpty {
                let collapsed = Self.collapsedMemory.contains("remote")
                out.append(.header(title: "Remote", key: "remote", indent: 0, collapsed: collapsed, count: list.remote.count))
                if !collapsed {
                    for r in list.remotes.isEmpty ? Array(Set(list.remote.compactMap(\.remote))).sorted() : list.remotes {
                        let items = list.remote.filter { $0.remote == r }
                        guard !items.isEmpty else { continue }
                        let key = "remote:" + r
                        let rc = Self.collapsedMemory.contains(key)
                        out.append(.header(title: r, key: key, indent: 1, collapsed: rc, count: items.count))
                        if !rc { out += groupRows(items, keyPrefix: "remote:" + r, indent: 2) { $0.shortName } }
                    }
                }
            }
            matches = Array(repeating: [], count: out.count)
            return (out, matches)
        }
        // search: flat fuzzy results over actions, local, remote and tags
        let chars = Array(q.lowercased().filter { !$0.isWhitespace })
        var scored: [(Int, Row)] = []
        for r in topActions() { if let s = Fuzzy.score(chars, in: r.title) { scored.append((s - 5, r)) } }
        for e in list.local { if let s = Fuzzy.score(chars, in: e.name) { scored.append((s + 4, entry(e, indent: 0, display: e.name, kind: "local"))) } }
        for e in list.remote { if let s = Fuzzy.score(chars, in: e.name) { scored.append((s, entry(e, indent: 0, display: e.name, kind: "remote"))) } }
        for t in list.tags { if let s = Fuzzy.score(chars, in: t) { scored.append((s - 2, .tag(t))) } }
        scored.sort { $0.0 > $1.0 }
        out = scored.prefix(100).map(\.1)
        matches = out.map { Self.matchIndices(chars, in: $0.title) }
        if out.isEmpty {
            if resolvesAsRevision(q) { out.append(.action(id: .checkoutRevision, title: "Checkout “\(q)”", symbol: "tag", enabled: true, detail: "revision")); matches = [[]] }
            else { out.append(.text("No matches")); matches = [[]] }
        }
        return (out, matches)
    }

    private func resolvesAsRevision(_ q: String) -> Bool { q.count >= 6 && q.allSatisfy { $0.isHexDigit } }

    private static func matchIndices(_ q: [Character], in title: String) -> Set<Int> {
        guard !q.isEmpty else { return [] }
        var out = Set<Int>(), qi = 0, i = 0
        for ch in title.utf16 {
            if qi < q.count, let u = Unicode.Scalar(ch), Character(u).lowercased() == String(q[qi]) { out.insert(i); qi += 1 }
            i += 1
        }
        return qi == q.count ? out : []
    }

    private func rebuild(keepSelection: Bool) {
        var selectedKey: String?
        if keepSelection, table.selectedRow >= 0, table.selectedRow < rows.count { selectedKey = rows[table.selectedRow].identity }
        switch mode {
        case .main:
            (rows, matchSets) = buildMain()
        case .actions(let e):
            rows = actionRows(for: e)
            matchSets = Array(repeating: [], count: rows.count)
        }
        table.reloadData()
        layoutPanel()
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
        var target = rows.firstIndex(where: { $0.selectable }) ?? 0
        if let selectedKey, let i = rows.firstIndex(where: { $0.identity == selectedKey }) { target = i }
        if case .actions = mode, selectedKey == nil { target = rows.firstIndex(where: { if case .action(_, _, _, let on, _) = $0 { return on }; return false }) ?? target }
        select(target)
        updateStatus()
    }

    // MARK: layout

    private func rowHeight(_ r: Row) -> CGFloat { if case .header = r { return Self.headerH }; return Self.rowH }

    private func layoutPanel() {
        guard let parent else { return }
        let w: CGFloat = min(600, parent.frame.width - 40)
        let contentH = min(rows.reduce(CGFloat(0)) { $0 + rowHeight($1) }, Self.maxRowsHeight)
        let listH = max(contentH, 40) + 8
        let h = Self.fieldH + 1 + listH + 1 + Self.statusH
        var origin = NSPoint(x: parent.frame.midX - w / 2, y: parent.frame.maxY - 90 - h)
        if let anchor, anchor.window != nil, !anchor.isHidden {
            let r = anchor.convert(anchor.bounds, to: nil)
            let s = parent.convertToScreen(r)
            origin = NSPoint(x: max(parent.frame.minX + 10, s.minX - 8), y: s.minY - 6 - h)
            if origin.x + w > parent.frame.maxX - 10 { origin.x = parent.frame.maxX - 10 - w }
        }
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: w, height: h)), display: true)
        root.frame = NSRect(x: 0, y: 0, width: w, height: h)
        status.frame = NSRect(x: 16, y: 5, width: w - 32 - 24, height: 16)
        spinner.frame = NSRect(x: w - 16 - 14, y: 6, width: 14, height: 14)
        statusDivider.frame = NSRect(x: 0, y: Self.statusH, width: w, height: 1)
        scroll.frame = NSRect(x: 0, y: Self.statusH + 1 + 4, width: w, height: listH - 8)
        divider.frame = NSRect(x: 0, y: h - Self.fieldH - 1, width: w, height: 1)
        field.frame = NSRect(x: 18, y: h - Self.fieldH + 10, width: w - 36, height: 28)
        table.tableColumns[0].width = w
        table.setFrameSize(NSSize(width: w, height: table.frame.height))
        root.layoutSubtreeIfNeeded()
    }

    // MARK: selection / actions

    private func select(_ row: Int) {
        guard !rows.isEmpty else { return }
        let r = min(max(row, 0), rows.count - 1)
        table.selectRowIndexes([r], byExtendingSelection: false)
        table.scrollRowToVisible(r)
        for i in 0..<rows.count { (table.view(atColumn: 0, row: i, makeIfNecessary: false) as? BranchRowCell).map { $0.star.isHidden = !starVisible(i) } }
    }

    private func starVisible(_ i: Int) -> Bool {
        guard case .branch(_, _, _, let fav, _) = rows[i] else { return true }
        return fav || i == table.selectedRow
    }

    private func move(_ delta: Int) {
        var i = table.selectedRow + delta
        while i >= 0, i < rows.count, !rows[i].selectable { i += delta }
        if i >= 0, i < rows.count { select(i) }
    }

    private func toggle(key: String) {
        let isCollapsed = rows.contains { if case .header(_, let k, _, let c, _) = $0 { return k == key && c == true }; return false }
        if isCollapsed { Self.collapsedMemory.remove(key); Self.expandedMemory.insert(key) }
        else { Self.collapsedMemory.insert(key); Self.expandedMemory.remove(key) }
        rebuild(keepSelection: true)
    }

    private func setCollapsed(_ on: Bool, key: String, current: Bool) {
        guard on != current else { return }
        toggle(key: key)
    }

    private func finish(_ block: @escaping () -> Void) {
        let parent = self.parent
        close(refocus: true)
        if AppEnv.headless { DispatchQueue.main.async { block() }; return }
        DispatchQueue.main.async {
            if parent?.isKeyWindow == false { parent?.makeKey() }
            block()
        }
    }

    fileprivate func activateSelected(row: Int? = nil) {
        let r = row ?? table.selectedRow
        guard r >= 0, r < rows.count, let controller else { return }
        switch rows[r] {
        case .header(_, let key, _, let collapsed, _):
            if collapsed != nil { toggle(key: key) }
        case .action(let id, let title, _, let enabled, _):
            guard enabled else { return }
            if case .actions(let e) = mode {
                if id == .favorite {
                    controller.toggleFavorite(e.name)
                    favorites = controller.favorites()
                    rebuild(keepSelection: true)
                    return
                }
                finish { controller.run(id, entry: e) }
            } else if id == .checkoutRevision, title.hasPrefix("Checkout “") {
                let rev = query
                finish { controller.checkoutRevision(rev) }
            } else {
                finish { controller.run(id, entry: nil) }
            }
        case .branch(let e, _, _, _, _):
            finish { controller.run(.checkout, entry: e) }
        case .tag(let t):
            finish { controller.checkoutRevision(t) }
        case .back: goBack()
        case .text: break
        }
    }

    fileprivate func openActionsForSelection() {
        let r = table.selectedRow
        guard r >= 0, r < rows.count, case .main = mode else { return }
        switch rows[r] {
        case .branch(let e, _, _, _, _):
            savedQuery = field.stringValue
            field.stringValue = ""
            mode = .actions(e)
            updatePlaceholder()
            rebuild(keepSelection: false)
        case .tag(let t):
            var e = BranchEntry(name: t, isRemote: false)
            e.hash = t
            savedQuery = field.stringValue
            field.stringValue = ""
            mode = .actions(e)
            updatePlaceholder()
            rebuild(keepSelection: false)
        case .header(_, let key, _, let collapsed, _):
            if collapsed == true { toggle(key: key) }
        default: break
        }
    }

    fileprivate func goBack() {
        guard case .actions = mode else { return }
        mode = .main
        field.stringValue = savedQuery
        updatePlaceholder()
        rebuild(keepSelection: false)
    }

    @objc private func clicked() {
        let r = table.clickedRow
        guard r >= 0, r < rows.count else { return }
        if case .branch(let e, _, _, _, _) = rows[r], let ev = NSApp.currentEvent {
            let x = table.convert(ev.locationInWindow, from: nil).x
            if x > table.bounds.width - 40 {
                controller?.toggleFavorite(e.name)
                favorites = controller?.favorites() ?? []
                rebuild(keepSelection: true)
                return
            }
        }
        activateSelected(row: r)
    }

    func controlTextDidChange(_ obj: Notification) {
        if case .actions = mode { return }
        errorText = nil
        rebuild(keepSelection: false)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.moveUp(_:)): move(-1)
        case #selector(NSResponder.moveDown(_:)): move(1)
        case #selector(NSResponder.pageUp(_:)), Selector(("movePageUp:")), #selector(NSResponder.scrollPageUp(_:)): move(-8)
        case #selector(NSResponder.pageDown(_:)), Selector(("movePageDown:")), #selector(NSResponder.scrollPageDown(_:)): move(8)
        case #selector(NSResponder.insertNewline(_:)): activateSelected()
        case #selector(NSResponder.moveRight(_:)):
            let ed = textView.selectedRange
            guard ed.length == 0, ed.location >= (textView.string as NSString).length else { return false }
            openActionsForSelection()
        case #selector(NSResponder.moveLeft(_:)):
            let r = table.selectedRow
            if case .actions = mode { goBack(); break }
            if textView.selectedRange.location == 0, r >= 0, r < rows.count, case .header(_, let key, _, let collapsed, _) = rows[r], collapsed == false {
                toggle(key: key)
            } else { return false }
        case #selector(NSResponder.cancelOperation(_:)):
            if case .actions = mode { goBack() } else { close(refocus: true) }
        default: return false
        }
        return true
    }

    // MARK: table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { rowHeight(rows[row]) }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { rows[row].selectable }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { BranchRowBackground() }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("row")
        let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? BranchRowCell) ?? { let c = BranchRowCell(frame: .zero); c.identifier = id; return c }()
        cell.configure(rows[row], matches: row < matchSets.count ? matchSets[row] : [], selected: row == tableView.selectedRow)
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        for i in 0..<rows.count { (table.view(atColumn: 0, row: i, makeIfNecessary: false) as? BranchRowCell).map { $0.star.isHidden = !starVisible(i) } }
    }
}

private extension Row {
    var title: String {
        switch self {
        case .action(_, let t, _, _, _): return t
        case .header(let t, _, _, _, _): return t
        case .branch(_, _, let d, _, _): return d
        case .tag(let t): return t
        case .back(let t): return t
        case .text(let t): return t
        }
    }
    var identity: String {
        switch self {
        case .header(_, let k, _, _, _): return "h:" + k
        case .branch(let e, _, _, _, _): return "b:" + e.name
        default: return "t:" + title
        }
    }
}
