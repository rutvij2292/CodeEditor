import Foundation
import SwiftTreeSitter

// A bounded, lazy type evaluator for the native JS / TS service (phase 3). Types are built on demand from declaration text and syntax
// nodes (nothing is kept between requests except the capped summaries), every evaluation has a step budget, and anything the evaluator
// cannot decide is `unknown`: callers treat that as "no answer", never as an answer.

final class NJSTRef {
    let name: String
    let scope: String                    // file whose scope the name was written in
    let args: [NJSTy]
    var decls: [NJSRes]?
    init(_ name: String, scope: String, args: [NJSTy]) { self.name = name; self.scope = scope; self.args = args }
}

struct NJSTParam {
    var name: String
    var ty: NJSTy
    var optional = false
    var rest = false
}

struct NJSFn {
    var tparams: [String] = []
    var params: [NJSTParam] = []
    var ret: NJSTy = .any
    var constraints: [String: NJSTy] = [:]     // `T extends C`
    var defaults: [String: NJSTy] = [:]        // `T = D`
}

struct NJSObjMember {
    var name: String
    var ty: NJSTy
    var optional = false
    var res: NJSRes?
}

final class NJSObj {
    var members: [NJSObjMember]
    var ambiguous = false              // several object literals of the same shape were merged: their members have no single declaration
    let path: String
    init(_ m: [NJSObjMember], path: String) { members = m; self.path = path }
}

indirect enum NJSTy {
    case any, unknown, never, void, undefined, null
    case string, number, boolean, bigint, symbol, nonPrimitive
    case strLit(String), numLit(String), boolLit(Bool)
    case ref(NJSTRef)
    case array(NJSTy)
    case tuple([NJSTy])
    case fn(NJSFn)
    case overloads([NJSFn])
    case obj(NJSObj)
    case union([NJSTy])
    case inter([NJSTy])
    case tparam(String)
    case classCtor(NJSRes)               // the value side of a class / enum / namespace: statics and `new`
    case ns(String)                      // `import * as x`: the module at that path
    case index(NJSTy, NJSTy)             // `T[K]` waiting for its type parameters
    case cond(NJSTy, NJSTy, NJSTy, NJSTy, Bool)   // `check extends ext ? then : else` waiting for its type parameters (last: distributive)

    /// Whether type parameter `n` occurs anywhere in the type.
    func mentions(_ n: String, _ d: Int = 0) -> Bool {
        if d > 8 { return true }
        switch self {
        case .tparam(let x): return x == n
        case .array(let e): return e.mentions(n, d + 1)
        case .tuple(let l), .union(let l), .inter(let l): return l.contains { $0.mentions(n, d + 1) }
        case .ref(let r): return r.args.contains { $0.mentions(n, d + 1) }
        case .fn(let f): return f.ret.mentions(n, d + 1) || f.params.contains { $0.ty.mentions(n, d + 1) }
        case .overloads(let l): return l.contains { NJSTy.fn($0).mentions(n, d + 1) }
        case .obj(let o): return o.members.contains { $0.ty.mentions(n, d + 1) }
        case .cond(let a, let b, let c, let e, _): return a.mentions(n, d + 1) || b.mentions(n, d + 1) || c.mentions(n, d + 1) || e.mentions(n, d + 1)
        case .index(let a, let b): return a.mentions(n, d + 1) || b.mentions(n, d + 1)
        default: return false
        }
    }
    /// Any type parameter occurs in the type.
    func hasTParam(_ d: Int = 0) -> Bool {
        if d > 8 { return true }
        switch self {
        case .tparam: return true
        case .array(let e): return e.hasTParam(d + 1)
        case .tuple(let l), .union(let l), .inter(let l): return l.contains { $0.hasTParam(d + 1) }
        case .ref(let r): return r.args.contains { $0.hasTParam(d + 1) }
        case .fn(let f): return f.ret.hasTParam(d + 1) || f.params.contains { $0.ty.hasTParam(d + 1) }
        case .overloads(let l): return l.contains { NJSTy.fn($0).hasTParam(d + 1) }
        case .obj(let o): return o.members.contains { $0.ty.hasTParam(d + 1) }
        case .cond, .index: return true
        default: return false
        }
    }
    /// A Vue ref type (`Ref`, `ComputedRef`, `ShallowRef`, ...) occurs in the type.
    var refLike: Bool {
        switch self {
        case .ref(let r): return r.name.hasSuffix("Ref") || r.args.contains { $0.refLike }
        case .array(let e): return e.refLike
        case .tuple(let l), .union(let l), .inter(let l): return l.contains { $0.refLike }
        case .obj(let o): return o.members.contains { $0.ty.refLike }
        default: return false
        }
    }
    /// Aliases that only reshape their argument (Vue's `UnwrapRef<T>` of a type without refs is `T`, `IfAny<T, A, B>`).
    static func deferred(_ name: String, _ args: [NJSTy]) -> NJSTy? {
        switch (name, args.count) {
        case ("UnwrapRef", 1), ("UnwrapNestedRefs", 1), ("UnwrapRefSimple", 1):
            if args[0].hasTParam() { return nil }
            return args[0].refLike || args[0].isUnknown ? .unknown : args[0]
        case ("IfAny", 3):
            switch args[0] { case .any: return args[1]; case .tparam: return nil; case .unknown: return .unknown; default: return args[2] }
        default: return nil
        }
    }
    /// `T` is the return type itself or one of its union / intersection members.
    func hasAtTopLevel(_ n: String) -> Bool {
        switch self {
        case .tparam(let x): return x == n
        case .union(let l), .inter(let l): return l.contains { $0.hasAtTopLevel(n) }
        default: return false
        }
    }
    var isUnknown: Bool { if case .unknown = self { return true }; return false }
    var isAny: Bool { if case .any = self { return true }; return false }
}

