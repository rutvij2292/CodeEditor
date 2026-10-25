import Foundation
import SwiftTreeSitter

/// Thin wrapper over a tree-sitter node plus the text it was parsed from (UTF-16 offsets line up with NSString).
struct PN {
    let n: Node
    let ns: NSString
    var type: String { n.nodeType ?? "" }
    var r: NSRange { n.range }
    var start: Int { n.range.location }
    var end: Int { NSMaxRange(n.range) }
    var text: String { ns.substring(with: r) }
    func field(_ f: String) -> PN? { n.child(byFieldName: f).map { PN(n: $0, ns: ns) } }
    var named: [PN] {
        var out: [PN] = []
        let c = n.namedChildCount
        out.reserveCapacity(c)
        for i in 0..<c { if let k = n.namedChild(at: i) { out.append(PN(n: k, ns: ns)) } }
        return out
    }
    var namedCount: Int { n.namedChildCount }
    func named(at i: Int) -> PN? { n.namedChild(at: i).map { PN(n: $0, ns: ns) } }
    func first(_ type: String) -> PN? {
        for i in 0..<n.namedChildCount { if let k = n.namedChild(at: i), k.nodeType == type { return PN(n: k, ns: ns) } }
        return nil
    }
    var parent: PN? { n.parent.map { PN(n: $0, ns: ns) } }
}

/// Builds a PyFile from a tree-sitter syntax tree.
final class PyOutlineBuilder {
    let path: String
    let ns: NSString
    let file: PyFile
    private var count = 0

    init(path: String, ns: NSString, root: Node) {
        self.path = path
        self.ns = ns
        let top = PyScope(kind: .module, start: 0, end: ns.length + 1, parent: nil)
        file = PyFile(path: path, root: top)
        let pn = PN(n: root, ns: ns)
        file.docRange = docOf(pn)
        for c in pn.named { walk(c, top) }
        file.symCount = count
        file.size = ns.length
        file.lineStarts = Self.lineStarts(ns)
    }

    static func lineStarts(_ ns: NSString) -> [Int32] {
        var out: [Int32] = [0]
        let n = ns.length
        if n == 0 { return out }
        var buf = [unichar](repeating: 0, count: min(n, 8192))
        var pos = 0
        while pos < n {
            let len = min(buf.count, n - pos)
            ns.getCharacters(&buf, range: NSRange(location: pos, length: len))
            for i in 0..<len where buf[i] == 10 { out.append(Int32(pos + i + 1)) }
            pos += len
        }
        return out
    }

    // MARK: Walk

    private func register(_ s: PySym) { file.declByOff[s.nameOff] = s; count += 1 }

    private func curFn(_ scope: PyScope) -> PySym? {
        var s: PyScope? = scope
        while let c = s {
            if c.kind == .fn { return c.owner }
            if c.kind == .cls || c.kind == .module { return nil }
            s = c.parent
        }
        return nil
    }

    private var level = 0

