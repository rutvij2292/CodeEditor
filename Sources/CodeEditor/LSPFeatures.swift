import AppKit

// MARK: - Public API (Find usages, Rename, Format, next problem)

extension LanguageServers {
    /// Test/integration hooks. Defaults present real UI.
    static var presentPicker: ((_ window: NSWindow?, _ placeholder: String, _ items: [PickerItem]) -> Void)?
    static var renamePrompt: ((_ placeholder: String, _ window: NSWindow, _ done: @escaping (String?) -> Void) -> Void)?
    static var renameConfirm: ((_ summary: String, _ window: NSWindow?, _ done: @escaping (Bool) -> Void) -> Void)?
    /// Last user-facing status/error message (also shown as a popup near the caret when a window is visible).
    private(set) static var lastMessage: String?
    static func report(_ message: String, session: LSPSession? = nil) {
        lastMessage = message
        LSPLog.log("message: \(message)")
        session?.toast(message)
    }

    static func session(for tab: EditorTab) -> LSPSession? { LanguageServerManager.shared.sessions[ObjectIdentifier(tab)] }

    /// Alt-F7. Returns false (silently) when no running server of the file supports references.
    @discardableResult
    static func findUsages(in tab: EditorTab) -> Bool {
        guard let s = session(for: tab), s.instance(supporting: "referencesProvider") != nil else { return false }
        s.findUsages()
        return true
    }

    /// Shift-F6. Returns false when the file has no server that supports rename.
    @discardableResult
    static func rename(in tab: EditorTab, over window: NSWindow) -> Bool {
        guard let s = session(for: tab), s.instance(supporting: "renameProvider") != nil else { return false }
        s.beginRename(over: window)
        return true
    }

    static func supportsFormatting(for url: URL) -> Bool {
        LanguageServerManager.shared.session(forURL: url)?.instance(supporting: "documentFormattingProvider") != nil
    }

    /// Formats the whole document as one undo step. Returns false when unsupported (caller falls back);
    /// true means the request was dispatched. `completion(true)` fires after the edits are applied.
    @discardableResult
    static func formatDocument(in tab: EditorTab, completion: ((Bool) -> Void)? = nil) -> Bool {
        guard let s = session(for: tab), s.instance(supporting: "documentFormattingProvider") != nil else { return false }
        s.format(selection: nil, completion: completion)
        return true
    }

    @discardableResult
    static func formatSelection(in tab: EditorTab, completion: ((Bool) -> Void)? = nil) -> Bool {
        guard let s = session(for: tab), tab.textView.selectedRange().length > 0,
              s.instance(supporting: "documentRangeFormattingProvider") != nil else { return false }
        s.format(selection: tab.textView.selectedRange(), completion: completion)
        return true
    }
}

// MARK: - Session implementation