extension NJSTy {
    static func union(of list: [NJSTy]) -> NJSTy {
        var out: [NJSTy] = []
        var seen = Set<String>()
        func add(_ t: NJSTy) {
            switch t {
            case .union(let inner): inner.forEach(add)
            case .never: break
            default:
                let key = NJSTy.key(t)
                if seen.insert(key).inserted { out.append(t) }
                else if case .obj(let dup) = t, let kept = out.first(where: { NJSTy.key($0) == key }), case .obj(let k) = kept, k !== dup { k.ambiguous = true }
            }
        }
        list.forEach(add)
        if out.contains(where: { $0.isAny }) { return .any }
        if out.isEmpty { return .never }
        if out.count > 1 { out = NJSTy.absorbLiterals(out) }
        return out.count == 1 ? out[0] : .union(out)
    }

    /// `string | 'a'` is `string`.
    private static func absorbLiterals(_ l: [NJSTy]) -> [NJSTy] {
        var hasString = false, hasNumber = false, hasBool = false
        for t in l { switch t { case .string: hasString = true; case .number: hasNumber = true; case .boolean: hasBool = true; default: break } }
        return l.filter { t in
            switch t {
            case .strLit: return !hasString
            case .numLit: return !hasNumber
            case .boolLit: return !hasBool
            default: return true
            }
        }
    }

    /// Structural identity string used for de-duplication.
    static func key(_ t: NJSTy) -> String {
        switch t {
        case .ref(let r): return "r:" + r.name + "<" + r.args.map { key($0) }.joined(separator: ",") + ">"
        case .array(let e): return "a:" + key(e)
        case .tuple(let e): return "t:" + e.map { key($0) }.joined(separator: ",")
        default: return describe(t, depth: 0)
        }
    }
    private static let dummy = NJSObj([], path: "")

    /// A literal's widened type (`let x = 1` is a number).
    var widened: NJSTy {
        switch self {
        case .strLit: return .string
        case .numLit: return .number
        case .boolLit: return .boolean
        case .union(let l): return NJSTy.union(of: l.map { $0.widened })
        case .array(let e): return .array(e.widened)
        default: return self
        }
    }

    var withoutNullish: NJSTy {
        switch self {
        case .undefined, .null: return .never
        case .union(let l): return NJSTy.union(of: l.map { $0.withoutNullish })
        default: return self
        }
    }

    var nullish: Bool {
        switch self {
        case .undefined, .null, .void: return true
        case .union(let l): return l.contains { $0.nullish }
        default: return false
        }
    }

    // MARK: printing (TypeScript's style)

    func describe() -> String { NJSTy.describe(self, depth: 0) }
    /// The way a language server prints object types in a hover: one member per line.
    func describeMultiline() -> String { NJSTy.describe(self, depth: 0, ml: 0) }

