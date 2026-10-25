import AppKit
import SwiftTreeSitter

/// Native JS / TS rename (Shift-F6). Built on the exact find-usages engine: a token is renamed only when it resolves to the declaration;
/// member usages with an unknown receiver type are never touched (the preview counts them). Refused (the caller falls back to a
/// language server when one runs) when the declaration lives in a dependency, when the symbol is a member of a structural type
/// (interface / type alias / object literal: object literals elsewhere may satisfy it), when the new name collides with a declaration,
/// or when a .vue file mentions the old name outside its script (the template cannot be updated natively here).
struct NJSRenamePlan {
    var symbol: NJSRefSymbol
    var newName: String
    var edits: [String: [(range: NSRange, text: String)]] = [:]       // per file, sorted DESCENDING by location
    var preview: [NPRefHit] = []
    var skipped: [NPRefHit] = []
    var warnings: [String] = []
    var conflict: String?
    var snapshots: [String: Int64] = [:]                              // disk stamp of every file planned (closed files are re-checked)
    var editCount: Int { edits.values.reduce(0) { $0 + $1.count } }
    var fileCount: Int { edits.count }
}

enum NJSRename {
    static let reserved: Set<String> = [
        "break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete", "do", "else", "enum", "export", "extends", "false", "finally",
        "for", "function", "if", "import", "in", "instanceof", "new", "null", "return", "super", "switch", "this", "throw", "true", "try", "typeof", "var",
        "void", "while", "with", "yield", "let", "static", "implements", "interface", "package", "private", "protected", "public", "await", "async", "of",
        "undefined", "arguments", "eval",
    ]

