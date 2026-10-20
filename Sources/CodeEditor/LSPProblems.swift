import AppKit

// MARK: - Model

/// Diagnostics of one file. Lines/columns are 1-based; columns are UTF-16 offsets like the editor's own columns.
struct FileProblems {
    struct Diagnostic {
        let severity: Int           // 1 error, 2 warning, 3 info, 4 hint
        let message: String
        let line: Int
        let column: Int
        let endLine: Int
        let endColumn: Int
        let source: String?
        let code: String?
    }
    let url: URL
    var diagnostics: [Diagnostic]
    var errorCount: Int { diagnostics.filter { $0.severity == 1 }.count }
    var warningCount: Int { diagnostics.filter { $0.severity == 2 }.count }
}

extension LanguageServers {
    /// Posted (main thread, coalesced) whenever any file's diagnostics change or a file with problems closes.
    static let problemsDidChange = Notification.Name("CodeEditor.languageServerProblemsDidChange")

    /// Problems of the OPEN files under `root` (servers such as Intelephense only publish diagnostics for open
    /// documents), sorted by path then position.
    static func problems(forRoot root: URL) -> [FileProblems] {
        let rp = root.standardizedFileURL.path
        var out: [FileProblems] = []
        var seen = Set<String>()
        for s in LanguageServerManager.shared.sessions.values {
            let path = s.url.standardizedFileURL.path
            guard path.hasPrefix(rp + "/") || path == rp, !seen.contains(path) else { continue }
            let list = s.allDiagnostics
            guard !list.isEmpty else { continue }
            seen.insert(path)
            let table = LSPLineTable(s.text as NSString)
            let ds = list.sorted { ($0.range.location, $0.severity) < ($1.range.location, $1.severity) }.map { d -> FileProblems.Diagnostic in
                let a = table.position(of: d.range.location), b = table.position(of: NSMaxRange(d.range))
                return FileProblems.Diagnostic(severity: d.severity, message: d.message, line: a.line + 1, column: a.character + 1,
                                               endLine: b.line + 1, endColumn: b.character + 1, source: d.source, code: d.code)
            }
            out.append(FileProblems(url: s.url.standardizedFileURL, diagnostics: ds))
        }
        out += NativeProblems.problems(forRoot: root, excluding: seen)     // JSON / YAML syntax checks (ViewerSystem.swift)
        out = TestResultsStore.shared.merged(into: out, root: root)         // failed tests (TestResultsStore.swift)
        return out.sorted { $0.url.path < $1.url.path }
    }

    /// F2 / Shift-F2: jump to the next / previous problem (errors, warnings, infos) of the current file, wrapping, and
    /// show its message. With nothing else in this file, continues in the next file that has problems via `openLocation`.
    /// Returns false when the file has no language-server session or there are no problems at all.
    @discardableResult
    static func nextProblem(in tab: EditorTab, forward: Bool) -> Bool {
        guard let s = session(for: tab) else { return false }
        let tv = tab.textView
        let caret = tv.selectedRange().location
        let list = s.allDiagnostics.filter { $0.severity <= 3 }.sorted { ($0.range.location, $0.severity) < ($1.range.location, $1.severity) }
        func show(_ d: LSPDiagnostic) {
            tv.setSelectedRange(NSRange(location: d.range.location, length: 0))
            tv.scrollRangeToVisible(d.range)
            let label = ["", "error", "warning", "info", "hint"][min(max(d.severity, 1), 4)]
            let msg = "**\(label)**\(d.source.map { " (\($0))" } ?? ""): \(d.message)"
            LanguageServers.report(msg, session: s)
        }
        let cur = tab.url.standardizedFileURL.path
        let others = problems(forRoot: s.instances.first?.root ?? tab.url.deletingLastPathComponent())
            .filter { $0.url.path != cur && $0.diagnostics.contains { $0.severity <= 3 } }
        if forward {
            if let d = list.first(where: { $0.range.location > caret }) { show(d); return true }
        } else {
            if let d = list.last(where: { $0.range.location < caret }) { show(d); return true }
        }
        // Past the last / before the first: move to another file if one has problems, else wrap here.
        if let next = (forward ? others.first(where: { $0.url.path > cur }) ?? others.first
                               : others.last(where: { $0.url.path < cur }) ?? others.last),
           let open = LanguageServers.openLocation {
            let pool = next.diagnostics.filter { $0.severity <= 3 }
            if let d = forward ? pool.first : pool.last { open(next.url, d.line, d.column); return true }
        }
        if let d = forward ? list.first : list.last { show(d); return true }
        LanguageServers.report("No problems found", session: s)
        return false
    }
}