    static func describe(_ t: NJSTy, depth: Int, ml: Int = -1) -> String {
        if depth > 4 { return "..." }
        switch t {
        case .any: return "any"
        case .unknown: return "unknown"
        case .never: return "never"
        case .void: return "void"
        case .undefined: return "undefined"
        case .null: return "null"
        case .string: return "string"
        case .number: return "number"
        case .boolean: return "boolean"
        case .bigint: return "bigint"
        case .symbol: return "symbol"
        case .nonPrimitive: return "object"
        case .strLit(let s): return "\"" + s + "\""
        case .numLit(let s): return s
        case .boolLit(let b): return b ? "true" : "false"
        case .ref(let r): return r.args.isEmpty ? r.name : r.name + "<" + r.args.map { describe($0, depth: depth + 1, ml: ml) }.joined(separator: ", ") + ">"
        case .array(let e):
            let inner = describe(e, depth: depth + 1, ml: ml)
            switch e { case .union, .inter, .fn, .overloads: return "(" + inner + ")[]"; default: return inner + "[]" }
        case .tuple(let e): return "[" + e.map { describe($0, depth: depth + 1, ml: ml) }.joined(separator: ", ") + "]"
        case .fn(let f): return describeFn(f, depth: depth)
        case .overloads(let l): return l.first.map { describeFn($0, depth: depth) } ?? "Function"
        case .obj(let o):
            if o.members.isEmpty { return "{}" }
            let shown = o.members.prefix(ml >= 0 ? 24 : 8).map { m in
                let n = m.name.range(of: #"^[A-Za-z_$][\w$]*$"#, options: .regularExpression) != nil ? m.name : "\"" + m.name + "\""
                return n + (m.optional ? "?" : "") + ": " + describe(m.ty, depth: depth + 1, ml: ml >= 0 ? ml + 1 : -1)
            }
            if ml >= 0 {
                let pad = String(repeating: "    ", count: ml + 1)
                return "{\n" + shown.map { pad + $0 + ";\n" }.joined() + (o.members.count > 24 ? pad + "...;\n" : "") + String(repeating: "    ", count: ml) + "}"
            }
            return "{ " + shown.joined(separator: "; ") + (o.members.count > 8 ? "; ..." : "") + " }"
        case .union(let l):
            let parts = l.prefix(12).map { x -> String in
                let s = describe(x, depth: depth + 1, ml: ml)
                if case .fn = x { return "(" + s + ")" }
                return s
            }
            return parts.joined(separator: " | ") + (l.count > 12 ? " | ..." : "")
        case .inter(let l): return l.map { describe($0, depth: depth + 1, ml: ml) }.joined(separator: " & ")
        case .tparam(let n): return n
        case .cond, .index: return "..."
        case .classCtor(let r): return "typeof " + r.name
        case .ns(let p): return "typeof import(\"" + ((p as NSString).lastPathComponent as NSString).deletingPathExtension + "\")"
        }
    }

    static func describeFn(_ f: NJSFn, depth: Int) -> String {
        let ps = f.params.map { p in (p.rest ? "..." : "") + p.name + (p.optional ? "?" : "") + ": " + describe(p.ty, depth: depth + 1, ml: -1) }
        return (f.tparams.isEmpty ? "" : "<" + f.tparams.joined(separator: ", ") + ">") + "(" + ps.joined(separator: ", ") + ") => " + describe(f.ret, depth: depth + 1)
    }

    // MARK: substitution and unification

    func substituting(_ env: [String: NJSTy]) -> NJSTy {
        if env.isEmpty { return self }
        switch self {
        case .tparam(let n): return env[n] ?? self
        case .array(let e): return .array(e.substituting(env))
        case .tuple(let l): return .tuple(l.map { $0.substituting(env) })
        case .union(let l): return NJSTy.union(of: l.map { $0.substituting(env) })
        case .inter(let l): return .inter(l.map { $0.substituting(env) })
        case .ref(let r):
            if r.args.isEmpty { return self }
            let args = r.args.map { $0.substituting(env) }
            return NJSTy.deferred(r.name, args) ?? .ref(NJSTRef(r.name, scope: r.scope, args: args))
        case .cond(let a, let b, let c, let d, let dist): return .cond(a.substituting(env), b.substituting(env), c.substituting(env), d.substituting(env), dist)
        case .index(let a, let b): return .index(a.substituting(env), b.substituting(env))
        case .fn(let f): return .fn(f.substituting(env))
        case .overloads(let l): return .overloads(l.map { $0.substituting(env) })
        case .obj(let o): return .obj(NJSObj(o.members.map { NJSObjMember(name: $0.name, ty: $0.ty.substituting(env), optional: $0.optional, res: $0.res) }, path: o.path))
        default: return self
        }
    }

    /// Binds the type parameters mentioned by `self` (a parameter type) from the argument type `arg`.
    func unify(_ arg: NJSTy, into binds: inout [String: NJSTy], depth: Int = 0) {
        if depth > 6 { return }
        switch (self, arg) {
        case (.tparam(let n), _):
            if case .unknown = arg { return }
            if let old = binds[n] {
                if NJSTy.key(old) != NJSTy.key(arg) { binds[n] = NJSTy.union(of: [old, arg]) }
            } else { binds[n] = arg }
        case (.array(let p), .array(let a)): p.unify(a, into: &binds, depth: depth + 1)
        case (.array(let p), .tuple(let l)): p.unify(NJSTy.union(of: l), into: &binds, depth: depth + 1)
        case (.tuple(let p), .tuple(let a)): for (x, y) in zip(p, a) { x.unify(y, into: &binds, depth: depth + 1) }
        case (.ref(let p), .ref(let a)) where p.name == a.name:
            for (x, y) in zip(p.args, a.args) { x.unify(y, into: &binds, depth: depth + 1) }
        case (.ref(let p), .array(let e)) where (p.name == "Iterable" || p.name == "ArrayLike" || p.name == "ReadonlyArray" || p.name == "Iterator") && p.args.count == 1:
            p.args[0].unify(e, into: &binds, depth: depth + 1)
        case (.fn(let p), .fn(let a)):
            p.ret.unify(a.ret, into: &binds, depth: depth + 1)
            for (x, y) in zip(p.params, a.params) { x.ty.unify(y.ty, into: &binds, depth: depth + 1) }
        case (.union(let alts), _):
            // `T | PromiseLike<T>`, `T | undefined`: use the alternative that structurally matches, else a bare parameter
            for alt in alts {
                switch (alt, arg) {
                case (.ref(let p), .ref(let a)) where p.name == a.name: alt.unify(arg, into: &binds, depth: depth + 1); return
                case (.array, .array), (.fn, .fn): alt.unify(arg, into: &binds, depth: depth + 1); return
                default: break
                }
            }
            if let bare = alts.first(where: { if case .tparam = $0 { return true }; return false }) { bare.unify(arg.withoutNullish, into: &binds, depth: depth + 1) }
        case (.obj(let p), .obj(let a)):
            for m in p.members { if let am = a.members.first(where: { $0.name == m.name }) { m.ty.unify(am.ty, into: &binds, depth: depth + 1) } }
        default: break
        }
    }
}

extension NJSFn {
    func substituting(_ env: [String: NJSTy]) -> NJSFn {
        var inner = env
        for tp in tparams { inner[tp] = nil }                             // own parameters shadow outer ones
        return NJSFn(tparams: tparams, params: params.map { NJSTParam(name: $0.name, ty: $0.ty.substituting(inner), optional: $0.optional, rest: $0.rest) }, ret: ret.substituting(inner), constraints: constraints, defaults: defaults)
    }
}

/// Builds types from declaration text / syntax nodes and answers questions about them.
final class NJSTyper {
    unowned let env: NJSEnv
    var steps = 0
    static let stepLimit = 6000
    private var parseCache: [String: NJSTy] = [:]
    var otherEnvs: [String: NJSEnv] = [:]        // other files opened to read an initializer (this request only)
    var inferring = Set<String>()                // declarations being evaluated: cycles evaluate to unknown

