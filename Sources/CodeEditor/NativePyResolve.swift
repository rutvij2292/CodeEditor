import Foundation

/// Static type of an expression, as far as the native engine can tell without running anything. `.unknown` is the safe answer:
/// every feature stays silent on it.
indirect enum PyType {
    case inst(PySym)                 // instance of a class
    case cls(PySym)                  // the class object
    case module(PyCtx.Loc)
    case fn(PySym)
    case sup(PySym)                  // super() inside this class
    case union([PyType])
    case gen(String, [PyType])       // list[Foo], dict[str, Foo] ...
    case unknown

    var isUnknown: Bool { if case .unknown = self { return true }; return false }
}

/// Name lookup (LEGB), import following, class hierarchy and expression typing. One resolver per request.
final class PyResolver {
    let ctx: PyCtx
    private var depth = 0
    private var visiting: Set<ObjectIdentifier> = []
    private var mroMemo: [ObjectIdentifier: [PySym]] = [:]

    init(ctx: PyCtx) { self.ctx = ctx }

    enum Imp { case module(PyCtx.Loc), syms([PySym]), none }

    private static let transparentDecorators: Set<String> = [
        "staticmethod", "classmethod", "property", "cached_property", "abstractmethod", "override", "final", "overload", "cache",
        "lru_cache", "abstractproperty", "abc.abstractmethod", "typing.override", "typing.final", "functools.cache", "functools.lru_cache",
        "functools.cached_property", "typing_extensions.override", "classproperty", "setter", "getter", "deleter",
    ]

    // MARK: Name lookup

    /// Bindings of `name` visible at `off` in `scope` (innermost scope first, class scopes skipped for nested scopes).
    func lookup(_ name: String, scope: PyScope, off: Int, file: PyFile) -> [PySym] {
        var s: PyScope? = scope
        while let c = s {
            if c.kind == .cls && c !== scope { s = c.parent; continue }
            if c.nonlocals.contains(name) { s = c.parent; continue }
            if c.globals.contains(name), let l = file.root.table[name] { return choose(l, c, scope, off) }
            if let l = c.table[name] { return choose(l, c, scope, off) }
            s = c.parent
        }
        if case .syms(let l) = starLookup(file, name, visited: []) { return l }
        return []
    }

    private func choose(_ list: [PySym], _ owner: PyScope, _ usage: PyScope, _ off: Int) -> [PySym] {
        if list.count == 1 { return list }
        if list.allSatisfy({ $0.isDefLike }) { return Array(list.prefix(4)) }
        var l = list
        // `try: import x` / `except ImportError: x = None`: the None placeholder is not the interesting binding
        let real = l.filter { !($0.kind == .variable && $0.annotation == nil && isNoneLiteral($0.value)) }
        if !real.isEmpty { l = real }
        if owner === usage, let prev = l.last(where: { $0.nameOff < off }) { return [prev] }
        if owner === usage { return [l[0]] }
        if let d = l.first(where: { $0.isDefLike || $0.kind == .imp }) { return [d] }
        return [l.last!]
    }

    private func isNoneLiteral(_ e: PyExpr?) -> Bool { if case .lit("None")? = e { return true }; return false }

    private func starLookup(_ file: PyFile, _ name: String, visited: Set<String>) -> Imp {
        guard !file.root.stars.isEmpty, visited.count < 6 else { return .none }
        var seen = visited; seen.insert(file.path)
        for st in file.root.stars {
            guard let loc = ctx.resolveModule(st.module, level: st.level, from: file.path), case .file(let p) = loc, !seen.contains(p), let g = ctx.file(p) else { continue }
            if let all = g.root.dunderAll { if !all.contains(name) { continue } } else if name.hasPrefix("_") { continue }
            let r = nameInModule(g, name, visited: seen)
            if case .none = r { continue }
            return r
        }
        return .none
    }

    // MARK: Imports

