import AppKit

/// Bottom-panel "Feature Map": what the project does, where it lives and how you reach it, in the owner's words.
/// Left: features grouped by area (search, "Needs you" filter) plus an "Unmapped files" row. Right: the selected feature's summary,
/// entry points, files and the accepted agent changes that touched it. Flat tables, reused cells, no timers.
final class FeatureMapPanel: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate, NSSearchFieldDelegate, NSTextFieldDelegate, NSMenuDelegate {
    enum ListRow: Equatable { case group(String, Int), feature(String), unmapped(Int) }
    enum DetailRow { case file(String), session(LedgerSession), unmapped(String) }
    enum Tab: Int { case files = 0, history = 1 }

    let view = FeatureRootView()
    let map: FeatureMap
    private let root: URL
    var openFile: ((URL, Int) -> Void)?
    var projectFiles: () -> [String] = { [] }
    var sessions: () -> [LedgerSession] = { [] }
    /// Called with the number of features that need the owner's review (tool badge).
    var onAttention: ((Int) -> Void)?
    var clock: () -> Date = { Date() }
    /// Shows the Features tool window (set by the window).
    var reveal: (() -> Void)?

    private let search = NSSearchField()
    private let scope = NSSegmentedControl(labels: ["All", "Needs you"], trackingMode: .selectOne, target: nil, action: nil)
    private let addButton = NSButton()
    private let moreButton = NSButton()
    private let listTable = SpeedTableView()
    private let listScroll = NSScrollView()
    private let divider = NSView()
    private let nameField = NSTextField()
    private let statusLabel = NSTextField(labelWithString: "")
    private let confirmButton = NSButton(title: "Confirm", target: nil, action: nil)
    private let summaryHint = NSTextField(labelWithString: "In your words: what does it do, when, and for whom?")
    private let entryHint = NSTextField(labelWithString: "How you reach it, one per line (route, menu, schedule, command)")
    private let summaryView = NSTextView(), entryView = NSTextView()
    private let summaryScroll = NSScrollView(), entryScroll = NSScrollView()
    private let tabs = NSSegmentedControl(labels: ["Files", "History"], trackingMode: .selectOne, target: nil, action: nil)
    private let addFilesButton = NSButton(title: "Add Files…", target: nil, action: nil)
    private let detailTable = NSTableView()
    private let detailScroll = NSScrollView()
    private let emptyBox = NSView()
    private let emptyTitle = NSTextField(labelWithString: "Know your app without asking an AI.")
    private let emptyBody = NSTextField(wrappingLabelWithString: "Write down what each feature does, where it lives and how you reach it, in your own words.")
    private let emptyAdd = NSButton(title: "Add First Feature", target: nil, action: nil)
    private let emptyScan = NSButton(title: "Scan Laravel Project", target: nil, action: nil)
    private let emptyDraft = NSButton(title: "Or let Claude draft it…", target: nil, action: nil)
    private let banner = NSTextField(labelWithString: "")

    private var rows: [ListRow] = []
    private var detailRows: [DetailRow] = []
    private var selectedID: String?
    private var showUnmapped = false
    private var tab: Tab = .files
    private var dirty = false
    /// Features whose summary the owner has edited or read this session (the second Confirm press commits).
    private var readIDs = Set<String>()
    private var unmappedCache: [String]?
    private var drafting: Process?
    private var sessionCache: [LedgerSession] = []