    init(env: NJSEnv) { self.env = env }

    /// Budget spent, or the thread is close to the end of its (small, 512 KB for dispatch queues) stack: evaluation stops and answers unknown.
    var exhausted: Bool {
        if steps > NJSTyper.stepLimit { return true }
        if NJSStack.low() { steps = NJSTyper.stepLimit + 1; return true }
        return false
    }

    // MARK: type nodes

    struct Scope {
        var path: String
        var tenv: [String: NJSTy] = [:]            // type parameters with a known type
        var tparams: Set<String> = []              // type parameters that stay symbolic
    }

    /// `type __T = <text>` parsed and converted; nil text -> unknown.
    func parse(text: String, scope: Scope) -> NJSTy {
        steps += 1
        if exhausted { return .unknown }
        let key = scope.path + "|" + scope.tparams.sorted().joined(separator: ",") + "|" + scope.tenv.keys.sorted().joined(separator: ",") + "|" + text
        if scope.tenv.isEmpty, let c = parseCache[key] { return c }
        let src = "type __T = " + text + ";"
        let ns = src as NSString
        guard let doc = NJSDoc(path: "/__ty.ts", text: ns), let alias = doc.root.kids.first, alias.kind == "type_alias_declaration", let v = alias.field("value") else { return .unknown }
        defer { withExtendedLifetime(doc) {} }
        let t = convert(v, ns, scope)
        if scope.tenv.isEmpty, parseCache.count < 400 { parseCache[key] = t }
        return t
    }

    /// A function type from `<T>(a: A, b?: B): R` as stored for declarations.
    /// Names, constraints and defaults of a `type_parameters` node; `inner` must already contain the names.
    func tparamInfo(_ tp: Node?, _ ns: NSString, _ inner: Scope) -> (names: [String], constraints: [String: NJSTy], defaults: [String: NJSTy]) {
        guard let tp else { return ([], [:], [:]) }
        var names: [String] = [], cons: [String: NJSTy] = [:], defs: [String: NJSTy] = [:]
        for t in tp.kids where t.kind == "type_parameter" {
            guard let nm = t.field("name")?.text(ns) else { continue }
            names.append(nm)
            if let c = t.field("constraint")?.kids.first { cons[nm] = convert(c, ns, inner) }
            if let dn = t.field("value") { defs[nm] = convert(dn.kind == "default_type" ? (dn.kids.first ?? dn) : dn, ns, inner) }
        }
        return (names, cons, defs)
    }

