import AppKit
import SwiftTreeSitter

/// Find usages for the native JS / TS service. A usage is only reported when the token resolves (through the same scope /
/// import / member rules as go to definition) to the very declaration being searched, so results are exact. Member accesses on
/// receivers whose type is unknown are listed separately as "possible". Files are read one at a time (text filter first, parse only
/// the candidates) and nothing but the capped summary cache survives the search.
struct NJSRefSymbol {
    var name: String
    var decls: [NJSRes]
    var isMember: Bool
    var root: String
    var declFile: String
    var display: String { name }
    var isLocal: Bool { decls.contains { $0.local } }
}

enum NJSRefs {
    static let maxHits = 1000
    static let maxUnresolved = 100
    static let maxFiles = 8000
    static let skipDirs: Set<String> = ["node_modules", ".git", "dist", "build", "out", ".next", ".nuxt", ".output", "coverage", "vendor", "storage", ".cache", "target", ".svelte-kit", ".turbo", "bower_components", ".yarn", "tmp"]

    private static func isIdent(_ k: String) -> Bool {
        k == "identifier" || k == "type_identifier" || k == "property_identifier" || k == "private_property_identifier" || k == "shorthand_property_identifier"
    }

    // MARK: identify

    static func identify(env: NJSEnv, offset: Int) -> NJSRefSymbol? {
        guard env.doc.inScript(offset), var node = env.doc.leaf(at: offset) else { return nil }
        if !isIdent(node.kind), offset > 0, let p = env.doc.leaf(at: offset - 1), isIdent(p.kind), p.end == offset { node = p }
        guard isIdent(node.kind) || node.kind == "shorthand_property_identifier_pattern" else { return nil }
        let name = node.text(env.doc.text)
        var decls: [NJSRes] = []
        var isMember = false
        if node.kind == "property_identifier" || node.kind == "private_property_identifier" {
            isMember = true
            if let p = node.parent, p.kind == "member_expression", let pr = p.field("property"), pr == node { decls = env.resolveToken(node) }
            else {
                for s in env.doc.summary.order {
                    if let m = s.members.first(where: { $0.loc == node.start }) { decls = [NJSRes(path: env.path, member: m, owner: s.name, siblings: s.members)]; break }
                }
            }
        } else if node.kind == "shorthand_property_identifier_pattern" {
            if let b = env.localBinding(name, from: node) { decls = [env.resolve(b)] }
        } else {
            decls = env.resolveToken(node)
        }
        decls = decls.filter { !$0.fileTop && $0.name != "default" }
        guard !decls.isEmpty else { return nil }
        return NJSRefSymbol(name: decls[0].name, decls: decls, isMember: isMember || decls[0].owner != nil, root: env.proj.root, declFile: decls[0].path)
    }

    // MARK: collect

    static func files(_ root: String, cancel: CancelToken?, truncated: inout Bool) -> [String] {
        var out: [String] = []
        let fm = FileManager.default
        guard let en = fm.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        for case let u as URL in en {
            if cancel?.isCancelled == true { break }
            let n = u.lastPathComponent
            if skipDirs.contains(n) { en.skipDescendants(); continue }
            guard NJSModules.codeExts.contains(u.pathExtension.lowercased()) else { continue }
            out.append((u.path as NSString).standardizingPath)
            if out.count >= maxFiles { truncated = true; break }
        }
        out.sort()
        return out
    }

    private static func role(of node: Node, isDecl: Bool) -> NPRefRole {
        if isDecl { return .declaration }
        var p = node.parent
        for _ in 0..<4 {
            guard let c = p else { break }
            switch c.kind {
            case "import_specifier", "import_clause", "namespace_import", "export_specifier": return .import
            case "assignment_expression": if let l = c.field("left"), l.start <= node.start, l.end >= node.end { return .write }
            default: break
            }
            p = c.parent
        }
        return .usage
    }

