import AppKit
import SwiftTreeSitter

/// Python completion: members after `.` (types from the resolver; silent when the receiver type is unknown), names in scope,
/// `import` / `from ... import` module and name lists. Registered as one more CompletionProvider (merged with the word provider).
final class NativePyCompletionProvider: CompletionProvider {
    let triggerCharacters = ["."]
    private var token = 0

    func complete(_ context: CompletionContext, deliver: @escaping ([CompletionItem], Bool) -> Void) {
        token += 1
        let mine = token
        guard NativePy.handles(context.fileURL) else { deliver([], false); return }
        let project = NativePy.project(for: context.fileURL)
        project.queue.async { [weak self] in
            guard let self, self.token == mine else { return }
            let items = PyComplete.items(project: project, url: context.fileURL, text: context.text as NSString, caret: context.caret, prefixRange: context.prefixRange)
            guard self.token == mine else { return }
            deliver(items, false)
        }
    }

    func cancel() { token += 1 }
}

enum PyComplete {
    static let keywords = ["False", "None", "True", "and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del", "elif", "else",
                           "except", "finally", "for", "from", "global", "if", "import", "in", "is", "lambda", "nonlocal", "not", "or", "pass", "raise",
                           "return", "try", "while", "with", "yield", "match", "case"]
    static let builtinFunctions = ["abs", "aiter", "all", "anext", "any", "ascii", "bin", "breakpoint", "callable", "chr", "compile", "delattr", "dir",
                                   "divmod", "eval", "exec", "format", "getattr", "globals", "hasattr", "hash", "help", "hex", "id", "input", "isinstance",
                                   "issubclass", "iter", "len", "locals", "max", "min", "next", "oct", "open", "ord", "pow", "print", "repr", "round",
                                   "setattr", "sorted", "sum", "vars", "__import__"]
    static let builtinClasses = ["bool", "bytearray", "bytes", "classmethod", "complex", "dict", "enumerate", "filter", "float", "frozenset", "int", "list",
                                 "map", "memoryview", "object", "property", "range", "reversed", "set", "slice", "staticmethod", "str", "super", "tuple",
                                 "type", "zip", "BaseException", "Exception", "ArithmeticError", "AssertionError", "AttributeError", "EOFError",
                                 "ImportError", "IndexError", "KeyError", "KeyboardInterrupt", "LookupError", "MemoryError", "ModuleNotFoundError",
                                 "NameError", "NotImplementedError", "OSError", "OverflowError", "RuntimeError", "StopIteration", "SyntaxError",
                                 "SystemExit", "TypeError", "ValueError", "ZeroDivisionError", "FileNotFoundError", "PermissionError", "TimeoutError"]

    static func isWord(_ c: unichar) -> Bool { PyRefs.isWord(c) }

    static func items(project: PyProject, url: URL, text: NSString, caret: Int, prefixRange: NSRange) -> [CompletionItem] {
        guard caret <= text.length else { return [] }
        let prefix = prefixRange.length > 0 && NSMaxRange(prefixRange) <= text.length ? text.substring(with: prefixRange) : ""
        let lineRange = text.lineRange(for: NSRange(location: caret, length: 0))
        let before = text.substring(with: NSRange(location: lineRange.location, length: caret - lineRange.location))
        if let items = importItems(project: project, url: url, before: before, prefix: prefix) { return items }
        let prefixStart = prefixRange.location == NSNotFound ? caret : prefixRange.location
        if prefixStart > 0, text.character(at: prefixStart - 1) == 46 /* . */ {
            return memberItems(project: project, url: url, text: text, dot: prefixStart - 1, caret: caret, prefix: prefix)
        }
        return nameItems(project: project, url: url, text: text, caret: caret, prefix: prefix)
    }

    // MARK: Inside a string / comment

    private static func inStringOrComment(_ tree: MutableTree, _ ns: NSString, _ caret: Int) -> Bool {
        guard let root = tree.rootNode else { return false }
        for off in [caret - 1, caret] where off >= 0 && off < ns.length {
            var n = root.descendant(in: UInt32(off * 2)..<UInt32(off * 2 + 2))
            while let c = n {
                let t = c.nodeType ?? ""
                if t == "comment" { return caret > c.range.location }
                if t == "interpolation" { return false }                       // an f-string replacement field is code again
                if t == "string" {
                    let r = c.range
                    let terminated = c.childCount >= 2 && c.child(at: c.childCount - 1)?.nodeType == "string_end"
                    return caret > r.location && (terminated ? caret < NSMaxRange(r) : caret <= NSMaxRange(r))
                }
                n = c.parent
            }
        }
        return false
    }

