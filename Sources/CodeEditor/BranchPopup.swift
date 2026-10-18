import AppKit

enum BranchAction: String {
    case newBranch, checkoutRevision, fetchUpdate
    case checkout, newFrom, checkoutAndRebase, checkoutAndUpdate, rebaseOnto, merge, compare, diffWorkingTree, newWorktree
    case pullMerge, pullRebase, push, rename, delete, deleteRemote, favorite
}

private final class BranchPanel: NSPanel {
    var onF2: (() -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 120, onF2?() == true { return }
        super.sendEvent(event)
    }
}

private final class BranchTable: NSTableView {
    var onHover: ((Int) -> Void)?
    override var acceptsFirstResponder: Bool { false }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseMoved(with event: NSEvent) { onHover?(row(at: convert(event.locationInWindow, from: nil))) }
    override func mouseExited(with event: NSEvent) { onHover?(-1) }
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
    case action(id: BranchAction, title: String, symbol: String?, shortcut: String)
    case separator
    case node(title: String, key: String, depth: Int, collapsed: Bool, folder: Bool, count: Int)
    case branch(BranchEntry, depth: Int, display: String, favorite: Bool)
    case tag(String, depth: Int)
    case text(String)

    var selectable: Bool { switch self { case .text, .separator: return false; default: return true } }
    var title: String {
        switch self {
        case .action(_, let t, _, _): return t
        case .node(let t, _, _, _, _, _): return t
        case .branch(_, _, let d, _): return d
        case .tag(let t, _): return t
        case .text(let t): return t
        case .separator: return "---"
        }
    }
    var identity: String {
        switch self {
        case .node(_, let k, _, _, _, _): return "n:" + k
        case .branch(let e, _, _, _): return "b:" + e.name
        default: return "t:" + title
        }
    }
}

