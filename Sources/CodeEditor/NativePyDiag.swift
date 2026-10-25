import Foundation
import SwiftTreeSitter

enum PyDiagGroup: String, CaseIterable {
    case syntax, imports, names, unused

    var key: String { "py.diag." + rawValue }
    var title: String {
        switch self {
        case .syntax: return "Syntax errors"
        case .imports: return "Unresolved imports"
        case .names: return "Undefined names"
        case .unused: return "Unused imports (dimmed)"
        }
    }
    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: key) }
    }
    static var enabledSet: Set<PyDiagGroup> { Set(allCases.filter { $0.enabled }) }
    static func resetPrefs() { for g in allCases { UserDefaults.standard.removeObject(forKey: g.key) } }
}

/// Conservative Python diagnostics. Every rule stays silent unless the finding is certain:
///  - syntax: tree-sitter ERROR / MISSING nodes (one per line, capped); when present nothing else is reported;
///  - imports: relative imports of files that do not exist, `from <project module> import name` where the module defines no such
///    name, and absolute imports whose top-level package exists nowhere (needs a discovered venv, outside try / except);
///  - names: an identifier that is bound nowhere in the file (any scope), is no builtin, in a file without `import *` / exec;
///  - unused imports (hint): the imported name does not occur anywhere else in the file text.
enum PyDiag {
    static let maxBytes = 800_000
    static let maxResults = 120

    static let builtinNames: Set<String> = Set((
        "ArithmeticError AssertionError AttributeError BaseException BaseExceptionGroup BlockingIOError BrokenPipeError BufferError BytesWarning ChildProcessError ConnectionAbortedError ConnectionError ConnectionRefusedError ConnectionResetError DeprecationWarning EOFError Ellipsis EncodingWarning EnvironmentError Exception ExceptionGroup False FileExistsError FileNotFoundError FloatingPointError FutureWarning GeneratorExit IOError ImportError ImportWarning IndentationError IndexError InterruptedError IsADirectoryError KeyError KeyboardInterrupt LookupError MemoryError ModuleNotFoundError NameError None NotADirectoryError NotImplemented NotImplementedError OSError OverflowError PendingDeprecationWarning PermissionError ProcessLookupError RecursionError ReferenceError ResourceWarning RuntimeError RuntimeWarning StopAsyncIteration StopIteration SyntaxError SyntaxWarning SystemError SystemExit TabError TimeoutError True TypeError UnboundLocalError UnicodeDecodeError UnicodeEncodeError UnicodeError UnicodeTranslateError UnicodeWarning UserWarning ValueError Warning ZeroDivisionError PythonFinalizationError WindowsError __build_class__ __debug__ __import__ abs aiter all anext any ascii bin bool breakpoint bytearray bytes callable chr classmethod compile complex copyright credits delattr dict dir divmod enumerate eval exec exit filter float format frozenset getattr globals hasattr hash help hex id input int isinstance issubclass iter len license list locals map max memoryview min next object oct open ord pow print property quit range repr reversed round set setattr slice sorted staticmethod str sum super tuple type vars zip " +
        "__name__ __file__ __doc__ __package__ __spec__ __loader__ __path__ __builtins__ __annotations__ __class__ __qualname__ __module__ __dict__ __all__ __cached__ __slots__ reveal_type reveal_locals _"
    ).split(separator: " ").map(String.init))

    static let builtinModules: Set<String> = ["_abc", "_ast", "_codecs", "_collections", "_functools", "_imp", "_io", "_locale", "_operator", "_signal", "_sre", "_stat",
                                              "_string", "_symtable", "_thread", "_tokenize", "_tracemalloc", "_typing", "_warnings", "_weakref", "atexit", "builtins",
                                              "errno", "faulthandler", "gc", "itertools", "marshal", "posix", "pwd", "sys", "time", "__main__", "__future__"]

    static func handles(_ url: URL) -> Bool { NativePy.handles(url) }

    /// On the project's queue.
    static func analyze(project: PyProject, url: URL, text: NSString, groups: Set<PyDiagGroup>) -> [NPDiag] {
        guard !groups.isEmpty, let (ctx, file, tree) = NativePy.prepare(project, url: url, text: text), let root = tree.rootNode else { return [] }
        let ns = file.live ?? text
        if root.hasError {
            return groups.contains(.syntax) ? syntaxErrors(root, ns) : []
        }
        if ns.length > maxBytes { return [] }
        var out: [NPDiag] = []
        let resolver = PyResolver(ctx: ctx)
        var walker = PyDiagWalker(file: file, ns: ns, groups: groups, ctx: ctx, resolver: resolver)
        walker.run(root)
        out = walker.out
        if groups.contains(.unused), !(file.isInit || file.isStub) { out += unusedImports(file: file, ns: ns, resolver: resolver) }
        out.sort { $0.range.location < $1.range.location }
        return Array(out.prefix(maxResults))
    }

