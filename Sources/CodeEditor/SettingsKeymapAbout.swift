import AppKit

// MARK: - Keymap

struct KeymapEntry: Equatable {
    let path: String          // "Edit › Find in Files…"
    let shortcut: String      // "⇧⌘F" or ""
    let conflict: String?     // macOS system shortcut this one collides with
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

    /// Every leaf menu item of `menu` with its title path and shortcut text. Pure function.
    static func entries(from menu: NSMenu) -> [KeymapEntry] {
        var out: [KeymapEntry] = []
        func walk(_ m: NSMenu, path: [String]) {
            for item in m.items where !item.isSeparatorItem {
                if let sub = item.submenu, item.keyEquivalent.isEmpty {
                    if sub.title != "Open Recent" { walk(sub, path: path + [item.title]) }   // Open Recent is a dynamic list
                    continue
                }
                let key = MainMenu.shortcutText(for: item)
                out.append(KeymapEntry(path: (path + [item.title]).joined(separator: " › "), shortcut: key,
                                       conflict: key.isEmpty ? nil : systemShortcuts[key]))
            }
        }
        for top in menu.items { if let sub = top.submenu { walk(sub, path: [top.title]) } }
        return out
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
    /// Overridable for tests / headless rendering.
    var menuProvider: () -> NSMenu? = { NSApp.mainMenu }

    override func loadView() {
        let root = NSView(frame: NSRect(origin: .zero, size: SettingsWindowController.contentSize))
        search.placeholderString = "Search commands or shortcuts"
        search.delegate = self
        search.setAccessibilityLabel("Search keymap")
        let cols = [("command", "Command", CGFloat(420)), ("shortcut", "Shortcut", CGFloat(110)), ("note", "Note", CGFloat(160))]
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
        table.setAccessibilityLabel("Keyboard shortcuts")
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let note = NSTextField(wrappingLabelWithString: "Shortcuts follow PhpStorm's macOS keymap (⌘O Go to Class, ⇧⌘O Go to File, ⌥⌘L Reformat, ⌘B Declaration). They are read from the menu bar, so what you see here is what works. Remapping is not supported yet. Folding uses ⌘− / ⌘= like PhpStorm; the tree's Collapse All moved to ⌃⌘−.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        count.font = .systemFont(ofSize: 11)
        count.textColor = .secondaryLabelColor
        for v in [search, scroll, note, count] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(v) }
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            search.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            search.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: search.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: search.trailingAnchor),
            note.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 10),
            note.leadingAnchor.constraint(equalTo: search.leadingAnchor), note.trailingAnchor.constraint(equalTo: search.trailingAnchor),
            count.topAnchor.constraint(equalTo: note.bottomAnchor, constant: 6),
            count.leadingAnchor.constraint(equalTo: search.leadingAnchor),
            count.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),
        ])
        view = root
        all = menuProvider().map(Keymap.entries(from:)) ?? []
        applyFilter()
    }

    private func applyFilter() {
        shown = Keymap.filter(all, query: search.stringValue)
        table.reloadData()
        let dupes = (menuProvider().map(MainMenu.duplicateShortcuts(in:)) ?? []).count
        count.stringValue = "\(shown.count) of \(all.count) commands" + (dupes > 0 ? " · \(dupes) duplicate shortcuts" : "")
    }

    func controlTextDidChange(_ obj: Notification) { applyFilter() }
    func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier.rawValue, row < shown.count else { return nil }
        let e = shown[row]
        let text: String
        switch id {
        case "command": text = e.path
        case "shortcut": text = e.shortcut
        default: text = e.conflict ?? ""
        }
        let cell = NSTextField(labelWithString: text)
        cell.lineBreakMode = .byTruncatingTail
        cell.font = id == "shortcut" ? .monospacedSystemFont(ofSize: 12, weight: .regular) : .systemFont(ofSize: id == "note" ? 11 : 12)
        if id == "note" { cell.textColor = .systemOrange; cell.toolTip = e.conflict }
        return cell
    }
}

// MARK: - About

final class AboutPane: SettingsPane {
    static let repoURL = Brand.repoURL
    private var timer: Timer?
    private var historySize: UInt64?
    private var cacheSize: UInt64?

    private static var cachesRoot: URL { URL(fileURLWithPath: NSHomeDirectory() + "/Library/Caches/CodeEditor", isDirectory: true) }

    override func build() {
        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String) ?? "development build"
        let build = (info?["CFBundleVersion"] as? String).map { " (\($0))" } ?? ""
        section(Brand.name)
        row("Version", infoLabel { version + build })
        row("Source", infoLabel { Self.repoURL })

        section("Memory")
        row("This app", infoLabel { SystemStats.megabytes(SystemStats.physFootprint()) + " physical footprint" })
        row("Language servers", infoLabel {
            let all = LanguageServers.statuses()
            return all.isEmpty ? "None running" : "\(all.count) running · " + SystemStats.megabytes(all.reduce(UInt64(0)) { $0 + $1.rssBytes })
        })
        row("Total", infoLabel {
            SystemStats.megabytes(SystemStats.physFootprint() + LanguageServers.statuses().reduce(UInt64(0)) { $0 + $1.rssBytes })
        })

        section("Caches and logs")
        row("Local History", infoLabel { [weak self] in self?.historySize.map(SystemStats.megabytes) ?? "Calculating…" })
        row(nil, button("Clear Local History…") { [weak self] in self?.clear("Local History", LocalHistory.root) })
        row("Index caches", infoLabel { [weak self] in self?.cacheSize.map(SystemStats.megabytes) ?? "Calculating…" },
            help: "Everything under ~/Library/Caches/CodeEditor, including Local History and the vendor index. They are rebuilt on demand.")
        row(nil, button("Clear Index Caches…") { [weak self] in self?.clear("index caches", Self.cachesRoot) })
        row(nil, button("Reveal Caches in Finder") {
            try? FileManager.default.createDirectory(at: Self.cachesRoot, withIntermediateDirectories: true)
            NSWorkspace.shared.activateFileViewerSelecting([Self.cachesRoot])
        })
        measure()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
    }

    override func viewDidDisappear() { super.viewDidDisappear(); timer?.invalidate(); timer = nil }

    private func measure() {
        let history = LocalHistory.root, caches = Self.cachesRoot
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let h = SystemStats.directorySize(history), c = SystemStats.directorySize(caches)
            DispatchQueue.main.async { self?.historySize = h; self?.cacheSize = c; self?.refresh() }
        }
    }

    private func clear(_ what: String, _ dir: URL) {
        guard confirm("Clear \(what)?", detail: "This deletes the cached files at \(dir.path). They are rebuilt when needed.", button: "Clear") else { return }
        try? FileManager.default.removeItem(at: dir)
        historySize = nil; cacheSize = nil
        refresh()
        measure()
    }
}