    init(map: FeatureMap, root: URL) {
        self.map = map
        self.root = root
        super.init()
        search.placeholderString = "Search features, files, entry points"
        search.controlSize = .small
        search.delegate = self
        scope.controlSize = .small
        scope.selectedSegment = 0
        scope.target = self; scope.action = #selector(scopeChanged)
        for (b, sym, tip, act) in [(addButton, "plus", "New feature", #selector(addFeature)), (moreButton, "ellipsis.circle", "More", #selector(showMore(_:)))] {
            b.image = NSImage(systemSymbolName: sym, accessibilityDescription: tip)
            b.isBordered = false; b.toolTip = tip; b.target = self; b.action = act
        }
        let col = NSTableColumn(identifier: .init("f")); col.resizingMask = .autoresizingMask
        listTable.addTableColumn(col)
        listTable.headerView = nil; listTable.rowHeight = 22
        listTable.dataSource = self; listTable.delegate = self
        listTable.backgroundColor = .clear; listTable.style = .plain
        listScroll.documentView = listTable; listScroll.hasVerticalScroller = true; listScroll.drawsBackground = false
        let dcol = NSTableColumn(identifier: .init("d")); dcol.resizingMask = .autoresizingMask
        detailTable.addTableColumn(dcol)
        detailTable.headerView = nil; detailTable.rowHeight = 20
        detailTable.dataSource = self; detailTable.delegate = self
        detailTable.target = self; detailTable.doubleAction = #selector(detailDoubleClicked)
        detailTable.allowsMultipleSelection = true
        detailTable.backgroundColor = .clear; detailTable.style = .plain
        detailScroll.documentView = detailTable; detailScroll.hasVerticalScroller = true; detailScroll.drawsBackground = false
        let ctx = NSMenu(); ctx.delegate = self
        detailTable.menu = ctx
        nameField.font = .systemFont(ofSize: 12, weight: .semibold)
        nameField.isBordered = false; nameField.drawsBackground = false; nameField.focusRingType = .none
        nameField.placeholderString = "New feature"
        nameField.delegate = self
        statusLabel.font = .systemFont(ofSize: 10.5); statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        confirmButton.bezelStyle = .rounded; confirmButton.controlSize = .small
        confirmButton.target = self; confirmButton.action = #selector(confirmPressed)
        confirmButton.keyEquivalent = ""
        for h in [summaryHint, entryHint] { h.font = .systemFont(ofSize: 10.5); h.textColor = .secondaryLabelColor; h.lineBreakMode = .byTruncatingTail }
        for (tv, sc) in [(summaryView, summaryScroll), (entryView, entryScroll)] {
            tv.isRichText = false; tv.allowsUndo = true
            tv.isAutomaticQuoteSubstitutionEnabled = false; tv.isAutomaticDashSubstitutionEnabled = false; tv.isAutomaticTextReplacementEnabled = false
            tv.font = .systemFont(ofSize: 12); tv.isVerticallyResizable = true; tv.autoresizingMask = [.width]
            tv.textContainerInset = NSSize(width: 4, height: 4); tv.delegate = self
            sc.documentView = tv; sc.hasVerticalScroller = true; sc.borderType = .bezelBorder
        }
        entryView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        tabs.controlSize = .small; tabs.selectedSegment = 0; tabs.target = self; tabs.action = #selector(tabChanged)
        addFilesButton.bezelStyle = .rounded; addFilesButton.controlSize = .small
        addFilesButton.target = self; addFilesButton.action = #selector(addFilesPressed)
        divider.wantsLayer = true; divider.layer?.backgroundColor = NSColor.separatorColor.cgColor
        banner.font = .systemFont(ofSize: 11); banner.textColor = .systemOrange; banner.lineBreakMode = .byTruncatingTail
        emptyTitle.font = .systemFont(ofSize: 13, weight: .semibold); emptyTitle.alignment = .center
        emptyBody.font = .systemFont(ofSize: 12); emptyBody.textColor = .secondaryLabelColor; emptyBody.alignment = .center
        for b in [emptyAdd, emptyScan, emptyDraft] { b.target = self }
        emptyAdd.action = #selector(addFeature); emptyAdd.bezelStyle = .rounded; emptyAdd.keyEquivalent = "\r"
        emptyScan.action = #selector(scanLaravel); emptyScan.bezelStyle = .rounded
        emptyDraft.action = #selector(draftWithClaude); emptyDraft.isBordered = false
        emptyDraft.contentTintColor = .linkColor
        for v in [emptyTitle, emptyBody, emptyAdd, emptyScan, emptyDraft] as [NSView] { emptyBox.addSubview(v) }
        let all: [NSView] = [search, scope, addButton, moreButton, listScroll, divider, nameField, statusLabel, confirmButton, summaryHint, entryHint,
                             summaryScroll, entryScroll, tabs, addFilesButton, detailScroll, banner, emptyBox]
        for v in all { view.addSubview(v) }
        view.panel = self
        map.onChange = { [weak self] in self?.reload() }
    }

    // MARK: Data

    private var allSessions: [LedgerSession] { sessionCache }

    private func attention(_ f: Feature) -> FeatureAttention { map.attention(of: f, sessions: allSessions) }

    private var unmappedFiles: [String] {
        if let c = unmappedCache { return c }
        let c = map.unmapped(in: projectFiles())
        unmappedCache = c
        return c
    }

    /// Rebuilds everything from the store and the ledger. Cheap: it runs on panel show and on changes, never on a timer.
    func reload() {
        commitEdits()
        sessionCache = sessions()
        unmappedCache = nil
        let q = search.stringValue
        var list = FeatureMap.filter(map.features, query: q)
        if scope.selectedSegment == 1 { list = list.filter { let a = attention($0); return a.needsReview || a.isDraft || !a.missingFiles.isEmpty } }
        rows = []
        if q.trimmingCharacters(in: .whitespaces).isEmpty {
            let groups = Dictionary(grouping: list) { $0.area.isEmpty ? "No area" : $0.area }
            for key in groups.keys.sorted(by: { $0.lowercased() < $1.lowercased() }) {
                let items = groups[key]!.sorted { $0.name.lowercased() < $1.name.lowercased() }
                rows.append(.group(key, items.count))
                rows += items.map { .feature($0.id) }
            }
        } else {
            rows = list.map { .feature($0.id) }
        }
        if !map.features.isEmpty { rows.append(.unmapped(unmappedFiles.count)) }
        listTable.reloadData()
        if showUnmapped, let i = rows.firstIndex(where: { if case .unmapped = $0 { return true } else { return false } }) { listTable.selectRowIndexes([i], byExtendingSelection: false) }
        else if let id = selectedID, let i = rows.firstIndex(of: .feature(id)) { listTable.selectRowIndexes([i], byExtendingSelection: false) }
        else { listTable.deselectAll(nil); if !showUnmapped { selectedID = nil } }
        updateDetail()
        onAttention?(map.needsReviewCount(sessions: allSessions))
        let empty = map.features.isEmpty
        emptyBox.isHidden = !empty
        emptyScan.isHidden = !LaravelFeatureSeeder.isLaravel(root)
        banner.stringValue = map.isReadOnly ? "features file could not be read: it is left untouched, nothing will be saved. Fix or remove it." : ""
        view.needsLayout = true
    }

    private var selectedFeature: Feature? { selectedID.flatMap { id in map.features.first { $0.id == id } } }

    private func updateDetail() {
        let f = selectedFeature
        let editor: [NSView] = [nameField, statusLabel, confirmButton, summaryHint, entryHint, summaryScroll, entryScroll, tabs, addFilesButton]
        if showUnmapped {
            for v in editor { v.isHidden = true }
            statusLabel.isHidden = false
            statusLabel.stringValue = "\(unmappedFiles.count) files no feature claims. Select some and use the right-click menu, or press Return, to assign them."
            detailRows = unmappedFiles.prefix(5000).map { .unmapped($0) }
            detailScroll.isHidden = false
            detailTable.reloadData(); return
        }
        guard let f else {
            for v in editor { v.isHidden = true }
            detailRows = []; detailTable.reloadData()
            detailScroll.isHidden = true
            return
        }
        for v in editor { v.isHidden = false }
        detailScroll.isHidden = false
        if nameField.stringValue != f.name { nameField.stringValue = f.name }
        if summaryView.string != f.summary { summaryView.string = f.summary }
        let e = f.entryPoints.joined(separator: "\n")
        if entryView.string != e { entryView.string = e }
        dirty = false
        let a = attention(f)
        var status = "", color = NSColor.secondaryLabelColor
        if !a.missingFiles.isEmpty { status = "\(a.missingFiles.count) file\(a.missingFiles.count == 1 ? "" : "s") no longer exist\(a.missingFiles.count == 1 ? "s" : "")"; color = .systemRed }
        else if a.needsReview { status = "Code changed since you confirmed it"; color = .systemOrange }
        else if a.isDraft { status = (f.origin == .agent ? "Draft · not yet read by you" : "Draft · not confirmed"); color = .systemPurple }
        else if let d = f.confirmedAt { status = "Confirmed " + Self.day.string(from: d); color = .systemGreen }
        statusLabel.stringValue = status; statusLabel.textColor = color
        confirmButton.title = a.needsReview ? "Still Right: Confirm" : (readIDs.contains(f.id) || !a.isDraft ? "Confirm" : "Read, then Confirm")
        confirmButton.isEnabled = a.isDraft || a.needsReview || f.confirmedAt == nil
        let nHist = map.history(of: f, sessions: allSessions).count
        tabs.setLabel("Files \(f.files.count)", forSegment: 0)
        tabs.setLabel("History \(nHist)", forSegment: 1)
        tabs.selectedSegment = tab.rawValue
        rebuildDetailRows(f)
    }

    private func rebuildDetailRows(_ f: Feature) {
        detailRows = tab == .files ? f.files.map { .file($0) } : map.history(of: f, sessions: allSessions).map { .session($0) }
        detailTable.reloadData()
    }

    static let day: DateFormatter = { let d = DateFormatter(); d.dateFormat = "d MMM yyyy"; return d }()
    private static let stamp: DateFormatter = { let d = DateFormatter(); d.dateFormat = "yyyy-MM-dd HH:mm"; return d }()

    // MARK: Actions

    @objc private func scopeChanged() { reload() }
    @objc private func tabChanged() { tab = Tab(rawValue: tabs.selectedSegment) ?? .files; if let f = selectedFeature { rebuildDetailRows(f) } }
    func controlTextDidChange(_ obj: Notification) { if (obj.object as? NSSearchField) === search { reload() } else { dirty = true; markRead() } }
    func controlTextDidEndEditing(_ obj: Notification) { if (obj.object as? NSTextField) === nameField { commitEdits() } }
    func textDidChange(_ notification: Notification) { dirty = true; if (notification.object as? NSTextView) === summaryView { markRead() } }
    func textDidEndEditing(_ notification: Notification) { commitEdits() }
    private func markRead() { if let id = selectedID { readIDs.insert(id) } }

    /// Saves the edited name, summary and entry points of the selected feature (no-op when unchanged).
    func commitEdits() {
        guard dirty, let id = selectedID, var f = map.features.first(where: { $0.id == id }) else { dirty = false; return }
        dirty = false
        let entries = entryView.string.split(separator: "\n").map(String.init)
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let new = (name.isEmpty ? f.name : name, summaryView.string, entries)
        guard new.0 != f.name || new.1 != f.summary || new.2 != f.entryPoints else { return }
        f.name = new.0; f.summary = new.1; f.entryPoints = new.2
        if f.origin == .agent && f.summary != map.features.first(where: { $0.id == id })?.summary { f.origin = .you }
        map.onChange = nil
        map.update(f)
        map.onChange = { [weak self] in self?.reload() }
        listTable.reloadData()
        if let i = rows.firstIndex(of: .feature(id)) { listTable.selectRowIndexes([i], byExtendingSelection: false) }
        onAttention?(map.needsReviewCount(sessions: allSessions))
    }

    @objc func addFeature() {
        commitEdits()
        showUnmapped = false
        let f = map.add(Feature.make(name: "New feature", status: .draft, origin: .you))
        selectedID = f.id
        reload()
        view.window?.makeFirstResponder(nameField)
        nameField.selectText(nil)
    }

    @objc private func confirmPressed() { confirmSelected() }

    /// First press on a draft you have not read: focus the summary so you read it; the next press confirms.
    func confirmSelected() {
        commitEdits()
        guard let f = selectedFeature else { return }
        let a = attention(f)
        if f.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            statusLabel.stringValue = "Write a summary in your own words first."; statusLabel.textColor = .systemOrange
            view.window?.makeFirstResponder(summaryView); return
        }
        if a.isDraft && !readIDs.contains(f.id) {
            readIDs.insert(f.id)
            statusLabel.stringValue = "Read it. Fix anything you would not say this way, then press Confirm again."; statusLabel.textColor = .systemPurple
            confirmButton.title = "Confirm as Is"
            view.window?.makeFirstResponder(summaryView); summaryView.selectAll(nil); return
        }
        if map.confirm(id: f.id, now: clock()) { readIDs.remove(f.id) }
    }

