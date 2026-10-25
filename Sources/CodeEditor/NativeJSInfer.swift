import Foundation
import SwiftTreeSitter

/// Expression and declaration typing over the syntax tree of one document: literals, object / array literals, functions and their
/// contextual parameter types, calls with simple generic inference (`T` from arguments, callback results), `new`, `await`, member
/// access on anything `NJSTyper` can enumerate, destructuring, for-of, `this`. Results are memoised per node; every path is bounded
/// by `NJSTyper`'s step budget and a recursion depth, and falls back to `unknown`.
final class NJSInfer {
    unowned let env: NJSEnv
    unowned let typer: NJSTyper
    private var cache: [UInt: NJSTy] = [:]
    private var active = Set<UInt>()
    private var depth = 0
    static let maxDepth = 28

    init(env: NJSEnv, typer: NJSTyper) { self.env = env; self.typer = typer }

    private var ns: NSString { env.doc.text }
    private var scope: NJSTyper.Scope { NJSTyper.Scope(path: env.path, tenv: [:], tparams: []) }

    /// The scope a type annotation written at `n` sees: type parameters of every enclosing function / class / interface / alias.
    func scope(at n: Node) -> NJSTyper.Scope {
        var sc = scope
        var p: Node? = n
        while let c = p {
            if let tp = c.field("type_parameters") { for t in tp.kids where t.kind == "type_parameter" { if let nm = t.field("name")?.text(ns) { sc.tparams.insert(nm) } } }
            p = c.parent
        }
        return sc
    }

    func ty(_ n: Node) -> NJSTy {
        if let c = cache[n.id] { return c }
        guard depth < NJSInfer.maxDepth, !typer.exhausted, active.insert(n.id).inserted else { return .unknown }
        depth += 1
        typer.steps += 1
        defer { depth -= 1; active.remove(n.id) }
        let t = compute(n)
        cache[n.id] = t
        return t
    }

    // MARK: expressions

    private func compute(_ n: Node) -> NJSTy {
        switch n.kind {
        case "number": return .numLit(n.text(ns))
        case "string": return .strLit(n.kids.count == 1 && n.kids[0].kind == "string_fragment" ? n.kids[0].text(ns) : (n.kids.isEmpty ? "" : "?"))
        case "template_string": return .string
        case "true": return .boolLit(true)
        case "false": return .boolLit(false)
        case "null": return .null
        case "undefined": return .undefined
        case "regex": return .ref(NJSTRef("RegExp", scope: env.path, args: []))
        case "this": return thisType(n)
        case "identifier":
            let name = n.text(ns)
            if name == "undefined" { return .undefined }
            if let b = env.localBinding(name, from: n) { return typeOfBinding(b) }
            return typer.valueType(of: env.resolveName(env.path, name))
        case "parenthesized_expression": return n.kids.first.map { ty($0) } ?? .unknown
        case "non_null_expression": return n.kids.first.map { ty($0).withoutNullish } ?? .unknown
        case "as_expression", "satisfies_expression":
            guard n.kids.count >= 2 else { return .unknown }
            if n.kids[1].text(ns) == "const" { return ty(n.kids[0]) }
            return n.kind == "satisfies_expression" ? ty(n.kids[0]) : typer.convert(n.kids[1], ns, scope(at: n))
        case "type_assertion": return n.kids.first.map { typer.convert($0, ns, scope(at: n)) } ?? .unknown
        case "array": return arrayType(n)
        case "object": return objectType(n)
        case "arrow_function", "function_expression", "function", "generator_function", "function_declaration", "generator_function_declaration", "method_definition":
            return .fn(fnType(n))
        case "member_expression": return memberType(n)
        case "subscript_expression": return subscriptType(n)
        case "call_expression": return callType(n)
        case "new_expression": return newType(n)
        case "await_expression": return n.kids.first.map { typer.awaited(ty($0)) } ?? .unknown
        case "binary_expression": return binaryType(n)
        case "unary_expression":
            let op = n.field("operator")?.text(ns) ?? n.allKids.first?.text(ns) ?? ""
            switch op {
            case "!": return .boolean
            case "typeof": return .string
            case "void": return .undefined
            case "-", "+", "~":
                if let a = n.field("argument") ?? n.kids.first, case .numLit(let v) = ty(a) { return op == "-" ? .numLit(v.hasPrefix("-") ? String(v.dropFirst()) : "-" + v) : .numLit(v) }
                return .number
            case "delete": return .boolean
            default: return .unknown
            }
        case "update_expression": return .number
        case "assignment_expression": return n.field("right").map { ty($0) } ?? .unknown
        case "augmented_assignment_expression": return .unknown
        case "ternary_expression":
            guard let c = n.field("consequence"), let a = n.field("alternative") else { return .unknown }
            return NJSTy.union(of: [ty(c), ty(a)])
        case "sequence_expression": return n.kids.last.map { ty($0) } ?? .unknown
        case "jsx_element", "jsx_self_closing_element", "jsx_fragment": return .ref(NJSTRef("JSX.Element", scope: env.path, args: []))
        case "yield_expression": return .any
        default: return .unknown
        }
    }

