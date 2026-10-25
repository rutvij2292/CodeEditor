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

    private static let listLock = NSLock()
    private static var listCache: (root: String, at: Date, files: [String], truncated: Bool)?
    static func dropFileList() { listLock.lock(); listCache = nil; listLock.unlock() }

    /// The project's source files; the listing is reused for 3 seconds (a second search right after the first costs no directory walk).
    static func files(_ root: String, cancel: CancelToken?, truncated: inout Bool) -> [String] {
        listLock.lock()
        if let c = listCache, c.root == root, Date().timeIntervalSince(c.at) < 3 { listLock.unlock(); truncated = c.truncated; return c.files }
        listLock.unlock()
        let out = walk(root, cancel: cancel, truncated: &truncated)
        if cancel?.isCancelled != true { listLock.lock(); listCache = (root, Date(), out, truncated); listLock.unlock() }
        return out
    }

    private static func walk(_ root: String, cancel: CancelToken?, truncated: inout Bool) -> [String] {
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

    @inline(__always) private static func identChar(_ c: unichar) -> Bool { (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 36 || c > 127 }

    static func hasWord(_ t: NSString, _ w: String) -> Bool {
        let n = t.length, wl = (w as NSString).length
        var from = 0
        while from < n {
            let r = t.range(of: w, options: .literal, range: NSRange(location: from, length: n - from))
            if r.location == NSNotFound { return false }
            let before = r.location > 0 && identChar(t.character(at: r.location - 1))
            let after = NSMaxRange(r) < n && identChar(t.character(at: NSMaxRange(r)))
            if !before && !after { return true }
            from = r.location + max(1, wl)
        }
        return false
    }

    private final class Memo {
        let key: String, digest: Int, live: NSString?, result: NPRefsResult
        init(key: String, digest: Int, live: NSString?, result: NPRefsResult) { self.key = key; self.digest = digest; self.live = live; self.result = result }
    }
    private static var memos: [Memo] = []
    private static let memoLock = NSLock()
    static var tList: UInt64 = 0, tGraph: UInt64 = 0, tParse: UInt64 = 0, tWalk: UInt64 = 0, tFound: UInt64 = 0      // diagnostics (bench)
    static func dropMemos() { memoLock.lock(); memos.removeAll(); memoLock.unlock() }

    static func collect(_ sym: NJSRefSymbol, liveDoc: NJSDoc?, liveTexts: [String: NSString], cancel: CancelToken? = nil) -> NPRefsResult {
        var result = NPRefsResult()
        let proj = NJSProject.shared(root: sym.root)
        let declKeys = Set(sym.decls.map { "\($0.path):\($0.loc)" })
        let declFiles = Array(Set(sym.decls.map(\.path)))
        var paths: [String]
        var viaBinding = Set<String>()
        var digest = 0
        let memoKey = declKeys.sorted().joined(separator: "|") + (sym.isMember ? "|m" : "")
        if sym.isLocal, let d = liveDoc { paths = [d.path] }
        else {
            var trunc = false
            let tList = NPStats.now()
            paths = files(sym.root, cancel: cancel, truncated: &trunc)
            NJSRefs.tList &+= NPStats.now() &- tList
            if trunc { result.truncated = true }
            for d in sym.decls where !paths.contains(d.path) { paths.append(d.path) }      // declarations inside node_modules / .d.ts files
            for p in liveTexts.keys where !paths.contains(p) && NJSModules.codeExts.contains((p as NSString).pathExtension.lowercased()) { paths.append(p) }
            // a repeated search over unchanged files and buffers is answered from the memo
            var h = Hasher()
            for p in paths { h.combine(p); h.combine(LaravelFS.mtime(p)) }
            for (p, t) in liveTexts { h.combine(p); h.combine(t.length); h.combine(t.hash) }
            digest = h.finalize()
            memoLock.lock()
            if let m = memos.first(where: { $0.key == memoKey && $0.digest == digest && (($0.live == nil && liveDoc == nil) || ($0.live != nil && liveDoc != nil && $0.live!.isEqual(liveDoc!.text))) }) {
                memoLock.unlock(); return m.result
            }
            memoLock.unlock()
            // import graph: only files that can reach the declaring module (ambient .d.ts globals are visible everywhere)
            let ambient = declFiles.contains { proj.summary(path: $0).map { !$0.isModule && !$0.commonJS } ?? false }
            if !ambient {
                var live = liveTexts
                if let d = liveDoc { live[d.path] = d.text }
                let tGraph = NPStats.now()
                defer { NJSRefs.tGraph &+= NPStats.now() &- tGraph }
                let cand = proj.graph.candidates(declFiles: declFiles, members: sym.isMember, files: paths, live: live, modules: proj.modules, stateKey: digest)
                viaBinding = cand.viaBinding
                paths = paths.filter { cand.files.contains($0) || declFiles.contains($0) }
            }
        }
        let shared = NJSMemo()

        struct FileResult { var hits: [NPRefHit] = []; var candidate = false; var parsed = false }

        /// One file: text filter, parse, walk. Pure with respect to everything but the thread safe caches, so files run in parallel.
        func scanOne(_ p: String) -> FileResult {
            var out = FileResult()
            guard let text = liveTexts[p] ?? FastProject.read(p) else { return out }
            guard hasWord(text, sym.name) || viaBinding.contains(p) || declFiles.contains(p) else { return out }
            out.candidate = true
            let doc: NJSDoc
            let tParse = NPStats.now()
            if let d = liveDoc, d.path == p { doc = d } else if let d = NJSDoc(path: p, text: text, maxChars: 1_500_000, skipMinified: true) { doc = d } else { return out }
            NJSRefs.tParse &+= NPStats.now() &- tParse
            out.parsed = true
            defer { withExtendedLifetime(doc) {} }          // nodes must not outlive the tree's arena
            let env = NJSEnv(proj: proj, doc: doc)
            env.memo = shared
            var names: Set<String> = [sym.name]
            if !sym.isMember && !sym.isLocal {
                for s in doc.summary.order where s.kind == .import && s.name != sym.name {
                    env.steps = 0
                    if env.followImport(s, from: p, depth: 0).contains(where: { declKeys.contains("\($0.path):\($0.loc)") }) { names.insert(s.name) }
                }
            }
            let lens = Set(names.map { ($0 as NSString).length })
            let tWalk = NPStats.now()
            defer { NJSRefs.tWalk &+= NPStats.now() &- tWalk }
            var tableStore: NPLineStarts?
            func tbl() -> NPLineStarts { if let t = tableStore { return t }; let t = NPLineStarts(text); tableStore = t; return t }
            var unresolved = 0
            func consider(_ n: Node) {
                guard n.isNamed, n.namedChildCount == 0, lens.contains(n.range.length) else { return }      // only leaves of a candidate's length are worth a string
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
                                let (line, col) = tbl().position(of: n.start)
                                out.hits.append(NPRefHit(path: p, range: n.range, line: line, column: col, snippet: NPText.lineText(text, n.start), role: .unresolved))
                            }
                        }
                        if matched {
                            let (line, col) = tbl().position(of: n.start)
                            out.hits.append(NPRefHit(path: p, range: n.range, line: line, column: col, snippet: NPText.lineText(text, n.start), role: role(of: n, isDecl: isDecl)))
                        }
                    }
                }
            }
            let cursor = doc.root.treeCursor           // allocation free walk (no child arrays)
            var finished = false
            while !finished {
                if let n = cursor.currentNode { consider(n) }
                if cursor.goToFirstChild() { continue }
                while !cursor.gotoNextSibling() { if !cursor.gotoParent() { finished = true; break } }
            }
            out.hits.sort { $0.range.location < $1.range.location }
            return out
        }

        // Files are independent: scan them in chunks on all cores (utility QoS, transient), then merge in path order.
        let chunkSize = max(1, paths.count / (ProcessInfo.processInfo.activeProcessorCount * 4))
        let chunkCount = (paths.count + chunkSize - 1) / chunkSize
        let slots = NJSSlots<[FileResult]>(chunkCount)
        let resolvedSoFar = NJSCounter()
        let list = paths
        let work: (Int) -> Void = { c in
            if cancel?.isCancelled == true || resolvedSoFar.value >= maxHits { return }           // a prefix of the chunks already fills the list
            var mine: [FileResult] = []
            for p in list[(c * chunkSize)..<min(list.count, (c + 1) * chunkSize)] {
                if cancel?.isCancelled == true { break }
                let r = scanOne(p)
                resolvedSoFar.add(r.hits.reduce(0) { $0 + ($1.role == .unresolved ? 0 : 1) })
                mine.append(r)
            }
            slots.set(c, mine)
        }
        if chunkCount > 1 && list.count > 12 { DispatchQueue.concurrentPerform(iterations: chunkCount, execute: work) } else { for c in 0..<chunkCount { work(c) } }
        if cancel?.isCancelled == true { result.cancelled = true }
        var scanned = 0
        var capped = false
        var unresolvedTotal = 0
        for chunk in slots.values {
            for r in chunk ?? [] {
                if r.candidate { result.candidates += 1 }
                if r.parsed { scanned += 1 }
                if capped { continue }
                for h in r.hits {
                    if h.role == .unresolved { if unresolvedTotal < maxUnresolved { unresolvedTotal += 1; result.hits.append(h) } }
                    else if result.hits.filter({ $0.role != .unresolved }).count < maxHits { result.hits.append(h) } else { result.truncated = true; capped = true }
                }
            }
        }
        result.filesScanned = scanned
        if !sym.isLocal, !result.cancelled {
            memoLock.lock()
            memos.append(Memo(key: memoKey, digest: digest, live: liveDoc?.text, result: result))
            if memos.count > 6 { memos.removeFirst() }
            memoLock.unlock()
        }
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


/// Tiny thread safe helpers for the parallel scan.
final class NJSSlots<T> {
    private let lock = NSLock()
    private var items: [T?]
    init(_ n: Int) { items = [T?](repeating: nil, count: n) }
    func set(_ i: Int, _ v: T) { lock.lock(); items[i] = v; lock.unlock() }
    var values: [T?] { lock.lock(); defer { lock.unlock() }; return items }
}

final class NJSCounter {
    private let lock = NSLock()
    private var n = 0
    func add(_ k: Int) { lock.lock(); n += k; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}
