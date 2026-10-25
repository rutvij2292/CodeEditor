import Foundation
import SwiftTreeSitter

/// A binding declared inside a function / block of the live document.
struct NJSLocal {
    var nameNode: Node
    var declNode: Node               // variable_declarator, parameter, function / class declaration, catch clause, ...
    var kind: NJSKind
    var keyword: String?
    var typeName: String?
}

extension NJSEnv {
    private static let functionKinds: Set<String> = ["function_declaration", "function_expression", "function", "generator_function", "generator_function_declaration",
                                                     "arrow_function", "method_definition"]

    func patternNames(_ p: Node, into out: inout [Node]) {
        switch p.kind {
        case "identifier", "shorthand_property_identifier_pattern": out.append(p)
        case "object_pattern":
            for c in p.kids {
                switch c.kind {
                case "shorthand_property_identifier_pattern": out.append(c)
                case "pair_pattern": if let v = c.field("value") { patternNames(v, into: &out) }
                case "object_assignment_pattern": if let l = c.field("left") { patternNames(l, into: &out) }
                case "rest_pattern": for k in c.kids { patternNames(k, into: &out) }
                default: break
                }
            }
        case "array_pattern": for c in p.kids { patternNames(c, into: &out) }
        case "assignment_pattern": if let l = p.field("left") { patternNames(l, into: &out) }
        case "rest_pattern": for c in p.kids { patternNames(c, into: &out) }
        default: break
        }
    }

    private func typeNameOf(_ node: Node?) -> String? { NJSExtractor(doc: doc).typeName(node) }

    private func fromDeclaration(_ decl: Node, name: String) -> NJSLocal? {
        let ns = doc.text
        switch decl.kind {
        case "lexical_declaration", "variable_declaration":
            let kw = decl.allKids.first.map { $0.text(ns) } ?? "var"
            for d in decl.kids where d.kind == "variable_declarator" {
                guard let pat = d.field("name") else { continue }
                var names: [Node] = []
                patternNames(pat, into: &names)
                for nn in names where nn.text(ns) == name {
                    let simple = pat.kind == "identifier"
                    return NJSLocal(nameNode: nn, declNode: d, kind: kw == "const" ? .constant : .variable, keyword: kw,
                                    typeName: simple ? (typeNameOf(d.field("type")) ?? NJSExtractor(doc: doc).newName(d.field("value"))) : nil)
                }
            }
        case "function_declaration", "generator_function_declaration", "function_signature":
            if let n = decl.field("name"), n.text(ns) == name { return NJSLocal(nameNode: n, declNode: decl, kind: .function, keyword: nil, typeName: typeNameOf(decl.field("return_type"))) }
        case "class_declaration", "abstract_class_declaration":
            if let n = decl.field("name"), n.text(ns) == name { return NJSLocal(nameNode: n, declNode: decl, kind: .class, keyword: nil, typeName: nil) }
        case "interface_declaration":
            if let n = decl.field("name"), n.text(ns) == name { return NJSLocal(nameNode: n, declNode: decl, kind: .interface, keyword: nil, typeName: nil) }
        case "type_alias_declaration":
            if let n = decl.field("name"), n.text(ns) == name { return NJSLocal(nameNode: n, declNode: decl, kind: .typeAlias, keyword: nil, typeName: nil) }
        case "enum_declaration":
            if let n = decl.field("name"), n.text(ns) == name { return NJSLocal(nameNode: n, declNode: decl, kind: .enum, keyword: nil, typeName: nil) }
        default: break
        }
        return nil
    }

    private func blockBinding(_ block: Node, _ name: String, hoistVar: Bool) -> NJSLocal? {
        for st in block.kids {
            if let b = fromDeclaration(st, name: name) { return b }
        }
        if hoistVar {                       // `var` anywhere in the function, not inside nested functions
            var stack = block.kids
            while let n = stack.popLast() {
                if n.kind == "variable_declaration", let b = fromDeclaration(n, name: name) { return b }
                if NJSEnv.functionKinds.contains(n.kind) || n.kind == "class_declaration" || n.kind == "class" { continue }
                stack.append(contentsOf: n.kids)
            }
        }
        return nil
    }

    private func paramBinding(_ params: Node, _ name: String) -> NJSLocal? {
        let ns = doc.text
        if params.kind == "identifier" { return params.text(ns) == name ? NJSLocal(nameNode: params, declNode: params, kind: .parameter, keyword: nil, typeName: nil) : nil }
        for p in params.kids {
            var pattern = p
            var typeNode: Node?
            if p.kind == "required_parameter" || p.kind == "optional_parameter" {
                guard let pt = p.field("pattern") else { continue }
                pattern = pt; typeNode = p.field("type")
            }
            var names: [Node] = []
            patternNames(pattern, into: &names)
            for nn in names where nn.text(ns) == name {
                return NJSLocal(nameNode: nn, declNode: p, kind: .parameter, keyword: nil, typeName: pattern.kind == "identifier" ? typeNameOf(typeNode) : nil)
            }
        }
        return nil
    }