    private func arrayType(_ n: Node) -> NJSTy {
        var elems: [NJSTy] = []
        for c in n.kids {
            if c.kind == "spread_element", let inner = c.kids.first { elems.append(elementType(of: ty(inner))) }
            else { elems.append(ty(c).widened) }
        }
        let u = NJSTy.union(of: elems.filter { !$0.isUnknown })
        if elems.isEmpty { return .array(.any) }
        if elems.contains(where: { $0.isUnknown }) && elems.allSatisfy({ $0.isUnknown }) { return .array(.unknown) }
        return .array(u)
    }

    private func objectType(_ n: Node) -> NJSTy {
        var members: [NJSObjMember] = []
        func upsert(_ m: NJSObjMember) { if let i = members.firstIndex(where: { $0.name == m.name }) { members[i] = m } else { members.append(m) } }
        for c in n.kids {
            switch c.kind {
            case "pair":
                guard let k = c.field("key"), let name = keyName(k), let v = c.field("value") else { continue }
                upsert(NJSObjMember(name: name, ty: ty(v).widened, res: memberRes(k, name, c)))
            case "shorthand_property_identifier":
                upsert(NJSObjMember(name: c.text(ns), ty: ty(c).widened, res: memberRes(c, c.text(ns), c)))
            case "method_definition":
                guard let k = c.field("name"), let name = keyName(k) else { continue }
                upsert(NJSObjMember(name: name, ty: .fn(fnType(c)), res: memberRes(k, name, c)))
            case "spread_element":
                if let inner = c.kids.first { for m in typer.allMembers(of: ty(inner)) { upsert(NJSObjMember(name: m.name, ty: m.ty, optional: m.optional, res: m.res)) } }
            default: break
            }
        }
        return .obj(NJSObj(members, path: env.path))
    }

    private func keyName(_ k: Node) -> String? {
        switch k.kind {
        case "property_identifier", "private_property_identifier", "identifier": return k.text(ns)
        case "string": return k.kids.first?.text(ns) ?? ""
        case "number": return k.text(ns)
        default: return nil
        }
    }

    private func memberRes(_ key: Node, _ name: String, _ decl: Node) -> NJSRes {
        NJSRes(path: env.path, member: NJSMember(name: name, kind: .property, loc: key.start, len: key.range.length, declStart: decl.start, sigEnd: decl.end), owner: nil)
    }

    // MARK: functions

    func fnType(_ f: Node) -> NJSFn {
        var sc = scope(at: f)
        var tps: [String] = []
        if let tp = f.field("type_parameters") { for t in tp.kids where t.kind == "type_parameter" { if let nm = t.field("name")?.text(ns) { tps.append(nm); sc.tparams.insert(nm) } } }
        let info = typer.tparamInfo(f.field("type_parameters"), ns, sc)
        var params: [NJSTParam] = []
        if let p = f.field("parameters") ?? f.field("parameter") {
            if p.kind == "identifier" { params.append(NJSTParam(name: p.text(ns), ty: paramType(p, fn: f, index: 0))) }
            else {
                for (i, c) in p.kids.enumerated() {
                    let idNode: Node? = c.field("pattern") ?? c
                    var name = "arg\(i)"
                    var rest = false
                    if let id = idNode {
                        if id.kind == "rest_pattern" { rest = true; name = id.kids.first?.text(ns) ?? name }
                        else if id.kind == "identifier" { name = id.text(ns) }
                        else if id.kind == "assignment_pattern", let l = id.field("left"), l.kind == "identifier" { name = l.text(ns) }
                    }
                    if name == "this" { continue }
                    var t = paramType(c, fn: f, index: i)
                    if rest, case .array = t {} else if rest { t = .array(t) }
                    params.append(NJSTParam(name: name, ty: t, optional: c.kind == "optional_parameter" || c.field("value") != nil || c.kind == "assignment_pattern", rest: rest))
                }
            }
        }
        var ret: NJSTy
        if let rt = f.field("return_type") { ret = typer.convert(rt, ns, sc) }
        else { ret = inferReturn(f) }
        if f.allKids.contains(where: { $0.kind == "async" }), !(f.field("return_type") != nil) { ret = .ref(NJSTRef("Promise", scope: env.path, args: [typer.awaited(ret)])) }
        return NJSFn(tparams: tps, params: params, ret: ret, constraints: info.constraints, defaults: info.defaults)
    }