    func parseSignature(_ sig: String, scope: Scope) -> NJSFn? {
        // `(...): R` -> `(...) => R`
        let u = Array(sig.utf16)
        var start = 0
        if u.first == 60 {                                                    // <T, U extends X>
            var d = 0, i = 0
            while i < u.count { if u[i] == 60 { d += 1 } else if u[i] == 62, !(i > 0 && u[i - 1] == 61) { d -= 1; if d == 0 { start = i + 1; break } }; i += 1 }
        }
        guard start < u.count, u[start] == 40 else { return nil }
        var depth = 0, close = -1, i = start
        while i < u.count {
            let c = u[i]
            if c == 40 || c == 91 || c == 123 { depth += 1 } else if c == 41 || c == 93 || c == 125 { depth -= 1; if depth == 0 { close = i; break } }
            else if c == 34 || c == 39 || c == 96 { var j = i + 1; while j < u.count, u[j] != c { if u[j] == 92 { j += 1 }; j += 1 }; i = j }
            i += 1
        }
        guard close > 0 else { return nil }
        let head = String(utf16CodeUnits: Array(u[0...close]), count: close + 1)
        var rest = String(utf16CodeUnits: Array(u[(close + 1)...]), count: u.count - close - 1).trimmingCharacters(in: .whitespaces)
        if rest.hasPrefix(":") { rest = String(rest.dropFirst()).trimmingCharacters(in: .whitespaces) } else { rest = "any" }
        if rest.isEmpty { rest = "any" }
        let t = parse(text: head + " => " + rest, scope: scope)
        if case .fn(let f) = t { return f }
        return nil
    }

    func convert(_ n: Node, _ ns: NSString, _ sc: Scope) -> NJSTy {
        steps += 1
        if exhausted { return .unknown }
        switch n.kind {
        case "predefined_type":
            switch n.text(ns) {
            case "string": return .string
            case "number": return .number
            case "boolean": return .boolean
            case "bigint": return .bigint
            case "symbol": return .symbol
            case "any": return .any
            case "unknown": return .unknown
            case "never": return .never
            case "void": return .void
            case "object": return .nonPrimitive
            case "undefined": return .undefined
            case "null": return .null
            default: return .unknown
            }
        case "literal_type":
            guard let c = n.kids.first else { return .unknown }
            switch c.kind {
            case "string": return .strLit(c.kids.first(where: { $0.kind == "string_fragment" })?.text(ns) ?? "")
            case "number": return .numLit(c.text(ns))
            case "unary_expression": return .numLit(c.text(ns))
            case "true": return .boolLit(true)
            case "false": return .boolLit(false)
            case "null": return .null
            case "undefined": return .undefined
            default: return .unknown
            }
        case "type_identifier", "identifier":
            let name = n.text(ns)
            if let t = sc.tenv[name] { return t }
            if sc.tparams.contains(name) { return .tparam(name) }
            return .ref(NJSTRef(name, scope: sc.path, args: []))
        case "nested_type_identifier":
            return .ref(NJSTRef(n.text(ns).replacingOccurrences(of: " ", with: ""), scope: sc.path, args: []))
        case "generic_type":
            guard let nm = n.field("name") else { return .unknown }
            let name = nm.text(ns).replacingOccurrences(of: " ", with: "")
            let args = (n.field("type_arguments")?.kids ?? []).map { convert($0, ns, sc) }
            if let t = sc.tenv[name], args.isEmpty { return t }
            switch name {
            case "Array", "ReadonlyArray": return .array(args.first ?? .any)
            default: break
            }
            if let u = utility(name, args) { return u }
            if let d = NJSTy.deferred(name, args) { return d }
            return .ref(NJSTRef(name, scope: sc.path, args: args))
        case "array_type": return .array(n.kids.first.map { convert($0, ns, sc) } ?? .any)
        case "readonly_type", "parenthesized_type", "opting_type_annotation", "type_annotation": return n.kids.first.map { convert($0, ns, sc) } ?? .unknown
        case "optional_type": return NJSTy.union(of: [n.kids.first.map { convert($0, ns, sc) } ?? .unknown, .undefined])
        case "tuple_type":
            var elems: [NJSTy] = []
            var rest = false
            for c in n.kids {
                if c.kind == "rest_type" { rest = true; if case .array(let e) = convert(c.kids.first ?? c, ns, sc) { elems.append(e) } else { elems.append(.any) } }
                else { elems.append(convert(c, ns, sc)) }
            }
            return rest ? .array(NJSTy.union(of: elems)) : .tuple(elems)
        case "union_type": return NJSTy.union(of: n.kids.map { convert($0, ns, sc) })
        case "intersection_type": return .inter(n.kids.map { convert($0, ns, sc) })
        case "function_type", "constructor_type":
            var inner = sc
            var tps: [String] = []
            if let tp = n.field("type_parameters") { for t in tp.kids where t.kind == "type_parameter" { if let nm = t.field("name")?.text(ns) { tps.append(nm); inner.tparams.insert(nm); inner.tenv[nm] = nil } } }
            let info = tparamInfo(n.field("type_parameters"), ns, inner)
            let params = fnParams(n.field("parameters"), ns, inner)
            let ret = (n.field("return_type") ?? n.field("type")).map { convert($0, ns, inner) } ?? .any
            return .fn(NJSFn(tparams: tps, params: params, ret: ret, constraints: info.constraints, defaults: info.defaults))
        case "object_type":
            var members: [NJSObjMember] = []
            for m in n.kids {
                switch m.kind {
                case "property_signature":
                    guard let nm = m.field("name") else { continue }
                    let optional = m.allKids.contains { $0.kind == "?" }
                    members.append(NJSObjMember(name: nm.kind == "string" ? (nm.kids.first?.text(ns) ?? "") : nm.text(ns), ty: m.field("type").map { convert($0, ns, sc) } ?? .any, optional: optional))
                case "method_signature":
                    guard let nm = m.field("name") else { continue }
                    var inner = sc
                    var tps: [String] = []
                    if let tp = m.field("type_parameters") { for t in tp.kids where t.kind == "type_parameter" { if let x = t.field("name")?.text(ns) { tps.append(x); inner.tparams.insert(x) } } }
                    let info = tparamInfo(m.field("type_parameters"), ns, inner)
                    let f = NJSFn(tparams: tps, params: fnParams(m.field("parameters"), ns, inner), ret: m.field("return_type").map { convert($0, ns, inner) } ?? .any, constraints: info.constraints, defaults: info.defaults)
                    members.append(NJSObjMember(name: nm.text(ns), ty: .fn(f), optional: m.allKids.contains { $0.kind == "?" }))
                case "index_signature":
                    if m.kids.contains(where: { $0.kind == "mapped_type_clause" }) { return .unknown }       // mapped type: not evaluated here
                default: break
                }
            }
            return .obj(NJSObj(members, path: sc.path))
        case "type_query":
            guard let id = n.kids.first else { return .unknown }
            return valueTypeOfName(id.text(ns), scope: sc.path)
        case "this_type": return sc.tenv["this"] ?? .tparam("this")
        case "template_literal_type": return .string
        case "index_type_query":
            let t = n.kids.first.map { convert($0, ns, sc) } ?? .unknown
            return keyUnion(of: t)
        case "lookup_type":
            guard n.kids.count == 2 else { return .unknown }
            let base = convert(n.kids[0], ns, sc), key = convert(n.kids[1], ns, sc)
            if base.hasTParam() || key.hasTParam() { return .index(base, key) }
            return evalIndex(base, key)
        case "conditional_type":
            guard let l = n.field("left"), let r = n.field("right"), let c = n.field("consequence"), let a = n.field("alternative") else { return .unknown }
            if containsInfer(r, ns) { return .unknown }
            var lt = convert(l, ns, sc), rt = convert(r, ns, sc)
            if l.kind == "tuple_type", r.kind == "tuple_type", l.kids.count == 1, r.kids.count == 1 { lt = convert(l.kids[0], ns, sc); rt = convert(r.kids[0], ns, sc) }       // `[T] extends [U]`: not distributive
            let dist = (l.kind == "type_identifier" || l.kind == "predefined_type") && sc.tparams.contains(l.text(ns))
            if lt.hasTParam() || rt.hasTParam() { return .cond(lt, rt, convert(c, ns, sc), convert(a, ns, sc), dist) }
            return evalCond(lt, rt, dist, then: { self.convert(c, ns, sc) }, else: { self.convert(a, ns, sc) })
        default: return .unknown
        }
    }

