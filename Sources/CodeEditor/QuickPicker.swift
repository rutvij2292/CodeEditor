import AppKit

private final class PickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class PickerTable: NSTableView {
    override var acceptsFirstResponder: Bool { false }
}

private final class PickerRowBackground: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.controlAccentColor.withAlphaComponent(Theme.isDark ? 0.35 : 0.22).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 1), xRadius: 6, yRadius: 6).fill()
    }
}

private final class PickerRowCell: NSView {
    let icon = NSImageView()
    let title = NSTextField(labelWithString: "")
    let detail = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        icon.imageScaling = .scaleProportionallyDown
        title.lineBreakMode = .byTruncatingTail
        detail.lineBreakMode = .byTruncatingHead
        detail.alignment = .right
        detail.font = .systemFont(ofSize: 12)
        for v in [icon, title, detail] { addSubview(v) }
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ item: PickerItem, matches: Set<Int>) {
        icon.image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil)
        icon.contentTintColor = Theme.gutter
        let base = NSFont.systemFont(ofSize: 14), bold = NSFont.systemFont(ofSize: 14, weight: .bold)
        let para = NSMutableParagraphStyle(); para.lineBreakMode = .byTruncatingTail
        let s = NSMutableAttributedString(string: item.title, attributes: [
            .font: base, .foregroundColor: Theme.foreground, .paragraphStyle: para])
        if !matches.isEmpty {
            let chars = Array(item.title.utf16)
            for i in matches where i < chars.count {
                s.addAttributes([.font: bold, .foregroundColor: NSColor.controlAccentColor], range: NSRange(location: i, length: 1))
            }
        }
        title.attributedStringValue = s
        detail.stringValue = item.detail
        detail.textColor = Theme.gutter
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let h = bounds.height, pad: CGFloat = 16
        icon.frame = NSRect(x: pad, y: (h - 16) / 2, width: 18, height: 16)
        let x0 = pad + 18 + 8, avail = bounds.width - x0 - pad, gap: CGFloat = 12
        // measured from the raw strings: a truncating label's own size() can report the already-truncated text
        let tNat = ceil(NSAttributedString(string: title.stringValue, attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .bold)]).size().width) + 8
        let dNat = detail.stringValue.isEmpty ? 0 : ceil((detail.stringValue as NSString).size(withAttributes: [.font: detail.font ?? NSFont.systemFont(ofSize: 12)]).width) + 6
        var tw = min(tNat, avail)
        var dw = max(0, min(dNat, avail - tw - gap))
        if dNat > 0 && dw < avail * 0.3 {
            dw = min(dNat, avail * 0.3)
            tw = avail - dw - gap
        }
        title.frame = NSRect(x: x0, y: (h - 18) / 2, width: tw, height: 18)
        detail.frame = NSRect(x: bounds.width - pad - dw, y: (h - 16) / 2, width: dw, height: 16)
    }
}