    static func validate(_ sym: NJSRefSymbol, name raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return "The new name is empty." }
        guard let f = name.unicodeScalars.first, f == "_" || f == "$" || CharacterSet.letters.contains(f) || (f == "#" && sym.isMember),
              name.unicodeScalars.dropFirst().allSatisfy({ $0 == "_" || $0 == "$" || CharacterSet.alphanumerics.contains($0) })
        else { return "\"\(name)\" is not a valid identifier." }
        if reserved.contains(name) { return "\"\(name)\" is a reserved word." }
        if name == sym.name { return "The new name is the same as the old one." }
        return nil
    }

    /// Why this symbol cannot be renamed natively (nil: it can). `env` belongs to the file the caret is in.
    static func refusal(_ sym: NJSRefSymbol, env: NJSEnv) -> String? {
        if sym.importLocal { return nil }                       // a local import binding: nothing outside this file changes
        for d in sym.decls {
            if d.path.contains("/node_modules/") || d.path.hasSuffix(".d.ts") || !d.path.hasPrefix(sym.root + "/") && !d.local {
                return "\(sym.name) is declared in a dependency (\((d.path as NSString).lastPathComponent)); it cannot be renamed."
            }
        }
        if sym.isMember, let d = sym.decls.first, let owner = d.owner {
            let kind = env.summary(d.path)?.order.first { $0.name == owner && $0.members.contains { $0.loc == d.loc } }?.kind
            if kind != .class && kind != .enum { return "\(sym.name) is a member of a structural type; object literals elsewhere may implement it, so it is not renamed natively." }
        }
        if sym.isMember, sym.decls.contains(where: { $0.owner == nil && !$0.local }) { return "\(sym.name) is a member of an object literal; not renamed natively." }
        return nil
    }

    // MARK: plan

    /// Blocking: scans the project (run off the main thread in the app).
    static func plan(_ sym: NJSRefSymbol, newName raw: String, liveDoc: NJSDoc?, liveTexts: [String: NSString], cancel: CancelToken? = nil) -> NJSRenamePlan {
        let newName = raw.trimmingCharacters(in: .whitespaces)
        var plan = NJSRenamePlan(symbol: sym, newName: newName)
        if let e = validate(sym, name: raw) { plan.conflict = e; return plan }
        let proj = NJSProject.shared(root: sym.root)
        if sym.importLocal, let d = liveDoc { return planImportLocal(sym, newName: newName, doc: d) }
        let result = NJSRefs.collect(sym, liveDoc: liveDoc, liveTexts: liveTexts, cancel: cancel)
        if result.cancelled { plan.conflict = "Cancelled."; return plan }
        if result.truncated { plan.conflict = "Too many occurrences to rename safely."; return plan }
        func text(_ p: String) -> NSString? { liveTexts[p] ?? (liveDoc?.path == p ? liveDoc?.text : nil) ?? FastProject.read(p) }
        var texts: [String: NSString] = [:]
        var byFile: [String: [NPRefHit]] = [:]
        for h in result.hits {
            if h.role == .unresolved { plan.skipped.append(h); continue }
            byFile[h.path, default: []].append(h)
        }
        guard !byFile.isEmpty else { plan.conflict = "No usages of \(sym.name) were found."; return plan }
        for (path, hits) in byFile {
            guard let t = text(path) else { plan.conflict = "Cannot read \((path as NSString).lastPathComponent)."; return plan }
            texts[path] = t
            plan.snapshots[path] = LaravelFS.mtime(path)
            var seen = Set<Int>()
            var edits: [(range: NSRange, text: String)] = []
            for h in hits.sorted(by: { $0.range.location < $1.range.location }) {
                guard NSMaxRange(h.range) <= t.length, t.substring(with: h.range) == sym.name else { continue }       // an alias (`import { a as b }`) keeps its own name
                guard seen.insert(h.range.location).inserted else { continue }
                var repl = newName
                if h.form == .scopeShort { repl = sym.name + ": " + newName }            // `{ a }` -> `{ a: b }`
                else if h.form == .dollar { repl = newName + ": " + sym.name }           // member in a pattern: `{ a }` -> `{ b: a }`
                edits.append((h.range, repl))
                plan.preview.append(h)
            }
            if !edits.isEmpty { plan.edits[path] = edits.sorted { $0.range.location > $1.range.location } }
        }
        guard !plan.edits.isEmpty else { plan.conflict = "Nothing to rename: every occurrence is an alias."; return plan }
        // .vue: the template is invisible to this engine
        for path in plan.edits.keys where path.hasSuffix(".vue") {
            guard let t = texts[path] else { continue }
            let (_, scripts, _) = NJSDoc.maskVue(t)
            var outside = t as String
            let m = NSMutableString(string: outside)
            for r in scripts { m.replaceCharacters(in: r, with: String(repeating: " ", count: r.length)) }
            outside = m as String
            if NJSRefs.hasWord(outside as NSString, sym.name) { plan.conflict = "\((path as NSString).lastPathComponent) mentions \(sym.name) outside its script (template); renaming it there is not supported natively yet."; return plan }
        }
        // collisions
        if sym.isMember {
            if let d = sym.decls.first, let owner = d.owner, let env = envFor(d.path, text: text(d.path), proj: proj, liveDoc: liveDoc) {
                let ownerRes = env.resolveTop(d.path, owner).first(where: { $0.members.contains { $0.loc == d.loc } })
                if let o = ownerRes, o.members.contains(where: { $0.name == newName }) || !env.members(of: o, name: newName, isStatic: false).isEmpty { plan.conflict = "\(owner) already has a member named \(newName)."; return plan }
            }
        } else if sym.isLocal {
            // a binding with the new name visible from any usage in the declaring file would capture or shadow
            if let p = sym.decls.first?.path, let t = texts[p] ?? text(p), let env = envFor(p, text: t, proj: proj, liveDoc: liveDoc) {
                for h in byFile[p] ?? [] {
                    guard let leaf = env.doc.leaf(at: h.range.location) else { continue }
                    if env.localBinding(newName, from: leaf) != nil { plan.conflict = "A variable named \(newName) is already visible where \(sym.name) is used."; return plan }
                }
            }
        } else {
            for path in plan.edits.keys {
                guard let t = texts[path], let env = envFor(path, text: t, proj: proj, liveDoc: liveDoc) else { continue }
                if env.summary(path)?.top[newName] != nil { plan.conflict = "\((path as NSString).lastPathComponent) already declares or imports \(newName)."; return plan }
            }
        }
        if !plan.skipped.isEmpty { plan.warnings.append("\(plan.skipped.count) possible usage\(plan.skipped.count == 1 ? "" : "s") with an unknown receiver type will not be changed.") }
        if result.truncated { plan.warnings.append("The usage list was capped.") }
        return plan
    }

    /// Renaming a use of a default / namespace / aliased import binding: only this file changes (the exporting side keeps its name).
    private static func planImportLocal(_ sym: NJSRefSymbol, newName: String, doc: NJSDoc) -> NJSRenamePlan {
        var plan = NJSRenamePlan(symbol: sym, newName: newName)
        let proj = NJSProject.shared(root: sym.root)
        let env = NJSEnv(proj: proj, doc: doc)
        let text = doc.text
        if doc.summary.top[newName] != nil { plan.conflict = "\((doc.path as NSString).lastPathComponent) already declares or imports \(newName)."; return plan }
        if doc.isVue {
            let (_, scripts, _) = NJSDoc.maskVue(text)
            let outside = NSMutableString(string: text as String)
            for r in scripts { outside.replaceCharacters(in: r, with: String(repeating: " ", count: r.length)) }
            if NJSRefs.hasWord(outside as NSString, sym.name) { plan.conflict = "\((doc.path as NSString).lastPathComponent) mentions \(sym.name) outside its script (template); renaming it there is not supported natively yet."; return plan }
        }
        var edits: [(range: NSRange, text: String)] = []
        let cursor = doc.root.treeCursor
        var finished = false
        let idKinds: Set<String> = ["identifier", "type_identifier", "shorthand_property_identifier", "shorthand_property_identifier_pattern"]
        while !finished {
            if let n = cursor.currentNode, n.isNamed, n.namedChildCount == 0, n.range.length == (sym.name as NSString).length, idKinds.contains(n.kind), n.text(text) == sym.name, doc.inScript(n.start) {
                var skip = false
                if let p = n.parent {
                    if p.kind == "export_specifier", let al = p.field("alias"), al == n { skip = true }                     // `export { x as NAME }`: the exported name
                    if p.kind == "import_specifier", let nm = p.field("name"), nm == n, p.field("alias") != nil { skip = true }  // `import { NAME as y }`: the exporter's name
                }
                if !skip, env.localBinding(sym.name, from: n) == nil {
                    var repl = newName
                    if n.kind.hasPrefix("shorthand") { repl = sym.name + ": " + newName }
                    edits.append((n.range, repl))
                    let (line, col) = NPLineStarts(text).position(of: n.start)
                    plan.preview.append(NPRefHit(path: doc.path, range: n.range, line: line, column: col, snippet: NPText.lineText(text, n.start), role: .usage))
                }
            }
            if cursor.goToFirstChild() { continue }
            while !cursor.gotoNextSibling() { if !cursor.gotoParent() { finished = true; break } }
        }
        guard !edits.isEmpty else { plan.conflict = "No usages found."; return plan }
        plan.edits[doc.path] = edits.sorted { $0.range.location > $1.range.location }
        plan.snapshots[doc.path] = LaravelFS.mtime(doc.path)
        plan.warnings.append("An import binding is local to this file: the exporting module keeps its name.")
        return plan
    }

    private static func envFor(_ path: String, text: NSString?, proj: NJSProject, liveDoc: NJSDoc?) -> NJSEnv? {
        if let d = liveDoc, d.path == path { return NJSEnv(proj: proj, doc: d) }
        guard let t = text, let d = NJSDoc(path: path, text: t) else { return nil }
        return NJSEnv(proj: proj, doc: d)
    }

    // MARK: apply

    struct ApplyResult { var applied = false; var failure: String?; var files = 0; var edits = 0; var written: [URL] = [] }

    static func apply(_ plan: NJSRenamePlan, liveTexts: [String: NSString] = [:], tabFor: (String) -> EditorTab?) -> ApplyResult {
        var res = ApplyResult()
        if let c = plan.conflict { res.failure = c; return res }
        let old = plan.symbol.name
        // 1. re-validate everything before touching anything
        var contents: [String: String] = [:]
        for (path, edits) in plan.edits {
            let base: NSString
            if let tab = tabFor(path) { base = tab.textView.string as NSString }
            else {
                guard LaravelFS.mtime(path) == plan.snapshots[path], let t = FastProject.read(path) else { res.failure = "\((path as NSString).lastPathComponent) changed on disk while the rename was prepared"; return res }
                base = t
            }
            for e in edits {
                guard NSMaxRange(e.range) <= base.length else { res.failure = "\((path as NSString).lastPathComponent) changed while the rename was prepared"; return res }
                let cur = base.substring(with: e.range)
                guard cur == old else { res.failure = "\((path as NSString).lastPathComponent) changed while the rename was prepared"; return res }
            }
            if tabFor(path) == nil {
                let m = NSMutableString(string: base as String)
                for e in edits { m.replaceCharacters(in: e.range, with: e.text) }          // descending: offsets stay valid
                contents[path] = m as String
            }
        }
        // 2. open tabs through the text view (one undo group each), closed files atomically
        for (path, edits) in plan.edits { if let tab = tabFor(path) { LSPEdits.applyToBuffer(tab.textView, edits, actionName: "Rename") } }
        for (path, s) in contents {
            do { try s.write(toFile: path, atomically: true, encoding: .utf8); res.written.append(URL(fileURLWithPath: path)) }
            catch { res.failure = "cannot write \((path as NSString).lastPathComponent): \(error.localizedDescription)"; break }
        }
        if !res.written.isEmpty { LanguageServers.fileEvents(res.written.map { ($0, 2) }) }
        NJSRefs.dropMemos(); NJSRefs.dropFileList()
        NJSProject.shared(root: plan.symbol.root).queue.async { NJSProject.shared(root: plan.symbol.root).trim() }
        res.files = plan.fileCount; res.edits = plan.editCount; res.applied = res.failure == nil
        return res
    }
}