    private func walk(_ node: PN, _ scope: PyScope) {
        if node.namedCount == 0 || level > 160 { return }       // generated files with huge expression chains: keep the (512 KB) stack small
        level += 1
        defer { level -= 1 }
        switch node.type {
        case "string", "comment": return
        case "function_definition": defFn(node, scope, decorators: []); return
        case "class_definition": defCls(node, scope, decorators: []); return
        case "decorated_definition":
            var decs: [String] = []
            for c in node.named where c.type == "decorator" {
                decs.append(decoratorName(c))
                for k in c.named { walk(k, scope) }
            }
            if let d = node.field("definition") {
                if d.type == "function_definition" { defFn(d, scope, decorators: decs, outer: node) }
                else if d.type == "class_definition" { defCls(d, scope, decorators: decs, outer: node) }
            }
            return
        case "assignment": assignment(node, scope); return
        case "named_expression":
            if let nm = node.field("name"), nm.type == "identifier", let v = node.field("value") {
                var target = scope
                while target.kind == .comp || target.kind == .lambda, let p = target.parent { target = p }
                addVar(nm, target, value: expr(v), annotation: nil, stmt: node)
                walk(v, scope)
                return
            }
        case "import_statement": importStatement(node, scope); return
        case "import_from_statement": importFrom(node, scope); return
        case "global_statement":
            for c in node.named where c.type == "identifier" { scope.globals.insert(c.text) }
            return
        case "nonlocal_statement":
            for c in node.named where c.type == "identifier" { scope.nonlocals.insert(c.text) }
            return
        case "for_statement":
            if let l = node.field("left"), let r = node.field("right") {
                bindTarget(l, scope, valueNode: nil, valueExpr: .iter(expr(r)), annotation: nil, stmt: node, unpackValue: false)
            }
        case "with_item":
            if let v = node.field("value"), v.type == "as_pattern" {
                if let inner = v.named.first {
                    if let alias = v.field("alias")?.named.first {
                        bindTarget(alias, scope, valueNode: nil, valueExpr: .enter(expr(inner)), annotation: nil, stmt: node, unpackValue: false)
                    }
                    walk(inner, scope)
                }
                return
            }
        case "except_clause":
            if let v = node.named.first, v.type == "as_pattern" {
                if let inner = v.named.first {
                    if let alias = v.field("alias")?.named.first {
                        bindTarget(alias, scope, valueNode: nil, valueExpr: .exc(expr(inner)), annotation: nil, stmt: node, unpackValue: false)
                    }
                    walk(inner, scope)
                }
                for c in node.named.dropFirst() { walk(c, scope) }
                return
            }
        case "lambda": lambda(node, scope); return
        case "list_comprehension", "set_comprehension", "dictionary_comprehension", "generator_expression":
            comprehension(node, scope); return
        case "return_statement":
            if let fn = curFn(scope), let v = node.named.first {
                if fn.retExprs.count < 4, v.type != "none" { fn.retExprs.append(expr(v)) }
                walk(v, scope)
            }
            return
        case "yield":
            curFn(scope)?.hasYield = true
        case "case_pattern":
            if node.namedCount == 1, let d = node.named(at: 0), d.type == "dotted_name", d.namedCount == 1, let id = d.named(at: 0), id.text != "_" {
                addVar(id, scope, value: .unknown, annotation: nil, stmt: node)
                return
            }
        case "splat_pattern":
            if let id = node.named.first, id.type == "identifier" { addVar(id, scope, value: .unknown, annotation: nil, stmt: node) }
            return
        case "as_pattern":
            if let alias = node.field("alias"), alias.type == "identifier" { addVar(alias, scope, value: .unknown, annotation: nil, stmt: node) }
            else if node.field("alias") == nil, node.namedCount >= 2, let last = node.named.last, last.type == "identifier" {     // `case P as name`
                addVar(last, scope, value: .unknown, annotation: nil, stmt: node)
            }
        case "type_alias_statement":
            if let l = node.field("left"), let id = firstIdentifier(l) { addVar(id, scope, value: .unknown, annotation: nil, stmt: node) }
        case "call":
            if let f = node.field("function"), f.type == "identifier", f.text == "locals" || f.text == "vars" || f.text == "globals" { scope.usesLocals = true }
        default: break
        }
        for c in node.named { walk(c, scope) }
    }

    private func firstIdentifier(_ n: PN) -> PN? {
        if n.type == "identifier" { return n }
        for c in n.named { if let r = firstIdentifier(c) { return r } }
        return nil
    }

    private func decoratorName(_ dec: PN) -> String {
        guard var e = dec.named.first else { return "" }
        if e.type == "call", let f = e.field("function") { e = f }
        func dotted(_ n: PN) -> String {
            switch n.type {
            case "identifier": return n.text
            case "attribute":
                guard let o = n.field("object"), let a = n.field("attribute") else { return "" }
                let l = dotted(o)
                return l.isEmpty ? "" : l + "." + a.text
            default: return ""
            }
        }
        return dotted(e)
    }

    // MARK: Definitions

    private func docOf(_ block: PN) -> NSRange? {
        for c in block.named {
            if c.type == "comment" { continue }
            guard c.type == "expression_statement", c.namedCount == 1, let s = c.named(at: 0), s.type == "string" else { return nil }
            // f-strings are not docstrings
            let head = ns.substring(with: NSRange(location: s.start, length: min(3, s.end - s.start))).lowercased()
            if head.hasPrefix("f") || head.hasPrefix("rf") || head.hasPrefix("fr") { return nil }
            return s.r
        }
        return nil
    }