    func resolveImport(_ s: PySym) -> Imp {
        guard depth < 24 else { return .none }
        depth += 1; defer { depth -= 1 }
        guard let loc = ctx.resolveModule(s.impModule, level: s.impLevel, from: s.path) else { return .none }
        guard let name = s.impName else { return .module(loc) }
        if case .file(let p) = loc, let f = ctx.file(p) {
            let r = nameInModule(f, name, visited: [])
            if case .none = r {} else { return r }
        }
        if let sub = ctx.submodule(of: loc, named: name) { return .module(sub) }
        return .none
    }

    func nameInModule(_ f: PyFile, _ name: String, visited: Set<String>) -> Imp {
        if let l = f.root.table[name] {
            let picked = choose(l, f.root, PyScope(kind: .lambda, start: 0, end: 0, parent: nil), Int.max)
            guard let s = picked.first else { return .none }
            if s.kind == .imp {
                let r = resolveImport(s)
                return r
            }
            return .syms(picked)
        }
        return starLookup(f, name, visited: visited)
    }

    func memberOfModule(_ loc: PyCtx.Loc, _ name: String) -> Imp {
        if case .file(let p) = loc, let f = ctx.file(p) {
            let r = nameInModule(f, name, visited: [])
            if case .none = r {} else { return r }
        }
        if let sub = ctx.submodule(of: loc, named: name) { return .module(sub) }
        return .none
    }

    // MARK: Classes

    func baseClasses(_ cls: PySym) -> [PySym] {
        guard let scope = cls.scope, let file = ctx.file(cls.path) else { return [] }
        var out: [PySym] = []
        for b in cls.bases {
            var e = b
            if case .sub(let base, _) = e { e = base }
            if case .cls(let c) = eval(e, scope: scope, file: file), c !== cls { out.append(c) }
        }
        return out
    }

    func mro(_ cls: PySym) -> [PySym] {
        let id = ObjectIdentifier(cls)
        if let m = mroMemo[id] { return m }
        var out: [PySym] = []
        var seen = Set<ObjectIdentifier>()
        func visit(_ c: PySym, _ d: Int) {
            guard d < 12, out.count < 40, seen.insert(ObjectIdentifier(c)).inserted else { return }
            out.append(c)
            for b in baseClasses(c) { visit(b, d + 1) }
        }
        visit(cls, 0)
        mroMemo[id] = out
        return out
    }

    func classMember(_ c: PySym, _ name: String) -> PySym? {
        guard let inner = c.inner else { return nil }
        if let l = inner.table[name] {
            if let f = l.first, f.kind == .fn { return f }
            let real = l.filter { !($0.kind == .variable && $0.annotation == nil && isNoneLiteral($0.value)) }
            return (real.isEmpty ? l : real).last
        }
        if let l = inner.attrs[name] { return l.first(where: { $0.annotation != nil }) ?? l.first }
        return nil
    }

    func memberSyms(_ cls: PySym, _ name: String, skipSelf: Bool = false) -> [PySym] {
        for (i, c) in mro(cls).enumerated() {
            if skipSelf && i == 0 { continue }
            if let s = classMember(c, name) { return [s] }
        }
        return []
    }

    /// The class whose body (through methods) contains `scope`.
    func enclosingClass(_ scope: PyScope) -> PySym? {
        var s: PyScope? = scope
        while let c = s {
            if c.kind == .cls { return c.owner }
            s = c.parent
        }
        return nil
    }

    // MARK: Typing

    private func enter(_ s: PySym) -> Bool {
        guard depth < 30 else { return false }
        return visiting.insert(ObjectIdentifier(s)).inserted
    }