    private func containsInfer(_ n: Node, _ ns: NSString) -> Bool { n.text(ns).contains("infer ") }

    /// `base[key]` for a literal key (or a union of them) of an object-like type, `number` over arrays and tuples.
    func evalIndex(_ base: NJSTy, _ key: NJSTy) -> NJSTy {
        switch key {
        case .strLit(let k):
            let hits = members(of: base, name: k)
            return hits.isEmpty ? .unknown : NJSInfer.mergeTypes(hits)
        case .union(let l): return NJSTy.union(of: l.map { evalIndex(base, $0) })
        case .number, .numLit:
            switch base {
            case .array(let e): return e
            case .tuple(let l): if case .numLit(let v) = key, let i = Int(v), i < l.count { return l[i] }; return NJSTy.union(of: l)
            default: return .unknown
            }
        default: return .unknown
        }
    }

    func evalCond(_ check: NJSTy, _ ext: NJSTy, _ dist: Bool, then: () -> NJSTy, else other: () -> NJSTy) -> NJSTy {
        if dist, case .union(let l) = check {
            return NJSTy.union(of: l.map { evalCond($0, ext, false, then: then, else: other) })
        }
        if dist, case .never = check { return .never }
        switch assignable(check, to: ext) {
        case true?: return then()
        case false?: return other()
        default: return .unknown
        }
    }

    /// Evaluates the conditional types left in `t` whose type parameters have been substituted since.
    func settle(_ t: NJSTy, depth: Int = 0) -> NJSTy {
        guard depth < 8, !exhausted else { return t }
        switch t {
        case .cond(let a, let b, let c, let d, let dist):
            if a.hasTParam() || b.hasTParam() { return t }
            return settle(evalCond(a, b, dist, then: { c }, else: { d }), depth: depth + 1)
        case .index(let a, let b):
            if a.hasTParam() || b.hasTParam() { return t }
            return settle(evalIndex(a, b), depth: depth + 1)
        case .array(let e): return .array(settle(e, depth: depth + 1))
        case .tuple(let l): return .tuple(l.map { settle($0, depth: depth + 1) })
        case .union(let l): return NJSTy.union(of: l.map { settle($0, depth: depth + 1) })
        case .inter(let l): return .inter(l.map { settle($0, depth: depth + 1) })
        case .ref(let r): return r.args.isEmpty ? t : .ref(NJSTRef(r.name, scope: r.scope, args: r.args.map { settle($0, depth: depth + 1) }))
        case .fn(let f): return .fn(NJSFn(tparams: f.tparams, params: f.params.map { NJSTParam(name: $0.name, ty: settle($0.ty, depth: depth + 1), optional: $0.optional, rest: $0.rest) }, ret: settle(f.ret, depth: depth + 1), constraints: f.constraints, defaults: f.defaults))
        default: return t
        }
    }

