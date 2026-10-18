import AppKit

/// One window per project: file tree, tabs, navigation history, popups, bottom tool panel (Git, Find, Problems, ...).
final class ProjectWindow: NSObject, NSWindowDelegate {
    let window: NSWindow
    let tree = FileTreeController()
    let tabs = TabHost()
    let bottom = BottomPanel()
    private(set) var root: URL?
    private(set) var editors: [String: EditorTab] = [:]
    /// Tabs that show a "cannot open this file" message instead of an editor.
    private(set) var placeholders: [String: LoadProblem] = [:]
    private var mru: [String] = []
    private var history: [String] = []
    private var historyIndex = -1
    private var navigating = false
    private var index: ProjectIndex?
    var findPanel: FindPanelController?
    var problemsPanel: ProblemsPanelController?
    var terminalPanel: TerminalPanelController?
    /// Right/bottom dock state of the terminal (see TerminalDocking.swift).
    let termDock = TerminalDockState()
    var problemsObserver: NSObjectProtocol?
    var projectFiles: [String] { index?.files ?? [] }
    private var symbols: SymbolIndex?
    private var watcher: FSWatcher?
    private var fallbackTimer: Timer?
    private var git: GitPanelController?
    var gitRoot: URL?
    private var gitRootResolved = false
    private let gitHost = NSView()
    let statusBar = StatusBar()
    private var gitSummary = ""
    private(set) var statusKinds: [String: VCSKind] = [:]
    let mainSplit = NSSplitViewController()
    let rootSplit = NSSplitViewController()
    var bottomItem: NSSplitViewItem!
    var restoring = false
    private var sessionWork: DispatchWorkItem?
    private var diffWindows: [NSWindow] = []
    private var lastSelectedID: String?
    /// The most recent clean-buffer reload caused by a change on disk (agent edit, git checkout); for tests and status UI.
    private(set) var lastExternalChange: ExternalChange?
    private lazy var coalescer = ChangeCoalescer(interval: 0.75) { [weak self] paths in self?.processChanges(paths) }
    /// FS-event bursts handled so far (after coalescing).
    private(set) var changeBatches = 0
    var onClose: ((ProjectWindow) -> Void)?
    /// A folder was dropped on the window: the app opens it as a project.
    var onOpenFolder: ((URL) -> Void)?
    /// Hooks for the Find/Replace-in-files tool (menu items call these; no-op until set).
    var onFindInFiles: (() -> Void)?
    var onReplaceInFiles: (() -> Void)?

    var coalesceInterval: TimeInterval {
        get { coalescer.interval }
        set { coalescer.interval = newValue }
    }
    var usesFallbackPolling: Bool { fallbackTimer != nil }

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.minSize = NSSize(width: 640, height: 400)
        window.delegate = self
        window.title = Brand.name

        tabs.onSelect = { [weak self] id in self?.didSelect(id) }
        tabs.onClose = { [weak self] id in self?.close(id) }
        tabs.menuProvider = { [weak self] id in self?.tabMenu(for: id) }
        tabs.onDropURLs = { [weak self] urls in self?.handleDrop(urls) }
        tabs.onReorder = { [weak self] in self?.scheduleSessionSave() }
        tree.onOpen = { [weak self] url in self?.open(url) }
        tree.onEscape = { [weak self] in self?.focusEditor() }
        tree.onChange = { [weak self] change in self?.handleFileChange(change) }

