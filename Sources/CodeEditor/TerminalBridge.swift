import AppKit

/// Pure text formatting for the editor -> terminal bridge (what gets pasted into an AI CLI's prompt).
/// Nothing here presses Return: results are inserted via bracketed paste so the user reviews and submits.
enum TerminalBridge {
    static let pasteStart: [UInt8] = [0x1b, 0x5b, 0x32, 0x30, 0x30, 0x7e]   // ESC [ 200 ~
    static let pasteEnd: [UInt8] = [0x1b, 0x5b, 0x32, 0x30, 0x31, 0x7e]     // ESC [ 201 ~

    /// Bytes written to the pty. With bracketed paste on, the text is wrapped in ESC[200~ ... ESC[201~ (newlines kept).
    /// Without it, newlines would act as Return in a line editor, so they are folded into single spaces.
    static func pasteBytes(_ text: String, bracketed: Bool) -> [UInt8] {
        if bracketed { return pasteStart + Array(text.utf8) + pasteEnd }
        var out = ""
        var lastWasBreak = false
        for ch in text {
            if ch == "\n" || ch == "\r" || ch == "\r\n" {
                if !lastWasBreak { out.append(" ") }
                lastWasBreak = true
            } else { out.append(ch); lastWasBreak = false }
        }
        return Array(out.utf8)
    }

    // MARK: Paths

    /// Path relative to `root` (symlink-insensitive: /var vs /private/var); absolute when outside the project.
    static func relativePath(_ url: URL, root: URL) -> String {
        for (u, r) in [(url.standardizedFileURL.path, root.standardizedFileURL.path),
                       (url.resolvingSymlinksInPath().path, root.resolvingSymlinksInPath().path)] {
            if u == r { return "." }
            if u.hasPrefix(r + "/") { return String(u.dropFirst(r.count + 1)) }
        }
        return url.standardizedFileURL.path
    }

    /// `@path`; a path containing whitespace is quoted as `@"my dir/File.php"`.
    static func mention(_ path: String) -> String {
        path.rangeOfCharacter(from: .whitespaces) != nil ? "@\"\(path)\"" : "@" + path
    }

    /// `@a.php @dir/b.php ` (directories get a trailing slash); trailing space so the user can keep typing.
    static func fileReferences(_ urls: [URL], root: URL) -> String {
        guard !urls.isEmpty else { return "" }
        return urls.map { url -> String in
            var isDir: ObjCBool = false
            var p = relativePath(url, root: root)
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue, p != ".", !p.hasSuffix("/") { p += "/" }
            return mention(p)
        }.joined(separator: " ") + " "
    }

    // MARK: Selections

    /// 1-based inclusive line range of a selection. A selection ending right after a newline does not include the next line.
    static func lineRange(in text: NSString, selection: NSRange) -> (start: Int, end: Int) {
        let length = text.length
        let loc = min(max(0, selection.location), length)
        var endLoc = min(length, loc + max(0, selection.length))
        if selection.length > 0, endLoc > loc, text.character(at: endLoc - 1) == 10 { endLoc -= 1 }
        func line(at offset: Int) -> Int {
            var n = 1
            var i = 0
            while i < offset { if text.character(at: i) == 10 { n += 1 }; i += 1 }
            return n
        }
        let start = line(at: loc)
        return (start, max(start, endLoc == loc ? start : line(at: endLoc)))
    }

    /// `@path:12 ` for one line, `@path:12-15 ` for a range.
    static func selectionReference(path: String, start: Int, end: Int) -> String {
        let r = end > start ? "\(start)-\(end)" : "\(start)"
        let base = mention(path)
        return (base.hasSuffix("\"") ? String(base.dropLast()) + ":\(r)\"" : base + ":\(r)") + " "
    }

    static func fenceLanguage(forPath path: String) -> String {
        let name = (path as NSString).lastPathComponent
        if name.hasSuffix(".blade.php") { return "blade" }
        let map = ["php": "php", "js": "js", "jsx": "jsx", "mjs": "js", "ts": "ts", "tsx": "tsx", "vue": "vue", "html": "html",
                   "css": "css", "scss": "scss", "json": "json", "md": "markdown", "yml": "yaml", "yaml": "yaml", "sh": "bash",
                   "sql": "sql", "xml": "xml", "py": "python", "rb": "ruby", "go": "go", "rs": "rust", "swift": "swift"]
        return map[(name as NSString).pathExtension.lowercased()] ?? ""
    }

    /// Header line `path:START-END`, then the code in a fenced block (longer fence if the code contains ```). Ends with a newline.
    static func fencedBlock(path: String, start: Int, end: Int, text: String) -> String {
        var body = text
        while body.hasSuffix("\n") { body.removeLast() }
        var fence = "```"
        while body.contains(fence) { fence += "`" }
        let range = end > start ? "\(start)-\(end)" : "\(start)"
        return "\(path):\(range)\n\(fence)\(fenceLanguage(forPath: path))\n\(body)\n\(fence)\n"
    }

    // MARK: Problems / changes

    static func severityName(_ s: Int) -> String {
        switch s { case 1: return "error"; case 2: return "warning"; case 3: return "info"; default: return "hint" }
    }

