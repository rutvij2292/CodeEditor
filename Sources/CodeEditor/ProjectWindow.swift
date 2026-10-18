import AppKit

/// One window per project: file tree, tabs, navigation history, popups, Git panel.
final class ProjectWindow: NSObject, NSWindowDelegate {
    let window: NSWindow
    let tree = FileTreeController()
    let tabs = TabHost()
    private(set) var root: URL?
    private(set) var editors: [String: EditorTab] = [:]
    private var mru: [String] = []
    private var history: [String] = []
    private var historyIndex = -1
    private var navigating = false
    private var index: ProjectIndex?
    private var symbols: SymbolIndex?
    private var watcher: FSWatcher?
    private var diskTimer: Timer?
    private var git: GitPanelController?
    private var gitRoot: URL?
    private let mainSplit = NSSplitViewController()
    private let rootSplit = NSSplitViewController()
    private let gitContainer = NSViewController()
    private var gitItem: NSSplitViewItem!
    var onClose: ((ProjectWindow) -> Void)?

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.minSize = NSSize(width: 640, height: 400)
        window.delegate = self
        window.title = "CodeEditor"

        tabs.onSelect = { [weak self] id in self?.didSelect(id) }
        tabs.onClose = { [weak self] id in self?.close(id) }
        tree.onOpen = { [weak self] url in self?.open(url) }
        tree.onEscape = { [weak self] in self?.focusEditor() }

        let sidebarVC = NSViewController(); sidebarVC.view = tree.scrollView
        let contentVC = NSViewController(); contentVC.view = tabs
        let sidebarItem = NSSplitViewItem(viewController: sidebarVC)
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 500
        sidebarItem.canCollapse = true
        let contentItem = NSSplitViewItem(viewController: contentVC)
        contentItem.minimumThickness = 300
        mainSplit.splitView.isVertical = true
        mainSplit.splitView.dividerStyle = .thin
        mainSplit.addSplitViewItem(sidebarItem)
        mainSplit.addSplitViewItem(contentItem)

        gitContainer.view = NSView()
        gitItem = NSSplitViewItem(viewController: gitContainer)
        gitItem.minimumThickness = 180
        gitItem.canCollapse = true
        gitItem.isCollapsed = true
        rootSplit.splitView.isVertical = false
        rootSplit.splitView.dividerStyle = .thin
        rootSplit.addSplitViewItem(NSSplitViewItem(viewController: mainSplit))
        rootSplit.addSplitViewItem(gitItem)

        window.contentViewController = rootSplit
        window.setContentSize(NSSize(width: 1200, height: 800))
        DispatchQueue.main.async { [weak self] in self?.mainSplit.splitView.setPosition(260, ofDividerAt: 0) }

        diskTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.editors.values.forEach { $0.reloadIfChangedOnDisk() }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(appBecameActive),
                                               name: NSApplication.didBecomeActiveNotification, object: nil)
    }

    deinit { diskTimer?.invalidate() }

    // MARK: Project

    func openFolder(_ url: URL) {
        let url = url.standardizedFileURL
        root = url
        tree.setRoot(url)
        let projectIndex = ProjectIndex(root: url)
        index = projectIndex
        let symbolIndex = SymbolIndex(root: url) { [weak projectIndex] in projectIndex?.files ?? [] }
        symbols = symbolIndex
        projectIndex.refresh(force: true) { symbolIndex.rebuild() }
        RecentProjects.add(url)
        git = nil
        gitRoot = GitRepo.repoRoot(for: url)
        watcher = AppEnv.headless ? nil : FSWatcher(path: url.path) { [weak self] paths in self?.filesChanged(paths) }
        updateTitle()
        refreshGitStatus()
    }

    private func filesChanged(_ paths: [String]) {
        let gitMeta = paths.contains { $0.contains("/.git/") }
        let content = paths.contains { path in
            !path.contains("/.git/") && !ProjectIndex.skipNames.contains(where: { path.contains("/\($0)/") })
        }
        if content {
            tree.refresh()
            index?.refresh(force: true) { [weak self] in self?.symbols?.rebuild() }
            editors.values.forEach { $0.reloadIfChangedOnDisk() }
        }
        if content || gitMeta { refreshGitStatus() }
    }

    @objc private func appBecameActive() {
        editors.values.forEach { $0.reloadIfChangedOnDisk() }
        if root != nil { refreshGitStatus() }
    }

    private func refreshGitStatus() {
        guard let gitRoot else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let map = (try? GitRepo(root: gitRoot).statusMap()) ?? [:]
            DispatchQueue.main.async { self?.tree.setStatus(map, repoRoot: gitRoot) }
        }
    }

    // MARK: Files and tabs

    func open(_ url: URL, line: Int? = nil) {
        let id = url.standardizedFileURL.path
        if editors[id] == nil {
            guard let editor = EditorTab(url: url) else { NSSound.beep(); return }
            editors[id] = editor
            let name = url.lastPathComponent
            editor.onDirtyChange = { [weak self, weak editor] in
                self?.tabs.setTitle((editor?.isDirty == true ? "● " : "") + name, for: id)
            }
            editor.onSave = { [weak self] in self?.fileSaved(url) }
            tabs.add(id: id, title: name, view: editor.view)
        } else {
            tabs.select(id)
        }
        if let line { editors[id]?.textView.goToLine(line) }
        if let root { RecentFiles.add(url, in: root) }
        window.makeFirstResponder(editors[id]?.textView)
    }

    private func fileSaved(_ url: URL) {
        if let root {
            let prefix = root.path + "/"
            if url.path.hasPrefix(prefix) { symbols?.update(file: String(url.path.dropFirst(prefix.count))) }
        }
        refreshGitStatus()
    }

    private func didSelect(_ id: String) {
        mru.removeAll { $0 == id }
        mru.insert(id, at: 0)
        if !navigating {
            history = Array(history.prefix(historyIndex + 1))
            if history.last != id { history.append(id) }
            historyIndex = history.count - 1
        }
        updateTitle()
    }

    private func updateTitle() {
        guard let root else { window.title = "CodeEditor"; return }
        if let id = tabs.selectedID, id.hasPrefix(root.path + "/") {
            window.title = "\(root.lastPathComponent) – \(id.dropFirst(root.path.count + 1))"
        } else {
            window.title = root.lastPathComponent
        }
        window.representedURL = root
    }

    var current: EditorTab? { tabs.selectedID.flatMap { editors[$0] } }

    func close(_ id: String) {
        guard let editor = editors[id], confirmDiscard(editor) else { return }
        tabs.remove(id)
        editors[id] = nil
        mru.removeAll { $0 == id }
        history.removeAll { $0 == id }
        historyIndex = min(historyIndex, history.count - 1)
        updateTitle()
    }

    private func confirmDiscard(_ editor: EditorTab) -> Bool {
        guard editor.isDirty, !AppEnv.headless else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes to “\(editor.url.lastPathComponent)”?"
        alert.informativeText = "Your changes will be lost if you don’t save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don’t Save")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: editor.save(); return !editor.isDirty
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }

    /// Asks about every unsaved tab; false means the user cancelled.
    func confirmCloseAll() -> Bool { editors.values.allSatisfy { confirmDiscard($0) } }

    func windowShouldClose(_ sender: NSWindow) -> Bool { confirmCloseAll() }

    func windowWillClose(_ notification: Notification) {
        diskTimer?.invalidate()
        watcher = nil
        QuickPicker.dismiss()
        onClose?(self)
    }

    // MARK: Actions

    func saveCurrent() { current?.save() }
    func saveAll() { editors.values.filter(\.isDirty).forEach { $0.save() } }
    func closeCurrentTab() { if let id = tabs.selectedID { close(id) } else { window.performClose(nil) } }

    func goBack() { step(-1) }
    func goForward() { step(1) }

    private func step(_ delta: Int) {
        var i = historyIndex + delta
        while history.indices.contains(i), editors[history[i]] == nil { i += delta }
        guard history.indices.contains(i) else { return }
        historyIndex = i
        navigating = true
        tabs.select(history[i])
        navigating = false
        window.makeFirstResponder(current?.textView)
    }

    func selectTab(offset: Int) {
        let ids = tabs.entries.map(\.id)
        guard ids.count > 1, let cur = tabs.selectedID, let i = ids.firstIndex(of: cur) else { return }
        tabs.select(ids[(i + offset + ids.count) % ids.count])
        window.makeFirstResponder(current?.textView)
    }

    func focusTree() {
        if let id = tabs.selectedID { tree.reveal(URL(fileURLWithPath: id)) }
        window.makeFirstResponder(tree.outline)
    }

    func focusEditor() { window.makeFirstResponder(current?.textView) }
    func collapseTree() { tree.collapseAll() }
    func selectOpenedFile() { if let id = tabs.selectedID { tree.reveal(URL(fileURLWithPath: id)) } }

    func goToLine() {
        guard let editor = current else { return }
        let alert = NSAlert()
        alert.messageText = "Go to Line"
        alert.informativeText = "Enter line or line:column"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let parts = field.stringValue.split(separator: ":").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard let line = parts.first else { return }
        editor.textView.goToLine(line, column: parts.count > 1 ? parts[1] : 1)
        window.makeFirstResponder(editor.textView)
    }

    // MARK: Popups

    private func relative(_ url: URL) -> String {
        guard let root, url.path.hasPrefix(root.path + "/") else { return url.path }
        return String(url.path.dropFirst(root.path.count + 1))
    }

    private func fileItem(_ rel: String) -> PickerItem {
        let url = URL(fileURLWithPath: rel, relativeTo: root).standardizedFileURL
        let dir = (rel as NSString).deletingLastPathComponent
        return PickerItem(title: url.lastPathComponent, detail: dir, symbol: FileIcon.symbol(forExtension: url.pathExtension),
                          key: rel) { [weak self] in self?.open(url) }
    }

    /// Open tabs (most recent first), then files opened in earlier sessions.
    private func recentRelativePaths() -> [String] {
        guard let root else { return [] }
        var seen = Set<String>(), result: [String] = []
        for path in mru + RecentFiles.all(for: root) where path.hasPrefix(root.path + "/") && seen.insert(path).inserted {
            if FileManager.default.fileExists(atPath: path) { result.append(String(path.dropFirst(root.path.count + 1))) }
        }
        return result
    }

    func showGoToFile() {
        guard let index else { return }
        index.refresh()
        let recents = recentRelativePaths()
        QuickPicker.present(over: window, placeholder: "Go to file…", items: [], provider: { [weak self] query in
            guard let self else { return [] }
            if query.trimmingCharacters(in: .whitespaces).isEmpty { return recents.prefix(15).map(self.fileItem) }
            return index.search(query, limit: 200).map { self.fileItem($0.path) }
        })
    }

    func showRecentFiles() {
        let recents = recentRelativePaths()
        QuickPicker.present(over: window, placeholder: "Recent files…", items: recents.map(fileItem),
                            preselect: recents.count > 1 ? 1 : 0)
    }

    func showGoToClass() { presentSymbols(typesOnly: true) }
    func showGoToSymbol() { presentSymbols(typesOnly: false) }

    private func presentSymbols(typesOnly: Bool) {
        guard let symbols, let root else { return }
        GoToSymbol.present(over: window, index: symbols, typesOnly: typesOnly) { [weak self] url, line in
            self?.open(URL(fileURLWithPath: url.path, relativeTo: root), line: line)
        }
    }

    func showFileStructure() {
        guard let editor = current else { return }
        FileStructure.present(over: window, text: editor.textView.string, fileExtension: editor.url.pathExtension,
                              currentLine: editor.textView.lineAndColumn.line) { [weak self, weak editor] line in
            editor?.textView.goToLine(line)
            self?.focusEditor()
        }
    }

    func showFindAction() {
        QuickPicker.present(over: window, placeholder: "Find action…", items: actionItems())
    }

    func showSearchEverywhere() {
        let actions = actionItems()
        let recents = recentRelativePaths()
        QuickPicker.present(over: window, placeholder: "Search everywhere…", items: [], provider: { [weak self] query in
            guard let self else { return [] }
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return recents.prefix(12).map(self.fileItem) }
            let q = Array(trimmed.lowercased().filter { !$0.isWhitespace })
            var scored: [(Int, PickerItem)] = []
            for hit in self.index?.search(query, limit: 12) ?? [] { scored.append((hit.score, self.fileItem(hit.path))) }
            for item in actions {
                if let s = Fuzzy.score(q, in: item.key) { scored.append((s - 10, item)) }
            }
            scored.sort { $0.0 > $1.0 }
            return scored.prefix(30).map(\.1)
        })
    }

    /// Every enabled menu command, as picker rows ("Code › Duplicate Line   ⌘D").
    private func actionItems() -> [PickerItem] {
        NSApp.mainMenu?.update()
        var items: [PickerItem] = []
        func walk(_ menu: NSMenu, path: [String]) {
            for item in menu.items where !item.isSeparatorItem {
                if let sub = item.submenu { walk(sub, path: path + [item.title]); continue }
                guard let action = item.action, item.isEnabled else { continue }
                let shortcut = MainMenu.shortcutText(for: item)
                items.append(PickerItem(title: item.title, detail: ([path.joined(separator: " › ")] + [shortcut])
                    .filter { !$0.isEmpty }.joined(separator: "   "), symbol: "command",
                    key: (path + [item.title]).joined(separator: " ")) {
                    NSApp.sendAction(action, to: item.target, from: item)
                })
            }
        }
        if let main = NSApp.mainMenu { for top in main.items { if let sub = top.submenu { walk(sub, path: [top.title]) } } }
        return items
    }

    // MARK: Git panel

    func toggleGitPanel() {
        guard root != nil else { return }
        ensureGitPanel()
        let willShow = gitItem.isCollapsed
        if AppEnv.headless { gitItem.isCollapsed = !willShow } else { gitItem.animator().isCollapsed = !willShow }
        if willShow {
            DispatchQueue.main.async { [self] in
                let height = rootSplit.splitView.bounds.height
                rootSplit.splitView.setPosition(max(height * 0.45, height - 420), ofDividerAt: 0)
                git?.reload()
                git?.focusCommitMessage()
            }
        } else {
            focusEditor()
        }
    }

    private func ensureGitPanel() {
        guard git == nil, let root else { return }
        let host = gitContainer.view
        host.subviews.forEach { $0.removeFromSuperview() }
        guard let repo = gitRoot ?? GitRepo.repoRoot(for: root) else {
            let label = NSTextField(labelWithString: "This project is not a Git repository.")
            label.textColor = .secondaryLabelColor
            label.translatesAutoresizingMaskIntoConstraints = false
            host.addSubview(label)
            NSLayoutConstraint.activate([label.centerXAnchor.constraint(equalTo: host.centerXAnchor),
                                         label.centerYAnchor.constraint(equalTo: host.centerYAnchor)])
            return
        }
        gitRoot = repo
        let panel = GitPanelController(root: repo) { [weak self] url in self?.open(url) }
        panel.onStatusChange = { [weak self] in self?.refreshGitStatus(); self?.tree.refresh() }
        git = panel
        panel.view.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(panel.view)
        NSLayoutConstraint.activate([
            panel.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            panel.view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            panel.view.topAnchor.constraint(equalTo: host.topAnchor),
            panel.view.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
    }
}
