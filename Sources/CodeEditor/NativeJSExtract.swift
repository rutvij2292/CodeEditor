import Foundation
import SwiftTreeSitter

/// Turns a parsed JS/TS file into its compact `NJSSummary`: top level declarations (with class / interface / enum / namespace /
/// object-literal members), import bindings, and the export table (ES modules, `export =`, CommonJS). Only offsets are stored.
struct NJSExtractor {
    let doc: NJSDoc
    var ns: NSString { doc.text }

    func extract() -> NJSSummary {
        let s = NJSSummary()
        for n in doc.root.kids { statement(n, s, exp: nil) }
        return s
    }

    // MARK: helpers

    private func docRange(before node: Node) -> (Int, Int) {
        var p = node.previousSibling
        while let c = p, c.kind == "comment" {
            let t = c.text(ns)
            if t.hasPrefix("/**") { return (c.start, c.end) }
            p = c.previousSibling
            if !t.hasPrefix("//") { break }
        }
        return (-1, -1)
    }

    private func stringValue(_ n: Node) -> String? {
        guard n.kind == "string" else { return nil }
        if let f = n.kids.first(where: { $0.kind == "string_fragment" }) { return f.text(ns) }
        let t = n.text(ns)
        return t.count >= 2 ? String(t.dropFirst().dropLast()) : nil
    }

    /// Simple type name of an annotation (`Foo`, `Foo<T>`, `ns.Foo`, `Foo | null`); nil for anything else.
    func typeName(_ node: Node?) -> String? {
        guard var n = node else { return nil }
        if n.kind == "type_annotation" || n.kind == "parenthesized_type" { guard let c = n.kids.first else { return nil }; n = c }
        switch n.kind {
        case "type_identifier", "nested_type_identifier": return n.text(ns)
        case "generic_type": return n.field("name").map { $0.text(ns) }
        case "parenthesized_type": return typeName(n.kids.first)
        case "union_type":
            let parts = n.kids.filter { c in
                let t = c.text(ns)
                return !(t == "null" || t == "undefined" || t == "void")
            }
            return parts.count == 1 ? typeName(parts[0]) : nil
        default: return nil
        }
    }

    func newName(_ value: Node?) -> String? {
        guard let v = value else { return nil }
        if v.kind == "new_expression", let c = v.field("constructor"), c.kind == "identifier" || c.kind == "member_expression" { return c.text(ns) }
        if v.kind == "as_expression" || v.kind == "satisfies_expression" || v.kind == "parenthesized_expression" { return newName(v.kids.first) }
        return nil
    }

    /// Names of the type parameters declared by `node` (`<T, U extends X>`).
    private func typeParams(_ node: Node) -> Set<String> {
        guard let tp = node.field("type_parameters") else { return [] }
        return Set(tp.kids.compactMap { $0.kind == "type_parameter" ? $0.field("name")?.text(ns) : nil })
    }

    private func memberName(_ n: Node?) -> (String, Node)? {
        guard let n else { return nil }
        switch n.kind {
        case "property_identifier", "private_property_identifier", "identifier": return (n.text(ns), n)
        case "string": return stringValue(n).map { ($0, n) }
        default: return nil
        }
    }

    private func sym(_ nameNode: Node, _ kind: NJSKind, outer: Node, sigEnd: Int) -> NJSSym {
        let s = NJSSym(name: nameNode.text(ns), kind: kind, loc: nameNode.start, len: nameNode.range.length, declStart: outer.start, sigEnd: sigEnd)
        (s.docStart, s.docEnd) = docRange(before: outer)
        return s
    }

    // MARK: statements

    private func statement(_ node: Node, _ s: NJSSummary, exp: Node?) {
        switch node.kind {
        case "import_statement": importStatement(node, s)
        case "export_statement": exportStatement(node, s)
        case "expression_statement": commonJS(node, s)
        default:
            for sy in syms(for: node, outer: exp ?? node, ambient: false) {
                if exp != nil { sy.exported = true; s.exports[sy.name] = s.exports[sy.name] ?? .local(sy.name) }
                s.add(sy)
            }
        }
    }

