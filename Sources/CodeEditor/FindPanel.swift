import AppKit

// Find in Files / Replace in Files panel. Host `FindPanelController.view` in the bottom tool panel.

// MARK: - Model

private final class FindFileNode {
    let url: URL
    let name: String
    let dir: String
    var matches: [FindMatchNode] = []
    init(url: URL, rel: String) {
        self.url = url
        name = url.lastPathComponent
        let d = (rel as NSString).deletingLastPathComponent
        dir = d
    }
    /// 1 = all included, 0 = none, -1 = mixed.
    var state: Int {
        let ex = matches.filter(\.excluded).count
        return ex == 0 ? 1 : ex == matches.count ? 0 : -1
    }
}

private final class FindMatchNode {
    let match: FindMatch
    var excluded = false
    unowned let file: FindFileNode
    init(_ m: FindMatch, file: FindFileNode) { match = m; self.file = file }
}

// MARK: - Views

private final class FindRowBackground: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.controlAccentColor.withAlphaComponent(Theme.isDark ? 0.35 : 0.22).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 5, yRadius: 5).fill()
    }
}

private final class FindCell: NSView {
    let check = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let icon = NSImageView()
    let primary = NSTextField(labelWithString: "")
    let secondary = NSTextField(labelWithString: "")
    let badge = NSTextField(labelWithString: "")
    var showsCheck = false
    var isFile = false
    var onToggle: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        check.controlSize = .small
        check.target = self
        check.action = #selector(toggled)
        icon.imageScaling = .scaleProportionallyDown
        primary.lineBreakMode = .byTruncatingTail
        secondary.lineBreakMode = .byTruncatingHead
        badge.alignment = .right
        for v in [check, icon, primary, secondary, badge] { addSubview(v) }
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func toggled() { onToggle?() }

    override func layout() {
        super.layout()
        let h = bounds.height
        var x: CGFloat = 4
        check.isHidden = !showsCheck
        if showsCheck { check.frame = NSRect(x: x, y: (h - 16) / 2, width: 18, height: 16); x += 20 }
        if isFile {
            icon.frame = NSRect(x: x, y: (h - 16) / 2, width: 18, height: 16); x += 24
            let bw = badge.stringValue.isEmpty ? 0 : ceil(badge.attributedStringValue.size().width) + 6
            badge.frame = NSRect(x: bounds.width - bw - 8, y: (h - 16) / 2, width: bw, height: 16)
            let avail = max(0, badge.frame.minX - x - 6)
            let pw = min(ceil(primary.attributedStringValue.size().width) + 6, avail)
            primary.frame = NSRect(x: x, y: (h - 18) / 2, width: pw, height: 18)
            secondary.frame = NSRect(x: x + pw + 4, y: (h - 16) / 2, width: max(0, avail - pw - 4), height: 16)
        } else {
            icon.isHidden = true
            secondary.frame = NSRect(x: x, y: (h - 16) / 2, width: 64, height: 16); x += 70
            badge.frame = .zero
            primary.frame = NSRect(x: x, y: (h - 18) / 2, width: max(0, bounds.width - x - 8), height: 18)
        }
    }
}

private final class FindOutlineView: NSOutlineView {
    var onOpen: (() -> Void)?
    var onSpace: (() -> Void)?
    var onEscape: (() -> Void)?
    var onUpAtTop: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: onOpen?()
        case 49: onSpace?()
        case 53: onEscape?()
        case 126 where selectedRow <= 1: onUpAtTop?()
        default: super.keyDown(with: event)
        }
    }
}

private final class FindRootView: NSView {
    var relayout: (() -> Void)?
    var onAppearance: (() -> Void)?
    override var isFlipped: Bool { true }
    override func layout() { super.layout(); relayout?() }
    override func draw(_ dirtyRect: NSRect) { Theme.background.setFill(); dirtyRect.fill() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); onAppearance?() }
}

// MARK: - Controller

