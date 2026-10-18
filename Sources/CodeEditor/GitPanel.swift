import AppKit

private enum GitGroupKind: Int, CaseIterable {
    case conflicts, staged, changes, untracked
    var title: String {
        switch self {
        case .conflicts: return "Conflicts"
        case .staged: return "Staged"
        case .changes: return "Changes"
        case .untracked: return "Untracked"
        }
    }
}

private final class GitGroup {
    let kind: GitGroupKind
    var rows: [GitRow] = []
    init(kind: GitGroupKind) { self.kind = kind }
}

private final class GitRow {
    let change: GitChange
    let kind: GitGroupKind
    init(change: GitChange, kind: GitGroupKind) { self.change = change; self.kind = kind }
    var key: String { "\(kind.rawValue)|\(change.path)" }

    var letter: String {
        if change.isConflict { return "!" }
        if change.isUntracked { return "U" }
        let c = kind == .staged ? change.index : change.work
        return String(c == "." ? "M" : c)
    }
}

private enum GitColors {
    static func dyn(_ light: NSColor, _ dark: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
    }
    static let added = dyn(NSColor(srgbRed: 0.13, green: 0.55, blue: 0.20, alpha: 1), NSColor(srgbRed: 0.45, green: 0.80, blue: 0.45, alpha: 1))
    static let modified = dyn(NSColor(srgbRed: 0.10, green: 0.40, blue: 0.80, alpha: 1), NSColor(srgbRed: 0.40, green: 0.68, blue: 0.95, alpha: 1))
    static let deleted = dyn(NSColor(white: 0.45, alpha: 1), NSColor(white: 0.60, alpha: 1))
    static let conflict = dyn(NSColor(srgbRed: 0.80, green: 0.15, blue: 0.15, alpha: 1), NSColor(srgbRed: 0.95, green: 0.42, blue: 0.40, alpha: 1))
    static let untracked = dyn(NSColor(srgbRed: 0.60, green: 0.38, blue: 0.12, alpha: 1), NSColor(srgbRed: 0.82, green: 0.62, blue: 0.38, alpha: 1))

    static func color(for row: GitRow) -> NSColor {
        if row.change.isConflict { return conflict }
        if row.change.isUntracked { return untracked }
        switch row.letter {
        case "A", "C": return added
        case "D": return deleted
        default: return modified
        }
    }
}

// MARK: views

private final class GitOutline: NSOutlineView {
    var onSpace: (() -> Void)?
    var onReturn: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 49: onSpace?()
        case 36, 76: onReturn?()
        default: super.keyDown(with: event)
        }
    }
}

private final class GitCommitTextView: NSTextView {
    var onCommit: (() -> Void)?
    var placeholder = "Commit message"
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, event.keyCode == 36 || event.keyCode == 76 {
            onCommit?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty else { return }
        placeholder.draw(at: NSPoint(x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 5), y: textContainerInset.height),
                         withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 13), .foregroundColor: Theme.gutter])
    }
    override func didChangeText() { super.didChangeText(); needsDisplay = true }
}