    private func inferReturn(_ f: Node) -> NJSTy {
        guard let body = f.field("body") else { return .any }                  // a declaration without annotation or body is `any`
        if body.kind != "statement_block" { return ty(body).widened }
        var types: [NJSTy] = []
        var stack = body.kids
        var visited = 0
        while let n = stack.popLast(), visited < 3000 {
            visited += 1
            if n.kind == "return_statement" { types.append(n.kids.first.map { ty($0).widened } ?? .undefined); continue }
            if ["function_declaration", "function_expression", "function", "arrow_function", "generator_function", "generator_function_declaration", "method_definition", "class_declaration", "class"].contains(n.kind) { continue }
            stack.append(contentsOf: n.kids)
        }
        if types.isEmpty { return .void }
        if types.contains(where: { $0.isUnknown }) { return .unknown }
        return NJSTy.union(of: types.reversed())
    }

    /// Type of the parameter `p` (a required / optional parameter node, an identifier, a pattern) of function `fn`.
    private func paramType(_ p: Node, fn: Node, index: Int) -> NJSTy {
        if let ann = p.field("type") { return typer.convert(ann, ns, scope(at: fn)) }
        if let def = p.field("value") { return ty(def).widened }
        if p.kind == "assignment_pattern", let r = p.field("right") { return ty(r).widened }
        if let ctx = contextualParam(fn: fn, index: index) { return ctx }
        return .any
    }

    // MARK: bindings

    func typeOfBinding(_ b: NJSLocal) -> NJSTy {
        let d = b.declNode
        switch d.kind {
        case "variable_declarator":
            guard let pat = d.field("name") else { return .unknown }
            var base: NJSTy
            if let ann = d.field("type") { base = typer.convert(ann, ns, scope(at: d)) }
            else if let v = d.field("value") {
                base = ty(v)
                if b.keyword != "const" { base = base.widened }
                if let kw = b.keyword, kw == "const", case .obj = base {} 
            } else { return .any }
            if pat.kind == "identifier" { return base }
            return patternType(pat, base: base, target: b.nameNode) ?? .unknown
        case "required_parameter", "optional_parameter":
            guard let pat = d.field("pattern") else { return .unknown }
            let fn = enclosingFunction(d)
            let idx = (d.parent?.kids.firstIndex(where: { $0 == d }) ?? 0)
            var t: NJSTy
            if let ann = d.field("type") { t = typer.convert(ann, ns, scope(at: d)) }
            else if let def = d.field("value") { t = ty(def).widened }
            else if let f = fn, let c = contextualParam(fn: f, index: idx) { t = c } else { t = .any }
            if pat.kind == "identifier" { return t }
            if pat.kind == "rest_pattern" { if case .array = t { return t }; return .array(t) }
            return patternType(pat, base: t, target: b.nameNode) ?? .unknown
        case "identifier":                                           // `x => ...`, `function (a, b)` JS parameters
            guard let f = enclosingFunction(d) else { return .any }
            let idx = (f.field("parameters") ?? f.field("parameter")).map { $0.kind == "identifier" ? 0 : ($0.kids.firstIndex(where: { $0 == d }) ?? 0) } ?? 0
            return contextualParam(fn: f, index: idx) ?? .any
        case "assignment_pattern", "object_pattern", "array_pattern", "rest_pattern":
            guard let f = enclosingFunction(d) else { return .unknown }
            let list = (f.field("parameters") ?? f.field("parameter"))
            var top: Node = d
            while let p = top.parent, p != list, p.kind != "formal_parameters" { top = p }
            let idx = list?.kids.firstIndex(where: { $0 == top }) ?? 0
            var t: NJSTy = .any
            if let c = contextualParam(fn: f, index: idx) { t = c }
            return patternType(top, base: t, target: b.nameNode) ?? .unknown
        case "for_in_statement":
            let isOf = d.allKids.contains { $0.kind == "of" }
            guard isOf, let r = d.field("right") else { return .string }
            let elem = elementType(of: ty(r))
            if let l = d.field("left"), l.kind != "identifier" { return patternType(l, base: elem, target: b.nameNode) ?? .unknown }
            return elem
        case "catch_clause": return .any
        case "function_declaration", "generator_function_declaration": return .fn(fnType(d))
        case "class_declaration", "abstract_class_declaration": return typer.valueType(of: [env.resolve(b)])
        default: return .unknown
        }
    }

