import Foundation
import SwiftTreeSitter

/// Go to definition / hover at an offset of a parsed file.
extension PyResolver {
    /// Identifier node at `offset` (or ending exactly there).
    static func identifier(in root: Node, ns: NSString, at offset: Int) -> PN? {
        for off in [offset, offset - 1] where off >= 0 && off < ns.length {
            guard let n = root.descendant(in: UInt32(off * 2)..<UInt32(off * 2 + 2)) else { continue }
            if n.nodeType == "identifier" { return PN(n: n, ns: ns) }
        }
        return nil
    }

    private func targets(_ imp: Imp) -> [NPTarget] {
        switch imp {
        case .module(let loc): return moduleTarget(loc).map { [$0] } ?? []
        case .syms(let l): return l.compactMap { s in ctx.file(s.path).map { $0.target(s) } }
        case .none: return []
        }
    }

    func moduleTarget(_ loc: PyCtx.Loc) -> NPTarget? {
        if case .file(let p) = loc, let f = ctx.file(p) { return f.moduleTarget() }
        return nil
    }

    private func kindName(_ s: PySym) -> String {
        switch s.kind {
        case .cls: return "class"
        case .fn: return s.isProperty ? "property" : (s.scope?.kind == .cls ? "method" : "function")
        case .variable: return "variable"
        case .param: return "parameter"
        case .imp: return "import"
        case .attr: return "attribute"
        }
    }

    private func hit(range: NSRange, imp: Imp, moduleName: String) -> NPHit? {
        let t = targets(imp)
        switch imp {
        case .module(let loc):
            return NPHit(range: range, targets: t, markdown: PyDocs.moduleMarkdown(loc, name: moduleName, self), kind: "module")
        case .syms(let l):
            guard let s = l.first else { return nil }
            return NPHit(range: range, targets: t, markdown: PyDocs.markdown(for: s, self), kind: kindName(s))
        case .none: return nil
        }
    }

    private func hit(range: NSRange, members: [PyMemberHit], name: String) -> NPHit? {
        var ts: [NPTarget] = []
        var first: NPHit?
        for m in members.prefix(6) {
            if let s = m.sym, let f = ctx.file(s.path) {
                ts.append(f.target(s))
                if first == nil { first = NPHit(range: range, targets: [], markdown: PyDocs.markdown(for: s, self), kind: kindName(s)) }
            } else if let loc = m.module {
                if let t = moduleTarget(loc) { ts.append(t) }
                if first == nil { first = NPHit(range: range, targets: [], markdown: PyDocs.moduleMarkdown(loc, name: name, self), kind: "module") }
            }
        }
        guard var h = first else { return nil }
        h.targets = ts
        return h
    }

    /// (module, level) of an `import_from_statement`.
    func fromModule(_ stmt: PN) -> (String, Int) {
        guard let m = stmt.field("module_name") else { return ("", 0) }
        if m.type == "relative_import" {
            let level = m.first("import_prefix").map { $0.text.filter { $0 == "." }.count } ?? 1
            return (m.first("dotted_name")?.text ?? "", level)
        }
        return (m.text, 0)
    }