    private func typeParamBinding(_ holder: Node, _ name: String) -> NJSLocal? {
        guard let tp = holder.field("type_parameters") else { return nil }
        for t in tp.kids where t.kind == "type_parameter" {
            if let n = t.field("name"), n.text(doc.text) == name { return NJSLocal(nameNode: n, declNode: t, kind: .typeAlias, keyword: nil, typeName: nil) }
        }
        return nil
    }

    /// Lexical lookup of `name` from `node` up to (not including) the program.
    func localBinding(_ name: String, from node: Node) -> NJSLocal? {
        let ns = doc.text
        var p = node.parent
        while let cur = p {
            switch cur.kind {
            case "program": return nil
            case "function_declaration", "function_expression", "function", "generator_function", "generator_function_declaration", "arrow_function", "method_definition":
                if let ps = cur.field("parameters") ?? cur.field("parameter"), let b = paramBinding(ps, name) { return b }
                if cur.kind != "function_declaration", cur.kind != "generator_function_declaration", cur.kind != "method_definition", cur.kind != "arrow_function",
                   let n = cur.field("name"), n.text(ns) == name { return NJSLocal(nameNode: n, declNode: cur, kind: .function, keyword: nil, typeName: nil) }
                if let b = typeParamBinding(cur, name) { return b }
                if let body = cur.field("body"), body.kind == "statement_block", let b = blockBinding(body, name, hoistVar: true) { return b }
            case "statement_block":
                if let b = blockBinding(cur, name, hoistVar: false) { return b }
            case "class_declaration", "abstract_class_declaration", "class", "interface_declaration", "type_alias_declaration":
                if let b = typeParamBinding(cur, name) { return b }
                if cur.kind == "class", let n = cur.field("name"), n.text(ns) == name { return NJSLocal(nameNode: n, declNode: cur, kind: .class, keyword: nil, typeName: nil) }
            case "for_statement":
                if let i = cur.field("initializer"), let b = fromDeclaration(i, name: name) { return b }
            case "for_in_statement":
                if let l = cur.field("left") {
                    var names: [Node] = []
                    patternNames(l, into: &names)
                    if let nn = names.first(where: { $0.text(ns) == name }) {
                        let kw = cur.allKids.first { $0.kind == "const" || $0.kind == "let" || $0.kind == "var" }?.kind
                        return NJSLocal(nameNode: nn, declNode: cur, kind: kw == "const" ? .constant : .variable, keyword: kw, typeName: nil)
                    }
                }
            case "catch_clause":
                if let pr = cur.field("parameter") {
                    var names: [Node] = []
                    patternNames(pr, into: &names)
                    if let nn = names.first(where: { $0.text(ns) == name }) { return NJSLocal(nameNode: nn, declNode: cur, kind: .parameter, keyword: nil, typeName: nil) }
                }
            case "switch_body", "switch_case", "switch_default":
                for c in cur.kids { if let b = fromDeclaration(c, name: name) { return b } }
            default: break
            }
            p = cur.parent
        }
        return nil
    }

    func resolve(_ b: NJSLocal) -> NJSRes {
        let n = b.nameNode, d = b.declNode
        var declStart = d.start
        if b.kind == .variable || b.kind == .constant, let par = d.parent, par.kind == "lexical_declaration" || par.kind == "variable_declaration" { declStart = par.start }
        let sym = NJSSym(name: n.text(doc.text), kind: b.kind, loc: n.start, len: n.range.length, declStart: declStart, sigEnd: d.end)
        sym.keyword = b.keyword
        sym.typeName = b.typeName
        if let body = d.field("body"), d.kind != "variable_declarator" { sym.sigEnd = body.start }
        let ex = NJSExtractor(doc: doc)
        if d.kind == "function_declaration" || d.kind == "generator_function_declaration" { sym.sigText = ex.fnSig(d) }
        else if d.kind == "variable_declarator", let v = d.field("value"), v.kind == "arrow_function" || v.kind == "function_expression" { sym.sigText = ex.fnSig(v) }
        if d.kind == "variable_declarator", let v = d.field("value"), v.kind == "object" { sym.members = ex.objectMembers(v) }
        else if d.kind == "variable_declarator", d.field("name")?.kind == "identifier", let v = d.field("value"), v.kind == "call_expression",
                let sh = ex.shape(of: v, imported: { n in
                    guard self.localBinding(n, from: v) == nil, let i = self.doc.summary.top[n]?.first(where: { $0.kind == .import }), let s = i.impSource, let nm = i.impName else { return nil }
                    return (s, nm)
                }) {
            sym.members = sh.members
            sym.valueMembers = sh.valueMembers
            if sym.typeName == nil { sym.typeName = sh.typeName }
        }
        else if b.kind == .class || b.kind == .interface || b.kind == .enum, let made = ex.syms(for: d, outer: d, ambient: false).first {
            sym.members = made.members; sym.heritage = made.heritage
        }
        var r = NJSRes(path: path, sym: sym)
        r.local = true
        return r
    }
}