private final class GitRowCell: NSTableCellView {
    let check = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let badge = NSTextField(labelWithString: "")
    let name = NSTextField(labelWithString: "")
    let dir = NSTextField(labelWithString: "")
    private let buttons = NSStackView()
    var onToggle: ((Bool) -> Void)?
    var onAccept: ((Int) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        check.target = self
        check.action = #selector(toggled)
        check.allowsMixedState = true
        badge.font = .monospacedSystemFont(ofSize: 11, weight: .bold)
        badge.alignment = .center
        name.font = .systemFont(ofSize: 12)
        name.lineBreakMode = .byTruncatingMiddle
        dir.font = .systemFont(ofSize: 11)
        dir.lineBreakMode = .byTruncatingHead
        for (i, title) in ["Accept Yours", "Accept Theirs", "Merge…"].enumerated() {
            let b = NSButton(title: title, target: self, action: #selector(accept(_:)))
            b.tag = i
            b.controlSize = .small
            b.bezelStyle = .rounded
            b.font = .systemFont(ofSize: 11)
            buttons.addArrangedSubview(b)
        }
        buttons.spacing = 4
        for v in [check, badge, name, dir, buttons] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        dir.setContentCompressionResistancePriority(.init(100), for: .horizontal)
        buttons.setContentCompressionResistancePriority(.required, for: .horizontal)
        let nameToButtons = name.trailingAnchor.constraint(lessThanOrEqualTo: buttons.leadingAnchor, constant: -6)
        let dirToButtons = dir.trailingAnchor.constraint(lessThanOrEqualTo: buttons.leadingAnchor, constant: -6)
        NSLayoutConstraint.activate([
            check.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            check.centerYAnchor.constraint(equalTo: centerYAnchor),
            badge.leadingAnchor.constraint(equalTo: check.trailingAnchor, constant: 2),
            badge.widthAnchor.constraint(equalToConstant: 14),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),
            name.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 4),
            name.centerYAnchor.constraint(equalTo: centerYAnchor),
            dir.leadingAnchor.constraint(equalTo: name.trailingAnchor, constant: 6),
            dir.centerYAnchor.constraint(equalTo: centerYAnchor),
            buttons.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            buttons.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameToButtons, dirToButtons,
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func toggled() {
        if check.state == .mixed { check.state = .on }
        onToggle?(check.state == .on)
    }
    @objc private func accept(_ s: NSButton) { onAccept?(s.tag) }

    func configureGroup(_ group: GitGroup, state: NSControl.StateValue) {
        check.isHidden = group.kind == .conflicts
        check.state = state
        badge.stringValue = ""
        name.stringValue = "\(group.kind.title)"
        name.font = .systemFont(ofSize: 12, weight: .semibold)
        name.textColor = Theme.foreground
        dir.stringValue = "\(group.rows.count) file\(group.rows.count == 1 ? "" : "s")"
        dir.textColor = Theme.gutter
        buttons.isHidden = true
    }

    func configureRow(_ row: GitRow, checked: Bool) {
        let color = GitColors.color(for: row)
        check.isHidden = row.kind == .conflicts
        check.state = checked ? .on : .off
        badge.stringValue = row.letter
        badge.textColor = color
        let path = row.change.path as NSString
        name.stringValue = path.lastPathComponent
        name.font = .systemFont(ofSize: 12)
        name.textColor = color
        dir.stringValue = path.deletingLastPathComponent
        dir.textColor = Theme.gutter
        buttons.isHidden = row.kind != .conflicts
    }
}

private final class GitPanelView: NSView {
    let split = NSSplitView()
    let right = NSSplitView()
    let bannerLabel = NSTextField(wrappingLabelWithString: "")
    var positioned = false

    override func layout() {
        super.layout()
        bannerLabel.preferredMaxLayoutWidth = max(100, bounds.width - 60)
        if !positioned, bounds.width > 100, bounds.height > 100 {
            positioned = true
            DispatchQueue.main.async { [self] in
                split.layoutSubtreeIfNeeded()
                split.setPosition(min(430, bounds.width * 0.42), ofDividerAt: 0)
                right.layoutSubtreeIfNeeded()
                right.setPosition(right.bounds.height - 190, ofDividerAt: 0)
            }
        }
    }
}

// MARK: controller

final class GitPanelController: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
    let view: NSView
    var onStatusChange: (() -> Void)?

    private let panel = GitPanelView()
    private var bannerLabel: NSTextField { panel.bannerLabel }
    private let repo: GitRepo
    private let openFile: (URL) -> Void
    private let reader = DispatchQueue(label: "git.read", qos: .userInitiated, attributes: .concurrent)
    private let ops = DispatchQueue(label: "git.ops", qos: .userInitiated)

    private let branchButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private let fetchButton = NSButton()
    private let pullButton = NSButton()
    private let pushButton = NSButton()
    private let spinner = NSProgressIndicator()
    private let banner = NSView()
    private let outline = GitOutline()
    private let diffHost = NSView()
    private let diffView = SideBySideDiffView()
    private var mergeView: MergeView?
    private let mergeBar = NSStackView()
    private let mergeTitle = NSTextField(labelWithString: "")
    private let diffMessage = NSTextField(labelWithString: "")
    private let messageView = GitCommitTextView()
    private let commitButton = NSButton(title: "Commit", target: nil, action: nil)
    private let commitPushButton = NSButton(title: "Commit and Push", target: nil, action: nil)
    private let amendCheck = NSButton(checkboxWithTitle: "Amend", target: nil, action: nil)
    private let countLabel = NSTextField(labelWithString: "")

    private var groups: [GitGroup] = []
    private var checked = Set<String>()
    private var known = Set<String>()
    private var collapsed = Set<GitGroupKind>()
    private var info: GitRepo.BranchInfo = ("", nil, 0, 0, false)
    private var branches: (local: [String], remote: [String]) = ([], [])
    private var merging = false
    private var busy = 0
    private var reloadGen = 0
    private var diffToken = 0
    private var shownDiffKey: String?
    private var mergingPath: String?

    init(root: URL, openFile: @escaping (URL) -> Void) {
        repo = GitRepo(root: root)
        self.openFile = openFile
        view = panel
        super.init()
        build()
        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(appActive), name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: Theme.didChange, object: nil)
        reload()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: build

    private func build() {
        panel.wantsLayer = true

        func tool(_ b: NSButton, _ title: String, _ symbol: String, _ action: Selector) {
            b.title = title
            b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            b.imagePosition = .imageLeading
            b.bezelStyle = .texturedRounded
            b.controlSize = .small
            b.font = .systemFont(ofSize: 12)
            b.target = self
            b.action = action
        }
        tool(fetchButton, "Fetch", "arrow.triangle.2.circlepath", #selector(fetchTapped))
        tool(pullButton, "Pull", "arrow.down.to.line", #selector(pullTapped))
        tool(pushButton, "Push", "arrow.up.to.line", #selector(pushTapped))
        branchButton.controlSize = .small
        branchButton.font = .systemFont(ofSize: 12)
        branchButton.bezelStyle = .texturedRounded
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.isIndeterminate = true

        let toolbar = NSStackView(views: [branchButton, fetchButton, pullButton, pushButton, spinner])
        toolbar.orientation = .horizontal
        toolbar.spacing = 6
        toolbar.alignment = .centerY
        toolbar.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        toolbar.setHuggingPriority(.defaultHigh, for: .vertical)

        // banner
        bannerLabel.font = .systemFont(ofSize: 12)
        bannerLabel.isSelectable = true
        bannerLabel.maximumNumberOfLines = 5
        bannerLabel.lineBreakMode = .byTruncatingTail
        bannerLabel.textColor = GitColors.conflict
        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Dismiss")!, target: self, action: #selector(dismissBanner))
        close.isBordered = false
        close.imageScaling = .scaleProportionallyDown
        banner.wantsLayer = true
        banner.isHidden = true
        for v in [bannerLabel, close] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; banner.addSubview(v) }
        NSLayoutConstraint.activate([
            bannerLabel.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 10),
            bannerLabel.trailingAnchor.constraint(lessThanOrEqualTo: close.leadingAnchor, constant: -8),
            bannerLabel.topAnchor.constraint(equalTo: banner.topAnchor, constant: 5),
            bannerLabel.bottomAnchor.constraint(equalTo: banner.bottomAnchor, constant: -5),
            close.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -8),
            close.topAnchor.constraint(equalTo: banner.topAnchor, constant: 6),
            close.widthAnchor.constraint(equalToConstant: 12), close.heightAnchor.constraint(equalToConstant: 12),
        ])

        // outline
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("change"))
        column.resizingMask = .autoresizingMask
        column.minWidth = 100
        outline.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.rowHeight = 22
        outline.indentationPerLevel = 12
        outline.allowsMultipleSelection = true
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.doubleAction = #selector(doubleClicked)
        outline.onSpace = { [weak self] in self?.toggleSelection() }
        outline.onReturn = { [weak self] in self?.openSelection() }
        let menu = NSMenu()
        menu.delegate = self
        outline.menu = menu
        let outlineScroll = NSScrollView()
        outlineScroll.documentView = outline
        outlineScroll.hasVerticalScroller = true
        outlineScroll.drawsBackground = false

        // diff area
        diffMessage.font = .systemFont(ofSize: 13)
        diffMessage.alignment = .center
        diffMessage.maximumNumberOfLines = 3
        mergeTitle.font = .systemFont(ofSize: 12, weight: .semibold)
        let cancel = NSButton(title: "Close Merge", target: self, action: #selector(closeMerge))
        cancel.bezelStyle = .rounded
        cancel.controlSize = .small
        mergeBar.setViews([mergeTitle, cancel], in: .leading)
        mergeBar.orientation = .horizontal
        mergeBar.spacing = 10
        mergeBar.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        mergeBar.isHidden = true
        for v in [diffView, diffMessage, mergeBar] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; diffHost.addSubview(v) }
        NSLayoutConstraint.activate([
            mergeBar.topAnchor.constraint(equalTo: diffHost.topAnchor),
            mergeBar.leadingAnchor.constraint(equalTo: diffHost.leadingAnchor),
            diffView.topAnchor.constraint(equalTo: diffHost.topAnchor),
            diffView.bottomAnchor.constraint(equalTo: diffHost.bottomAnchor),
            diffView.leadingAnchor.constraint(equalTo: diffHost.leadingAnchor),
            diffView.trailingAnchor.constraint(equalTo: diffHost.trailingAnchor),
            diffMessage.centerXAnchor.constraint(equalTo: diffHost.centerXAnchor),
            diffMessage.centerYAnchor.constraint(equalTo: diffHost.centerYAnchor),
            diffMessage.widthAnchor.constraint(lessThanOrEqualTo: diffHost.widthAnchor, constant: -40),
        ])
        diffHost.setContentHuggingPriority(.init(1), for: .vertical)

        // commit box
        messageView.isRichText = false
        messageView.font = .systemFont(ofSize: 13)
        messageView.textContainerInset = NSSize(width: 4, height: 6)
        messageView.isAutomaticQuoteSubstitutionEnabled = false
        messageView.isAutomaticDashSubstitutionEnabled = false
        messageView.allowsUndo = true
        messageView.isVerticallyResizable = true
        messageView.autoresizingMask = [.width]
        messageView.textContainer?.widthTracksTextView = true
        messageView.onCommit = { [weak self] in self?.commitTapped() }
        let messageScroll = NSScrollView()
        messageScroll.documentView = messageView
        messageScroll.hasVerticalScroller = true
        messageScroll.borderType = .lineBorder
        messageScroll.translatesAutoresizingMaskIntoConstraints = false

        amendCheck.target = self
        amendCheck.action = #selector(amendToggled)
        amendCheck.controlSize = .small
        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor
        for b in [commitButton, commitPushButton] {
            b.bezelStyle = .rounded
            b.controlSize = .regular
            b.target = self
        }
        commitButton.action = #selector(commitTapped)
        commitButton.bezelColor = .controlAccentColor
        commitPushButton.action = #selector(commitPushTapped)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let actions = NSStackView(views: [amendCheck, countLabel, spacer, commitPushButton, commitButton])
        actions.orientation = .horizontal
        actions.spacing = 8
        actions.translatesAutoresizingMaskIntoConstraints = false
        let commitBox = NSView()
        commitBox.addSubview(messageScroll)
        commitBox.addSubview(actions)
        NSLayoutConstraint.activate([
            messageScroll.topAnchor.constraint(equalTo: commitBox.topAnchor, constant: 8),
            messageScroll.leadingAnchor.constraint(equalTo: commitBox.leadingAnchor, constant: 8),
            messageScroll.trailingAnchor.constraint(equalTo: commitBox.trailingAnchor, constant: -8),
            messageScroll.bottomAnchor.constraint(equalTo: actions.topAnchor, constant: -8),
            actions.leadingAnchor.constraint(equalTo: commitBox.leadingAnchor, constant: 8),
            actions.trailingAnchor.constraint(equalTo: commitBox.trailingAnchor, constant: -8),
            actions.bottomAnchor.constraint(equalTo: commitBox.bottomAnchor, constant: -8),
            messageScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            commitBox.heightAnchor.constraint(greaterThanOrEqualToConstant: 110),
        ])

        // layout
        panel.right.isVertical = false
        panel.right.dividerStyle = .thin
        panel.right.addArrangedSubview(diffHost)
        panel.right.addArrangedSubview(commitBox)
        panel.right.setHoldingPriority(.init(260), forSubviewAt: 1)
        panel.split.isVertical = true
        panel.split.dividerStyle = .thin
        outlineScroll.translatesAutoresizingMaskIntoConstraints = false
        outlineScroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        diffHost.heightAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
        panel.split.addArrangedSubview(outlineScroll)
        panel.split.addArrangedSubview(panel.right)
        panel.split.setHoldingPriority(.init(260), forSubviewAt: 0)

        let separator = NSBox()
        separator.boxType = .separator
        let stack = NSStackView(views: [toolbar, separator, banner])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setHuggingPriority(.required, for: .vertical)
        stack.setContentCompressionResistancePriority(.required, for: .vertical)
        panel.split.setContentHuggingPriority(.init(1), for: .vertical)
        panel.split.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(stack)
        panel.addSubview(panel.split)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: panel.topAnchor),
            stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            toolbar.widthAnchor.constraint(equalTo: stack.widthAnchor),
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            banner.widthAnchor.constraint(equalTo: stack.widthAnchor),
            panel.split.topAnchor.constraint(equalTo: stack.bottomAnchor),
            panel.split.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
            panel.split.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            panel.split.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
        ])
        showDiffMessage("Select a file to see its changes")
        updateButtons()
    }

    @objc private func applyTheme() {
        panel.layer?.backgroundColor = Theme.background.cgColor
        banner.layer?.backgroundColor = GitColors.conflict.withAlphaComponent(0.14).cgColor
        outline.backgroundColor = Theme.background
        messageView.backgroundColor = Theme.background
        messageView.textColor = Theme.foreground
        messageView.insertionPointColor = Theme.foreground
        diffMessage.textColor = Theme.gutter
        mergeTitle.textColor = Theme.foreground
        countLabel.textColor = Theme.gutter
        outline.reloadData()
        expandAll()
    }

    // MARK: public

    func focusCommitMessage() { panel.window?.makeFirstResponder(messageView) }

    @objc private func appActive() { reload() }

    func reload() {
        reloadGen += 1
        let gen = reloadGen
        reader.async { [repo] in
            let result: Result<(changes: [GitChange], info: GitRepo.BranchInfo, branches: (local: [String], remote: [String]), merging: Bool), Error>
            do {
                let s = try repo.statusAndBranch()
                let b = (try? repo.branches()) ?? ([], [])
                result = .success((s.changes, s.info, b, repo.isMerging))
            } catch { result = .failure(error) }
            DispatchQueue.main.async { [weak self] in
                guard let self, gen == self.reloadGen else { return }
                switch result {
                case .success(let r):
                    self.info = r.info
                    self.branches = r.branches
                    self.merging = r.merging
                    self.apply(changes: r.changes)
                case .failure(let e): self.showError(e)
                }
            }
        }
    }

    // MARK: model

    private func apply(changes: [GitChange]) {
        let previous = selectedRow()?.key
        var byKind: [GitGroupKind: GitGroup] = [:]
        func add(_ c: GitChange, _ kind: GitGroupKind) {
            let g = byKind[kind] ?? GitGroup(kind: kind)
            g.rows.append(GitRow(change: c, kind: kind))
            byKind[kind] = g
        }
        for c in changes {
            if c.isConflict { add(c, .conflicts); continue }
            if c.isUntracked { add(c, .untracked); continue }
            if c.index != "." { add(c, .staged) }
            if c.work != "." { add(c, .changes) }
        }
        groups = GitGroupKind.allCases.compactMap { byKind[$0] }
        for g in groups { g.rows.sort { $0.change.path.localizedStandardCompare($1.change.path) == .orderedAscending } }

        let paths = Set(changes.map(\.path))
        for c in changes where !known.contains(c.path) {
            known.insert(c.path)
            if !c.isUntracked && !c.isConflict { checked.insert(c.path) }
        }
        known.formIntersection(paths)
        checked.formIntersection(paths)

        outline.reloadData()
        expandAll()
        if let previous, let row = groups.flatMap(\.rows).first(where: { $0.key == previous }) {
            outline.selectRowIndexes([outline.row(forItem: row)], byExtendingSelection: false)
        } else if outline.selectedRow < 0, let first = groups.first?.rows.first {
            outline.selectRowIndexes([outline.row(forItem: first)], byExtendingSelection: false)
        }
        outline.scrollRowToVisible(0)
        refreshBranchMenu()
        updateButtons()
        if selectedRow() == nil, mergingPath == nil { showDiffMessage(groups.isEmpty ? "No changes" : "Select a file to see its changes") }
        else { showDiffForSelection(force: false) }
    }

    private func expandAll() {
        for g in groups where !collapsed.contains(g.kind) { outline.expandItem(g) }
    }

    private func selectedRow() -> GitRow? {
        outline.selectedRow >= 0 ? outline.item(atRow: outline.selectedRow) as? GitRow : nil
    }

    private func selectedItems() -> [Any] {
        outline.selectedRowIndexes.compactMap { outline.item(atRow: $0) }
    }

    private func checkedPaths() -> [String] {
        groups.flatMap(\.rows).map(\.change).filter { checked.contains($0.path) && !$0.isConflict }
            .reduce(into: [String]()) { acc, c in
                for p in [c.path] + (c.origPath.map { [$0] } ?? []) where !acc.contains(p) { acc.append(p) }
            }
    }

    // MARK: outline

    func outlineView(_ o: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let g = item as? GitGroup else { return item == nil ? groups.count : 0 }
        return g.rows.count
    }
    func outlineView(_ o: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? GitGroup)?.rows[index] ?? groups[index]
    }
    func outlineView(_ o: NSOutlineView, isItemExpandable item: Any) -> Bool { item is GitGroup }

    func outlineView(_ o: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = o.makeView(withIdentifier: id, owner: nil) as? GitRowCell ?? {
            let c = GitRowCell(frame: .zero)
            c.identifier = id
            return c
        }()
        if let g = item as? GitGroup {
            let on = g.rows.filter { checked.contains($0.change.path) }.count
            cell.configureGroup(g, state: on == 0 ? .off : on == g.rows.count ? .on : .mixed)
            cell.onToggle = { [weak self] on in
                guard let self else { return }
                for r in g.rows { if on { self.checked.insert(r.change.path) } else { self.checked.remove(r.change.path) } }
                self.checksChanged()
            }
            cell.onAccept = nil
        } else if let row = item as? GitRow {
            cell.configureRow(row, checked: checked.contains(row.change.path))
            cell.onToggle = { [weak self] on in
                guard let self else { return }
                if on { self.checked.insert(row.change.path) } else { self.checked.remove(row.change.path) }
                self.checksChanged()
            }
            cell.onAccept = { [weak self] i in
                switch i {
                case 0: self?.accept(row.change, ours: true)
                case 1: self?.accept(row.change, ours: false)
                default: self?.startMerge(row.change)
                }
            }
        }
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        if mergingPath != nil { closeMerge() }
        showDiffForSelection(force: true)
    }
    func outlineViewItemDidCollapse(_ n: Notification) { if let g = n.userInfo?["NSObject"] as? GitGroup { collapsed.insert(g.kind) } }
    func outlineViewItemDidExpand(_ n: Notification) { if let g = n.userInfo?["NSObject"] as? GitGroup { collapsed.remove(g.kind) } }

    private func checksChanged() {
        for g in groups {
            let row = outline.row(forItem: g)
            if row >= 0 { outline.reloadData(forRowIndexes: [row], columnIndexes: [0]) }
        }
        updateButtons()
    }

    private func toggleSelection() {
        let rows = selectedItems().flatMap { item -> [GitRow] in
            (item as? GitGroup)?.rows ?? (item as? GitRow).map { [$0] } ?? []
        }.filter { $0.kind != .conflicts }
        guard !rows.isEmpty else { return }
        let allOn = rows.allSatisfy { checked.contains($0.change.path) }
        for r in rows { if allOn { checked.remove(r.change.path) } else { checked.insert(r.change.path) } }
        outline.reloadData(forRowIndexes: IndexSet(0..<outline.numberOfRows), columnIndexes: [0])
        updateButtons()
    }

    private func openSelection() {
        guard let item = selectedItems().first else { return }
        if let g = item as? GitGroup {
            if outline.isItemExpanded(g) { outline.collapseItem(g) } else { outline.expandItem(g) }
        } else if let r = item as? GitRow { open(r.change) }
    }

    private func open(_ c: GitChange) {
        let url = repo.root.appendingPathComponent(c.path)
        if FileManager.default.fileExists(atPath: url.path) { openFile(url) } else { NSSound.beep() }
    }

    @objc private func doubleClicked() {
        guard let item = outline.item(atRow: outline.clickedRow) else { return }
        if let r = item as? GitRow { open(r.change) }
        else if let g = item as? GitGroup { if outline.isItemExpanded(g) { outline.collapseItem(g) } else { outline.expandItem(g) } }
    }

    // MARK: context menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let clicked = outline.clickedRow
        if clicked >= 0, !outline.selectedRowIndexes.contains(clicked) {
            outline.selectRowIndexes([clicked], byExtendingSelection: false)
        }
        let rows = selectedItems().compactMap { $0 as? GitRow }
        guard !rows.isEmpty else { return }
        func add(_ title: String, _ sel: Selector) {
            let i = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            i.target = self
            menu.addItem(i)
        }
        add("Open in Editor", #selector(menuOpen))
        menu.addItem(.separator())
        if rows.contains(where: { $0.kind == .changes || $0.kind == .untracked }) { add("Stage", #selector(menuStage)) }
        if rows.contains(where: { $0.kind == .staged }) { add("Unstage", #selector(menuUnstage)) }
        if rows.contains(where: { $0.kind != .conflicts }) { menu.addItem(.separator()); add("Discard Changes…", #selector(menuDiscard)) }
    }

    private func menuRows() -> [GitRow] { selectedItems().compactMap { $0 as? GitRow } }
    @objc private func menuOpen() { menuRows().first.map { open($0.change) } }
    @objc private func menuStage() {
        let paths = menuRows().filter { $0.kind == .changes || $0.kind == .untracked }.map(\.change.path)
        perform { try $0.stage(paths) }
    }
    @objc private func menuUnstage() {
        let paths = menuRows().filter { $0.kind == .staged }.flatMap { [$0.change.path] + ($0.change.origPath.map { [$0] } ?? []) }
        perform { try $0.unstage(paths) }
    }
    @objc private func menuDiscard() {
        let paths = menuRows().filter { $0.kind != .conflicts }.map(\.change.path)
        guard !paths.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "Discard changes to \(paths.count) file\(paths.count == 1 ? "" : "s")?"
        alert.informativeText = "This cannot be undone. Untracked files are deleted."
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        perform { try $0.discard(paths) }
    }

    // MARK: diff

    private func showDiffMessage(_ text: String) {
        diffMessage.stringValue = text
        diffMessage.isHidden = false
        diffView.isHidden = true
    }

    private func showDiffForSelection(force: Bool) {
        guard let row = selectedRow() else {
            shownDiffKey = nil
            showDiffMessage(groups.isEmpty ? "No changes" : "Select a file to see its changes")
            return
        }
        let c = row.change
        let mtime = (try? FileManager.default.attributesOfItem(atPath: repo.root.appendingPathComponent(c.path).path)[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let key = "\(row.key)|\(c.index)\(c.work)|\(mtime)"
        if !force, key == shownDiffKey, !diffView.isHidden { return }
        shownDiffKey = key
        diffToken += 1
        let token = diffToken
        let kind = row.kind
        reader.async { [repo] in
            enum Out { case diff(String, String, String, String); case message(String) }
            let out: Out
            do {
                switch kind {
                case .staged:
                    let old = try repo.headContent(of: c.origPath ?? c.path) ?? ""
                    out = .diff(old, try repo.indexContent(of: c.path) ?? "", "HEAD", "Staged")
                case .changes:
                    out = .diff(try repo.indexContent(of: c.path) ?? "", try repo.workingContent(of: c.path) ?? "", "Staged", "Working Copy")
                case .untracked:
                    out = .diff("", try repo.workingContent(of: c.path) ?? "", "", "Working Copy")
                case .conflicts:
                    let v = try repo.conflictVersions(of: c.path)
                    out = .diff(v.ours ?? "", v.theirs ?? "", "Yours", "Theirs")
                }
            } catch let e as GitError {
                out = .message(e.message.hasPrefix("Binary") || e.message.hasPrefix("File too large") ? "\(e.message): diff not shown" : e.message)
            } catch { out = .message(error.localizedDescription) }
            DispatchQueue.main.async { [weak self] in
                guard let self, token == self.diffToken, self.mergingPath == nil else { return }
                switch out {
                case .diff(let old, let new, let oldT, let newT):
                    self.diffMessage.isHidden = true
                    self.diffView.isHidden = false
                    self.diffView.show(old: old, new: new, oldTitle: oldT, newTitle: newT, fileExtension: (c.path as NSString).pathExtension)
                case .message(let m): self.showDiffMessage(m)
                }
            }
        }
    }

    // MARK: conflicts

    private func accept(_ c: GitChange, ours: Bool) {
        perform { repo in
            let v = try repo.conflictVersions(of: c.path)
            if let content = ours ? v.ours : v.theirs { try repo.markResolved(path: c.path, content: content) }
            else { try repo.markResolvedDeleted(path: c.path) }
        }
    }

    private func startMerge(_ c: GitChange) {
        reader.async { [repo] in
            let result = Result { try repo.conflictVersions(of: c.path) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch result {
                case .failure(let e): self.showError(e)
                case .success(let v):
                    let mv = self.mergeView ?? self.makeMergeView()
                    self.mergingPath = c.path
                    self.diffToken += 1
                    self.mergeTitle.stringValue = "Merging \(c.path)"
                    self.mergeBar.isHidden = false
                    self.diffView.isHidden = true
                    self.diffMessage.isHidden = true
                    mv.isHidden = false
                    mv.show(base: v.base, ours: v.ours ?? "", theirs: v.theirs ?? "", oursTitle: "Yours", theirsTitle: "Theirs",
                            fileExtension: (c.path as NSString).pathExtension)
                    mv.onResolved = { [weak self] text in
                        self?.closeMerge()
                        self?.perform { try $0.markResolved(path: c.path, content: text) }
                    }
                }
            }
        }
    }

    private func makeMergeView() -> MergeView {
        let mv = MergeView()
        mv.translatesAutoresizingMaskIntoConstraints = false
        diffHost.addSubview(mv)
        NSLayoutConstraint.activate([
            mv.topAnchor.constraint(equalTo: mergeBar.bottomAnchor),
            mv.bottomAnchor.constraint(equalTo: diffHost.bottomAnchor),
            mv.leadingAnchor.constraint(equalTo: diffHost.leadingAnchor),
            mv.trailingAnchor.constraint(equalTo: diffHost.trailingAnchor),
            mergeBar.trailingAnchor.constraint(lessThanOrEqualTo: diffHost.trailingAnchor),
        ])
        mergeView = mv
        return mv
    }

    @objc private func closeMerge() {
        mergingPath = nil
        mergeView?.isHidden = true
        mergeBar.isHidden = true
        showDiffForSelection(force: true)
    }

    // MARK: operations

    private func showError(_ e: Error) {
        bannerLabel.stringValue = (e as? GitError)?.message ?? e.localizedDescription
        banner.isHidden = false
        panel.needsLayout = true
    }

    @objc private func dismissBanner() { banner.isHidden = true }

    private func setBusy(_ on: Bool) {
        busy += on ? 1 : -1
        if busy > 0 { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        updateButtons()
    }

    /// Runs `work` serially off the main thread, then refreshes. Errors land in the banner.
    private func perform(_ work: @escaping (GitRepo) throws -> Void, done: (() -> Void)? = nil) {
        setBusy(true)
        banner.isHidden = true
        ops.async { [repo] in
            let error: Error?
            do { try work(repo); error = nil } catch let e { error = e }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.setBusy(false)
                if let error { self.showError(error) }
                done?()
                self.reload()
                self.onStatusChange?()
            }
        }
    }

    @objc private func fetchTapped() { perform { try $0.fetch() } }
    @objc private func pullTapped() { perform { try $0.pull() } }
    @objc private func pushTapped() { perform { try $0.push() } }

    private func updateButtons() {
        let idle = busy == 0
        for b in [fetchButton, pullButton, pushButton] { b.isEnabled = idle }
        let hasConflicts = groups.contains { $0.kind == .conflicts }
        let n = checkedPaths().isEmpty ? 0 : groups.flatMap(\.rows).filter { $0.kind != .conflicts && checked.contains($0.change.path) }
            .reduce(into: Set<String>()) { $0.insert($1.change.path) }.count
        countLabel.stringValue = hasConflicts ? "Resolve conflicts first" : "\(n) file\(n == 1 ? "" : "s") selected"
        let can = idle && !hasConflicts
        commitButton.isEnabled = can
        commitPushButton.isEnabled = can
    }

    @objc private func amendToggled() {
        guard amendCheck.state == .on, messageView.string.isEmpty else { return }
        reader.async { [repo] in
            let msg = (try? repo.lastCommitMessage()) ?? ""
            DispatchQueue.main.async { [weak self] in
                guard let self, self.amendCheck.state == .on, self.messageView.string.isEmpty else { return }
                self.messageView.string = msg
                self.messageView.needsDisplay = true
            }
        }
    }

    @objc private func commitTapped() { commit(push: false) }
    @objc private func commitPushTapped() { commit(push: true) }

    private func commit(push: Bool) {
        guard busy == 0, !groups.contains(where: { $0.kind == .conflicts }) else { return }
        let paths = checkedPaths()
        let amend = amendCheck.state == .on
        let message = messageView.string
        if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !amend {
            showError(GitError(message: "Enter a commit message"))
            focusCommitMessage()
            return
        }
        if paths.isEmpty && !amend && !merging {
            showError(GitError(message: "No files selected to commit"))
            return
        }
        perform({ repo in
            try repo.commit(message: message, paths: paths.isEmpty ? nil : paths, amend: amend)
            if push { try repo.push() }
        }, done: { [weak self] in
            guard let self, self.banner.isHidden else { return }
            self.messageView.string = ""
            self.messageView.needsDisplay = true
            self.amendCheck.state = .off
        })
    }

    // MARK: branches

    private func refreshBranchMenu() {
        branchButton.removeAllItems()
        var title = "\u{2387} " + (info.name.isEmpty ? "—" : info.name)
        if info.detached { title += " (detached)" }
        if info.ahead > 0 { title += "  \u{2191}\(info.ahead)" }
        if info.behind > 0 { title += "  \u{2193}\(info.behind)" }
        branchButton.addItem(withTitle: title)
        let menu = branchButton.menu!
        func header(_ t: String) {
            let i = NSMenuItem(title: t, action: nil, keyEquivalent: "")
            i.isEnabled = false
            menu.addItem(i)
        }
        func branch(_ name: String, current: Bool) {
            let i = NSMenuItem(title: name, action: #selector(branchPicked(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = name
            i.state = current ? .on : .off
            menu.addItem(i)
        }
        let nb = NSMenuItem(title: "New Branch…", action: #selector(newBranch), keyEquivalent: "")
        nb.target = self
        menu.addItem(nb)
        menu.addItem(.separator())
        header("Local Branches")
        for b in branches.local { branch(b, current: b == info.name && !info.detached) }
        let remotes = branches.remote.filter { r in !branches.local.contains { r.hasSuffix("/" + $0) } || true }
        if !remotes.isEmpty {
            menu.addItem(.separator())
            header("Remote Branches")
            for r in remotes { branch(r, current: false) }
        }
    }

    @objc private func branchPicked(_ s: NSMenuItem) {
        guard let name = s.representedObject as? String, name != info.name else { return }
        perform { try $0.checkout(name) }
    }

    @objc private func newBranch() {
        let alert = NSAlert()
        alert.messageText = "New Branch"
        alert.informativeText = "Create and check out a branch from \(info.name)."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 22))
        field.placeholderString = "branch-name"
        alert.accessoryView = field
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        perform { try $0.createBranch(name, checkout: true) }
    }
}
