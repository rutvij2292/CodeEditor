import AppKit

enum GitLogAction {
    case copyHash, checkout, createBranch, cherryPick, cherryPickMany([GitCommit]), revert, reset(GitResetMode)
}

private final class LogTable: NSTableView {
    var onEscape: (() -> Void)?
}

/// "Log" tab of the Git panel: paged commit list with search, per-commit files and a side-by-side diff.
final class GitLogView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate, NSSearchFieldDelegate {
    var pageSize = 200
    private(set) var commits: [GitCommit] = []
    private(set) var files: [GitFileChange] = []
    private(set) var exhausted = false
    private(set) var historyPath: String?
    /// Ref the log walks from ("HEAD" = current branch); chosen with the Branch control.
    private(set) var revision = "HEAD"
    var onAction: ((GitLogAction, GitCommit) -> Void)?
    /// Fired when a page (or the file list / diff of the selection) finished loading; used by tests and the panel.
    var onIdle: (() -> Void)?

    private var repo: GitRepo
    private let reader = DispatchQueue(label: "git.log", qos: .userInitiated, attributes: .concurrent)
    private let search = NSSearchField()
    private let branchButton = NSButton(title: "", target: nil, action: nil)
    private let historyBar = NSStackView()
    private let historyLabel = NSTextField(labelWithString: "")
    private let commitTable = LogTable()
    private let fileTable = NSTableView()
    private let diffView = SideBySideDiffView()
    private let diffMessage = NSTextField(labelWithString: "")
    private let status = NSTextField(labelWithString: "")
    private let split = NSSplitView()
    private let rightSplit = NSSplitView()
    private var generation = 0
    private var loading = false
    private var query = ""
    private var follow = false
    private var debounce: Timer?
    private var fileToken = 0, diffToken = 0
    private var positioned = false
    private var preferredFile: String?
    private var graphRows: [GitGraphRow] = []
    private var myName = ""

    /// The graph only makes sense for an unfiltered walk (a search or file history skips commits, so lanes would lie).
    private var showsGraph: Bool { query.trimmingCharacters(in: .whitespaces).isEmpty && historyPath == nil }