    // MARK: Syntax

    static func syntaxErrors(_ root: Node, _ ns: NSString) -> [NPDiag] {
        var found: [NPDiag] = []
        func collect(_ n: Node, _ depth: Int) {
            guard (n.hasError || n.isMissing), depth < 300, found.count < 40 else { return }
            if n.isMissing {
                let type = n.nodeType ?? "token"
                var loc = min(n.range.location, ns.length)
                var k = loc
                while k > 0, loc - k < 400, [32, 9, 10, 13].contains(ns.character(at: k - 1)) { k -= 1 }
                if k > 0 { loc = k - 1 }
                found.append(NPDiag(range: NSRange(location: min(loc, max(0, ns.length - 1)), length: ns.length > 0 ? 1 : 0), severity: 1, message: "Syntax error: expected \(type)", code: "syntax", group: .syntax))
                return
            }
            if n.nodeType == "ERROR" {
                // an ERROR node that only wraps already-reported inner problems is skipped by recursing first
                var inner = 0
                let before = found.count
                for i in 0..<n.childCount { if let c = n.child(at: i) { collect(c, depth + 1); inner = found.count - before } }
                if inner > 0 { return }
                let r = n.range
                let line = ns.lineRange(for: NSRange(location: min(r.location, max(0, ns.length - 1)), length: 0))
                let end = min(NSMaxRange(r), NSMaxRange(line))
                let len = max(1, min(end - r.location, 40))
                found.append(NPDiag(range: NSRange(location: r.location, length: min(len, max(1, ns.length - r.location))), severity: 1, message: "Syntax error", code: "syntax", group: .syntax))
                return
            }
            for i in 0..<n.childCount { if let c = n.child(at: i) { collect(c, depth + 1) } }
        }
        collect(root, 0)
        found.sort { $0.range.location < $1.range.location }
        var out: [NPDiag] = []
        var lastLine = -1
        for d in found {
            let ls = ns.lineRange(for: NSRange(location: min(d.range.location, max(0, ns.length - 1)), length: 0)).location
            if ls == lastLine { continue }
            out.append(d); lastLine = ls
            if out.count >= 5 { break }
        }
        return out
    }

    // MARK: Unused imports

    private static func unusedImports(file: PyFile, ns: NSString, resolver: PyResolver) -> [NPDiag] {
        var syms: [PySym] = []
        func gather(_ s: PyScope) {
            for sym in s.order where sym.kind == .imp { syms.append(sym) }
            for c in s.children { gather(c) }
        }
        gather(file.root)
        guard !syms.isEmpty, syms.count < 400 else { return [] }
        var out: [NPDiag] = []
        for s in syms {
            let len = (s.name as NSString).length
            guard let lineText = Optional(ns.substring(with: ns.lineRange(for: NSRange(location: s.nameOff, length: 0)))), !lineText.contains("noqa") else { continue }
            var used = false
            var from = 0
            while from < ns.length {
                let r = ns.range(of: s.name, options: .literal, range: NSRange(location: from, length: ns.length - from))
                if r.location == NSNotFound { break }
                from = NSMaxRange(r)
                if r.location >= s.declStart && r.location < s.declEnd { continue }       // inside its own import statement
                if r.location > 0, PyRefs.isWord(ns.character(at: r.location - 1)) { continue }
                if from < ns.length, PyRefs.isWord(ns.character(at: from)) { continue }
                used = true; break
            }
            if !used { out.append(NPDiag(range: NSRange(location: s.nameOff, length: len), severity: 4, message: "Unused import '\(s.name)'", code: "unused-import", group: .imports)) }
        }
        return out
    }
}

/// One walk over the syntax tree for the import and name rules.
struct PyDiagWalker {
    let file: PyFile
    let ns: NSString
    let groups: Set<PyDiagGroup>
    let ctx: PyCtx
    let resolver: PyResolver
    var out: [NPDiag] = []
    private var bound: Set<String> = []
    private var checkNames = false
    private var futureAnnotations = false
    private var guardedDepth = 0

