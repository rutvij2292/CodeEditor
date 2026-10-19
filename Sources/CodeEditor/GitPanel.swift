import AppKit

private enum GitGroupKind: Int, CaseIterable {
    case conflicts, staged, changes, untracked
    var title: String {
        switch self {
        case .conflicts: return "Conflicts"
        case .staged: return "Staged"
        case .changes: return "Changes"
        case .untracked: return "Unversioned Files"
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
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 49 where mods.isEmpty: onSpace?()
        case 36 where mods.isEmpty, 76 where mods.isEmpty: onReturn?()
        default: super.keyDown(with: event)
        }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods == .command, event.charactersIgnoringModifiers == "a", window?.firstResponder === self {
            selectAll(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
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
    private var nameToButtons: NSLayoutConstraint!, dirToButtons: NSLayoutConstraint!
    private var nameToEdge: NSLayoutConstraint!, dirToEdge: NSLayoutConstraint!

    /// A hidden stack view still reserves its width, which clipped file names to half the row: only constrain against the buttons while they show.
    private func showButtons(_ on: Bool) {
        buttons.isHidden = !on
        nameToButtons.isActive = on; dirToButtons.isActive = on
        nameToEdge.isActive = !on; dirToEdge.isActive = !on
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        check.target = self
        check.action = #selector(toggled)
        badge.font = .monospacedSystemFont(ofSize: 11, weight: .bold)
        badge.alignment = .center
        name.font = .systemFont(ofSize: 12)
        name.lineBreakMode = .byTruncatingTail
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
        name.setContentCompressionResistancePriority(.init(500), for: .horizontal)
        dir.setContentCompressionResistancePriority(.init(100), for: .horizontal)
        buttons.setContentCompressionResistancePriority(.required, for: .horizontal)
        nameToButtons = name.trailingAnchor.constraint(lessThanOrEqualTo: buttons.leadingAnchor, constant: -6)
        dirToButtons = dir.trailingAnchor.constraint(lessThanOrEqualTo: buttons.leadingAnchor, constant: -6)
        nameToEdge = name.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6)
        dirToEdge = dir.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6)
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
        showButtons(false)
    }
    required init?(coder: NSCoder) { fatalError() }

    private var shown: NSControl.StateValue = .off
    private var rowColor: NSColor?, dirColor: NSColor = Theme.gutter

    /// On the accent-coloured selection the status colours vanish (blue on blue): switch to white text there.
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { applySelectionColors() }
    }

    private func applySelectionColors() {
        let selected = backgroundStyle == .emphasized
        name.textColor = selected ? .white : (rowColor ?? Theme.foreground)
        if let rowColor { badge.textColor = selected ? .white : rowColor }
        dir.textColor = selected ? NSColor.white.withAlphaComponent(0.75) : dirColor
    }

    private func setState(_ s: NSControl.StateValue) {
        shown = s
        check.allowsMixedState = true
        check.state = s
    }

    // mixed -> on, so a partially checked file or group becomes fully checked on click
    @objc private func toggled() {
        let on = shown != .on
        setState(on ? .on : .off)
        onToggle?(on)
    }
    @objc private func accept(_ s: NSButton) { onAccept?(s.tag) }

    func configureGroup(_ group: GitGroup, state: NSControl.StateValue) {
        check.isHidden = group.kind == .conflicts
        setState(state)
        badge.stringValue = ""
        name.stringValue = "\(group.kind.title)"
        name.font = .systemFont(ofSize: 12, weight: .semibold)
        name.textColor = Theme.foreground
        dir.stringValue = "\(group.rows.count) file\(group.rows.count == 1 ? "" : "s")"
        dir.textColor = Theme.gutter
        rowColor = nil; dirColor = Theme.gutter
        showButtons(false)
    }

    func configureRow(_ row: GitRow, state: NSControl.StateValue) {
        let color = GitColors.color(for: row)
        check.isHidden = row.kind == .conflicts
        setState(state)
        badge.stringValue = row.letter
        badge.textColor = color
        let path = row.change.path as NSString
        name.stringValue = path.lastPathComponent
        name.font = .systemFont(ofSize: 12)
        name.textColor = color
        dir.stringValue = path.deletingLastPathComponent
        dir.textColor = Theme.gutter
        rowColor = color; dirColor = Theme.gutter
        applySelectionColors()
        showButtons(row.kind == .conflicts)
    }
}

private final class GitPanelView: NSView {
    let split = NSSplitView()
    let right = NSSplitView()
    let bannerLabel = NSTextField(wrappingLabelWithString: "")
    var positioned = false
    var onCommit: (() -> Void)?
    var onCommitPush: (() -> Void)?
    var onRollback: (() -> Void)?
    var onEscape: (() -> Void)?
    /// True while a popover, sheet or search text should get Esc instead of the panel.
    var escapeIsBusy: () -> Bool = { false }