private final class BranchRowCell: NSView {
    let icon = NSImageView()
    let disclosure = NSImageView()
    let title = NSTextField(labelWithString: "")
    let counts = NSTextField(labelWithString: "")
    let upstream = NSTextField(labelWithString: "")
    let more = NSImageView()
    var depth = 0
    var kind = 0                 // 0 other, 1 node, 2 branch/tag, 3 action
    var hasDisclosure = false, hasIcon = false, hasMore = false
    var separator = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        icon.imageScaling = .scaleProportionallyDown
        disclosure.imageScaling = .scaleProportionallyDown
        more.imageScaling = .scaleProportionallyDown
        title.lineBreakMode = .byTruncatingTail
        upstream.lineBreakMode = .byTruncatingMiddle
        upstream.alignment = .right
        upstream.font = .systemFont(ofSize: 12)
        counts.font = .systemFont(ofSize: 12)
        for v in [disclosure, icon, title, counts, upstream, more] { addSubview(v) }
    }
    required init?(coder: NSCoder) { fatalError() }

    private func symbol(_ name: String, size: CGFloat = 12, weight: NSFont.Weight = .regular) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: size, weight: weight))
    }

    func configure(_ row: Row, matches: Set<Int>, selected: Bool, hovered: Bool) {
        var text = "", up = "", countText = NSAttributedString(), size: CGFloat = 13.5, bold = false
        var titleColor = Theme.foreground
        var iconName: String?, iconTint = Theme.gutter
        separator = false; hasDisclosure = false; hasIcon = false; hasMore = false; depth = 0; kind = 0
        toolTip = nil
        switch row {
        case .separator:
            separator = true
        case .action(_, let t, let s, let shortcut):
            text = t; kind = 3; iconName = s; iconTint = Theme.foreground; up = shortcut
            if s == nil { depth = 0 }
        case .node(let t, _, let d, let collapsed, let folder, _):
            text = t; kind = 1; depth = d
            hasDisclosure = true
            disclosure.image = symbol(collapsed ? "chevron.right" : "chevron.down", size: 9, weight: .bold)
            disclosure.contentTintColor = Theme.gutter
            if folder { iconName = "folder"; iconTint = Theme.gutter }
            else { size = 13; bold = true }
        case .branch(let e, let d, let display, let fav):
            text = display; kind = 2; depth = d; hasMore = true
            let showStar = fav || ((hovered || selected) && !e.isCurrent)
            if fav || (showStar && !e.isCurrent) { iconName = fav ? "star.fill" : "star"; iconTint = fav ? .systemYellow : Theme.gutter }
            else if e.isCurrent { iconName = "tag.fill"; iconTint = .systemYellow }
            else { iconName = "arrow.triangle.branch"; iconTint = Theme.gutter }
            bold = e.isCurrent
            let c = NSMutableAttributedString()
            let blue: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.systemBlue]
            if e.behind > 0 { c.append(NSAttributedString(string: "↙ \(e.behind)", attributes: blue)) }
            if e.ahead > 0 { if c.length > 0 { c.append(NSAttributedString(string: "  ", attributes: blue)) }; c.append(NSAttributedString(string: "↗ \(e.ahead)", attributes: blue)) }
            countText = c
            up = e.isRemote ? "" : (e.upstream ?? "")
            let age = BranchAge.short(e.timestamp)
            toolTip = "\(e.hash)  \(e.subject)" + (age.isEmpty ? "" : " · \(age) ago")
        case .tag(let t, let d):
            text = t; kind = 2; depth = d; iconName = "tag"; iconTint = .systemYellow
        case .text(let t):
            text = t; size = 12; titleColor = Theme.gutter
        }
        if let iconName { icon.image = symbol(iconName, size: 12); icon.contentTintColor = iconTint; hasIcon = true }
        icon.isHidden = !hasIcon
        disclosure.isHidden = !hasDisclosure
        more.isHidden = !hasMore
        if hasMore { more.image = symbol("chevron.right", size: 10, weight: .semibold); more.contentTintColor = Theme.gutter }
        let font = NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        let para = NSMutableParagraphStyle(); para.lineBreakMode = .byTruncatingTail
        let s = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: titleColor, .paragraphStyle: para])
        if !matches.isEmpty {
            let n = (text as NSString).length
            for i in matches where i < n { s.addAttributes([.font: NSFont.systemFont(ofSize: size, weight: .bold), .foregroundColor: NSColor.controlAccentColor], range: NSRange(location: i, length: 1)) }
        }
        title.attributedStringValue = s
        counts.attributedStringValue = countText
        upstream.stringValue = up
        upstream.textColor = Theme.gutter
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        guard !separator else { return }
        let h = bounds.height, w = bounds.width
        var x = 12 + CGFloat(depth) * 16
        if kind == 1 {
            disclosure.frame = NSRect(x: x, y: (h - 12) / 2, width: 12, height: 12)
            x += 16
        } else if kind == 2 {
            x += 16
        } else if kind == 3 {
            x += hasIcon ? 4 : 26
        }
        if hasIcon { icon.frame = NSRect(x: x, y: (h - 15) / 2, width: 16, height: 15); x += 22 }
        let rightEdge = w - (hasMore ? 34 : 14)
        if hasMore { more.frame = NSRect(x: w - 26, y: (h - 12) / 2, width: 10, height: 12) }
        let avail = max(20, rightEdge - x)
        let gap: CGFloat = 8
        let nW = ceil(title.attributedStringValue.size().width) + 6
        let cW = counts.attributedStringValue.length > 0 ? ceil(counts.attributedStringValue.size().width) + 4 : 0
        let uW = upstream.stringValue.isEmpty ? 0 : ceil(upstream.attributedStringValue.size().width) + 6
        var tw = nW, uw = uW
        if nW + cW + uW + (cW > 0 ? gap : 0) + (uW > 0 ? gap : 0) > avail {
            uw = uW > 0 ? max(min(uW, avail * 0.3), min(uW, avail - nW - cW - 2 * gap)) : 0
            tw = max(30, avail - uw - cW - (cW > 0 ? gap : 0) - (uw > 0 ? gap : 0))
            tw = min(tw, nW)
        }
        title.frame = NSRect(x: x, y: (h - 18) / 2, width: tw, height: 18)
        var cx = x + tw + gap
        counts.frame = NSRect(x: cx, y: (h - 16) / 2, width: cW, height: 16)
        cx += cW
        if kind == 3 {
            upstream.frame = NSRect(x: rightEdge - uw, y: (h - 16) / 2, width: uw, height: 16)
        } else {
            upstream.frame = NSRect(x: rightEdge - uw, y: (h - 16) / 2, width: uw, height: 16)
        }
        counts.isHidden = cW == 0
    }

    override func draw(_ dirtyRect: NSRect) {
        guard separator else { return }
        Theme.gutter.withAlphaComponent(0.3).setFill()
        NSRect(x: 10, y: bounds.midY, width: bounds.width - 20, height: 1).fill()
    }
}

