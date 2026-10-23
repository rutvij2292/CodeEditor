import AppKit

// MARK: - Keymap

struct KeymapEntry: Equatable {
    let id: String            // KeymapStore identity ("selector|title")
    let group: String         // "Edit › Find"
    let title: String
    let shortcut: String      // "⇧⌘F" or ""
    let conflict: String?     // macOS system shortcut this one collides with
    let isCustom: Bool        // differs from the shipped binding
    var path: String { group.isEmpty ? title : group + " › " + title }
}

enum Keymap {
    /// macOS system shortcuts that commonly swallow or collide with editor shortcuts.
    static let systemShortcuts: [String: String] = [
        "⌃Space": "macOS: Select previous input source (disable in System Settings › Keyboard › Shortcuts)",
        "⌃⌥Space": "macOS: Select next input source",
        "⌘Space": "macOS: Spotlight",
        "⌥⌘Space": "macOS: Finder search",
        "⌘`": "macOS: Switch windows of the app",
        "⌘⇧3": "macOS: Screenshot", "⌘⇧4": "macOS: Screenshot", "⌘⇧5": "macOS: Screenshot",
        "⌥⌘D": "macOS: Show/hide Dock",
        "⌃↑": "macOS: Mission Control", "⌃↓": "macOS: Application windows",
        "⌃←": "macOS: Move to left Space", "⌃→": "macOS: Move to right Space",
    ]

    /// Every leaf menu item of `menu` with its group and shortcut text. Pure function.
    static func entries(from menu: NSMenu) -> [KeymapEntry] {
        let overrides = KeymapStore.load()
        return KeymapStore.leaves(of: menu).compactMap { item, group in
            guard let id = KeymapStore.identity(of: item) else { return nil }
            let key = MainMenu.shortcutText(for: item)
            let custom = overrides[id].map { $0 != KeymapStore.factory[id] } ?? false
            return KeymapEntry(id: id, group: group, title: item.title, shortcut: key,
                               conflict: key.isEmpty ? nil : systemShortcuts[key], isCustom: custom)
        }
    }

    static func filter(_ entries: [KeymapEntry], query: String) -> [KeymapEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return entries }
        return entries.filter { $0.path.lowercased().contains(q) || $0.shortcut.lowercased().contains(q) }
    }
}

