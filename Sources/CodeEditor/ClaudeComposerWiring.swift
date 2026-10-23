import AppKit

// Glue between the prompt composer / "Fix with Claude" and a project window: the host closures, sending to the agent tab and
// the entry points hooked into Problems, Tests, the Quick Fix picker, terminal selections and the Git menu.

extension ProjectWindow {
    /// UserDefaults `claude.fixSendDirect` = true sends "Fix with Claude" prompts straight to a running agent tab instead of opening
    /// the composer for editing first (default: composer).
    static var fixSendsDirectly: Bool { UserDefaults.standard.bool(forKey: "claude.fixSendDirect") }

    // MARK: composer

    func composerHost() -> ClaudeComposerHost {
        let root = self.root ?? URL(fileURLWithPath: NSHomeDirectory())
        return ClaudeComposerHost(
            root: root,
            searchFiles: { [weak self] q in
                guard let self else { return [] }
                if q.isEmpty { return self.editors.keys.compactMap { p -> String? in
                    let r = TerminalBridge.relativePath(URL(fileURLWithPath: p), root: root)
                    return r.hasPrefix("/") ? nil : r }.sorted().prefix(ClaudeComposer.maxSuggestions).map { $0 } }
                return self.indexSearch(q, limit: ClaudeComposer.maxSuggestions)
            },
            slashEntries: { ClaudeComposerLogic.scanSlashEntries(root: root) },
            send: { [weak self] text in self?.sendPromptToAgent(text) ?? false },
            startAgentAndSend: { [weak self] text in self?.startAgentAndSend(text) })
    }

    /// Cmd-Shift-Return. Pre-fills `@path:start-end` when the editor has a selection.
    func showClaudeComposer(prefill: String? = nil) {
        var pre = prefill
        if pre == nil, let tv = current?.textView, tv.selectedRange().length > 0, let root, let url = current?.url {
            let r = TerminalBridge.lineRange(in: tv.string as NSString, selection: tv.selectedRange())
            pre = TerminalBridge.selectionReference(path: TerminalBridge.relativePath(url, root: root), start: r.start, end: r.end)
        }
        ClaudeComposer.present(over: window, host: composerHost(), prefill: pre)
    }

    /// Pastes `text` into the agent tab (the active one when it is an agent, else the first Claude tab) and presses Return.
    /// False when no agent tab exists.
    @discardableResult
    func sendPromptToAgent(_ text: String) -> Bool {
        guard let term = terminalPanel else { return false }
        if term.activeAgentTab == nil {
            guard let i = term.tabTitles.firstIndex(where: { $0.hasPrefix("Claude") }) else { return false }
            if !isTerminalVisible { showTerminalPanel(focus: false) }
            term.select(i)
        } else if !isTerminalVisible { showTerminalPanel(focus: false) }
        submit(text, in: term)
        return true
    }