    private func importStatement(_ node: Node, _ s: NJSSummary) {
        s.isModule = true
        guard let src = node.field("source"), let spec = stringValue(src) else {
            // `import x = require('y')`
            if let req = node.kids.first(where: { $0.kind == "import_require_clause" }), let id = req.kids.first(where: { $0.kind == "identifier" }),
               let str = req.kids.first(where: { $0.kind == "string" }), let spec = stringValue(str) {
                let sy = sym(id, .import, outer: node, sigEnd: node.end); sy.impSource = spec; sy.impName = "*"; s.add(sy)
            }
            return
        }
        for clause in node.kids where clause.kind == "import_clause" {
            for c in clause.kids {
                switch c.kind {
                case "identifier":
                    let sy = sym(c, .import, outer: node, sigEnd: node.end); sy.impSource = spec; sy.impName = "default"; s.add(sy)
                case "namespace_import":
                    if let id = c.kids.first(where: { $0.kind == "identifier" }) {
                        let sy = sym(id, .import, outer: node, sigEnd: node.end); sy.impSource = spec; sy.impName = "*"; s.add(sy)
                    }
                case "named_imports":
                    for sp in c.kids where sp.kind == "import_specifier" {
                        guard let name = sp.field("name") else { continue }
                        let local = sp.field("alias") ?? name
                        let sy = sym(local, .import, outer: node, sigEnd: node.end)
                        sy.impSource = spec; sy.impName = name.kind == "string" ? (stringValue(name) ?? "") : name.text(ns)
                        s.add(sy)
                    }
                default: break
                }
            }
        }
    }

    private func exportStatement(_ node: Node, _ s: NJSSummary) {
        s.isModule = true
        let kids = node.allKids
        let isDefault = kids.contains { $0.kind == "default" }
        let source = node.field("source").flatMap { stringValue($0) }
        if let decl = node.field("declaration") {
            let made = syms(for: decl, outer: node, ambient: false)
            for sy in made {
                sy.exported = true
                s.add(sy)
                if !isDefault { s.exports[sy.name] = .local(sy.name) }
            }
            if isDefault {
                if let first = made.first { s.exports["default"] = .local(first.name) }
                else { s.exports["default"] = anon(node, at: decl) }
            }
            return
        }
        if isDefault {
            if let v = node.field("value") {
                if v.kind == "identifier" { s.exports["default"] = .local(v.text(ns)) } else { s.exports["default"] = anon(node, at: v) }
            }
            return
        }
        for c in node.kids {
            switch c.kind {
            case "export_clause":
                for sp in c.kids where sp.kind == "export_specifier" {
                    guard let name = sp.field("name") else { continue }
                    let nm = name.kind == "string" ? (stringValue(name) ?? "") : name.text(ns)
                    let alias = sp.field("alias").map { $0.kind == "string" ? (stringValue($0) ?? "") : $0.text(ns) } ?? nm
                    if let spec = source { s.exports[alias] = .reexport(spec: spec, name: nm) } else { s.exports[alias] = .local(nm) }
                }
            case "namespace_export":
                if let id = c.kids.first, let spec = source { s.exports[id.text(ns)] = .moduleNS(spec: spec) }
            case "identifier":
                s.exportEquals = c.text(ns)           // export = X
            default: break
            }
        }
        if let spec = source, !node.kids.contains(where: { $0.kind == "export_clause" || $0.kind == "namespace_export" }) { s.stars.append(spec) }
    }

    private func anon(_ exp: Node, at n: Node) -> NJSExport {
        let kw = exp.allKids.first { $0.kind == "default" }
        let (d0, d1) = docRange(before: exp)
        return .anon(loc: kw?.start ?? n.start, len: kw?.range.length ?? 1, declStart: exp.start, sigEnd: min(n.end, exp.start + 200), docStart: d0, docEnd: d1)
    }

    // CommonJS: module.exports = ..., module.exports.x = ..., exports.x = ...
    private func commonJS(_ node: Node, _ s: NJSSummary) {
        guard let a = node.kids.first, a.kind == "assignment_expression", let l = a.field("left"), l.kind == "member_expression",
              let obj = l.field("object"), let prop = l.field("property") else { return }
        let r = a.field("right")
        func exportValue(_ key: String, loc: Node, value: Node?) {
            if let v = value, v.kind == "identifier" { s.exports[key] = .local(v.text(ns)) }
            else {
                let (d0, d1) = docRange(before: node)
                s.exports[key] = .anon(loc: loc.start, len: loc.range.length, declStart: node.start, sigEnd: min(node.end, node.start + 200), docStart: d0, docEnd: d1)
            }
        }
        if obj.kind == "identifier", obj.text(ns) == "module", prop.text(ns) == "exports" {
            s.commonJS = true
            exportValue("=", loc: l, value: r)
            if let r, r.kind == "object" {
                for m in r.kids {
                    switch m.kind {
                    case "shorthand_property_identifier": s.exports[m.text(ns)] = .local(m.text(ns))
                    case "pair": if let (k, kn) = memberName(m.field("key")) { exportValue(k, loc: kn, value: m.field("value")) }
                    case "method_definition": if let (k, kn) = memberName(m.field("name")) { exportValue(k, loc: kn, value: nil) }
                    default: break
                    }
                }
            }
        } else if obj.kind == "identifier", obj.text(ns) == "exports" {
            s.commonJS = true
            exportValue(prop.text(ns), loc: prop, value: r)
        } else if obj.kind == "member_expression", let o2 = obj.field("object"), let p2 = obj.field("property"),
                  o2.text(ns) == "module", p2.text(ns) == "exports" {
            s.commonJS = true
            exportValue(prop.text(ns), loc: prop, value: r)
        }
    }