    private func enclosingFunction(_ n: Node) -> Node? {
        var p = n.parent
        while let c = p {
            if ["arrow_function", "function_expression", "function", "function_declaration", "generator_function", "generator_function_declaration", "method_definition"].contains(c.kind) { return c }
            p = c.parent
        }
        return nil
    }

    /// Type bound to `target` inside the destructuring `pattern` of a value of type `base`.
    func patternType(_ pattern: Node, base: NJSTy, target: Node) -> NJSTy? {
        guard pattern.start <= target.start, target.end <= pattern.end else { return nil }
        switch pattern.kind {
        case "identifier", "shorthand_property_identifier_pattern": return pattern == target ? base : nil
        case "assignment_pattern":
            guard let l = pattern.field("left") else { return nil }
            let t = patternType(l, base: base.withoutNullish.isUnknown ? base : base.withoutNullish, target: target)
            return t
        case "rest_pattern":
            guard let inner = pattern.kids.first else { return nil }
            return patternType(inner, base: base, target: target)
        case "object_pattern":
            for c in pattern.kids {
                guard c.start <= target.start, target.end <= c.end else { continue }
                switch c.kind {
                case "shorthand_property_identifier_pattern":
                    return c == target ? (typer.members(of: base.withoutNullish, name: c.text(ns)).first?.ty ?? .unknown) : nil
                case "object_assignment_pattern":
                    guard let l = c.field("left") else { return nil }
                    return l == target ? (typer.members(of: base.withoutNullish, name: l.text(ns)).first?.ty ?? .unknown) : nil
                case "pair_pattern":
                    guard let k = c.field("key"), let v = c.field("value"), let kn = keyName(k) else { return nil }
                    let sub = typer.members(of: base.withoutNullish, name: kn).first?.ty ?? .unknown
                    return patternType(v, base: sub, target: target)
                case "rest_pattern":
                    return base
                default: return nil
                }
            }
            return nil
        case "array_pattern":
            var idx = 0
            for c in pattern.kids {
                if c.start <= target.start, target.end <= c.end {
                    var elem: NJSTy
                    switch base {
                    case .tuple(let l): elem = idx < l.count ? l[idx] : .undefined
                    case .array(let e): elem = e
                    default: elem = elementType(of: base)
                    }
                    if c.kind == "rest_pattern" { return .array(elementType(of: base)) }
                    return patternType(c, base: elem, target: target)
                }
                idx += 1
            }
            return nil
        default: return nil
        }
    }

    /// The type produced by iterating a value (for-of, spread, array destructuring).
    func elementType(of t: NJSTy) -> NJSTy {
        switch t {
        case .array(let e): return e
        case .tuple(let l): return NJSTy.union(of: l)
        case .string, .strLit: return .string
        case .ref(let r) where (r.name == "Set" || r.name == "ReadonlySet" || r.name == "Iterable" || r.name == "IterableIterator" || r.name == "Generator" || r.name == "ReadonlyArray") && !r.args.isEmpty: return r.args[0]
        case .ref(let r) where (r.name == "Map" || r.name == "ReadonlyMap") && r.args.count == 2: return .tuple(r.args)
        case .union(let l): return NJSTy.union(of: l.filter { !$0.nullish }.map { elementType(of: $0) })
        case .any: return .any
        default: return .unknown
        }
    }

    // MARK: this

    private func thisType(_ n: Node) -> NJSTy {
        var p = n.parent
        while let c = p {
            switch c.kind {
            case "class_declaration", "abstract_class_declaration":
                guard let nm = c.field("name")?.text(ns) else { return .unknown }
                let decls = env.resolveTop(env.path, nm).filter { $0.path == env.path && $0.kind == .class }
                guard let d = decls.first else { return .unknown }
                let ref = NJSTRef(nm, scope: env.path, args: d.tparams.map { .tparam($0) })
                ref.decls = decls
                return .ref(ref)
            case "function_expression", "function_declaration", "generator_function", "generator_function_declaration", "class": return .unknown
            case "method_definition":
                if c.parent?.kind != "class_body" { return .unknown }
                p = c.parent
            default: p = c.parent
            }
        }
        return .unknown
    }

