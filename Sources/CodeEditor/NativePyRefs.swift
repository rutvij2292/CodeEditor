import AppKit
import SwiftTreeSitter

/// Find usages for Python. The symbol under the caret is identified through the same resolver as go to definition (its set of
/// declaration sites is the identity); candidate files are found by a byte search of the name over the project, and each textual
/// occurrence is accepted only when the resolver says it refers to that same declaration. Occurrences that cannot be resolved
/// are not listed (silent beats wrong).
struct PyRefHit {
    enum Role: String { case declaration, write, `import`, usage }
    var path: String
    var offset: Int
    var line: Int
    var column: Int
    var snippet: String
    var role: Role
}

struct PyRefTarget {
    var name: String
    var sites: Set<String>          // "path:offset" of every declaration of the symbol
    var module: String?             // module file path when the target is a module
    var local: Bool                 // function-local: only the declaring file can refer to it
    var display: String
    var path: String                // declaring file
}

struct PyRefsResult { var hits: [PyRefHit]; var truncated: Bool; var scannedFiles: Int; var candidateFiles: Int }

enum PyRefs {
    static let skipDirs: Set<String> = [".git", "node_modules", "__pycache__", "site-packages", ".tox", ".mypy_cache", ".pytest_cache", ".ruff_cache",
                                        ".idea", ".vscode", "htmlcov", ".eggs", "dist", ".nox", ".hg", ".svn", "__pypackages__"]
    static var maxFiles = 8000
    static var maxHits = 2000

    /// Identifies the symbol at `offset` of the live buffer (on the project's queue).
    static func identify(_ r: PyResolver, file: PyFile, root: Node, ns: NSString, offset: Int) -> PyRefTarget? {
        guard let hit = r.lookupHit(file: file, root: root, ns: ns, offset: offset), let t = hit.targets.first else { return nil }
        if hit.kind == "module" {
            let stem = moduleName(t.path)
            return PyRefTarget(name: stem, sites: [], module: t.path, local: false, display: stem, path: t.path)
        }
        guard let tf = r.ctx.file(t.path), let sym = tf.declByOff[t.offset] else { return nil }
        var sites = Set<String>()
        var local = false
        var siblings: [PySym] = [sym]
        if let scope = sym.scope {
            switch sym.kind {
            case .attr: siblings = (scope.attrs[sym.name] ?? []) + (scope.table[sym.name] ?? [])
            case .fn, .cls, .variable, .param: siblings = scope.table[sym.name] ?? [sym]
            case .imp: break
            }
            if scope.kind == .fn || scope.kind == .lambda || scope.kind == .comp { local = true }
        }
        if sym.kind == .attr, let scope = sym.scope { siblings += (scope.attrs[sym.name] ?? []) }
        for s in siblings { sites.insert("\(s.path):\(s.nameOff)") }
        sites.insert("\(sym.path):\(sym.nameOff)")
        var display = sym.name
        if let owner = sym.scope?.owner, sym.scope?.kind == .cls { display = owner.name + "." + sym.name }
        return PyRefTarget(name: sym.name, sites: sites, module: nil, local: local, display: display, path: sym.path)
    }

    static func moduleName(_ path: String) -> String {
        let ns = path as NSString
        let base = (ns.lastPathComponent as NSString).deletingPathExtension
        return base == "__init__" ? (ns.deletingLastPathComponent as NSString).lastPathComponent : base
    }

    // MARK: Candidate files

