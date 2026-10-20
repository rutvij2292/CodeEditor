import AppKit

/// One entry of `textDocument/codeAction`: a quick fix, refactor or source action offered by a language server.
struct LSPCodeAction {
    let title: String
    let kind: String?
    let isPreferred: Bool
    /// The server's raw object: a CodeAction, or a bare Command wrapped as `["command": <Command>]`.
    let raw: [String: Any]
    let instance: LSPServerInstance

    /// Short label for the picker's right column.
    var kindLabel: String {
        guard let kind else { return "" }
        if kind.hasPrefix("quickfix") { return "Quick Fix" }
        if kind.hasPrefix("source.organizeImports") { return "Organize Imports" }
        if kind.hasPrefix("source") { return "Source" }
        if kind.hasPrefix("refactor.extract") { return "Extract" }
        if kind.hasPrefix("refactor.inline") { return "Inline" }
        if kind.hasPrefix("refactor") { return "Refactor" }
        return kind
    }

    var sortRank: Int {
        if isPreferred { return 0 }
        guard let kind else { return 3 }
        if kind.hasPrefix("quickfix") { return 1 }
        if kind.hasPrefix("refactor") { return 2 }
        return 3
    }

    var symbol: String {
        guard let kind else { return "wand.and.stars" }
        if kind.hasPrefix("quickfix") { return "lightbulb" }
        if kind.hasPrefix("refactor") { return "arrow.triangle.2.circlepath" }
        return "wand.and.stars"
    }

    /// Parses a codeAction response (null | (Command | CodeAction)[]), dropping disabled actions.
    static func parse(_ value: Any?, instance: LSPServerInstance) -> [LSPCodeAction] {
        ((value as? [[String: Any]]) ?? []).compactMap { d in
            guard let title = d["title"] as? String, !title.isEmpty else { return nil }
            if d["disabled"] is [String: Any] { return nil }
            if d["command"] is String {          // bare Command: title, command, arguments
                return LSPCodeAction(title: title, kind: nil, isPreferred: false, raw: ["title": title, "command": d], instance: instance)
            }
            return LSPCodeAction(title: title, kind: d["kind"] as? String, isPreferred: (d["isPreferred"] as? Bool) ?? false,
                                 raw: d, instance: instance)
        }
    }

    static func sorted(_ actions: [LSPCodeAction]) -> [LSPCodeAction] {
        actions.enumerated().sorted { a, b in
            a.element.sortRank != b.element.sortRank ? a.element.sortRank < b.element.sortRank : a.offset < b.offset
        }.map(\.element)
    }
}

extension LSPSession {
    /// Alt-Return: asks every server of this file for actions at the caret / selection (with the diagnostics under it) and
    /// shows them in a picker; choosing one applies its edit and / or runs its command.
    func showCodeActions() {
        guard let tv = textView else { return }
        let range = tv.selectedRange()
        fetchCodeActions(range: range) { [weak self] actions in
            guard let self else { return }
            guard !actions.isEmpty else { LanguageServers.report("No quick fixes or actions available here", session: self); return }
            let items = actions.map { a in
                PickerItem(title: a.title, detail: a.kindLabel, symbol: a.symbol, key: a.title + " " + a.kindLabel) { [weak self] in self?.run(a) }
            }
            let placeholder = "Quick fixes and actions (\(actions.count))"
            if let hook = LanguageServers.presentPicker { hook(tv.window, placeholder, items); return }
            guard let window = tv.window else { return }
            QuickPicker.present(over: window, placeholder: placeholder, items: items)
        }
    }