// MARK: UI (Shift-F6)

extension NativeJSUI {
    static var promptHook: ((_ initial: String, _ done: @escaping (String?) -> Void) -> Void)?
    static var confirmHook: ((_ plan: NJSRenamePlan, _ done: @escaping (Bool) -> Void) -> Void)?
    static var messageHook: ((String) -> Void)?
    private static var renameToken: CancelToken?

    enum RenameStart { case handled, notNative, refused(String) }

    private static func message(_ s: String, window: NSWindow?) {
        LanguageServers.report(s)
        if let h = messageHook { h(s); return }
        guard !AppEnv.headless, let window, window.isVisible else { return }
        let a = NSAlert(); a.messageText = s; a.beginSheetModal(for: window)
    }

    /// prepareRename: the symbol under the caret, or why native cannot rename it (nil symbol and no message: not a JS / TS symbol).
    static func prepareRename(tab: EditorTab) -> (symbol: NJSRefSymbol?, doc: NJSDoc?, refusal: String?) {
        guard NativeJS.handles(tab.url) else { return (nil, nil, nil) }
        let text = tab.textView.string as NSString
        let offset = tab.textView.selectedRange().location
        let proj = NJSProject.shared(root: NativeJS.root(for: tab.url))
        var doc: NJSDoc?
        var out: (NJSRefSymbol?, String?) = (nil, nil)
        proj.queue.sync {
            guard let env = NativeJS.env(url: tab.url, text: text, root: proj.root) else { return }
            doc = env.doc
            guard let sym = NJSRefs.identify(env: env, offset: offset) else { return }
            out = (sym, NJSRename.refusal(sym, env: env))
        }
        return (out.0, doc, out.1)
    }

