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
            out.append(FileProblems(url: s.url.standardizedFileURL, diagnostics: NativePHPDiag.merged(ds, path: path)))
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
    var key: String { ProblemsPanelController.key(url, d) }
}

/// Category or inspection row of the Inspections tab; children are group rows or problem rows.
private final class ProblemGroupNode: NSObject {
    let id: String
    let title: String
    let severity: Int
    var children: [NSObject] = []
    init(id: String, title: String, severity: Int) { self.id = id; self.title = title; self.severity = severity }
    var count: Int { children.reduce(0) { $0 + (($1 as? ProblemGroupNode)?.count ?? 1) } }
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

/// Problems tool window: File / Project Errors / Inspections tabs, an outline of problems and a detail pane with the on-request
/// Claude evaluation.
final class ProblemsPanelController: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
    enum Tab: Int { case file = 0, project = 1, inspections = 2 }
    private enum ScanState { case idle, running, done }

    let view = NSView()
    let detail = ProblemsDetailPane()
    /// Returns the file shown in the editor; the File and Inspections tabs show only this file.
    var currentFileProvider: (() -> URL?)?
    /// "Fix with Claude" on a problem row (context menu); also the default for Hand to agent.
    var onFixWithClaude: ((URL, FileProblems.Diagnostic) -> Void)?
    /// Replaces `LanguageServers.problems(forRoot:)` (tests).
    var problemsProvider: (() -> [FileProblems])?
    /// Text of a file for snippets and Claude prompts (the open buffer, else a capped read of the file).
    var textProvider: ((URL) -> String?)?
    /// Replaces the real Claude call (tests).
    var evaluateOverride: (([ProblemRef], @escaping (Result<[Int: ProblemAnswer], ClaudeCLI.Failure>) -> Void) -> Void)?
    /// Replaces text `old` by `new` in a file; false when `old` is not found exactly once.
    var applyFix: ((URL, String, String) -> Bool)?
    var handOff: ((URL, FileProblems.Diagnostic) -> Void)?

    private let root: URL
    private let openFile: (URL, Int, Int) -> Void
    private let outline = ProblemsOutline()
    private let speed = SpeedSearch()
    private let scroll = NSScrollView()
    private let toolbar = NSView()
    private let tabs = NSSegmentedControl(labels: ["File", "Project Errors", "Inspections"], trackingMode: .selectOne, target: nil, action: nil)
    private let summary = NSTextField(labelWithString: "")
    private let scanButton = NSButton()
    private let errorsButton = NSButton()
    private let warningsButton = NSButton()
    private let emptyLabel = NSTextField(labelWithString: "")
    private var nodes: [NSObject] = []
    private var collapsed = Set<String>()
    private var reloadScheduled = false
    private(set) var totals = (errors: 0, warnings: 0, files: 0)
    private(set) var tab: Tab = .file

    // Project scan
    private var scanState: ScanState = .idle
    private var scan: ProjectScan?
    private var scanResults: [FileProblems] = []
    private var scanProgress = ""
    private var scanCancelled = false
    private var refreshWork: DispatchWorkItem?

    // Claude evaluation
    private var evaluating = Set<String>()
    private var failures: [String: String] = [:]
    private var evaluated: [String: String] = [:]      // problem key -> ProblemAnswerCache key
    private var evalNote: String?
    private var currentProcess: Process?
    private var menuItem: NSObject?

