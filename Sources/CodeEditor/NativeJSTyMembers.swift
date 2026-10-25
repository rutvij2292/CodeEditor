import Foundation
import SwiftTreeSitter

struct NJSMemberHit {
    var res: NJSRes?
    var ty: NJSTy
    var optional = false
}

/// Members of types and the types of declared values.
extension NJSTyper {
    private func libDecls(_ name: String) -> [NJSRes] { env.resolveName(env.path, name) }

    private func apparent(_ t: NJSTy) -> (name: String, args: [NJSTy])? {
        switch t {
        case .string, .strLit: return ("String", [])
        case .number, .numLit: return ("Number", [])
        case .boolean, .boolLit: return ("Boolean", [])
        case .bigint: return ("BigInt", [])
        case .symbol: return ("Symbol", [])
        case .array(let e): return ("Array", [e])
        case .tuple(let l): return ("Array", [NJSTy.union(of: l)])
        case .fn, .overloads: return ("Function", [])
        case .nonPrimitive: return ("Object", [])
        default: return nil
        }
    }

    func tenv(for decl: NJSRes, args: [NJSTy]) -> [String: NJSTy] {
        var e: [String: NJSTy] = [:]
        for (i, p) in decl.tparams.enumerated() {
            if i < args.count { e[p] = args[i]; continue }
            let def = i < decl.tparamDefaults.count ? decl.tparamDefaults[i] : ""
            e[p] = def.isEmpty ? .unknown : parse(text: def, scope: Scope(path: decl.path, tenv: e, tparams: []))       // `interface Ref<T = any, S = T>`
        }
        return e
    }

    /// `Ref<number>` written with fewer arguments than the declaration has parameters gets the declared defaults filled in (`Ref<number, number>`).
    func complete(_ t: NJSTy, depth: Int = 0) -> NJSTy {
        guard depth < 6, !exhausted else { return t }
        switch t {
        case .ref(let r):
            var args = r.args.map { complete($0, depth: depth + 1) }
            if let d = decls(r).first(where: { ($0.kind == .interface || $0.kind == .class || $0.kind == .typeAlias) && $0.tparams.count > args.count }) {
                let te = tenv(for: d, args: args)
                args += d.tparams[args.count...].map { te[$0] ?? .unknown }
            }
            return args.isEmpty ? t : .ref(NJSTRef(r.name, scope: r.scope, args: args))
        case .array(let e): return .array(complete(e, depth: depth + 1))
        case .tuple(let l): return .tuple(l.map { complete($0, depth: depth + 1) })
        case .union(let l): return NJSTy.union(of: l.map { complete($0, depth: depth + 1) })
        case .inter(let l): return .inter(l.map { complete($0, depth: depth + 1) })
        default: return t
        }
    }

    /// The type of a declared member (property, method, accessor) as seen from an instance whose type arguments are in `tenv`.
    func typeOf(member m: NJSRes, tenv: [String: NJSTy]) -> NJSTy {
        steps += 1
        if exhausted { return .unknown }
        let sc = Scope(path: m.path, tenv: tenv, tparams: Set(m.tparams).subtracting(tenv.keys))
        if m.typeText == nil, m.sigText != nil {                          // methods, accessors, arrow-function fields / consts
            guard var f = fnType(of: m, scope: sc) else { return .any }
            if !tenv.isEmpty { f = f.substituting(tenv) }
            if m.kind == .getter || m.accessor == 1 { return f.ret }
            if m.accessor == 2 { return f.params.first?.ty ?? .unknown }
            return .fn(f)
        }
        if let tt = m.typeText { return parse(text: tt, scope: sc) }
        if m.kind == .variable || m.kind == .constant || m.kind == .property, let t = initializerType(of: m), !t.isUnknown { return t }
        if let tn = m.typeName { return .ref(NJSTRef(tn, scope: m.path, args: [])) }
        if m.kind == .enumMember { return .number }
        return initializerType(of: m) ?? .unknown
    }