    private func submit(_ text: String, in term: TerminalPanelController) {
        let tab = term.activeIndex
        term.paste(text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak term] in term?.send("\r", tab: tab) }
        term.focusTerminal()
    }

    /// New Claude Code tab; the prompt is sent after the TUI has had a few seconds to start.
    func startAgentAndSend(_ text: String) {
        let agents = TerminalAgents.all()
        guard let term = terminalPanel, let a = agents.first(where: { $0.command == "claude" }) ?? TerminalAgents.primary(in: agents) else {
            statusBar.flash("No AI agent CLI found on PATH"); return
        }
        if !isTerminalVisible { showTerminalPanel(focus: false) }
        term.startAgent(a)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self, weak term] in
            guard let self, let term else { return }
            self.submit(text, in: term)
        }
    }

    // MARK: Fix with Claude

    /// Default: opens the composer pre-filled so the prompt can be edited; with `claude.fixSendDirect` and a running agent it is sent.
    func fixWithClaude(prompt: String) {
        if Self.fixSendsDirectly, sendPromptToAgent(prompt) { return }
        showClaudeComposer(prefill: prompt)
    }

    func indexSearch(_ q: String, limit: Int) -> [String] { index?.search(q, limit: limit).map(\.path) ?? [] }

    private func relPath(_ url: URL) -> String { root.map { TerminalBridge.relativePath(url, root: $0) } ?? url.path }

    private func readText(_ url: URL) -> String? {
        if let tab = editors[url.standardizedFileURL.path] { return tab.textView.string }
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        return (try? h.read(upToCount: 400_000)).map { String(decoding: $0, as: UTF8.self) }
    }

    func fixProblemWithClaude(url: URL, _ d: FileProblems.Diagnostic) {
        fixWithClaude(prompt: FixWithClaude.problemPrompt(path: relPath(url), line: d.line, column: d.column, severity: d.severity,
                                                          message: d.message, source: d.source, code: d.code, fileText: readText(url)))
    }

    func fixTestWithClaude(_ r: TestResult) {
        let url = r.file.isEmpty ? nil : URL(fileURLWithPath: r.file)
        fixWithClaude(prompt: FixWithClaude.testPrompt(r, path: url.map(relPath) ?? "", fileText: url.flatMap(readText)))
    }

    /// Quick Fix picker entry: the diagnostics on the caret line (all severities up to warning), else just the line.
    func fixCaretWithClaude(_ s: LSPSession) {
        guard let tv = s.textView else { return }
        let ns = tv.string as NSString
        let table = LSPLineTable(ns)
        let caret = tv.selectedRange().location
        let line = table.position(of: caret).line + 1
        let here = s.allDiagnostics.filter { $0.severity <= 2 && table.position(of: $0.range.location).line + 1 <= line && table.position(of: NSMaxRange($0.range)).line + 1 >= line }
        if let d = here.first {
            let p = table.position(of: d.range.location)
            fixWithClaude(prompt: FixWithClaude.problemPrompt(path: relPath(s.url), line: p.line + 1, column: p.character + 1, severity: d.severity,
                                                              message: d.message, source: d.source, code: d.code, fileText: tv.string))
        } else if let snip = FixWithClaude.snippet(of: tv.string, around: line) {
            let block = TerminalBridge.fencedBlock(path: relPath(s.url), start: snip.start, end: snip.end, text: snip.text)
            fixWithClaude(prompt: "There is a problem near line \(line) of \(relPath(s.url)). Find and fix it:\n\n" + block)
        }
    }

    /// Terminal selection (context menu / Ask Claude About Selection while the terminal has focus). True when handled.
    @discardableResult
    func askClaudeAboutTerminalSelection() -> Bool {
        guard let tv = window.firstResponder as? CETerminalView, let sel = tv.getSelection(),
              !sel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        showClaudeComposer(prefill: FixWithClaude.selectionPrompt(sel))
        return true
    }

    /// Git menu: composer pre-filled with a review request for the uncommitted changes (the agent runs `git diff` itself).
    func reviewDiffWithClaude() {
        guard let repoRoot = gitRoot else { statusBar.flash("Not a Git repository"); return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let repo = GitRepo(root: repoRoot)
            let status = try? repo.statusAndBranch()
            let stat = try? repo.text(["diff", "--stat", "HEAD"])
            DispatchQueue.main.async {
                guard let self, let status else { self?.statusBar.flash("Could not read Git status"); return }
                guard !status.changes.isEmpty else { self.statusBar.flash("No changes to review"); return }
                self.fixWithClaude(prompt: FixWithClaude.diffReviewPrompt(branch: status.info.name, changes: status.changes, stat: stat))
            }
        }
    }
}

enum ClaudeComposerWiring {
    /// Once per process: hooks that need a window lookup (Quick Fix entry, terminal context menu).
    static func install() {
        func owner(_ window: NSWindow?) -> ProjectWindow? {
            guard let window else { return nil }
            return (NSApp.delegate as? AppDelegate)?.windows.first { $0.window === window }
        }
        LanguageServers.fixWithClaude = { s in owner(s.textView?.window)?.fixCaretWithClaude(s) }
        CETerminalView.askClaudeHandler = { owner($0)?.askClaudeAboutTerminalSelection() ?? false }
    }
}