final class FindPanelController: NSObject, NSSearchFieldDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
    let view: NSView
    var onClose: (() -> Void)?
    /// Optional richer open hook (gets the whole match, e.g. to select the range). Takes precedence over `openFile`.
    var openMatch: ((FindMatch) -> Void)?

    private let engine: FindEngine
    private let openFile: (URL, Int, Int) -> Void
    private let openBuffer: (URL) -> EditorTab?
    private let rootURL: URL

    // controls (internal for the headless harness)
    let queryField = NSSearchField()
    let replaceField = NSTextField()
    let maskField = NSTextField()
    private let caseButton = NSButton()
    private let wordButton = NSButton()
    private let regexButton = NSButton()
    private let disclose = NSButton()
    private let closeButton = NSButton()
    private let scopePopup = NSPopUpButton()
    private let spinner = NSProgressIndicator()
    private let status = NSTextField(labelWithString: "")
    private let replaceAllButton = NSButton(title: "Replace All", target: nil, action: nil)
    private let replaceFileButton = NSButton(title: "Replace in File", target: nil, action: nil)
    private let undoButton = NSButton(title: "Undo Last Replace", target: nil, action: nil)
    private let divider = NSView()
    private let scroll = NSScrollView()
    private let outline = FindOutlineView()
    private let root = FindRootView()

    private var directory: URL?
    private(set) var replaceMode = false
    private var files: [FindFileNode] = []
    private var fileIndex: [String: FindFileNode] = [:]
    private var matchTotal = 0
    private var token: CancelToken?
    private var debounce: DispatchWorkItem?
    private var lastOptions: FindOptions?
    private var lastStats: FindStats?
    private var searching = false
    private var errorText: String?
    private var note = ""
    private var observer: NSObjectProtocol?
    var onSearchDone: (() -> Void)?    // test hook

    init(root: URL, files: @escaping () -> [String],
         openFile: @escaping (URL, _ line: Int, _ column: Int) -> Void,
         openBuffer: @escaping (URL) -> EditorTab?) {
        rootURL = root
        engine = FindEngine(root: root, files: files)
        self.openFile = openFile
        self.openBuffer = openBuffer
        view = self.root
        super.init()
        build()
        observer = NotificationCenter.default.addObserver(forName: Theme.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.applyTheme()
        }
    }

    deinit {
        token?.cancel()
        if let o = observer { NotificationCenter.default.removeObserver(o) }
    }

    // MARK: public API

    func show(seed: String?, replaceMode: Bool) {
        setReplaceMode(replaceMode)
        if let s = seed?.components(separatedBy: .newlines).first, !s.isEmpty {
            queryField.stringValue = s
            scheduleSearch(immediately: true)
        } else if files.isEmpty, !queryField.stringValue.isEmpty {
            scheduleSearch(immediately: true)
        }
        focusQuery()
    }

    func focusQuery() {
        guard let w = view.window else { return }
        w.makeFirstResponder(queryField)
        queryField.currentEditor()?.selectAll(nil)
    }

    /// Cancels any search and frees results (the undo backup stays until `releaseResources`).
    func clearResults() {
        debounce?.cancel(); token?.cancel(); token = nil
        searching = false; spinner.stopAnimation(nil)
        files = []; fileIndex = [:]; matchTotal = 0; lastStats = nil; note = ""
        outline.reloadData()
        updateStatus()
    }

    /// Frees everything, including the replace-undo backup. Call when the project closes.
    func releaseResources() {
        clearResults()
        engine.releaseBackups()
        updateButtons()
    }

    // MARK: build

    private func configureToggle(_ b: NSButton, title: String, tip: String) {
        b.title = title
        b.setButtonType(.pushOnPushOff)
        b.bezelStyle = .recessed
        b.controlSize = .small
        b.font = .systemFont(ofSize: 11, weight: .semibold)
        b.toolTip = tip
        b.target = self
        b.action = #selector(optionChanged)
    }

    private func build() {
        configureToggle(caseButton, title: "Cc", tip: "Match Case")
        configureToggle(wordButton, title: "W", tip: "Whole Word")
        configureToggle(regexButton, title: ".*", tip: "Regular Expression ($1 and \\n work in the replacement)")

        queryField.placeholderString = "Find in files"
        queryField.delegate = self
        queryField.controlSize = .regular
        queryField.sendsSearchStringImmediately = false
        queryField.focusRingType = .none
        replaceField.placeholderString = "Replace with"
        replaceField.isBezeled = true; replaceField.bezelStyle = .roundedBezel
        replaceField.delegate = self
        maskField.placeholderString = "File mask: *.php, *.blade.php, !*.min.js"
        maskField.isBezeled = true; maskField.bezelStyle = .roundedBezel
        maskField.delegate = self
        maskField.toolTip = "Comma separated globs; prefix with ! to exclude"
        for f in [replaceField, maskField] { f.font = .systemFont(ofSize: 12); f.controlSize = .regular }

        scopePopup.controlSize = .small
        scopePopup.target = self
        scopePopup.action = #selector(scopeChanged)
        rebuildScopeMenu(selecting: 0)

        disclose.isBordered = false
        disclose.imagePosition = .imageOnly
        disclose.target = self
        disclose.action = #selector(toggleReplace)
        disclose.toolTip = "Toggle Replace"
        closeButton.isBordered = false
        closeButton.imagePosition = .imageOnly
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        closeButton.toolTip = "Close (Esc)"

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        status.font = .systemFont(ofSize: 11)
        status.lineBreakMode = .byTruncatingTail

        for b in [replaceAllButton, replaceFileButton, undoButton] {
            b.bezelStyle = .rounded; b.controlSize = .small; b.target = self
        }
        replaceAllButton.action = #selector(replaceAllTapped)
        replaceFileButton.action = #selector(replaceFileTapped)
        undoButton.action = #selector(undoTapped)
        replaceAllButton.toolTip = "Replace all included matches in all files"
        replaceFileButton.toolTip = "Replace included matches in the selected file"

        divider.wantsLayer = true

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c"))
        col.resizingMask = .autoresizingMask
        outline.addTableColumn(col)
        outline.outlineTableColumn = col
        outline.headerView = nil
        outline.rowHeight = 22
        outline.indentationPerLevel = 14
        outline.intercellSpacing = .zero
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.doubleAction = #selector(openSelected)
        outline.allowsMultipleSelection = false
        outline.floatsGroupRows = false
        outline.onOpen = { [weak self] in self?.openSelected() }
        outline.onSpace = { [weak self] in self?.toggleSelectedExclusion() }
        outline.onEscape = { [weak self] in self?.closeTapped() }
        outline.onUpAtTop = { [weak self] in self?.focusQuery() }
        let menu = NSMenu()
        menu.delegate = self
        outline.menu = menu
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = true
        scroll.borderType = .noBorder

        for v in [disclose, queryField, caseButton, wordButton, regexButton, closeButton, maskField, scopePopup,
                  spinner, status, replaceField, replaceAllButton, replaceFileButton, undoButton, divider, scroll] as [NSView] {
            root.addSubview(v)
        }
        root.relayout = { [weak self] in self?.layoutAll() }
        root.onAppearance = { [weak self] in self?.applyTheme() }
        applyTheme()
        setReplaceMode(false)
    }

    private func applyTheme() {
        outline.backgroundColor = Theme.background
        scroll.backgroundColor = Theme.background
        divider.layer?.backgroundColor = NSColor.separatorColor.cgColor
        status.textColor = errorText != nil ? .systemRed : Theme.gutter
        root.needsDisplay = true
        outline.reloadData()
        expandAll()
        updateChrome()
    }

    private func updateChrome() {
        disclose.image = NSImage(systemSymbolName: replaceMode ? "chevron.down" : "chevron.right", accessibilityDescription: "Replace")
        disclose.contentTintColor = Theme.gutter
        closeButton.contentTintColor = Theme.gutter
    }

    private func rebuildScopeMenu(selecting index: Int) {
        scopePopup.removeAllItems()
        scopePopup.addItem(withTitle: "In Project")
        if let d = directory { scopePopup.addItem(withTitle: d.lastPathComponent) }
        scopePopup.menu?.addItem(.separator())
        scopePopup.addItem(withTitle: "Directory…")
        scopePopup.selectItem(at: index)
    }

    private func setReplaceMode(_ on: Bool) {
        replaceMode = on
        for v in [replaceField, replaceAllButton, replaceFileButton, undoButton] as [NSView] { v.isHidden = !on }
        updateChrome()
        updateButtons()
        outline.reloadData()
        expandAll()
        root.needsLayout = true
    }

    private func updateButtons() {
        undoButton.isEnabled = engine.canUndoReplace
        replaceAllButton.isEnabled = matchTotal > 0
        replaceFileButton.isEnabled = matchTotal > 0
    }

    // MARK: layout

    private func layoutAll() {
        let w = root.bounds.width, pad: CGFloat = 8
        var y: CGFloat = 6
        let rowH: CGFloat = 24
        let tw: CGFloat = 30
        disclose.frame = NSRect(x: pad - 2, y: y + 2, width: 20, height: 20)
        closeButton.frame = NSRect(x: w - pad - 18, y: y + 3, width: 18, height: 18)
        regexButton.frame = NSRect(x: closeButton.frame.minX - 6 - tw, y: y + 1, width: tw, height: 22)
        wordButton.frame = NSRect(x: regexButton.frame.minX - 2 - tw, y: y + 1, width: tw, height: 22)
        caseButton.frame = NSRect(x: wordButton.frame.minX - 2 - tw, y: y + 1, width: tw, height: 22)
        let qx = pad + 20
        queryField.frame = NSRect(x: qx, y: y, width: max(60, caseButton.frame.minX - 6 - qx), height: rowH)
        y += rowH + 4
        let popW: CGFloat = 130
        scopePopup.frame = NSRect(x: w - pad - popW, y: y + 1, width: popW, height: 22)
        maskField.frame = NSRect(x: qx, y: y, width: max(60, scopePopup.frame.minX - 6 - qx), height: rowH)
        y += rowH + 4
        if replaceMode {
            let bw1: CGFloat = 84, bw2: CGFloat = 104, bw3: CGFloat = 124
            undoButton.frame = NSRect(x: w - pad - bw3, y: y + 1, width: bw3, height: 22)
            replaceFileButton.frame = NSRect(x: undoButton.frame.minX - 4 - bw2, y: y + 1, width: bw2, height: 22)
            replaceAllButton.frame = NSRect(x: replaceFileButton.frame.minX - 4 - bw1, y: y + 1, width: bw1, height: 22)
            replaceField.frame = NSRect(x: qx, y: y, width: max(60, replaceAllButton.frame.minX - 6 - qx), height: rowH)
            y += rowH + 4
        }
        spinner.frame = NSRect(x: qx, y: y + 1, width: 14, height: 14)
        status.frame = NSRect(x: qx + 20, y: y, width: max(0, w - qx - 20 - pad), height: 16)
        y += 20
        divider.frame = NSRect(x: 0, y: y, width: w, height: 1)
        scroll.frame = NSRect(x: 0, y: y + 1, width: w, height: max(0, root.bounds.height - y - 1))
        outline.sizeLastColumnToFit()
    }

    // MARK: search

    func regexToggleForTest() { regexButton.state = regexButton.state == .on ? .off : .on; optionChanged() }

    @objc private func optionChanged() {
        for b in [caseButton, wordButton, regexButton] {
            b.bezelColor = b.state == .on ? NSColor.controlAccentColor.withAlphaComponent(0.55) : nil
            b.contentTintColor = b.state == .on ? .white : nil
        }
        scheduleSearch(immediately: true)
    }

    private var currentOptions: FindOptions {
        var o = FindOptions(query: queryField.stringValue)
        o.caseSensitive = caseButton.state == .on
        o.wholeWord = wordButton.state == .on
        o.isRegex = regexButton.state == .on
        o.fileMask = maskField.stringValue
        o.directory = directory
        return o
    }

    private func scheduleSearch(immediately: Bool = false) {
        debounce?.cancel()
        if immediately { startSearch(); return }
        let item = DispatchWorkItem { [weak self] in self?.startSearch() }
        debounce = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
    }

    private func setError(_ e: String?) {
        errorText = e
        queryField.wantsLayer = true
        queryField.layer?.borderWidth = e == nil ? 0 : 1
        queryField.layer?.borderColor = NSColor.systemRed.cgColor
        queryField.layer?.cornerRadius = 6
        queryField.textColor = e == nil ? nil : .systemRed
        queryField.toolTip = e
    }

    private func startSearch() {
        token?.cancel(); token = nil
        files = []; fileIndex = [:]; matchTotal = 0; lastStats = nil; note = ""
        outline.reloadData()
        let o = currentOptions
        lastOptions = o
        guard !o.query.isEmpty else {
            setError(nil); searching = false; spinner.stopAnimation(nil); updateStatus(); updateButtons(); return
        }
        if o.isRegex, let err = FindEngine.validate(o) {
            setError(err); searching = false; spinner.stopAnimation(nil)
            updateStatus(); updateButtons(); return
        }
        setError(nil)
        searching = true
        spinner.startAnimation(nil)
        updateStatus()
        token = engine.search(o, batch: { [weak self] ms in self?.ingest(ms) }, done: { [weak self] stats in
            self?.finished(stats)
        })
    }

    private func relPath(_ url: URL) -> String {
        let p = url.path, base = (rootURL.path as NSString).standardizingPath
        if p.hasPrefix(base + "/") { return String(p.dropFirst(base.count + 1)) }
        let real = URL(fileURLWithPath: base).resolvingSymlinksInPath().path
        if p.hasPrefix(real + "/") { return String(p.dropFirst(real.count + 1)) }
        return p
    }

    private func ingest(_ ms: [FindMatch]) {
        var order: [FindFileNode] = []
        var added: [ObjectIdentifier: (node: FindFileNode, old: Int, isNew: Bool)] = [:]
        for m in ms {
            let node: FindFileNode
            if let n = fileIndex[m.url.path] { node = n } else {
                node = FindFileNode(url: m.url, rel: relPath(m.url))
                fileIndex[m.url.path] = node
            }
            let id = ObjectIdentifier(node)
            if added[id] == nil {
                let isNew = !files.contains { $0 === node }
                added[id] = (node, node.matches.count, isNew)
                order.append(node)
            }
            node.matches.append(FindMatchNode(m, file: node))
        }
        matchTotal += ms.count
        let firstRows = files.isEmpty
        for n in order {
            let info = added[ObjectIdentifier(n)]!
            if info.isNew {
                files.append(n)
                outline.insertItems(at: IndexSet(integer: files.count - 1), inParent: nil, withAnimation: [])
                outline.expandItem(n)
            } else {
                outline.insertItems(at: IndexSet(info.old..<n.matches.count), inParent: n, withAnimation: [])
                outline.reloadItem(n, reloadChildren: false)
            }
        }
        if firstRows, outline.selectedRow < 0, outline.numberOfRows > 1 {
            outline.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        }
        updateStatus(); updateButtons()
    }

    private func finished(_ stats: FindStats) {
        searching = false
        spinner.stopAnimation(nil)
        lastStats = stats
        if let e = stats.error { setError(e) }
        // Workers finish out of order: restore path order once.
        let sorted = files.sorted { $0.url.path < $1.url.path }
        if zip(sorted, files).contains(where: { $0 !== $1 }) {
            files = sorted
            outline.reloadData()
            expandAll()
            if outline.numberOfRows > 1 { outline.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false) }
        }
        updateStatus(); updateButtons()
        onSearchDone?()
    }

    private func expandAll() { outline.expandItem(nil, expandChildren: true) }

    private static let nf: NumberFormatter = { let f = NumberFormatter(); f.numberStyle = .decimal; return f }()
    private func n(_ v: Int) -> String { Self.nf.string(from: NSNumber(value: v)) ?? "\(v)" }

    private func updateStatus() {
        status.textColor = errorText != nil ? .systemRed : Theme.gutter
        if let e = errorText { status.stringValue = "Invalid regular expression: \(e)"; return }
        if !note.isEmpty { status.stringValue = note; return }
        if lastOptions?.query.isEmpty ?? true { status.stringValue = ""; return }
        let m = matchTotal, f = files.count
        var s = "\(n(m)) match\(m == 1 ? "" : "es") in \(n(f)) file\(f == 1 ? "" : "s")"
        if let st = lastStats {
            if st.truncated { s += " · results truncated at \(n(FindEngine.maxMatches))" }
            s += " · \(n(st.filesScanned)) scanned · \(Int(st.milliseconds)) ms"
        } else if searching { s = "Searching… " + s }
        status.stringValue = s
    }

    // MARK: text field delegate

    func controlTextDidChange(_ obj: Notification) {
        guard let f = obj.object as? NSTextField, f === queryField || f === maskField else { return }
        scheduleSearch()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.cancelOperation(_:)):
            closeTapped(); return true
        case #selector(NSResponder.moveDown(_:)):
            if control === queryField || control === maskField || control === replaceField { focusResults(); return true }
        case #selector(NSResponder.insertNewline(_:)):
            if control === replaceField { replaceAllTapped() } else { scheduleSearch(immediately: true) }
            return true
        default: break
        }
        return false
    }

    private func focusResults() {
        guard outline.numberOfRows > 0 else { return }
        if outline.selectedRow < 0 { outline.selectRowIndexes(IndexSet(integer: min(1, outline.numberOfRows - 1)), byExtendingSelection: false) }
        view.window?.makeFirstResponder(outline)
    }

    // MARK: actions

    @objc private func closeTapped() {
        clearResults()
        onClose?()
    }

    @objc private func toggleReplace() { setReplaceMode(!replaceMode); if replaceMode { view.window?.makeFirstResponder(replaceField) } }

    @objc private func scopeChanged() {
        let title = scopePopup.titleOfSelectedItem ?? ""
        if title == "In Project" {
            directory = nil; rebuildScopeMenu(selecting: 0); scheduleSearch(immediately: true)
        } else if title == "Directory…" {
            let p = NSOpenPanel()
            p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = false
            p.directoryURL = directory ?? rootURL
            p.prompt = "Search Here"
            let done: (NSApplication.ModalResponse) -> Void = { [weak self] r in
                guard let self else { return }
                if r == .OK, let u = p.url { self.directory = u }
                self.rebuildScopeMenu(selecting: self.directory == nil ? 0 : 1)
                self.scheduleSearch(immediately: true)
            }
            if let w = view.window { p.beginSheetModal(for: w, completionHandler: done) } else { done(p.runModal()) }
        }
    }

    private func match(atRow row: Int) -> FindMatchNode? { row >= 0 ? outline.item(atRow: row) as? FindMatchNode : nil }

    @objc private func openSelected() {
        let row = outline.clickedRow >= 0 && NSApp.currentEvent?.clickCount == 2 ? outline.clickedRow : outline.selectedRow
        guard row >= 0, let item = outline.item(atRow: row) else { return }
        if let m = item as? FindMatchNode { open(m.match) }
        else if let f = item as? FindFileNode, let first = f.matches.first { open(first.match) }
    }

    private func open(_ m: FindMatch) {
        if let h = openMatch { h(m) } else { openFile(m.url, m.line, m.column) }
    }

    private func toggleSelectedExclusion() {
        guard replaceMode, let item = outline.item(atRow: outline.selectedRow) else { return }
        if let m = item as? FindMatchNode { m.excluded.toggle(); reloadRows(for: m.file) }
        else if let f = item as? FindFileNode { setFile(f, excluded: f.state != 0) }
    }

    private func setFile(_ f: FindFileNode, excluded: Bool) {
        for m in f.matches { m.excluded = excluded }
        reloadRows(for: f)
    }

    private func reloadRows(for f: FindFileNode) {
        outline.reloadItem(f, reloadChildren: true)
        outline.expandItem(f)
    }

    // MARK: replace

    @objc private func replaceAllTapped() { replaceAll(confirm: true) }

    /// Replaces every included match; `confirm` shows the "Replace N matches in M files?" alert when > 1 file.
    func replaceAll(confirm: Bool = true) { performReplace(nodes: files, confirm: confirm) }

    @objc private func replaceFileTapped() {
        guard let item = outline.item(atRow: outline.selectedRow) else { return }
        let f = (item as? FindFileNode) ?? (item as? FindMatchNode)?.file
        if let f { performReplace(nodes: [f], confirm: false) }
    }

    private func performReplace(nodes: [FindFileNode], confirm: Bool) {
        guard let o = lastOptions else { return }
        let sel = nodes.flatMap { $0.matches.filter { !$0.excluded }.map(\.match) }
        let fileCount = Set(sel.map { $0.url.path }).count
        guard !sel.isEmpty else { note = "Nothing to replace"; updateStatus(); return }
        let go = { [weak self] in self?.applyReplace(sel, options: o) }
        if confirm && fileCount > 1 {
            let a = NSAlert()
            a.messageText = "Replace \(n(sel.count)) matches in \(n(fileCount)) files?"
            a.informativeText = "Open files are edited in their editor (undo with Cmd-Z, then save). Other files are written to disk; \"Undo Last Replace\" restores them."
            a.addButton(withTitle: "Replace"); a.addButton(withTitle: "Cancel")
            if let w = view.window { a.beginSheetModal(for: w) { if $0 == .alertFirstButtonReturn { go() } } }
            else if a.runModal() == .alertFirstButtonReturn { go() }
        } else { go() }
    }

    func applyReplace(_ sel: [FindMatch], options o: FindOptions) {
        let report = engine.replace(sel, with: replaceField.stringValue, options: o, openBuffer: openBuffer)
        if let e = report.error { note = "Replace failed: \(e)"; updateStatus(); return }
        // Drop replaced matches from the results.
        for f in files { f.matches.removeAll { report.replaced.contains($0.match.key) } }
        files.removeAll { $0.matches.isEmpty }
        fileIndex = fileIndex.filter { p, f in files.contains { $0 === f } }
        matchTotal = files.reduce(0) { $0 + $1.matches.count }
        outline.reloadData(); expandAll()
        var s = "Replaced \(n(report.replaced.count)) match\(report.replaced.count == 1 ? "" : "es") in \(n(report.filesChanged + report.buffersEdited)) file\(report.filesChanged + report.buffersEdited == 1 ? "" : "s")"
        if report.buffersEdited > 0 { s += " (\(report.buffersEdited) open, unsaved)" }
        if !report.skipped.isEmpty {
            let names = Set(report.skipped.map { $0.url.lastPathComponent })
            s += " · skipped \(names.count): " + names.sorted().prefix(3).joined(separator: ", ") + (names.count > 3 ? "…" : "") + " (changed since search)"
        }
        note = s
        updateStatus(); updateButtons()
    }

    @objc private func undoTapped() { undoLastReplace() }

    func undoLastReplace() {
        let r = engine.undoLastReplace()
        scheduleSearch(immediately: true)
        note = "Restored \(r.restored) file\(r.restored == 1 ? "" : "s")" + (r.skipped.isEmpty ? "" : " · \(r.skipped.count) skipped (modified since)")
        updateStatus(); updateButtons()
    }

    // MARK: outline data source / delegate

    func outlineView(_ ov: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return files.count }
        return (item as? FindFileNode)?.matches.count ?? 0
    }
    func outlineView(_ ov: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil { return files[index] }
        return (item as! FindFileNode).matches[index]
    }
    func outlineView(_ ov: NSOutlineView, isItemExpandable item: Any) -> Bool { item is FindFileNode }
    func outlineView(_ ov: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? { FindRowBackground() }
    func outlineView(_ ov: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat { 22 }

    func outlineView(_ ov: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = (ov.makeView(withIdentifier: id, owner: nil) as? FindCell) ?? { let c = FindCell(frame: .zero); c.identifier = id; return c }()
        cell.showsCheck = replaceMode
        if let f = item as? FindFileNode {
            cell.isFile = true
            cell.icon.isHidden = false
            let ext = f.url.pathExtension
            cell.icon.image = NSImage(systemSymbolName: FileIcon.symbol(forExtension: ext), accessibilityDescription: nil)
            cell.icon.contentTintColor = FileIcon.tint(forExtension: ext)
            cell.primary.font = .systemFont(ofSize: 12.5, weight: .medium)
            cell.primary.textColor = Theme.foreground
            cell.primary.stringValue = f.name
            cell.secondary.font = .systemFont(ofSize: 11.5)
            cell.secondary.textColor = Theme.gutter
            cell.secondary.stringValue = f.dir
            cell.badge.font = .systemFont(ofSize: 11, weight: .medium)
            cell.badge.textColor = Theme.gutter
            cell.badge.stringValue = "\(f.matches.count)"
            cell.check.allowsMixedState = true
            cell.check.state = f.state == 1 ? .on : f.state == 0 ? .off : .mixed
            cell.onToggle = { [weak self, weak f] in
                guard let self, let f else { return }
                self.setFile(f, excluded: f.state != 0)
            }
        } else if let m = item as? FindMatchNode {
            cell.isFile = false
            cell.icon.isHidden = true
            cell.secondary.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            cell.secondary.textColor = Theme.gutter
            cell.secondary.alignment = .right
            cell.secondary.lineBreakMode = .byClipping
            cell.secondary.stringValue = "\(m.match.line):\(m.match.column)"
            cell.badge.stringValue = ""
            cell.primary.attributedStringValue = attributed(m)
            cell.check.allowsMixedState = false
            cell.check.state = m.excluded ? .off : .on
            cell.onToggle = { [weak self, weak m] in
                guard let self, let m else { return }
                m.excluded.toggle(); self.outline.reloadItem(m)
            }
        }
        cell.needsLayout = true
        return cell
    }

    private func attributed(_ node: FindMatchNode) -> NSAttributedString {
        let m = node.match
        let u = Array(m.lineText.utf16)
        var trim = 0
        while trim < u.count, trim < m.textOffset, u[trim] == 32 || u[trim] == 9 { trim += 1 }
        let shown = String(utf16CodeUnits: Array(u[trim...]), count: u.count - trim)
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let bold = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        let fg = node.excluded ? Theme.gutter.withAlphaComponent(0.6) : Theme.foreground
        let para = NSMutableParagraphStyle(); para.lineBreakMode = .byTruncatingTail
        let s = NSMutableAttributedString(string: shown, attributes: [.font: font, .foregroundColor: fg, .paragraphStyle: para])
        let loc = m.textOffset - trim
        if loc >= 0, loc < u.count - trim {
            let len = min(m.length, u.count - trim - loc)
            var attrs: [NSAttributedString.Key: Any] = [
                .font: bold,
                .backgroundColor: NSColor.systemYellow.withAlphaComponent(Theme.isDark ? 0.30 : 0.45),
            ]
            if node.excluded { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            s.addAttributes(attrs, range: NSRange(location: loc, length: len))
        }
        return s
    }

    // MARK: context menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard outline.clickedRow >= 0, let item = outline.item(atRow: outline.clickedRow) else { return }
        if item is FindMatchNode {
            let c = NSMenuItem(title: "Copy Line", action: #selector(copyLine), keyEquivalent: ""); c.target = self; menu.addItem(c)
        }
        let f = (item as? FindFileNode) ?? (item as? FindMatchNode)?.file
        if let f {
            let allEx = f.state == 0
            let title = replaceMode ? (allEx ? "Include File" : "Exclude File") : "Remove File from Results"
            let e = NSMenuItem(title: title, action: #selector(excludeFile), keyEquivalent: ""); e.target = self; menu.addItem(e)
            let p = NSMenuItem(title: "Copy Path", action: #selector(copyPath), keyEquivalent: ""); p.target = self; menu.addItem(p)
        }
    }

    @objc private func copyLine() {
        guard let m = outline.item(atRow: outline.clickedRow) as? FindMatchNode else { return }
        let t = m.match.lineText.trimmingCharacters(in: .whitespaces)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(t, forType: .string)
    }

    @objc private func copyPath() {
        let item = outline.item(atRow: outline.clickedRow)
        guard let f = (item as? FindFileNode) ?? (item as? FindMatchNode)?.file else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(f.url.path, forType: .string)
    }

    @objc private func excludeFile() {
        let item = outline.item(atRow: outline.clickedRow)
        guard let f = (item as? FindFileNode) ?? (item as? FindMatchNode)?.file else { return }
        if replaceMode { setFile(f, excluded: f.state != 0); return }
        files.removeAll { $0 === f }
        fileIndex[f.url.path] = nil
        matchTotal -= f.matches.count
        outline.reloadData(); expandAll()
        updateStatus(); updateButtons()
    }
}