    // MARK: declarations

    func syms(for node: Node, outer: Node, ambient: Bool) -> [NJSSym] {
        switch node.kind {
        case "function_declaration", "generator_function_declaration", "function_signature", "function":
            guard let n = node.field("name") else { return [] }
            let sy = sym(n, .function, outer: outer, sigEnd: node.field("body")?.start ?? node.end)
            sy.typeName = typeName(node.field("return_type"))
            if let t = sy.typeName, typeParams(node).contains(t) { sy.typeName = nil }
            return [sy]
        case "class_declaration", "abstract_class_declaration", "class":
            guard let n = node.field("name") else { return [] }
            let sy = sym(n, .class, outer: outer, sigEnd: node.field("body")?.start ?? node.end)
            for h in node.kids where h.kind == "class_heritage" {
                if let ext = h.kids.first(where: { $0.kind == "extends_clause" }) {
                    if let v = ext.field("value") { sy.heritage.append(v.text(ns)) }
                } else if let v = h.kids.first { sy.heritage.append(v.text(ns)) }
            }
            if let body = node.field("body") { sy.members = classMembers(body, typeParams: typeParams(node)) }
            return [sy]
        case "interface_declaration":
            guard let n = node.field("name") else { return [] }
            let sy = sym(n, .interface, outer: outer, sigEnd: node.field("body")?.start ?? node.end)
            for h in node.kids where h.kind == "extends_type_clause" { for t in h.kids { if let tn = typeName(t) { sy.heritage.append(tn) } } }
            if let body = node.field("body") { sy.members = signatureMembers(body, typeParams: typeParams(node)) }
            return [sy]
        case "type_alias_declaration":
            guard let n = node.field("name") else { return [] }
            let sy = sym(n, .typeAlias, outer: outer, sigEnd: node.end)
            if let v = node.field("value"), v.kind == "object_type" { sy.members = signatureMembers(v, typeParams: typeParams(node)) }
            return [sy]
        case "enum_declaration":
            guard let n = node.field("name") else { return [] }
            let sy = sym(n, .enum, outer: outer, sigEnd: node.field("body")?.start ?? node.end)
            if let body = node.field("body") {
                for m in body.kids {
                    let nameNode = m.kind == "enum_assignment" ? m.field("name") : m
                    guard let (nm, nn) = memberName(nameNode) else { continue }
                    var mem = NJSMember(name: nm, kind: .enumMember, loc: nn.start, len: nn.range.length, declStart: m.start, sigEnd: m.end)
                    (mem.docStart, mem.docEnd) = docRange(before: m)
                    sy.members.append(mem)
                }
            }
            return [sy]
        case "internal_module", "module":
            guard let n = node.field("name"), n.kind == "identifier" || n.kind == "nested_identifier" else { return [] }
            let nameNode = n.kind == "nested_identifier" ? (n.kids.first ?? n) : n
            let sy = sym(nameNode, .namespace, outer: outer, sigEnd: node.field("body")?.start ?? node.end)
            if let body = node.field("body") { sy.members = namespaceMembers(body, ambient: ambient || outer.kind == "ambient_declaration") }
            return [sy]
        case "ambient_declaration":
            var out: [NJSSym] = []
            for c in node.kids { out += syms(for: c, outer: outer.kind == "export_statement" ? outer : node, ambient: true) }
            return out
        case "lexical_declaration", "variable_declaration":
            let kw = node.allKids.first.map { $0.text(ns) } ?? "var"
            var out: [NJSSym] = []
            for d in node.kids where d.kind == "variable_declarator" { out += declarator(d, keyword: kw, outer: outer) }
            return out
        case "expression_statement":
            if let m = node.kids.first, m.kind == "internal_module" || m.kind == "module" { return syms(for: m, outer: outer, ambient: ambient) }
            return []
        default: return []
        }
    }