    // MARK: members and calls

    private func memberType(_ n: Node) -> NJSTy {
        guard let o = n.field("object"), let p = n.field("property") else { return .unknown }
        var base = ty(o)
        let optional = n.allKids.contains { $0.kind == "optional_chain" || $0.text(ns) == "?." }
        if optional { base = base.withoutNullish }
        let hits = typer.members(of: base, name: p.text(ns))
        guard !hits.isEmpty else { return base.isAny ? .any : .unknown }
        let t = mergeHits(hits)
        return optional ? NJSTy.union(of: [t, .undefined]) : t
    }

    /// One type for the declarations found for a member (overloads of a method become an overload set).
    func mergeHits(_ hits: [NJSMemberHit]) -> NJSTy { NJSInfer.mergeTypes(hits) }

    static func mergeTypes(_ hits: [NJSMemberHit]) -> NJSTy {
        let fns = hits.compactMap { h -> [NJSFn]? in
            switch h.ty { case .fn(let f): return [f]; case .overloads(let l): return l; default: return nil }
        }
        if fns.count == hits.count, fns.count > 1 { return .overloads(fns.flatMap { $0 }) }
        return hits[0].ty
    }

    private func subscriptType(_ n: Node) -> NJSTy {
        guard let o = n.field("object"), let idx = n.field("index") ?? n.kids.dropFirst().first else { return .unknown }
        let base = ty(o).withoutNullish
        let i = ty(idx)
        switch base {
        case .array(let e): return e
        case .tuple(let l): if case .numLit(let v) = i, let k = Int(v), k < l.count { return l[k] }; return NJSTy.union(of: l)
        case .string, .strLit: return .string
        default:
            if case .strLit(let k) = i { return typer.members(of: base, name: k).first?.ty ?? .unknown }
            return .unknown
        }
    }

    private func binaryType(_ n: Node) -> NJSTy {
        guard let l = n.field("left"), let r = n.field("right") else { return .unknown }
        let op = n.field("operator")?.text(ns) ?? ""
        switch op {
        case "+":
            let a = ty(l).widened, b = ty(r).widened
            if case .string = a { return .string }
            if case .string = b { return .string }
            if case .number = a, case .number = b { return .number }
            if case .bigint = a, case .bigint = b { return .bigint }
            if a.isAny || b.isAny { return .any }
            return .unknown
        case "-", "*", "/", "%", "**", "&", "|", "^", "<<", ">>", ">>>":
            if case .bigint = ty(l).widened { return .bigint }
            return .number
        case "==", "===", "!=", "!==", "<", ">", "<=", ">=", "instanceof", "in": return .boolean
        case "&&":
            let a = ty(l)
            return NJSTy.union(of: [falsyPart(a), ty(r)])
        case "||":
            return NJSTy.union(of: [truthyPart(ty(l)), ty(r)])
        case "??": return NJSTy.union(of: [ty(l).withoutNullish, ty(r)])
        default: return .unknown
        }
    }

    private func truthyPart(_ t: NJSTy) -> NJSTy {
        switch t {
        case .undefined, .null, .void, .boolLit(false): return .never
        case .boolean: return .boolLit(true)
        case .union(let l): return NJSTy.union(of: l.map { truthyPart($0) })
        default: return t
        }
    }

    private func falsyPart(_ t: NJSTy) -> NJSTy {
        switch t {
        case .undefined, .null, .void, .boolLit(false): return t
        case .boolean: return .boolLit(false)
        case .string: return .strLit("")
        case .number: return .numLit("0")
        case .union(let l): return NJSTy.union(of: l.map { falsyPart($0) })
        case .strLit(let s): return s.isEmpty ? t : .never
        case .any, .unknown: return t
        default: return .never
        }
    }

    // MARK: calls

    private func signatures(of t: NJSTy, constructing: Bool) -> [NJSFn] {
        switch t {
        case .fn(let f): return constructing ? [] : [f]
        case .overloads(let l): return constructing ? [] : l
        case .ref, .obj:
            let hits = typer.members(of: t, name: constructing ? "new" : "()")
            return hits.flatMap { h -> [NJSFn] in
                switch h.ty { case .fn(let f): return [f]; case .overloads(let l): return l; default: return [] }
            }
        case .union(let l): return l.filter { !$0.nullish }.flatMap { signatures(of: $0, constructing: constructing) }
        default: return []
        }
    }

    private func argumentNodes(_ call: Node) -> [Node] { call.field("arguments")?.kids ?? [] }