    private func focusInside() -> Bool {
        guard let r = window?.firstResponder as? NSView else { return false }
        return r.isDescendant(of: self)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard focusInside() else { return super.performKeyEquivalent(with: event) }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods == .command, event.keyCode == 36 || event.keyCode == 76 { onCommit?(); return true }
        if mods == [.command, .option], event.keyCode == 40 { onCommitPush?(); return true }            // K
        if mods == [.command, .option], event.keyCode == 6, window?.firstResponder is NSOutlineView {    // Z
            onRollback?(); return true
        }
        if event.keyCode == 53, mods.isEmpty || mods == .shift, window?.attachedSheet == nil, !escapeIsBusy() {
            onEscape?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

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
    /// Set by the Commit window: opens the shared branch popup instead of the plain menu below.
    var onShowBranches: (() -> Void)?
    /// Esc / Shift-Esc pressed while focus is inside the panel and no popover, sheet or search text wants it.
    var onRequestClose: (() -> Void)?
    /// Fired after a successful commit (`andPush`: the push is about to start).
    var onCommitted: ((_ andPush: Bool) -> Void)?
    /// Fired after every successful reload of the repository state.
    var onSummaryChange: ((GitSummary) -> Void)?
    private(set) var summary = GitSummary.empty

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
    private let rollbackButton = NSButton()
    private let stashButton = NSButton()
    private let modeControl = NSSegmentedControl(labels: ["Changes", "Log"], trackingMode: .selectOne, target: nil, action: nil)
    private let spinner = NSProgressIndicator()
    private let banner = NSView()
    private let opBanner = NSView()
    private let opLabel = NSTextField(labelWithString: "")
    private let opContinue = NSButton(title: "Continue", target: nil, action: nil)
    private let opAbort = NSButton(title: "Abort", target: nil, action: nil)
    private lazy var logView = GitLogView(repo: repo)
    private var stashPopover: NSPopover?
    private var stashes: [GitStash] = []
    private var currentOp: GitOperation?
    private var bannerIsNote = false
    private var capNoteShown = false
    private var reloading = false
    private var reloadQueued = false
    private enum Mode { case changes, log }
    private var mode = Mode.changes
    private static let maxUntrackedShown = 2000
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

    private struct PartialSel { var checked: Int; var total: Int; var content: String; var mtime: TimeInterval }
    private struct ActiveDiff { let rowKey: String; let path: String; let kind: GitGroupKind; let view: SideBySideDiffView }
    private var partial: [String: PartialSel] = [:]
    private var stageViews: [String: (view: SideBySideDiffView, sig: String)] = [:]
    private var active: ActiveDiff?
    private var changes: [GitChange] = []
    private var editMode = true
    private var pendingWrite: (path: String, text: String)?
    private var writeTimer: Timer?
    private let diffBar = NSStackView()
    private let prevButton = NSButton()
    private let nextButton = NSButton()
    private let stageSelectedButton = NSButton(title: "Stage Selected", target: nil, action: nil)
    private let editCheck = NSButton(checkboxWithTitle: "Revert arrows", target: nil, action: nil)
    private let diffInfo = NSTextField(labelWithString: "")
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
        tool(rollbackButton, "Rollback", "arrow.uturn.backward", #selector(rollbackTapped))
        tool(stashButton, "Stash", "tray.and.arrow.down", #selector(stashTapped))
        rollbackButton.toolTip = "Roll back selected changes (⌥⌘Z)"
        pushButton.toolTip = "Push (hold ⌥ to always preview)"
        modeControl.controlSize = .small
        modeControl.selectedSegment = 0
        modeControl.target = self
        modeControl.action = #selector(modeChanged)
        branchButton.controlSize = .small
        branchButton.font = .systemFont(ofSize: 12)
        branchButton.bezelStyle = .texturedRounded
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.isIndeterminate = true

        let toolbar = NSStackView(views: [branchButton, modeControl, fetchButton, pullButton, pushButton, rollbackButton, stashButton, spinner])
        toolbar.orientation = .horizontal
        toolbar.spacing = 6
        toolbar.alignment = .centerY
        toolbar.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        toolbar.setHuggingPriority(.defaultHigh, for: .vertical)

        // banner
        bannerLabel.font = .systemFont(ofSize: 12)
        bannerLabel.isSelectable = true
        bannerLabel.maximumNumberOfLines = 9
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

        // operation-in-progress banner (merge / rebase / cherry-pick / revert)
        opLabel.font = .systemFont(ofSize: 12, weight: .medium)
        for b in [opContinue, opAbort] {
            b.bezelStyle = .rounded
            b.controlSize = .small
            b.font = .systemFont(ofSize: 11)
            b.target = self
        }
        opContinue.action = #selector(opContinueTapped)
        opAbort.action = #selector(opAbortTapped)
        opBanner.wantsLayer = true
        opBanner.isHidden = true
        for v in [opLabel, opContinue, opAbort] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; opBanner.addSubview(v) }
        NSLayoutConstraint.activate([
            opLabel.leadingAnchor.constraint(equalTo: opBanner.leadingAnchor, constant: 10),
            opLabel.centerYAnchor.constraint(equalTo: opBanner.centerYAnchor),
            opAbort.trailingAnchor.constraint(equalTo: opBanner.trailingAnchor, constant: -8),
            opContinue.trailingAnchor.constraint(equalTo: opAbort.leadingAnchor, constant: -6),
            opAbort.centerYAnchor.constraint(equalTo: opBanner.centerYAnchor),
            opContinue.centerYAnchor.constraint(equalTo: opBanner.centerYAnchor),
            opLabel.trailingAnchor.constraint(lessThanOrEqualTo: opContinue.leadingAnchor, constant: -8),
            opBanner.heightAnchor.constraint(equalToConstant: 30),
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
        for (b, symbol, tip) in [(prevButton, "chevron.up", "Previous Change (⇧F7)"), (nextButton, "chevron.down", "Next Change (F7)")] {
            b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
            b.toolTip = tip
            b.isBordered = false
            b.target = self
            b.widthAnchor.constraint(equalToConstant: 22).isActive = true
        }
        prevButton.action = #selector(prevChange)
        nextButton.action = #selector(nextChange)
        let f7 = String(Character(UnicodeScalar(UInt32(NSF7FunctionKey))!))
        nextButton.keyEquivalent = f7
        nextButton.keyEquivalentModifierMask = []
        prevButton.keyEquivalent = f7
        prevButton.keyEquivalentModifierMask = [.shift]
        stageSelectedButton.bezelStyle = .texturedRounded
        stageSelectedButton.controlSize = .small
        stageSelectedButton.font = .systemFont(ofSize: 11)
        stageSelectedButton.target = self
        stageSelectedButton.action = #selector(stageSelectedTapped)
        editCheck.controlSize = .small
        editCheck.font = .systemFont(ofSize: 11)
        editCheck.state = .on
        editCheck.target = self
        editCheck.action = #selector(editToggled)
        editCheck.toolTip = "Edit the right pane and revert hunks with the » arrows"
        diffInfo.font = .systemFont(ofSize: 11)
        let barSpacer = NSView()
        barSpacer.setContentHuggingPriority(.init(1), for: .horizontal)
        for v in [prevButton, nextButton, stageSelectedButton, editCheck, barSpacer, diffInfo] { diffBar.addArrangedSubview(v) }
        diffBar.orientation = .horizontal
        diffBar.spacing = 8
        diffBar.alignment = .centerY
        diffBar.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        diffBar.isHidden = true
        for v in [diffView, diffMessage, mergeBar, diffBar] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; diffHost.addSubview(v) }
        NSLayoutConstraint.activate([
            diffBar.topAnchor.constraint(equalTo: diffHost.topAnchor),
            diffBar.leadingAnchor.constraint(equalTo: diffHost.leadingAnchor),
            diffBar.trailingAnchor.constraint(equalTo: diffHost.trailingAnchor),
            diffBar.heightAnchor.constraint(equalToConstant: 28),
            mergeBar.topAnchor.constraint(equalTo: diffHost.topAnchor),
            mergeBar.leadingAnchor.constraint(equalTo: diffHost.leadingAnchor),
            diffView.topAnchor.constraint(equalTo: diffBar.bottomAnchor),
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
        let stack = NSStackView(views: [toolbar, separator, banner, opBanner])
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
        logView.translatesAutoresizingMaskIntoConstraints = false
        logView.isHidden = true
        panel.addSubview(logView)
        panel.onCommit = { [weak self] in self?.commitTapped() }
        panel.onCommitPush = { [weak self] in self?.commitPushTapped() }
        panel.onRollback = { [weak self] in self?.rollbackTapped() }
        panel.onEscape = { [weak self] in self?.onRequestClose?() }
        panel.escapeIsBusy = { [weak self] in
            guard let self else { return false }
            return self.stashPopover?.isShown == true || (self.mode == .log && self.logView.searchIsEditing)
        }
        logView.onAction = { [weak self] a, c in self?.logAction(a, c) }
        NSLayoutConstraint.activate([
            logView.topAnchor.constraint(equalTo: stack.bottomAnchor),
            logView.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
            logView.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            logView.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
        ])
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: panel.topAnchor),
            stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            toolbar.widthAnchor.constraint(equalTo: stack.widthAnchor),
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            banner.widthAnchor.constraint(equalTo: stack.widthAnchor),
            opBanner.widthAnchor.constraint(equalTo: stack.widthAnchor),
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
        styleBanner()
        opBanner.layer?.backgroundColor = GitColors.modified.withAlphaComponent(0.16).cgColor
        opLabel.textColor = Theme.foreground
        outline.backgroundColor = Theme.background
        messageView.backgroundColor = Theme.background
        messageView.textColor = Theme.foreground
        messageView.insertionPointColor = Theme.foreground
        diffMessage.textColor = Theme.gutter
        diffInfo.textColor = Theme.gutter
        mergeTitle.textColor = Theme.foreground
        countLabel.textColor = Theme.gutter
        outline.reloadData()
        expandAll()
    }

    // MARK: public

    func focusCommitMessage() { panel.window?.makeFirstResponder(messageView) }
    func fetch() { fetchTapped() }
    func pull() { pullTapped() }
    func push() { pushTapped() }

    @objc private func appActive() { reload() }

    private struct Snapshot {
        var changes: [GitChange]; var info: GitRepo.BranchInfo; var branches: (local: [String], remote: [String])
        var merging: Bool; var op: GitOperation?; var stashes: [GitStash]; var hiddenUntracked: Int
    }

    /// Refreshes status, branches, stashes and the in-progress operation off the main thread. Calls made while a
    /// refresh is running are coalesced into one follow-up refresh. Never changes the first responder.
    func reload() {
        if reloading { reloadQueued = true; return }
        reloading = true
        reloadGen += 1
        let gen = reloadGen
        reader.async { [repo] in
            let result: Result<Snapshot, Error>
            do {
                let s = try repo.statusCapped(maxUntracked: Self.maxUntrackedShown)
                let b = (try? repo.branches()) ?? ([], [])
                result = .success(Snapshot(changes: s.changes, info: s.info, branches: b, merging: repo.isMerging,
                                           op: repo.operationInProgress(), stashes: (try? repo.stashList()) ?? [],
                                           hiddenUntracked: s.hiddenUntracked))
            } catch { result = .failure(error) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.reloading = false
                if gen == self.reloadGen {
                    switch result {
                    case .success(let r):
                        self.info = r.info
                        self.branches = r.branches
                        self.merging = r.merging
                        self.currentOp = r.op
                        self.stashes = r.stashes
                        self.apply(changes: r.changes)
                        self.updateOpBanner()
                        self.updateCapNote(hidden: r.hiddenUntracked)
                        self.publishSummary()
                        if self.mode == .log { self.logView.reload() }
                    case .failure(let e): self.showError(e)
                    }
                }
                if self.reloadQueued { self.reloadQueued = false; self.reload() }
            }
        }
    }

    private func publishSummary() {
        let paths = Set(changes.map(\.path))
        summary = GitSummary(branch: info.name, ahead: info.ahead, behind: info.behind, changes: paths.count,
                             conflicts: changes.filter(\.isConflict).count, staged: changes.filter { $0.isStaged }.count)
        onSummaryChange?(summary)
    }

    private func updateCapNote(hidden: Int) {
        if hidden > 0 {
            if banner.isHidden || capNoteShown {
                showNote("\(hidden) more untracked files are not shown (first \(Self.maxUntrackedShown) listed). Ignore generated folders in .gitignore.")
                capNoteShown = true
            }
        } else if capNoteShown {
            banner.isHidden = true
            capNoteShown = false
        }
    }

    private func updateOpBanner() {
        guard let op = currentOp else { opBanner.isHidden = true; return }
        let conflicts = groups.contains { $0.kind == .conflicts }
        opLabel.stringValue = "\(op.title) in progress" + (conflicts ? " — resolve conflicts, then continue" : "")
        opBanner.isHidden = false
    }

    @objc private func opContinueTapped() {
        guard let op = currentOp else { return }
        perform({ try $0.continueOperation(op) }, resets: true)
    }

    @objc private func opAbortTapped() {
        guard let op = currentOp else { return }
        let a = GitDialogs.confirmAlert(title: "Abort \(op.title.lowercased())?", info: "The \(op.title.lowercased()) is cancelled and its partial results are discarded.",
                                        button: "Abort", destructive: true)
        present(a) { [weak self] r in
            guard r == .alertFirstButtonReturn else { return }
            self?.perform({ try $0.abortOperation(op) }, resets: true)
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
        self.changes = changes
        partial = partial.filter { paths.contains($0.key) }
        for (k, v) in stageViews where !paths.contains(String(k.dropFirst(2))) { v.view.removeFromSuperview(); stageViews[k] = nil }

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
            let states = g.rows.map { rowState($0.change.path) }
            let on = states.filter { $0 == .on }.count
            cell.configureGroup(g, state: on == states.count ? .on : (on == 0 && !states.contains(.mixed)) ? .off : .mixed)
            cell.onToggle = { [weak self] on in
                guard let self else { return }
                for r in g.rows { self.setFileChecked(r.change.path, on) }
                self.checksChanged()
            }
            cell.onAccept = nil
        } else if let row = item as? GitRow {
            cell.configureRow(row, state: rowState(row.change.path))
            cell.onToggle = { [weak self] on in
                guard let self else { return }
                self.setFileChecked(row.change.path, on)
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
        outline.reloadData(forRowIndexes: IndexSet(0..<outline.numberOfRows), columnIndexes: [0])
        updateButtons()
    }

    private func rowState(_ path: String) -> NSControl.StateValue {
        guard checked.contains(path) else { return .off }
        if let p = partial[path], p.checked > 0, p.checked < p.total { return .mixed }
        return .on
    }

    /// Per-file checkbox: also drives the line checkboxes of that file's diff so both stay in sync.
    private func setFileChecked(_ path: String, _ on: Bool) {
        if on { checked.insert(path) } else { checked.remove(path) }
        var hadView = false
        for k in ["\(GitGroupKind.changes.rawValue)|\(path)", "\(GitGroupKind.untracked.rawValue)|\(path)"] {
            if let v = stageViews[k]?.view { hadView = true; v.setAllChecked(on) }
        }
        if !hadView { partial[path] = nil }
    }

    private func isCommitPartialEligible(_ c: GitChange) -> Bool {
        guard !merging, !c.isConflict else { return false }
        return c.isUntracked || (c.index == "." && c.work != "." && c.work != "D")
    }

    private func toggleSelection() {
        let rows = selectedItems().flatMap { item -> [GitRow] in
            (item as? GitGroup)?.rows ?? (item as? GitRow).map { [$0] } ?? []
        }.filter { $0.kind != .conflicts }
        guard !rows.isEmpty else { return }
        let allOn = rows.allSatisfy { rowState($0.change.path) == .on }
        for r in rows { setFileChecked(r.change.path, !allOn) }
        checksChanged()
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
        if rows.contains(where: { $0.kind != .conflicts }) {
            menu.addItem(.separator())
            add("Rollback…", #selector(rollbackTapped))
            menu.items.last?.keyEquivalent = "z"
            menu.items.last?.keyEquivalentModifierMask = [.command, .option]
        }
    }

    private func menuRows() -> [GitRow] { selectedItems().compactMap { $0 as? GitRow } }
    @objc private func menuOpen() { menuRows().first.map { open($0.change) } }
    @objc private func menuStage() {
        let paths = menuRows().filter { $0.kind == .changes || $0.kind == .untracked }.map(\.change.path)
        perform({ try $0.stage(paths) }, resets: true)
    }
    @objc private func menuUnstage() {
        let paths = menuRows().filter { $0.kind == .staged }.flatMap { [$0.change.path] + ($0.change.origPath.map { [$0] } ?? []) }
        perform({ try $0.unstage(paths) }, resets: true)
    }
    // MARK: rollback

    /// Selected files (groups expand to their rows); falls back to the checked files when nothing is selected.
    private func rollbackTargets() -> (tracked: [String], untracked: [String]) {
        var rows = selectedItems().flatMap { item -> [GitRow] in
            (item as? GitGroup)?.rows ?? (item as? GitRow).map { [$0] } ?? []
        }
        if rows.isEmpty { rows = groups.flatMap(\.rows).filter { checked.contains($0.change.path) } }
        var seen = Set<String>(), tracked: [String] = [], untracked: [String] = []
        for r in rows where r.kind != .conflicts && seen.insert(r.change.path).inserted {
            if r.change.isUntracked { untracked.append(r.change.path) } else { tracked.append(r.change.path) }
        }
        return (tracked, untracked)
    }

    func makeRollbackAlert() -> NSAlert? {
        let t = rollbackTargets()
        return t.tracked.isEmpty && t.untracked.isEmpty ? nil : GitDialogs.rollbackAlert(tracked: t.tracked, untracked: t.untracked)
    }

    @objc private func rollbackTapped() {
        guard busy == 0 else { return }
        let t = rollbackTargets()
        let paths = t.tracked + t.untracked
        guard !paths.isEmpty else { NSSound.beep(); return }
        present(GitDialogs.rollbackAlert(tracked: t.tracked, untracked: t.untracked)) { [weak self] r in
            guard r == .alertFirstButtonReturn else { return }
            self?.perform({ try $0.rollback(paths) }, resets: true)
        }
    }

    // MARK: stash

    func makeStashView() -> GitStashView {
        let v = GitStashView()
        v.onStash = { [weak self] in self?.stashPopover?.close(); self?.stashChanges() }
        v.onApply = { [weak self] s in self?.stashPopover?.close(); self?.perform({ try $0.stashApply(index: s.index) }, resets: true) }
        v.onPop = { [weak self] s in self?.stashPopover?.close(); self?.perform({ try $0.stashPop(index: s.index) }, resets: true) }
        v.onDrop = { [weak self] s in
            self?.stashPopover?.close()
            let a = GitDialogs.confirmAlert(title: "Drop stash?", info: "\(s.message)\n\nThis cannot be undone.", button: "Drop", destructive: true)
            self?.present(a) { r in
                guard r == .alertFirstButtonReturn else { return }
                self?.perform({ try $0.stashDrop(index: s.index) })
            }
        }
        v.show(stashes: stashes)
        return v
    }

    @objc private func stashTapped() {
        if let p = stashPopover, p.isShown { p.close(); return }
        reader.async { [repo] in
            let list = (try? repo.stashList()) ?? []
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.stashes = list
                let pop = NSPopover()
                pop.behavior = .transient
                let vc = NSViewController()
                vc.view = self.makeStashView()
                pop.contentViewController = vc
                pop.contentSize = vc.view.frame.size
                self.stashPopover = pop
                pop.show(relativeTo: self.stashButton.bounds, of: self.stashButton, preferredEdge: .maxY)
            }
        }
    }

    private func stashChanges() {
        let (alert, field, untracked) = GitDialogs.stashAlert()
        present(alert) { [weak self] r in
            guard r == .alertFirstButtonReturn else { return }
            let msg = field.stringValue, inc = untracked.state == .on
            self?.perform({ try $0.stashPush(message: msg, includeUntracked: inc) }, resets: true)
        }
    }

    // MARK: log tab

    @objc private func modeChanged() { setMode(modeControl.selectedSegment == 1 ? .log : .changes) }

    private func setMode(_ m: Mode, reloadLog: Bool = true) {
        mode = m
        modeControl.selectedSegment = m == .log ? 1 : 0
        panel.split.isHidden = m == .log
        logView.isHidden = m == .changes
        if m == .log, reloadLog { logView.reload() }
    }

    func showLog() { setMode(.log) }
    func showChanges() { setMode(.changes) }

    /// Switches to the Log tab listing the history of one file (`git log --follow`).
    func showHistory(for url: URL) {
        let root = repo.root.resolvingSymlinksInPath().path
        let path = url.resolvingSymlinksInPath().path
        guard path.hasPrefix(root + "/") else { NSSound.beep(); return }
        setMode(.log, reloadLog: false)
        logView.showHistory(path: String(path.dropFirst(root.count + 1)))
    }

    /// Asks before cherry-picking (target branch and commit list shown); a merge commit also asks which parent to keep.
    private func confirmCherryPick(_ commits: [GitCommit]) {
        let repo = repo
        let target = (try? repo.branchInfo())?.name ?? "HEAD"
        let merges = commits.filter { $0.parents.count > 1 }
        if commits.count > 1, !merges.isEmpty {
            present(GitDialogs.confirmAlert(title: "Cannot cherry-pick merge commits in a batch",
                                            info: "Select “\(merges[0].subject)” on its own to choose which parent to keep.", button: "OK")) { _ in }
            return
        }
        var info = "Apply onto “\(target)”, oldest first:\n\n"
        info += commits.prefix(8).map { "\($0.shortHash)  \($0.subject)" }.joined(separator: "\n")
        if commits.count > 8 { info += "\n… and \(commits.count - 8) more" }
        if repo.hasLocalChanges() { info += "\n\nYou have uncommitted changes; git stops if they overlap with the picked commits." }
        let alert = GitDialogs.confirmAlert(title: commits.count == 1 ? "Cherry-pick \(commits[0].shortHash)?" : "Cherry-pick \(commits.count) commits?",
                                            info: info, button: "Cherry-Pick")
        var parentPopup: NSPopUpButton?
        if let m = merges.first {
            let p = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
            for (i, h) in repo.parentHashes(m.hash).enumerated() { p.addItem(withTitle: "Keep parent \(i + 1) (\(String(h.prefix(7))))") }
            alert.accessoryView = p
            parentPopup = p
        }
        present(alert) { [weak self] r in
            guard r == .alertFirstButtonReturn else { return }
            let hashes = commits.map(\.hash)
            let mainline = parentPopup.map { $0.indexOfSelectedItem + 1 }
            self?.perform({ try $0.cherryPick(hashes, mainline: mainline) }, resets: true)
        }
    }

    private func logAction(_ action: GitLogAction, _ c: GitCommit) {
        switch action {
        case .copyHash:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(c.hash, forType: .string)
        case .checkout:
            let a = GitDialogs.confirmAlert(title: "Checkout \(c.shortHash)?", info: "HEAD will be detached at “\(c.subject)”. Create a branch to keep new commits.", button: "Checkout")
            present(a) { [weak self] r in
                guard r == .alertFirstButtonReturn else { return }
                self?.perform({ try $0.checkoutRevision(c.hash) }, resets: true)
            }
        case .createBranch:
            let (a, field) = GitDialogs.textAlert(title: "New Branch", info: "Create and check out a branch at \(c.shortHash).", placeholder: "branch-name", button: "Create")
            present(a) { [weak self] r in
                let name = field.stringValue.trimmingCharacters(in: .whitespaces)
                guard r == .alertFirstButtonReturn, !name.isEmpty else { return }
                self?.perform({ try $0.createBranch(name, at: c.hash, checkout: true) }, resets: true)
            }
        case .cherryPick: confirmCherryPick([c])
        case .cherryPickMany(let list): confirmCherryPick(list)
        case .revert: perform({ try $0.revertCommit(c.hash) }, resets: true)
        case .reset(let mode):
            if mode == .hard {
                let (a, field) = GitDialogs.textAlert(
                    title: "Hard reset to \(c.shortHash)?",
                    info: "The current branch moves to “\(c.subject)” and ALL uncommitted changes (\(changes.count) file\(changes.count == 1 ? "" : "s")) and later commits are discarded. Type RESET to confirm.",
                    placeholder: "RESET", button: "Hard Reset")
                a.buttons[0].hasDestructiveAction = true
                present(a) { [weak self] r in
                    guard r == .alertFirstButtonReturn, field.stringValue == "RESET" else { return }
                    self?.perform({ try $0.reset(to: c.hash, mode: .hard) }, resets: true)
                }
            } else {
                let a = GitDialogs.confirmAlert(title: "Reset current branch to \(c.shortHash)?",
                                                info: mode == .soft ? "Later commits are removed; their changes stay staged." : "Later commits are removed; their changes stay in the working tree, unstaged.",
                                                button: "Reset")
                present(a) { [weak self] r in
                    guard r == .alertFirstButtonReturn else { return }
                    self?.perform({ try $0.reset(to: c.hash, mode: mode) }, resets: true)
                }
            }
        }
    }

    // MARK: diff

    private func hideDiffs() {
        diffHost.subviews.compactMap { $0 as? SideBySideDiffView }.forEach { $0.isHidden = true }
        diffBar.isHidden = true
        active = nil
    }

    private func showDiffMessage(_ text: String) {
        hideDiffs()
        diffMessage.stringValue = text
        diffMessage.isHidden = false
    }

    private func mtime(of path: String) -> TimeInterval {
        let url = repo.root.appendingPathComponent(path)
        return ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
    }

    private func diffKey(_ c: GitChange, _ kind: GitGroupKind) -> String {
        "\(kind.rawValue)|\(c.path)|\(c.index)\(c.work)|\(mtime(of: c.path))"
    }

    /// Views of files without a partial selection are dropped; the rest keep their line checkboxes while another file is shown.
    private func pruneStageViews(keeping rowKey: String) {
        for (k, v) in stageViews where k != rowKey && v.view.checkedLineCount == v.view.changedLineCount {
            v.view.removeFromSuperview()
            stageViews[k] = nil
        }
    }

    private func resetSelections() {
        partial.removeAll()
        for (_, v) in stageViews { v.view.removeFromSuperview() }
        stageViews.removeAll()
        shownDiffKey = nil
        hideDiffs()
    }

    private func makeStageView() -> SideBySideDiffView {
        let v = SideBySideDiffView()
        v.translatesAutoresizingMaskIntoConstraints = false
        diffHost.addSubview(v)
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: diffBar.bottomAnchor),
            v.bottomAnchor.constraint(equalTo: diffHost.bottomAnchor),
            v.leadingAnchor.constraint(equalTo: diffHost.leadingAnchor),
            v.trailingAnchor.constraint(equalTo: diffHost.trailingAnchor),
        ])
        return v
    }

    private func present(_ v: SideBySideDiffView, rowKey: String, path: String, kind: GitGroupKind) {
        diffMessage.isHidden = true
        for sv in diffHost.subviews.compactMap({ $0 as? SideBySideDiffView }) { sv.isHidden = sv !== v }
        active = ActiveDiff(rowKey: rowKey, path: path, kind: kind, view: v)
        diffBar.isHidden = false
        updateDiffBar()
    }

    private func updateDiffBar() {
        guard let a = active else { return }
        let v = a.view
        let n = v.checkedLineCount, t = v.changedLineCount
        let picking = v.pickMode != .none
        let working = a.kind == .changes || a.kind == .untracked
        stageSelectedButton.isHidden = !picking
        stageSelectedButton.title = a.kind == .staged ? "Unstage Unchecked" : "Stage Selected"
        stageSelectedButton.isEnabled = a.kind == .staged ? (t > 0 && n < t) : n > 0
        editCheck.isHidden = !(working && picking)
        editCheck.state = editMode ? .on : .off
        diffInfo.stringValue = picking ? "\(n) of \(t) changed lines selected" : ""
        prevButton.isEnabled = v.changeCount > 0
        nextButton.isEnabled = v.changeCount > 0
    }

    @objc private func prevChange() { active?.view.previousChange() }
    @objc private func nextChange() { active?.view.nextChange() }

    @objc private func editToggled() {
        editMode = editCheck.state == .on
        for (k, v) in stageViews where k.hasPrefix("\(GitGroupKind.changes.rawValue)|") || k.hasPrefix("\(GitGroupKind.untracked.rawValue)|") {
            v.view.isNewSideEditable = editMode
        }
    }

    @objc private func stageSelectedTapped() {
        flushPendingWrite()
        guard let a = active else { return }
        let content = a.view.contentApplyingChecked()
        let path = a.path
        if a.kind == .staged { perform({ try $0.unstagePartial(path: path, content: content) }, resets: true) }
        else { perform({ try $0.stagePartial(path: path, content: content) }, resets: true) }
    }

    private func lineChecksChanged(path: String, kind: GitGroupKind, view v: SideBySideDiffView) {
        if kind == .changes || kind == .untracked, let c = changes.first(where: { $0.path == path }), isCommitPartialEligible(c) {
            let n = v.checkedLineCount, t = v.changedLineCount
            partial[path] = PartialSel(checked: n, total: t, content: (n > 0 && n < t) ? v.contentApplyingChecked() : "", mtime: mtime(of: path))
            if t > 0 { if n == 0 { checked.remove(path) } else { checked.insert(path) } }
            checksChanged()
        }
        if active?.view === v { updateDiffBar() }
    }

    private func scheduleWrite(_ path: String, _ text: String) {
        pendingWrite = (path, text)
        writeTimer?.invalidate()
        writeTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in self?.flushPendingWrite() }
    }

    /// Writes edits made in the diff's right pane to disk (atomic, keeps permissions, only when changed).
    private func flushPendingWrite() {
        writeTimer?.invalidate()
        writeTimer = nil
        guard let w = pendingWrite else { return }
        pendingWrite = nil
        let url = repo.root.appendingPathComponent(w.path)
        if (try? String(contentsOf: url, encoding: .utf8)) == w.text { return }
        let perms = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions]
        do {
            try w.text.write(to: url, atomically: true, encoding: .utf8)
            if let perms { try? FileManager.default.setAttributes([.posixPermissions: perms], ofItemAtPath: url.path) }
        } catch {
            showError(GitError(message: "Cannot write \(w.path): \(error.localizedDescription)"))
            return
        }
        // keep the shown diff's signature current so the refresh below does not rebuild it and lose line checks
        if let a = active, a.path == w.path, let c = changes.first(where: { $0.path == w.path }) {
            let key = diffKey(c, a.kind)
            shownDiffKey = key
            stageViews[a.rowKey]?.sig = key
        }
        if partial[w.path] != nil { partial[w.path]?.mtime = mtime(of: w.path) }
        onStatusChange?()
        reload()
    }

    private func showDiffForSelection(force: Bool) {
        if force { flushPendingWrite() }
        guard let row = selectedRow() else {
            shownDiffKey = nil
            showDiffMessage(groups.isEmpty ? "No changes" : "Select a file to see its changes")
            return
        }
        let c = row.change
        let kind = row.kind
        let key = diffKey(c, kind)
        if !force, key == shownDiffKey, let a = active, !a.view.isHidden { return }
        pruneStageViews(keeping: row.key)
        shownDiffKey = key
        diffToken += 1
        let token = diffToken
        if let stored = stageViews[row.key], stored.sig == key {
            present(stored.view, rowKey: row.key, path: c.path, kind: kind)
            return
        }
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
                    let pickable = kind != .conflicts && !(kind == .changes && c.work == "D") && !(kind == .staged && c.index == "D")
                    let v: SideBySideDiffView
                    if pickable {
                        self.stageViews[row.key]?.view.removeFromSuperview()
                        v = self.makeStageView()
                        self.stageViews[row.key] = (v, key)
                    } else { v = self.diffView }
                    let working = kind == .changes || kind == .untracked
                    v.pickMode = pickable ? .stage : .none
                    v.isNewSideEditable = pickable && working && self.editMode
                    v.isOldSideEditable = false
                    v.onNewSideEdited = pickable && working ? { [weak self] text in self?.scheduleWrite(c.path, text) } : nil
                    v.onCheckedChanged = pickable ? { [weak self, weak v] in
                        guard let self, let v else { return }
                        self.lineChecksChanged(path: c.path, kind: kind, view: v)
                    } : nil
                    v.show(old: old, new: new, oldTitle: oldT, newTitle: newT, fileExtension: (c.path as NSString).pathExtension)
                    self.present(v, rowKey: row.key, path: c.path, kind: kind)
                    if pickable { v.setAllChecked(kind == .staged || self.checked.contains(c.path)) }
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
                    self.hideDiffs()
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
        bannerIsNote = false
        capNoteShown = false
        styleBanner()
        bannerLabel.stringValue = (e as? GitError)?.message ?? e.localizedDescription
        banner.isHidden = false
        panel.needsLayout = true
    }

    private func showNote(_ text: String) {
        bannerIsNote = true
        styleBanner()
        bannerLabel.stringValue = text
        banner.isHidden = false
        panel.needsLayout = true
    }

    private func styleBanner() {
        let c = bannerIsNote ? GitColors.modified : GitColors.conflict
        banner.layer?.backgroundColor = c.withAlphaComponent(0.14).cgColor
        bannerLabel.textColor = bannerIsNote ? Theme.foreground : GitColors.conflict
    }

    /// Runs the alert as a sheet on the panel's window (modal fallback when it has none).
    private func present(_ alert: NSAlert, _ completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let w = panel.window, w.isVisible { alert.beginSheetModal(for: w, completionHandler: completion) }
        else { completion(alert.runModal()) }
    }

    @objc private func dismissBanner() { banner.isHidden = true }

    private func setBusy(_ on: Bool) {
        busy += on ? 1 : -1
        if busy > 0 { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        updateButtons()
    }

    /// Runs `work` serially off the main thread, then refreshes. Errors land in the banner.
    private func perform(_ work: @escaping (GitRepo) throws -> Void, done: (() -> Void)? = nil,
                         then: ((Error?) -> Void)? = nil, resets: Bool = false) {
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
                then?(error)
                if resets { self.resetSelections() }
                self.reload()
                self.onStatusChange?()
            }
        }
    }