    init(file: PyFile, ns: NSString, groups: Set<PyDiagGroup>, ctx: PyCtx, resolver: PyResolver) {
        self.file = file; self.ns = ns; self.groups = groups; self.ctx = ctx; self.resolver = resolver
    }

    mutating func run(_ root: Node) {
        // names rule preconditions: no star imports, no exec / locals() tricks
        var hasStar = false, dynamic = false
        func scan(_ s: PyScope) {
            for (k, _) in s.table { bound.insert(k) }
            if !s.stars.isEmpty { hasStar = true }
            if s.usesLocals { dynamic = true }
            for c in s.children { scan(c) }
        }
        scan(file.root)
        let text = ns as String
        if text.contains("exec(") || text.contains("__builtins__") || text.contains("setattr(") { dynamic = true }
        checkNames = groups.contains(.names) && !hasStar && !dynamic
        futureAnnotations = text.contains("from __future__ import annotations")
        walk(PN(n: root, ns: ns), 0)
    }

    private mutating func report(_ n: PN, _ sev: Int, _ msg: String, _ code: String, _ group: NPDiagGroup) {
        guard out.count < PyDiag.maxResults else { return }
        out.append(NPDiag(range: n.r, severity: sev, message: msg, code: code, group: group))
    }

    private mutating func walkTarget(_ n: PN, _ depth: Int) {
        switch n.type {
        case "identifier": return
        case "attribute": if let o = n.field("object") { walk(o, depth + 1) }
        case "subscript": for c in n.named { walk(c, depth + 1) }
        case "pattern_list", "tuple_pattern", "list_pattern", "tuple", "list", "list_splat_pattern", "list_splat", "parenthesized_expression", "as_pattern_target":
            for c in n.named { walkTarget(c, depth + 1) }
        default: walk(n, depth + 1)
        }
    }

    private mutating func walkParams(_ p: PN?, _ depth: Int) {
        guard let p else { return }
        for c in p.named {
            switch c.type {
            case "typed_parameter": if let t = c.field("type") { walk(t, depth + 1) }
            case "default_parameter": if let v = c.field("value") { walk(v, depth + 1) }
            case "typed_default_parameter":
                if let t = c.field("type") { walk(t, depth + 1) }
                if let v = c.field("value") { walk(v, depth + 1) }
            default: break
            }
        }
    }

    private mutating func walk(_ n: PN, _ depth: Int) {
        if depth > 220 || n.namedCount == 0 && n.type != "identifier" { return }
        switch n.type {
        case "identifier":
            let name = n.text
            if checkNames, !bound.contains(name), !PyDiag.builtinNames.contains(name) {
                report(n, 2, "Undefined name '\(name)'", "undefined-name", .variables)
            }
            return
        case "attribute": if let o = n.field("object") { walk(o, depth + 1) }; return
        case "keyword_argument": if let v = n.field("value") { walk(v, depth + 1) }; return
        case "function_definition":
            walkParams(n.field("parameters"), depth)
            if let r = n.field("return_type") { walk(r, depth + 1) }
            if let b = n.field("body") { walk(b, depth + 1) }
            return
        case "lambda":
            walkParams(n.field("parameters"), depth)
            if let b = n.field("body") { walk(b, depth + 1) }
            return
        case "class_definition":
            if let s = n.field("superclasses") { walk(s, depth + 1) }
            if let b = n.field("body") { walk(b, depth + 1) }
            return
        case "assignment":
            if let l = n.field("left") { walkTarget(l, depth) }
            if let t = n.field("type") { walk(t, depth + 1) }
            if let r = n.field("right") { walk(r, depth + 1) }
            return
        case "for_statement":
            if let l = n.field("left") { walkTarget(l, depth) }
            for c in n.named where c.n.id != n.field("left")?.n.id { walk(c, depth + 1) }
            return
        case "for_in_clause":
            if let l = n.field("left") { walkTarget(l, depth) }
            if let r = n.field("right") { walk(r, depth + 1) }
            return
        case "named_expression": if let v = n.field("value") { walk(v, depth + 1) }; return
        case "with_item", "except_clause":
            for c in n.named {
                if c.type == "as_pattern" {
                    for k in c.named where k.type != "as_pattern_target" { walk(k, depth + 1) }
                    if let a = c.field("alias") { walkTarget(a, depth) }
                } else { walk(c, depth + 1) }
            }
            return
        case "global_statement", "nonlocal_statement", "dotted_name", "type_parameter", "splat_pattern", "keyword_pattern", "wildcard_import": return
        case "as_pattern":
            let kids = n.named
            let aliasID = n.field("alias")?.n.id ?? (kids.count >= 2 && kids.last?.type == "identifier" ? kids.last?.n.id : nil)
            for c in kids where c.n.id != aliasID { walk(c, depth + 1) }
            return
        case "type_alias_statement": if let r = n.field("right") { walk(r, depth + 1) }; return
        case "import_statement": checkImport(n); return
        case "import_from_statement": checkFromImport(n); return
        case "try_statement":
            let hasHandler = n.named.contains { $0.type == "except_clause" || $0.type == "except_group_clause" }
            for c in n.named {
                if c.type == "block", hasHandler, c.n.id == n.field("body")?.n.id { guardedDepth += 1; walk(c, depth + 1); guardedDepth -= 1 }
                else { walk(c, depth + 1) }
            }
            return
        case "string": return
        case "type": if futureAnnotations { return }          // annotations are never evaluated: names there are not certain errors
        default: break
        }
        for c in n.named { walk(c, depth + 1) }
    }