    // MARK: members of a type

    func members(of t: NJSTy, name: String, depth: Int = 0) -> [NJSMemberHit] {
        guard depth < 8, !exhausted else { return [] }
        steps += 1
        switch t {
        case .obj(let o):
            let own = o.members.filter { $0.name == name }.map { NJSMemberHit(res: o.ambiguous ? nil : $0.res, ty: $0.ty, optional: $0.optional) }
            if !own.isEmpty { return own }
            return nominal(libDecls("Object"), args: [], name: name, depth: depth + 1)
        case .ref:
            let ex = expand(t)
            if case .ref(let r) = ex { return nominal(decls(r).filter { $0.kind == .class || $0.kind == .interface || $0.kind == .enum }, args: r.args, name: name, depth: depth + 1) }
            return members(of: ex, name: name, depth: depth + 1)
        case .union(let l):
            var out: [NJSMemberHit] = []
            for x in l where !x.nullish { out += members(of: x, name: name, depth: depth + 1) }
            return out
        case .inter(let l):
            var out: [NJSMemberHit] = []
            for x in l { out += members(of: x, name: name, depth: depth + 1) }
            return out
        case .classCtor(let r):
            let ms = env.members(of: r, name: name, isStatic: true)
            var out = ms.map { NJSMemberHit(res: $0, ty: typeOf(member: $0, tenv: [:])) }
            if r.kind == .enum { out = ms.map { NJSMemberHit(res: $0, ty: .ref(NJSTRef(r.name, scope: r.path, args: []))) } }
            if out.isEmpty { out = nominal(libDecls("Function"), args: [], name: name, depth: depth + 1) }
            return out
        case .ns(let p):
            return env.exportOf(p, name).map { NJSMemberHit(res: $0, ty: valueType(of: [$0])) }
        default:
            if let a = apparent(t) { return nominal(libDecls(a.name), args: a.args, name: name, depth: depth + 1) }
            return []
        }
    }

    private func nominal(_ decls: [NJSRes], args: [NJSTy], name: String, depth: Int) -> [NJSMemberHit] {
        var out: [NJSMemberHit] = []
        for d in decls where d.kind == .class || d.kind == .interface || d.kind == .enum || d.kind == .namespace {
            let te = tenv(for: d, args: args)
            for m in d.members where m.name == name && (d.kind != .class || !m.isStatic) {
                let r = NJSRes(path: d.path, member: m, owner: d.name, siblings: d.members, ownerParams: d.tparams)
                out.append(NJSMemberHit(res: r, ty: d.kind == .enum ? .ref(NJSTRef(d.name, scope: d.path, args: [])) : typeOf(member: r, tenv: te), optional: m.optional))
            }
        }
        if !out.isEmpty { return out }
        for d in decls {
            let te = tenv(for: d, args: args)
            let heritage = d.heritageFull.isEmpty ? d.heritage : d.heritageFull
            for h in heritage {
                let base = parse(text: h, scope: Scope(path: d.path, tenv: te, tparams: Set(d.tparams).subtracting(te.keys)))
                out += members(of: base, name: name, depth: depth + 1)
                if !out.isEmpty { return out }
            }
        }
        return out
    }

