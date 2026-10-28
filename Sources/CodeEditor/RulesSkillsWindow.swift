import AppKit

/// File > Rules & Skills…: the tree of every instruction file that applies to the project (project, global, memory) with an editor
/// next to it. Rows Claude added or changed since the user last looked carry a badge; opening one shows what changed and clears it.
/// Built on demand, scanned on open and after our own actions, never watched. Released on close.
final class RulesSkillsWindowController: NSObject, NSWindowDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTextViewDelegate, NSSearchFieldDelegate {
    private static var current: RulesSkillsWindowController?

    private final class Node {
        let scope: RulesSkills.Scope?
        let item: RulesSkills.Item?
        var children: [Node] = []
        init(scope: RulesSkills.Scope) { self.scope = scope; item = nil }
        init(item: RulesSkills.Item) { self.item = item; scope = nil }
    }

    private let root: URL
    private var items: [RulesSkills.Item] = []
    private var store = RulesSkills.Store()
    private var sections: [Node] = []
    private var filter = ""
    private var selected: RulesSkills.Item?
    private var original = ""
    private var dirty = false
    private var restoringSelection = false

    private var window: NSWindow?
    private let outline = NSOutlineView()
    private let search = NSSearchField()
    private let pathLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let modeControl = NSSegmentedControl(labels: ["Edit", "Changes"], trackingMode: .selectOne, target: nil, action: nil)
    private let editor = NSTextView(), changes = NSTextView()
    private var editorScroll = NSScrollView(), changesScroll = NSScrollView()
    private let saveButton = NSButton(title: "Save", target: nil, action: nil)
    private let disableButton = NSButton(title: "Disable", target: nil, action: nil)
    private let moveButton = NSButton(title: "Move to Global", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Move to Trash", target: nil, action: nil)
    private let revealButton = NSButton(title: "Reveal", target: nil, action: nil)
    private let summary = NSTextField(labelWithString: "")

    static func show(root: URL) {
        guard !AppEnv.headless else { return }
        if let c = current { c.window?.makeKeyAndOrderFront(nil); c.reload(); return }
        let c = RulesSkillsWindowController(root: root)
        current = c
        c.build()
    }

    private init(root: URL) { self.root = root }

    // MARK: window

    /// Headless render for verification (nothing is shown); uses whatever ~/.claude and state file the caller pointed at.
    static func render(root: URL, to path: String) {
        let c = RulesSkillsWindowController(root: root)
        c.build(show: false)
        c.apply(RulesSkills.scan(projectRoot: root), select: nil)
        guard let v = c.window?.contentView else { return }
        v.frame = NSRect(x: 0, y: 0, width: 980, height: 640)
        v.layoutSubtreeIfNeeded()
        v.appearance = NSAppearance(named: .aqua)
        if let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
            v.cacheDisplay(in: v.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
    }

    private func build(show: Bool = true) {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 640), styleMask: [.titled, .closable, .resizable, .miniaturizable],
                         backing: .buffered, defer: false)
        w.title = "Rules & Skills — \(root.lastPathComponent)"
        w.delegate = self
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 760, height: 440)
        window = w

        // left: filter + tree + add menu
        search.placeholderString = "Filter"; search.delegate = self
        let add = NSPopUpButton(frame: .zero, pullsDown: true)
        add.addItem(withTitle: "+ Add")
        for (title, sel) in [("New Rule…", #selector(newRule)), ("New Skill…", #selector(newSkill))] {
            let it = NSMenuItem(title: title, action: sel, keyEquivalent: ""); it.target = self; add.menu?.addItem(it)
        }
        add.controlSize = .small
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c")); col.resizingMask = .autoresizingMask
        outline.addTableColumn(col); outline.outlineTableColumn = col; outline.headerView = nil
        outline.dataSource = self; outline.delegate = self; outline.rowHeight = 24; outline.indentationPerLevel = 14
        outline.style = .inset
        let treeScroll = NSScrollView(); treeScroll.documentView = outline; treeScroll.hasVerticalScroller = true
        let treeTop = NSStackView(views: [search, add]); treeTop.spacing = 6
        let left = NSStackView(views: [treeTop, treeScroll]); left.orientation = .vertical; left.spacing = 6; left.alignment = .leading
        left.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 6)
        for v in [treeTop, treeScroll] { v.translatesAutoresizingMaskIntoConstraints = false; v.widthAnchor.constraint(equalTo: left.widthAnchor, constant: -16).isActive = true }