    /// Scope of the caret: the innermost scope of the last code before it, left again when the caret line is indented no deeper
    /// than the `def` / `class` line (the body ended).
    static func completionScope(_ file: PyFile, _ ns: NSString, _ caret: Int) -> PyScope {
        var p = min(caret, ns.length) - 1
        while p > 0, [32, 9, 10, 13].contains(ns.character(at: p)) { p -= 1 }
        var scope = file.root.innermost(at: max(0, p))
        let line = ns.lineRange(for: NSRange(location: min(caret, max(0, ns.length - 1)), length: 0))
        var ci = 0
        while line.location + ci < ns.length, ns.character(at: line.location + ci) == 32 || ns.character(at: line.location + ci) == 9 { ci += 1 }
        let atBlank = line.location + ci >= caret            // nothing but indentation before the caret
        let lineIndent = atBlank ? caret - line.location : ci
        while (scope.kind == .fn || scope.kind == .cls), let owner = scope.owner {
            let dl = ns.lineRange(for: NSRange(location: min(owner.nameOff, max(0, ns.length - 1)), length: 0))
            var di = 0
            while dl.location + di < ns.length, ns.character(at: dl.location + di) == 32 || ns.character(at: dl.location + di) == 9 { di += 1 }
            if lineIndent > di || (caret <= scope.end && !atBlank && caret > scope.start) { break }
            guard let parent = scope.parent else { break }
            scope = parent
        }
        return scope
    }

    // MARK: Member completion

    private static func memberItems(project: PyProject, url: URL, text: NSString, dot: Int, caret: Int, prefix: String) -> [CompletionItem] {
        var end = caret
        while end < text.length, isWord(text.character(at: end)) { end += 1 }
        let patched = text.replacingCharacters(in: NSRange(location: dot, length: end - dot), with: "")
        let ns = NSString(string: patched)
        guard let parser = project.parser, let tree = parser.parse(patched), let root = tree.rootNode else { return [] }
        let file = PyOutlineBuilder(path: url.standardizedFileURL.path, ns: ns, root: root).file
        file.live = ns
        let ctx = PyCtx(project: project, livePath: file.path, live: file)
        let r = PyResolver(ctx: ctx)
        guard dot > 0, var node = root.descendant(in: UInt32((dot - 1) * 2)..<UInt32(dot * 2)) else { return [] }
        // grow to the whole receiver expression ending at the dot
        let growable: Set<String> = ["attribute", "call", "subscript", "parenthesized_expression", "argument_list", "await"]
        while let p = node.parent, NSMaxRange(p.range) == dot, growable.contains(p.nodeType ?? "") { node = p }
        let t = node.nodeType ?? ""
        guard ["identifier", "attribute", "call", "subscript", "parenthesized_expression", "await"].contains(t) else { return [] }
        let scope = file.root.innermost(at: max(0, dot - 1))
        let recv = r.eval(PyExprMaker.make(PN(n: node, ns: ns)), scope: scope, file: file)
        if recv.isUnknown { return [] }
        var out: [CompletionItem] = []
        var seen = Set<String>()
        let enclosing = r.enclosingClass(scope)
        collectMembers(recv, r, file: file, enclosing: enclosing, prefix: prefix, into: &out, seen: &seen)
        return out
    }