    private func header(_ node: PN, bodyStart: Int) -> String {
        let len = max(0, min(bodyStart, ns.length) - node.start)
        var s = ns.substring(with: NSRange(location: node.start, length: min(len, 1200)))
        // trailing `:`, whitespace
        while let l = s.last, l == ":" || l.isWhitespace { s.removeLast() }
        var out = ""
        var lastSpace = false
        for ch in s {
            if ch.isWhitespace { if !lastSpace { out.append(" ") }; lastSpace = true } else { out.append(ch); lastSpace = false }
        }
        out = out.replacingOccurrences(of: "( ", with: "(").replacingOccurrences(of: " )", with: ")").replacingOccurrences(of: ", )", with: ")")
        if out.count > 400 { out = String(out.prefix(400)) + "…" }
        return out
    }

    private func typeParams(_ node: PN, _ scope: PyScope) {
        guard let tp = node.field("type_parameters") else { return }
        for t in tp.named {
            if let id = firstIdentifier(t) { addVar(id, scope, value: .unknown, annotation: nil, stmt: t) }
        }
    }

    private func params(_ pn: PN?, lambda: Bool) -> [PyParam] {
        guard let pn else { return [] }
        var out: [PyParam] = []
        for c in pn.named {
            switch c.type {
            case "identifier": out.append(PyParam(name: c.text, nameOff: c.start))
            case "typed_parameter":
                var star: UInt8 = 0
                var idn: PN?
                for k in c.named {
                    if k.type == "identifier" { idn = k }
                    else if k.type == "list_splat_pattern" { star = 1; idn = k.named.first }
                    else if k.type == "dictionary_splat_pattern" { star = 2; idn = k.named.first }
                }
                if let idn { out.append(PyParam(name: idn.text, nameOff: idn.start, annotation: c.field("type").map { typeExpr($0) }, star: star)) }
            case "default_parameter", "typed_default_parameter":
                if let nm = c.field("name") {
                    var p = PyParam(name: nm.text, nameOff: nm.start, annotation: c.field("type").map { typeExpr($0) })
                    if let v = c.field("value") { p.defaultText = String(v.text.prefix(40)) }
                    out.append(p)
                }
            case "list_splat_pattern": if let i = c.named.first { out.append(PyParam(name: i.text, nameOff: i.start, star: 1)) }
            case "dictionary_splat_pattern": if let i = c.named.first { out.append(PyParam(name: i.text, nameOff: i.start, star: 2)) }
            default: break
            }
        }
        return out
    }

    private func typeExpr(_ n: PN) -> PyExpr {
        if n.type == "type", let k = n.named.first { return expr(k) }
        return expr(n)
    }

    private func defFn(_ node: PN, _ scope: PyScope, decorators: [String], outer: PN? = nil) {
        guard let nameN = node.field("name"), let body = node.field("body") else { return }
        let sym = PySym(name: nameN.text, kind: .fn, path: path, nameOff: nameN.start)
        sym.declStart = (outer ?? node).start
        sym.declEnd = node.end
        sym.decorators = decorators
        sym.isAsync = node.n.child(at: 0)?.nodeType == "async"
        sym.header = header(node, bodyStart: body.start)
        let ps = params(node.field("parameters"), lambda: false)
        sym.params = ps
        sym.returns = node.field("return_type").map { typeExpr($0) }
        sym.docRange = docOf(body)
        bindName(sym, scope)
        let inner = PyScope(kind: .fn, start: body.start, end: body.end, parent: scope)
        inner.owner = sym
        sym.inner = inner
        scope.children.append(inner)
        for (i, p) in ps.enumerated() {
            let ps = PySym(name: p.name, kind: .param, path: path, nameOff: p.nameOff)
            ps.paramIndex = i
            ps.annotation = p.annotation
            ps.declStart = p.nameOff; ps.declEnd = p.nameOff + (p.name as NSString).length
            inner.add(ps)
            register(ps)
        }
        typeParams(node, inner)
        if let pn = node.field("parameters") { for c in pn.named { walk(c, scope) } }
        if let r = node.field("return_type") { walk(r, scope) }
        for c in body.named { walk(c, inner) }
    }