    init(root: URL, openFile: @escaping (URL, Int, Int) -> Void) {
        self.root = root.standardizedFileURL
        self.openFile = openFile
        super.init()
        view.frame = NSRect(x: 0, y: 0, width: 760, height: 240)
        view.autoresizesSubviews = true
        view.wantsLayer = true

        toolbar.autoresizingMask = [.width, .minYMargin]
        tabs.controlSize = .small
        tabs.segmentStyle = .rounded
        tabs.selectedSegment = 0
        tabs.target = self
        tabs.action = #selector(tabClicked)
        toolbar.addSubview(tabs)
        summary.font = .systemFont(ofSize: 11, weight: .medium)
        summary.lineBreakMode = .byTruncatingTail
        toolbar.addSubview(summary)
        for (b, title, on) in [(errorsButton, "Errors", true), (warningsButton, "Warnings", true)] {
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
        scanButton.title = "Scan"
        scanButton.bezelStyle = .recessed
        scanButton.controlSize = .small
        scanButton.font = .systemFont(ofSize: 11)
        scanButton.target = self
        scanButton.action = #selector(scanClicked)
        scanButton.isHidden = true
        toolbar.addSubview(scanButton)
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
        let ctx = NSMenu(); ctx.delegate = self; outline.menu = ctx
        outline.onActivate = { [weak self] in self?.activate() }
        speed.attach(to: outline) { [weak self] row in
            switch self?.outline.item(atRow: row) {
            case let f as ProblemFileNode: return f.relative
            case let g as ProblemGroupNode: return g.title
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
        view.addSubview(detail)

        detail.onEvaluate = { [weak self] in
            guard let self, self.outline.selectedRow >= 0, let n = self.outline.item(atRow: self.outline.selectedRow) as? ProblemNode else { return }
            self.evaluate(item: n)
        }
        detail.onApply = { [weak self] in self?.applySelected() }
        detail.onHandOff = { [weak self] in
            guard let self, self.outline.selectedRow >= 0, let n = self.outline.item(atRow: self.outline.selectedRow) as? ProblemNode else { return }
            (self.handOff ?? self.onFixWithClaude)?(n.url, n.d)
        }

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

    deinit {
        scan?.cancel()
        currentProcess?.terminate()
        NotificationCenter.default.removeObserver(self)
    }

    static func key(_ url: URL, _ d: FileProblems.Diagnostic) -> String { "\(url.path):\(d.line):\(d.column):\(d.message)" }

    // MARK: Tabs

    @objc private func tabClicked() { select(tab: Tab(rawValue: tabs.selectedSegment) ?? .file) }

    func select(tab new: Tab) {
        if tab == .project, new != .project { stopScanAndForget() }
        tab = new
        tabs.selectedSegment = new.rawValue
        evalNote = nil
        scanButton.isHidden = new != .project
        layoutSubviews()
        reload()
    }

    // MARK: Project scan

    var projectResultCount: Int { scanResults.count }

    /// Test hook: pretend a scan finished with `results`.
    func setProjectResults(_ results: [FileProblems]) {
        scanResults = results
        scanState = .done
        scanCancelled = false
        reload()
    }

    @objc private func scanClicked() {
        if scanState == .running { scan?.cancel(); return }
        startScan()
    }

    private func startScan() {
        scan?.cancel()
        scanResults = []
        scanState = .running
        scanCancelled = false
        scanProgress = "Scanning…"
        let s = ProjectScan(root: root)
        s.isPaused = { [weak self] in PowerState.windowHidden(self?.view) }
        s.onProgress = { [weak self, weak s] files, problems in
            guard let self, let s, self.scan === s, self.scanState == .running else { return }
            self.scanProgress = "Scanning… \(files) files, \(problems) problems"
            self.updateSummary()
        }
        s.onFinish = { [weak self, weak s] results, cancelled in
            guard let self, let s, self.scan === s else { return }
            self.scanResults = results
            self.scanState = .done
            self.scanCancelled = cancelled
            self.scan = nil
            self.reload()
        }
        scan = s
        updateScanButton()
        reload()
        s.start()
    }

    private func stopScanAndForget() {
        scan?.cancel()
        scan = nil
        scanResults = []
        scanState = .idle
        scanCancelled = false
        refreshWork?.cancel()
    }

    private func updateScanButton() {
        scanButton.title = scanState == .running ? "Cancel" : (scanState == .idle ? "Scan" : "Rescan")
        scanButton.sizeToFit()
        layoutSubviews()
    }

    /// After a scan, the file being edited is re-analysed (that one file, on a background queue) so its entry stays current.
    private func scheduleCurrentFileRefresh() {
        guard tab == .project, scanState == .done, let url = currentFileProvider?()?.standardizedFileURL else { return }
        let rp = root.path + "/"
        guard url.path.hasPrefix(rp), !ProjectProblemScanner.shouldSkip(relativePath: String(url.path.dropFirst(rp.count)), isDirectory: false) else { return }
        refreshWork?.cancel()
        let root = self.root
        let work = DispatchWorkItem { [weak self] in
            let fresh = ProjectScan.analyzeFile(url: url, root: root)
            DispatchQueue.main.async {
                guard let self, self.tab == .project, self.scanState == .done else { return }
                self.scanResults.removeAll { $0.url.standardizedFileURL.path == url.path }
                if let fresh { self.scanResults.append(fresh); self.scanResults.sort { $0.url.path < $1.url.path } }
                self.reload()
            }
        }
        refreshWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    // MARK: Layout and theme

    @objc private func layoutSubviews() {
        let w = view.bounds.width, h = view.bounds.height, th: CGFloat = 30
        toolbar.frame = NSRect(x: 0, y: h - th, width: w, height: th)
        let showDetail = w >= 520
        let dw: CGFloat = showDetail ? min(max(260, w * 0.38), 460) : 0
        scroll.frame = NSRect(x: 0, y: 0, width: w - dw, height: h - th)
        detail.frame = NSRect(x: w - dw, y: 0, width: dw, height: h - th)
        detail.isHidden = !showDetail
        tabs.sizeToFit()
        tabs.frame = NSRect(x: 8, y: (th - tabs.frame.height) / 2, width: tabs.frame.width, height: tabs.frame.height)
        var x = w - 8
        var right: [NSButton] = [warningsButton, errorsButton]
        if !scanButton.isHidden { right.append(scanButton) }
        for b in right {
            b.sizeToFit()
            let bw = b.frame.width + 6
            x -= bw
            b.frame = NSRect(x: x, y: (th - 20) / 2, width: bw, height: 20)
            x -= 4
        }
        let sx = tabs.frame.maxX + 12
        summary.frame = NSRect(x: sx, y: (th - 16) / 2, width: max(0, x - sx - 6), height: 16)
        emptyLabel.frame = NSRect(x: 0, y: (h - th) / 2 - 8, width: w - dw, height: 18)
        outline.sizeLastColumnToFit()
    }

    @objc private func themeChanged() { applyTheme(); outline.reloadData(); expandAll(); detail.applyTheme() }

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
        detail.applyTheme()
    }

    // MARK: Data

    @objc private func scheduleReload() {
        guard !reloadScheduled else { return }
        reloadScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.reloadScheduled = false
            self?.reload()
            self?.scheduleCurrentFileRefresh()
        }
    }

    @objc private func filterChanged() { reload() }

    private func liveProblems() -> [FileProblems] { problemsProvider?() ?? LanguageServers.problems(forRoot: root) }

    /// Scan results, with the live (open-file) problems taking over their own files.
    private func mergedProject(_ live: [FileProblems]) -> [FileProblems] {
        let livePaths = Set(live.map { $0.url.standardizedFileURL.path })
        return (scanResults.filter { !livePaths.contains($0.url.standardizedFileURL.path) } + live).sorted { $0.url.path < $1.url.path }
    }

    func reload() {
        let live = liveProblems()
        totals = (live.reduce(0) { $0 + $1.errorCount }, live.reduce(0) { $0 + $1.warningCount }, live.count)
        let cur = currentFileProvider?()?.standardizedFileURL.path
        let curCount = live.first { $0.url.standardizedFileURL.path == cur }?.diagnostics.count ?? 0
        tabs.setLabel(curCount > 0 ? "File \(curCount)" : "File", forSegment: 0)
        let source: [FileProblems]
        switch tab {
        case .file, .inspections: source = live.filter { $0.url.standardizedFileURL.path == cur }
        case .project: source = mergedProject(live)        // before a scan: the open files' problems only
        }
        let showE = errorsButton.state == .on, showW = warningsButton.state == .on
        let rp = root.path + "/"
        let filtered: [FileProblems] = source.compactMap { f in
            let ds = f.diagnostics.filter { $0.severity == 1 ? showE : ($0.severity == 2 ? showW : (showE || showW)) }
            return ds.isEmpty ? nil : FileProblems(url: f.url, diagnostics: ds)
        }
        if tab == .inspections {
            nodes = ProblemGrouping.group(filtered).map { g in
                let cat = ProblemGroupNode(id: "c:" + g.category, title: g.category, severity: g.inspections.map { $0.severity }.min() ?? 2)
                cat.children = g.inspections.map { ins in
                    let n = ProblemGroupNode(id: "i:\(g.category)/\(ins.name)", title: ins.name, severity: ins.severity)
                    n.children = ins.items.map { ProblemNode(url: $0.url, d: $0.d) }
                    return n
                }
                return cat
            }
        } else {
            nodes = filtered.map { f in
                let n = ProblemFileNode(file: f, relative: f.url.path.hasPrefix(rp) ? String(f.url.path.dropFirst(rp.count)) : f.url.path)
                n.children = f.diagnostics.map { ProblemNode(url: f.url, d: $0) }
                return n
            }
        }
        let selKey = outline.selectedRow >= 0 ? itemKey(outline.item(atRow: outline.selectedRow)) : nil
        outline.reloadData()
        expandAll()
        if let selKey {
            for row in 0..<outline.numberOfRows where itemKey(outline.item(atRow: row)) == selKey {
                outline.selectRowIndexes([row], byExtendingSelection: false)
                break
            }
        }
        let shownErrors = filtered.reduce(0) { $0 + $1.errorCount }, shownWarnings = filtered.reduce(0) { $0 + $1.warningCount }
        baseSummary = summaryText(errors: shownErrors, warnings: shownWarnings, files: filtered.count)
        updateSummary()
        let (text, hide) = emptyState(filteredEmpty: filtered.isEmpty, sourceEmpty: source.isEmpty)
        emptyLabel.stringValue = text
        emptyLabel.isHidden = !hide
        scroll.isHidden = nodes.isEmpty
        updateScanButton()
        updateDetail()
    }

    private var baseSummary = ""

    private func summaryText(errors: Int, warnings: Int, files: Int) -> String {
        func plural(_ n: Int, _ s: String) -> String { "\(n) \(s)\(n == 1 ? "" : "s")" }
        if tab == .project {
            switch scanState {
            case .idle: return files == 0 ? "Not scanned" : "\(plural(errors, "error")) · \(plural(warnings, "warning")) in open files — press Scan for the whole project"
            case .running: return scanProgress
            case .done:
                let counts = files == 0 ? "No problems" : "\(plural(errors, "error")) · \(plural(warnings, "warning")) · \(plural(files, "file"))"
                return scanCancelled ? counts + " (scan cancelled)" : counts
            }
        }
        return errors + warnings == 0 && files == 0 ? "No problems" : "\(plural(errors, "error")) · \(plural(warnings, "warning"))"
    }

    private func emptyState(filteredEmpty: Bool, sourceEmpty: Bool) -> (String, Bool) {
        guard filteredEmpty else { return ("", false) }
        if tab == .project {
            switch scanState {
            case .idle: return ("Press Scan to check the whole project (vendor, node_modules and public/build are skipped)", true)
            case .running: return ("Scanning…", true)
            case .done: return (sourceEmpty ? "No problems found in the project" : "No problems match the filters", true)
            }
        }
        return (sourceEmpty ? "No problems in the current file" : "No problems match the filters", true)
    }

    private func updateSummary() {
        summary.stringValue = baseSummary + (evalNote.map { "  —  " + $0 } ?? "")
        if tab == .project, scanState == .running { summary.stringValue = scanProgress }
    }

    var emptyText: String { emptyLabel.stringValue }
    var statusText: String { summary.stringValue }

    private func itemKey(_ item: Any?) -> String? {
        switch item {
        case let n as ProblemNode: return n.key
        case let f as ProblemFileNode: return "f:" + f.file.url.path
        case let g as ProblemGroupNode: return g.id
        default: return nil
        }
    }

    private func expandAll() {
        func expand(_ item: NSObject) {
            guard let key = itemKey(item), !collapsed.contains(key) else { return }
            outline.expandItem(item)
            for c in (item as? ProblemGroupNode)?.children ?? [] where c is ProblemGroupNode { expand(c) }
        }
        for n in nodes { expand(n) }
    }

    // MARK: Outline

    private func children(of item: Any?) -> [NSObject] {
        switch item {
        case nil: return nodes
        case let f as ProblemFileNode: return f.children
        case let g as ProblemGroupNode: return g.children
        default: return []
        }
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { children(of: item).count }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { children(of: item)[index] }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { item is ProblemFileNode || item is ProblemGroupNode }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        if let k = itemKey(notification.userInfo?["NSObject"]) { collapsed.insert(k) }
    }
    func outlineViewItemDidExpand(_ notification: Notification) {
        if let k = itemKey(notification.userInfo?["NSObject"]) { collapsed.remove(k) }
    }
    func outlineViewSelectionDidChange(_ notification: Notification) { updateDetail() }

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
        } else if let g = item as? ProblemGroupNode {
            let (img, tint) = Self.severityImage(g.severity)
            cell.icon.image = img
            cell.icon.contentTintColor = tint
            cell.primary.stringValue = g.title
            cell.primary.font = .systemFont(ofSize: 12, weight: .semibold)
            cell.primary.textColor = fg
            cell.secondary.stringValue = "\(g.count)"
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
            if evaluated[p.key] != nil { tail = "✦ " + tail }
            cell.secondary.stringValue = tail
            cell.secondary.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
            cell.secondary.textColor = dim
        }
        cell.needsLayout = true
        return cell
    }

    // MARK: Context menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menuItem = nil
        guard outline.clickedRow >= 0, let item = outline.item(atRow: outline.clickedRow) as? NSObject else { return }
        menuItem = item
        let count = problemNodes(under: item).count
        let title = item is ProblemNode ? "Evaluate with Claude" : "Evaluate \(count) problem\(count == 1 ? "" : "s") with Claude"
        let ev = NSMenuItem(title: title, action: #selector(evaluateClicked), keyEquivalent: "")
        ev.target = self
        menu.addItem(ev)
        if item is ProblemNode, onFixWithClaude != nil {
            let fix = NSMenuItem(title: "Fix with Claude…", action: #selector(fixClicked), keyEquivalent: "")
            fix.target = self
            menu.addItem(fix)
        }
    }

    @objc private func evaluateClicked() { if let item = menuItem { evaluate(item: item) } }

    @objc private func fixClicked() {
        guard outline.clickedRow >= 0, let p = outline.item(atRow: outline.clickedRow) as? ProblemNode else { return }
        onFixWithClaude?(p.url, p.d)
    }

    @objc private func activate() {
        let row = outline.clickedRow >= 0 ? outline.clickedRow : outline.selectedRow
        guard row >= 0, let item = outline.item(atRow: row) else { return }
        if let p = item as? ProblemNode { openFile(p.url, p.d.line, p.d.column) }
        else if item is ProblemFileNode || item is ProblemGroupNode {
            if outline.isItemExpanded(item) { outline.collapseItem(item) } else { outline.expandItem(item) }
        }
    }

    // MARK: Claude evaluation

    private func relPath(_ url: URL) -> String { TerminalBridge.relativePath(url, root: root) }

    private func problemNodes(under item: Any) -> [ProblemNode] {
        switch item {
        case let p as ProblemNode: return [p]
        case let f as ProblemFileNode: return f.children.compactMap { $0 as? ProblemNode }
        case let g as ProblemGroupNode: return g.children.flatMap { problemNodes(under: $0) }
        default: return []
        }
    }

    /// The still-valid answer for a problem: dropped when the text of its line (or the message) has changed since it was evaluated.
    private func answer(for n: ProblemNode) -> ProblemAnswer? {
        guard let ck = evaluated[n.key], let a = ProblemAnswerCache.shared.get(ck) else { return nil }
        let ref = ProblemRef(id: 0, url: n.url, relPath: "", d: n.d, fileText: textProvider?(n.url))
        guard ck == n.url.path + "|" + ProblemEvaluator.fingerprint(ref) else { evaluated[n.key] = nil; return nil }
        return a
    }

    func evaluateSelection() {
        guard outline.selectedRow >= 0, let item = outline.item(atRow: outline.selectedRow) else { return }
        evaluate(item: item)
    }

    /// One Claude call for the problem, or for up to 20 of the problems under a file / group row (those without an answer yet).
    private func evaluate(item: Any) {
        let single = item is ProblemNode
        let pending = problemNodes(under: item).filter { !evaluating.contains($0.key) && (single || answer(for: $0) == nil) }
        guard !pending.isEmpty else { return }
        let batch = Array(pending.prefix(ProblemEvaluator.maxPerCall))
        let more = pending.count - batch.count
        var texts: [String: String?] = [:]
        func text(_ u: URL) -> String? {
            if let t = texts[u.path] { return t }
            let t = textProvider?(u)
            texts[u.path] = t
            return t
        }
        let refs = batch.enumerated().map { ProblemRef(id: $0.offset + 1, url: $0.element.url, relPath: relPath($0.element.url), d: $0.element.d, fileText: text($0.element.url)) }
        for n in batch { evaluating.insert(n.key); failures[n.key] = nil }
        evalNote = "Asking Claude about \(batch.count) problem\(batch.count == 1 ? "" : "s")…"
        updateSummary(); updateDetail()
        let finish: (Result<[Int: ProblemAnswer], ClaudeCLI.Failure>) -> Void = { [weak self] result in
            guard let self else { return }
            self.currentProcess = nil
            for n in batch { self.evaluating.remove(n.key) }
            switch result {
            case .failure(let f):
                for n in batch { self.failures[n.key] = f.message }
                self.evalNote = "Claude failed"
            case .success(let answers):
                var got = 0
                for (i, n) in batch.enumerated() {
                    if let a = answers[i + 1] {
                        let ck = n.url.path + "|" + ProblemEvaluator.fingerprint(refs[i])
                        ProblemAnswerCache.shared.set(ck, a)
                        self.evaluated[n.key] = ck
                        got += 1
                    } else { self.failures[n.key] = "No answer for this problem." }
                }
                self.evalNote = "\(got) evaluated" + (more > 0 ? ", \(more) more not evaluated — evaluate again" : "")
            }
            self.reload()
        }
        if let o = evaluateOverride { o(refs, finish) } else { currentProcess = ProblemEvaluator.evaluate(refs, completion: finish) }
    }

    private func updateDetail() {
        guard outline.selectedRow >= 0, let n = outline.item(atRow: outline.selectedRow) as? ProblemNode else {
            detail.show(problem: nil, path: "", answer: nil, state: .idle, snippet: nil)
            return
        }
        let state: ProblemsDetailPane.State = evaluating.contains(n.key) ? .evaluating : (failures[n.key].map { .failed($0) } ?? .idle)
        let snippet = textProvider?(n.url).flatMap { FixWithClaude.snippet(of: $0, around: n.d.line, context: 3)?.text }
        detail.show(problem: (n.url, n.d), path: relPath(n.url), answer: answer(for: n), state: state, snippet: snippet)
    }

    private func applySelected() {
        guard outline.selectedRow >= 0, let n = outline.item(atRow: outline.selectedRow) as? ProblemNode,
              let a = answer(for: n), let old = a.oldText, let new = a.newText else { return }
        if applyFix?(n.url, old, new) == true {
            evaluated[n.key] = nil
            evalNote = "Fix applied"
        } else {
            evalNote = "Could not apply: the code no longer matches exactly once"
        }
        updateSummary(); updateDetail()
    }

    // MARK: Test support

    /// Rows as plain strings (for headless checks).
    var rowDescriptions: [String] {
        (0..<outline.numberOfRows).map { r in
            let it = outline.item(atRow: r)
            if let f = it as? ProblemFileNode { return "FILE \(f.relative) e\(f.file.errorCount) w\(f.file.warningCount)" }
            if let g = it as? ProblemGroupNode { return "GROUP \(g.title) (\(g.count))" }
            if let p = it as? ProblemNode { return "  \(p.d.severity) \(p.d.line):\(p.d.column) \(p.d.message)" }
            return "?"
        }
    }

    @discardableResult
    func selectRow(containing text: String) -> Bool {
        for (r, d) in rowDescriptions.enumerated() where d.contains(text) {
            outline.selectRowIndexes([r], byExtendingSelection: false)
            updateDetail()
            return true
        }
        return false
    }

    func snapshot(to path: String, size: NSSize = NSSize(width: 900, height: 300)) {
        view.frame = NSRect(origin: .zero, size: size)
        layoutSubviews()
        view.layoutSubtreeIfNeeded()
        outline.reloadData(); expandAll()
        outline.layoutSubtreeIfNeeded()
        scroll.layoutSubtreeIfNeeded()
        outline.noteNumberOfRowsChanged()
        for row in 0..<outline.numberOfRows { _ = outline.view(atColumn: 0, row: row, makeIfNecessary: true) }
        detail.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
