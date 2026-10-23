import AppKit

// UI glue for native find usages (Alt-F7) and rename (Shift-F6). Results go through the existing QuickPicker list that the LSP
// usages already use; rename prompts with the LSP prompt sheet and previews its edits in the same list. Nothing is retained after
// the picker closes except the (capped) item closures.

enum NativePHPUI {
    // Test / integration hooks (defaults present real UI).
    static var presentHook: ((_ title: String, _ items: [PickerItem]) -> Void)?
    static var messageHook: ((String) -> Void)?
    static var promptHook: ((_ initial: String, _ done: @escaping (String?) -> Void) -> Void)?
    static var confirmHook: ((_ plan: NPRenamePlan, _ done: @escaping (Bool) -> Void) -> Void)?
    static var vendorConfirmHook: ((_ message: String, _ done: @escaping (Bool) -> Void) -> Void)?

    private static var token: CancelToken?

    static func cancel() { token?.cancel(); token = nil }

    static func message(_ s: String, window: NSWindow? = nil) {
        LanguageServers.report(s)
        if let h = messageHook { h(s); return }
        guard !AppEnv.headless, let window, window.isVisible else { return }
        let a = NSAlert()
        a.messageText = s
        a.beginSheetModal(for: window)
    }

    static func liveTexts(_ w: ProjectWindow) -> [String: NSString] {
        var out: [String: NSString] = [:]
        for (path, tab) in w.editors where tab.isDirty && (path.hasSuffix(".php") || path.hasSuffix(".phtml")) {
            out[path] = tab.textView.string as NSString
        }
        return out
    }

    static func tab(_ w: ProjectWindow, _ path: String) -> EditorTab? {
        if let t = w.editors[path] ?? w.editors[URL(fileURLWithPath: path).standardizedFileURL.path] { return t }
        return w.editors.first { NPRefs.canon($0.key) == path }?.value
    }

    private static func identify(_ w: ProjectWindow) -> (EditorTab, NPRefIdentity, String)? {
        guard let tab = w.current, NativePHP.handles(tab.url), let root = FastTier.root(for: tab.url) else { return nil }
        let text = tab.textView.string as NSString
        let id = NPRefs.identify(url: tab.url, text: text, offset: tab.textView.selectedRange().location, root: root)
        return (tab, id, root)
    }

    // MARK: Find usages

    /// True when native handled the request (results are delivered asynchronously). False: nothing native to say, use the LSP.
    @discardableResult
    static func findUsages(_ w: ProjectWindow) -> Bool {
        guard let (tab, id, _) = identify(w) else { return false }
        switch id {
        case .none: return false
        case .unsupported(let m):
            LanguageServers.report(m)
            return false
        case .symbol(let sym):
            run(sym, w: w, tab: tab, includeVendor: false)
            return true
        }
    }

    static func run(_ sym: NPRefSymbol, w: ProjectWindow, tab: EditorTab, includeVendor: Bool) {
        cancel()
        var opts = NPRefsOptions()
        opts.includeVendor = includeVendor
        token = NPRefs.collectAsync(sym, options: opts, liveTexts: liveTexts(w), done: { result in
            token = nil
            let resolved = result.resolvedCount
            if resolved == 0 {
                // native found nothing: let a running language server try before giving up
                if sym.kind != .variable, LanguageServers.findUsages(in: tab) { return }
                if result.hits.isEmpty { message("No usages of \(sym.display) found", window: w.window); return }
            }
            present(sym, result: result, root: sym.root, window: w.window, vendorRerun: sym.inVendor && !includeVendor ? { run(sym, w: w, tab: tab, includeVendor: true) } : nil)
        })
    }

    static func icon(_ role: NPRefRole) -> String {
        switch role {
        case .declaration: return "d.circle"
        case .import: return "arrow.down.right.circle"
        case .write: return "pencil"
        case .read: return "eye"
        case .string: return "quote.bubble"
        case .docblock: return "text.alignleft"
        case .unresolved: return "questionmark.circle"
        case .usage: return "arrow.turn.down.right"
        }
    }

    static func rel(_ path: String, _ root: String) -> String { path.hasPrefix(root + "/") ? String(path.dropFirst(root.count + 1)) : path }

    static func items(for hits: [NPRefHit], root: String) -> [PickerItem] {
        hits.map { h in
            let r = rel(h.path, root)
            let tag = h.role == .usage ? "" : "  [\(h.role == .unresolved ? "unknown receiver type" : h.role.rawValue)]"
            let title = h.snippet.isEmpty ? "(blank line)" : h.snippet
            return PickerItem(title: title, detail: "\(r):\(h.line)\(tag)", symbol: icon(h.role), key: title + " " + r) {
                LanguageServers.openLocation?(URL(fileURLWithPath: h.path), h.line, h.column)
            }
        }
    }