        // right: header, editor / changes, actions
        pathLabel.font = .systemFont(ofSize: 15, weight: .semibold); pathLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.font = .systemFont(ofSize: 11); statusLabel.textColor = .secondaryLabelColor
        modeControl.target = self; modeControl.action = #selector(modeChanged); modeControl.selectedSegment = 0
        for tv in [editor, changes] {
            tv.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
            tv.isAutomaticQuoteSubstitutionEnabled = false; tv.isAutomaticDashSubstitutionEnabled = false; tv.isAutomaticSpellingCorrectionEnabled = false
            tv.textContainerInset = NSSize(width: 6, height: 8)
            tv.isVerticallyResizable = true; tv.autoresizingMask = [.width]
        }
        editor.delegate = self; editor.allowsUndo = true
        changes.isEditable = false
        for (s, tv) in [(editorScroll, editor), (changesScroll, changes)] { s.documentView = tv; s.hasVerticalScroller = true; s.borderType = .bezelBorder }
        changesScroll.isHidden = true

        saveButton.target = self; saveButton.action = #selector(save); saveButton.bezelStyle = .rounded; saveButton.keyEquivalent = "s"; saveButton.keyEquivalentModifierMask = .command
        disableButton.target = self; disableButton.action = #selector(toggleDisabled); disableButton.bezelStyle = .rounded
        moveButton.target = self; moveButton.action = #selector(moveScope); moveButton.bezelStyle = .rounded
        deleteButton.target = self; deleteButton.action = #selector(trash); deleteButton.bezelStyle = .rounded
        revealButton.target = self; revealButton.action = #selector(reveal); revealButton.bezelStyle = .rounded
        summary.font = .systemFont(ofSize: 11); summary.textColor = .secondaryLabelColor
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let actions = NSStackView(views: [disableButton, moveButton, revealButton, deleteButton, spacer, saveButton]); actions.spacing = 8
        let titles = NSStackView(views: [pathLabel, statusLabel]); titles.orientation = .vertical; titles.alignment = .leading; titles.spacing = 2
        let head = NSStackView(views: [titles, modeControl]); head.alignment = .top
        let body = NSView()
        for s in [editorScroll, changesScroll] { s.translatesAutoresizingMaskIntoConstraints = false; body.addSubview(s)
            NSLayoutConstraint.activate([s.leadingAnchor.constraint(equalTo: body.leadingAnchor), s.trailingAnchor.constraint(equalTo: body.trailingAnchor),
                                         s.topAnchor.constraint(equalTo: body.topAnchor), s.bottomAnchor.constraint(equalTo: body.bottomAnchor)]) }
        let right = NSStackView(views: [head, body, summary, actions]); right.orientation = .vertical; right.alignment = .leading; right.spacing = 8
        right.edgeInsets = NSEdgeInsets(top: 12, left: 8, bottom: 12, right: 16)
        for v in [head, body, actions] { v.translatesAutoresizingMaskIntoConstraints = false; v.widthAnchor.constraint(equalTo: right.widthAnchor, constant: -24).isActive = true }
        body.setContentHuggingPriority(.defaultLow, for: .vertical)

        let split = NSSplitView(); split.isVertical = true; split.dividerStyle = .thin
        split.addArrangedSubview(left); split.addArrangedSubview(right)
        left.widthAnchor.constraint(greaterThanOrEqualToConstant: 250).isActive = true
        left.widthAnchor.constraint(lessThanOrEqualToConstant: 380).isActive = true
        split.setHoldingPriority(.defaultHigh, forSubviewAt: 0)
        w.contentView = split
        showEmpty()
        guard show else { return }
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        reload()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { resolveDirty() }
    func windowWillClose(_ notification: Notification) { Self.current = nil; window = nil; items = []; sections = []; store = RulesSkills.Store() }