    func lookupHit(file: PyFile, root: Node, ns: NSString, offset: Int) -> NPHit? {
        guard let ident = Self.identifier(in: root, ns: ns, at: offset) else { return nil }
        let name = ident.text
        let range = ident.r
        let parent = ident.parent

        // import statements
        if let p = parent, p.type == "dotted_name", let gp = p.parent {
            let comps = p.named
            let idx = comps.firstIndex { $0.n.id == ident.n.id } ?? 0
            let joined = comps[0...idx].map { $0.text }.joined(separator: ".")
            switch gp.type {
            case "import_statement":
                return hit(range: range, imp: ctx.resolveModule(joined, level: 0, from: file.path).map { .module($0) } ?? .none, moduleName: joined)
            case "aliased_import":
                if let ggp = gp.parent, ggp.type == "import_statement" {
                    return hit(range: range, imp: ctx.resolveModule(joined, level: 0, from: file.path).map { .module($0) } ?? .none, moduleName: joined)
                }
                if let ggp = gp.parent, ggp.type == "import_from_statement" { return importedName(ggp, name: comps.map { $0.text }.joined(separator: "."), range: range, file: file) }
            case "relative_import":
                if let stmt = gp.parent, stmt.type == "import_from_statement" {
                    let (_, level) = fromModule(stmt)
                    return hit(range: range, imp: ctx.resolveModule(joined, level: level, from: file.path).map { .module($0) } ?? .none, moduleName: joined)
                }
            case "import_from_statement":
                if let mn = gp.field("module_name"), mn.n.id == p.n.id {
                    return hit(range: range, imp: ctx.resolveModule(joined, level: 0, from: file.path).map { .module($0) } ?? .none, moduleName: joined)
                }
                return importedName(gp, name: name, range: range, file: file)
            default: break
            }
        }
        if let p = parent, p.type == "aliased_import", let stmt = p.parent {
            if let al = p.field("alias"), al.n.id == ident.n.id {                         // `... as alias`
                if let sym = file.declByOff[ident.start], sym.kind == .imp { return hit(range: range, imp: resolveImport(sym), moduleName: sym.impModule) }
            } else if stmt.type == "import_from_statement" {
                return importedName(stmt, name: name, range: range, file: file)
            }
        }

        // declarations: the identifier is itself a binding
        if let sym = file.declByOff[ident.start] {
            if sym.kind == .imp { return hit(range: range, imp: resolveImport(sym), moduleName: sym.impModule) }
            guard let f = ctx.file(sym.path) else { return nil }
            return NPHit(range: range, targets: [f.target(sym)], markdown: PyDocs.markdown(for: sym, self), kind: kindName(sym))
        }

        let scope = file.root.innermost(at: ident.start)
        // obj.name
        if let p = parent, p.type == "attribute", let a = p.field("attribute"), a.n.id == ident.n.id, let obj = p.field("object") {
            let recv = eval(PyExprMaker.make(obj), scope: scope, file: file)
            return hit(range: range, members: memberTargets(recv, name), name: name)
        }
        // f(name=...)
        if let p = parent, p.type == "keyword_argument", let nm = p.field("name"), nm.n.id == ident.n.id,
           let args = p.parent, args.type == "argument_list", let call = args.parent, call.type == "call", let f = call.field("function") {
            let callee = eval(PyExprMaker.make(f), scope: scope, file: file)
            if let s = keywordParam(callee, name) { return hit(range: range, imp: .syms([s]), moduleName: name) }
            return nil
        }
        if let p = parent, p.type == "keyword_argument", let nm = p.field("name"), nm.n.id == ident.n.id { return nil }
        if let p = parent, p.type == "keyword_pattern" { return nil }
        // plain name
        let syms = lookup(name, scope: scope, off: ident.start, file: file)
        guard !syms.isEmpty else { return nil }
        if syms[0].kind == .imp { return hit(range: range, imp: resolveImport(syms[0]), moduleName: syms[0].impModule) }
        return hit(range: range, imp: .syms(syms), moduleName: name)
    }

    private func importedName(_ stmt: PN, name: String, range: NSRange, file: PyFile) -> NPHit? {
        let (module, level) = fromModule(stmt)
        guard let loc = ctx.resolveModule(module, level: level, from: file.path) else { return nil }
        return hit(range: range, imp: memberOfModule(loc, name), moduleName: name)
    }

    /// Parameter named `name` of a callable (functions, class constructors, instances with __call__).
    func keywordParam(_ callee: PyType, _ name: String) -> PySym? {
        switch callee {
        case .fn(let f): return f.inner?.table[name]?.first(where: { $0.kind == .param })
        case .cls(let c):
            if let m = memberSyms(c, "__init__").first, m.kind == .fn, let p = m.inner?.table[name]?.first(where: { $0.kind == .param }) { return p }
            // dataclass-style fields
            return mro(c).compactMap { $0.inner?.table[name]?.first(where: { $0.kind == .variable && $0.annotation != nil }) }.first
        case .inst(let c):
            if let m = memberSyms(c, "__call__").first, m.kind == .fn { return m.inner?.table[name]?.first(where: { $0.kind == .param }) }
            return nil
        case .sup(let c):
            if let m = memberSyms(c, "__init__", skipSelf: true).first, m.kind == .fn { return m.inner?.table[name]?.first(where: { $0.kind == .param }) }
            return nil
        default: return nil
        }
    }
}