    static func collect(_ sym: NJSRefSymbol, liveDoc: NJSDoc?, liveTexts: [String: NSString], cancel: CancelToken? = nil) -> NPRefsResult {
        var result = NPRefsResult()
        let proj = NJSProject.shared(root: sym.root)
        let declKeys = Set(sym.decls.map { "\($0.path):\($0.loc)" })
        var paths: [String]
        if sym.isLocal, let d = liveDoc { paths = [d.path] }
        else {
            var trunc = false
            paths = files(sym.root, cancel: cancel, truncated: &trunc)
            if trunc { result.truncated = true }
            for d in sym.decls where !paths.contains(d.path) { paths.append(d.path) }      // declarations inside node_modules / .d.ts files
            for p in liveTexts.keys where !paths.contains(p) && NJSModules.codeExts.contains((p as NSString).pathExtension.lowercased()) { paths.append(p) }
        }
        // names that can appear in text: the symbol itself and, for default / require exports, the declaring file's stem
        var stems: [String] = []
        if !sym.isMember, !sym.isLocal {
            let base = ((sym.declFile as NSString).lastPathComponent as NSString).deletingPathExtension
            stems.append(base == "index" ? ((sym.declFile as NSString).deletingLastPathComponent as NSString).lastPathComponent : base)
        }
        var unresolved = 0
        var scanned = 0
        for p in paths {
            if cancel?.isCancelled == true { result.cancelled = true; break }
            guard let text = liveTexts[p] ?? FastProject.read(p) else { continue }
            let hasName = text.range(of: sym.name).location != NSNotFound
            let hasStem = !hasName && stems.contains { !$0.isEmpty && text.range(of: $0).location != NSNotFound }
            guard hasName || hasStem else { continue }
            result.candidates += 1
            let doc: NJSDoc
            if let d = liveDoc, d.path == p { doc = d } else if let d = NJSDoc(path: p, text: text) { doc = d } else { continue }
            scanned += 1
            let env = NJSEnv(proj: proj, doc: doc)
            var names: Set<String> = [sym.name]
            if !sym.isMember && !sym.isLocal {
                for s in doc.summary.order where s.kind == .import && s.name != sym.name {
                    env.steps = 0
                    if env.followImport(s, from: p, depth: 0).contains(where: { declKeys.contains("\($0.path):\($0.loc)") }) { names.insert(s.name) }
                }
            }
            let table = NPLineStarts(text)
            var stack: [Node] = [doc.root]
            var fileHits: [NPRefHit] = []
            while let n = stack.popLast() {
                let k = n.kind
                if isIdent(k) || k == "shorthand_property_identifier_pattern" {
                    let nm = n.text(text)
                    if names.contains(nm), doc.inScript(n.start) {
                        env.steps = 0
                        var matched = false, isDecl = false
                        if p == sym.declFile || p == doc.path, declKeys.contains("\(p):\(n.start)") { matched = true; isDecl = true }
                        if !matched {
                            let res: [NJSRes]
                            if k == "shorthand_property_identifier_pattern" { res = env.localBinding(nm, from: n).map { [env.resolve($0)] } ?? [] }
                            else { res = env.resolveToken(n) }
                            matched = res.contains { declKeys.contains("\($0.path):\($0.loc)") }
                            if !matched, sym.isMember, res.isEmpty, k == "property_identifier", let par = n.parent, par.kind == "member_expression",
                               let pr = par.field("property"), pr == n, let o = par.field("object"), env.typeOf(o) == nil, unresolved < maxUnresolved {
                                unresolved += 1
                                let (line, col) = table.position(of: n.start)
                                fileHits.append(NPRefHit(path: p, range: n.range, line: line, column: col, snippet: NPText.lineText(text, n.start), role: .unresolved))
                            }
                        }
                        if matched {
                            let (line, col) = table.position(of: n.start)
                            fileHits.append(NPRefHit(path: p, range: n.range, line: line, column: col, snippet: NPText.lineText(text, n.start), role: role(of: n, isDecl: isDecl)))
                        }
                    }
                }
                if n.namedChildCount > 0 { stack.append(contentsOf: n.kids.reversed()) }
            }
            fileHits.sort { $0.range.location < $1.range.location }
            for h in fileHits {
                if h.role == .unresolved { result.hits.append(h) }
                else if result.hits.filter({ $0.role != .unresolved }).count < maxHits { result.hits.append(h) } else { result.truncated = true }
            }
        }
        result.filesScanned = scanned
        // resolved hits first (file order kept), possible usages last
        result.hits = result.hits.filter { $0.role != .unresolved } + result.hits.filter { $0.role == .unresolved }
        return result
    }
}

private let refsQueue = DispatchQueue(label: "nativejs.refs", qos: .utility)

enum NativeJSUI {
    static var presentHook: ((_ title: String, _ items: [PickerItem]) -> Void)?
    private static var token: CancelToken?

    static func cancel() { token?.cancel(); token = nil }

    static func liveTexts(_ w: ProjectWindow) -> [String: NSString] {
        var out: [String: NSString] = [:]
        for (path, tab) in w.editors where tab.isDirty && NativeJS.extensions.contains((path as NSString).pathExtension.lowercased()) {
            out[(path as NSString).standardizingPath] = tab.textView.string as NSString
        }
        return out
    }

    /// True when native took the request (results arrive asynchronously). False: use the language server.
    @discardableResult
    static func findUsages(_ w: ProjectWindow) -> Bool {
        guard let tab = w.current, NativeJS.handles(tab.url) else { return false }
        let text = tab.textView.string as NSString
        let offset = tab.textView.selectedRange().location
        let proj = NJSProject.shared(root: NativeJS.root(for: tab.url))
        var doc: NJSDoc?
        let sym: NJSRefSymbol? = proj.queue.sync {
            guard let env = NativeJS.env(url: tab.url, text: text, root: proj.root) else { return nil }
            doc = env.doc
            return NJSRefs.identify(env: env, offset: offset)
        }
        guard let sym else { return false }
        cancel()
        let t = CancelToken()
        token = t
        let live = liveTexts(w)
        let window = w.window
        refsQueue.async {
            let result = NJSRefs.collect(sym, liveDoc: doc, liveTexts: live, cancel: t)
            DispatchQueue.main.async {
                guard !t.isCancelled else { return }
                token = nil
                let usages = result.hits.filter { $0.role != .unresolved && $0.role != .declaration }
                if usages.isEmpty, LanguageServers.findUsages(in: tab) { return }       // native found nothing beyond the declaration
                present(sym, result: result, window: window)
            }
        }
        return true
    }

    static func present(_ sym: NJSRefSymbol, result: NPRefsResult, window: NSWindow?) {
        let list = NativePHPUI.items(for: result.hits, root: sym.root)
        let n = result.resolvedCount
        var title = "Usages of \(sym.display) (\(n) in \(Set(result.hits.filter { $0.role != .unresolved }.map(\.path)).count) files)"
        if result.truncated { title += " - capped, narrow the search" }
        let unknown = result.hits.count - n
        if unknown > 0 { title += " + \(unknown) possible" }
        if let h = presentHook { h(title, list); return }
        guard let window else { return }
        QuickPicker.present(over: window, placeholder: title, items: list)
    }
}