// MARK: - Panel

private final class ProblemFileNode: NSObject {
    let file: FileProblems
    let relative: String
    var children: [ProblemNode] = []
    init(file: FileProblems, relative: String) { self.file = file; self.relative = relative }
}

private final class ProblemNode: NSObject {
    let url: URL
    let d: FileProblems.Diagnostic
    init(url: URL, d: FileProblems.Diagnostic) { self.url = url; self.d = d }
}

private final class ProblemsOutline: NSOutlineView {
    var onActivate: (() -> Void)?
    var speedSearch: SpeedSearch?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 { onActivate?(); return }
        if speedSearch?.handleKeyDown(event) == true { return }
        super.keyDown(with: event)
    }
}

private final class ProblemCell: NSTableCellView {
    let icon = NSImageView()
    let primary = NSTextField(labelWithString: "")
    let secondary = NSTextField(labelWithString: "")
    override init(frame: NSRect) {
        super.init(frame: frame)
        icon.imageScaling = .scaleProportionallyDown
        primary.lineBreakMode = .byTruncatingTail
        secondary.lineBreakMode = .byTruncatingTail
        secondary.alignment = .right
        for v in [icon, primary, secondary] as [NSView] { addSubview(v) }
        imageView = icon
        textField = primary
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        let h = bounds.height, pad: CGFloat = 2
        icon.frame = NSRect(x: pad, y: (h - 16) / 2, width: 16, height: 16)
        let sw = min(ceil(secondary.attributedStringValue.size().width) + 4, bounds.width * 0.4)
        secondary.frame = NSRect(x: bounds.width - sw - 6, y: (h - 16) / 2, width: sw, height: 16)
        let x0 = icon.frame.maxX + 6
        primary.frame = NSRect(x: x0, y: (h - 17) / 2, width: max(0, secondary.frame.minX - x0 - 6), height: 17)
    }
}