    // MARK: Imports

    private static let topLevelCache = NSLock()

    private mutating func checkImport(_ n: PN) {
        guard groups.contains(.imports), guardedDepth == 0 else { return }
        for c in n.named {
            let dotted: PN? = c.type == "dotted_name" ? c : (c.type == "aliased_import" ? c.field("name") : nil)
            guard let d = dotted else { continue }
            let name = d.text
            if resolveAbsolute(name) == .missing { report(d, 2, "Import '\(name)' could not be resolved", "unresolved-import", .imports) }
        }
    }

    private mutating func checkFromImport(_ n: PN) {
        guard groups.contains(.imports), guardedDepth == 0, let mn = n.field("module_name") else { return }
        let (module, level) = resolver.fromModule(n)
        if level == 0 {
            if resolveAbsolute(module) == .missing { report(mn, 2, "Import '\(module)' could not be resolved", "unresolved-import", .imports); return }
        } else if ctx.resolveModule(module, level: level, from: file.path) == nil {
            report(mn, 1, "Cannot resolve relative import '\(String(repeating: ".", count: level))\(module)'", "unresolved-import", .imports)
            return
        }
        guard let loc = ctx.resolveModule(module, level: level, from: file.path), case .file(let p) = loc, ctx.isProjectLocal(p), let mf = ctx.file(p) else { return }
        // names that must exist in a project module
        if mf.root.usesLocals || mf.root.table["__getattr__"] != nil { return }
        for c in n.named where c.n.id != mn.n.id {
            var nm: PN?
            if c.type == "dotted_name", c.namedCount == 1 { nm = c.named(at: 0) }
            else if c.type == "aliased_import" { nm = c.field("name")?.named.first }
            guard let id = nm else { continue }
            let name = id.text
            let r = resolver.nameInModule(mf, name, visited: [])
            if case .none = r {
                if ctx.submodule(of: loc, named: name) != nil { continue }
                if hasUnresolvableStar(mf) { continue }
                report(id, 2, "'\(name)' is not defined in module '\(String(repeating: ".", count: level))\(module)'", "unresolved-from-import", .imports)
            }
        }
    }

    private func hasUnresolvableStar(_ f: PyFile) -> Bool {
        for st in f.root.stars where ctx.resolveModule(st.module, level: st.level, from: f.path) == nil { return true }
        return false
    }

    enum Resolved { case found, missing, unknown }

    private func resolveAbsolute(_ name: String) -> Resolved {
        guard !name.isEmpty else { return .unknown }
        let comps = name.split(separator: ".").map(String.init)
        let top = comps[0]
        if PyDiag.builtinModules.contains(top) { return .found }
        if ctx.resolveModule(name, level: 0, from: file.path) != nil { return .found }
        // The top-level package: a venv must have been discovered, otherwise the environment is a guess.
        guard let top1 = ctx.resolveModule(top, level: 0, from: file.path) else {
            guard ctx.env.venv != nil, ctx.env.known else { return .unknown }
            if ctx.projectHasModule(top) || ctx.extensionModuleExists(top, from: file.path) { return .found }
            return .missing
        }
        // top-level found: a missing submodule is only certain for project-local packages
        if comps.count > 1, case .file(let p) = top1, ctx.isProjectLocal(p) {
            if (p as NSString).lastPathComponent.hasPrefix("__init__"), let f = ctx.file(p), f.root.table["__path__"] == nil, f.root.table["__getattr__"] == nil,
               !f.root.usesLocals { return .missing }
            return .unknown
        }
        return .found
    }
}