    /// "Problems in app/A.php (1 error, 1 warning):" then `app/A.php:12:5 error: message [source code]` per line.
    static func problemsText(path: String, diagnostics: [FileProblems.Diagnostic]) -> String {
        let errors = diagnostics.filter { $0.severity == 1 }.count, warnings = diagnostics.filter { $0.severity == 2 }.count
        var parts: [String] = []
        if errors > 0 { parts.append("\(errors) error\(errors == 1 ? "" : "s")") }
        if warnings > 0 { parts.append("\(warnings) warning\(warnings == 1 ? "" : "s")") }
        let others = diagnostics.count - errors - warnings
        if others > 0 { parts.append("\(others) other") }
        var lines = ["Problems in \(path) (\(parts.joined(separator: ", "))):"]
        for d in diagnostics {
            var tag = [d.source, d.code].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            if !tag.isEmpty { tag = " [\(tag)]" }
            let message = d.message.replacingOccurrences(of: "\n", with: " ")
            lines.append("\(path):\(d.line):\(d.column) \(severityName(d.severity)): \(message)\(tag)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// `git status`/`git diff --stat`-style summary of the working tree.
    static func changeSummary(branch: String?, changes: [GitChange], stat: String?) -> String {
        var lines = ["Changed files" + (branch.map { " on \($0)" } ?? "") + " (\(changes.count)):"]
        for c in changes {
            let code = c.isUntracked ? "??" : "\(c.index)\(c.work)"
            lines.append(" \(code) \(c.path)")
        }
        if let stat, !stat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("")
            lines.append(stat.trimmingCharacters(in: .newlines))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

// MARK: - ProjectWindow bridge actions

extension ProjectWindow {
    /// Inserts `text` into the active terminal tab through bracketed paste (no Return). Shows + focuses the terminal first
    /// (lazily starting a shell) when it is hidden.
    func sendToTerminal(_ text: String, focus: Bool = true) {
        guard !text.isEmpty, let term = terminalPanel else { return }
        if !isTerminalVisible { showTerminalPanel(focus: false) }
        term.paste(text)
        if focus { term.focusTerminal() }
    }

    /// The files an "@file" action refers to: tree selection when the tree has focus, else the current editor file,
    /// else the tree selection.
    private func fileTargets() -> [URL] {
        let treeSel: [URL] = tree.outline.selectedRowIndexes.compactMap { (tree.outline.item(atRow: $0) as? FileNode)?.url }
            .filter { $0.path != root?.path }
        if window.firstResponder === tree.outline, !treeSel.isEmpty { return treeSel }
        if let url = current?.url { return [url] }
        return treeSel
    }

    @discardableResult
    func sendFileReference() -> String? {
        guard let root else { return nil }
        let urls = fileTargets()
        guard !urls.isEmpty else { statusBar.flash("No file to reference"); return nil }
        let text = TerminalBridge.fileReferences(urls, root: root)
        sendToTerminal(text)
        return text
    }

    @discardableResult
    func sendSelectionReference() -> String? {
        guard let root, let editor = current else { statusBar.flash("No editor selection"); return nil }
        let tv = editor.textView
        let r = TerminalBridge.lineRange(in: tv.string as NSString, selection: tv.selectedRange())
        let text = TerminalBridge.selectionReference(path: TerminalBridge.relativePath(editor.url, root: root), start: r.start, end: r.end)
        sendToTerminal(text)
        return text
    }

    @discardableResult
    func sendSelectionText() -> String? {
        guard let root, let editor = current else { statusBar.flash("No editor selection"); return nil }
        let tv = editor.textView
        let sel = tv.selectedRange()
        guard sel.length > 0 else { statusBar.flash("Select some code first"); return nil }
        let ns = tv.string as NSString
        let r = TerminalBridge.lineRange(in: ns, selection: sel)
        let text = TerminalBridge.fencedBlock(path: TerminalBridge.relativePath(editor.url, root: root), start: r.start, end: r.end,
                                              text: ns.substring(with: sel))
        sendToTerminal(text)
        return text
    }

    /// Opens the Ask Claude chat for the selected code (answered by the Claude Code CLI login, no API key).
    func askClaudeAboutSelection() {
        guard let root, let editor = current else { statusBar.flash("Open a file and select some code first"); return }
        let tv = editor.textView
        let sel = tv.selectedRange()
        guard sel.length > 0 else { statusBar.flash("Select some code to ask Claude about"); return }
        let ns = tv.string as NSString
        let r = TerminalBridge.lineRange(in: ns, selection: sel)
        let ctx = ClaudeAskPanel.Context(path: TerminalBridge.relativePath(editor.url, root: root), startLine: r.start, endLine: r.end,
                                         code: ns.substring(with: sel))
        ClaudeAskPanel.present(over: window, context: ctx, cwd: nil) { [weak self] text in self?.sendToTerminal(text) }
    }

    @discardableResult
    func sendProblems() -> String? {
        guard let root, let editor = current else { return nil }
        let path = editor.url.standardizedFileURL.path
        let file = LanguageServers.problems(forRoot: root).first { $0.url.standardizedFileURL.path == path }
        guard let diagnostics = file?.diagnostics, !diagnostics.isEmpty else { statusBar.flash("No problems in this file"); return nil }
        let text = TerminalBridge.problemsText(path: TerminalBridge.relativePath(editor.url, root: root), diagnostics: diagnostics)
        sendToTerminal(text)
        return text
    }

    /// Working-tree summary (status list + `git diff --stat HEAD`) pasted into the prompt, e.g. before "write a commit message".
    func sendCommitContext() {
        guard let repoRoot = gitRoot else { statusBar.flash("Not a Git repository"); return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let repo = GitRepo(root: repoRoot)
            let status = try? repo.statusAndBranch()
            let stat = try? repo.text(["diff", "--stat", "HEAD"])
            DispatchQueue.main.async {
                guard let self, let status else { self?.statusBar.flash("Could not read Git status"); return }
                guard !status.changes.isEmpty else { self.statusBar.flash("No changes"); return }
                self.sendToTerminal(TerminalBridge.changeSummary(branch: status.info.name, changes: status.changes, stat: stat))
            }
        }
    }
}