    static func primitiveLike(_ t: NJSTy) -> Bool {
        switch t {
        case .string, .number, .boolean, .bigint, .symbol, .strLit, .numLit, .boolLit: return true
        case .union(let l): return l.allSatisfy { primitiveLike($0) }
        default: return false
        }
    }

    /// tsc keeps a literal candidate only when T is a bare parameter type, appears at the top level of the return type and has no
    /// constraint; otherwise it is widened (a constrained parameter with a literal candidate is not decided here).
    func settle(_ sig: NJSFn, _ binds: [String: NJSTy], args: [Node]) -> [String: NJSTy] {
        var out = binds
        let fnArg = args.contains { $0.kind == "arrow_function" || $0.kind == "function_expression" || $0.kind == "function" }
        for tp in sig.tparams {
            guard let b = binds[tp] else { continue }
            let widened = b.widened
            if NJSTy.key(widened) == NJSTy.key(b) { continue }
            if let c = sig.constraints[tp], NJSInfer.primitiveLike(c) { continue }          // `T extends string` keeps 'a'
            let bare = sig.params.allSatisfy { p in
                guard p.ty.mentions(tp) else { return true }
                if case .tparam = p.ty { return true }
                if p.rest, case .array(let e) = p.ty, case .tparam = e { return true }
                return false
            }
            out[tp] = (bare && !fnArg && sig.ret.hasAtTopLevel(tp)) ? b : widened
        }
        return out
    }

    /// Chooses the overload for the arguments and returns it with its inferred type arguments. When an earlier overload cannot be
    /// ruled out and would answer differently from the one that fits, the call is undecided (nil).
    func resolveCall(_ sigs: [NJSFn], args: [Node], typeArgs: Int = 0, skipFns: Bool = false) -> (NJSFn, [String: NJSTy])? {
        var maybes: [(NJSFn, [String: NJSTy])] = []
        for sig in sigs {
            if typeArgs > 0, sig.tparams.count != typeArgs { continue }
            let required = sig.params.filter { !$0.optional && !$0.rest }.count
            let hasRest = sig.params.contains { $0.rest }
            if args.count < required || (!hasRest && args.count > sig.params.count) { continue }
            var binds: [String: NJSTy] = [:]
            var failed = false, certain = true
            // arguments that are not functions first, so callbacks see the parameters bound by them
            for pass in 0..<2 {
                for (i, a) in args.enumerated() {
                    let isFn = a.kind == "arrow_function" || a.kind == "function_expression" || a.kind == "function"
                    if (pass == 0) == isFn || (isFn && skipFns) { continue }
                    guard let p = paramFor(sig, index: i) else { continue }
                    let at = ty(a)
                    let want = p.substituting(binds)
                    if !isFn, !want.hasTParam() {                                         // a bare type parameter takes anything; its constraint is checked below
                        switch typer.assignable(at, to: want) { case false?: failed = true; case nil: certain = false; default: break }
                    }
                    if failed { break }
                    p.unify(at, into: &binds)
                }
                if failed { break }
            }
            if failed { continue }
            let settled = settle(sig, binds, args: args)
            for (tp, c) in sig.constraints {                                            // inferred type arguments must satisfy their constraints
                guard let b = settled[tp] else { continue }
                switch typer.assignable(b, to: c.substituting(settled)) { case false?: failed = true; case nil: certain = false; default: break }
            }
            if failed { continue }
            if certain {
                if maybes.isEmpty { return (sig, settled) }
                let all = maybes + [(sig, settled)]
                return sameAnswer(all) ? (sig, settled) : nil
            }
            maybes.append((sig, settled))
        }
        if maybes.isEmpty { return nil }
        return sameAnswer(maybes) ? maybes[0] : nil
    }

    private func sameAnswer(_ list: [(NJSFn, [String: NJSTy])]) -> Bool {
        let texts = list.map { typer.settle($0.0.ret.substituting(completed($0.1, sig: $0.0, own: $0.0.tparams))).describe() }
        return Set(texts).count == 1
    }

    private func paramFor(_ sig: NJSFn, index i: Int) -> NJSTy? {
        if i < sig.params.count, !sig.params[i].rest { return sig.params[i].ty }
        if let last = sig.params.last, last.rest { if case .array(let e) = last.ty { return e }; return last.ty }
        return nil
    }

