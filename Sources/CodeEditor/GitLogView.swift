import AppKit

enum GitLogAction {
    case copyHash, checkout, createBranch, cherryPick, cherryPickMany([GitCommit]), revert, reset(GitResetMode)
}

/// Soft rounded selection (no full-width blue bar); text colors stay put because the row never reports "emphasized".
private final class LogRowView: NSTableRowView {
    override var isEmphasized: Bool { get { false } set {} }
    override func drawSelection(in dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 4, dy: 1)
        NSColor.controlAccentColor.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect: r, xRadius: 5, yRadius: 5).fill()
    }
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
    private(set) var filter = GitLogFilter()
    var onAction: ((GitLogAction, GitCommit) -> Void)?
    /// Fired when a page (or the file list / diff of the selection) finished loading; used by tests and the panel.
    var onIdle: (() -> Void)?

    private var repo: GitRepo
    private let reader = DispatchQueue(label: "git.log", qos: .userInitiated, attributes: .concurrent)
    private let search = NSSearchField()
    private let branchButton = NSButton(title: "", target: nil, action: nil)
    private let userButton = NSButton(title: "", target: nil, action: nil)
    private let dateButton = NSButton(title: "", target: nil, action: nil)
    private let pathButton = NSButton(title: "", target: nil, action: nil)
    private let filterBar = NSStackView()
    private let details = NSTextView()
    private var detailsToken = 0
    private var dateChoice = "All"
    private let historyBar = NSStackView()
    /// A hidden stack view still reserves its height; this pins it to zero until a file history is shown.
    private lazy var historyCollapse = historyBar.heightAnchor.constraint(equalToConstant: 0)
    private let historyLabel = NSTextField(labelWithString: "")
    private let commitTable = LogTable()
    private let fileTable = NSTableView()
    private var diffView: CommitDiffView?
    /// Display rows of the changed-files tree: folders (with depth and file count) and files (index into `files`).
    private enum FileRow { case folder(name: String, depth: Int, count: Int); case file(index: Int, depth: Int) }
    private var fileRows: [FileRow] = []
    /// The host shows this view in an editor tab (a file's diff never opens a separate window).
    var onShowFileDiff: ((CommitDiffView) -> Void)?
    private let status = NSTextField(labelWithString: "")
    private let split = NSSplitView()
    private let rightSplit = NSSplitView()
    private var generation = 0
    private var loading = false
    private var query = ""
    private var follow = false
    private var debounce: Timer?
    private var fileToken = 0
    private var positioned = false
    private var preferredFile: String?
    private var graphRows: [GitGraphRow] = []
    private var myName = ""

    /// The graph only makes sense for an unfiltered walk (a search or file history skips commits, so lanes would lie).
    private var showsGraph: Bool { query.trimmingCharacters(in: .whitespaces).isEmpty && historyPath == nil && !filter.isActive }

    private func commitsChanged() {
        graphRows = showsGraph ? GitGraphLayout.rows(for: commits) : []
        let col = commitTable.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("graph"))
        col?.isHidden = !showsGraph
        if showsGraph, let col { let w = GitGraphCell.width(forLanes: graphRows.map(\.laneCount).max() ?? 1); col.minWidth = w; col.maxWidth = w; col.width = w }
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
        search.placeholderString = "Search commits"
        search.controlSize = .small
        search.font = .systemFont(ofSize: 12)
        search.delegate = self
        search.focusRingType = .none
        search.translatesAutoresizingMaskIntoConstraints = false
        search.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        search.setContentHuggingPriority(.defaultLow, for: .horizontal)

        for (b, sel) in [(branchButton, #selector(showBranchMenu(_:))), (userButton, #selector(showUserMenu(_:))),
                         (dateButton, #selector(showDateMenu(_:))), (pathButton, #selector(showPathMenu(_:)))] {
            b.target = self
            b.action = sel
            b.setContentHuggingPriority(.required, for: .horizontal)
            b.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        }
        updateBranchTitle()
        updateFilterTitles()

        // One slim, borderless toolbar row (PhpStorm style): search, then flat text filters.
        filterBar.setViews([search, branchButton, userButton, dateButton, pathButton], in: .leading)
        filterBar.orientation = .horizontal
        filterBar.spacing = 12
        filterBar.alignment = .centerY
        filterBar.edgeInsets = NSEdgeInsets(top: 7, left: 8, bottom: 7, right: 8)
        search.widthAnchor.constraint(lessThanOrEqualToConstant: 200).isActive = true
        search.widthAnchor.constraint(greaterThanOrEqualToConstant: 90).isActive = true

        details.isEditable = false
        details.drawsBackground = false
        details.textContainerInset = NSSize(width: 10, height: 8)
        details.font = .monospacedSystemFont(ofSize: 12, weight: .regular)

        historyLabel.font = .systemFont(ofSize: 11, weight: .medium)
        historyLabel.lineBreakMode = .byTruncatingHead
        let clear = NSButton(title: "Show All", target: self, action: #selector(clearHistory))
        clear.bezelStyle = .rounded
        clear.controlSize = .small
        clear.font = .systemFont(ofSize: 11)
        historyBar.setViews([historyLabel, clear], in: .leading)
        historyBar.orientation = .horizontal
        historyBar.spacing = 8
        historyBar.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 6, right: 8)
        historyBar.isHidden = true
        historyCollapse.isActive = true

        for (id, title, w) in [("graph", "", 60), ("subject", "Commit", 260), ("author", "Author", 110), ("date", "Date", 84)] {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            c.title = title
            c.width = CGFloat(w)
            c.minWidth = id == "subject" ? 100 : (id == "graph" ? 24 : 50)
            if id == "graph" { c.maxWidth = 130 }
            c.resizingMask = id == "subject" ? .autoresizingMask : .userResizingMask
            commitTable.addTableColumn(c)
        }
        commitTable.headerView = nil
        commitTable.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        commitTable.rowHeight = 24
        commitTable.intercellSpacing = NSSize(width: 8, height: 0)
        commitTable.allowsMultipleSelection = true
        commitTable.dataSource = self
        commitTable.delegate = self
        commitTable.usesAlternatingRowBackgroundColors = false
        commitTable.selectionHighlightStyle = .regular
        let menu = NSMenu()
        menu.delegate = self
        commitTable.menu = menu
        let commitScroll = NSScrollView()
        commitScroll.documentView = commitTable
        commitScroll.hasVerticalScroller = true
        commitScroll.drawsBackground = false
        commitScroll.scrollerStyle = .overlay

        status.font = .systemFont(ofSize: 11)

        let left = NSView()
        for v in [filterBar, historyBar, commitScroll] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; left.addSubview(v) }
        NSLayoutConstraint.activate([
            filterBar.topAnchor.constraint(equalTo: left.topAnchor),
            filterBar.leadingAnchor.constraint(equalTo: left.leadingAnchor),
            filterBar.trailingAnchor.constraint(lessThanOrEqualTo: left.trailingAnchor),
            historyBar.topAnchor.constraint(equalTo: filterBar.bottomAnchor),
            historyBar.leadingAnchor.constraint(equalTo: left.leadingAnchor),
            historyBar.trailingAnchor.constraint(equalTo: left.trailingAnchor),
            commitScroll.topAnchor.constraint(equalTo: historyBar.bottomAnchor),
            commitScroll.leadingAnchor.constraint(equalTo: left.leadingAnchor),
            commitScroll.trailingAnchor.constraint(equalTo: left.trailingAnchor),
            commitScroll.bottomAnchor.constraint(equalTo: left.bottomAnchor),
            left.widthAnchor.constraint(greaterThanOrEqualToConstant: 260),
        ])

        let fileCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        fileCol.resizingMask = .autoresizingMask
        fileTable.addTableColumn(fileCol)
        fileTable.headerView = nil
        fileTable.rowHeight = 22
        fileTable.intercellSpacing = NSSize(width: 0, height: 0)
        fileTable.dataSource = self
        fileTable.delegate = self
        fileTable.target = self
        fileTable.doubleAction = #selector(openFileDiff)
        let fileScroll = NSScrollView()
        fileScroll.documentView = fileTable
        fileScroll.hasVerticalScroller = true
        fileScroll.drawsBackground = false
        fileScroll.scrollerStyle = .overlay
        fileScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true

        rightSplit.isVertical = false
        rightSplit.dividerStyle = .thin
        let detailsScroll = NSScrollView()
        detailsScroll.documentView = details
        detailsScroll.hasVerticalScroller = true
        detailsScroll.drawsBackground = false
        detailsScroll.scrollerStyle = .overlay
        detailsScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true
        details.isVerticallyResizable = true
        details.autoresizingMask = [.width]
        // Changed files (a folder tree) on top, the commit message underneath.
        rightSplit.addArrangedSubview(fileScroll)
        rightSplit.addArrangedSubview(detailsScroll)
        rightSplit.setHoldingPriority(.init(250), forSubviewAt: 0)
        rightSplit.setHoldingPriority(.init(260), forSubviewAt: 1)
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
            split.setPosition(min(720, bounds.width * 0.58), ofDividerAt: 0)
            rightSplit.layoutSubtreeIfNeeded()
            rightSplit.setPosition(rightSplit.bounds.height * 0.60, ofDividerAt: 0)
        }
    }

    @objc private func applyTheme() {
        wantsLayer = true
        layer?.backgroundColor = Theme.background.cgColor
        commitTable.backgroundColor = Theme.background
        fileTable.backgroundColor = Theme.background
        status.textColor = Theme.gutter
        details.textColor = Theme.foreground
        historyLabel.textColor = Theme.foreground
        updateBranchTitle()
        updateFilterTitles()
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
        let (q, p, f, n, rev, flt) = (query, historyPath, follow, pageSize, revision, filter)
        let repo = repo
        reader.async {
            let r = Result { try repo.log(skip: 0, limit: n, query: q, path: p, follow: f, rev: rev, filter: flt) }
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

    // MARK: filters

    /// Flat, borderless toolbar filter: dim label with a small chevron; accent-colored while it narrows the list.
    private func flat(_ b: NSButton, _ title: String, active: Bool) {
        let color = active ? NSColor.controlAccentColor : Theme.gutter
        b.isBordered = false
        b.imagePosition = .imageTrailing
        b.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 8, weight: .semibold))
        b.contentTintColor = color
        b.attributedTitle = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: color])
        b.sizeToFit()
    }

    private func updateFilterTitles() {
        flat(userButton, filter.user.map { "User: \($0)" } ?? "User", active: filter.user != nil)
        flat(dateButton, dateChoice == "All" ? "Date" : dateChoice, active: dateChoice != "All")
        flat(pathButton, filter.path.map { "Path: " + ($0 as NSString).lastPathComponent } ?? "Path", active: filter.path != nil)
    }

    private func applyFilter(_ new: GitLogFilter) {
        filter = new
        updateFilterTitles()
        preferredFile = historyPath
        reload()
        commitTable.scrollRowToVisible(0)
    }

    @objc private func showUserMenu(_ sender: NSButton) {
        let repo = repo
        reader.async {
            let names = repo.recentAuthors()
            let me = (try? repo.text(["config", "user.name"]))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let menu = NSMenu()
                func add(_ title: String, _ user: String?, checked: Bool) {
                    let i = NSMenuItem(title: title, action: #selector(self.userPicked(_:)), keyEquivalent: "")
                    i.target = self; i.representedObject = user ?? ""; i.state = checked ? .on : .off
                    menu.addItem(i)
                }
                add("All", nil, checked: self.filter.user == nil)
                if !me.isEmpty { add("Me (\(me))", me, checked: self.filter.user == me) }
                menu.addItem(.separator())
                for n in names where n != me { add(n, n, checked: self.filter.user == n) }
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 2), in: sender)
            }
        }
    }

    @objc private func userPicked(_ s: NSMenuItem) {
        var f = filter
        let v = s.representedObject as? String ?? ""
        f.user = v.isEmpty ? nil : v
        applyFilter(f)
    }

    @objc private func showDateMenu(_ sender: NSButton) {
        let menu = NSMenu()
        for t in ["All", "Last 24 hours", "Last 7 days", "Last 30 days", "Last year"] {
            let i = NSMenuItem(title: t, action: #selector(datePicked(_:)), keyEquivalent: "")
            i.target = self; i.state = t == dateChoice ? .on : .off
            menu.addItem(i)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 2), in: sender)
    }

    @objc private func datePicked(_ s: NSMenuItem) {
        dateChoice = s.title
        let day: TimeInterval = 86_400
        var f = filter
        switch s.title {
        case "Last 24 hours": f.since = Date().addingTimeInterval(-day)
        case "Last 7 days": f.since = Date().addingTimeInterval(-7 * day)
        case "Last 30 days": f.since = Date().addingTimeInterval(-30 * day)
        case "Last year": f.since = Date().addingTimeInterval(-365 * day)
        default: f.since = nil
        }
        applyFilter(f)
    }

    @objc private func showPathMenu(_ sender: NSButton) {
        let menu = NSMenu()
        let all = NSMenuItem(title: "All paths", action: #selector(pathPicked(_:)), keyEquivalent: "")
        all.target = self; all.representedObject = ""; all.state = filter.path == nil ? .on : .off
        menu.addItem(all)
        let choose = NSMenuItem(title: "File or folder…", action: #selector(pathChoose), keyEquivalent: "")
        choose.target = self
        menu.addItem(choose)
        if let p = filter.path {
            menu.addItem(.separator())
            let cur = NSMenuItem(title: p, action: nil, keyEquivalent: ""); cur.state = .on; cur.isEnabled = false
            menu.addItem(cur)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 2), in: sender)
    }

    @objc private func pathPicked(_ s: NSMenuItem) {
        var f = filter
        let v = s.representedObject as? String ?? ""
        f.path = v.isEmpty ? nil : v
        applyFilter(f)
    }

    @objc private func pathChoose() {
        let (alert, field) = GitDialogs.textAlert(title: "Filter by path", info: "A file or folder, relative to the project root.", placeholder: "app/Http/Controllers", button: "Filter")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let v = field.stringValue.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        var f = filter
        f.path = v.isEmpty ? nil : v
        applyFilter(f)
    }

    // MARK: details pane

    private func loadDetails(for c: GitCommit) {
        detailsToken += 1
        let token = detailsToken
        let repo = repo
        reader.async {
            let info = try? repo.commitInfo(hash: c.hash)
            DispatchQueue.main.async { [weak self] in
                guard let self, token == self.detailsToken else { return }
                let out = NSMutableAttributedString()
                func line(_ text: String, font: NSFont, color: NSColor, gap: CGFloat = 0) {
                    let p = NSMutableParagraphStyle(); p.paragraphSpacing = gap
                    out.append(NSAttributedString(string: text + "\n", attributes: [.font: font, .foregroundColor: color, .paragraphStyle: p]))
                }
                let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
                let message = (info?.message ?? c.subject).trimmingCharacters(in: .whitespacesAndNewlines)
                let parts = message.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
                line(parts.first ?? c.subject, font: .monospacedSystemFont(ofSize: 12, weight: .bold), color: Theme.foreground, gap: 6)
                if parts.count > 1, !parts[1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    line(parts[1].trimmingCharacters(in: .whitespacesAndNewlines), font: mono, color: Theme.foreground, gap: 10)
                }
                let when = info.map { Self.dateFormat.string(from: Date(timeIntervalSince1970: $0.authorTime)) } ?? c.relativeDate
                let who = info?.author ?? c.author
                line("\(c.shortHash) \u{00B7} \(who) \u{00B7} \(when)", font: .monospacedSystemFont(ofSize: 11, weight: .regular), color: Theme.gutter)
                self.details.textStorage?.setAttributedString(out)
                self.details.scrollToBeginningOfDocument(nil)
            }
        }
    }

    /// Details pane for several selected commits: their subjects, plus the net-diff note.
    private func loadRangeDetails(_ picked: [GitCommit]) {
        detailsToken += 1
        let out = NSMutableAttributedString()
        let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        out.append(NSAttributedString(string: "\(picked.count) commits selected \u{2014} files show their combined changes\n",
                                      attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold), .foregroundColor: Theme.foreground]))
        for c in picked.reversed() {
            out.append(NSAttributedString(string: "\n\(c.shortHash)  \(c.subject)", attributes: [.font: mono, .foregroundColor: Theme.foreground]))
        }
        details.textStorage?.setAttributedString(out)
        details.scrollToBeginningOfDocument(nil)
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
        flat(branchButton, "Branch: " + (revision == "HEAD" ? "HEAD" : (revision.count > 28 ? String(revision.prefix(27)) + "\u{2026}" : revision)), active: revision != "HEAD")
        branchButton.toolTip = revision
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
        historyCollapse.isActive = path == nil
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
        let (q, p, f, n, skip, rev, flt) = (query, historyPath, follow, pageSize, commits.count, revision, filter)
        let repo = repo
        reader.async {
            let r = try? repo.log(skip: skip, limit: n, query: q, path: p, follow: f, rev: rev, filter: flt)
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
        detailsToken += 1
        files = []
        fileRows = []
        fileTable.reloadData()
        details.string = message
    }

    func tableViewSelectionDidChange(_ n: Notification) {
        if (n.object as? NSTableView) === fileTable { return }
        guard let c = selectedCommit else { return }
        let picked = selectedCommitsOldestFirst
        let multi = picked.count > 1
        if multi { loadRangeDetails(picked) } else { loadDetails(for: c) }
        fileToken += 1
        let token = fileToken
        let repo = repo
        let base = multi ? (picked.first?.parents.first ?? "") : ""
        let head = multi ? (picked.last?.hash ?? c.hash) : c.hash
        reader.async {
            let r = Result { multi ? try repo.rangeFiles(base: base, head: head) : try repo.commitFiles(c.hash) }
            DispatchQueue.main.async { [weak self] in
                guard let self, token == self.fileToken else { return }
                switch r {
                case .success(let list):
                    self.files = list
                    self.fileRows = Self.tree(list)
                    self.fileTable.reloadData()
                    if list.isEmpty { self.clearSelectionUI("No file changes in this commit"); self.onIdle?(); return }
                    if let pf = self.preferredFile,
                       let idx = list.firstIndex(where: { $0.path == pf })
                        ?? list.firstIndex(where: { ($0.path as NSString).lastPathComponent == (pf as NSString).lastPathComponent }) {
                        if let row = self.fileRows.firstIndex(where: { if case .file(let i, _) = $0 { return i == idx }; return false }) {
                            self.fileTable.selectRowIndexes([row], byExtendingSelection: false)
                            self.fileTable.scrollRowToVisible(row)
                        }
                    }
                    self.onIdle?()
                case .failure(let e): self.clearSelectionUI(e.localizedDescription); self.onIdle?()
                }
            }
        }
    }

    /// Double-click on a file: its side-by-side diff opens in an editor tab (steppable across the commit's files).
    @objc private func openFileDiff() {
        let row = fileTable.clickedRow >= 0 ? fileTable.clickedRow : fileTable.selectedRow
        guard row >= 0, row < fileRows.count, case .file(let r, _) = fileRows[row], let c = selectedCommit else { return }
        let v = diffView ?? CommitDiffView(repo: repo)
        diffView = v
        let picked = selectedCommitsOldestFirst
        if picked.count > 1, let oldest = picked.first, let newest = picked.last {
            v.show(commit: newest, files: files, index: r, rangeBase: oldest.parents.first ?? "",
                   rangeLabel: "\(oldest.shortHash)..\(newest.shortHash)")
        } else {
            v.show(commit: c, files: files, index: r)
        }
        onShowFileDiff?(v)
    }

    /// Flattens sorted paths into folder + file rows (every folder expanded, with the number of files beneath it).
    private static func tree(_ list: [GitFileChange]) -> [FileRow] {
        let order = list.indices.sorted { list[$0].path.localizedStandardCompare(list[$1].path) == .orderedAscending }
        var counts: [String: Int] = [:]
        for f in list {
            var prefix = ""
            for part in f.path.split(separator: "/").dropLast() { prefix += part + "/"; counts[prefix, default: 0] += 1 }
        }
        var rows: [FileRow] = []
        var open: [String] = []
        for i in order {
            let comps = list[i].path.split(separator: "/").map(String.init)
            let dirs = Array(comps.dropLast())
            var common = 0
            while common < open.count, common < dirs.count, open[common] == dirs[common] { common += 1 }
            open = Array(open.prefix(common))
            for d in dirs[common...] {
                open.append(d)
                rows.append(.folder(name: d, depth: open.count - 1, count: counts[open.joined(separator: "/") + "/"] ?? 0))
            }
            rows.append(.file(index: i, depth: dirs.count))
        }
        return rows
    }

    /// Short, quiet date: relative within a week, then "21 Aug" / "21 Aug 25".
    private static func shortDate(_ ts: TimeInterval) -> String {
        let d = Date(timeIntervalSince1970: ts), age = Date().timeIntervalSince(d)
        if age < 60 { return "now" }
        if age < 3600 { return "\(Int(age / 60))m ago" }
        if age < 86_400 { return "\(Int(age / 3600))h ago" }
        if age < 7 * 86_400 { return "\(Int(age / 86_400))d ago" }
        let cal = Calendar.current
        return (cal.component(.year, from: d) == cal.component(.year, from: Date()) ? dayMonth : dayMonthYear).string(from: d)
    }
    private static let dayMonth: DateFormatter = { let f = DateFormatter(); f.dateFormat = "d MMM"; return f }()
    private static let dayMonthYear: DateFormatter = { let f = DateFormatter(); f.dateFormat = "d MMM yy"; return f }()

    // MARK: table

    func numberOfRows(in t: NSTableView) -> Int { t === fileTable ? fileRows.count : commits.count }

    func tableView(_ t: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { LogRowView() }

    func tableView(_ t: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard t === fileTable else { return true }
        if row < fileRows.count, case .file = fileRows[row] { return true }
        return false
    }

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
            guard row < fileRows.count else { return cell }
            let para = NSMutableParagraphStyle()
            func icon(_ symbol: String, _ color: NSColor) -> NSAttributedString {
                let att = NSTextAttachment()
                let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: 12, weight: .regular).applying(.init(paletteColors: [color])))
                att.image = img
                att.bounds = NSRect(x: 0, y: -2, width: 14, height: 13)
                return NSAttributedString(attachment: att)
            }
            let s = NSMutableAttributedString()
            switch fileRows[row] {
            case .folder(let name, let depth, let count):
                para.firstLineHeadIndent = 8 + CGFloat(depth) * 14
                s.append(icon("folder", Theme.gutter))
                s.append(NSAttributedString(string: " \(name)", attributes: [.foregroundColor: Theme.foreground, .font: NSFont.systemFont(ofSize: 12)]))
                s.append(NSAttributedString(string: "  \(count) file\(count == 1 ? "" : "s")", attributes: [.foregroundColor: Theme.gutter, .font: NSFont.systemFont(ofSize: 11)]))
            case .file(let i, let depth):
                let f = files[i]
                para.firstLineHeadIndent = 8 + CGFloat(depth) * 14
                let color: NSColor = f.status == "A" ? .systemGreen : f.status == "D" ? .systemGray : f.status == "R" ? .systemPurple : .systemBlue
                s.append(icon("doc.text", color))
                let shown = f.oldPath != nil ? "\((f.oldPath! as NSString).lastPathComponent) \u{2192} \((f.path as NSString).lastPathComponent)" : (f.path as NSString).lastPathComponent
                s.append(NSAttributedString(string: " " + shown, attributes: [.foregroundColor: color, .font: NSFont.systemFont(ofSize: 12)]))
            }
            s.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: s.length))
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
            // At most two quiet ref pills; a local branch and its remote twin collapse into one.
            var shown: [String] = []
            for ref in c.refs where !shown.contains(where: { $0 == ref || ref.hasSuffix("/" + $0.replacingOccurrences(of: "HEAD -> ", with: "")) }) { shown.append(ref) }
            for ref in shown.prefix(2) {
                let name = ref.replacingOccurrences(of: "HEAD -> ", with: "")
                s.append(NSAttributedString(string: "\u{2009}\(name)\u{2009}", attributes: [
                    .font: NSFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: Self.refColor(ref),
                    .backgroundColor: Self.refColor(ref).withAlphaComponent(0.12)]))
                s.append(NSAttributedString(string: "  "))
            }
            let isMerge = c.parents.count > 1
            s.append(NSAttributedString(string: c.subject, attributes: [.foregroundColor: isMerge ? Theme.gutter : Theme.foreground, .font: NSFont.systemFont(ofSize: 12)]))
            cell.attributedStringValue = s
        case "author":
            let mine = !myName.isEmpty && c.author == myName
            cell.stringValue = c.author
            cell.textColor = Theme.gutter
            cell.font = .systemFont(ofSize: 12, weight: mine ? .medium : .regular)
        case "date":
            cell.stringValue = Self.shortDate(c.timestamp)
            cell.toolTip = Self.dateFormat.string(from: Date(timeIntervalSince1970: c.timestamp))
            cell.textColor = Theme.gutter
            cell.alignment = .right
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