    static func candidates(root: String, word: String, onlyFile: String?, cancel: CancelToken?) -> (paths: [String], scanned: Int) {
        if let f = onlyFile { return ([f], 1) }
        var out: [String] = []
        var scanned = 0
        let needle = Data(word.utf8)
        let fm = FileManager.default
        guard let en = fm.enumerator(atPath: root) else { return ([], 0) }
        while let rel = en.nextObject() as? String {
            if cancel?.isCancelled == true { break }
            let name = (rel as NSString).lastPathComponent
            let attrs = en.fileAttributes
            if attrs?[.type] as? FileAttributeType == .typeDirectory {
                if name.hasPrefix(".") || skipDirs.contains(name) || name.hasSuffix(".egg-info") || fm.fileExists(atPath: root + "/" + rel + "/pyvenv.cfg") { en.skipDescendants() }
                continue
            }
            guard name.hasSuffix(".py") || name.hasSuffix(".pyi"), !name.hasPrefix("."), (attrs?[.size] as? Int ?? 0) <= 2 << 20 else { continue }
            scanned += 1
            if scanned > maxFiles { break }
            let path = root + "/" + rel
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe), data.range(of: needle) != nil else { continue }
            out.append(path)
        }
        return (out, scanned)
    }

    // MARK: Collect

    /// On the project's queue. `liveText` supplies unsaved buffers (path -> text).
    static func collect(_ target: PyRefTarget, project: PyProject, liveFile: PyFile?, includeDeclarations: Bool = true,
                        cancel: CancelToken? = nil) -> PyRefsResult {
        let ctx = PyCtx(project: project, livePath: liveFile?.path, live: liveFile)
        let r = PyResolver(ctx: ctx)
        let (paths, scanned) = candidates(root: project.root, word: target.name, onlyFile: target.local ? target.path : nil, cancel: cancel)
        var hits: [PyRefHit] = []
        var truncated = false
        var seen = Set<String>()
        for path in paths {
            if cancel?.isCancelled == true { break }
            // an unsaved buffer is searched instead of the file on disk
            let isLive = liveFile?.path == path
            guard let text = isLive ? liveFile!.live : (PyFS.read(path).map { $0 as NSString }) else { continue }
            guard let parser = project.parser, let tree = parser.parse(text as String), let root = tree.rootNode else { continue }
            guard let file = isLive ? liveFile : ctx.file(path) else { continue }
            var words = [target.name]
            var wi = 0
            while wi < words.count {
                let word = words[wi]; wi += 1
                var from = 0
                let n = text.length
                while from < n {
                    let rg = text.range(of: word, options: .literal, range: NSRange(location: from, length: n - from))
                    if rg.location == NSNotFound { break }
                    from = NSMaxRange(rg)
                    if false { fputs("PYDEBUG   occ \(path.suffix(20)) @\(rg.location) ident=\(PyResolver.identifier(in: root, ns: text, at: rg.location).map { "\($0.start)/\($0.r.length)" } ?? "nil")\n", stderr) }
                    if rg.location > 0, isWord(text.character(at: rg.location - 1)) { continue }
                    if from < n, isWord(text.character(at: from)) { continue }
                    guard let ident = PyResolver.identifier(in: root, ns: text, at: rg.location), ident.start == rg.location, ident.r.length == rg.length else { continue }
                    guard let hit = r.lookupHit(file: file, root: root, ns: text, offset: rg.location) else { continue }
                    let matches: Bool
                    if let m = target.module { matches = hit.kind == "module" && hit.targets.contains { $0.path == m } }
                    else { matches = hit.targets.contains { target.sites.contains("\($0.path):\($0.offset)") } }
                    if false { fputs("PYDEBUG   cand \(path.suffix(20)) @\(rg.location) hit=\(hit.targets.map { "\($0.path.suffix(20)):\($0.offset)" }) sites=\(target.sites.map { String($0.suffix(24)) }) match=\(matches)\n", stderr) }
                    if !matches {
                        continue
                    }
                    let key = "\(path):\(rg.location)"
                    guard seen.insert(key).inserted else { continue }
                    let role = roleOf(ident, file: file, target: target)
                    if role == .declaration && !includeDeclarations { continue }
                    // `from m import foo as bar`: `bar` is another name of the same symbol inside this file
                    if let p = ident.parent, let ai = p.type == "aliased_import" ? p : (p.type == "dotted_name" ? p.parent : nil), ai.type == "aliased_import",
                       let al = ai.field("alias"), al.n.id != ident.n.id, !words.contains(al.text) { words.append(al.text) }
                    let p = file.position(of: rg.location)
                    let line = text.lineRange(for: NSRange(location: rg.location, length: 0))
                    var snippet = text.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines)
                    if snippet.count > 160 { snippet = String(snippet.prefix(160)) + "…" }
                    hits.append(PyRefHit(path: path, offset: rg.location, line: p.line, column: p.col, snippet: snippet, role: role))
                    if hits.count >= maxHits { truncated = true; break }
                }
                if truncated { break }
            }
            if truncated { break }
        }
        hits.sort { $0.path == $1.path ? $0.offset < $1.offset : $0.path < $1.path }
        return PyRefsResult(hits: hits, truncated: truncated, scannedFiles: scanned, candidateFiles: paths.count)
    }

    static func isWord(_ c: unichar) -> Bool {
        (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || c == 95 || (c >= 97 && c <= 122) || c > 127
    }

    private static func roleOf(_ ident: PN, file: PyFile, target: PyRefTarget) -> PyRefHit.Role {
        var cur = ident.parent
        var hops = 0
        while let p = cur, hops < 6 {
            if p.type == "import_statement" || p.type == "import_from_statement" { return .import }
            if p.type == "module" || p.type == "block" { break }
            cur = p.parent; hops += 1
        }
        if let s = file.declByOff[ident.start], target.sites.contains("\(s.path):\(s.nameOff)") {
            return s.kind == .variable || s.kind == .attr ? .write : .declaration
        }
        if let p = ident.parent, p.type == "augmented_assignment", let l = p.field("left"), l.n.id == ident.n.id { return .write }
        if let p = ident.parent, p.type == "attribute", let pp = p.parent, pp.type == "augmented_assignment", let l = pp.field("left"), l.n.id == p.n.id { return .write }
        return .usage
    }
}