    /// Type arguments written at a call (`f<string>(x)`, `new Map<string, number>()`) bound to the signature's parameters.
    private func explicitBinds(_ call: Node, _ sig: NJSFn) -> [String: NJSTy]? {
        guard let ta = call.field("type_arguments") else { return [:] }
        let given = ta.kids.map { typer.convert($0, ns, scope(at: call)) }
        guard given.count <= sig.tparams.count else { return nil }
        var out: [String: NJSTy] = [:]
        for (i, g) in given.enumerated() { out[sig.tparams[i]] = g }
        return out
    }

    private func callType(_ n: Node) -> NJSTy {
        guard let f = n.field("function") else { return .unknown }
        if f.kind == "import" { return .ref(NJSTRef("Promise", scope: env.path, args: [.unknown])) }
        if f.kind == "super" { return .void }
        if f.kind == "identifier", f.text(ns) == "require", env.localBinding("require", from: f) == nil,
           let a = argumentNodes(n).first, a.kind == "string", let spec = a.kids.first?.text(ns), let target = env.resolveModule(spec, from: env.path), NJSEnv.isCode(target) { return .ns(target) }
        let callee = ty(f)
        let sigs = signatures(of: callee, constructing: false)
        guard let (sig, inferred) = resolveCall(sigs, args: argumentNodes(n), typeArgs: n.field("type_arguments")?.kids.count ?? 0) else { return callee.isAny ? .any : .unknown }
        guard let given = explicitBinds(n, sig) else { return .unknown }
        return typer.settle(sig.ret.substituting(completed(inferred.merging(given) { _, g in g }, sig: sig, own: sig.tparams)))
    }

    /// Substitutes the inferred type arguments; parameters nothing bound become unknown.
    private func finish(_ t: NJSTy, binds: [String: NJSTy], own: [String]) -> NJSTy {
        return t.substituting(completed(binds, sig: nil, own: own))
    }

    /// Type parameters nothing was inferred for: their default, else their constraint, else unknown.
    func completed(_ binds: [String: NJSTy], sig: NJSFn?, own: [String]) -> [String: NJSTy] {
        var env2 = binds
        for p in own where env2[p] == nil {
            if let d = sig?.defaults[p] { env2[p] = d.substituting(env2) }
            else if let c = sig?.constraints[p] { env2[p] = c.substituting(env2) }
            else { env2[p] = .unknown }
        }
        return env2
    }

    private func newType(_ n: Node) -> NJSTy {
        guard let c = n.field("constructor") else { return .unknown }
        let callee = ty(c)
        let args = argumentNodes(n)
        switch callee {
        case .classCtor(let r) where r.kind == .class:
            var targs: [NJSTy] = []
            if !r.tparams.isEmpty {
                var binds: [String: NJSTy] = [:]
                let ctors = typer.members(of: callee, name: "constructor")                     // static lookup misses it: use instance side
                _ = ctors
                let ctorRes = env.members(of: r, name: "constructor", isStatic: false)
                if let cr = ctorRes.first, let sig = cr.sigText, let f = typer.parseSignature(sig, scope: NJSTyper.Scope(path: cr.path, tenv: [:], tparams: Set(r.tparams))) {
                    for (i, a) in args.enumerated() { if let p = paramFor(f, index: i) { p.unify(ty(a), into: &binds) } }
                    binds = settle(f, binds, args: args)
                }
                if let ta = n.field("type_arguments") {
                    let given = ta.kids.map { typer.convert($0, ns, scope(at: n)) }
                    targs = r.tparams.enumerated().map { $0.offset < given.count ? given[$0.offset] : (binds[$0.element] ?? .any) }
                } else { targs = r.tparams.map { binds[$0] ?? .any } }
            }
            let ref = NJSTRef(r.name, scope: r.path, args: targs)
            ref.decls = [r]
            return .ref(ref)
        case .ref, .obj, .overloads, .fn:
            let sigs = signatures(of: callee, constructing: true)
            guard let (sig, inferred) = resolveCall(sigs, args: args, typeArgs: n.field("type_arguments")?.kids.count ?? 0), let given = explicitBinds(n, sig) else { return .unknown }
            var env2 = inferred.merging(given) { _, g in g }
            for p in sig.tparams where env2[p] == nil && sig.defaults[p] == nil && sig.constraints[p] == nil { env2[p] = .any }      // `new Map()` is Map<any, any>
            return typer.settle(sig.ret.substituting(completed(env2, sig: sig, own: sig.tparams)))
        default: return .unknown
        }
    }

    // MARK: contextual typing of callbacks