    static func rename(_ w: ProjectWindow) -> RenameStart {
        guard let tab = w.current else { return .notNative }
        let (symOpt, doc, why) = prepareRename(tab: tab)
        guard let sym = symOpt else { return .notNative }
        if let why { return .refused(why) }
        let go: (String?) -> Void = { name in
            guard let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty, name != sym.name else { return }
            planAndConfirm(sym, name: name, doc: doc, w: w)
        }
        if let h = promptHook { h(sym.name, go) } else {
            LSPSession.promptSheet(title: "Rename \(sym.isMember ? "member" : "symbol")", message: "New name for \(sym.name)", initial: sym.name, button: "Preview", window: w.window, done: go)
        }
        return .handled
    }

    private static func planAndConfirm(_ sym: NJSRefSymbol, name: String, doc: NJSDoc?, w: ProjectWindow) {
        renameToken?.cancel()
        let t = CancelToken()
        renameToken = t
        let live = liveTexts(w)
        DispatchQueue.global(qos: .userInitiated).async {
            let plan = NJSRename.plan(sym, newName: name, liveDoc: doc, liveTexts: live, cancel: t)
            DispatchQueue.main.async {
                guard !t.isCancelled else { return }
                renameToken = nil
                if let c = plan.conflict { message("Cannot rename \(sym.name): \(c)", window: w.window); return }
                confirm(plan, w: w, live: live)
            }
        }
    }