    func fnParams(_ list: Node?, _ ns: NSString, _ sc: Scope) -> [NJSTParam] {
        var out: [NJSTParam] = []
        for p in list?.kids ?? [] {
            switch p.kind {
            case "required_parameter", "optional_parameter":
                var name = "arg\(out.count)"
                var rest = false
                if let pat = p.field("pattern") {
                    if pat.kind == "rest_pattern" { rest = true; name = pat.kids.first?.text(ns) ?? name } else if pat.kind == "identifier" || pat.kind == "this" { name = pat.text(ns) } else { name = clip(pat.text(ns)) }
                }
                if name == "this" { continue }                                   // `this:` parameters are not arguments
                var t = p.field("type").map { convert($0, ns, sc) } ?? .any
                if rest, case .array = t {} else if rest { t = .array(t) }
                out.append(NJSTParam(name: name, ty: rest ? t : t, optional: p.kind == "optional_parameter" || p.field("value") != nil, rest: rest))
            default: break
            }
        }
        return out
    }

    private func clip(_ s: String) -> String { s.count > 16 ? String(s.prefix(14)) + "..." : s }

    // MARK: utility types

    private func utility(_ name: String, _ args: [NJSTy]) -> NJSTy? {
        switch (name, args.count) {
        case ("NonNullable", 1): return args[0].withoutNullish
        case ("Partial", 1), ("Required", 1), ("Readonly", 1): return reshape(args[0], optional: name == "Partial" ? true : name == "Required" ? false : nil)
        case ("Pick", 2): return pick(args[0], keys: keyList(args[1]), keep: true)
        case ("Omit", 2): return pick(args[0], keys: keyList(args[1]), keep: false)
        case ("Record", 2):
            let ks = keyList(args[0])
            return ks.isEmpty ? .obj(NJSObj([], path: "")) : .obj(NJSObj(ks.map { NJSObjMember(name: $0, ty: args[1]) }, path: ""))
        case ("ReturnType", 1): return returnType(args[0])
        case ("Awaited", 1): return awaited(args[0])
        case ("Parameters", 1): if case .fn(let f) = args[0] { return .tuple(f.params.map { $0.ty }) }; return nil
        case ("Exclude", 2): if case .union(let l) = args[0] { return NJSTy.union(of: l.filter { assignable($0, to: args[1]) != true }) }; return assignable(args[0], to: args[1]) == true ? .never : args[0]
        case ("Extract", 2): if case .union(let l) = args[0] { return NJSTy.union(of: l.filter { assignable($0, to: args[1]) == true }) }; return assignable(args[0], to: args[1]) == true ? args[0] : .never
        default: return nil
        }
    }

    private func keyList(_ t: NJSTy) -> [String] {
        switch t {
        case .strLit(let s): return [s]
        case .union(let l): return l.flatMap { keyList($0) }
        default: return []
        }
    }

    private func reshape(_ t: NJSTy, optional: Bool?) -> NJSTy {
        let all = allMembers(of: t)
        guard !all.isEmpty else { return .unknown }
        return .obj(NJSObj(all.map { NJSObjMember(name: $0.name, ty: $0.ty, optional: optional ?? $0.optional, res: $0.res) }, path: ""))
    }

    private func pick(_ t: NJSTy, keys: [String], keep: Bool) -> NJSTy {
        let all = allMembers(of: t)
        guard !all.isEmpty else { return .unknown }
        let ks = Set(keys)
        return .obj(NJSObj(all.filter { ks.contains($0.name) == keep }.map { NJSObjMember(name: $0.name, ty: $0.ty, optional: $0.optional, res: $0.res) }, path: ""))
    }

    func keyUnion(of t: NJSTy) -> NJSTy {
        let all = allMembers(of: t)
        return all.isEmpty ? .unknown : NJSTy.union(of: all.map { .strLit($0.name) })
    }

    func returnType(_ t: NJSTy) -> NJSTy {
        switch t {
        case .fn(let f): return f.ret
        case .overloads(let l): return l.last?.ret ?? .unknown
        default: return .unknown
        }
    }

    /// `Promise<T>` -> T (recursively), unions member by member.
    func awaited(_ t: NJSTy) -> NJSTy {
        switch t {
        case .ref(let r) where (r.name == "Promise" || r.name == "PromiseLike") && r.args.count == 1: return awaited(r.args[0])
        case .union(let l): return NJSTy.union(of: l.map { awaited($0) })
        default: return t
        }
    }