    // MARK: data

    private func reload(select path: String? = nil) {
        let root = self.root
        let keep = path ?? selected?.key
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let found = RulesSkills.scan(projectRoot: root)
            DispatchQueue.main.async { self?.apply(found, select: keep) }
        }
    }

    private func apply(_ found: [RulesSkills.Item], select path: String?) {
        items = found
        store = RulesSkills.loadStore()
        var seeded = store
        RulesSkills.seedIfNeeded(projectRoot: root, items: items, store: &seeded)
        if seeded.projects != store.projects { store = seeded; RulesSkills.saveStore(store) }
        rebuildTree()
        if let path, let item = items.first(where: { $0.key == path }) { select(item, userInitiated: false) }
        else if selected == nil, let first = items.first(where: { RulesSkills.status($0, in: store) != .seen }) { select(first, userInitiated: false) }
        updateSummary()
    }

    private func rebuildTree() {
        let q = filter.lowercased()
        sections = RulesSkills.Scope.allCases.map { sc in
            let n = Node(scope: sc)
            n.children = items.filter { $0.scope == sc && (q.isEmpty || $0.title.lowercased().contains(q)) }.map { Node(item: $0) }
            return n
        }
        outline.reloadData()
        for s in sections where s.scope != .memory || !q.isEmpty { outline.expandItem(s) }
    }

    private func updateSummary() {
        let c = RulesSkills.counts(items, in: store)
        let new = c.values.reduce(0, +)
        summary.stringValue = "\(items.count) files apply to this project" + (new > 0 ? " · \(new) new or changed since you last looked" : "")
    }

    // MARK: outline

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { (item as? Node)?.children.count ?? sections.count }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { (item as? Node)?.children[index] ?? sections[index] }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { (item as? Node)?.scope != nil }
    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool { (item as? Node)?.item != nil }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let n = item as? Node else { return nil }
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: ""); label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(label)
        let badge = NSTextField(labelWithString: ""); badge.font = .systemFont(ofSize: 10, weight: .semibold); badge.alignment = .center
        badge.wantsLayer = true; badge.layer?.cornerRadius = 7; badge.layer?.masksToBounds = true
        badge.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(badge)
        NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2), label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                                     badge.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6), badge.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                                     label.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -6)])
        if let sc = n.scope {
            let fresh = n.children.filter { RulesSkills.status($0.item!, in: store) != .seen }.count
            label.stringValue = sc.title.uppercased() + "  ·  \(n.children.count)"; label.font = .systemFont(ofSize: 11, weight: .semibold); label.textColor = .secondaryLabelColor
            setBadge(badge, fresh > 0 ? "\(fresh)" : nil, color: .systemGreen)
        } else if let it = n.item {
            let st = RulesSkills.status(it, in: store)
            label.stringValue = (it.kind == .skill ? "◆ " : "") + it.title + (it.disabled ? "  (disabled)" : "")
            label.font = .systemFont(ofSize: 13, weight: st == .seen ? .regular : .semibold)
            label.textColor = it.disabled ? .tertiaryLabelColor : .labelColor
            setBadge(badge, st == .new ? "new" : st == .changed ? "changed" : nil, color: st == .new ? .systemGreen : .systemOrange)
        }
        return cell
    }

    private func setBadge(_ b: NSTextField, _ text: String?, color: NSColor) {
        b.isHidden = text == nil
        b.stringValue = text.map { " \($0) " } ?? ""
        b.textColor = .white
        b.layer?.backgroundColor = color.cgColor
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !restoringSelection, let n = outline.item(atRow: outline.selectedRow) as? Node, let it = n.item else { return }
        if it.key == selected?.key { return }
        guard resolveDirty() else { restoreSelection(); return }
        select(it, userInitiated: true)
    }

    private func restoreSelection() {
        guard let key = selected?.key else { return }
        restoringSelection = true
        for r in 0..<outline.numberOfRows where (outline.item(atRow: r) as? Node)?.item?.key == key { outline.selectRowIndexes([r], byExtendingSelection: false) }
        restoringSelection = false
    }

    func controlTextDidChange(_ obj: Notification) { filter = search.stringValue; rebuildTree(); restoreSelection() }

    // MARK: selection

    private func showEmpty() {
        selected = nil; dirty = false
        pathLabel.stringValue = "Rules & Skills"
        statusLabel.stringValue = "Pick a file on the left."
        editor.string = ""; editor.isEditable = false; changes.string = ""
        for b in [saveButton, disableButton, moveButton, deleteButton, revealButton] { b.isEnabled = false }
        modeControl.isEnabled = false
    }

    private func select(_ it: RulesSkills.Item, userInitiated: Bool) {
        let text = (try? String(contentsOf: it.file, encoding: .utf8)) ?? ""
        let st = RulesSkills.status(it, in: store)
        let before = store.files[it.key]?.text
        selected = it; original = text; dirty = false
        editor.isEditable = true
        editor.string = text
        let home = NSHomeDirectory()
        pathLabel.stringValue = it.title
        statusLabel.stringValue = it.kind.label + " · " + it.scope.title + " · " + it.file.path.replacingOccurrences(of: home, with: "~")
            + (st == .new ? " · new since you last looked" : st == .changed ? " · changed since you last looked" : "")
        renderChanges(status: st, before: before, now: text)
        modeControl.isEnabled = true
        modeControl.selectedSegment = st == .seen ? 0 : 1
        modeChanged()
        for b in [disableButton, deleteButton, revealButton] { b.isEnabled = true }
        disableButton.title = it.disabled ? "Enable" : "Disable"
        let movable = [.rule, .skill, .command].contains(it.kind) && it.scope != .memory
        moveButton.isEnabled = movable
        moveButton.title = it.scope == .project ? "Move to Global" : "Move to Project"
        saveButton.isEnabled = false
        // looking at it clears the badge
        if st != .seen {
            RulesSkills.markSeen(it, text: text, in: &store)
            RulesSkills.saveStore(store)
            outline.reloadData()
            for s in sections where s.scope != .memory || !filter.isEmpty { outline.expandItem(s) }
            restoreSelection()
        }
        if !userInitiated { restoreSelection() }
        updateSummary()
    }

    private func renderChanges(status: RulesSkills.Status, before: String?, now: String) {
        let mono = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        let out = NSMutableAttributedString()
        func line(_ s: String, _ bg: NSColor?, _ fg: NSColor = .labelColor) {
            var a: [NSAttributedString.Key: Any] = [.font: mono, .foregroundColor: fg]
            if let bg { a[.backgroundColor] = bg }
            out.append(NSAttributedString(string: s + "\n", attributes: a))
        }
        switch status {
        case .seen: line("Nothing changed since you last looked.", nil, .secondaryLabelColor)
        case .new: line("New file. You have not seen it before; its text is on the Edit tab.", nil, .secondaryLabelColor)
        case .changed:
            if let before {
                for d in RulesSkills.diff(old: before, new: now) {
                    switch d.kind {
                    case .same: line("   " + d.text, nil, .secondaryLabelColor)
                    case .added: line(" + " + d.text, NSColor.systemGreen.withAlphaComponent(0.22))
                    case .removed: line(" - " + d.text, NSColor.systemRed.withAlphaComponent(0.22))
                    }
                }
            } else { line("Changed, but the earlier text was too large to keep for comparison.", nil, .secondaryLabelColor) }
        }
        changes.textStorage?.setAttributedString(out)
    }

    @objc private func modeChanged() {
        let showChanges = modeControl.selectedSegment == 1
        changesScroll.isHidden = !showChanges
        editorScroll.isHidden = showChanges
    }

    // MARK: editing

    func textDidChange(_ notification: Notification) {
        dirty = editor.string != original
        saveButton.isEnabled = dirty
        statusLabel.stringValue = statusLabel.stringValue.replacingOccurrences(of: " · unsaved", with: "") + (dirty ? " · unsaved" : "")
    }

    @objc private func save() {
        guard let it = selected, dirty else { return }
        do {
            try editor.string.write(to: it.file, atomically: true, encoding: .utf8)
        } catch { return alert("Could not save", error.localizedDescription) }
        original = editor.string; dirty = false; saveButton.isEnabled = false
        statusLabel.stringValue = statusLabel.stringValue.replacingOccurrences(of: " · unsaved", with: "")
        // our own edit is something the user has seen
        reload(select: it.key)
        DispatchQueue.main.async { [weak self] in
            guard let self, let cur = self.items.first(where: { $0.key == it.key }) else { return }
            RulesSkills.markSeen(cur, text: self.original, in: &self.store); RulesSkills.saveStore(self.store)
            self.outline.reloadData(); self.restoreSelection()
        }
    }

    /// Returns false when the user cancelled.
    private func resolveDirty() -> Bool {
        guard dirty, selected != nil else { return true }
        let a = NSAlert()
        a.messageText = "Save changes to \(selected?.title ?? "this file")?"
        a.addButton(withTitle: "Save"); a.addButton(withTitle: "Discard"); a.addButton(withTitle: "Cancel")
        switch a.runModal() {
        case .alertFirstButtonReturn: save(); return !dirty
        case .alertSecondButtonReturn: dirty = false; return true
        default: return false
        }
    }

    // MARK: actions

    @objc private func newRule() { create(.rule) }
    @objc private func newSkill() { create(.skill) }

    private func create(_ what: RulesSkills.Creatable) {
        guard resolveDirty() else { return }
        let scope: RulesSkills.Scope = selected?.scope == .global ? .global : .project
        let a = NSAlert()
        a.messageText = "New \(what == .rule ? "rule" : "skill") in \(scope.title)"
        a.informativeText = scope == .project ? "Created in this project's .claude folder." : "Created in ~/.claude and applies to every project."
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24)); f.placeholderString = what == .rule ? "api-style" : "deploy"
        a.accessoryView = f
        a.addButton(withTitle: "Create"); a.addButton(withTitle: "Cancel")
        a.window.initialFirstResponder = f
        guard a.runModal() == .alertFirstButtonReturn else { return }
        do {
            let url = try RulesSkills.create(what, named: f.stringValue, scope: scope, projectRoot: root)
            selected = nil
            reload(select: url.path)
        } catch { alert("Could not create it", error.localizedDescription) }
    }

    @objc private func toggleDisabled() {
        guard let it = selected, resolveDirty() else { return }
        do { let url = try RulesSkills.setDisabled(it, !it.disabled); selected = nil; reload(select: url.path) } catch { alert("Could not change it", error.localizedDescription) }
    }

    @objc private func moveScope() {
        guard let it = selected, resolveDirty() else { return }
        let to: RulesSkills.Scope = it.scope == .project ? .global : .project
        do { let url = try RulesSkills.move(it, to: to, projectRoot: root); selected = nil; reload(select: url.path) } catch { alert("Could not move it", error.localizedDescription) }
    }

    @objc private func reveal() { if let it = selected { NSWorkspace.shared.activateFileViewerSelecting([it.container]) } }

    @objc private func trash() {
        guard let it = selected, let w = window else { return }
        let a = NSAlert()
        a.messageText = "Move \(it.title) to the Trash?"
        a.informativeText = it.scope == .global ? "This is a global file: Claude stops using it in every project. You can restore it from the Trash." : "Claude stops using it in this project. You can restore it from the Trash."
        a.addButton(withTitle: "Move to Trash"); a.addButton(withTitle: "Cancel")
        a.beginSheetModal(for: w) { [weak self] r in
            guard r == .alertFirstButtonReturn, let self else { return }
            do { try RulesSkills.trash(it); self.dirty = false; self.store.files[it.key] = nil; RulesSkills.saveStore(self.store); self.showEmpty(); self.reload() }
            catch { self.alert("Could not move it", error.localizedDescription) }
        }
    }

    private func alert(_ title: String, _ text: String) {
        let a = NSAlert(); a.messageText = title; a.informativeText = text; a.runModal()
    }
}

extension ProjectWindow {
    func showRulesSkills() {
        guard let root else { return }
        RulesSkillsWindowController.show(root: root)
    }
}
