import AppKit

/// Bottom-panel "Claude Changes": per agent session, the files it changed (+/- lines, time) with Accept / Reject per file,
/// per session and for everything. Clicking a file opens the side-by-side diff (baseline vs current); double-click opens the file.
final class ChangeReviewPanel: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    enum Row { case session(ChangeReviewStore.Session), file(ChangeReviewStore.Session, ChangeReviewStore.Entry) }

    let view = NSView()
    private let table = SpeedTableView()
    private let speed = SpeedSearch()
    private let summary = NSTextField(labelWithString: "")
    private let store: ChangeReviewStore
    private(set) var rows: [Row] = []
    var openFile: ((URL) -> Void)?
    /// Asks before a bulk reject (session / all). Tests replace it.
    var confirm: (String) -> Bool = { message in
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = "Files are restored to the text they had before the agent changed them."
        alert.addButton(withTitle: "Reject")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
    /// Shows the diff for a file (default: a window; tests / headless record the call instead).
    var showDiff: (ChangeReviewStore.Entry) -> Void = { _ in }
    private static let time: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f }()

    init(store: ChangeReviewStore) {
        self.store = store
        super.init()
        showDiff = { [weak self] e in self?.presentDiffWindow(e) }
        let column = NSTableColumn(identifier: .init("c"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 20
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(clicked)
        table.doubleAction = #selector(doubleClicked)
        speed.attach(to: table) { [weak self] row in
            guard let r = self?.rows, r.indices.contains(row) else { return nil }
            if case .file(_, let e) = r[row] { return e.rel }
            return nil
        }
        table.speedSearch = speed
        table.usesAlternatingRowBackgroundColors = false
        table.backgroundColor = .clear
        table.style = .plain
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        func button(_ title: String, _ action: Selector) -> NSButton {
            let b = NSButton(title: title, target: self, action: action)
            b.bezelStyle = .rounded
            b.controlSize = .small
            return b
        }
        summary.font = .systemFont(ofSize: 11)
        summary.textColor = .secondaryLabelColor
        summary.setContentHuggingPriority(.init(1), for: .horizontal)
        summary.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        let bar = NSStackView(views: [summary, button("Accept", #selector(acceptSelected)), button("Reject", #selector(rejectSelected)),
                                      button("Accept All", #selector(acceptAllTapped)), button("Reject All", #selector(rejectAllTapped)),
                                      button("Clear", #selector(clearTapped))])
        bar.spacing = 6
        bar.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        for v in [bar, scroll] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(v) }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.topAnchor), bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor), bar.heightAnchor.constraint(equalToConstant: 30),
            scroll.topAnchor.constraint(equalTo: bar.bottomAnchor), scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        reload()
    }

    // MARK: Data

    func reload() {
        rows = []
        for s in store.sessions.reversed() where !s.entries.isEmpty {
            rows.append(.session(s))
            for e in s.entries.sorted(by: { $0.last > $1.last }) { rows.append(.file(s, e)) }
        }
        table.reloadData()
        let pending = store.pendingEntries
        let a = pending.reduce(0) { $0 + $1.entry.added }, r = pending.reduce(0) { $0 + $1.entry.removed }
        summary.stringValue = rows.isEmpty ? "No agent changes yet. Edits made while an agent terminal tab is active are listed here."
            : "\(store.pendingFileCount) pending file(s)  +\(a) \u{2212}\(r)"
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let field = NSTextField(labelWithString: "")
        field.lineBreakMode = .byTruncatingMiddle
        field.attributedStringValue = Self.text(for: rows[row])
        return field
    }

    static func text(for row: Row) -> NSAttributedString {
        let out = NSMutableAttributedString()
        func add(_ s: String, _ color: NSColor, bold: Bool = false) {
            out.append(NSAttributedString(string: s, attributes: [
                .font: bold ? NSFont.systemFont(ofSize: 12, weight: .semibold) : NSFont.systemFont(ofSize: 12), .foregroundColor: color]))
        }
        switch row {
        case .session(let s):
            let pending = s.pending
            add("\u{2726} \(s.title)", .labelColor, bold: true)
            add("   started \(time.string(from: s.started))   \(pending.count) pending of \(s.entries.count) file(s)  ", .secondaryLabelColor)
            add("+\(pending.reduce(0) { $0 + $1.added })", .systemGreen)
            add(" \u{2212}\(pending.reduce(0) { $0 + $1.removed })", .systemRed)
        case .file(_, let e):
            let dim: NSColor = e.state == .pending ? .labelColor : .secondaryLabelColor
            add("    \(e.rel)", dim)
            add("   +\(e.added)", e.state == .pending ? .systemGreen : .secondaryLabelColor)
            add(" \u{2212}\(e.removed)", e.state == .pending ? .systemRed : .secondaryLabelColor)
            add("   \(time.string(from: e.last))", .secondaryLabelColor)
            switch e.state {
            case .accepted: add("   accepted", .secondaryLabelColor)
            case .rejected: add("   rejected", .secondaryLabelColor)
            case .pending:
                if let n = e.note { add("   \(n)", .systemOrange) } else if e.source == .head { add("   vs HEAD", .secondaryLabelColor) }
            }
        }
        return out
    }

    // MARK: Actions

    private var selectedRow: Row? { table.selectedRow >= 0 && table.selectedRow < rows.count ? rows[table.selectedRow] : nil }

    /// Click on a file row opens its diff (a click on a session row only selects it for the Accept / Reject buttons).
    @objc private func clicked() { click(row: table.clickedRow) }
    func click(row: Int) {
        guard row >= 0, row < rows.count, case .file(_, let e) = rows[row] else { return }
        showDiff(e)
    }

    @objc private func doubleClicked() {
        let r = table.clickedRow
        guard r >= 0, r < rows.count, case .file(_, let e) = rows[r] else { return }
        openFile?(e.url)
    }

    func accept(_ row: Row) {
        switch row {
        case .session(let s): store.acceptAll(in: s)
        case .file(_, let e): store.acceptFile(e)
        }
    }

    func reject(_ row: Row) {
        switch row {
        case .session(let s):
            guard confirm("Reject all \(s.pending.count) pending change(s) by \(s.title)?") else { return }
            report(store.rejectAll(in: s))
        case .file(_, let e): if !store.rejectFile(e) { report(1) }
        }
    }

    private func report(_ failed: Int) {
        guard failed > 0 else { return }
        summary.stringValue = "\(failed) file(s) could not be restored (no baseline or write failed)"
    }

    @objc private func acceptSelected() { if let r = selectedRow { accept(r) } }
    @objc private func rejectSelected() { if let r = selectedRow { reject(r) } }
    @objc private func acceptAllTapped() { store.acceptAll() }
    @objc private func rejectAllTapped() {
        guard store.pendingFileCount > 0, confirm("Reject all \(store.pendingFileCount) pending file(s) changed by agents?") else { return }
        report(store.rejectAll())
    }
    @objc private func clearTapped() { store.clearResolved() }

    // MARK: Diff

    /// (old, new, file extension) the diff window shows for an entry: baseline vs what is on disk now.
    func diffContents(for e: ChangeReviewStore.Entry) -> (old: String, new: String, ext: String) {
        (e.baseline ?? "", HunkActions.readDisk(e.url)?.text ?? "", e.url.pathExtension)
    }

    private var diffWindows: [String: NSWindow] = [:]

    private func presentDiffWindow(_ e: ChangeReviewStore.Entry) {
        guard !AppEnv.headless else { return }
        let c = diffContents(for: e)
        let window = diffWindows[e.path] ?? NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 640),
                                                      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Claude changes \u{2013} \(e.rel)"
        let diff = SideBySideDiffView(frame: NSRect(x: 0, y: 0, width: 1100, height: 640))
        diff.autoresizingMask = [.width, .height]
        let baseTitle = e.baseline == nil ? "No baseline" : "Before Claude (\(e.source?.rawValue ?? "baseline"))"
        diff.show(old: c.old, new: c.new, oldTitle: baseTitle, newTitle: "Current", fileExtension: c.ext)
        window.contentView = diff
        if diffWindows[e.path] == nil { DialogMemory.remember(window, as: "ClaudeChangesDiff"); window.center(); diffWindows[e.path] = window }
        window.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Window wiring

extension ProjectWindow {
    /// Creates the review store, the "Claude Changes" bottom panel and the gutter hooks (called once per window).
    func installChangeReview(root: URL) {
        guard changeReview == nil else { return }
        let store = ChangeReviewStore(root: root)
        store.activeAgent = { [weak self] in self?.terminalPanel?.activeAgentTab }
        store.preimage = { [weak self] path in
            guard let tab = self?.editors[path], !tab.isDirty, !tab.isLargeFile else { return nil }
            return tab.serializedText()
        }
        store.restore = { [weak self] url, text in
            guard let tab = self?.editors[url.standardizedFileURL.path] else { return HunkActions.writeDisk(text, to: url) }
            let tv = tab.textView
            tv.replaceUndoable(NSRange(location: 0, length: (tv.string as NSString).length), with: text)
            return tab.save()
        }
        let panel = ChangeReviewPanel(store: store)
        panel.openFile = { [weak self] url in self?.open(url) }
        changeReview = store
        changeReviewPanel = panel
        registerToolPanel(id: "claude-changes", title: "Claude Changes", view: panel.view)
        let binder = ChangeReviewGutter(store: store, window: self)
        changeReviewGutter = binder
        store.onChange = { [weak self, weak panel] in
            panel?.reload()
            self?.changeReviewGutter?.sync()
            let n = self?.changeReview?.pendingFileCount ?? 0
            self?.setToolPanelBadge(n > 0 ? "\(n)" : nil, for: "claude-changes")
        }
        ChangeReviewGutter.start()
    }

    func showClaudeChanges() { showToolPanel("claude-changes") }
}

/// Points each open tab's git gutter at the review baseline while the file has a pending agent change, so the existing hunk
/// markers and popover show "changes since the agent started", with Accept / Reject on the popover.
final class ChangeReviewGutter {
    private weak var window: ProjectWindow?
    private let store: ChangeReviewStore
    private static var started = false
    private static var live = NSHashTable<ChangeReviewGutter>.weakObjects()

    init(store: ChangeReviewStore, window: ProjectWindow) {
        self.store = store
        self.window = window
        Self.live.add(self)
    }

    /// A tab that opens later picks up its baseline (once, for all windows).
    static func start() {
        guard !started else { return }
        started = true
        EditorEvents.onOpen { _ in DispatchQueue.main.async { live.allObjects.forEach { $0.sync() } } }
    }

    func sync() {
        guard let window else { return }
        for (path, tab) in window.editors {
            guard let c = GitGutter.controller(for: tab) else { continue }
            let entry = store.pendingEntry(VCSKind.canonical(path))
            guard let base = entry?.baseline else {
                c.reviewBaseline = nil; c.onReviewAccept = nil; c.onReviewRejected = nil
                continue
            }
            c.reviewBaseline = base
            c.onReviewAccept = { [weak self, weak tab] hunk, text in
                guard let self, tab != nil else { return }
                self.store.acceptHunk(path: path, old: hunk.old, current: text)
            }
            c.onReviewRejected = { [weak self, weak tab] in
                guard let self, let tab else { return }
                // The buffer edit is one undo step; saving makes the disk match so the agent's change is really gone.
                _ = tab.save()
                self.store.noteChanges([path])
            }
        }
    }
}