    private func defCls(_ node: PN, _ scope: PyScope, decorators: [String], outer: PN? = nil) {
        guard let nameN = node.field("name"), let body = node.field("body") else { return }
        let sym = PySym(name: nameN.text, kind: .cls, path: path, nameOff: nameN.start)
        sym.declStart = (outer ?? node).start
        sym.declEnd = node.end
        sym.decorators = decorators
        sym.header = header(node, bodyStart: body.start)
        if let sup = node.field("superclasses") {
            for c in sup.named where c.type != "keyword_argument" && sym.bases.count < 8 { sym.bases.append(expr(c)) }
            for c in sup.named { walk(c, scope) }
        }
        sym.docRange = docOf(body)
        bindName(sym, scope)
        let inner = PyScope(kind: .cls, start: body.start, end: body.end, parent: scope)
        inner.owner = sym
        sym.inner = inner
        scope.children.append(inner)
        typeParams(node, inner)
        for c in body.named { walk(c, inner) }
    }

    private func bindName(_ sym: PySym, _ scope: PyScope) {
        var target = scope
        if scope.globals.contains(sym.name) { target = file.root }
        target.add(sym)
        register(sym)
    }

    private func lambda(_ node: PN, _ scope: PyScope) {
        let inner = PyScope(kind: .lambda, start: node.start, end: node.end, parent: scope)
        scope.children.append(inner)
        for (i, p) in params(node.field("parameters"), lambda: true).enumerated() {
            let s = PySym(name: p.name, kind: .param, path: path, nameOff: p.nameOff)
            s.paramIndex = i; s.declStart = p.nameOff; s.declEnd = p.nameOff + (p.name as NSString).length
            inner.add(s); register(s)
        }
        if let ps = node.field("parameters") { for c in ps.named { walk(c, scope) } }
        if let b = node.field("body") { walk(b, inner) }
    }

    private func comprehension(_ node: PN, _ scope: PyScope) {
        let inner = PyScope(kind: .comp, start: node.start, end: node.end, parent: scope)
        scope.children.append(inner)
        for c in node.named where c.type == "for_in_clause" {
            if let l = c.field("left"), let r = c.field("right") {
                bindTarget(l, inner, valueNode: nil, valueExpr: .iter(expr(r)), annotation: nil, stmt: c, unpackValue: false)
            }
        }
        for c in node.named { walk(c, inner) }
    }

    // MARK: Bindings

    private func assignment(_ node: PN, _ scope: PyScope) {
        var targets: [PN] = []
        var cur = node
        var rhs: PN?
        var ann: PyExpr?
        while true {
            if let l = cur.field("left") { targets.append(l) }
            if ann == nil, let t = cur.field("type") { ann = typeExpr(t) }
            guard let r = cur.field("right") else { break }
            if r.type == "assignment" { cur = r } else { rhs = r; break }
        }
        for t in targets {
            if scope.kind == .module, t.type == "identifier", t.text == "__all__", let r = rhs { scope.dunderAll = stringList(r) }
            bindTarget(t, scope, valueNode: rhs, valueExpr: nil, annotation: ann, stmt: node, unpackValue: true)
        }
        if let rhs { walk(rhs, scope) }
    }

    private func stringList(_ n: PN) -> [String]? {
        guard n.type == "list" || n.type == "tuple" else { return nil }
        var out: [String] = []
        for c in n.named where c.type == "string" {
            if case .str(let s) = expr(c) { out.append(s) }
        }
        return out
    }