    func fetchCodeActions(range: NSRange, completion: @escaping ([LSPCodeAction]) -> Void) {
        let servers = instances(supporting: "codeActionProvider")
        guard !servers.isEmpty else {
            LanguageServers.report("No language server with quick fixes is running for this file", session: self)
            return
        }
        flushChanges()
        let table = LSPLineTable(text as NSString)
        let lspRange: [String: Any] = ["start": table.lspPosition(range.location), "end": table.lspPosition(NSMaxRange(range))]
        let path = url.standardizedFileURL.path
        var all: [LSPCodeAction] = []
        let group = DispatchGroup()
        for inst in servers {
            guard let client = inst.client else { continue }
            let diags = (manager.diagnostics[path]?[inst.config.id] ?? []).filter {
                $0.range.location <= NSMaxRange(range) && NSMaxRange($0.range) >= range.location
            }.map { d -> [String: Any] in
                var o: [String: Any] = ["range": ["start": table.lspPosition(d.range.location), "end": table.lspPosition(NSMaxRange(d.range))],
                                        "message": d.message, "severity": d.severity]
                if let s = d.source { o["source"] = s }
                if let c = d.code { o["code"] = Int(c) ?? c }
                return o
            }
            let params: [String: Any] = ["textDocument": ["uri": uri], "range": lspRange,
                                         "context": ["diagnostics": diags, "triggerKind": 1]]
            group.enter()
            client.request("textDocument/codeAction", params, timeout: 15) { result in
                if case .success(let v) = result { all += LSPCodeAction.parse(v, instance: inst) }
                group.leave()
            }
            // Servers only list file-wide source actions (organize imports, fix all, ...) when asked for them by kind.
            let kinds = ((inst.capabilities["codeActionProvider"] as? [String: Any])?["codeActionKinds"] as? [String]) ?? ["source"]
            if kinds.contains(where: { $0.hasPrefix("source") }) {
                var sourceParams = params
                sourceParams["context"] = ["diagnostics": [], "only": ["source"], "triggerKind": 1]
                group.enter()
                client.request("textDocument/codeAction", sourceParams, timeout: 15) { result in
                    if case .success(let v) = result {
                        let have = Set(all.map(\.title))
                        all += LSPCodeAction.parse(v, instance: inst).filter { !have.contains($0.title) }
                    }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) {
            var seen = Set<String>()
            completion(LSPCodeAction.sorted(all).filter { seen.insert($0.title + "|" + ($0.kind ?? "")).inserted })
        }
    }

    /// Applies the action: its edit (resolving it first when the server defers it), then its command.
    func run(_ action: LSPCodeAction) {
        let snapshot = text
        func finish(_ raw: [String: Any]) {
            if let edit = raw["edit"] {
                guard text == snapshot else { LanguageServers.report("“\(action.title)” cancelled: the document changed meanwhile", session: self); return }
                let parsed = LSPEdits.parse(edit)
                if let err = parsed.error { LanguageServers.report("“\(action.title)” cancelled: \(err)", session: self); return }
                if parsed.files.contains(where: { !$0.edits.isEmpty }) {
                    let r = LSPEdits.apply(parsed.files, label: action.title)
                    if let f = r.failureReason { LanguageServers.report("“\(action.title)” failed: \(f)", session: self); return }
                }
            }
            if let command = raw["command"] as? [String: Any], let name = command["command"] as? String {
                var params: [String: Any] = ["command": name]
                if let args = command["arguments"] { params["arguments"] = args }
                action.instance.client?.request("workspace/executeCommand", params, timeout: 30) { [weak self] result in
                    if case .failure(let e) = result, let self { LanguageServers.report("“\(action.title)” failed: \(e)", session: self) }
                }
            }
        }
        let resolvable = (action.instance.capabilities["codeActionProvider"] as? [String: Any])?["resolveProvider"] as? Bool == true
        if resolvable, action.raw["edit"] == nil, action.raw["command"] == nil, let client = action.instance.client {
            client.request("codeAction/resolve", action.raw, timeout: 15) { [weak self] result in
                switch result {
                case .success(let v): finish((v as? [String: Any]) ?? action.raw)
                case .failure(let e): if let self { LanguageServers.report("“\(action.title)” failed: \(e)", session: self) }
                }
            }
        } else { finish(action.raw) }
    }
}

extension LanguageServers {
    /// Alt-Return. Returns false (after a hint) when the file has no language-server session.
    @discardableResult
    static func showCodeActions(in tab: EditorTab) -> Bool {
        guard let s = session(for: tab) else { return false }
        s.showCodeActions()
        return true
    }
}