// MARK: - UI

enum NativePyUI {
    static var presentHook: ((_ title: String, _ items: [PickerItem]) -> Void)?
    static var messageHook: ((String) -> Void)?
    private static var token: CancelToken?
    /// Tests run on the main queue and cannot wait for it: deliver inline.
    static var synchronous = false
    private static func onMain(_ body: @escaping () -> Void) { if synchronous { body() } else { DispatchQueue.main.async(execute: body) } }

    static func message(_ s: String, window: NSWindow?) {
        LanguageServers.report(s)
        if let h = messageHook { h(s); return }
        guard !AppEnv.headless, let window, window.isVisible else { return }
        let a = NSAlert()
        a.messageText = s
        a.beginSheetModal(for: window)
    }

    static func rel(_ path: String, _ root: String) -> String { path.hasPrefix(root + "/") ? String(path.dropFirst(root.count + 1)) : path }

    static func items(_ hits: [PyRefHit], root: String) -> [PickerItem] {
        hits.map { h in
            let tag = h.role == .usage ? "" : "  [\(h.role.rawValue)]"
            let title = h.snippet.isEmpty ? "(blank line)" : h.snippet
            let icon = h.role == .declaration ? "d.circle" : h.role == .import ? "arrow.down.right.circle" : h.role == .write ? "pencil" : "arrow.turn.down.right"
            return PickerItem(title: title, detail: "\(rel(h.path, root)):\(h.line)\(tag)", symbol: icon, key: title + " " + rel(h.path, root)) {
                LanguageServers.openLocation?(URL(fileURLWithPath: h.path), h.line, h.column)
            }
        }
    }

    /// Alt-F7 / click on a declaration. True when the file is Python and the symbol was identified (results arrive asynchronously).
    @discardableResult
    static func findUsages(tab: EditorTab) -> Bool {
        guard NativePy.handles(tab.url) else { return false }
        let text = NSString(string: tab.textView.string)
        let offset = tab.textView.selectedRange().location
        let url = tab.url
        let project = NativePy.project(for: url)
        let window = tab.textView.window
        token?.cancel()
        let tok = CancelToken()
        token = tok
        let work = {
            guard let (ctx, file, tree) = NativePy.prepare(project, url: url, text: text), let root = tree.rootNode else { return }
            let r = PyResolver(ctx: ctx)
            guard let target = PyRefs.identify(r, file: file, root: root, ns: file.live ?? text, offset: offset) else {
                onMain { message("No symbol with known usages at the caret", window: window) }
                return
            }
            let result = PyRefs.collect(target, project: project, liveFile: file, cancel: tok)
            onMain {
                guard !tok.isCancelled else { return }
                token = nil
                if result.hits.isEmpty { message("No usages of \(target.display) found", window: window); return }
                var title = "Usages of \(target.display) (\(result.hits.count) in \(Set(result.hits.map(\.path)).count) files)"
                if result.truncated { title += " - capped, narrow the search" }
                let list = items(result.hits, root: project.root)
                if let h = presentHook { h(title, list); return }
                guard let window else { return }
                QuickPicker.present(over: window, placeholder: title, items: list)
            }
        }
        if synchronous { project.queue.sync(execute: work) } else { project.queue.async(execute: work) }
        return true
    }
}