    @objc private func fetchTapped() { perform { try $0.fetch() } }
    @objc private func pullTapped() { perform { try $0.pull() } }
    @objc private func pushTapped() { startPush(forcePreview: NSEvent.modifierFlags.contains(.option)) }

    /// Lists the commits about to be pushed and asks first (unless "Don't ask again" was ticked). Never forces.
    private func startPush(forcePreview: Bool = false) {
        guard busy == 0 else { return }
        setBusy(true)
        reader.async { [repo] in
            let r = Result { try repo.pushPreview() }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.setBusy(false)
                switch r {
                case .failure(let e): self.showError(e)
                case .success(let p):
                    if p.commits.isEmpty, !p.newBranch { self.showNote("Nothing to push: \(p.branch) is up to date with \(p.upstream ?? "its remote")."); return }
                    if GitDialogs.skipPushPreview, !forcePreview { self.perform({ try $0.push() }); return }
                    let (alert, dontAsk) = GitDialogs.pushAlert(p)
                    self.present(alert) { resp in
                        guard resp == .alertFirstButtonReturn else { return }
                        if dontAsk.state == .on { GitDialogs.skipPushPreview = true }
                        self.perform({ try $0.push() })
                    }
                }
            }
        }
    }

    private func updateButtons() {
        let idle = busy == 0
        for b in [fetchButton, pullButton, pushButton] { b.isEnabled = idle }
        let hasConflicts = groups.contains { $0.kind == .conflicts }
        let n = checkedPaths().isEmpty ? 0 : groups.flatMap(\.rows).filter { $0.kind != .conflicts && checked.contains($0.change.path) }
            .reduce(into: Set<String>()) { $0.insert($1.change.path) }.count
        countLabel.stringValue = hasConflicts ? "Resolve conflicts first" : "\(n) file\(n == 1 ? "" : "s") selected"
        rollbackButton.isEnabled = idle && !groups.isEmpty
        stashButton.isEnabled = idle
        let can = idle && !hasConflicts && (n > 0 || amendCheck.state == .on || merging)
        commitButton.isEnabled = can
        commitPushButton.isEnabled = can
    }

    @objc private func amendToggled() {
        updateButtons()
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
        flushPendingWrite()
        let paths = checkedPaths()
        var entries: [GitRepo.CommitEntry] = []
        var usesPartial = false
        for c in changes where checked.contains(c.path) && !c.isConflict {
            if let p = partial[c.path], p.checked > 0, p.checked < p.total, isCommitPartialEligible(c) {
                guard p.mtime == mtime(of: c.path) else {
                    showError(GitError(message: "\(c.path) changed on disk; review its selected lines again"))
                    return
                }
                entries.append(.init(path: c.path, content: p.content))
                usesPartial = true
            } else {
                entries.append(.init(path: c.path, content: nil))
                if let o = c.origPath { entries.append(.init(path: o, content: nil)) }
            }
        }
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
        var notes: [String] = []
        perform({ repo in
            if usesPartial { notes = try repo.commitPartial(message: message, entries: entries, amend: amend) }
            else { try repo.commit(message: message, paths: paths.isEmpty ? nil : paths, amend: amend) }
        }, then: { [weak self] error in
            guard let self, error == nil else { return }
            self.messageView.string = ""
            self.messageView.needsDisplay = true
            self.amendCheck.state = .off
            if !notes.isEmpty { self.showNote(notes.joined(separator: "\n")) }
            self.onCommitted?(push)
            if push { self.startPush() }
        }, resets: true)
    }

    // MARK: branches

    private func refreshBranchMenu() {
        branchButton.removeAllItems()
        var title = "\u{2387} " + (info.name.isEmpty ? "—" : info.name)
        if info.detached { title += " (detached HEAD)" }
        if repo.isLinkedWorktree { title += " [worktree]" }
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
        if onShowBranches != nil {
            let bp = NSMenuItem(title: "Branches… (⌘⌥B)", action: #selector(openBranchPopup), keyEquivalent: "")
            bp.target = self
            menu.addItem(bp)
            menu.addItem(.separator())
        }
        let nb = NSMenuItem(title: "New Branch…", action: #selector(newBranch), keyEquivalent: "")
        nb.target = self
        menu.addItem(nb)
        menu.addItem(.separator())
        header("Local Branches")
        for b in branches.local { branch(b, current: b == info.name && !info.detached) }
        // remote branches that already have a local counterpart are reached through the local entry
        let remotes = branches.remote.filter { r in
            guard let slash = r.firstIndex(of: "/") else { return true }
            return !branches.local.contains(String(r[r.index(after: slash)...]))
        }
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

    @objc private func openBranchPopup() { onShowBranches?() }

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