    private func commitsChanged() {
        graphRows = showsGraph ? GitGraphLayout.rows(for: commits) : []
        let col = commitTable.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("graph"))
        col?.isHidden = !showsGraph
        if showsGraph, let col { col.width = GitGraphCell.width(forLanes: graphRows.map(\.laneCount).max() ?? 1) }
    }

    private static let dateFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yy, h:mm a"
        return f
    }()

    init(repo: GitRepo) {
        self.repo = repo
        super.init(frame: .zero)
        build()
        applyTheme()
        let r0 = repo
        reader.async { let n = (try? r0.text(["config", "user.name"]))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""; DispatchQueue.main.async { [weak self] in self?.myName = n; self?.commitTable.reloadData() } }
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: Theme.didChange, object: nil)
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: build

    private func build() {
        search.placeholderString = "Search message, author or hash"
        search.controlSize = .small
        search.font = .systemFont(ofSize: 12)
        search.delegate = self
        search.translatesAutoresizingMaskIntoConstraints = false

        branchButton.bezelStyle = .recessed
        branchButton.controlSize = .small
        branchButton.font = .systemFont(ofSize: 11, weight: .medium)
        branchButton.imagePosition = .imageLeading
        branchButton.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil)
        branchButton.target = self
        branchButton.action = #selector(showBranchMenu(_:))
        branchButton.translatesAutoresizingMaskIntoConstraints = false
        updateBranchTitle()

        historyLabel.font = .systemFont(ofSize: 11, weight: .medium)
        historyLabel.lineBreakMode = .byTruncatingHead
        let clear = NSButton(title: "Show All", target: self, action: #selector(clearHistory))
        clear.bezelStyle = .rounded
        clear.controlSize = .small
        clear.font = .systemFont(ofSize: 11)
        historyBar.setViews([historyLabel, clear], in: .leading)
        historyBar.orientation = .horizontal
        historyBar.spacing = 8
        historyBar.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        historyBar.isHidden = true

        for (id, title, w) in [("graph", "", 60), ("subject", "Commit", 260), ("author", "Author", 120), ("date", "Date", 130)] {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            c.title = title
            c.width = CGFloat(w)
            c.minWidth = id == "subject" ? 100 : (id == "graph" ? 24 : 50)
            if id == "graph" { c.maxWidth = 130 }
            c.resizingMask = id == "subject" ? .autoresizingMask : .userResizingMask
            commitTable.addTableColumn(c)
        }
        commitTable.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        commitTable.rowHeight = 22
        commitTable.intercellSpacing = NSSize(width: 6, height: 0)
        commitTable.allowsMultipleSelection = true
        commitTable.dataSource = self
        commitTable.delegate = self
        commitTable.usesAlternatingRowBackgroundColors = false
        let menu = NSMenu()
        menu.delegate = self
        commitTable.menu = menu
        let commitScroll = NSScrollView()
        commitScroll.documentView = commitTable
        commitScroll.hasVerticalScroller = true
        commitScroll.drawsBackground = false

        status.font = .systemFont(ofSize: 11)
        status.lineBreakMode = .byTruncatingTail

        let left = NSView()
        for v in [branchButton, search, historyBar, commitScroll, status] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; left.addSubview(v) }
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: left.topAnchor, constant: 6),
            branchButton.leadingAnchor.constraint(equalTo: left.leadingAnchor, constant: 8),
            branchButton.centerYAnchor.constraint(equalTo: search.centerYAnchor),
            branchButton.widthAnchor.constraint(lessThanOrEqualToConstant: 190),
            search.leadingAnchor.constraint(equalTo: branchButton.trailingAnchor, constant: 8),
            search.trailingAnchor.constraint(equalTo: left.trailingAnchor, constant: -8),
            historyBar.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 4),
            historyBar.leadingAnchor.constraint(equalTo: left.leadingAnchor),
            historyBar.trailingAnchor.constraint(equalTo: left.trailingAnchor),
            commitScroll.topAnchor.constraint(equalTo: historyBar.bottomAnchor, constant: 4),
            commitScroll.leadingAnchor.constraint(equalTo: left.leadingAnchor),
            commitScroll.trailingAnchor.constraint(equalTo: left.trailingAnchor),
            commitScroll.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -2),
            status.leadingAnchor.constraint(equalTo: left.leadingAnchor, constant: 8),
            status.trailingAnchor.constraint(equalTo: left.trailingAnchor, constant: -8),
            status.bottomAnchor.constraint(equalTo: left.bottomAnchor, constant: -3),
            left.widthAnchor.constraint(greaterThanOrEqualToConstant: 260),
        ])

        let fileCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        fileCol.resizingMask = .autoresizingMask
        fileTable.addTableColumn(fileCol)
        fileTable.headerView = nil
        fileTable.rowHeight = 20
        fileTable.dataSource = self
        fileTable.delegate = self
        let fileScroll = NSScrollView()
        fileScroll.documentView = fileTable
        fileScroll.hasVerticalScroller = true
        fileScroll.drawsBackground = false
        fileScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true

        let diffHost = NSView()
        diffMessage.font = .systemFont(ofSize: 13)
        diffMessage.alignment = .center
        diffMessage.stringValue = "Select a commit"
        diffView.pickMode = .none
        diffView.isHidden = true
        for v in [diffView, diffMessage] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; diffHost.addSubview(v) }
        NSLayoutConstraint.activate([
            diffView.topAnchor.constraint(equalTo: diffHost.topAnchor),
            diffView.bottomAnchor.constraint(equalTo: diffHost.bottomAnchor),
            diffView.leadingAnchor.constraint(equalTo: diffHost.leadingAnchor),
            diffView.trailingAnchor.constraint(equalTo: diffHost.trailingAnchor),
            diffMessage.centerXAnchor.constraint(equalTo: diffHost.centerXAnchor),
            diffMessage.centerYAnchor.constraint(equalTo: diffHost.centerYAnchor),
            diffMessage.widthAnchor.constraint(lessThanOrEqualTo: diffHost.widthAnchor, constant: -40),
            diffHost.heightAnchor.constraint(greaterThanOrEqualToConstant: 100),
        ])

        rightSplit.isVertical = false
        rightSplit.dividerStyle = .thin
        rightSplit.addArrangedSubview(fileScroll)
        rightSplit.addArrangedSubview(diffHost)
        rightSplit.setHoldingPriority(.init(260), forSubviewAt: 0)
        split.isVertical = true
        split.dividerStyle = .thin
        split.addArrangedSubview(left)
        split.addArrangedSubview(rightSplit)
        split.setHoldingPriority(.init(260), forSubviewAt: 0)
        split.translatesAutoresizingMaskIntoConstraints = false
        addSubview(split)
        NSLayoutConstraint.activate([
            split.topAnchor.constraint(equalTo: topAnchor), split.bottomAnchor.constraint(equalTo: bottomAnchor),
            split.leadingAnchor.constraint(equalTo: leadingAnchor), split.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    override func layout() {
        super.layout()
        if !positioned, bounds.width > 200, bounds.height > 100 {
            positioned = true
            split.layoutSubtreeIfNeeded()
            split.setPosition(min(640, bounds.width * 0.55), ofDividerAt: 0)
            rightSplit.layoutSubtreeIfNeeded()
            rightSplit.setPosition(min(110, rightSplit.bounds.height * 0.25), ofDividerAt: 0)
        }
    }

    @objc private func applyTheme() {
        wantsLayer = true
        layer?.backgroundColor = Theme.background.cgColor
        commitTable.backgroundColor = Theme.background
        fileTable.backgroundColor = Theme.background
        diffMessage.textColor = Theme.gutter
        status.textColor = Theme.gutter
        historyLabel.textColor = Theme.foreground
        commitTable.reloadData()
        fileTable.reloadData()
    }

    // MARK: public

    var selectedCommit: GitCommit? {
        let r = commitTable.selectedRow
        return r >= 0 && r < commits.count ? commits[r] : nil
    }

    /// Selected commits, oldest first (the order a cherry-pick sequence must apply them in).
    var selectedCommitsOldestFirst: [GitCommit] {
        commitTable.selectedRowIndexes.sorted(by: >).filter { $0 < commits.count }.map { commits[$0] }
    }

    func focusSearch() { window?.makeFirstResponder(search) }
    var searchIsEditing: Bool { search.currentEditor() != nil && !search.stringValue.isEmpty }

    /// Reloads the first page, keeping the filter. The selected commit stays selected when it is still listed.
    func reload() {
        generation += 1
        let keep = selectedCommit?.hash
        let gen = generation
        loading = true
        exhausted = false
        let (q, p, f, n, rev) = (query, historyPath, follow, pageSize, revision)
        let repo = repo
        reader.async {
            let r = Result { try repo.log(skip: 0, limit: n, query: q, path: p, follow: f, rev: rev) }
            DispatchQueue.main.async { [weak self] in
                guard let self, gen == self.generation else { return }
                self.loading = false
                switch r {
                case .success(let page):
                    self.commits = page
                    self.commitsChanged()
                    self.exhausted = page.count < n
                    self.commitTable.reloadData()
                    if let keep, let i = page.firstIndex(where: { $0.hash == keep }) {
                        self.commitTable.selectRowIndexes([i], byExtendingSelection: false)
                    } else if !page.isEmpty {
                        self.commitTable.selectRowIndexes([0], byExtendingSelection: false)
                    } else {
                        self.clearSelectionUI(page.isEmpty ? (q.isEmpty ? "No commits" : "No matching commits") : "")
                    }
                    self.updateStatus()
                case .failure(let e):
                    self.commits = []
                    self.commitsChanged()
                    self.commitTable.reloadData()
                    self.clearSelectionUI(e.localizedDescription)
                }
                self.onIdle?()
            }
        }
    }

    // MARK: branch filter

    /// Points the log at another ref ("HEAD", a branch, "origin/x" or a tag) and reloads from the top.
    func setRevision(_ rev: String) {
        revision = rev.isEmpty ? "HEAD" : rev
        updateBranchTitle()
        preferredFile = historyPath
        reload()
        commitTable.scrollRowToVisible(0)
    }

    private func updateBranchTitle() {
        branchButton.title = revision == "HEAD" ? "HEAD" : revision
        branchButton.toolTip = "Branch: \(branchButton.title)"
    }

    @objc private func showBranchMenu(_ sender: NSButton) {
        let repo = repo
        reader.async {
            let list = try? repo.branchList()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.popBranchMenu(list ?? BranchList(), anchor: sender)
            }
        }
    }

    private func popBranchMenu(_ list: BranchList, anchor: NSView) {
        let menu = NSMenu()
        func item(_ title: String, rev: String, in m: NSMenu, checked: Bool = false, star: Bool = false) {
            let i = NSMenuItem(title: title, action: #selector(branchMenuPicked(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = rev
            i.state = checked || rev == revision ? .on : .off
            if star { i.image = NSImage(systemSymbolName: "star.fill", accessibilityDescription: nil) }
            m.addItem(i)
        }
        let select = NSMenuItem(title: "Select…", action: #selector(branchSelectPicker), keyEquivalent: "")
        select.target = self
        menu.addItem(select)
        func submenu(_ title: String, _ names: [String]) {
            let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for n in names { item(n, rev: n, in: sub) }
            parent.submenu = sub
            parent.isEnabled = !names.isEmpty
            menu.addItem(parent)
        }
        submenu("Recent", list.recent)
        menu.addItem(.separator())
        var favs = ["HEAD"]
        let all = Set(list.local.map(\.name) + list.remote.map(\.name))
        for f in ["main", "master", "origin/main", "origin/master"] where all.contains(f) { favs.append(f) }
        for f in BranchFavorites.all(for: repo.root).sorted() where !favs.contains(f) { favs.append(f) }
        for f in favs { item(f, rev: f, in: menu, star: true) }
        menu.addItem(.separator())
        submenu("Local", list.local.map(\.name))
        for remote in list.remotes {
            submenu("\(remote)/…", list.remote.filter { $0.remote == remote }.map(\.name))
        }
        if !list.tags.isEmpty { submenu("Tags", list.tags) }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.height + 2), in: anchor)
    }

    @objc private func branchMenuPicked(_ s: NSMenuItem) {
        if let rev = s.representedObject as? String { setRevision(rev) }
    }

    @objc private func branchSelectPicker() {
        guard let window else { return }
        let repo = repo
        reader.async {
            let list = try? repo.branchList()
            DispatchQueue.main.async { [weak self] in
                guard let self, let list else { return }
                var items = [PickerItem(title: "HEAD", detail: "current branch", symbol: "arrow.triangle.branch") { [weak self] in self?.setRevision("HEAD") }]
                for b in list.local + list.remote {
                    items.append(PickerItem(title: b.name, detail: b.subject, symbol: b.isRemote ? "cloud" : "arrow.triangle.branch") { [weak self] in
                        self?.setRevision(b.name)
                    })
                }
                for t in list.tags { items.append(PickerItem(title: t, detail: "tag", symbol: "tag") { [weak self] in self?.setRevision(t) }) }
                QuickPicker.present(over: window, placeholder: "Show commits of branch or tag", items: items)
            }
        }
    }

    func showHistory(path: String?) {
        historyPath = path
        follow = path != nil
        historyBar.isHidden = path == nil
        historyLabel.stringValue = path.map { "History of \($0)" } ?? ""
        preferredFile = path
        search.stringValue = ""
        query = ""
        reload()
    }

    func setQuery(_ q: String) {
        search.stringValue = q
        query = q
        reload()
    }

    private func loadMore() {
        guard !loading, !exhausted else { return }
        loading = true
        let gen = generation
        let (q, p, f, n, skip, rev) = (query, historyPath, follow, pageSize, commits.count, revision)
        let repo = repo
        reader.async {
            let r = try? repo.log(skip: skip, limit: n, query: q, path: p, follow: f, rev: rev)
            DispatchQueue.main.async { [weak self] in
                guard let self, gen == self.generation else { return }
                self.loading = false
                guard let page = r else { self.exhausted = true; return }
                self.exhausted = page.count < n
                let start = self.commits.count
                self.commits += page
                self.commitTable.insertRows(at: IndexSet(start..<(start + page.count)), withAnimation: [])
                self.commitsChanged()
                if let gi = self.commitTable.tableColumns.firstIndex(where: { $0.identifier.rawValue == "graph" }) {
                    self.commitTable.reloadData(forRowIndexes: IndexSet(0..<self.commits.count), columnIndexes: [gi])   // later pages can add lanes
                }
                self.updateStatus()
                self.onIdle?()
            }
        }
    }

    private func updateStatus() {
        status.stringValue = "\(commits.count) commit\(commits.count == 1 ? "" : "s")" + (exhausted ? "" : "+ (scroll for more)")
    }

    @objc private func clearHistory() { showHistory(path: nil) }

    func controlTextDidChange(_ obj: Notification) {
        debounce?.invalidate()
        debounce = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.query = self.search.stringValue
            self.reload()
        }
    }

    // MARK: selection

    private func clearSelectionUI(_ message: String) {
        files = []
        fileTable.reloadData()
        diffView.isHidden = true
        diffMessage.stringValue = message
        diffMessage.isHidden = false
    }

    func tableViewSelectionDidChange(_ n: Notification) {
        if (n.object as? NSTableView) === fileTable { showSelectedFileDiff(); return }
        guard let c = selectedCommit else { return }
        fileToken += 1
        diffToken += 1
        let token = fileToken
        let repo = repo
        reader.async {
            let r = Result { try repo.commitFiles(c.hash) }
            DispatchQueue.main.async { [weak self] in
                guard let self, token == self.fileToken else { return }
                switch r {
                case .success(let list):
                    self.files = list
                    self.fileTable.reloadData()
                    if list.isEmpty { self.clearSelectionUI("No file changes in this commit"); self.onIdle?(); return }
                    var idx = 0
                    if let pf = self.preferredFile {
                        idx = list.firstIndex { $0.path == pf }
                            ?? list.firstIndex { ($0.path as NSString).lastPathComponent == (pf as NSString).lastPathComponent } ?? 0
                    }
                    if self.fileTable.selectedRow == idx { self.showSelectedFileDiff() }
                    else { self.fileTable.selectRowIndexes([idx], byExtendingSelection: false) }
                case .failure(let e): self.clearSelectionUI(e.localizedDescription); self.onIdle?()
                }
            }
        }
    }

    private func showSelectedFileDiff() {
        let r = fileTable.selectedRow
        guard r >= 0, r < files.count, let c = selectedCommit else { return }
        let file = files[r]
        diffToken += 1
        let token = diffToken
        let repo = repo
        reader.async {
            let res = Result { try repo.commitDiffSides(rev: c.hash, file: file) }
            DispatchQueue.main.async { [weak self] in
                guard let self, token == self.diffToken else { return }
                switch res {
                case .success(let sides):
                    self.diffMessage.isHidden = true
                    self.diffView.isHidden = false
                    self.diffView.show(old: sides.old, new: sides.new, oldTitle: "\(c.shortHash)^", newTitle: c.shortHash,
                                       fileExtension: (file.path as NSString).pathExtension)
                case .failure(let e):
                    self.diffView.isHidden = true
                    self.diffMessage.stringValue = e.localizedDescription.hasPrefix("Binary") ? "Binary file: diff not shown" : e.localizedDescription
                    self.diffMessage.isHidden = false
                }
                self.onIdle?()
            }
        }
    }

    // MARK: table

    func numberOfRows(in t: NSTableView) -> Int { t === fileTable ? files.count : commits.count }

    private static func refColor(_ ref: String) -> NSColor {
        if ref.hasPrefix("tag:") { return NSColor(srgbRed: 0.80, green: 0.55, blue: 0.15, alpha: 1) }
        if ref.contains("/") && !ref.hasPrefix("HEAD") { return NSColor(srgbRed: 0.25, green: 0.55, blue: 0.90, alpha: 1) }
        return NSColor(srgbRed: 0.25, green: 0.70, blue: 0.40, alpha: 1)
    }

    func tableView(_ t: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell." + (col?.identifier.rawValue ?? ""))
        let cell = t.makeView(withIdentifier: id, owner: nil) as? NSTextField ?? {
            let f = NSTextField(labelWithString: "")
            f.identifier = id
            f.lineBreakMode = .byTruncatingTail
            f.font = .systemFont(ofSize: 12)
            return f
        }()
        if t === fileTable {
            guard row < files.count else { return cell }
            let f = files[row]
            let color: NSColor = f.status == "A" ? NSColor.systemGreen : f.status == "D" ? NSColor.systemGray : NSColor.systemBlue
            let s = NSMutableAttributedString(string: f.status + "  ", attributes: [.foregroundColor: color, .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)])
            let name = f.oldPath.map { "\($0) \u{2192} \(f.path)" } ?? f.path
            s.append(NSAttributedString(string: name, attributes: [.foregroundColor: Theme.foreground, .font: NSFont.systemFont(ofSize: 12)]))
            cell.attributedStringValue = s
            return cell
        }
        guard row < commits.count else { return cell }
        if row >= commits.count - 25 { loadMore() }
        let c = commits[row]
        switch col?.identifier.rawValue {
        case "graph":
            let gid = NSUserInterfaceItemIdentifier("cell.graph.view")
            let g = t.makeView(withIdentifier: gid, owner: nil) as? GitGraphCell ?? { let v = GitGraphCell(); v.identifier = gid; return v }()
            g.row = row < graphRows.count ? graphRows[row] : GitGraphRow()
            g.isMerge = c.parents.count > 1
            g.needsDisplay = true
            return g
        case "subject":
            let s = NSMutableAttributedString()
            for ref in c.refs {
                let name = ref.replacingOccurrences(of: "HEAD -> ", with: "\u{25B8} ")
                s.append(NSAttributedString(string: " \(name) ", attributes: [
                    .font: NSFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: Self.refColor(ref),
                    .backgroundColor: Self.refColor(ref).withAlphaComponent(0.16)]))
                s.append(NSAttributedString(string: " "))
            }
            let isMerge = c.parents.count > 1
            s.append(NSAttributedString(string: c.subject, attributes: [.foregroundColor: isMerge ? Theme.gutter : Theme.foreground, .font: NSFont.systemFont(ofSize: 12)]))
            cell.attributedStringValue = s
        case "author":
            let mine = !myName.isEmpty && c.author == myName
            cell.stringValue = c.author
            cell.textColor = c.parents.count > 1 ? Theme.gutter : Theme.foreground
            cell.font = .systemFont(ofSize: 12, weight: mine ? .bold : .regular)
        case "date":
            cell.stringValue = Self.dateFormat.string(from: Date(timeIntervalSince1970: c.timestamp))
            cell.textColor = Theme.gutter
        default:
            cell.stringValue = c.shortHash
            cell.textColor = Theme.gutter
            cell.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        }
        return cell
    }

    // MARK: context menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let clicked = commitTable.clickedRow
        if clicked >= 0 { commitTable.selectRowIndexes([clicked], byExtendingSelection: false) }
        guard selectedCommit != nil else { return }
        let picked = selectedCommitsOldestFirst
        func add(_ title: String, _ tag: Int, to m: NSMenu) {
            let i = NSMenuItem(title: title, action: #selector(menuPicked(_:)), keyEquivalent: "")
            i.target = self
            i.tag = tag
            m.addItem(i)
        }
        add("Copy Hash", 0, to: menu)
        menu.addItem(.separator())
        add("Checkout Revision…", 1, to: menu)
        add("Create Branch Here…", 2, to: menu)
        menu.addItem(.separator())
        add(picked.count > 1 ? "Cherry-Pick \(picked.count) Commits…" : "Cherry-Pick…", 3, to: menu)
        if picked.count == 1 { add("Revert Commit", 4, to: menu) }
        guard picked.count == 1 else { return }
        let reset = NSMenuItem(title: "Reset Current Branch to Here", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        add("Soft (keep changes staged)", 5, to: sub)
        add("Mixed (keep changes unstaged)", 6, to: sub)
        add("Hard (discard changes)…", 7, to: sub)
        reset.submenu = sub
        menu.addItem(reset)
    }

    @objc private func menuPicked(_ s: NSMenuItem) {
        guard let c = selectedCommit else { return }
        let action: GitLogAction
        switch s.tag {
        case 0: action = .copyHash
        case 1: action = .checkout
        case 2: action = .createBranch
        case 3:
            let picked = selectedCommitsOldestFirst
            action = picked.count > 1 ? .cherryPickMany(picked) : .cherryPick
        case 4: action = .revert
        case 5: action = .reset(.soft)
        case 6: action = .reset(.mixed)
        default: action = .reset(.hard)
        }
        onAction?(action, c)
    }
}