    private static func collectMembers(_ recv: PyType, _ r: PyResolver, file: PyFile, enclosing: PySym?, prefix: String,
                                       into out: inout [CompletionItem], seen: inout Set<String>) {
        switch recv {
        case .inst(let c), .cls(let c), .sup(let c):
            var skipFirst = false
            if case .sup = recv { skipFirst = true }
            for (i, cls) in r.mro(c).enumerated() {
                if skipFirst && i == 0 { continue }
                guard let inner = cls.inner else { continue }
                let own = enclosing != nil && cls === enclosing
                let syms = inner.order + inner.attrOrder
                for s in syms where shouldOffer(s.name, prefix: prefix, own: own) && seen.insert(s.name).inserted {
                    if s.kind == .param { continue }
                    out.append(item(for: s, rank: i, r))
                }
            }
        case .module(let loc):
            guard case .file(let p) = loc, let f = r.ctx.file(p) else {
                if case .dir(let d) = loc { addSubmodules(dir: d, prefix: prefix, into: &out, seen: &seen) }
                return
            }
            for s in f.root.order where shouldOffer(s.name, prefix: prefix, own: false) && seen.insert(s.name).inserted {
                if s.kind == .imp, !(f.isInit || (f.root.dunderAll?.contains(s.name) ?? false)) { seen.remove(s.name); continue }
                out.append(item(for: s, rank: 0, r))
            }
            if f.isInit { addSubmodules(dir: (p as NSString).deletingLastPathComponent, prefix: prefix, into: &out, seen: &seen) }
        case .union(let l):
            for t in l { collectMembers(t, r, file: file, enclosing: enclosing, prefix: prefix, into: &out, seen: &seen) }
        default: break
        }
    }

    private static func shouldOffer(_ name: String, prefix: String, own: Bool) -> Bool {
        if name.hasPrefix("__") && name.hasSuffix("__") { return prefix.hasPrefix("__") }
        if name.hasPrefix("_") { return own || prefix.hasPrefix("_") }
        return true
    }

    private static func addSubmodules(dir: String, prefix: String, into out: inout [CompletionItem], seen: inout Set<String>) {
        for e in PyFS.list(dir) {
            var name = e
            if e.hasSuffix(".py") || e.hasSuffix(".pyi") { name = (e as NSString).deletingPathExtension }
            else if PyFS.isDir(dir + "/" + e), PyFS.isFile(dir + "/" + e + "/__init__.py") || PyFS.isFile(dir + "/" + e + "/__init__.pyi") {}
            else { continue }
            guard name != "__init__", !name.hasPrefix("."), name.first?.isNumber == false, shouldOffer(name, prefix: prefix, own: false), seen.insert(name).inserted else { continue }
            out.append(CompletionItem(label: name, insertText: name, kind: .module, detail: "module", sortText: "5" + name))
        }
    }

    private static func item(for s: PySym, rank: Int, _ r: PyResolver) -> CompletionItem {
        var kind: CompletionKind
        var detail = ""
        switch s.kind {
        case .cls: kind = .class; detail = "class"
        case .fn:
            kind = s.isProperty ? .property : (s.scope?.kind == .cls ? .method : .function)
            if let h = s.header, let paren = h.firstIndex(of: "(") { detail = String(h[paren...]) }
        case .variable: kind = PyDocs.isConstantName(s.name) ? .constant : .variable
        case .attr: kind = .field
        case .param: kind = .variable
        case .imp: kind = s.impName == nil ? .module : .value; detail = "import"
        }
        let sortPrefix = s.name.hasPrefix("_") ? "9" : String(min(rank, 8))
        var it = CompletionItem(label: s.name, insertText: s.name, kind: kind, detail: detail, sortText: sortPrefix + s.name)
        if s.docRange != nil, let f = r.ctx.file(s.path) {
            let range = s.docRange
            it.resolve = { done in
                var copy = it
                copy.documentation = PyDocs.docstring(range, in: f) ?? ""
                done(copy)
            }
        }
        return it
    }

    // MARK: Names