    private func bindingNodes(_ p: Node, into out: inout [(Node, String?)], imported: String? = nil) {
        switch p.kind {
        case "identifier": out.append((p, imported))
        case "shorthand_property_identifier_pattern": out.append((p, p.text(ns)))
        case "object_pattern":
            for c in p.kids {
                switch c.kind {
                case "shorthand_property_identifier_pattern": out.append((c, c.text(ns)))
                case "pair_pattern":
                    if let v = c.field("value") { bindingNodes(v, into: &out, imported: c.field("key")?.text(ns)) }
                case "object_assignment_pattern":
                    if let l = c.field("left") { bindingNodes(l, into: &out, imported: l.text(ns)) }
                case "rest_pattern": for k in c.kids { bindingNodes(k, into: &out) }
                default: break
                }
            }
        case "array_pattern": for c in p.kids { bindingNodes(c, into: &out) }
        case "assignment_pattern": if let l = p.field("left") { bindingNodes(l, into: &out) }
        case "rest_pattern": for c in p.kids { bindingNodes(c, into: &out) }
        default: break
        }
    }

    private func declarator(_ d: Node, keyword: String, outer: Node) -> [NJSSym] {
        guard let nameNode = d.field("name") else { return [] }
        let value = d.field("value")
        var requireSpec: String?
        if let v = value, v.kind == "call_expression", let f = v.field("function"), f.kind == "identifier", f.text(ns) == "require",
           let a = v.field("arguments"), let str = a.kids.first, let sv = stringValue(str) { requireSpec = sv }
        var out: [NJSSym] = []
        if nameNode.kind == "identifier" {
            let sy = sym(nameNode, keyword == "const" ? .constant : .variable, outer: outer, sigEnd: d.end)
            sy.keyword = keyword
            if let spec = requireSpec { sy.kind = .import; sy.impSource = spec; sy.impName = "="; sy.keyword = nil }
            sy.typeName = typeName(d.field("type")) ?? newName(value)
            if let v = value, v.kind == "object" { sy.members = objectMembers(v) }
            if sy.typeName == nil, let v = value, v.kind == "call_expression", let f = v.field("function"), f.kind == "identifier" || f.kind == "member_expression" { sy.initCall = f.text(ns) }
            out.append(sy)
        } else {
            var bs: [(Node, String?)] = []
            bindingNodes(nameNode, into: &bs)
            for (b, imported) in bs {
                let sy = sym(b, .variable, outer: outer, sigEnd: d.end)
                sy.keyword = keyword
                if let spec = requireSpec, let imp = imported { sy.kind = .import; sy.impSource = spec; sy.impName = imp; sy.keyword = nil }
                out.append(sy)
            }
        }
        return out
    }

    // MARK: members

    private func classMembers(_ body: Node, typeParams tps: Set<String>) -> [NJSMember] {
        var out: [NJSMember] = []
        var seen = Set<String>()
        func add(_ m: NJSMember) { out.append(m); seen.insert((m.isStatic ? "s:" : "i:") + m.name) }
        var ctorBodies: [Node] = []
        for m in body.kids {
            switch m.kind {
            case "method_definition", "abstract_method_signature", "method_signature":
                guard let (nm, nn) = memberName(m.field("name")) else { continue }
                var kind: NJSKind = .method
                var isStatic = false
                for c in m.allKids {
                    if c.start >= nn.start { break }
                    if c.kind == "get" { kind = .getter } else if c.kind == "set" { kind = .setter } else if c.kind == "static" { isStatic = true }
                }
                var mem = NJSMember(name: nm, kind: kind, loc: nn.start, len: nn.range.length, declStart: m.start, sigEnd: m.field("body")?.start ?? m.end)
                mem.isStatic = isStatic
                mem.typeName = typeName(m.field("return_type"))
                if let t = mem.typeName, tps.contains(t) || typeParams(m).contains(t) { mem.typeName = nil }
                (mem.docStart, mem.docEnd) = docRange(before: m)
                add(mem)
                if nm == "constructor", let b = m.field("body") {
                    ctorBodies.append(b)
                    for p in m.field("parameters")?.kids ?? [] where p.kind == "required_parameter" || p.kind == "optional_parameter" {
                        let mods = p.kids.contains { $0.kind == "accessibility_modifier" || $0.kind == "override_modifier" } || p.allKids.contains { $0.kind == "readonly" }
                        guard mods, let pat = p.field("pattern"), pat.kind == "identifier" else { continue }
                        var pm = NJSMember(name: pat.text(ns), kind: .property, loc: pat.start, len: pat.range.length, declStart: p.start, sigEnd: p.end)
                        pm.typeName = typeName(p.field("type"))
                        if let t = pm.typeName, tps.contains(t) { pm.typeName = nil }
                        add(pm)
                    }
                } else if let b = m.field("body") { ctorBodies.append(b) }
            case "public_field_definition", "field_definition":
                guard let (nm, nn) = memberName(m.field("name") ?? m.field("property")) else { continue }
                var mem = NJSMember(name: nm, kind: .property, loc: nn.start, len: nn.range.length, declStart: m.start, sigEnd: m.end)
                mem.isStatic = m.allKids.contains { $0.kind == "static" && $0.start < nn.start }
                mem.typeName = typeName(m.field("type")) ?? newName(m.field("value"))
                if let t = mem.typeName, tps.contains(t) { mem.typeName = nil }
                (mem.docStart, mem.docEnd) = docRange(before: m)
                add(mem)
            default: break
            }
        }
        // JS style properties: `this.x = ...` in the constructor / methods (first assignment wins)
        for b in ctorBodies {
            var stack = [b]
            while let n = stack.popLast() {
                if n.kind == "assignment_expression", let l = n.field("left"), l.kind == "member_expression", let o = l.field("object"), o.kind == "this",
                   let p = l.field("property"), p.kind == "property_identifier", !seen.contains("i:" + p.text(ns)) {
                    var mem = NJSMember(name: p.text(ns), kind: .property, loc: p.start, len: p.range.length, declStart: n.start, sigEnd: n.end)
                    mem.typeName = newName(n.field("right"))
                    add(mem)
                }
                if n.kind == "function_expression" || n.kind == "function_declaration" || n.kind == "class" || n.kind == "class_declaration" { continue }
                stack.append(contentsOf: n.kids.reversed())
            }
        }
        return out
    }