/// Problems tool window: files with diagnostics, expandable to individual problems.
final class ProblemsPanelController: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    let view = NSView()
    /// Returns the file shown in the editor; used by the "Current file" filter.
    var currentFileProvider: (() -> URL?)?

    private let root: URL
    private let openFile: (URL, Int, Int) -> Void
    private let outline = ProblemsOutline()
    private let speed = SpeedSearch()
    private let scroll = NSScrollView()
    private let toolbar = NSView()
    private let summary = NSTextField(labelWithString: "")
    private let errorsButton = NSButton()
    private let warningsButton = NSButton()
    private let currentButton = NSButton()
    private let emptyLabel = NSTextField(labelWithString: "No problems detected in open files")
    private var nodes: [ProblemFileNode] = []
    private var collapsed = Set<String>()
    private var reloadScheduled = false
    private(set) var totals = (errors: 0, warnings: 0, files: 0)

    init(root: URL, openFile: @escaping (URL, Int, Int) -> Void) {
        self.root = root.standardizedFileURL
        self.openFile = openFile
        super.init()
        view.frame = NSRect(x: 0, y: 0, width: 640, height: 240)
        view.autoresizesSubviews = true
        view.wantsLayer = true

        toolbar.autoresizingMask = [.width, .minYMargin]
        summary.font = .systemFont(ofSize: 11, weight: .medium)
        summary.lineBreakMode = .byTruncatingTail
        toolbar.addSubview(summary)
        for (b, title, on) in [(errorsButton, "Errors", true), (warningsButton, "Warnings", true), (currentButton, "Current file", false)] {
            b.title = title
            b.setButtonType(.pushOnPushOff)
            b.bezelStyle = .recessed
            b.controlSize = .small
            b.font = .systemFont(ofSize: 11)
            b.state = on ? .on : .off
            b.target = self
            b.action = #selector(filterChanged)
            toolbar.addSubview(b)
        }
        view.addSubview(toolbar)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("problem"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.rowHeight = 22
        outline.indentationPerLevel = 14
        outline.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        outline.usesAlternatingRowBackgroundColors = false
        outline.selectionHighlightStyle = .regular
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.doubleAction = #selector(activate)
        outline.onActivate = { [weak self] in self?.activate() }
        speed.attach(to: outline) { [weak self] row in
            switch self?.outline.item(atRow: row) {
            case let f as ProblemFileNode: return f.relative
            case let p as ProblemNode: return p.d.message
            default: return nil
            }
        }
        speed.onReturn = { [weak self] in self?.activate() }
        outline.speedSearch = speed
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.autoresizingMask = [.width, .height]
        view.addSubview(scroll)

        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.alignment = .center
        emptyLabel.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        view.addSubview(emptyLabel)

        view.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(layoutSubviews), name: NSView.frameDidChangeNotification, object: view)
        NotificationCenter.default.addObserver(self, selector: #selector(scheduleReload), name: LanguageServers.problemsDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: Theme.didChange, object: nil)
        applyTheme()
        layoutSubviews()
        reload()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: Layout and theme

    @objc private func layoutSubviews() {
        let w = view.bounds.width, h = view.bounds.height, th: CGFloat = 28
        toolbar.frame = NSRect(x: 0, y: h - th, width: w, height: th)
        scroll.frame = NSRect(x: 0, y: 0, width: w, height: h - th)
        var x = w - 8
        for b in [currentButton, warningsButton, errorsButton] {
            b.sizeToFit()
            let bw = b.frame.width + 6
            x -= bw
            b.frame = NSRect(x: x, y: (th - 20) / 2, width: bw, height: 20)
            x -= 4
        }
        summary.frame = NSRect(x: 10, y: (th - 16) / 2, width: max(0, x - 14), height: 16)
        emptyLabel.frame = NSRect(x: 0, y: (h - th) / 2 - 8, width: w, height: 18)
        outline.sizeLastColumnToFit()
    }

    @objc private func themeChanged() { applyTheme(); outline.reloadData(); expandAll() }

    private func applyTheme() {
        let dark = Theme.isDark
        view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        view.layer?.backgroundColor = Theme.background.cgColor
        toolbar.wantsLayer = true
        toolbar.layer?.backgroundColor = (dark ? NSColor(white: 1, alpha: 0.05) : NSColor(white: 0, alpha: 0.04)).cgColor
        outline.backgroundColor = Theme.background
        scroll.backgroundColor = Theme.background
        summary.textColor = dark ? NSColor(white: 0.78, alpha: 1) : NSColor(white: 0.25, alpha: 1)
        emptyLabel.textColor = Theme.gutter
    }

    // MARK: Data

    @objc private func scheduleReload() {
        guard !reloadScheduled else { return }
        reloadScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.reloadScheduled = false
            self?.reload()
        }
    }

    @objc private func filterChanged() { reload() }

    func reload() {
        let all = LanguageServers.problems(forRoot: root)
        totals = (all.reduce(0) { $0 + $1.errorCount }, all.reduce(0) { $0 + $1.warningCount }, all.count)
        let showE = errorsButton.state == .on, showW = warningsButton.state == .on
        let current = currentButton.state == .on ? currentFileProvider?()?.standardizedFileURL.path : nil
        let rp = root.path + "/"
        nodes = all.compactMap { f in
            if currentButton.state == .on, f.url.path != current { return nil }
            let ds = f.diagnostics.filter { $0.severity == 1 ? showE : ($0.severity == 2 ? showW : (showE || showW)) }
            guard !ds.isEmpty else { return nil }
            let file = FileProblems(url: f.url, diagnostics: ds)
            let n = ProblemFileNode(file: file, relative: f.url.path.hasPrefix(rp) ? String(f.url.path.dropFirst(rp.count)) : f.url.path)
            n.children = ds.map { ProblemNode(url: f.url, d: $0) }
            return n
        }
        let sel = outline.selectedRow >= 0 ? outline.item(atRow: outline.selectedRow) : nil
        var selKey: String?
        if let n = sel as? ProblemNode { selKey = "\(n.url.path):\(n.d.line):\(n.d.column):\(n.d.message)" }
        else if let f = sel as? ProblemFileNode { selKey = f.file.url.path }
        outline.reloadData()
        expandAll()
        if let selKey {
            for row in 0..<outline.numberOfRows {
                let it = outline.item(atRow: row)
                let key = (it as? ProblemNode).map { "\($0.url.path):\($0.d.line):\($0.d.column):\($0.d.message)" } ?? (it as? ProblemFileNode)?.file.url.path
                if key == selKey { outline.selectRowIndexes([row], byExtendingSelection: false); break }
            }
        }
        func plural(_ n: Int, _ s: String) -> String { "\(n) \(s)\(n == 1 ? "" : "s")" }
        summary.stringValue = totals.files == 0 ? "No problems" :
            "\(plural(totals.errors, "error")) · \(plural(totals.warnings, "warning")) · \(plural(totals.files, "file"))"
        emptyLabel.isHidden = !nodes.isEmpty
        emptyLabel.stringValue = totals.files == 0 ? "No problems detected in open files" : "No problems match the filters"
        scroll.isHidden = nodes.isEmpty
    }

    private func expandAll() {
        for n in nodes where !collapsed.contains(n.file.url.path) { outline.expandItem(n) }
    }

    // MARK: Outline

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return nodes.count }
        return (item as? ProblemFileNode)?.children.count ?? 0
    }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        item == nil ? nodes[index] : (item as! ProblemFileNode).children[index]
    }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { item is ProblemFileNode }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        if let n = notification.userInfo?["NSObject"] as? ProblemFileNode { collapsed.insert(n.file.url.path) }
    }
    func outlineViewItemDidExpand(_ notification: Notification) {
        if let n = notification.userInfo?["NSObject"] as? ProblemFileNode { collapsed.remove(n.file.url.path) }
    }

    static func severityImage(_ s: Int) -> (NSImage?, NSColor) {
        switch s {
        case 1: return (NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Error"), .systemRed)
        case 2: return (NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Warning"), .systemOrange)
        case 3: return (NSImage(systemSymbolName: "info.circle.fill", accessibilityDescription: "Info"), .systemBlue)
        default: return (NSImage(systemSymbolName: "lightbulb.fill", accessibilityDescription: "Hint"), .systemGray)
        }
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("problemCell")
        let cell = (outlineView.makeView(withIdentifier: id, owner: nil) as? ProblemCell) ?? {
            let c = ProblemCell(frame: .zero)
            c.identifier = id
            return c
        }()
        let fg = Theme.foreground
        let dim = Theme.isDark ? NSColor(white: 0.60, alpha: 1) : NSColor(white: 0.42, alpha: 1)
        if let f = item as? ProblemFileNode {
            let ext = f.file.url.pathExtension
            cell.icon.image = NSImage(systemSymbolName: FileIcon.symbol(forExtension: ext), accessibilityDescription: nil)
            cell.icon.contentTintColor = FileIcon.tint(forExtension: ext)
            cell.primary.stringValue = f.relative
            cell.primary.font = .systemFont(ofSize: 12, weight: .semibold)
            cell.primary.textColor = fg
            var parts: [String] = []
            let e = f.file.errorCount, w = f.file.warningCount
            if e > 0 { parts.append("\(e) error\(e == 1 ? "" : "s")") }
            if w > 0 { parts.append("\(w) warning\(w == 1 ? "" : "s")") }
            let other = f.file.diagnostics.count - e - w
            if other > 0 { parts.append("\(other) other") }
            cell.secondary.stringValue = parts.joined(separator: ", ")
            cell.secondary.font = .systemFont(ofSize: 11)
            cell.secondary.textColor = dim
        } else if let p = item as? ProblemNode {
            let (img, tint) = Self.severityImage(p.d.severity)
            cell.icon.image = img
            cell.icon.contentTintColor = tint
            cell.primary.stringValue = p.d.message.replacingOccurrences(of: "\n", with: " ")
            cell.primary.font = .systemFont(ofSize: 12)
            cell.primary.textColor = fg
            var tail = "\(p.d.line):\(p.d.column)"
            if let s = p.d.source { tail += "  \(s)" + (p.d.code.map { "(\($0))" } ?? "") }
            cell.secondary.stringValue = tail
            cell.secondary.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
            cell.secondary.textColor = dim
        }
        cell.needsLayout = true
        return cell
    }

    @objc private func activate() {
        let row = outline.clickedRow >= 0 ? outline.clickedRow : outline.selectedRow
        guard row >= 0, let item = outline.item(atRow: row) else { return }
        if let p = item as? ProblemNode { openFile(p.url, p.d.line, p.d.column) }
        else if let f = item as? ProblemFileNode {
            if outline.isItemExpanded(f) { outline.collapseItem(f) } else { outline.expandItem(f) }
        }
    }

    // MARK: Test support

    /// Rows as plain strings (for headless checks).
    var rowDescriptions: [String] {
        (0..<outline.numberOfRows).map { r in
            let it = outline.item(atRow: r)
            if let f = it as? ProblemFileNode { return "FILE \(f.relative) e\(f.file.errorCount) w\(f.file.warningCount)" }
            if let p = it as? ProblemNode { return "  \(p.d.severity) \(p.d.line):\(p.d.column) \(p.d.message)" }
            return "?"
        }
    }

    func snapshot(to path: String, size: NSSize = NSSize(width: 720, height: 260)) {
        view.frame = NSRect(origin: .zero, size: size)
        layoutSubviews()
        view.layoutSubtreeIfNeeded()
        outline.reloadData(); expandAll()
        outline.layoutSubtreeIfNeeded()
        scroll.layoutSubtreeIfNeeded()
        outline.noteNumberOfRowsChanged()
        for row in 0..<outline.numberOfRows { _ = outline.view(atColumn: 0, row: row, makeIfNecessary: true) }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