    static func hitRows(for hits: [NPRefHit], root: String) -> [PickerItem] {
        hits.map { h in
            let rel = h.path.hasPrefix(root + "/") ? String(h.path.dropFirst(root.count + 1)) : h.path
            let tag = h.role == .usage || h.role == .declaration ? "" : "  [\(h.role == .unresolved ? "unknown receiver type" : h.role.rawValue)]"
            let title = h.snippet.isEmpty ? "(blank line)" : h.snippet
            return PickerItem(title: title, detail: "\(rel):\(h.line)\(tag)", symbol: h.role == .declaration ? "d.circle" : h.role == .import ? "arrow.down.right.circle" : h.role == .unresolved ? "questionmark.circle" : "arrow.turn.down.right", key: title + " " + rel) {
                LanguageServers.openLocation?(URL(fileURLWithPath: h.path), h.line, h.column)
            }
        }
    }

    static func summary(_ p: NJSRenamePlan) -> String {
        "Rename \(p.symbol.name) to \(p.newName): \(p.editCount) occurrence\(p.editCount == 1 ? "" : "s") in \(p.fileCount) file\(p.fileCount == 1 ? "" : "s")"
    }

    private static func confirm(_ plan: NJSRenamePlan, w: ProjectWindow, live: [String: NSString]) {
        let apply: (Bool) -> Void = { ok in
            guard ok else { return }
            let r = NJSRename.apply(plan, liveTexts: live) { path in w.editors[path] ?? w.editors.first { ($0.key as NSString).standardizingPath == path }?.value }
            if let f = r.failure { message("Rename failed: \(f)", window: w.window); return }
            message("Renamed to \(plan.newName): \(r.edits) occurrence\(r.edits == 1 ? "" : "s") in \(r.files) file\(r.files == 1 ? "" : "s")", window: nil)
        }
        if let h = confirmHook { h(plan, apply); return }
        var rows = [PickerItem(title: "Apply: " + summary(plan), detail: plan.warnings.first ?? "Open files can be undone with Undo; other files are saved immediately", symbol: "checkmark.circle", key: "apply rename") { apply(true) }]
        rows += hitRows(for: plan.preview.sorted { ($0.path, $0.range.location) < ($1.path, $1.range.location) }, root: plan.symbol.root)
        for h in plan.skipped.prefix(100) {
            rows.append(PickerItem(title: h.snippet, detail: "\((h.path as NSString).lastPathComponent):\(h.line)  [not changed: unknown receiver type]", symbol: "questionmark.circle", key: h.snippet + " " + h.path) {
                LanguageServers.openLocation?(URL(fileURLWithPath: h.path), h.line, h.column)
            })
        }
        guard let window = w.window as NSWindow? else { return }
        QuickPicker.present(over: window, placeholder: "Rename preview: " + summary(plan) + " - Enter on the first row applies", items: rows)
    }
}