        let sidebarVC = NSViewController(); sidebarVC.view = tree.scrollView
        let contentVC = NSViewController()
        let host = NSView()
        tabs.translatesAutoresizingMaskIntoConstraints = false
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(tabs); host.addSubview(statusBar)
        NSLayoutConstraint.activate([
            tabs.topAnchor.constraint(equalTo: host.topAnchor), tabs.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            tabs.trailingAnchor.constraint(equalTo: host.trailingAnchor), tabs.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            statusBar.leadingAnchor.constraint(equalTo: host.leadingAnchor), statusBar.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
        contentVC.view = host
        statusBar.onGoToLine = { [weak self] in self?.goToLine() }
        statusBar.onChooseIndent = { [weak self] anchor in self?.chooseIndent(from: anchor) }
        statusBar.onShowGit = { [weak self] in self?.showCommit() }
        statusBar.onChooseEncoding = { [weak self] anchor in self?.chooseEncoding(from: anchor) }
        statusBar.onToggleTerminal = { [weak self] in self?.toggleTerminal() }
        let sidebarItem = NSSplitViewItem(viewController: sidebarVC)
        sidebarItem.holdingPriority = NSLayoutConstraint.Priority(260)
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 500
        sidebarItem.canCollapse = true
        let contentItem = NSSplitViewItem(viewController: contentVC)
        contentItem.minimumThickness = 200     // the 400 pt editor floor is enforced by the terminal auto-collapse
        let terminalVC = NSViewController()
        terminalVC.view = termDock.host
        let terminalItem = NSSplitViewItem(viewController: terminalVC)
        terminalItem.minimumThickness = TerminalDockMath.minTerminal
        terminalItem.canCollapse = true
        terminalItem.isCollapsed = true
        terminalItem.holdingPriority = NSLayoutConstraint.Priority(261)   // keeps its width on window resize; the editor flexes
        mainSplit.splitView.isVertical = true
        mainSplit.splitView.dividerStyle = .thin
        mainSplit.addSplitViewItem(sidebarItem)
        mainSplit.addSplitViewItem(contentItem)
        mainSplit.addSplitViewItem(terminalItem)
        termDock.sidebarItem = sidebarItem
        termDock.contentItem = contentItem
        termDock.terminalItem = terminalItem

        let bottomVC = NSViewController()
        bottomVC.view = bottom.view
        bottomItem = NSSplitViewItem(viewController: bottomVC)
        bottomItem.minimumThickness = 120
        bottomItem.canCollapse = true
        bottomItem.isCollapsed = true
        rootSplit.splitView.isVertical = false
        rootSplit.splitView.dividerStyle = .thin
        let mainItem = NSSplitViewItem(viewController: mainSplit)
        termDock.mainItem = mainItem
        rootSplit.addSplitViewItem(mainItem)
        rootSplit.addSplitViewItem(bottomItem)

        bottom.onVisibilityChange = { [weak self] visible in self?.applyBottomVisibility(visible) }
        bottom.onEscape = { [weak self] in self?.focusEditor() }
        bottom.onWillShow = { [weak self] id in if id == "git" { self?.ensureGitPanel() } }
        bottom.register(id: "git", title: "Git", view: gitHost)

        window.contentViewController = rootSplit
        window.setContentSize(NSSize(width: 1200, height: 800))
        DispatchQueue.main.async { [weak self] in self?.mainSplit.splitView.setPosition(260, ofDividerAt: 0) }

        NotificationCenter.default.addObserver(self, selector: #selector(appBecameActive),
                                               name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appResignedActive),
                                               name: NSApplication.didResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowResignedKey),
                                               name: NSWindow.didResignKeyNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(selectionChanged(_:)),
                                               name: NSTextView.didChangeSelectionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(terminalSplitDidResize(_:)),
                                               name: NSSplitView.didResizeSubviewsNotification, object: mainSplit.splitView)
        NotificationCenter.default.addObserver(self, selector: #selector(terminalPrefsChanged(_:)),
                                               name: Prefs.didChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(languageServerStatusChanged),
                                               name: LanguageServers.statusDidChange, object: nil)
    }

    deinit { fallbackTimer?.invalidate() }

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
        gitRoot = nil
        gitRootResolved = false
        gitHost.subviews.forEach { $0.removeFromSuperview() }
        bottom.setPersistence(key: AppEnv.headless ? nil : url.path)
        watcher = AppEnv.headless ? nil : FSWatcher(path: url.path) { [weak self] paths in self?.filesChanged(paths) }
        // FSEvents replaces polling; poll slowly only when the watcher could not start.
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        if !AppEnv.headless, watcher == nil {
            fallbackTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                self?.editors.values.forEach { $0.reloadIfChangedOnDisk() }
            }
        }
        updateTitle()
        GitRepo.repoRoot(for: url) { [weak self] repo in
            guard let self, self.root == url else { return }
            self.gitRoot = repo
            self.gitRootResolved = true
            if self.bottom.isVisible, self.bottom.selectedID == "git" { self.ensureGitPanel() }
            self.refreshGitStatus()
        }
        installFeaturePanels()
        if let session = SessionStore.load(for: url) { restoreSession(session) }
    }

    // MARK: File-system events

    /// FSEvents callback: filters out skipped/build directories and coalesces bursts into one `processChanges`.
    func filesChanged(_ paths: [String]) {
        guard let root else { return }
        coalescer.add(paths.filter { $0.contains("/.git/") || !ProjectIndex.isSkipped(path: $0, under: root) })
    }

    private func processChanges(_ paths: Set<String>) {
        changeBatches += 1
        let gitMeta = paths.contains { $0.contains("/.git/") }
        let content = paths.contains { !$0.contains("/.git/") }
        if let root, paths.contains(where: { $0.hasSuffix("/composer.lock") || $0.hasSuffix("/vendor/composer/installed.json") }) {
            VendorIndex.invalidate(root: root)
        }
        if content {
            if let root { LaravelNavigator.invalidate(root: root) }
            tree.refresh()
            index?.refresh(force: true) { [weak self] in self?.symbols?.rebuild() }
            editors.values.forEach { $0.reloadIfChangedOnDisk() }
        }
        if content || gitMeta { refreshGitStatus() }
    }

    /// Rescans Go to File and symbols (e.g. after toggling "Include vendor").
    func reindex() {
        index?.refresh(force: true) { [weak self] in self?.symbols?.rebuild() }
    }

    /// Shows the language server's state and memory cost under the window title.
    @objc private func languageServerStatusChanged() { refreshStatus() }

    @objc private func selectionChanged(_ note: Notification) {
        if (note.object as? NSTextView) === current?.textView { refreshStatus() }
    }

    private static func languageName(_ url: URL) -> String {
        let names = ["php": "PHP", "js": "JavaScript", "jsx": "JSX", "mjs": "JavaScript", "ts": "TypeScript", "tsx": "TSX",
                     "vue": "Vue", "html": "HTML", "htm": "HTML", "css": "CSS", "scss": "SCSS", "json": "JSON", "md": "Markdown",
                     "yml": "YAML", "yaml": "YAML", "sh": "Shell", "sql": "SQL", "xml": "XML", "env": "Env"]
        if url.lastPathComponent.hasSuffix(".blade.php") { return "Blade" }
        return names[url.pathExtension.lowercased()] ?? "Plain Text"
    }

    func refreshStatus() {
        let editor = current
        let caret = editor?.textView.lineAndColumn
        statusBar.update(line: caret?.line, column: caret?.column, selected: editor?.textView.selectedRange().length ?? 0,
                         indent: editor?.indent.label, language: editor.map { Self.languageName($0.url) },
                         lineEnding: editor?.lineEnding, branch: gitSummary,
                         server: root.map { LanguageServers.statusText(forRoot: $0) } ?? "", encoding: editor?.encodingName)
    }

    var statusBarBranchText: String { statusBar.branchText }
    var statusBarNotice: String { statusBar.noticeText }
    var statusBarEncoding: String { statusBar.encodingText }

    // MARK: Auto-save

    /// Saves every modified buffer that is safe to save (see `EditorTab.autoSave`).
    func autoSaveAll(_ trigger: AutoSave.Trigger) {
        for editor in editors.values { editor.autoSave(trigger) }
    }

    @objc private func appResignedActive() { autoSaveAll(.focusLoss) }

    /// The window lost key status: auto-save unless focus only moved to one of our own panels/sheets (pickers, dialogs).
    @objc private func windowResignedKey() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let key = NSApp.keyWindow, key is NSPanel || self.window.childWindows?.contains(key) == true { return }
            if self.window.attachedSheet != nil { return }
            self.autoSaveAll(.focusLoss)
        }
    }

    // MARK: Encoding

    private func chooseEncoding(from anchor: NSView) {
        guard let editor = current else { return }
        let menu = NSMenu()
        func header(_ title: String) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        header("Reopen with Encoding")
        for (i, choice) in TextEncodings.choices.enumerated() {
            let item = NSMenuItem(title: choice.name, action: #selector(reopenEncodingPicked(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            item.state = editor.encoding == choice.encoding ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        header("Save with Encoding")
        for (i, choice) in TextEncodings.choices.enumerated() {
            let item = NSMenuItem(title: choice.name, action: #selector(saveEncodingPicked(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            item.state = editor.encoding == choice.encoding ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.height + 4), in: anchor)
    }

    @objc private func reopenEncodingPicked(_ item: NSMenuItem) {
        guard TextEncodings.choices.indices.contains(item.tag) else { return }
        reopenCurrentTab(encoding: TextEncodings.choices[item.tag].encoding)
    }

    @objc private func saveEncodingPicked(_ item: NSMenuItem) {
        guard TextEncodings.choices.indices.contains(item.tag) else { return }
        setCurrentSaveEncoding(TextEncodings.choices[item.tag].encoding)
    }

    /// "Reopen with encoding": re-decodes the file from disk in `encoding`. A modified buffer is only discarded after asking
    /// (headless runs refuse). The old tab stays if the file cannot be decoded that way.
    @discardableResult
    func reopenCurrentTab(encoding: String.Encoding) -> Bool {
        guard let editor = current else { return false }
        if editor.isDirty {
            guard !AppEnv.headless else { return false }
            let alert = NSAlert()
            alert.messageText = "Discard changes to “\(editor.url.lastPathComponent)”?"
            alert.informativeText = "Reopening re-reads the file from disk with another encoding."
            alert.addButton(withTitle: "Reopen"); alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return false }
        }
        let options = OpenOptions(encoding: encoding, autoDetect: false)
        guard case .success = EditorTab.read(editor.url, options: options) else {
            statusBar.flash("Can’t decode “\(editor.url.lastPathComponent)” as that encoding")
            return false
        }
        reopenEditor(editor, options)
        return true
    }

    /// "Save with encoding": the next save writes the buffer in `encoding`.
    @discardableResult
    func setCurrentSaveEncoding(_ encoding: String.Encoding) -> Bool {
        guard let editor = current else { return false }
        guard editor.setSaveEncoding(encoding) else {
            statusBar.flash("Some characters can’t be saved in that encoding")
            return false
        }
        refreshStatus()
        return true
    }

    /// Replaces an open editor by a fresh one over the same file with other options (position, caret and scroll kept).
    private func reopenEditor(_ editor: EditorTab, _ options: OpenOptions) {
        let url = editor.url
        let id = url.standardizedFileURL.path
        let position = tabs.entries.firstIndex { $0.id == id }
        let caret = editor.caretLocation, scrollY = editor.scrollY
        closeNow(id)
        open(url, options: options)
        if let position { tabs.move(id, toIndex: position) }
        editors[id]?.restore(caret: caret, scrollY: scrollY)
        refreshStatus()
    }

    // MARK: Save As

    /// Banner "Save As…" (file deleted / replaced by a directory / unwritable).
    private func promptSaveAs(_ editor: EditorTab) {
        guard !AppEnv.headless else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = editor.url.lastPathComponent
        panel.directoryURL = editor.url.deletingLastPathComponent()
        panel.beginSheetModal(for: window) { [weak self, weak editor] response in
            guard response == .OK, let url = panel.url, let editor else { return }
            self?.saveEditor(editor, as: url)
        }
    }

    /// Saves the buffer to `newURL` and retargets its tab there.
    @discardableResult
    func saveEditor(_ editor: EditorTab, as newURL: URL) -> Bool {
        let old = editor.url.standardizedFileURL, new = newURL.standardizedFileURL
        if old != new {
            guard editors[new.path] == nil else { statusBar.flash("“\(new.lastPathComponent)” is already open"); return false }
            retargetTabs(from: old, to: new)
        }
        let ok = editor.save(overwriteNewer: true)
        tree.refresh()
        return ok
    }

    // MARK: Local history

    /// Local History…: pick an earlier version of the current file; it replaces the buffer as one undoable edit.
    func showLocalHistory() {
        guard let editor = current else { return }
        let revisions = LocalHistory.revisions(for: editor.url)
        let items: [PickerItem]
        if revisions.isEmpty {
            items = [PickerItem(title: "No local history for this file yet", detail: "Versions are kept on save and on external reload",
                                symbol: "clock", key: "none") {}]
        } else {
            items = revisions.map { rev in
                let lines = LocalHistory.data(of: rev).map { $0.reduce(0) { $1 == 10 ? $0 + 1 : $0 } } ?? 0
                return PickerItem(title: LocalHistory.describe(rev), detail: "\(lines) lines", symbol: "clock.arrow.circlepath",
                                  key: LocalHistory.describe(rev)) { [weak self, weak editor] in
                    if let editor { self?.restoreRevision(rev, into: editor) }
                }
            }
        }
        QuickPicker.present(over: window, placeholder: "Local History — \(editor.url.lastPathComponent)", items: items)
    }

    /// Replaces the buffer with a revision (undoable; nothing is written to disk until the user saves).
    @discardableResult
    func restoreRevision(_ revision: LocalHistory.Revision, into editor: EditorTab, confirm: Bool? = nil) -> Bool {
        guard !editor.isReadOnly, let text = LocalHistory.text(of: revision, encoding: editor.encoding) else { return false }
        if confirm ?? !AppEnv.headless {
            let alert = NSAlert()
            alert.messageText = "Restore the version from \(LocalHistory.describe(revision))?"
            alert.informativeText = "The buffer is replaced; press ⌘Z to undo. Nothing is saved until you save."
            alert.addButton(withTitle: "Restore"); alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return false }
        }
        editor.replaceText(text, actionName: "Restore from Local History")
        return true
    }

    private func chooseIndent(from anchor: NSView) {
        guard current != nil else { return }
        let menu = NSMenu()
        for (title, tabs, size) in [("2 spaces", false, 2), ("4 spaces", false, 4), ("8 spaces", false, 8),
                                    ("Tabs (width 4)", true, 4), ("Tabs (width 8)", true, 8)] {
            let item = NSMenuItem(title: title, action: #selector(indentPicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = IndentSettings(useTabs: tabs, size: size)
            item.state = current?.indent == IndentSettings(useTabs: tabs, size: size) ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.height + 4), in: anchor)
    }

    @objc private func indentPicked(_ item: NSMenuItem) {
        guard let settings = item.representedObject as? IndentSettings else { return }
        current?.applyIndent(settings)
        refreshStatus()
    }

    @objc private func appBecameActive() {
        editors.values.forEach { $0.reloadIfChangedOnDisk() }
        if root != nil { refreshGitStatus() }
    }

    private func refreshGitStatus() {
        guard let gitRoot else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = try? GitRepo(root: gitRoot).statusAndBranch()
            DispatchQueue.main.async {
                guard let self else { return }
                self.applyGitStatus(changes: result?.changes ?? [], info: result?.info, repoRoot: gitRoot)
            }
        }
    }

    /// Applies a status snapshot: tree and tab colours, and the status bar's Git summary.
    func applyGitStatus(changes: [GitChange], info: GitRepo.BranchInfo?, repoRoot: URL) {
        let map = Dictionary(changes.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        tree.setStatus(map, repoRoot: repoRoot)
        NotificationCenter.default.post(name: GitGutter.statusChanged, object: nil)
        statusKinds = Dictionary(VCSKind.kinds(for: map, repoRoot: repoRoot).map { (VCSKind.canonical($0.key), $0.value) },
                                 uniquingKeysWith: { a, _ in a })
        for e in tabs.entries { applyTint(e.id) }
        gitSummary = info.map { StatusBar.gitSummary(branch: $0.name, ahead: $0.ahead, behind: $0.behind, changes: changes.count) } ?? ""
        refreshStatus()
    }

    private func applyTint(_ id: String) {
        tabs.setTint(statusKinds[VCSKind.canonical(id)]?.color, for: id)
    }

    // MARK: Files and tabs

    func open(_ url: URL, line: Int? = nil, options: OpenOptions = OpenOptions()) {
        let id = url.standardizedFileURL.path
        if editors[id] == nil {
            if placeholders[id] != nil { tabs.select(id); return }
            guard let editor = EditorTab(url: url, options: options) else { showLoadProblem(url); return }
            editors[id] = editor
            editor.onDirtyChange = { [weak self, weak editor] in
                guard let self, let editor else { return }
                self.tabs.setDirty(editor.isDirty, for: editor.url.standardizedFileURL.path)
            }
            editor.onSave = { [weak self, weak editor] in if let editor { self?.fileSaved(editor.url) } }
            editor.onDropURLs = { [weak self] urls in self?.handleDrop(urls) }
            editor.onShowDiff = { [weak self] e in self?.showDiff(e) }
            editor.onSaveAs = { [weak self] e in self?.promptSaveAs(e) }
            editor.onCloseRequest = { [weak self] e in self?.close(e.url.standardizedFileURL.path) }
            editor.onOpenAnyway = { [weak self] e in self?.reopenEditor(e, OpenOptions(openAnyway: true)) }
            editor.onExternalReload = { [weak self] e, change in
                guard let self else { return }
                self.lastExternalChange = change
                let name = e === self.current ? "" : " “\(e.url.lastPathComponent)”"
                self.statusBar.flash("Reloaded\(name) from disk (agent edit?)  ⌘Z to undo", seconds: 8)
            }
            tabs.add(id: id, title: url.lastPathComponent, view: editor.view)
            if VendorIndex.isLibraryFile(url), !editor.isReadOnly, let container = editor.view as? EditorPane {
                editor.textView.isEditable = false
                container.showBanner("Library file (vendor) — read only.", actions: [("Edit Anyway", { [weak editor, weak container] in
                    editor?.textView.isEditable = true
                    container?.hideBanner()
                })])
            }
            applyTint(id)
        } else {
            tabs.select(id)
        }
        if let line { editors[id]?.textView.goToLine(line) }
        if let root { RecentFiles.add(url, in: root) }
        window.makeFirstResponder(editors[id]?.textView)
        scheduleSessionSave()
    }

    /// Shows a message tab for a file that cannot be opened as plain text, with a way to open it anyway.
    private func showLoadProblem(_ url: URL) {
        let id = url.standardizedFileURL.path
        let problem = EditorTab.loadProblem(for: url) ?? .unreadable
        placeholders[id] = problem
        let name = url.lastPathComponent
        let view: LoadProblemView
        switch problem {
        case .notUTF8:
            view = LoadProblemView(message: "“\(name)” is not valid UTF-8 text.",
                                   detail: "It may be binary or use another encoding.",
                                   actions: [("Open anyway as Latin-1", { [weak self] in self?.reopen(url, OpenOptions(encoding: .isoLatin1, autoDetect: false)) }),
                                             ("Windows-1252", { [weak self] in self?.reopen(url, OpenOptions(encoding: .windowsCP1252, autoDetect: false)) }),
                                             ("Shift-JIS", { [weak self] in self?.reopen(url, OpenOptions(encoding: .shiftJIS, autoDetect: false)) }),
                                             ("GB18030", { [weak self] in self?.reopen(url, OpenOptions(encoding: TextEncodings.gb18030, autoDetect: false)) })])
        case .tooLarge(let size):
            let mb = String(format: "%.1f", Double(size) / 1_000_000)
            view = LoadProblemView(message: "“\(name)” is \(mb) MB, over the 5 MB limit.",
                                   detail: "Large files are slow to edit and highlight.",
                                   actions: [("Open read-only (first 5 MB)", { [weak self] in self?.reopen(url, OpenOptions(readOnlyTruncated: true)) })]
                                   + (size <= EditorTab.hardLimit ? [("Open anyway (editable, features off)", { [weak self] in self?.reopen(url, OpenOptions(openAnyway: true)) })] : []))
        case .unreadable:
            view = LoadProblemView(message: "“\(name)” could not be read.", detail: "Check that the file exists and you can read it.", actions: [])
        }
        view.addAction("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        tabs.add(id: id, title: name, view: view)
    }

    private func reopen(_ url: URL, _ options: OpenOptions) {
        let id = url.standardizedFileURL.path
        let position = tabs.entries.firstIndex { $0.id == id }
        placeholders[id] = nil
        tabs.remove(id)
        open(url, options: options)
        if let position { tabs.move(id, toIndex: position) }
    }

    private func fileSaved(_ url: URL) {
        if let root {
            let prefix = root.path + "/"
            if url.path.hasPrefix(prefix) { symbols?.update(file: String(url.path.dropFirst(prefix.count))) }
        }
        refreshGitStatus()
    }

    private func didSelect(_ id: String) {
        if let previous = lastSelectedID, previous != id { editors[previous]?.autoSave(.tabSwitch) }
        lastSelectedID = id
        problemsPanel?.reload()
        mru.removeAll { $0 == id }
        mru.insert(id, at: 0)
        if !navigating {
            history = Array(history.prefix(historyIndex + 1))
            if history.last != id { history.append(id) }
            historyIndex = history.count - 1
        }
        updateTitle()
        refreshStatus()
        scheduleSessionSave()
    }

    private func updateTitle() {
        guard let root else { window.title = Brand.name; return }
        if let id = tabs.selectedID, id.hasPrefix(root.path + "/") {
            window.title = "\(root.lastPathComponent) – \(id.dropFirst(root.path.count + 1))"
        } else {
            window.title = root.lastPathComponent
        }
        window.representedURL = root
    }

    var symbolEntries: [SymbolIndex.Entry] { symbols?.entries ?? [] }

    var current: EditorTab? { tabs.selectedID.flatMap { editors[$0] } }

    /// Closes a tab, asking about unsaved changes. False means the user cancelled.
    @discardableResult
    func close(_ id: String) -> Bool {
        if placeholders[id] != nil { placeholders[id] = nil; forget(id); return true }
        guard let editor = editors[id], confirmDiscard(editor) else { return false }
        closeNow(id)
        return true
    }

    /// Closes without asking (file deleted, or the user already decided).
    private func closeNow(_ id: String) {
        guard let editor = editors[id] else { return }
        editors[id] = nil
        EditorEvents.notifyClosed(editor)
        forget(id)
    }

    private func forget(_ id: String) {
        tabs.remove(id)
        mru.removeAll { $0 == id }
        history.removeAll { $0 == id }
        historyIndex = min(historyIndex, history.count - 1)
        updateTitle()
        refreshStatus()
        scheduleSessionSave()
    }

    private func closeMany(_ ids: [String]) {
        for id in ids where !close(id) { break }
    }

    func closeOthers(_ id: String) { closeMany(tabs.ids(except: id)) }
    func closeAllTabs() { closeMany(tabs.entries.map(\.id)) }
    func closeToTheRight(of id: String) { closeMany(tabs.ids(toRightOf: id)) }

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
        saveSession()
        sessionWork?.cancel()
        coalescer.cancel()
        fallbackTimer?.invalidate()
        watcher = nil
        terminalPanel?.terminate()
        editors.values.forEach { EditorEvents.notifyClosed($0) }
        diffWindows.forEach { $0.close() }
        QuickPicker.dismiss()
        onClose?(self)
    }

    // MARK: Tab menu

    func tabMenu(for id: String) -> NSMenu {
        let menu = NSMenu()
        let rows: [(String, Selector)] = [("Close", #selector(tabMenuClose(_:))), ("Close Others", #selector(tabMenuCloseOthers(_:))),
                                          ("Close All", #selector(tabMenuCloseAll(_:))),
                                          ("Close to the Right", #selector(tabMenuCloseRight(_:)))]
        for (title, action) in rows {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = id
            if title == "Close Others" { item.isEnabled = tabs.entries.count > 1 }
            if title == "Close to the Right" { item.isEnabled = !tabs.ids(toRightOf: id).isEmpty }
            menu.addItem(item)
        }
        menu.addItem(.separator())
        for (title, action) in [("Copy Path", #selector(tabMenuCopyPath(_:))), ("Reveal in Finder", #selector(tabMenuReveal(_:)))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = id
            menu.addItem(item)
        }
        return menu
    }

    private func tabID(_ item: NSMenuItem) -> String? { item.representedObject as? String }
    @objc private func tabMenuClose(_ i: NSMenuItem) { if let id = tabID(i) { close(id) } }
    @objc private func tabMenuCloseOthers(_ i: NSMenuItem) { if let id = tabID(i) { closeOthers(id) } }
    @objc private func tabMenuCloseAll(_ i: NSMenuItem) { closeAllTabs() }
    @objc private func tabMenuCloseRight(_ i: NSMenuItem) { if let id = tabID(i) { closeToTheRight(of: id) } }
    @objc private func tabMenuCopyPath(_ i: NSMenuItem) {
        guard let id = tabID(i) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(id, forType: .string)
    }
    @objc private func tabMenuReveal(_ i: NSMenuItem) {
        if let id = tabID(i) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: id)]) }
    }

    // MARK: File operations (from the tree) and drops

    /// Brings open tabs, the tree, the index and Git status in line with a change made through the tree.
    func handleFileChange(_ change: FileChange) {
        switch change {
        case .created: break
        case .moved(let from, let to): retargetTabs(from: from, to: to)
        case .deleted(let url): closeTabsForDeleted(url)
        }
        tree.refresh()
        reindex()
        refreshGitStatus()
        scheduleSessionSave()
    }

    private func retargetTabs(from: URL, to: URL) {
        let old = from.standardizedFileURL.path, new = to.standardizedFileURL.path
        for id in tabs.entries.map(\.id) {
            guard let newID = FileOperations.remap(path: id, from: old, to: new) else { continue }
            guard let editor = editors.removeValue(forKey: id) else {
                placeholders[id] = nil
                forget(id)
                continue
            }
            let newURL = URL(fileURLWithPath: newID)
            editor.retarget(to: newURL)
            editors[newID] = editor
            tabs.retarget(id, to: newID, title: newURL.lastPathComponent)
            mru = mru.map { $0 == id ? newID : $0 }
            history = history.map { $0 == id ? newID : $0 }
            applyTint(newID)
        }
        updateTitle()
    }

    private func closeTabsForDeleted(_ url: URL) {
        let gone = url.standardizedFileURL.path
        var closed: [String] = []
        for id in tabs.entries.map(\.id) where FileOperations.remap(path: id, from: gone, to: "") != nil {
            if placeholders[id] != nil { placeholders[id] = nil; forget(id) } else { closeNow(id) }
            closed.append((id as NSString).lastPathComponent)
        }
        if !closed.isEmpty {
            statusBar.flash(closed.count == 1 ? "Closed “\(closed[0])” (deleted)" : "Closed \(closed.count) deleted files")
        }
    }

    /// Files dropped on the editor area or tab strip open as tabs; folders open as projects.
    func handleDrop(_ urls: [URL]) {
        for url in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue { onOpenFolder?(url) } else { open(url) }
        }
    }

    private func showDiff(_ editor: EditorTab) {
        guard !AppEnv.headless, let disk = editor.currentDiskText() else { return }
        let view = SideBySideDiffView(frame: NSRect(x: 0, y: 0, width: 1100, height: 680))
        view.show(old: disk, new: editor.textView.string, oldTitle: "On disk", newTitle: "Your buffer",
                  fileExtension: editor.url.pathExtension)
        let win = NSWindow(contentRect: view.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        win.isReleasedWhenClosed = false
        win.contentView = view
        win.title = "Diff – \(editor.url.lastPathComponent)"
        diffWindows.append(win)
        win.makeKeyAndOrderFront(nil)
    }

    // MARK: Session

    func captureSession() -> Session {
        var s = Session()
        for e in tabs.entries {
            guard let editor = editors[e.id] else { continue }
            s.tabs.append(.init(path: e.id, caret: editor.caretLocation, scrollY: editor.scrollY))
        }
        s.selected = tabs.selectedID
        let f = window.frame
        s.windowFrame = [Double(f.minX), Double(f.minY), Double(f.width), Double(f.height)]
        if let w = mainSplit.splitView.subviews.first?.frame.width, w > 50 { s.sidebarWidth = Double(w) }
        let height = bottom.isVisible && bottom.view.bounds.height > 80 ? bottom.view.bounds.height : bottom.height
        s.bottom = .init(visible: bottom.isVisible, selected: bottom.selectedID, height: Double(height))
        s.expanded = tree.expandedPaths()
        if terminalPanel != nil { s.terminal = captureTerminalState() }
        return s
    }

    func restoreSession(_ s: Session) {
        restoring = true
        defer { restoring = false }
        tree.expand(paths: s.expanded)
        for t in s.tabs where FileManager.default.fileExists(atPath: t.path) {
            open(URL(fileURLWithPath: t.path))
            editors[t.path]?.restore(caret: t.caret, scrollY: t.scrollY)
        }
        if let sel = s.selected, editors[sel] != nil { tabs.select(sel) }
        if let f = s.windowFrame, f.count == 4, f[2] >= 640, f[3] >= 400 {
            var rect = NSRect(x: f[0], y: f[1], width: f[2], height: f[3])
            if let screen = NSScreen.main { rect = window.constrainFrameRect(rect, to: screen) }
            window.setFrame(rect, display: false)
        }
        if let w = s.sidebarWidth, w >= 180 {
            DispatchQueue.main.async { [weak self] in self?.mainSplit.splitView.setPosition(CGFloat(w), ofDividerAt: 0) }
        }
        if let b = s.bottom {
            if b.height > 80 { bottom.height = CGFloat(b.height) }
            if b.visible, let sel = b.selected, bottom.has(sel) { bottom.show(sel) }
        }
        restoreTerminalState(s.terminal)
    }

    func saveSession() {
        guard SessionStore.enabled, !restoring, let root else { return }
        SessionStore.save(captureSession(), for: root)
    }

    func scheduleSessionSave() {
        guard SessionStore.enabled, !restoring, root != nil else { return }
        sessionWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveSession() }
        sessionWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
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

    /// Cmd-L: a small QuickPicker-style input accepting `line` or `line:column`.
    func goToLine() {
        guard let editor = current else { return }
        let total = (editor.textView.string as NSString).length == 0 ? 1 : editor.textView.string.split(separator: "\n", omittingEmptySubsequences: false).count
        QuickPicker.present(over: window, placeholder: "Go to line — line or line:column (1–\(total))", items: [], provider: { [weak self, weak editor] query in
            guard let (line, column) = GoToLineInput.parse(query) else { return [] }
            let clamped = min(line, total)
            return [PickerItem(title: "Go to line \(clamped)" + (column > 1 ? ", column \(column)" : ""),
                               detail: "of \(total)", symbol: "arrow.right.to.line", key: query) {
                editor?.textView.goToLine(clamped, column: column)
                self?.focusEditor()
            }]
        })
    }

    // MARK: Tool panels (bottom)

    /// Adds a tab to the bottom tool panel (Find, Problems, ...). `installCloseRequest` receives a closure the tool
    /// can call to hide the panel and return focus to the editor.
    func registerToolPanel(id: String, title: String, view: NSView,
                           installCloseRequest: ((@escaping () -> Void) -> Void)? = nil) {
        bottom.register(id: id, title: title, view: view, installCloseRequest: installCloseRequest)
    }

    func hasToolPanel(_ id: String) -> Bool { bottom.has(id) }

    func showToolPanel(_ id: String, focus: (() -> Void)? = nil) { bottom.show(id, focus: focus) }

    func toggleToolPanel(_ id: String) { bottom.toggle(id) }

    func setToolPanelBadge(_ text: String?, for id: String) { bottom.setBadge(text, for: id) }

    private func applyBottomVisibility(_ visible: Bool) {
        if AppEnv.headless { bottomItem.isCollapsed = !visible } else { bottomItem.animator().isCollapsed = !visible }
        guard visible else { return }
        DispatchQueue.main.async { [self] in
            let total = rootSplit.splitView.bounds.height
            rootSplit.splitView.setPosition(max(total * 0.3, total - bottom.height), ofDividerAt: 0)
        }
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

    /// Cmd-K: show the Commit/Changes panel (never hides it) and put the caret in the commit message.
    func showCommit() {
        guard root != nil else { return }
        bottom.show("git") { [weak self] in
            self?.git?.reload()
            self?.git?.focusCommitMessage()
        }
    }

    func gitPush() { showCommit(); git?.push() }
    func gitPull() { showCommit(); git?.pull() }
    func gitFetch() { showCommit(); git?.fetch() }

    /// Cmd-9: show the Git tool, or hide the panel if Git is what it shows.
    func toggleGitPanel() {
        guard root != nil else { return }
        let hiding = bottom.isVisible && bottom.selectedID == "git"
        bottom.toggle("git") { [weak self] in
            self?.git?.reload()
            self?.git?.focusCommitMessage()
        }
        if hiding { focusEditor() }
    }

    /// Git › Show History for File: opens the Git panel's Log tab filtered by the current file (`git log --follow`).
    func showFileHistory() {
        guard let url = current?.url, root != nil else { return }
        ensureGitPanel()
        showToolPanel("git") { [weak self] in self?.git?.showHistory(for: url) }
    }

    private func ensureGitPanel() {
        guard git == nil, root != nil else { return }
        let host = gitHost
        host.subviews.forEach { $0.removeFromSuperview() }
        func message(_ text: String) {
            let label = NSTextField(labelWithString: text)
            label.textColor = .secondaryLabelColor
            label.translatesAutoresizingMaskIntoConstraints = false
            host.addSubview(label)
            NSLayoutConstraint.activate([label.centerXAnchor.constraint(equalTo: host.centerXAnchor),
                                         label.centerYAnchor.constraint(equalTo: host.centerYAnchor)])
        }
        guard gitRootResolved else { message("Looking for a Git repository…"); return }
        guard let repo = gitRoot else { message("This project is not a Git repository."); return }
        let panel = GitPanelController(root: repo) { [weak self] url in self?.open(url) }
        panel.onStatusChange = { [weak self] in self?.refreshGitStatus(); self?.tree.refresh() }
        git = panel
        panel.onRequestClose = { [weak self] in self?.bottom.hide(); self?.focusEditor() }
        panel.onSummaryChange = { [weak self] summary in
            self?.setToolPanelBadge(summary.changes > 0 ? "\(summary.changes)" : nil, for: "git")
        }
        panel.view.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(panel.view)
        NSLayoutConstraint.activate([
            panel.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            panel.view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            panel.view.topAnchor.constraint(equalTo: host.topAnchor),
            panel.view.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
        if bottom.isVisible, bottom.selectedID == "git" {
            DispatchQueue.main.async { panel.reload() }
        }
    }
}