    /// Every member of `t` (own and inherited) with its type, for completion and for utility types.
    func allMembers(of t: NJSTy, depth: Int = 0) -> [(name: String, ty: NJSTy, optional: Bool, res: NJSRes?)] {
        guard depth < 6, !exhausted else { return [] }
        steps += 1
        switch t {
        case .obj(let o): return o.members.map { ($0.name, $0.ty, $0.optional, $0.res) }
        case .ref:
            let ex = expand(t)
            if case .ref(let r) = ex { return nominalAll(decls(r).filter { $0.kind == .class || $0.kind == .interface || $0.kind == .enum }, args: r.args, depth: depth + 1) }
            return allMembers(of: ex, depth: depth + 1)
        case .union(let l):
            // members present in every non-nullish constituent
            let parts = l.filter { !$0.nullish }.map { allMembers(of: $0, depth: depth + 1) }
            guard var common = parts.first else { return [] }
            for p in parts.dropFirst() { let names = Set(p.map { $0.name }); common = common.filter { names.contains($0.name) } }
            return common
        case .inter(let l): return l.flatMap { allMembers(of: $0, depth: depth + 1) }
        case .classCtor(let r):
            return r.members.filter { $0.isStatic || r.kind != .class }.map { m in
                let res = NJSRes(path: r.path, member: m, owner: r.name, siblings: r.members, ownerParams: r.tparams)
                return (m.name, r.kind == .enum ? NJSTy.ref(NJSTRef(r.name, scope: r.path, args: [])) : typeOf(member: res, tenv: [:]), false, res)
            }
        case .ns(let p):
            var names: [(name: String, kind: NJSKind?)] = []
            env.exportNames(p, into: &names)
            return names.map { n in (n.name, NJSTy.unknown, false, nil) }
        default:
            if let a = apparent(t) { return nominalAll(libDecls(a.name), args: a.args, depth: depth + 1) }
            return []
        }
    }

    private func nominalAll(_ decls: [NJSRes], args: [NJSTy], depth: Int) -> [(name: String, ty: NJSTy, optional: Bool, res: NJSRes?)] {
        var out: [(name: String, ty: NJSTy, optional: Bool, res: NJSRes?)] = []
        var seen = Set<String>()
        for d in decls where d.kind == .class || d.kind == .interface || d.kind == .enum {
            let te = tenv(for: d, args: args)
            for m in d.members where m.name != "constructor" && m.name != "new" && m.name != "()" && (d.kind != .class || !m.isStatic) {
                let r = NJSRes(path: d.path, member: m, owner: d.name, siblings: d.members, ownerParams: d.tparams)
                if seen.insert(m.name).inserted { out.append((m.name, typeOf(member: r, tenv: te), m.optional, r)) }
            }
            for h in (d.heritageFull.isEmpty ? d.heritage : d.heritageFull) {
                let base = parse(text: h, scope: Scope(path: d.path, tenv: te, tparams: Set(d.tparams).subtracting(te.keys)))
                for x in allMembers(of: base, depth: depth + 1) where seen.insert(x.name).inserted { out.append(x) }
            }
        }
        return out
    }

    // MARK: values

    /// The type of the value a declaration (or an overload set) introduces.
    func valueType(of res: [NJSRes]) -> NJSTy {
        steps += 1
        if exhausted { return .unknown }
        if res.isEmpty { return .unknown }
        let fns = res.filter { $0.kind == .function || $0.kind == .method }
        if !fns.isEmpty, fns.count == res.count || fns.count > 1 {
            let sigs = (fns.contains { $0.overload } ? fns.filter { $0.overload } : fns).compactMap { r -> NJSFn? in
                guard r.sigText != nil else { return nil }
                return fnType(of: r, scope: Scope(path: r.path, tenv: [:], tparams: []))
            }
            if sigs.count == 1 { return .fn(sigs[0]) }
            if !sigs.isEmpty { return .overloads(sigs) }
            return .any
        }
        for r in res {
            if r.fileTop { return .ns(r.path) }
            switch r.kind {
            case .class, .enum, .namespace: return .classCtor(r)
            case .function, .method: if r.sigText != nil, let f = fnType(of: r, scope: Scope(path: r.path, tenv: [:], tparams: [])) { return .fn(f) }
            case .variable, .constant, .property, .parameter, .getter, .setter, .enumMember:
                let t = typeOf(member: r, tenv: [:])
                if !t.isUnknown { return t }
            default: continue
            }
        }
        return .unknown
    }
}
