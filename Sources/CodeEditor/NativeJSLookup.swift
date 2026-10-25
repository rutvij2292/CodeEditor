import Foundation
import SwiftTreeSitter

/// Go to definition / hover for the token at an offset of the live buffer. Returns nil whenever the answer is not certain
/// (globals, untyped receivers, unresolved modules): the caller then falls back to the external TypeScript server.
extension NJSEnv {
    private static let identKinds: Set<String> = ["identifier", "type_identifier", "property_identifier", "private_property_identifier", "shorthand_property_identifier"]

    func target(_ r: NJSRes) -> NPTarget {
        if r.fileTop { return NPTarget(path: r.path, offset: 0, line: 1, column: 1) }
        let (line, col) = text(r.path).map { NPText.lineCol($0, r.loc) } ?? (1, 1)
        return NPTarget(path: r.path, offset: r.loc, line: line, column: col)
    }

    func lookup(at offset: Int) -> NPHit? {
        guard doc.inScript(offset) else { return nil }
        var leaf = doc.leaf(at: offset)
        if let l = leaf, !NJSEnv.identKinds.contains(l.kind), l.kind != "string_fragment", l.kind != "string", offset > 0, let p = doc.leaf(at: offset - 1),
           NJSEnv.identKinds.contains(p.kind), p.end == offset { leaf = p }
        guard let node = leaf else { return nil }
        if node.kind == "string_fragment" || node.kind == "string" { return moduleHit(node) }
        guard NJSEnv.identKinds.contains(node.kind) else { return nil }
        let res = resolveToken(node)
        guard !res.isEmpty else { return nil }
        var seen = Set<String>()
        let uniq = res.filter { seen.insert("\($0.path):\($0.loc):\($0.fileTop)").inserted }
        return NPHit(range: node.range, targets: uniq.map { target($0) }, markdown: markdown(uniq[0], others: uniq.count - 1), kind: uniq[0].kind.label)
    }

    func resolveToken(_ node: Node) -> [NJSRes] {
        let ns = doc.text
        let name = node.text(ns)
        guard let parent = node.parent else { return [] }
        switch node.kind {
        case "property_identifier", "private_property_identifier":
            guard parent.kind == "member_expression", let p = parent.field("property"), p == node, let o = parent.field("object"), let t = typeOf(o) else { return [] }
            return memberOf(t, name)
        default: break
        }
        switch parent.kind {
        case "import_specifier", "import_clause", "namespace_import":
            let local: Node = parent.kind == "import_specifier" ? (parent.field("alias") ?? parent.field("name") ?? node) : node
            guard let sym = doc.summary.order.first(where: { $0.kind == .import && $0.loc == local.start }) else { return [] }
            return followImport(sym, from: path, depth: 0)
        case "export_specifier":
            guard let nm = parent.field("name")?.text(ns) else { return [] }
            var p: Node? = parent
            while let c = p, c.kind != "export_statement" { p = c.parent }
            if let ex = p, let src = ex.field("source") {
                let spec = src.kids.first(where: { $0.kind == "string_fragment" })?.text(ns) ?? ""
                guard let t = proj.modules.resolve(spec, from: path) else { return [] }
                return NJSEnv.isCode(t) ? exportOf(t, nm) : []
            }
            return resolveTop(path, nm)
        case "jsx_opening_element", "jsx_self_closing_element", "jsx_closing_element":
            if node.kind == "identifier", let f = name.unicodeScalars.first, f.properties.isLowercase { return [] }   // intrinsic element
        case "nested_type_identifier":
            if let nm = parent.field("name"), nm == node, let m = parent.field("module") {
                let base: [NJSRes] = m.kind == "identifier" ? (localBinding(m.text(ns), from: m).map { [resolve($0)] } ?? resolveTop(path, m.text(ns))) : []
                guard let t = tv(of: base) else { return [] }
                return memberOf(t, name)
            }
        case "required_parameter", "optional_parameter":
            break
        default: break
        }
        if node.kind == "shorthand_property_identifier_pattern" { return [] }
        if let b = localBinding(name, from: node) { return [resolve(b)] }
        return resolveTop(path, name)
    }

    private func moduleHit(_ n: Node) -> NPHit? {
        let ns = doc.text
        var str = n
        if n.kind == "string_fragment" { guard let p = n.parent else { return nil }; str = p }
        guard str.kind == "string", let p = str.parent else { return nil }
        var isSpec = false
        switch p.kind {
        case "import_statement", "export_statement": isSpec = p.field("source") == str
        case "import_require_clause": isSpec = true
        case "arguments":
            if let c = p.parent, c.kind == "call_expression", let f = c.field("function") {
                let t = f.text(ns)
                isSpec = (t == "require" || f.kind == "import") && p.kids.first == str
            }
        default: break
        }
        guard isSpec, let frag = str.kids.first(where: { $0.kind == "string_fragment" }) else { return nil }
        let spec = frag.text(ns)
        guard let target = proj.modules.resolve(spec, from: path) else { return nil }
        let res = NJSRes(fileTop: target)
        return NPHit(range: frag.range, targets: [self.target(res)], markdown: markdown(res, others: 0), kind: "module")
    }
}