    static func present(_ sym: NPRefSymbol, result: NPRefsResult, root: String, window: NSWindow?, vendorRerun: (() -> Void)?) {
        // grouped by file (the scan order), then by position
        var list = items(for: result.hits, root: root)
        let n = result.resolvedCount
        var title = "Usages of \(sym.display) (\(n) in \(Set(result.hits.filter { $0.role != .unresolved }.map(\.path)).count) files)"
        if result.truncated { title += " - capped, narrow the search" }
        let unknown = result.hits.count - n
        if unknown > 0 { title += " + \(unknown) possible" }
        if let rerun = vendorRerun {
            list.insert(PickerItem(title: "Also search vendor/ (slower)", detail: "target is declared in a vendor package", symbol: "shippingbox", key: "vendor also search", run: rerun), at: 0)
        }
        if let h = presentHook { h(title, list); return }
        guard let window else { return }
        QuickPicker.present(over: window, placeholder: title, items: list)
    }

    // MARK: Rename

    enum RenameStart { case handled, notNative, refused(String) }

    /// Shift-F6. `.notNative` = fall back to the LSP; `.refused` = native recognised the symbol but cannot rename it.
    @discardableResult
    static func rename(_ w: ProjectWindow) -> RenameStart {
        guard let (tab, id, _) = identify(w) else { return .notNative }
        switch id {
        case .none: return .notNative
        case .unsupported(let m): return .refused(m)
        case .symbol(let sym):
            beginRename(sym, w: w, tab: tab)
            return .handled
        }
    }

    static func beginRename(_ sym: NPRefSymbol, w: ProjectWindow, tab: EditorTab) {
        let initial = sym.kind == .variable ? sym.name : sym.name
        let go: (String?) -> Void = { name in
            guard let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty, name != initial else { return }
            plan(sym, name: name, w: w, tab: tab)
        }
        if let h = promptHook { h(initial, go); return }
        LSPSession.promptSheet(title: "Rename \(sym.kind.rawValue)", message: "New name for \(sym.display)", initial: initial, button: "Preview", window: w.window, done: go)
    }

    static func plan(_ sym: NPRefSymbol, name: String, w: ProjectWindow, tab: EditorTab) {
        cancel()
        let live = liveTexts(w)
        let t = CancelToken()
        token = t
        DispatchQueue.global(qos: .userInitiated).async {
            let plan = NPRename.plan(sym, newName: name, liveTexts: live, cancel: t)
            DispatchQueue.main.async {
                guard !t.isCancelled else { return }
                token = nil
                if let c = plan.conflict { message("Cannot rename \(sym.name): \(c)", window: w.window); return }
                let proceed: () -> Void = { confirm(plan, w: w, live: live) }
                if sym.inVendor, let warn = plan.warnings.first {
                    if let h = vendorConfirmHook { h(warn) { if $0 { proceed() } }; return }
                    LSPSession.confirmSheet(title: "Rename in vendor code?", message: warn, button: "Continue", window: w.window) { if $0 { proceed() } }
                    return
                }
                proceed()
            }
        }
    }

    static func summary(_ plan: NPRenamePlan) -> String {
        var s = "Rename \(plan.symbol.display) to \(plan.newName): \(plan.editCount) occurrence\(plan.editCount == 1 ? "" : "s") in \(plan.fileCount) file\(plan.fileCount == 1 ? "" : "s")"
        if let f = plan.fileRename { s += ", file renamed to \((f.to as NSString).lastPathComponent)" }
        return s
    }

    static func confirm(_ plan: NPRenamePlan, w: ProjectWindow, live: [String: NSString]) {
        let apply: (Bool) -> Void = { ok in
            guard ok else { return }
            let r = NPRename.apply(plan, liveTexts: live) { tab(w, $0) }
            if let m = r.movedFile { w.handleFileChange(.moved(from: m.from, to: m.to)) }
            if let f = r.failure { message("Rename failed: \(f)", window: w.window); return }
            message("Renamed to \(plan.newName): \(r.edits) occurrence\(r.edits == 1 ? "" : "s") in \(r.files) file\(r.files == 1 ? "" : "s")", window: nil)
        }
        if let h = confirmHook { h(plan, apply); return }
        var rows: [PickerItem] = []
        var detail = plan.warnings.joined(separator: " ")
        if plan.editCount > 0, detail.isEmpty { detail = "Open files can be undone with Undo; other files are saved immediately" }
        rows.append(PickerItem(title: "Apply: " + summary(plan), detail: detail, symbol: "checkmark.circle", key: "apply rename") { apply(true) })
        let root = plan.symbol.root
        for h in plan.hits.sorted(by: { ($0.path, $0.range.location) < ($1.path, $1.range.location) }).prefix(2000) {
            let r = rel(h.path, root)
            rows.append(PickerItem(title: h.snippet.isEmpty ? "(blank line)" : h.snippet, detail: "\(r):\(h.line)  [\(h.role.rawValue)]", symbol: icon(h.role), key: h.snippet + " " + r) {
                LanguageServers.openLocation?(URL(fileURLWithPath: h.path), h.line, h.column)
            })
        }
        for h in plan.skipped.prefix(100) {
            let r = rel(h.path, root)
            rows.append(PickerItem(title: h.snippet, detail: "\(r):\(h.line)  [not changed: unknown receiver type]", symbol: "questionmark.circle", key: h.snippet + " " + r) {
                LanguageServers.openLocation?(URL(fileURLWithPath: h.path), h.line, h.column)
            })
        }
        let title = "Rename preview: " + summary(plan) + " - Enter on the first row applies"
        guard let window = w.window as NSWindow? else { return }
        QuickPicker.present(over: window, placeholder: title, items: rows)
    }
}