/// PhpStorm-style branch popup: search field with tools, New Branch / Checkout Tag actions, a Recent / Local / Remote tree
/// with prefix folders, and a floating per-branch actions menu (→ or the › chevron).
final class BranchPopup: NSObject, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private static var current: BranchPopup?
    static var collapse = BranchCollapseState()
    static var groupByPrefix = true
    static var showTags = false

    static func present(over window: NSWindow, controller: BranchController, anchor: NSView?) {
        dismiss()
        let p = BranchPopup(parent: window, controller: controller, anchor: anchor)
        current = p
        p.show()
    }
    static func dismiss() { current?.close(refocus: true) }
    static var isShown: Bool { current != nil }

    // Test / verification hooks.
    static func type(_ q: String) { current?.field.stringValue = q; current?.rebuild(keepSelection: false) }
    static var shownTitles: [String] { current?.rows.map(\.title) ?? [] }
    static var selectedTitle: String { current.map { $0.table.selectedRow >= 0 && $0.table.selectedRow < $0.rows.count ? $0.rows[$0.table.selectedRow].title : "" } ?? "" }
    static var menuTitles: [String] { current?.menu?.allTitles ?? [] }
    static var menuOpen: Bool { current?.menu != nil }
    static func pressRight() { current?.handle(.right) }
    static func pressLeft() { current?.handle(.left) }
    static func pressUp() { current?.handle(.up) }
    static func pressDown() { current?.handle(.down) }
    static func pressEscape() { current?.handle(.escape) }
    static func pressEnter() { current?.handle(.enter) }
    static func pressDelete() { current?.handle(.delete) }
    static func pressF2() { current?.handle(.rename) }
    static func selectTitle(_ t: String) { if let c = current, let i = c.rows.firstIndex(where: { $0.title == t }) { c.table.selectRowIndexes([i], byExtendingSelection: false) } }
    static func setList(_ l: BranchList) { current?.apply(list: l) }
    static var statusText: String { current?.status.stringValue ?? "" }
    static func pressToggleAll() { current?.toggleAll() }

    /// Renders the popup and any open actions menu side by side (as on screen) into one PNG.
    static func snapshot(to path: String) { current?.composite(to: path) }

    static var maxHeight: CGFloat = 420
    private static let rowH: CGFloat = 26, headerH: CGFloat = 56, statusH: CGFloat = 26, width: CGFloat = 500

    private enum Key { case up, down, left, right, enter, escape, delete, rename }

    private weak var parent: NSWindow?
    private weak var controller: BranchController?
    private weak var anchor: NSView?
    private var list = BranchList()
    private var loaded = false
    private var rows: [Row] = []
    private var matchSets: [Set<Int>] = []
    private var favorites: Set<String> = []
    private var observers: [NSObjectProtocol] = []
    private var closed = false
    private var fetching = false
    private var errorText: String?
    private var hoverRow = -1
    private var menu: BranchActionsMenu?
    private var menuRow = -1

    private let panel: BranchPanel
    private let root = NSView()
    private let box = NSView()
    private let magnifier = NSImageView()
    private let field = NSTextField()
    private let toggleAllButton = NSButton()
    private let gearButton = NSButton()
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
        panel = BranchPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.contentView = root
        panel.onF2 = { [weak self] in guard let self, self.menu != nil else { return false }; self.handle(.rename); return true }
        root.wantsLayer = true
        root.layer?.cornerRadius = 10
        root.layer?.masksToBounds = true
        root.layer?.borderWidth = 0.5

        box.wantsLayer = true
        box.layer?.cornerRadius = 8
        box.layer?.borderWidth = 1
        magnifier.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        magnifier.imageScaling = .scaleProportionallyDown
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 14)
        field.delegate = self
        field.cell?.isScrollable = true
        field.cell?.usesSingleLineMode = true
        for b in [toggleAllButton, gearButton] {
            b.isBordered = false
            b.imagePosition = .imageOnly
            b.imageScaling = .scaleProportionallyDown
            b.target = self
        }
        toggleAllButton.action = #selector(toggleAllTapped)
        toggleAllButton.toolTip = "Collapse / expand all"
        gearButton.action = #selector(gearTapped)
        gearButton.toolTip = "Settings"
        gearButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")?.withSymbolConfiguration(.init(pointSize: 14, weight: .regular))

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
        table.onHover = { [weak self] r in self?.setHover(r) }
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
        for v in [magnifier, field] { box.addSubview(v) }
        for v in [box, toggleAllButton, gearButton, divider, scroll, statusDivider, status, spinner] { root.addSubview(v) }
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
        box.layer?.backgroundColor = (Theme.isDark ? NSColor.white.withAlphaComponent(0.06) : NSColor.black.withAlphaComponent(0.03)).cgColor
        box.layer?.borderColor = Theme.gutter.withAlphaComponent(0.45).cgColor
        divider.layer?.backgroundColor = Theme.gutter.withAlphaComponent(0.3).cgColor
        statusDivider.layer?.backgroundColor = Theme.gutter.withAlphaComponent(0.2).cgColor
        field.textColor = Theme.foreground
        field.placeholderAttributedString = NSAttributedString(string: "Search for branches and actions", attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: Theme.gutter])
        magnifier.contentTintColor = Theme.gutter
        toggleAllButton.contentTintColor = Theme.gutter
        gearButton.contentTintColor = Theme.gutter
        updateToggleAllIcon()
        updateStatus()
    }

    private func updateToggleAllIcon() {
        let allCollapsed = !rows.contains { if case .node(_, _, _, let c, _, _) = $0 { return !c }; return false }
        toggleAllButton.image = NSImage(systemSymbolName: allCollapsed ? "chevron.down.2" : "chevron.up.2", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
    }

    private func updateStatus() {
        if let errorText {
            status.stringValue = errorText; status.textColor = .systemRed
        } else if fetching {
            status.stringValue = "Fetching remotes…"; status.textColor = Theme.gutter
        } else if !loaded {
            status.stringValue = "Loading branches…"; status.textColor = Theme.gutter
        } else if table.selectedRow >= 0, table.selectedRow < rows.count, case .branch(let e, _, _, _) = rows[table.selectedRow] {
            let age = BranchAge.short(e.timestamp)
            status.stringValue = "\(e.hash)  \(e.subject)" + (age.isEmpty ? "" : " · \(age) ago")
            status.textColor = Theme.gutter
        } else {
            status.stringValue = "↑↓ navigate   ⏎ select   → actions   ⎋ close"; status.textColor = Theme.gutter
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
        closeMenu()
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

    static func menuShortcut(_ title: String) -> String {
        func find(_ m: NSMenu) -> NSMenuItem? {
            for i in m.items { if i.title == title { return i }; if let s = i.submenu, let h = find(s) { return h } }
            return nil
        }
        return NSApp.mainMenu.flatMap(find).map(MainMenu.shortcutText(for:)) ?? ""
    }

    private func topActions() -> [Row] {
        [.action(id: .newBranch, title: "New Branch…", symbol: "plus", shortcut: Self.menuShortcut("New Branch…")),
         .action(id: .checkoutRevision, title: "Checkout Tag or Revision…", symbol: nil, shortcut: "")]
    }

    private func buildMain() -> ([Row], [Set<Int>]) {
        let q = query
        var out: [Row] = []
        var matches: [Set<Int>] = []
        if q.isEmpty {
            out += topActions()
            out.append(.separator)
            if !loaded { out.append(.text("Loading…")) }
            var keys: [String] = []
            for r in BranchTree.flatten(list, favorites: favorites, groupByPrefix: Self.groupByPrefix, showTags: Self.showTags, state: Self.collapse, keys: &keys) {
                switch r.kind {
                case .node(let folder, let collapsed, let count): out.append(.node(title: r.title, key: r.key, depth: r.depth, collapsed: collapsed, folder: folder, count: count))
                case .branch(let e): out.append(.branch(e, depth: r.depth, display: r.title, favorite: favorites.contains(e.name)))
                case .tag: out.append(.tag(r.title, depth: r.depth))
                }
            }
            return (out, Array(repeating: [], count: out.count))
        }
        let chars = Array(q.lowercased().filter { !$0.isWhitespace })
        var scored: [(Int, Row)] = []
        for r in topActions() { if let s = Fuzzy.score(chars, in: r.title) { scored.append((s - 5, r)) } }
        for e in list.local { if let s = Fuzzy.score(chars, in: e.name) { scored.append((s + 4, .branch(e, depth: 0, display: e.name, favorite: favorites.contains(e.name)))) } }
        for e in list.remote { if let s = Fuzzy.score(chars, in: e.name) { scored.append((s, .branch(e, depth: 0, display: e.name, favorite: favorites.contains(e.name)))) } }
        for t in list.tags { if let s = Fuzzy.score(chars, in: t) { scored.append((s - 2, .tag(t, depth: 0))) } }
        scored.sort { $0.0 > $1.0 }
        out = scored.prefix(100).map(\.1)
        matches = out.map { Self.matchIndices(chars, in: $0.title) }
        if out.isEmpty {
            if q.count >= 6, q.allSatisfy({ $0.isHexDigit }) { out.append(.action(id: .checkoutRevision, title: "Checkout “\(q)”", symbol: "tag", shortcut: "")) }
            else { out.append(.text("No matches")) }
            matches = [[]]
        }
        return (out, matches)
    }

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
        (rows, matchSets) = buildMain()
        hoverRow = -1
        table.reloadData()
        layoutPanel()
        if !keepSelection { scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView) }
        var target = rows.firstIndex(where: { $0.selectable }) ?? 0
        if let selectedKey, let i = rows.firstIndex(where: { $0.identity == selectedKey }) { target = i }
        select(target)
        updateToggleAllIcon()
        updateStatus()
    }

    // MARK: layout

    private func rowHeight(_ r: Row) -> CGFloat { if case .separator = r { return 9 }; return Self.rowH }

    private func layoutPanel() {
        guard let parent else { return }
        let w: CGFloat = min(Self.width, parent.frame.width - 40)
        let maxList = Self.maxHeight - Self.headerH - 1 - Self.statusH - 1
        let contentH = rows.reduce(CGFloat(0)) { $0 + rowHeight($1) }
        let listH = min(max(contentH, 40) + 8, maxList)
        let h = Self.headerH + 1 + listH + 1 + Self.statusH
        var origin = NSPoint(x: parent.frame.midX - w / 2, y: parent.frame.maxY - 90 - h)
        if let anchor, anchor.window != nil, !anchor.isHidden {
            let s = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
            origin = NSPoint(x: max(parent.frame.minX + 10, s.minX - 8), y: s.minY - 6 - h)
            if origin.x + w > parent.frame.maxX - 10 { origin.x = parent.frame.maxX - 10 - w }
        }
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: w, height: h)), display: true)
        root.frame = NSRect(x: 0, y: 0, width: w, height: h)
        status.frame = NSRect(x: 16, y: 5, width: w - 32 - 24, height: 16)
        spinner.frame = NSRect(x: w - 16 - 14, y: 6, width: 14, height: 14)
        statusDivider.frame = NSRect(x: 0, y: Self.statusH, width: w, height: 1)
        scroll.frame = NSRect(x: 0, y: Self.statusH + 1 + 4, width: w, height: listH - 8)
        divider.frame = NSRect(x: 0, y: h - Self.headerH - 1, width: w, height: 1)
        let by = h - Self.headerH + 12
        toggleAllButton.frame = NSRect(x: w - 10 - 24 - 6 - 24, y: by + 4, width: 24, height: 24)
        gearButton.frame = NSRect(x: w - 10 - 24, y: by + 4, width: 24, height: 24)
        box.frame = NSRect(x: 12, y: by, width: toggleAllButton.frame.minX - 12 - 8, height: 32)
        magnifier.frame = NSRect(x: 10, y: 8, width: 16, height: 16)
        field.frame = NSRect(x: 32, y: 4, width: box.frame.width - 42, height: 24)
        table.tableColumns[0].width = w
        table.setFrameSize(NSSize(width: w, height: table.frame.height))
        root.layoutSubtreeIfNeeded()
    }

    // MARK: selection

    private func select(_ row: Int) {
        guard !rows.isEmpty else { return }
        let r = min(max(row, 0), rows.count - 1)
        table.selectRowIndexes([r], byExtendingSelection: false)
        table.scrollRowToVisible(r)
        refreshCells()
    }

    private func refreshCells() {
        for i in 0..<rows.count {
            (table.view(atColumn: 0, row: i, makeIfNecessary: false) as? BranchRowCell)?
                .configure(rows[i], matches: i < matchSets.count ? matchSets[i] : [], selected: i == table.selectedRow, hovered: i == hoverRow)
        }
    }

    private func setHover(_ r: Int) {
        guard r != hoverRow else { return }
        hoverRow = r
        refreshCells()
    }

    private func move(_ delta: Int) {
        var i = table.selectedRow + delta
        while i >= 0, i < rows.count, !rows[i].selectable { i += delta }
        if i >= 0, i < rows.count { select(i) }
    }

    private func toggleNode(key: String, collapsed: Bool) {
        BranchTree.toggle(key, currentlyCollapsed: collapsed, state: &Self.collapse)
        rebuild(keepSelection: true)
    }

    private func toggleAll() {
        let allCollapsed = !rows.contains { if case .node(_, _, _, let c, _, _) = $0 { return !c }; return false }
        Self.collapse = allCollapsed
            ? BranchTree.expandAll(list, favorites: favorites, groupByPrefix: Self.groupByPrefix, showTags: Self.showTags)
            : BranchTree.collapseAll(list, favorites: favorites, groupByPrefix: Self.groupByPrefix, showTags: Self.showTags)
        rebuild(keepSelection: false)
        select(rows.firstIndex(where: { if case .node = $0 { return true }; return false }) ?? 0)
    }

    @objc private func toggleAllTapped() { toggleAll() }

    @objc private func gearTapped() {
        let m = NSMenu()
        func add(_ title: String, _ sel: Selector, on: Bool? = nil) {
            let i = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            i.target = self
            if let on { i.state = on ? .on : .off }
            m.addItem(i)
        }
        add("Group by Prefix", #selector(gearGroup), on: Self.groupByPrefix)
        add("Show Tags", #selector(gearTags), on: Self.showTags)
        m.addItem(.separator())
        add("Fetch / Update Project", #selector(gearFetch))
        m.popUp(positioning: nil, at: NSPoint(x: 0, y: gearButton.bounds.height + 2), in: gearButton)
    }
    @objc private func gearGroup() { Self.groupByPrefix.toggle(); rebuild(keepSelection: false) }
    @objc private func gearTags() { Self.showTags.toggle(); rebuild(keepSelection: false) }
    @objc private func gearFetch() { guard let c = controller else { return }; finish { c.run(.fetchUpdate, entry: nil) } }

    private func finish(_ block: @escaping () -> Void) {
        let parent = self.parent
        close(refocus: true)
        if AppEnv.headless { DispatchQueue.main.async { block() }; return }
        DispatchQueue.main.async {
            if parent?.isKeyWindow == false { parent?.makeKey() }
            block()
        }
    }

    // MARK: keys and activation

    private func handle(_ key: Key) {
        if let m = menu {
            switch key {
            case .up: m.deepest.move(-1)
            case .down: m.deepest.move(1)
            case .right: m.deepest.openChild()
            case .enter: m.deepest.activate()
            case .left, .escape: if !m.closeDeepestChild() { closeMenu() }
            case .delete: _ = m.runKeyed("delete")
            case .rename: _ = m.runKeyed("rename")
            }
            return
        }
        let r = table.selectedRow
        let row: Row? = r >= 0 && r < rows.count ? rows[r] : nil
        switch key {
        case .up: move(-1)
        case .down: move(1)
        case .enter: activateSelected()
        case .escape: close(refocus: true)
        case .right:
            switch row {
            case .branch?, .tag?: openMenu(row: r)
            case .node(_, let k, _, let c, _, _)?: if c { toggleNode(key: k, collapsed: true) } else { move(1) }
            default: break
            }
        case .left:
            if case .node(_, let k, let d, let c, _, _)? = row {
                if !c { toggleNode(key: k, collapsed: false) } else if d > 0 { selectParent(of: r, depth: d) }
            } else if let row, query.isEmpty { var d = 0; if case .branch(_, let dd, _, _) = row { d = dd }; if case .tag(_, let dd) = row { d = dd }; selectParent(of: r, depth: d) }
        case .delete, .rename: break
        }
    }

    private func selectParent(of row: Int, depth: Int) {
        var i = row - 1
        while i >= 0 {
            if case .node(_, _, let d, _, _, _) = rows[i], d < depth { select(i); return }
            i -= 1
        }
    }

    fileprivate func activateSelected(row: Int? = nil) {
        let r = row ?? table.selectedRow
        guard r >= 0, r < rows.count, let controller else { return }
        switch rows[r] {
        case .node(_, let k, _, let c, _, _): toggleNode(key: k, collapsed: c)
        case .action(let id, let title, _, _):
            if id == .checkoutRevision, title.hasPrefix("Checkout “") { let rev = query; finish { controller.checkoutRevision(rev) } }
            else { finish { controller.run(id, entry: nil) } }
        case .branch(let e, _, _, _): finish { controller.run(.checkout, entry: e) }
        case .tag(let t, _): finish { controller.checkoutRevision(t) }
        case .separator, .text: break
        }
    }

    @objc private func clicked() {
        let r = table.clickedRow
        guard r >= 0, r < rows.count else { return }
        if case .branch(let e, let depth, _, _) = rows[r], let ev = NSApp.currentEvent {
            let x = table.convert(ev.locationInWindow, from: nil).x
            if x > table.bounds.width - 36 { select(r); openMenu(row: r); return }
            if x < 12 + CGFloat(depth) * 16 + 16 + 22 {
                controller?.toggleFavorite(e.name)
                favorites = controller?.favorites() ?? []
                rebuild(keepSelection: true)
                return
            }
        }
        closeMenu()
        activateSelected(row: r)
    }

    // MARK: actions menu

    private func closeMenu() { menu?.close(); menu = nil; menuRow = -1 }

    private func openMenu(row: Int) {
        guard row >= 0, row < rows.count, let controller, let parent else { return }
        var entry: BranchEntry
        switch rows[row] {
        case .branch(let e, _, _, _): entry = e
        case .tag(let t, _): entry = BranchEntry(name: t, isRemote: false); entry.hash = t
        default: return
        }
        let rowRect = panel.convertToScreen(table.convert(table.rect(ofRow: row), to: nil))
        closeMenu()
        menu = BranchActionsMenu(items: actionItems(for: entry, controller: controller), over: panel, anchor: rowRect)
        menuRow = row
        _ = parent
    }

    private func actionItems(for e: BranchEntry, controller c: BranchController) -> [BranchMenuItem] {
        let cur = list.detached ? "HEAD" : list.current
        let isCur = e.isCurrent
        func act(_ id: BranchAction, on entry: BranchEntry) -> () -> Void { { [weak self] in self?.finish { c.run(id, entry: entry) } } }
        func item(_ t: String, _ id: BranchAction, enabled: Bool = true, shortcut: String = "", key: String? = nil, entry: BranchEntry? = nil) -> BranchMenuItem {
            BranchMenuItem(title: t, shortcut: shortcut, enabled: enabled, key: key, run: act(id, on: entry ?? e))
        }
        let tracked = e.isRemote ? nil : e.upstream.flatMap { up in list.remote.first { $0.name == up } }
        var items: [BranchMenuItem] = [
            item("Checkout", .checkout, enabled: !isCur),
            item("New Branch from '\(e.name)'…", .newFrom),
        ]
        if !e.isRemote { items.append(item("Checkout and Rebase onto '\(cur)'", .checkoutAndRebase, enabled: !isCur)) }
        items.append(item("Checkout and Update", .checkoutAndUpdate, enabled: !isCur))
        items += [.sep,
                  item("Compare with '\(cur)'", .compare, enabled: !isCur),
                  item("Show Diff with Working Tree", .diffWorkingTree),
                  .sep,
                  item("Rebase '\(cur)' onto '\(e.name)'", .rebaseOnto, enabled: !isCur),
                  item("Merge '\(e.name)' into '\(cur)'", .merge, enabled: !isCur),
                  .sep,
                  item("New Worktree from '\(e.name)'…", .newWorktree),
                  .sep]
        let canPull = e.isRemote || e.upstream != nil
        let pullLabel = isCur ? "Pull" : "Pull into '\(cur)'"
        items.append(BranchMenuItem(title: "Update", enabled: canPull, children: [
            item("\(pullLabel) using Merge", .pullMerge, enabled: canPull),
            item("\(pullLabel) using Rebase", .pullRebase, enabled: canPull)]))
        if !e.isRemote { items.append(item("Push…", .push, shortcut: Self.menuShortcut("Push…"))) }
        if let t = tracked {
            items.append(BranchMenuItem(title: "Tracked Branch '\(t.name)'", children: [
                item("Checkout", .checkout, entry: t),
                item("Compare with '\(cur)'", .compare, enabled: !isCur, entry: t),
                item("Pull into '\(cur)' using Merge", .pullMerge, entry: t),
                item("Pull into '\(cur)' using Rebase", .pullRebase, entry: t),
                item("Merge '\(t.name)' into '\(cur)'", .merge, enabled: !isCur, entry: t)]))
        }
        items.append(.sep)
        if e.isRemote {
            items.append(item("Delete Remote Branch…", .deleteRemote, shortcut: "⌫", key: "delete"))
        } else {
            items.append(item("Rename…", .rename, shortcut: "F2", key: "rename"))
            items.append(item("Delete", .delete, enabled: !isCur, shortcut: "⌫", key: "delete"))
        }
        items.append(.sep)
        let fav = favorites.contains(e.name)
        items.append(BranchMenuItem(title: fav ? "Remove from Favorites" : "Add to Favorites", run: { [weak self] in
            guard let self else { return }
            self.controller?.toggleFavorite(e.name)
            self.favorites = self.controller?.favorites() ?? []
            self.closeMenu()
            self.rebuild(keepSelection: true)
        }))
        return items
    }

    // MARK: text field

    func controlTextDidChange(_ obj: Notification) {
        closeMenu()
        errorText = nil
        rebuild(keepSelection: false)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.moveUp(_:)): handle(.up)
        case #selector(NSResponder.moveDown(_:)): handle(.down)
        case #selector(NSResponder.pageUp(_:)), Selector(("movePageUp:")), #selector(NSResponder.scrollPageUp(_:)): if menu == nil { move(-8) }
        case #selector(NSResponder.pageDown(_:)), Selector(("movePageDown:")), #selector(NSResponder.scrollPageDown(_:)): if menu == nil { move(8) }
        case #selector(NSResponder.insertNewline(_:)): handle(.enter)
        case #selector(NSResponder.cancelOperation(_:)): handle(.escape)
        case #selector(NSResponder.deleteBackward(_:)):
            guard menu != nil else { return false }
            handle(.delete)
        case #selector(NSResponder.moveRight(_:)):
            if menu == nil { let ed = textView.selectedRange; guard ed.length == 0, ed.location >= (textView.string as NSString).length else { return false } }
            handle(.right)
        case #selector(NSResponder.moveLeft(_:)):
            if menu == nil, textView.selectedRange.location != 0 || textView.selectedRange.length != 0 { return false }
            if menu == nil, !query.isEmpty { return false }
            handle(.left)
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
        cell.configure(rows[row], matches: row < matchSets.count ? matchSets[row] : [], selected: row == tableView.selectedRow, hovered: row == hoverRow)
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        if menu != nil, table.selectedRow != menuRow { closeMenu() }
        refreshCells()
        updateStatus()
    }

    // MARK: snapshot

    private func composite(to path: String) {
        root.layoutSubtreeIfNeeded()
        func image(of v: NSView) -> NSImage? {
            guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return nil }
            v.cacheDisplay(in: v.bounds, to: rep)
            let img = NSImage(size: v.bounds.size); img.addRepresentation(rep); return img
        }
        var parts: [(NSImage, NSRect)] = []
        if let i = image(of: root) { parts.append((i, panel.frame)) }
        var m = menu
        while let cur = m { if let i = cur.renderImage() { parts.append((i, cur.panelFrame)) }; m = cur.child }
        guard !parts.isEmpty else { return }
        let union = parts.map(\.1).reduce(parts[0].1) { $0.union($1) }.insetBy(dx: -12, dy: -12)
        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(union.width * scale), pixelsHigh: Int(union.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0), let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.cgContext.scaleBy(x: scale, y: scale)
        (Theme.isDark ? NSColor(white: 0.10, alpha: 1) : NSColor(white: 0.86, alpha: 1)).setFill()
        NSRect(origin: .zero, size: union.size).fill()
        for (img, frame) in parts {
            let r = NSRect(x: frame.minX - union.minX, y: frame.minY - union.minY, width: frame.width, height: frame.height)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10).addClip()
            img.draw(in: r)
            NSGraphicsContext.restoreGraphicsState()
        }
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