    private static func nameItems(project: PyProject, url: URL, text: NSString, caret: Int, prefix: String) -> [CompletionItem] {
        guard !prefix.isEmpty || true, let (ctx, file, tree) = NativePy.prepare(project, url: url, text: text) else { return [] }
        if inStringOrComment(tree, text, caret) { return [] }
        let r = PyResolver(ctx: ctx)
        var out: [CompletionItem] = []
        var seen = Set<String>()
        var scope: PyScope? = completionScope(file, text, caret)
        let start = scope
        var depth = 0
        while let sc = scope {
            if sc.kind != .cls || sc === start {
                for s in sc.order where seen.insert(s.name).inserted {
                    if s.nameOff >= caret - prefix.utf16.count && s.nameOff <= caret && s.kind != .param { continue }     // the word being typed
                    out.append(item(for: s, rank: depth, r))
                }
            }
            depth += 1
            scope = sc.parent
        }
        // names pulled in by `from m import *`
        for st in file.root.stars {
            guard let loc = ctx.resolveModule(st.module, level: st.level, from: file.path), case .file(let p) = loc, let g = ctx.file(p) else { continue }
            let all = g.root.dunderAll
            for s in g.root.order where seen.insert(s.name).inserted {
                if let all { if !all.contains(s.name) { seen.remove(s.name); continue } } else if s.name.hasPrefix("_") { seen.remove(s.name); continue }
                out.append(item(for: s, rank: 5, r))
            }
        }
        for n in builtinClasses where seen.insert(n).inserted { out.append(CompletionItem(label: n, insertText: n, kind: .class, detail: "builtin", sortText: "7" + n)) }
        for n in builtinFunctions where seen.insert(n).inserted { out.append(CompletionItem(label: n, insertText: n, kind: .function, detail: "builtin", sortText: "7" + n)) }
        if !prefix.isEmpty { for n in keywords where seen.insert(n).inserted { out.append(CompletionItem(label: n, insertText: n, kind: .keyword, sortText: "8" + n)) } }
        return out
    }

    // MARK: import / from ... import

    private static func importItems(project: PyProject, url: URL, before: String, prefix: String) -> [CompletionItem]? {
        let t = String(before.drop(while: { $0 == " " || $0 == "\t" }))
        // `from pkg.mod import a, b|`
        if let re = NPRe.make(pattern: #"^from\s+(\.*)([\w.]*)\s+import\s+(?:\(?[\w\s,]*)$"#), let m = re.firstMatch(in: t, range: NSRange(location: 0, length: (t as NSString).length)) {
            let ns = t as NSString
            let level = ns.substring(with: m.range(at: 1)).count
            let module = ns.substring(with: m.range(at: 2))
            let ctx = PyCtx(project: project)
            let r = PyResolver(ctx: ctx)
            guard let loc = ctx.resolveModule(module, level: level, from: url.standardizedFileURL.path) else { return [] }
            var out: [CompletionItem] = []
            var seen = Set<String>()
            if case .file(let p) = loc, let f = ctx.file(p) {
                for s in f.root.order where shouldOffer(s.name, prefix: prefix, own: false) && seen.insert(s.name).inserted { out.append(item(for: s, rank: 0, r)) }
                if f.isInit { addSubmodules(dir: (p as NSString).deletingLastPathComponent, prefix: prefix, into: &out, seen: &seen) }
            } else if case .dir(let d) = loc { addSubmodules(dir: d, prefix: prefix, into: &out, seen: &seen) }
            return out
        }
        // `import a.b|`, `from a.b|`
        if let re = NPRe.make(pattern: #"^(?:import|from)\s+(?:[\w.\s,]*,\s*)?(\.*)([\w]+\.)*[\w]*$"#), re.firstMatch(in: t, range: NSRange(location: 0, length: (t as NSString).length)) != nil,
           t.hasPrefix("import ") || t.hasPrefix("from ") {
            let word = t.split(whereSeparator: { $0 == " " || $0 == "," }).last.map(String.init) ?? ""
            let level = word.prefix(while: { $0 == "." }).count
            var path = String(word.dropFirst(level))
            if let dot = path.lastIndex(of: ".") { path = String(path[..<dot]) } else { path = "" }
            let ctx = PyCtx(project: project)
            let file = url.standardizedFileURL.path
            var out: [CompletionItem] = []
            var seen = Set<String>()
            if path.isEmpty && level == 0 {
                for root in ctx.roots(for: file) { addSubmodules(dir: root, prefix: prefix, into: &out, seen: &seen) }
            } else if level > 0 && path.isEmpty {
                var base = (file as NSString).deletingLastPathComponent
                for _ in 1..<level { base = (base as NSString).deletingLastPathComponent }
                addSubmodules(dir: base, prefix: prefix, into: &out, seen: &seen)
            } else if let loc = ctx.resolveModule(path, level: level, from: file) {
                switch loc {
                case .file(let p): addSubmodules(dir: (p as NSString).deletingLastPathComponent, prefix: prefix, into: &out, seen: &seen)
                case .dir(let d): addSubmodules(dir: d, prefix: prefix, into: &out, seen: &seen)
                }
            }
            return out
        }
        return nil
    }
}