    // MARK: assignability (coarse; nil = cannot tell)

    func assignable(_ a: NJSTy, to b: NJSTy) -> Bool? {
        steps += 1
        if exhausted { return nil }
        switch (a, b) {
        case (_, .any), (.any, _): return true
        case (.never, _): return true
        case (.tparam, _), (_, .tparam), (.unknown, _), (_, .unknown): return nil
        case (.union(let l), _):
            var all = true
            for x in l { switch assignable(x, to: b) { case false?: return false; case nil: all = false; default: break } }
            return all ? true : nil
        case (_, .union(let l)):
            var unsure = false
            for y in l { switch assignable(a, to: y) { case true?: return true; case nil: unsure = true; default: break } }
            return unsure ? nil : false
        case (.string, .string), (.number, .number), (.boolean, .boolean), (.bigint, .bigint), (.symbol, .symbol), (.void, .void), (.undefined, .undefined), (.null, .null): return true
        case (.strLit, .string), (.numLit, .number), (.boolLit, .boolean): return true
        case (.strLit(let x), .strLit(let y)): return x == y
        case (.numLit(let x), .numLit(let y)): return x == y
        case (.boolLit(let x), .boolLit(let y)): return x == y
        case (.array(let x), .array(let y)): return assignable(x, to: y)
        case (.tuple, .array): return nil
        case (.ref(let x), .ref(let y)): return x.name == y.name ? true : nil
        case (.string, .ref(let r)), (.number, .ref(let r)), (.boolean, .ref(let r)), (.strLit, .ref(let r)), (.numLit, .ref(let r)), (.boolLit, .ref(let r)), (.undefined, .ref(let r)), (.null, .ref(let r)):
            return missingRequired(a, in: r) ? false : nil
        case (.obj, .ref(let r)), (.array, .ref(let r)), (.tuple, .ref(let r)), (.fn, .ref(let r)), (.overloads, .ref(let r)): return missingRequired(a, in: r) ? false : nil
        case (.string, _), (.number, _), (.boolean, _), (.undefined, _), (.null, _), (.strLit, _), (.numLit, _), (.boolLit, _):
            switch b { case .string, .number, .boolean, .undefined, .null, .strLit, .numLit, .boolLit, .bigint, .symbol, .void: return false; case .array, .tuple, .fn: return false; default: return nil }
        default: return nil
        }
    }

    /// True when the interface / class `r` has a required member the (primitive or object literal) type `a` provably lacks.
    private func missingRequired(_ a: NJSTy, in r: NJSTRef) -> Bool {
        let ds = decls(r).filter { $0.kind == .interface || $0.kind == .class }
        guard !ds.isEmpty, ds.count == decls(r).count else { return false }
        for d in ds {
            if !d.heritage.isEmpty { continue }                              // only flat declarations are decided
            for m in d.members where !m.isStatic && m.name != "constructor" && m.name != "()" && m.name != "new" && !m.optional {
                if members(of: a, name: m.name).isEmpty { return true }
            }
        }
        return false
    }

    // MARK: declarations behind names

    func decls(_ r: NJSTRef) -> [NJSRes] {
        if let d = r.decls { return d }
        steps += 1
        let d = env.resolveTypeRef(r.name, in: r.scope)
        r.decls = d
        return d
    }

    /// The nominal / structural shape of `t` with aliases expanded (bounded).
    func expand(_ t: NJSTy, depth: Int = 0) -> NJSTy {
        guard depth < 8, !exhausted, case .ref(let r) = t else { return t }
        let ds = decls(r)
        guard let alias = ds.first(where: { $0.kind == .typeAlias }), let text = alias.aliasText else { return t }
        var tenv: [String: NJSTy] = [:]
        for (i, p) in alias.tparams.enumerated() { tenv[p] = i < r.args.count ? r.args[i] : .unknown }
        let v = parse(text: text, scope: Scope(path: alias.path, tenv: tenv, tparams: []))
        if case .unknown = v { return t }
        return expand(v, depth: depth + 1)
    }

    /// Type of a value named `name` in `scope` (for `typeof x`).
    func valueTypeOfName(_ name: String, scope: String) -> NJSTy {
        let parts = name.split(separator: ".").map(String.init)
        guard let first = parts.first else { return .unknown }
        var cur = valueType(of: env.resolveName(scope, first))
        for p in parts.dropFirst() { cur = members(of: cur, name: p).first?.ty ?? .unknown }
        return cur
    }
}

/// Remaining stack of the current thread.
enum NJSStack {
    static func low(reserve: UInt = 120 * 1024) -> Bool {
        var marker = 0
        let me = pthread_self()
        let top = UInt(bitPattern: pthread_get_stackaddr_np(me))
        let bottom = top - UInt(pthread_get_stacksize_np(me))
        let sp = withUnsafePointer(to: &marker) { UInt(bitPattern: $0) }
        return sp < bottom + reserve
    }
}