    func typeOf(_ s: PySym) -> PyType {
        guard enter(s) else { return .unknown }
        depth += 1
        defer { depth -= 1; visiting.remove(ObjectIdentifier(s)) }
        switch s.kind {
        case .cls: return .cls(s)
        case .fn: return .fn(s)
        case .imp:
            switch resolveImport(s) {
            case .module(let l): return .module(l)
            case .syms(let l): return l.first.map { typeOf($0) } ?? .unknown
            case .none: return .unknown
            }
        case .param: return paramType(s)
        case .variable, .attr:
            guard let scope = s.scope, let file = ctx.file(s.path) else { return .unknown }
            if let a = s.annotation {
                let t = annType(a, scope: scope, file: file)
                if !t.isUnknown { return t }
            }
            if let v = s.value { return eval(v, scope: scope, file: file) }
            return .unknown
        }
    }

    private func paramType(_ s: PySym) -> PyType {
        guard let inner = s.scope, let file = ctx.file(s.path), let fn = inner.owner, let outer = fn.scope else {
            return .unknown
        }
        if s.paramIndex == 0, outer.kind == .cls, let cls = outer.owner, !fn.isStatic, inner.kind == .fn {
            let implicitClassMethods: Set<String> = ["__new__", "__init_subclass__", "__class_getitem__"]
            if let p = fn.params.first, p.star == 0 {
                if fn.isClassMethod || implicitClassMethods.contains(fn.name) { return .cls(cls) }
                return .inst(cls)
            }
        }
        if s.paramIndex >= 0, s.paramIndex < fn.params.count {
            let p = fn.params[s.paramIndex]
            if p.star != 0 { return .unknown }
            if let a = p.annotation { return annType(a, scope: outer, file: file) }
        }
        return .unknown
    }

    /// Annotation expression -> the type of a value that satisfies it.
    func annType(_ e: PyExpr, scope: PyScope, file: PyFile) -> PyType {
        guard depth < 30 else { return .unknown }
        depth += 1; defer { depth -= 1 }
        switch e {
        case .name(let n, let off):
            if n == "Self" || n == "Self_" { if let c = enclosingClass(scope) { return .inst(c) } }
            let syms = lookup(n, scope: scope, off: Int.max, file: file)
            guard let s = syms.first else { return builtinGeneric(n, []) }
            if s.kind == .variable, s.annotation == nil, let v = s.value, enter(s) {      // type alias:  Alias = Optional[Foo]
                defer { visiting.remove(ObjectIdentifier(s)) }
                switch v { case .sub, .union, .name, .attr: return annType(v, scope: s.scope ?? scope, file: ctx.file(s.path) ?? file); default: break }
            }
            _ = off
            if case .cls(let c) = typeOf(s) { return .inst(c) }
            return .unknown
        case .attr:
            if case .cls(let c) = eval(e, scope: scope, file: file) { return .inst(c) }
            return .unknown
        case .str(let text): return stringAnnotation(text, scope: scope, file: file)
        case .sub(let base, let idx):
            let baseName: String
            switch base { case .name(let n, _): baseName = n; case .attr(_, let n, _): baseName = n; default: return .unknown }
            switch baseName {
            case "Optional", "Annotated", "ClassVar", "Final", "Required", "NotRequired", "ReadOnly", "InitVar", "Awaitable_":
                return idx.first.map { annType($0, scope: scope, file: file) } ?? .unknown
            case "Union": return unionOf(idx.map { annType($0, scope: scope, file: file) })
            case "Type", "type":
                if let f = idx.first, case .inst(let c) = annType(f, scope: scope, file: file) { return .cls(c) }
                return .unknown
            default:
                if case .cls(let c) = eval(base, scope: scope, file: file) { return .inst(c) }     // user generic class
                return builtinGeneric(baseName, idx.map { annType($0, scope: scope, file: file) })
            }
        case .union(let list): return unionOf(list.map { annType($0, scope: scope, file: file) })
        default: return .unknown
        }
    }

    private static let containers: Set<String> = ["list", "List", "set", "Set", "frozenset", "FrozenSet", "Sequence", "Iterable", "Iterator",
                                                  "Collection", "MutableSequence", "tuple", "Tuple", "deque", "Deque", "dict", "Dict",
                                                  "Mapping", "MutableMapping", "DefaultDict", "defaultdict", "OrderedDict", "AbstractSet", "Generator"]

