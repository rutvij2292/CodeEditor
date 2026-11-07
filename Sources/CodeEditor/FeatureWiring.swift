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
        ClaudeComposerWiring.install()
        PlanSupport.start()
        installRecentLocations()
        onFindInFiles = { [weak self] in self?.showFind(replace: false) }
        onReplaceInFiles = { [weak self] in self?.showFind(replace: true) }
    }

    /// Cmd-Shift-F / Cmd-Shift-R: floating Find / Replace in Files popup seeded with the current single-line selection.
    func showFind(replace: Bool) {
        guard let find = findPanel, let root else { return }
        var seed: String?
        if let tv = current?.textView, tv.selectedRange().length > 0 {
            let text = (tv.string as NSString).substring(with: tv.selectedRange())
            if !text.contains("\n"), text.count <= 200 { seed = text }
        }
        let host = FindPopupHost(
            root: root, engine: find.engine,
            openBuffer: { [weak self] url in self?.editors[url.standardizedFileURL.path] },
            openMatch: { [weak self] m in
                self?.open(m.url, line: m.line)
                self?.current?.textView.goToLine(m.line, column: m.column)
            },
            openFilePaths: { [weak self] in Set(self?.editors.keys.map { $0 } ?? []) },
            openInFindWindow: { [weak self] o, rep, mode in
                self?.showToolPanel("find") { find.adopt(o, replaceText: rep, replaceMode: mode) }
            })
        FindPopup.present(over: window, host: host, seed: seed, replace: replace)
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
        problems.onFixWithClaude = { [weak self] url, d in self?.fixProblemWithClaude(url: url, d) }
        problems.textProvider = { [weak self] url in self?.readText(url) }
        problems.applyFix = { [weak self] url, old, new in self?.applyProblemFix(url: url, old: old, new: new) ?? false }
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

// MARK: - Feature Map

extension ProjectWindow {
    /// Creates the per-project feature map and its "Features" bottom panel (called once per window, from `installChangeReview`).
    func installFeatureMap(root: URL, ledger: ChangeLedger) {
        guard featureMap == nil else { return }
        let map = FeatureMap(root: root)
        let panel = FeatureMapPanel(map: map, root: root)
        panel.openFile = { [weak self] url, line in
            self?.open(url, line: line)
            self?.current?.textView.goToLine(line, column: 1)
        }
        panel.projectFiles = { [weak self] in self?.projectFiles ?? [] }
        panel.sessions = { [weak ledger] in ledger?.sessions ?? [] }
        panel.onAttention = { [weak self] n in self?.setToolPanelBadge(n > 0 ? "\(n)" : nil, for: "features") }
        panel.reveal = { [weak self] in self?.showToolPanel("features") }
        tree.extraMenuItems = { [weak panel] url in panel?.treeMenuItems(for: url) ?? [] }
        changeLedgerPanel?.featureLookup = { [weak map] rels in
            guard let map else { return ([], 0) }
            return (map.features(touching: rels).map { $0.name }, map.features.isEmpty ? 0 : map.unmapped(in: rels).count)
        }
        panel.openMapFile = { [weak self] url in self?.open(url) }
        map.onSaved = { [weak self, weak map] in
            guard let map else { return }
            self?.editors[map.fileURL.standardizedFileURL.path]?.reloadIfChangedOnDisk()     // an open tab shows the panel's edit at once
        }
        featureMap = map
        featureMapPanel = panel
        registerToolPanel(id: "features", title: "Features", view: panel.view)
    }
}