    @objc private func revealMapFile() {
        if map.exists { NSWorkspace.shared.activateFileViewerSelecting([map.fileURL]) }
        else { NSWorkspace.shared.open(FeatureMap.directory.deletingLastPathComponent().standardizedFileURL) }
    }

    @objc private func deleteMapFile() {
        let alert = NSAlert()
        alert.messageText = "Delete this project's feature map?"
        alert.informativeText = "All \(map.features.count) features and your summaries are removed (\(map.fileURL.lastPathComponent)). Your code is not touched."
        alert.addButton(withTitle: "Delete"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        selectedID = nil; showUnmapped = false
        map.deleteFile()
    }

    @objc private func deleteFeature() {
        guard let f = selectedFeature else { return }
        let alert = NSAlert()
        alert.messageText = "Delete “\(f.name)”?"
        alert.informativeText = "Its summary, entry points and notes are removed from the feature map. Your code is not touched."
        alert.addButton(withTitle: "Delete"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        selectedID = nil
        map.remove(id: f.id)
    }

    @objc private func showMore(_ sender: NSButton) {
        let m = NSMenu()
        if LaravelFeatureSeeder.isLaravel(root) { m.addItem(withTitle: "Scan Laravel Project (schedule, commands, mail, controllers)", action: #selector(scanLaravel), keyEquivalent: "").target = self }
        let d = m.addItem(withTitle: drafting == nil ? "Draft Unmapped Files with Claude…" : "Cancel Drafting", action: #selector(draftWithClaude), keyEquivalent: "")
        d.target = self
        m.addItem(.separator())
        m.addItem(withTitle: "Reveal Map File in Finder", action: #selector(revealMapFile), keyEquivalent: "").target = self
        m.addItem(withTitle: "Delete This Project's Map…", action: #selector(deleteMapFile), keyEquivalent: "").target = self
        m.addItem(.separator())
        let del = m.addItem(withTitle: "Delete Selected Feature…", action: #selector(deleteFeature), keyEquivalent: "")
        del.target = self; del.isEnabled = selectedFeature != nil
        m.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    }

    /// Adds drafts from the Laravel scan (no AI); returns how many were new.
    @discardableResult
    func scanLaravelNow() -> Int {
        let n = map.addDrafts(LaravelFeatureSeeder.seed(root: root))
        statusLabel.isHidden = false
        return n
    }

    @objc private func scanLaravel() {
        let n = scanLaravelNow()
        banner.stringValue = n == 0 ? "Nothing new found." : "Added \(n) draft features. They are drafts: read each one and press Confirm."
        banner.textColor = .secondaryLabelColor
        view.needsLayout = true
    }

    @objc private func draftWithClaude() {
        if let p = drafting { p.terminate(); drafting = nil; banner.stringValue = ""; return }
        let files = unmappedFiles
        guard !files.isEmpty else { banner.stringValue = "Every project file is already in a feature."; banner.textColor = .secondaryLabelColor; view.needsLayout = true; return }
        banner.stringValue = "Drafting from \(min(files.count, 600)) unmapped files… (choose More ▸ Cancel Drafting to stop)"
        banner.textColor = .secondaryLabelColor
        let prompt = FeatureMap.draftPrompt(projectName: root.lastPathComponent, files: files, existing: map.features)
        drafting = ClaudeCLI.run(prompt: prompt, model: "sonnet", timeout: 180) { [weak self] result in
            guard let self else { return }
            self.drafting = nil
            switch result {
            case .success(let text):
                let drafts = FeatureMap.parseDrafts(text)
                let n = self.map.addDrafts(drafts)
                self.banner.stringValue = drafts.isEmpty ? "Claude's reply had no features. Nothing was changed." : "Added \(n) draft features. Read each one, then Confirm."
            case .failure(let e):
                self.banner.stringValue = "Claude couldn't draft features: \(e.message). Nothing was changed."
            }
            self.view.needsLayout = true
        }
    }

    @objc private func addFilesPressed() {
        guard let f = selectedFeature else { return }
        let p = NSOpenPanel()
        p.directoryURL = root; p.canChooseFiles = true; p.canChooseDirectories = true; p.allowsMultipleSelection = true
        p.prompt = "Add to “\(f.name)”"
        guard p.runModal() == .OK else { return }
        let base = root.standardizedFileURL.path + "/"
        let rels = p.urls.compactMap { u -> String? in
            let path = u.standardizedFileURL.path
            guard path.hasPrefix(base) else { return nil }
            let rel = String(path.dropFirst(base.count))
            return LaravelFS.isDir(path) ? rel + "/" : rel
        }
        map.assign(rels, to: f.id)
    }

    /// Adds project-relative paths (dropped from the tree, or picked) to the selected feature.
    func addPaths(_ rels: [String]) { if let id = selectedID { map.assign(rels, to: id) } }

    @objc private func detailDoubleClicked() { openDetail(row: detailTable.clickedRow) }

    func openDetail(row: Int) {
        guard detailRows.indices.contains(row) else { return }
        switch detailRows[row] {
        case .file(let p): if !p.hasSuffix("/"), !p.contains("*") { openFile?(root.appendingPathComponent(p), 1) }
        case .unmapped(let p): openFile?(root.appendingPathComponent(p), 1)
        case .session(let s): if let r = s.files.first(where: { _ in true }) { openFile?(root.appendingPathComponent(r.rel), 1) }
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if let m = self.menu(for: detailTable.clickedRow) { for i in m.items { m.removeItem(i); menu.addItem(i) } }
    }

    /// Right-click on the detail table: assign unmapped files, or remove a claimed file.
    func menu(for row: Int) -> NSMenu? {
        let m = NSMenu()
        guard detailRows.indices.contains(row) else { return nil }
        if !detailTable.selectedRowIndexes.contains(row) { detailTable.selectRowIndexes([row], byExtendingSelection: false) }
        switch detailRows[row] {
        case .unmapped:
            let sub = NSMenu()
            for f in map.features.prefix(60) { let i = sub.addItem(withTitle: f.name, action: #selector(assignChosen(_:)), keyEquivalent: ""); i.target = self; i.representedObject = f.id }
            sub.addItem(.separator())
            let n = sub.addItem(withTitle: "New Feature from These Files", action: #selector(assignToNew), keyEquivalent: ""); n.target = self
            let parent = m.addItem(withTitle: "Assign to Feature", action: nil, keyEquivalent: ""); parent.submenu = sub
        case .file:
            let i = m.addItem(withTitle: "Remove from Feature", action: #selector(removeSelectedFiles), keyEquivalent: ""); i.target = self
        case .session: return nil
        }
        return m
    }

    private var selectedUnmapped: [String] {
        detailTable.selectedRowIndexes.compactMap { if detailRows.indices.contains($0), case .unmapped(let p) = detailRows[$0] { return p } else { return nil } }
    }

    @objc private func assignChosen(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String else { return }
        map.assign(selectedUnmapped, to: id)
    }

    @objc private func assignToNew() {
        let paths = selectedUnmapped
        guard !paths.isEmpty else { return }
        let dir = (paths[0] as NSString).deletingLastPathComponent
        let f = map.add(Feature.make(name: dir.isEmpty ? "New feature" : ((dir as NSString).lastPathComponent), files: paths, status: .draft, origin: .you))
        showUnmapped = false; selectedID = f.id
        reload()
        view.window?.makeFirstResponder(nameField); nameField.selectText(nil)
    }

    @objc private func removeSelectedFiles() {
        guard var f = selectedFeature else { return }
        let drop = Set(detailTable.selectedRowIndexes.compactMap { i -> String? in if detailRows.indices.contains(i), case .file(let p) = detailRows[i] { return p } else { return nil } })
        f.files.removeAll { drop.contains($0) }
        map.update(f)
    }

    // MARK: Selection and tables

    func numberOfRows(in tableView: NSTableView) -> Int { tableView === listTable ? rows.count : detailRows.count }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard (notification.object as? NSTableView) === listTable else { return }
        commitEdits()
        let r = listTable.selectedRow
        guard rows.indices.contains(r) else { return }
        switch rows[r] {
        case .feature(let id): selectedID = id; showUnmapped = false
        case .unmapped: selectedID = nil; showUnmapped = true
        case .group: return
        }
        if let f = selectedFeature, attention(f).needsReview { tab = .history }
        updateDetail()
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        tableView === listTable && rows.indices.contains(row) && { if case .group = rows[row] { return true } else { return false } }()
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { !self.tableView(tableView, isGroupRow: row) }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if tableView === listTable, rows.indices.contains(row), case .group = rows[row] { return 18 }
        return tableView === listTable ? 22 : 20
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("fcell")
        let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? FeatureCell) ?? { let c = FeatureCell(); c.identifier = id; return c }()
        let fg = Theme.foreground, dim = Theme.isDark ? NSColor(white: 0.62, alpha: 1) : NSColor(white: 0.40, alpha: 1)
        func line(_ parts: [(String, NSColor, NSFont)]) -> NSAttributedString {
            let o = NSMutableAttributedString()
            for (t, c, f) in parts { o.append(NSAttributedString(string: t, attributes: [.foregroundColor: c, .font: f])) }
            return o
        }
        cell.flag.stringValue = ""
        cell.icon.image = nil
        if tableView === listTable, rows.indices.contains(row) {
            switch rows[row] {
            case .group(let name, let n):
                cell.text.attributedStringValue = line([(name.uppercased() + "  \(n)", dim, .systemFont(ofSize: 10.5, weight: .semibold))])
            case .unmapped(let n):
                cell.setIcon("circle.dotted", .tertiaryLabelColor)
                cell.text.attributedStringValue = line([("Unmapped files", fg, .systemFont(ofSize: 12)), ("  \(n)", dim, .systemFont(ofSize: 11))])
            case .feature(let fid):
                guard let f = map.features.first(where: { $0.id == fid }) else { break }
                let a = attention(f)
                let (sym, col): (String, NSColor) = !a.missingFiles.isEmpty ? ("exclamationmark.triangle.fill", .systemRed)
                    : a.needsReview ? ("exclamationmark.circle.fill", .systemOrange) : a.isDraft ? ("circle.dashed", .systemPurple) : ("checkmark.circle.fill", .systemGreen)
                cell.setIcon(sym, col)
                var nameFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
                if a.isDraft { nameFont = NSFontManager.shared.convert(nameFont, toHaveTrait: .italicFontMask) }
                let searching = !search.stringValue.trimmingCharacters(in: .whitespaces).isEmpty
                let excerpt = searching ? f.area : f.summary.replacingOccurrences(of: "\n", with: " ")
                cell.text.attributedStringValue = line([(f.name, fg, nameFont), ("   " + String(excerpt.prefix(90)), dim, .systemFont(ofSize: 11))])
                var flag = "\(f.files.count) file\(f.files.count == 1 ? "" : "s")"
                if !a.missingFiles.isEmpty { flag = "\(a.missingFiles.count) missing" }
                else if let s = a.changedSince.first { flag = "changed " + Self.ago(s.updated) }
                cell.flag.stringValue = flag
                cell.flag.textColor = !a.missingFiles.isEmpty ? .systemRed : a.needsReview ? .systemOrange : .tertiaryLabelColor
            }
        } else if detailRows.indices.contains(row) {
            switch detailRows[row] {
            case .file(let p):
                let missing = !p.contains("*") && !FileManager.default.fileExists(atPath: root.appendingPathComponent(p).path)
                cell.setIcon(p.hasSuffix("/") ? "folder" : (p.contains("*") ? "asterisk" : "doc"), missing ? .systemRed : .secondaryLabelColor)
                cell.text.attributedStringValue = line([(p, missing ? .systemRed : fg, .systemFont(ofSize: 12))])
                cell.flag.stringValue = missing ? "missing" : ""
                cell.flag.textColor = .systemRed
            case .unmapped(let p):
                cell.setIcon("circle.dotted", .tertiaryLabelColor)
                cell.text.attributedStringValue = line([(p, fg, .systemFont(ofSize: 12))])
            case .session(let s):
                cell.setIcon("book.closed", .secondaryLabelColor)
                var parts: [(String, NSColor, NSFont)] = [(Self.stamp.string(from: s.updated) + "  ", dim, .monospacedSystemFont(ofSize: 11, weight: .regular)), (s.title, fg, .systemFont(ofSize: 12, weight: .semibold))]
                if !s.note.isEmpty { parts.append(("  " + s.note.replacingOccurrences(of: "\n", with: " ").prefix(80), dim, .systemFont(ofSize: 11))) }
                cell.text.attributedStringValue = line(parts)
            }
        }
        cell.needsLayout = true
        return cell
    }

    static func ago(_ d: Date, now: Date = Date()) -> String {
        let s = Int(now.timeIntervalSince(d))
        if s < 3600 { return "\(max(1, s / 60))m ago" }
        if s < 86_400 { return "\(s / 3600)h ago" }
        return "\(s / 86_400)d ago"
    }

    // MARK: File tree menu

    /// Project-relative path of `url` (folders get a trailing "/"), or nil outside the project.
    func relativePath(_ url: URL) -> String? {
        let base = root.standardizedFileURL.path + "/", p = url.standardizedFileURL.path
        guard p.hasPrefix(base) else { return nil }
        return String(p.dropFirst(base.count)) + (LaravelFS.isDir(p) ? "/" : "")
    }

    /// "Show in Feature Map" and "Add to Feature" for the right-clicked file or folder.
    func treeMenuItems(for url: URL) -> [NSMenuItem] {
        guard let rel = relativePath(url) else { return [] }
        let show = NSMenuItem(title: "Which Feature Is This?", action: #selector(showOwner(_:)), keyEquivalent: "")
        show.target = self; show.representedObject = rel
        let add = NSMenuItem(title: "Add to Feature", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for f in map.features.prefix(40) {
            let i = sub.addItem(withTitle: f.name, action: #selector(addToFeature(_:)), keyEquivalent: "")
            i.target = self; i.representedObject = [rel, f.id]
        }
        if map.features.isEmpty { sub.addItem(withTitle: "No features yet", action: nil, keyEquivalent: "").isEnabled = false }
        add.submenu = sub
        return [show, add]
    }

    @objc private func showOwner(_ item: NSMenuItem) { if let rel = item.representedObject as? String { revealOwner(of: rel) } }

    @objc private func addToFeature(_ item: NSMenuItem) {
        guard let a = item.representedObject as? [String], a.count == 2 else { return }
        map.assign([a[0]], to: a[1])
        select(featureID: a[1])
        reveal?()
    }

    /// Selects the feature that owns `rel`; for a file nothing claims, the Unmapped row.
    func revealOwner(of rel: String) {
        commitEdits()
        if let f = map.features(claiming: rel).first { select(featureID: f.id) } else { selectUnmapped() }
        reveal?()
    }

    // MARK: State for tests and snapshots

    var rowDescriptions: [String] {
        rows.map {
            switch $0 {
            case .group(let n, let c): return "GROUP \(n) \(c)"
            case .unmapped(let n): return "UNMAPPED \(n)"
            case .feature(let id): return "FEATURE " + (map.features.first { $0.id == id }?.name ?? id)
            }
        }
    }
    var detailDescriptions: [String] { detailRows.map { switch $0 { case .file(let p): return "FILE " + p; case .unmapped(let p): return "UNMAPPED " + p; case .session(let s): return "SESSION " + s.title } } }
    var summaryText: String { summaryView.string }
    var bannerText: String { banner.stringValue }
    var statusText: String { statusLabel.stringValue }
    var confirmTitle: String { confirmButton.title }
    func select(featureID id: String) { showUnmapped = false; selectedID = id; reload() }
    func selectUnmapped() { showUnmapped = true; selectedID = nil; reload() }
    func setSummary(_ s: String) { summaryView.string = s; dirty = true; markRead() }
    func setTab(_ t: Tab) { tab = t; if let f = selectedFeature { updateDetail(); _ = f } }

    func snapshot(to path: String, size: NSSize = NSSize(width: 900, height: 270)) {
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded(); view.layout()
        listTable.reloadData(); detailTable.reloadData()
        for r in 0..<listTable.numberOfRows { _ = listTable.view(atColumn: 0, row: r, makeIfNecessary: true) }
        for r in 0..<detailTable.numberOfRows { _ = detailTable.view(atColumn: 0, row: r, makeIfNecessary: true) }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    /// Fallback layout when the panel is narrower than this: the list alone.
    fileprivate func layoutPanel(_ b: NSRect) {
        let w = b.width, h = b.height
        let leftW = max(280, w * 0.40)
        let bannerH: CGFloat = banner.stringValue.isEmpty ? 0 : 16
        banner.frame = NSRect(x: 8, y: 2, width: w - 16, height: bannerH)
        let top = bannerH + 4
        search.frame = NSRect(x: 8, y: top + 2, width: leftW - 160, height: 22)
        scope.frame = NSRect(x: leftW - 146, y: top + 2, width: 118, height: 22)
        addButton.frame = NSRect(x: leftW - 26, y: top + 2, width: 22, height: 22)
        listScroll.frame = NSRect(x: 0, y: top + 30, width: leftW, height: max(0, h - top - 30))
        divider.frame = NSRect(x: leftW, y: top, width: 1, height: max(0, h - top))
        let rx = leftW + 10, rw = max(0, w - leftW - 18)
        let confirmW: CGFloat = 120
        nameField.frame = NSRect(x: rx, y: top + 4, width: max(60, rw * 0.46), height: 18)
        confirmButton.frame = NSRect(x: rx + rw - confirmW - 26, y: top + 2, width: confirmW, height: 22)
        moreButton.frame = NSRect(x: rx + rw - 22, y: top + 2, width: 22, height: 22)
        statusLabel.frame = NSRect(x: nameField.frame.maxX + 6, y: top + 5, width: max(0, confirmButton.frame.minX - nameField.frame.maxX - 12), height: 14)
        let hy = top + 28
        let sw = rw * 0.58 - 4
        summaryHint.frame = NSRect(x: rx, y: hy, width: sw, height: 14)
        entryHint.frame = NSRect(x: rx + sw + 8, y: hy, width: rw - sw - 8, height: 14)
        let th: CGFloat = min(84, max(48, h * 0.30))
        summaryScroll.frame = NSRect(x: rx, y: hy + 16, width: sw, height: th)
        entryScroll.frame = NSRect(x: rx + sw + 8, y: hy + 16, width: rw - sw - 8, height: th)
        let ty = summaryScroll.frame.maxY + 6
        tabs.frame = NSRect(x: rx, y: ty, width: 170, height: 20)
        addFilesButton.frame = NSRect(x: rx + rw - 90, y: ty - 1, width: 90, height: 22)
        addFilesButton.isHidden = addFilesButton.isHidden || tab != .files
        let editorVisible = !summaryScroll.isHidden
        let dy = editorVisible ? ty + 26 : top + 26
        if !editorVisible { statusLabel.frame = NSRect(x: rx, y: top + 6, width: rw, height: 14) }
        detailScroll.frame = NSRect(x: leftW + 1, y: dy, width: max(0, w - leftW - 1), height: max(0, h - dy))
        emptyBox.frame = NSRect(x: 0, y: 0, width: w, height: h)
        let cx = w / 2, cy = h / 2
        emptyTitle.frame = NSRect(x: cx - 220, y: cy - 62, width: 440, height: 18)
        emptyBody.frame = NSRect(x: cx - 220, y: cy - 40, width: 440, height: 34)
        emptyAdd.frame = NSRect(x: cx - 60 - (emptyScan.isHidden ? 0 : 78), y: cy + 4, width: 130, height: 26)
        emptyScan.frame = NSRect(x: emptyAdd.frame.maxX + 8, y: cy + 4, width: 150, height: 26)
        emptyDraft.frame = NSRect(x: cx - 100, y: cy + 38, width: 200, height: 20)
    }
}

/// Frame layout host (the panel positions its own subviews).
final class FeatureRootView: NSView {
    weak var panel: FeatureMapPanel?
    override var isFlipped: Bool { true }
    override func layout() { super.layout(); panel?.layoutPanel(bounds) }
}

/// One reused row: icon, one attributed line, and a right-aligned flag.
final class FeatureCell: NSTableCellView {
    let icon = NSImageView()
    let text = NSTextField(labelWithString: "")
    let flag = NSTextField(labelWithString: "")
    override init(frame: NSRect) {
        super.init(frame: frame)
        text.lineBreakMode = .byTruncatingTail
        flag.font = .systemFont(ofSize: 10.5); flag.alignment = .right; flag.textColor = .tertiaryLabelColor
        icon.imageScaling = .scaleProportionallyDown
        addSubview(icon); addSubview(text); addSubview(flag)
    }
    required init?(coder: NSCoder) { fatalError() }
    func setIcon(_ symbol: String, _ color: NSColor) {
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
        icon.contentTintColor = color
    }
    override func layout() {
        super.layout()
        let h = bounds.height, hasIcon = icon.image != nil
        icon.frame = hasIcon ? NSRect(x: 4, y: (h - 14) / 2, width: 14, height: 14) : .zero
        let flagW: CGFloat = flag.stringValue.isEmpty ? 0 : min(110, flag.intrinsicContentSize.width + 4)
        let tx: CGFloat = hasIcon ? 24 : 4
        flag.frame = NSRect(x: bounds.width - flagW - 6, y: (h - 14) / 2, width: flagW, height: 14)
        text.frame = NSRect(x: tx, y: (h - 17) / 2, width: max(0, bounds.width - tx - flagW - 10), height: 17)
    }
}