final class QuickPicker: NSObject, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private static var current: QuickPicker?

    static func present(over window: NSWindow, placeholder: String, items: [PickerItem],
                        preselect: Int = 0, initialQuery: String = "",
                        provider: ((String) -> [PickerItem])? = nil) {
        dismiss()
        let p = QuickPicker(parent: window, placeholder: placeholder, items: items,
                            preselect: preselect, initialQuery: initialQuery, provider: provider)
        current = p
        p.show()
    }

    /// Renders the currently presented picker's content view to a PNG (headless verification).
    static func snapshot(to path: String) {
        guard let v = current?.panel.contentView else { return }
        v.layoutSubtreeIfNeeded()
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
        v.cacheDisplay(in: v.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    static var isOpen: Bool { current != nil }

    static func dismiss() { current?.close(refocus: true) }

    /// Re-runs the provider / filter for the open picker (rows that arrive after it was shown, e.g. artisan output).
    static func reload() { current?.refilter() }

    // Test hooks (headless harness).
    static func type(_ query: String) { current?.field.stringValue = query; current?.refilter() }
    static var shownTitles: [String] { current?.shown.map(\.title) ?? [] }
    static var selectedRow: Int { current?.table.selectedRow ?? -1 }

    private static let rowHeight: CGFloat = 28, fieldHeight: CGFloat = 52, maxRows = 10, maxShown = 200
    private static let tabBarHeight: CGFloat = 44, footerHeight: CGFloat = 30

    /// Tabbed mode (Search Everywhere): All / Classes / Files / ... with an "Include non-project items" switch and a footer.
    private var tabs: [PickerTab] = []
    private var tabIndex = 0
    private var includeNonProject = false
    private var tabButtons: [NSButton] = []
    private let tabUnderline = NSView()
    private let nonProjectBox = NSButton(checkboxWithTitle: "Include non-project items", target: nil, action: nil)
    private let footerPath = NSTextField(labelWithString: "")
    private let footerHint = NSTextField(labelWithString: "")
    private var tabbed: Bool { !tabs.isEmpty }

    static func presentTabbed(over window: NSWindow, tabs: [PickerTab], placeholder: String, selectedTab: Int = 0) {
        dismiss()
        let p = QuickPicker(parent: window, placeholder: placeholder, items: [], preselect: 0, initialQuery: "", provider: nil)
        p.tabs = tabs
        p.tabIndex = min(max(selectedTab, 0), tabs.count - 1)
        p.buildTabChrome()
        current = p
        p.show()
    }

    static var tabTitles: [String] { current?.tabs.map(\.title) ?? [] }
    static var selectedTabIndex: Int { current?.tabIndex ?? -1 }
    static func selectTab(_ i: Int) { current?.switchTab(to: i) }

    private weak var parent: NSWindow?
    private var items: [PickerItem]
    private var provider: ((String) -> [PickerItem])?
    private var preselect: Int
    private var shown: [PickerItem] = []
    private var matchSets: [Set<Int>] = []
    private var query: [Character] = []
    private var observers: [NSObjectProtocol] = []
    private var closed = false

    private let panel: PickerPanel
    private let field = NSTextField()
    private let divider = NSView()
    private let table = PickerTable()
    private let scroll = NSScrollView()
    private let empty = NSTextField(labelWithString: "No matches")
    private let root = NSView()

    private init(parent: NSWindow, placeholder: String, items: [PickerItem], preselect: Int,
                 initialQuery: String, provider: ((String) -> [PickerItem])?) {
        self.parent = parent
        self.items = items
        self.preselect = preselect
        self.provider = provider
        panel = PickerPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 100),
                            styleMask: [.borderless], backing: .buffered, defer: false)
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
        field.font = .systemFont(ofSize: 20)
        field.placeholderString = placeholder
        field.stringValue = initialQuery
        field.delegate = self
        field.cell?.isScrollable = true
        field.cell?.usesSingleLineMode = true

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c"))
        table.addTableColumn(col)
        table.headerView = nil
        table.style = .plain
        table.rowHeight = Self.rowHeight
        table.intercellSpacing = .zero
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .regular
        table.allowsEmptySelection = false
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(clicked)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsetsZero

        empty.alignment = .center
        empty.font = .systemFont(ofSize: 13)
        empty.isHidden = true

        divider.wantsLayer = true
        for v in [field, divider, scroll, empty] { root.addSubview(v) }
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
        restyleTabs()
        root.layer?.backgroundColor = Theme.background.cgColor
        root.layer?.borderColor = Theme.gutter.withAlphaComponent(0.35).cgColor
        divider.layer?.backgroundColor = Theme.gutter.withAlphaComponent(0.3).cgColor
        field.textColor = Theme.foreground
        field.placeholderAttributedString = NSAttributedString(
            string: field.placeholderString ?? "",
            attributes: [.font: NSFont.systemFont(ofSize: 20), .foregroundColor: Theme.gutter])
        empty.textColor = Theme.gutter
    }

    private func show() {
        guard let parent else { return }
        refilter(initial: true)
        parent.addChildWindow(panel, ordered: .above)
        if !AppEnv.headless { panel.makeKeyAndOrderFront(nil) }
        panel.makeFirstResponder(field)
        if let ed = field.currentEditor() { ed.selectedRange = NSRange(location: ed.string.utf16.count, length: 0) }
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
        if refocus || parent?.isKeyWindow == false, !AppEnv.headless { parent?.makeKey() }
        field.delegate = nil
        table.dataSource = nil
        table.delegate = nil
        items = []; shown = []; matchSets = []; provider = nil
    }

    // MARK: filtering

    private func refilter(initial: Bool = false) {
        let text = field.stringValue
        query = Array(text.lowercased().filter { !$0.isWhitespace })
        if tabbed {
            shown = Array(tabs[tabIndex].provider(text, includeNonProject).prefix(Self.maxShown))
        } else if let provider {
            shown = Array(provider(text).prefix(Self.maxShown))
        } else if query.isEmpty {
            shown = Array(items.prefix(Self.maxShown))
        } else {
            shown = Self.filter(items, query: query)
        }
        matchSets = shown.map { Self.matchIndices(query, in: $0.title) }
        table.reloadData()
        resize(animated: !initial)
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
        if !shown.isEmpty {
            select(initial ? min(max(preselect, 0), shown.count - 1) : 0)
        }
    }

    /// Single pass over ASCII keys (no per-item allocation); anything else falls back to Fuzzy.score.
    static func filter(_ items: [PickerItem], query: [Character]) -> [PickerItem] {
        let q = query.compactMap { $0.isASCII ? $0.asciiValue : nil }
        let asciiQuery = q.count == query.count
        var hits: [(score: Int, index: Int)] = []
        for i in items.indices {
            var s: Int?
            var done = false
            if asciiQuery {
                done = items[i].key.utf8.withContiguousStorageIfAvailable { t -> Bool in
                    for c in t where c >= 128 { return false }
                    s = asciiScore(q, t)
                    return true
                } ?? false
            }
            if !done { s = Fuzzy.score(query, in: items[i].key) }
            if let s { hits.append((s, i)) }
        }
        hits.sort { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }
        return hits.prefix(maxShown).map { items[$0.index] }
    }

    /// Mirrors Fuzzy.score for ASCII text.
    private static func asciiScore(_ q: [UInt8], _ t: UnsafeBufferPointer<UInt8>) -> Int? {
        if q.isEmpty { return 0 }
        @inline(__always) func lower(_ c: UInt8) -> UInt8 { c >= 65 && c <= 90 ? c + 32 : c }
        @inline(__always) func isSep(_ c: UInt8) -> Bool { c == 47 || c == 46 || c == 95 || c == 45 || c == 32 }
        @inline(__always) func upper(_ c: UInt8) -> Bool { c >= 65 && c <= 90 }
        var qi = 0, score = 0, prev = -2, first = -1
        for i in 0..<t.count where lower(t[i]) == q[qi] {
            var s = 1
            if i == prev + 1 { s += 5 }
            if i == 0 || isSep(t[i - 1]) { s += 8 }
            else if upper(t[i]) && !upper(t[i - 1]) { s += 6 }
            score += s
            prev = i
            if first < 0 { first = i }
            qi += 1
            if qi == q.count { break }
        }
        guard qi == q.count else { return nil }
        // contiguous substring bonus
        if t.count >= q.count {
            outer: for st in 0...(t.count - q.count) {
                for k in 0..<q.count where lower(t[st + k]) != q[k] { continue outer }
                score += 20
                break
            }
        }
        var nameStart = 0
        for i in stride(from: t.count - 1, through: 0, by: -1) where t[i] == 47 { nameStart = i + 1; break }
        if first >= nameStart { score += 25 }
        return score - t.count / 8
    }

    static func matchIndices(_ q: [Character], in title: String) -> Set<Int> {
        guard !q.isEmpty else { return [] }
        var out = Set<Int>(), qi = 0, i = 0
        for ch in title.utf16 {
            if qi < q.count, let u = Unicode.Scalar(ch), Character(u).lowercased() == String(q[qi]) {
                out.insert(i); qi += 1
            }
            i += 1
        }
        return qi == q.count ? out : []
    }

    // MARK: layout

    private func resize(animated: Bool) {
        guard let parent else { return }
        let w = min(tabbed ? 760 : 640, parent.frame.width - 40)
        let rows = min(shown.count, Self.maxRows)
        let listH = shown.isEmpty ? 44 : CGFloat(rows) * Self.rowHeight + 8
        let chrome: CGFloat = tabbed ? Self.tabBarHeight + Self.footerHeight : 0
        let h = Self.fieldHeight + 1 + listH + chrome
        let pf = parent.frame
        let frame = NSRect(x: pf.midX - w / 2, y: pf.maxY - 90 - h, width: w, height: h)
        empty.isHidden = !shown.isEmpty
        scroll.isHidden = shown.isEmpty
        let animate = animated && !AppEnv.headless && panel.isVisible && abs(panel.frame.height - h) > 1
        panel.setFrame(frame, display: true, animate: animate)
        layoutContent(width: w, height: h, listH: listH)
    }

    private func layoutContent(width w: CGFloat, height h: CGFloat, listH: CGFloat) {
        root.frame = NSRect(x: 0, y: 0, width: w, height: h)
        let top = tabbed ? Self.tabBarHeight : 0, bottom = tabbed ? Self.footerHeight : 0
        field.frame = NSRect(x: 18, y: h - top - Self.fieldHeight + 12, width: w - 36, height: 28)
        divider.frame = NSRect(x: 0, y: h - top - Self.fieldHeight - 1, width: w, height: 1)
        scroll.frame = NSRect(x: 0, y: bottom + 4, width: w, height: listH - 8)
        empty.frame = NSRect(x: 0, y: bottom + (listH - 18) / 2, width: w, height: 18)
        if tabbed { layoutTabChrome(width: w, height: h) }
        table.tableColumns[0].width = w
        table.setFrameSize(NSSize(width: w, height: table.frame.height))
        root.layoutSubtreeIfNeeded()
    }

    // MARK: tabbed chrome

    private func buildTabChrome() {
        for (i, t) in tabs.enumerated() {
            let b = NSButton(title: t.title, target: self, action: #selector(tabClicked(_:)))
            b.isBordered = false
            b.tag = i
            b.setButtonType(.momentaryChange)
            tabButtons.append(b)
            root.addSubview(b)
        }
        tabUnderline.wantsLayer = true
        nonProjectBox.target = self
        nonProjectBox.action = #selector(nonProjectToggled)
        nonProjectBox.font = .systemFont(ofSize: 13)
        footerPath.font = .systemFont(ofSize: 12)
        footerPath.lineBreakMode = .byTruncatingHead
        footerHint.font = .systemFont(ofSize: 12)
        footerHint.alignment = .right
        for v in [tabUnderline, nonProjectBox, footerPath, footerHint] { root.addSubview(v) }
        restyleTabs()
    }

    private func restyleTabs() {
        guard tabbed else { return }
        for (i, b) in tabButtons.enumerated() {
            b.attributedTitle = NSAttributedString(string: tabs[i].title, attributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: i == tabIndex ? .semibold : .regular),
                .foregroundColor: i == tabIndex ? Theme.foreground : Theme.gutter])
        }
        tabUnderline.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        nonProjectBox.attributedTitle = NSAttributedString(string: "Include non-project items", attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: Theme.foreground])
        footerPath.textColor = Theme.gutter
        footerHint.textColor = NSColor.controlAccentColor
    }

    private func layoutTabChrome(width w: CGFloat, height h: CGFloat) {
        var x: CGFloat = 16
        let y = h - Self.tabBarHeight + 8
        for (i, b) in tabButtons.enumerated() {
            b.sizeToFit()
            let bw = b.frame.width + 8
            b.frame = NSRect(x: x, y: y, width: bw, height: 26)
            if i == tabIndex { tabUnderline.frame = NSRect(x: x + 4, y: y - 3, width: bw - 8, height: 2.5) }
            x += bw + 8
        }
        nonProjectBox.sizeToFit()
        let bw = nonProjectBox.frame.width
        nonProjectBox.frame = NSRect(x: max(x + 8, w - bw - 16), y: y + 1, width: bw, height: 24)
        footerPath.frame = NSRect(x: 16, y: 6, width: w * 0.62, height: 18)
        footerHint.frame = NSRect(x: w * 0.62 + 16, y: 6, width: w - w * 0.62 - 32, height: 18)
    }

    @objc private func tabClicked(_ sender: NSButton) { switchTab(to: sender.tag) }

    @objc private func nonProjectToggled() {
        includeNonProject = nonProjectBox.state == .on
        refilter()
    }

    private func switchTab(to i: Int) {
        guard tabbed, i >= 0, i < tabs.count else { return }
        tabIndex = i
        restyleTabs()
        refilter()
        panel.makeFirstResponder(field)
    }

    private func updateFooter() {
        guard tabbed else { return }
        let r = table.selectedRow
        guard r >= 0, r < shown.count else { footerPath.stringValue = ""; footerHint.stringValue = ""; return }
        let it = shown[r]
        footerPath.stringValue = it.footer.isEmpty ? it.detail : it.footer
        footerHint.stringValue = it.runSplit != nil ? "Open In Right Split  \u{21E7}\u{21A9}" : ""
    }

    // MARK: selection and running

    private func select(_ row: Int) {
        guard !shown.isEmpty else { return }
        let r = min(max(row, 0), shown.count - 1)
        table.selectRowIndexes([r], byExtendingSelection: false)
        table.scrollRowToVisible(r)
        updateFooter()
    }

    private func runSelected(row: Int? = nil, split: Bool = false) {
        let r = row ?? table.selectedRow
        guard r >= 0, r < shown.count else { return }
        let run = split ? (shown[r].runSplit ?? shown[r].run) : shown[r].run
        let parent = self.parent
        close(refocus: true)
        if AppEnv.headless { DispatchQueue.main.async { run() }; return }
        DispatchQueue.main.async {
            if parent?.isKeyWindow == false { parent?.makeKey() }
            run()
        }
    }

    @objc private func clicked() {
        let r = table.clickedRow
        if r >= 0 { runSelected(row: r) }
    }

    func controlTextDidChange(_ obj: Notification) { refilter() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        let page = max(1, Self.maxRows - 1)
        switch sel {
        case #selector(NSResponder.moveUp(_:)): select(table.selectedRow - 1)
        case #selector(NSResponder.moveDown(_:)): select(table.selectedRow + 1)
        case #selector(NSResponder.pageUp(_:)), Selector(("movePageUp:")),
             #selector(NSResponder.scrollPageUp(_:)): select(table.selectedRow - page)
        case #selector(NSResponder.pageDown(_:)), Selector(("movePageDown:")),
             #selector(NSResponder.scrollPageDown(_:)): select(table.selectedRow + page)
        case #selector(NSResponder.insertNewline(_:)): runSelected()
        case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)): if tabbed { runSelected(split: true) } else { runSelected() }
        case #selector(NSResponder.insertTab(_:)): if tabbed { switchTab(to: (tabIndex + 1) % tabs.count) } else { return false }
        case #selector(NSResponder.insertBacktab(_:)): if tabbed { switchTab(to: (tabIndex + tabs.count - 1) % tabs.count) } else { return false }
        case #selector(NSResponder.cancelOperation(_:)): close(refocus: true)
        default: return false
        }
        return true
    }

    func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { PickerRowBackground() }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("row")
        let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? PickerRowCell) ?? {
            let c = PickerRowCell(frame: .zero); c.identifier = id; return c
        }()
        cell.configure(shown[row], matches: matchSets[row])
        return cell
    }
}