final class KeymapPane: SettingsPane, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private var all: [KeymapEntry] = []
    private var shown: [KeymapEntry] = []
    private let table = NSTableView()
    private let search = NSSearchField()
    private let count = NSTextField(labelWithString: "")
    private let status = NSTextField(labelWithString: "")
    private let recordButton = NSButton(title: "Set Shortcut…", target: nil, action: nil)
    private let removeButton = NSButton(title: "Remove", target: nil, action: nil)
    private let resetButton = NSButton(title: "Reset", target: nil, action: nil)
    private let resetAllButton = NSButton(title: "Reset All…", target: nil, action: nil)
    /// Only installed while recording a shortcut (no standing monitor).
    private var recorder: Any?
    private var recordingID: String?
    /// Overridable for tests / headless rendering.
    var menuProvider: () -> NSMenu? = { NSApp.mainMenu }

    override func loadView() {
        let root = NSView(frame: NSRect(origin: .zero, size: SettingsWindowController.contentSize))
        search.placeholderString = "Search commands or shortcuts"
        search.delegate = self
        search.setAccessibilityLabel("Search keymap")
        let cols = [("group", "Group", CGFloat(120)), ("command", "Command", CGFloat(300)), ("shortcut", "Shortcut", CGFloat(90)), ("note", "Note", CGFloat(150))]
        for (id, title, width) in cols {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            c.title = title
            c.width = width
            c.minWidth = 60
            table.addTableColumn(c)
        }
        table.dataSource = self
        table.delegate = self
        table.usesAlternatingRowBackgroundColors = true
        table.rowHeight = 20
        table.target = self
        table.doubleAction = #selector(startRecording)
        table.setAccessibilityLabel("Keyboard shortcuts")
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        for (b, sel) in [(recordButton, #selector(startRecording)), (removeButton, #selector(removeShortcut)),
                         (resetButton, #selector(resetOne)), (resetAllButton, #selector(resetEverything))] {
            b.target = self; b.action = sel; b.bezelStyle = .rounded; b.controlSize = .small
        }
        let buttons = NSStackView(views: [recordButton, removeButton, resetButton, resetAllButton])
        buttons.spacing = 8
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        let note = NSTextField(wrappingLabelWithString: "Shortcuts default to PhpStorm's macOS keymap. Select a command and click Set Shortcut (or double-click it), then press the new keys; Escape cancels. Customised shortcuts are saved and show in menus, Find Action and tooltips. Some keys are fixed in code and cannot be remapped: Escape, Shift-Escape, Double-Shift, ⌘⌫ / ⌘N / ⇧F6 in the project tree, and ⇧⌘[ / ] inside tool windows.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        count.font = .systemFont(ofSize: 11)
        count.textColor = .secondaryLabelColor
        for v in [search, scroll, buttons, status, note, count] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(v) }
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            search.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            search.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: search.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: search.trailingAnchor),
            buttons.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 8),
            buttons.leadingAnchor.constraint(equalTo: search.leadingAnchor),
            status.centerYAnchor.constraint(equalTo: buttons.centerYAnchor),
            status.leadingAnchor.constraint(equalTo: buttons.trailingAnchor, constant: 12),
            status.trailingAnchor.constraint(equalTo: search.trailingAnchor),
            note.topAnchor.constraint(equalTo: buttons.bottomAnchor, constant: 8),
            note.leadingAnchor.constraint(equalTo: search.leadingAnchor), note.trailingAnchor.constraint(equalTo: search.trailingAnchor),
            count.topAnchor.constraint(equalTo: note.bottomAnchor, constant: 6),
            count.leadingAnchor.constraint(equalTo: search.leadingAnchor),
            count.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),
        ])
        view = root
        reload()
    }

    override func viewWillDisappear() { super.viewWillDisappear(); stopRecording() }

    // MARK: data

    func reload() {
        let keepID = selected?.id
        all = menuProvider().map(Keymap.entries(from:)) ?? []
        applyFilter()
        if let keepID, let row = shown.firstIndex(where: { $0.id == keepID }) { table.selectRowIndexes([row], byExtendingSelection: false) }
    }

    private func applyFilter() {
        shown = Keymap.filter(all, query: search.stringValue)
        table.reloadData()
        let dupes = (menuProvider().map(MainMenu.duplicateShortcuts(in:)) ?? []).count
        let custom = all.filter(\.isCustom).count
        count.stringValue = "\(shown.count) of \(all.count) commands" + (custom > 0 ? " · \(custom) customised" : "")
            + (dupes > 0 ? " · \(dupes) duplicate shortcuts" : "")
    }

    private var selected: KeymapEntry? { table.selectedRow >= 0 && table.selectedRow < shown.count ? shown[table.selectedRow] : nil }

    func controlTextDidChange(_ obj: Notification) { applyFilter() }
    func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier.rawValue, row < shown.count else { return nil }
        let e = shown[row]
        var text: String
        switch id {
        case "group": text = e.group
        case "command": text = e.title
        case "shortcut": text = recordingID == e.id ? "Press keys…" : e.shortcut
        default: text = e.isCustom ? "customised" : (e.conflict ?? "")
        }
        let cell = NSTextField(labelWithString: text)
        cell.lineBreakMode = .byTruncatingTail
        cell.font = id == "shortcut" ? .monospacedSystemFont(ofSize: 12, weight: e.isCustom ? .semibold : .regular)
                                     : .systemFont(ofSize: id == "note" || id == "group" ? 11 : 12)
        if id == "note" { cell.textColor = e.isCustom ? .controlAccentColor : .systemOrange; cell.toolTip = e.conflict }
        if id == "group" { cell.textColor = .secondaryLabelColor }
        return cell
    }

    // MARK: editing

    @objc private func startRecording() {
        guard let e = selected else { status.stringValue = "Select a command first."; return }
        stopRecording()
        recordingID = e.id
        status.stringValue = "Press the new shortcut for “\(e.title)” (Escape cancels)…"
        table.reloadData(forRowIndexes: [table.selectedRow], columnIndexes: [2])
        recorder = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.recordingID != nil else { return event }
            if event.keyCode == 53, event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
                self.stopRecording(); self.status.stringValue = ""; return nil
            }
            if let b = KeyBinding.from(event: event) { self.commit(b, forID: e.id, title: e.title) }
            else { self.status.stringValue = "Use a shortcut with ⌘, ⌥ or ⌃ (or a function key)…" }
            return nil          // swallow: menu key equivalents must not fire while recording
        }
    }

    private func stopRecording() {
        if let r = recorder { NSEvent.removeMonitor(r) }
        recorder = nil
        recordingID = nil
        if isViewLoaded { table.reloadData() }
    }

    /// Applies `binding` after resolving conflicts (asks to reassign / confirm; headless runs refuse).
    func commit(_ binding: KeyBinding, forID id: String, title: String) {
        stopRecording()
        guard let menu = menuProvider() else { return }
        let conflicts = KeymapStore.conflicts(for: binding, excluding: id, in: menu)
        var unbind: [String] = []
        if !conflicts.isEmpty {
            let lines = conflicts.map { "• " + $0.message }.joined(separator: "\n")
            let hasCommand = conflicts.contains { if case .command = $0.kind { return true }; return false }
            guard !AppEnv.headless else { status.stringValue = "\(binding.text) is in conflict; not changed."; return }
            let alert = NSAlert()
            alert.messageText = "\(binding.text) is already in use"
            alert.informativeText = lines + (hasCommand ? "\n\nReassign it to “\(title)” and remove it from the other command?" : "\n\nUse it anyway?")
            alert.addButton(withTitle: hasCommand ? "Reassign" : "Use Anyway")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { status.stringValue = "Cancelled."; return }
            unbind = conflicts.compactMap { if case .command(let other, _) = $0.kind { return other }; return nil }
        }
        KeymapStore.set(id, binding, unbinding: unbind, menu: menu)
        status.stringValue = "“\(title)” is now \(binding.text)."
        reload()
    }

    @objc private func removeShortcut() {
        guard let e = selected, let menu = menuProvider() else { return }
        KeymapStore.set(e.id, .unbound, menu: menu)
        status.stringValue = "Removed the shortcut of “\(e.title)”."
        reload()
    }

    @objc private func resetOne() {
        guard let e = selected, let menu = menuProvider() else { return }
        KeymapStore.reset(e.id, menu: menu)
        status.stringValue = "Reset “\(e.title)”."
        reload()
    }

    @objc private func resetEverything() {
        guard let menu = menuProvider(), confirm("Reset all shortcuts?", detail: "Every command returns to its default shortcut.", button: "Reset All") else { return }
        KeymapStore.resetAll(menu: menu)
        status.stringValue = "All shortcuts reset."
        reload()
    }
}
