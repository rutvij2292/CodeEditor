import AppKit

/// Connects independently built features (Find in Files, ...) to a project window's tool panel and menu actions.
extension ProjectWindow {
    func installFeaturePanels() {
        guard let root, !hasToolPanel("find") else { return }
        let find = FindPanelController(
            root: root,
            files: { [weak self] in self?.projectFiles ?? [] },
            openFile: { [weak self] url, line, column in self?.open(url, line: line); self?.current?.textView.goToLine(line, column: column) },
            openBuffer: { [weak self] url in self?.editors[url.standardizedFileURL.path] })
        find.openMatch = { [weak self] match in
            self?.open(match.url, line: match.line)
            self?.current?.textView.goToLine(match.line, column: match.column)
        }
        findPanel = find
        registerToolPanel(id: "find", title: "Find", view: find.view) { close in find.onClose = close }
        find.onEscapeToEditor = { [weak self] in self?.focusEditor() }
        installProblemsPanel(root: root)
        installHttpPanel(root: root)
        installTerminalPanel(root: root)
        installChangeReview(root: root)
        installTestsPanel(root: root)
        installTodoAndBookmarks(root: root)
        installClaudeBridge()
        PlanSupport.start()
        onFindInFiles = { [weak self] in self?.showFind(replace: false) }
        onReplaceInFiles = { [weak self] in self?.showFind(replace: true) }
    }

    /// Cmd-Shift-F / Cmd-Shift-R: opens the Find panel seeded with the current single-line selection.
    func showFind(replace: Bool) {
        guard let find = findPanel else { return }
        var seed: String?
        if let tv = current?.textView, tv.selectedRange().length > 0 {
            let text = (tv.string as NSString).substring(with: tv.selectedRange())
            if !text.contains("\n"), text.count <= 200 { seed = text }
        }
        showToolPanel("find") { find.show(seed: seed, replaceMode: replace) }
    }

    private func installHttpPanel(root: URL) {
        HttpSystem.start()
        let http = HttpPanelController(root: root)
        http.reveal = { [weak self] in self?.showToolPanel("http") }
        HttpSystem.register(http)
        registerToolPanel(id: "http", title: "HTTP", view: http.view)
    }

    private func installProblemsPanel(root: URL) {
        let problems = ProblemsPanelController(root: root) { [weak self] url, line, column in
            self?.open(url, line: line)
            self?.current?.textView.goToLine(line, column: column)
        }
        problems.currentFileProvider = { [weak self] in self?.current?.url }
        problemsPanel = problems
        registerToolPanel(id: "problems", title: "Problems", view: problems.view)
        problemsObserver = NotificationCenter.default.addObserver(forName: LanguageServers.problemsDidChange, object: nil, queue: .main) { [weak self] _ in
            guard let self, let root = self.root else { return }
            if self.bottom.isVisible, self.bottom.selectedID == "problems" { self.problemsPanel?.reload() }   // rebuilt on show otherwise
            let files = LanguageServers.problems(forRoot: root)
            let errors = files.reduce(0) { $0 + $1.errorCount }, warnings = files.reduce(0) { $0 + $1.warningCount }
            self.setToolPanelBadge(errors + warnings > 0 ? (errors > 0 ? "\(errors)" : "\(warnings)") : nil, for: "problems")
        }
    }

    private func installTerminalPanel(root: URL) {
        let term = TerminalPanelController(root: root)
        term.openPath = { [weak self] path, line, column in
            self?.open(URL(fileURLWithPath: path), line: line)
            if let line { self?.current?.textView.goToLine(line, column: column ?? 1) }
        }
        term.onActivity = { [weak self] in self?.updateTerminalAttention() }
        term.onClose = { [weak self] in self?.hideTerminal() }
        term.onFilesDropped = { [weak self] urls in
            guard let self, let root = self.root else { return }
            self.sendToTerminal(TerminalBridge.fileReferences(urls, root: root))
        }
        terminalPanel = term
        // Right dock (default): the view is attached lazily on first show. Bottom dock: a tab in the bottom panel.
        if termDock.side == "bottom" { registerBottomTerminal() }
    }
}