    /// Binds the names of an assignment / loop / with target. `valueNode` is the right-hand side (for tuple destructuring of a
    /// tuple / list literal); `valueExpr` replaces it for loops, with-items and except clauses.
    private func bindTarget(_ t: PN, _ scope: PyScope, valueNode: PN?, valueExpr: PyExpr?, annotation: PyExpr?, stmt: PN, unpackValue: Bool) {
        switch t.type {
        case "identifier":
            let v: PyExpr? = valueExpr ?? valueNode.map { expr($0) }
            addVar(t, scope, value: v, annotation: annotation, stmt: stmt)
        case "attribute":
            guard let o = t.field("object"), o.type == "identifier", let a = t.field("attribute") else { return }
            addSelfAttr(selfName: o.text, attr: a, scope, value: valueExpr ?? valueNode.map { expr($0) }, annotation: annotation, stmt: stmt)
        case "pattern_list", "tuple_pattern", "list_pattern", "tuple", "list", "parenthesized_expression":
            let kids = t.named
            var elems: [PN]?
            if unpackValue, let v = valueNode, v.type == "tuple" || v.type == "list" || v.type == "parenthesized_expression" {
                var items = v.named
                if v.type == "parenthesized_expression", let inner = items.first, inner.type == "tuple" { items = inner.named }
                if items.count == kids.count, !items.contains(where: { $0.type == "list_splat" }), !kids.contains(where: { $0.type == "list_splat_pattern" }) { elems = items }
            }
            for (i, k) in kids.enumerated() {
                bindTarget(k, scope, valueNode: elems?[i], valueExpr: elems == nil ? PyExpr.unknown : nil, annotation: nil, stmt: stmt, unpackValue: true)
            }
        case "list_splat_pattern", "list_splat":
            if let i = t.named.first { bindTarget(i, scope, valueNode: nil, valueExpr: PyExpr.unknown, annotation: nil, stmt: stmt, unpackValue: false) }
        default: break
        }
    }

    private func addVar(_ id: PN, _ scope: PyScope, value: PyExpr?, annotation: PyExpr?, stmt: PN) {
        let name = id.text
        if scope.nonlocals.contains(name) { return }
        var target = scope
        if scope.globals.contains(name) { target = file.root }
        let s = PySym(name: name, kind: .variable, path: path, nameOff: id.start)
        s.value = value; s.annotation = annotation
        s.declStart = stmt.start; s.declEnd = stmt.end
        // a docstring-less statement: keep a tiny header for hover
        target.add(s)
        register(s)
    }

    /// `self.x = v` inside a method: an instance attribute of the enclosing class.
    private func addSelfAttr(selfName: String, attr: PN, _ scope: PyScope, value: PyExpr?, annotation: PyExpr?, stmt: PN) {
        var s: PyScope? = scope
        while let c = s, c.kind == .comp || c.kind == .lambda { s = c.parent }
        guard let fnScope = s, fnScope.kind == .fn, let method = fnScope.owner, !method.isStatic,
              let clsScope = fnScope.parent, clsScope.kind == .cls, let first = method.params.first, first.name == selfName, first.star == 0
        else { return }
        let sym = PySym(name: attr.text, kind: .attr, path: path, nameOff: attr.start)
        sym.value = value; sym.annotation = annotation
        sym.declStart = stmt.start; sym.declEnd = stmt.end
        clsScope.addAttr(sym)
        register(sym)
    }

    // MARK: Imports

    private func importStatement(_ node: PN, _ scope: PyScope) {
        for c in node.named {
            if c.type == "dotted_name", let first = c.named.first {
                let s = PySym(name: first.text, kind: .imp, path: path, nameOff: first.start)
                s.impModule = first.text
                s.declStart = node.start; s.declEnd = node.end
                bindName(s, scope)
            } else if c.type == "aliased_import", let nm = c.field("name"), let al = c.field("alias") {
                let s = PySym(name: al.text, kind: .imp, path: path, nameOff: al.start)
                s.impModule = nm.text
                s.declStart = node.start; s.declEnd = node.end
                bindName(s, scope)
            }
        }
    }