    private func builtinGeneric(_ name: String, _ args: [PyType]) -> PyType {
        guard Self.containers.contains(name), !args.isEmpty else { return .unknown }
        return .gen(name, args)
    }

    private func unionOf(_ ts: [PyType]) -> PyType {
        var known: [PyType] = []
        for t in ts {
            if case .unknown = t { return .unknown }
            known.append(t)
        }
        return known.count == 1 ? known[0] : known.isEmpty ? .unknown : .union(known)
    }

    private func stringAnnotation(_ text: String, scope: PyScope, file: PyFile) -> PyType {
        let t = text.trimmingCharacters(in: .whitespaces)
        var inner = t
        for wrap in ["Optional[", "Type["] where t.hasPrefix(wrap) && t.hasSuffix("]") { inner = String(t.dropFirst(wrap.count).dropLast()) }
        guard !inner.isEmpty, inner.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }), !(inner.first!.isNumber) else { return .unknown }
        let parts = inner.split(separator: ".").map(String.init)
        var e: PyExpr = .name(parts[0], Int.max)
        for p in parts.dropFirst() { e = .attr(e, p, Int.max) }
        return annType(e, scope: scope, file: file)
    }

    func eval(_ e: PyExpr, scope: PyScope, file: PyFile) -> PyType {
        guard depth < 30 else { return .unknown }
        depth += 1; defer { depth -= 1 }
        switch e {
        case .name(let n, let off):
            let syms = lookup(n, scope: scope, off: off, file: file)
            guard let s = syms.first else { return .unknown }
            return typeOf(s)
        case .attr(let base, let name, _):
            return memberType(eval(base, scope: scope, file: file), name)
        case .call(let callee, let first, _):
            if case .name("super", _) = callee, let c = enclosingClass(scope) { return .sup(c) }
            if case .name("type", _) = callee, let f = first {
                if case .inst(let c) = eval(f, scope: scope, file: file) { return .cls(c) }
                return .unknown
            }
            return callResult(eval(callee, scope: scope, file: file), awaited: false)
        case .await(let inner):
            if case .call(let callee, _, _) = inner { return callResult(eval(callee, scope: scope, file: file), awaited: true) }
            return eval(inner, scope: scope, file: file)
        case .sub(let base, _):
            switch eval(base, scope: scope, file: file) {
            case .gen(let n, let args):
                if n.lowercased().contains("dict") || n.contains("Mapping") { return args.count > 1 ? args[1] : .unknown }
                return args.first ?? .unknown
            case .inst(let c):
                if let m = memberSyms(c, "__getitem__").first, m.kind == .fn { return returnType(m, awaited: false, selfClass: c) }
                return .unknown
            default: return .unknown
            }
        case .either(let a, let b):
            let ta = eval(a, scope: scope, file: file), tb = eval(b, scope: scope, file: file)
            if ta.isUnknown { return tb }
            if tb.isUnknown { return ta }
            return .union([ta, tb])
        case .enter(let ctxExpr):
            guard case .inst(let c) = eval(ctxExpr, scope: scope, file: file), let m = memberSyms(c, "__enter__").first, m.kind == .fn else { return .unknown }
            return returnType(m, awaited: false, selfClass: c)
        case .exc(let x):
            if case .cls(let c) = eval(x, scope: scope, file: file) { return .inst(c) }
            return .unknown
        case .iter(let x):
            if case .gen(let n, let args) = eval(x, scope: scope, file: file), n != "Generator" || !args.isEmpty { return args.first ?? .unknown }
            return .unknown
        case .str, .lit, .union, .unknown: return .unknown
        }
    }

    func callResult(_ t: PyType, awaited: Bool) -> PyType {
        switch t {
        case .cls(let c): return awaited ? .unknown : .inst(c)
        case .fn(let f): return returnType(f, awaited: awaited, selfClass: nil)
        case .inst(let c):
            if let m = memberSyms(c, "__call__").first, m.kind == .fn { return returnType(m, awaited: awaited, selfClass: c) }
            return .unknown
        case .union(let l):
            let r = l.map { callResult($0, awaited: awaited) }.filter { !$0.isUnknown }
            return r.count == 1 ? r[0] : r.isEmpty ? .unknown : .union(r)
        default: return .unknown
        }
    }

    func returnType(_ f: PySym, awaited: Bool, selfClass: PySym?) -> PyType {
        guard enter(f) else { return .unknown }
        depth += 1
        defer { depth -= 1; visiting.remove(ObjectIdentifier(f)) }
        for d in f.decorators where !Self.transparentDecorators.contains(d) && !d.hasSuffix(".setter") && !d.hasSuffix(".getter") { return .unknown }
        guard let outer = f.scope, let file = ctx.file(f.path) else { return .unknown }
        if f.isAsync && !awaited { return .unknown }
        if f.hasYield { return .unknown }
        if let r = f.returns {
            let t = annType(r, scope: outer, file: file)
            if case .name("Self", _) = r, let sc = selfClass { return .inst(sc) }
            return t
        }
        guard let inner = f.inner else { return .unknown }
        for re in f.retExprs {
            let t = eval(re, scope: inner, file: file)
            if !t.isUnknown { return t }
        }
        return .unknown
    }

    func memberType(_ recv: PyType, _ name: String) -> PyType {
        switch recv {
        case .module(let loc):
            switch memberOfModule(loc, name) {
            case .module(let l): return .module(l)
            case .syms(let l): return l.first.map { typeOf($0) } ?? .unknown
            case .none: return .unknown
            }
        case .inst(let c):
            guard let s = memberSyms(c, name).first else { return .unknown }
            if s.kind == .fn && s.isProperty { return returnType(s, awaited: false, selfClass: c) }
            return typeOf(s)
        case .cls(let c):
            guard let s = memberSyms(c, name).first else { return .unknown }
            return typeOf(s)
        case .sup(let c):
            guard let s = memberSyms(c, name, skipSelf: true).first else { return .unknown }
            if s.kind == .fn && s.isProperty { return returnType(s, awaited: false, selfClass: c) }
            return typeOf(s)
        case .union(let l):
            let r = l.map { memberType($0, name) }.filter { !$0.isUnknown }
            return r.count == 1 ? r[0] : r.isEmpty ? .unknown : .union(r)
        default: return .unknown
        }
    }

    /// Declarations `name` may refer to on a receiver of type `recv` (union receivers contribute every branch).
    func memberTargets(_ recv: PyType, _ name: String) -> [PyMemberHit] {
        switch recv {
        case .module(let loc):
            switch memberOfModule(loc, name) {
            case .module(let l): return [PyMemberHit(module: l)]
            case .syms(let l): return l.map { PyMemberHit(sym: $0) }
            case .none: return []
            }
        case .inst(let c), .cls(let c): return memberSyms(c, name).map { PyMemberHit(sym: $0) }
        case .sup(let c): return memberSyms(c, name, skipSelf: true).map { PyMemberHit(sym: $0) }
        case .union(let l): return l.flatMap { memberTargets($0, name) }
        default: return []
        }
    }

    func typeString(_ t: PyType) -> String? {
        switch t {
        case .inst(let c): return c.name
        case .cls(let c): return "type[\(c.name)]"
        case .module: return "module"
        case .fn: return nil
        case .sup: return nil
        case .union(let l):
            let parts = l.compactMap { typeString($0) }
            return parts.count == l.count ? parts.joined(separator: " | ") : nil
        case .gen(let n, let a):
            let parts = a.compactMap { typeString($0) }
            return parts.count == a.count ? "\(n)[\(parts.joined(separator: ", "))]" : nil
        case .unknown: return nil
        }
    }
}

struct PyMemberHit {
    var sym: PySym?
    var module: PyCtx.Loc?
    init(sym: PySym) { self.sym = sym }
    init(module: PyCtx.Loc) { self.module = module }
}