    private func signatureMembers(_ body: Node, typeParams tps: Set<String>) -> [NJSMember] {
        var out: [NJSMember] = []
        for m in body.kids {
            switch m.kind {
            case "property_signature", "method_signature":
                guard let (nm, nn) = memberName(m.field("name")) else { continue }
                var mem = NJSMember(name: nm, kind: m.kind == "method_signature" ? .method : .property, loc: nn.start, len: nn.range.length, declStart: m.start, sigEnd: m.end)
                mem.typeName = typeName(m.field(m.kind == "method_signature" ? "return_type" : "type"))
                if let t = mem.typeName, tps.contains(t) || typeParams(m).contains(t) { mem.typeName = nil }
                (mem.docStart, mem.docEnd) = docRange(before: m)
                out.append(mem)
            default: break
            }
        }
        return out
    }

    func objectMembers(_ obj: Node) -> [NJSMember] {
        var out: [NJSMember] = []
        for m in obj.kids {
            switch m.kind {
            case "pair":
                guard let (nm, nn) = memberName(m.field("key")) else { continue }
                let v = m.field("value")
                let fn = v.map { $0.kind == "arrow_function" || $0.kind == "function_expression" } ?? false
                var mem = NJSMember(name: nm, kind: fn ? .method : .property, loc: nn.start, len: nn.range.length, declStart: m.start, sigEnd: fn ? (v?.field("body")?.start ?? m.end) : m.end)
                mem.typeName = newName(v)
                (mem.docStart, mem.docEnd) = docRange(before: m)
                out.append(mem)
            case "method_definition":
                guard let (nm, nn) = memberName(m.field("name")) else { continue }
                var mem = NJSMember(name: nm, kind: .method, loc: nn.start, len: nn.range.length, declStart: m.start, sigEnd: m.field("body")?.start ?? m.end)
                (mem.docStart, mem.docEnd) = docRange(before: m)
                out.append(mem)
            case "shorthand_property_identifier":
                out.append(NJSMember(name: m.text(ns), kind: .property, loc: m.start, len: m.range.length, declStart: m.start, sigEnd: m.end))
            default: break
            }
        }
        return out
    }

    private func namespaceMembers(_ body: Node, ambient: Bool) -> [NJSMember] {
        var out: [NJSMember] = []
        for st in body.kids {
            var decl = st
            var outer = st
            if st.kind == "export_statement" { guard let d = st.field("declaration") else { continue }; decl = d }
            else if !ambient { continue }
            outer = st
            for sy in syms(for: decl, outer: outer, ambient: ambient) {
                var m = NJSMember(name: sy.name, kind: sy.kind, loc: sy.loc, len: sy.len, declStart: sy.declStart, sigEnd: sy.sigEnd, docStart: sy.docStart, docEnd: sy.docEnd)
                m.typeName = sy.typeName
                if !sy.members.isEmpty { m.sub = sy.members }
                m.heritage = sy.heritage
                out.append(m)
            }
        }
        return out
    }
}