extension LSPSession {
    /// Shows a transient popup near the caret (no-op without a visible window).
    func toast(_ markdown: String) {
        guard let tv = textView, tv.window?.isVisible == true else { return }
        hoverToken += 1
        let token = hoverToken
        let popup = LSPPopups.hover
        popup.setContent(LSPMarkdown.render(markdown))
        popup.show(for: self, anchor: screenRect(forCharacterRange: NSRange(location: tv.selectedRange().location, length: 1)))
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
            if let self, self.hoverToken == token { LSPPopups.hideHover() }
        }
    }

    private func failureText(_ e: LSPError, action: String) -> String {
        if e.code == LSPError.notRunning.code { return "\(action) cancelled: the language server stopped" }
        if e.code == LSPError.timeout.code { return "\(action) cancelled: the language server did not answer in time" }
        return "\(action) failed: \(e.message)"
    }

    // MARK: Find usages

    func findUsages() {
        guard let tv = textView, let inst = instance(supporting: "referencesProvider"), let client = inst.client else { return }
        flushChanges()
        let caret = tv.selectedRange().location
        let word = wordRange(at: caret)
        let symbol = word.length > 0 ? (text as NSString).substring(with: word) : "symbol"
        let params: [String: Any] = ["textDocument": ["uri": uri], "position": LSPLineTable(text as NSString).lspPosition(caret),
                                     "context": ["includeDeclaration": true]]
        let root = inst.root.path
        client.request("textDocument/references", params, timeout: 30) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let e): LanguageServers.report(self.failureText(e, action: "Find usages"), session: self)
            case .success(let v):
                let locs = LSPUIParse.locations(from: v)
                guard !locs.isEmpty else { LanguageServers.report("No usages of \(symbol) found", session: self); return }
                self.presentUsages(locs, symbol: symbol, root: root)
            }
        }
    }

    private func presentUsages(_ all: [LSPLocation], symbol: String, root: String) {
        let sorted = all.sorted { ($0.url.path, $0.line, $0.character) < ($1.url.path, $1.line, $1.character) }
        let cap = 200
        var cache: [String: [Substring]] = [:]
        func lineText(_ loc: LSPLocation) -> String {
            let path = loc.url.standardizedFileURL.path
            if cache[path] == nil {
                if let s = LanguageServerManager.shared.session(forURL: loc.url) { cache[path] = s.text.split(separator: "\n", omittingEmptySubsequences: false) }
                else if let data = try? Data(contentsOf: loc.url), data.count < 8_000_000, let s = String(data: data, encoding: .utf8) {
                    cache[path] = s.split(separator: "\n", omittingEmptySubsequences: false)
                } else { cache[path] = [] }
            }
            let lines = cache[path]!
            guard loc.line < lines.count else { return "" }
            let t = lines[loc.line].trimmingCharacters(in: .whitespacesAndNewlines)
            return t.count > 200 ? String(t.prefix(200)) + "…" : t
        }
        let items = sorted.prefix(cap).map { loc -> PickerItem in
            var rel = loc.url.standardizedFileURL.path
            if rel.hasPrefix(root + "/") { rel = String(rel.dropFirst(root.count + 1)) }
            let title = lineText(loc)
            return PickerItem(title: title.isEmpty ? "(blank line)" : title, detail: "\(rel):\(loc.line + 1)",
                              symbol: "arrow.turn.down.right", key: title + " " + rel) {
                LSPSession.open(loc, from: nil)
            }
        }
        var placeholder = "Usages of \(symbol) (\(sorted.count))"
        if sorted.count > cap { placeholder += " - showing the first \(cap); narrow down the search" }
        if let hook = LanguageServers.presentPicker { hook(textView?.window, placeholder, items); return }
        guard let window = textView?.window else { return }
        QuickPicker.present(over: window, placeholder: placeholder, items: items)
    }

    static func open(_ loc: LSPLocation, from session: LSPSession?) {
        LanguageServers.openLocation?(loc.url, loc.line + 1, loc.character + 1)
    }

    // MARK: Rename

    func beginRename(over window: NSWindow) {
        guard let tv = textView, let inst = instance(supporting: "renameProvider"), let client = inst.client else { return }
        flushChanges()
        let caret = tv.selectedRange().location
        let snapshot = text
        let word = wordRange(at: caret)
        let position = LSPLineTable(snapshot as NSString).lspPosition(caret)
        let params: [String: Any] = ["textDocument": ["uri": uri], "position": position]
        func prompt(_ placeholder: String) {
            let go: (String?) -> Void = { [weak self] name in
                guard let self, let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty, name != placeholder else { return }
                self.performRename(name, position: position, snapshot: snapshot, over: window)
            }
            if let hook = LanguageServers.renamePrompt { hook(placeholder, window, go); return }
            LSPSession.promptSheet(title: "Rename", message: "New name for \(placeholder)", initial: placeholder,
                                   button: "Rename", window: window, done: go)
        }
        let provider = inst.capabilities["renameProvider"] as? [String: Any]
        guard (provider?["prepareProvider"] as? Bool) == true else {
            guard word.length > 0 else { LanguageServers.report("Nothing to rename here", session: self); return }
            prompt((snapshot as NSString).substring(with: word)); return
        }
        client.request("textDocument/prepareRename", params, timeout: 10) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let e):
                // Servers answer "cannot rename" with an error; surface their text.
                LanguageServers.report(e.code == LSPError.notRunning.code ? self.failureText(e, action: "Rename")
                                                                          : "Cannot rename here: \(e.message)", session: self)
            case .success(let v):
                guard let d = v as? [String: Any] else { LanguageServers.report("Nothing to rename here", session: self); return }
                if let p = d["placeholder"] as? String { prompt(p); return }
                if let r = (d["range"] ?? (d["start"] != nil ? d : nil)) as? [String: Any],
                   let nr = LSPLineTable(snapshot as NSString).range(fromLSP: r), NSMaxRange(nr) <= (snapshot as NSString).length {
                    prompt((snapshot as NSString).substring(with: nr)); return
                }
                guard word.length > 0 else { LanguageServers.report("Nothing to rename here", session: self); return }
                prompt((snapshot as NSString).substring(with: word))
            }
        }
    }

    func performRename(_ newName: String, position: [String: Int], snapshot: String, over window: NSWindow?,
                       completion: ((LSPApplyResult) -> Void)? = nil) {
        guard let inst = instance(supporting: "renameProvider"), let client = inst.client else { return }
        flushChanges()
        let params: [String: Any] = ["textDocument": ["uri": uri], "position": position, "newName": newName]
        client.request("textDocument/rename", params, timeout: 60) { [weak self] result in
            guard let self else { return }
            func fail(_ m: String) { LanguageServers.report(m, session: self); completion?(LSPApplyResult(applied: false, failureReason: m)) }
            switch result {
            case .failure(let e): fail(self.failureText(e, action: "Rename")); return
            case .success(let v):
                guard v != nil else { fail("Rename produced no changes"); return }
                guard self.text == snapshot else { fail("Rename cancelled: the document changed while the server was working"); return }
                let parsed = LSPEdits.parse(v)
                if let err = parsed.error { fail("Rename cancelled: \(err)"); return }
                let n = parsed.files.reduce(0) { $0 + $1.edits.count }, m = parsed.files.filter { !$0.edits.isEmpty }.count
                guard n > 0 else { fail("Rename produced no changes"); return }
                let summary = "Rename updates \(n) occurrence\(n == 1 ? "" : "s") in \(m) file\(m == 1 ? "" : "s")"
                let go: (Bool) -> Void = { ok in
                    guard ok else { completion?(LSPApplyResult(applied: false, failureReason: "cancelled")); return }
                    let r = LSPEdits.apply(parsed.files, label: "Rename")
                    if let f = r.failureReason { fail("Rename failed: \(f)") }
                    else {
                        LanguageServers.report("Renamed to \(newName): \(n) occurrence\(n == 1 ? "" : "s") in \(m) file\(m == 1 ? "" : "s")", session: self)
                        completion?(r)
                    }
                }
                if let hook = LanguageServers.renameConfirm { hook(summary, window, go); return }
                guard let window else { go(true); return }
                LSPSession.confirmSheet(title: summary, message: "Open files can be undone with Undo; other files are saved immediately.",
                                        button: "Rename", window: window, done: go)
            }
        }
    }

    // MARK: Format

    func format(selection: NSRange?, completion: ((Bool) -> Void)?) {
        let cap = selection == nil ? "documentFormattingProvider" : "documentRangeFormattingProvider"
        guard let tab, let inst = instance(supporting: cap), let client = inst.client else { completion?(false); return }
        flushChanges()
        let snapshot = text
        let table = LSPLineTable(snapshot as NSString)
        var params: [String: Any] = ["textDocument": ["uri": uri],
                                     "options": ["tabSize": tab.indent.size, "insertSpaces": !tab.indent.useTabs,
                                                 "trimTrailingWhitespace": true, "insertFinalNewline": true]]
        if let sel = selection, sel.length > 0 {
            params["range"] = ["start": table.lspPosition(sel.location), "end": table.lspPosition(NSMaxRange(sel))]
        } else if selection != nil { completion?(false); return }
        client.request(selection == nil ? "textDocument/formatting" : "textDocument/rangeFormatting", params, timeout: 20) { [weak self] result in
            guard let self else { completion?(false); return }
            switch result {
            case .failure(let e): LanguageServers.report(self.failureText(e, action: "Format"), session: self); completion?(false)
            case .success(let v):
                guard self.tab != nil else { completion?(false); return }       // closed mid-request
                guard self.text == snapshot else {
                    LanguageServers.report("Format cancelled: the document changed while the server was working", session: self)
                    completion?(false); return
                }
                let edits = LSPEdits.parseTextEdits(v)
                let ns = snapshot as NSString
                var ranges: [(range: NSRange, text: String)] = []
                for e in edits {
                    guard let r = table.range(fromLSP: e.range) else { completion?(false); return }
                    ranges.append((r, e.newText))
                }
                ranges.sort { $0.range.location < $1.range.location }
                for i in 1..<max(1, ranges.count) where NSMaxRange(ranges[i - 1].range) > ranges[i].range.location {
                    LanguageServers.report("Format failed: overlapping edits", session: self); completion?(false); return
                }
                let minimal = LSPEdits.minimized(ranges, in: ns).sorted { $0.range.location > $1.range.location }
                if let tv = self.textView { LSPEdits.applyToBuffer(tv, minimal, actionName: "Format") }
                completion?(true)
            }
        }
    }

    // MARK: Sheets

    static func promptSheet(title: String, message: String, initial: String, button: String, window: NSWindow,
                            done: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = initial
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { resp in done(resp == .alertFirstButtonReturn ? field.stringValue : nil) }
        field.selectText(nil)
    }

    static func confirmSheet(title: String, message: String, button: String, window: NSWindow, done: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { done($0 == .alertFirstButtonReturn) }
    }
}