    /// The parameter type a function expression gets from the call it is an argument of.
    private func contextualParam(fn: Node, index: Int) -> NJSTy? {
        guard let args = fn.parent, args.kind == "arguments", let call = args.parent, call.kind == "call_expression" || call.kind == "new_expression" else { return nil }
        let nodes = args.kids
        guard let pos = nodes.firstIndex(where: { $0 == fn }) else { return nil }
        let calleeNode = call.field(call.kind == "new_expression" ? "constructor" : "function")
        guard let cn = calleeNode else { return nil }
        let callee = ty(cn)
        let sigs = signatures(of: callee, constructing: call.kind == "new_expression")
        guard let (sig, binds) = resolveCall(sigs, args: nodes, typeArgs: call.field("type_arguments")?.kids.count ?? 0, skipFns: true), let pt0 = paramFor(sig, index: pos) else { return nil }
        let pt = typer.settle(pt0.substituting(completed(binds, sig: sig, own: sig.tparams)))
        var f: NJSFn?
        switch typer.expand(pt) {
        case .fn(let x): f = x
        case .union(let l): for alt in l { if case .fn(let x) = typer.expand(alt) { f = x; break } }
        default: break
        }
        guard let f, index < f.params.count || f.params.last?.rest == true else { return nil }
        if index < f.params.count { return f.params[index].ty }
        if let last = f.params.last { if case .array(let e) = last.ty { return e }; return last.ty }
        return nil
    }
}

// MARK: environment hooks

extension NJSTyper {
    /// The function type of a declaration: its signature text when that states a return type, else the syntax tree of its body.
    func fnType(of r: NJSRes, scope sc: Scope) -> NJSFn? {
        if let s = r.sigText, !s.hasSuffix(")") { return parseSignature(s, scope: sc) }
        if r.loc >= 0, let e = envFor(path: r.path), let leaf = e.doc.leaf(at: r.loc) {
            var n: Node? = leaf
            for _ in 0..<4 {
                guard let c = n else { break }
                switch c.kind {
                case "function_declaration", "generator_function_declaration", "method_definition", "function_signature", "arrow_function", "function_expression", "function", "generator_function":
                    if c.field("name") != nil || c.kind == "arrow_function" || c.kind.hasPrefix("function") || c.kind == "generator_function" { return e.infer.fnType(c) }
                case "variable_declarator", "public_field_definition", "field_definition", "pair":
                    if let v = c.field("value"), ["arrow_function", "function_expression", "function", "generator_function"].contains(v.kind) { return e.infer.fnType(v) }
                default: break
                }
                n = c.parent
            }
        }
        return r.sigText.flatMap { parseSignature($0, scope: sc) }
    }

    /// The environment of another file (parsed once per request) for reading an initializer.
    func envFor(path p: String) -> NJSEnv? {
        let real = NJSTypes.realPath(p)
        if real == env.path { return env }
        if let e = otherEnvs[real] { return e }
        guard !NJSLib.isLibPath(real), otherEnvs.count < 6, let text = FastProject.read(real), let d = NJSDoc(path: real, text: text, maxChars: 1_000_000, skipMinified: true) else { return nil }
        let e = NJSEnv(proj: env.proj, doc: d)
        otherEnvs[real] = e
        return e
    }

    /// The type of a declaration that has no annotation: its initializer, evaluated in its own file.
    func initializerType(of r: NJSRes) -> NJSTy? {
        let key = r.path + ":" + String(r.loc)
        guard !exhausted, inferring.insert(key).inserted else { return nil }
        defer { inferring.remove(key) }
        guard r.loc >= 0, let e = envFor(path: r.path), let leaf = e.doc.leaf(at: r.loc) else { return nil }
        var n: Node? = leaf
        var value: Node?
        var mutable = true
        while let c = n, value == nil {
            switch c.kind {
            case "variable_declarator":
                value = c.field("value")
                if let kw = c.parent?.allKids.first?.text(e.doc.text) { mutable = kw != "const" }
                if let pat = c.field("name"), pat.kind != "identifier" {                      // destructuring: the part of the value this name binds
                    guard let v = value else { return nil }
                    let whole = e.infer.ty(v)
                    return e.infer.patternType(pat, base: mutable ? whole.widened : whole, target: leaf)
                }
            case "public_field_definition", "field_definition": value = c.field("value")
            case "pair": value = c.field("value")
            case "assignment_expression": value = c.field("right")
            case "program", "statement_block", "class_body": n = nil; continue
            default: break
            }
            n = c.parent
        }
        guard let v = value else { return nil }
        let t = e.infer.ty(v)
        return mutable ? t.widened : t
    }
}