    private func importFrom(_ node: PN, _ scope: PyScope) {
        var module = "", level = 0
        if let m = node.field("module_name") {
            if m.type == "relative_import" {
                level = m.first("import_prefix").map { $0.text.filter { $0 == "." }.count } ?? 1
                module = m.first("dotted_name")?.text ?? ""
            } else { module = m.text }
        }
        for c in node.named {
            if c.type == "wildcard_import" { scope.stars.append((module, level)); continue }
            if let mn = node.field("module_name"), c.n.id == mn.n.id { continue }
            if c.type == "dotted_name", c.namedCount == 1, let id = c.named(at: 0) {
                let s = PySym(name: id.text, kind: .imp, path: path, nameOff: id.start)
                s.impModule = module; s.impLevel = level; s.impName = id.text
                s.declStart = node.start; s.declEnd = node.end
                bindName(s, scope)
            } else if c.type == "aliased_import", let nm = c.field("name"), let al = c.field("alias") {
                let s = PySym(name: al.text, kind: .imp, path: path, nameOff: al.start)
                s.impModule = module; s.impLevel = level; s.impName = nm.text
                s.declStart = node.start; s.declEnd = node.end
                bindName(s, scope)
            }
        }
    }

    // MARK: Expressions

    func expr(_ n: PN, _ depth: Int = 0) -> PyExpr { PyExprMaker.make(n, depth) }
}

enum PyExprMaker {
    static func make(_ n: PN, _ depth: Int = 0) -> PyExpr {
        if depth > 10 { return .unknown }
        switch n.type {
        case "identifier": return .name(n.text, n.start)
        case "attribute":
            guard let o = n.field("object"), let a = n.field("attribute") else { return .unknown }
            return .attr(make(o, depth + 1), a.text, a.start)
        case "call":
            guard let f = n.field("function") else { return .unknown }
            var first: PyExpr?
            if let args = n.field("arguments"), let a = args.named.first(where: { $0.type != "keyword_argument" }) { first = make(a, depth + 1) }
            return .call(make(f, depth + 1), first, n.start)
        case "subscript":
            guard let v = n.field("value") else { return .unknown }
            var idx: [PyExpr] = []
            for c in n.named.dropFirst() where idx.count < 4 { idx.append(make(c, depth + 1)) }
            return .sub(make(v, depth + 1), idx)
        case "string":
            let raw = n.text
            let head = raw.prefix(3).lowercased()
            if head.hasPrefix("b") || head.hasPrefix("rb") || head.hasPrefix("br") { return .lit("bytes") }
            var content = ""
            for c in n.named {
                if c.type == "interpolation" { return .lit("str") }
                if c.type == "string_content" { content += c.text }
            }
            return .str(String(content.prefix(160)))
        case "generic_type":
            guard let base = n.named.first else { return .unknown }
            var idx: [PyExpr] = []
            if let tp = n.first("type_parameter") { for c in tp.named where idx.count < 4 { idx.append(make(c, depth + 1)) } }
            return .sub(make(base, depth + 1), idx)
        case "concatenated_string": return .lit("str")
        case "integer": return .lit("int")
        case "float": return .lit("float")
        case "true", "false": return .lit("bool")
        case "none": return .lit("None")
        case "list", "list_comprehension": return .lit("list")
        case "dictionary", "dictionary_comprehension": return .lit("dict")
        case "set", "set_comprehension": return .lit("set")
        case "tuple": return .lit("tuple")
        case "parenthesized_expression", "type", "named_expression":
            if n.type == "named_expression", let v = n.field("value") { return make(v, depth + 1) }
            return n.named.first.map { make($0, depth + 1) } ?? .unknown
        case "binary_operator":
            guard let l = n.field("left"), let r = n.field("right"), let op = n.n.child(byFieldName: "operator"), PN(n: op, ns: n.ns).text == "|" else { return .unknown }
            return .union([make(l, depth + 1), make(r, depth + 1)])
        case "conditional_expression":
            let k = n.named
            guard k.count == 3 else { return .unknown }
            return .either(make(k[0], depth + 1), make(k[2], depth + 1))
        case "boolean_operator":
            guard let l = n.field("left"), let r = n.field("right"), let op = n.n.child(byFieldName: "operator"), PN(n: op, ns: n.ns).text == "or" else { return .unknown }
            return .either(make(l, depth + 1), make(r, depth + 1))
        case "await": return n.named.first.map { .await(make($0, depth + 1)) } ?? .unknown
        default: return .unknown
        }
    }
}
