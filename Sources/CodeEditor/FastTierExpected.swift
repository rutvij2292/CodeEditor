import Foundation

// Expected type at the caret (PhpStorm's "type-aware" ranking): the type the surrounding code wants at this position, derived from
//   - the parameter of the call being typed (positional, named, `new X(`, static / instance method, function, built-in),
//   - `return |` (declared return type of the enclosing function / method),
//   - `$this->typed = |` / `$typed = |` (property type, or the type of the variable),
//   - `catch (|` and `throw new |` (Throwable).
// It is computed ONLY from what the resolver already knows (NPResolver call-site / callee resolution, FTEval declared types): no extra
// index, nothing cached beyond the request. Unknown stays unknown (`nil`): the ranking is then untouched ("silent beats wrong").
//
// Candidates carry `CompletionItem.valueType` (class FQN, or lower-case scalar name); `FTEval.typeMatch` compares it with the expected
// type: 2 exact, 1 subtype / compatible, 0 unknown or different. The ranker lifts typeMatch > 0 above equal match classes.

struct FTExpected {
    var classes: [String] = []          // FQNs (a union lists all its class parts)
    var scalars: Set<String> = []       // int string float bool array callable iterable object
    var isEmpty: Bool { classes.isEmpty && scalars.isEmpty }
    var summary: String { (classes.map { String($0.split(separator: "\\").last ?? Substring($0)) } + scalars.sorted()).joined(separator: "|") }
}

extension FTEval {
    static let scalarNames: Set<String> = ["int", "float", "string", "bool", "array", "callable", "iterable", "object", "integer", "boolean", "double", "false", "true", "resource"]

    static func canonicalScalar(_ s: String) -> String {
        switch s {
        case "integer": return "int"
        case "boolean", "false", "true": return "bool"
        case "double": return "float"
        default: return s
        }
    }

    /// Value type of a declared type text (`?Foo`, `int|string`, `static`, `Collection<int, Foo>`): class FQN, lower-case scalar, or nil
    /// (undeclared, `mixed`, `void`, `null`, `never`, unions of unrelated parts keep the first).
    static func valueType(_ raw: String, owner: FTClass?) -> String? {
        var text = raw.trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return nil }
        if let lt = text.firstIndex(of: "<") { text = String(text[..<lt]) }                // generics: only the container matters
        for part in text.split(whereSeparator: { $0 == "|" || $0 == "&" || $0 == "(" || $0 == ")" }) {
            var p = part.trimmingCharacters(in: .whitespaces)
            if p.hasPrefix("?") { p.removeFirst() }
            if p.hasSuffix("[]") { return "array" }
            let l = p.lowercased()
            if p.isEmpty || l == "null" || l == "void" || l == "never" { continue }
            if l == "mixed" { return nil }
            if scalarNames.contains(l) { return canonicalScalar(l) }
            if l == "self" || l == "static" || l == "$this" { return owner.flatMap { $0.fqn.isEmpty ? nil : $0.fqn } }
            if l == "parent" { return owner?.extends }
            guard let o = owner else { return p.hasPrefix("\\") ? String(p.dropFirst()) : p }
            return o.resolve(p)
        }
        return nil
    }

    /// Parses a parameter / return type text into an expected type. nil = no constraint (`mixed` or undeclared).
    static func expected(fromDeclared raw: String, owner: FTClass?, extra: ((String) -> String)? = nil) -> FTExpected? {
        var text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        if let lt = text.firstIndex(of: "<") { text = String(text[..<lt]) }
        var e = FTExpected()
        for part in text.split(whereSeparator: { $0 == "|" || $0 == "&" || $0 == "(" || $0 == ")" }) {
            var p = part.trimmingCharacters(in: .whitespaces)
            if p.hasPrefix("?") { p.removeFirst() }
            let l = p.lowercased()
            if p.isEmpty || l == "null" || l == "void" || l == "never" { continue }
            if l == "mixed" { return nil }
            if p.hasSuffix("[]") { e.scalars.insert("array"); continue }
            if scalarNames.contains(l) { e.scalars.insert(canonicalScalar(l)); continue }
            if l == "self" || l == "static" { if let f = owner?.fqn, !f.isEmpty { e.classes.append(f) }; continue }
            if l == "parent" { if let x = owner?.extends { e.classes.append(x) }; continue }
            if l == "closure" || l == "\\closure" { e.classes.append("Closure"); e.scalars.insert("callable"); continue }
            if let o = owner { e.classes.append(o.resolve(p)) } else { e.classes.append(p.hasPrefix("\\") ? String(p.dropFirst()) : p) }
        }
        if e.scalars.contains("callable") { e.classes.append("Closure") }
        return e.isEmpty ? nil : e
    }

    /// `sub` is `sup` or extends / implements it (own walk: the class hierarchy lists parents and traits, interfaces are followed here).
    func isSubtype(_ sub: String, of sup: String, depth: Int = 0) -> Bool {
        if sub.caseInsensitiveCompare(sup) == .orderedSame { return true }
        guard depth < 4 else { return false }
        for k in hierarchy(sub) {
            if k.fqn.caseInsensitiveCompare(sup) == .orderedSame { return true }
            for i in k.implements where isSubtype(i, of: sup, depth: depth + 1) { return true }
        }
        return false
    }

    /// 2 exact, 1 compatible (subtype, int for float, array for iterable ...), 0 unknown / different. `budget` bounds the class files that
    /// may be read for subtype checks in one request (decremented per class that needs its hierarchy).
    func typeMatch(_ vt: String?, _ e: FTExpected, budget: inout Int) -> UInt8 {
        guard let vt, !vt.isEmpty else { return 0 }
        let l = vt.lowercased()
        if Self.scalarNames.contains(l) {
            let s = Self.canonicalScalar(l)
            if e.scalars.contains(s) { return 2 }
            if s == "int", e.scalars.contains("float") { return 1 }
            if s == "array", e.scalars.contains("iterable") || e.classes.contains(where: { $0 == "Traversable" || $0 == "Countable" || $0 == "ArrayAccess" }) { return 1 }
            if e.scalars.contains("object") { return 0 }
            return 0
        }
        for c in e.classes where c.caseInsensitiveCompare(vt) == .orderedSame { return 2 }
        if e.scalars.contains("object") { return 1 }
        if e.scalars.contains("iterable"), vt.hasSuffix("Collection") { return 1 }
        guard budget > 0, !e.classes.isEmpty else { return 0 }
        budget -= 1
        for c in e.classes where isSubtype(vt, of: c) { return 1 }
        return 0
    }

    /// Sets `typeMatch` on every item that carries a `valueType`.
    func annotate(_ items: inout [CompletionItem], expected e: FTExpected, budget: Int = 24) {
        var b = budget
        var memo: [String: UInt8] = [:]
        for i in items.indices {
            guard let vt = items[i].valueType else { continue }
            if let m = memo[vt] { items[i].typeMatch = m; continue }
            let m = typeMatch(vt, e, budget: &b)
            memo[vt] = m
            items[i].typeMatch = m
        }
    }

    /// Value type of an Eloquent column (migration builder type) for ranking.
    static func columnValueType(_ t: String) -> String? {
        let l = t.lowercased()
        if l.contains("int") || l == "id" || l == "foreignid" || l.hasPrefix("foreign") || l == "increments" || l == "bigincrements" { return "int" }
        if l.contains("string") || l == "text" || l == "char" || l.contains("text") || l == "uuid" || l == "ulid" || l == "enum" || l == "email" { return "string" }
        if l.contains("bool") { return "bool" }
        if l == "array" || l == "collection" || l == "object" || l.contains("json") || l == "encrypted:array" { return "array" }
        if l == "hashed" { return "string" }
        if l.contains("decimal") || l.contains("float") || l.contains("double") { return "float" }
        if l == "json" || l == "jsonb" { return "array" }
        if l.contains("date") || l.contains("timestamp") || l == "time" { return "Illuminate\\Support\\Carbon" }
        return nil
    }
}

extension NPResolver {
    /// Expected type for the expression whose FIRST token is `lo` (tokens before `lo` are the context). nil = unknown.
    func expectedType(beforeToken lo: Int) -> FTExpected? {
        guard !FUsage.off, lo >= 1, lo <= lex.count else { return nil }
        var i = lo - 1
        // unary noise in front of the expression: `!`, `&`, `@`, `...`
        while i >= 1, lex.toks[i].kind == .punct, [33, 38, 64].contains(lex.toks[i].ch), !(i >= 1 && lex.toks[i - 1].kind == .punct && lex.toks[i - 1].ch == lex.toks[i].ch) { i -= 1 }
        let t = lex.toks[i]
        if t.kind == .ident {
            let w = lex.text(i).lowercased()
            if w == "return" { return returnExpectation(at: i) }
            if w == "new", i >= 1, lex.isIdent(i - 1, "throw") { return throwable }
            return nil
        }
        guard t.kind == .punct else { return nil }
        switch t.ch {
        case 40:                                                                       // `(`
            if i >= 1, lex.isIdent(i - 1, "catch") { return throwable }
            return argumentExpectation(startToken: lo)
        case 44:                                                                       // `,`
            return argumentExpectation(startToken: lo)
        case 58:                                                                       // `name: |` named argument (not `::`: that is dcolon)
            guard i >= 1, lex.toks[i - 1].kind == .ident, i >= 2, lex.isPunct(i - 2, "(") || lex.isPunct(i - 2, ","), !(i >= 3 && lex.isPunct(i - 3, "?")) else { return nil }
            return argumentExpectation(startToken: i - 1)
        case 61:                                                                       // `=`
            return assignmentExpectation(eqToken: i)
        default:
            return nil
        }
    }

    private var throwable: FTExpected { FTExpected(classes: ["Throwable"], scalars: []) }

    // MARK: Arguments

    private func argumentExpectation(startToken lo: Int) -> FTExpected? {
        guard let site = callSite(at: lo < lex.count ? lex.toks[lo].loc : ns.length) else { return nil }
        guard let (target, owner) = expectedTarget(open: site.open) else { return nil }
        var ps = Self.splitParams(target.params)
        if target.dropFirst, !ps.isEmpty { ps.removeFirst() }
        guard !ps.isEmpty else { return nil }
        var idx = site.index
        let a = site.argStart
        if a >= 0, a + 1 < lex.count, lex.toks[a].kind == .ident, lex.isPunct(a + 1, ":") {
            let n = "$" + lex.text(a)
            guard let k = ps.firstIndex(where: { Self.paramName($0) == n }) else { return nil }
            idx = k
        } else if idx >= ps.count {
            guard let last = ps.last, last.contains("...") else { return nil }
            idx = ps.count - 1
        }
        return Self.declaredType(ofParam: ps[idx]).flatMap { FTEval.expected(fromDeclared: $0, owner: owner) }
    }

    /// Type text of one parameter (`?Foo $x = null` -> `?Foo`); nil when untyped.
    static func declaredType(ofParam p: String) -> String? {
        var s = p
        if let eq = s.firstIndex(of: "=") { s = String(s[..<eq]) }
        guard let dollar = s.firstIndex(of: "$") else { return nil }
        var head = String(s[..<dollar]).trimmingCharacters(in: .whitespaces)
        for m in ["public ", "protected ", "private ", "readonly "] { head = head.replacingOccurrences(of: m, with: "") }
        head = head.replacingOccurrences(of: "...", with: "").replacingOccurrences(of: "&", with: "").trimmingCharacters(in: .whitespaces)
        if head.hasPrefix("#[") { return nil }
        return head.isEmpty ? nil : head
    }

    /// `calleeTarget` that also reports the class whose file declared the parameter types (names resolve through its imports).
    private func expectedTarget(open: Int) -> (NPSigTarget, FTClass?)? {
        let o = open - 1
        guard o >= 0, lex.toks[o].kind == .ident else { return nil }
        let name = lex.text(o)
        if o >= 1, lex.isPunct(o - 1, code: PHPTok.arrow) || lex.isPunct(o - 1, code: PHPTok.dcolon) {
            let isStaticOp = lex.isPunct(o - 1, code: PHPTok.dcolon)
            let lo = ev.chainStart(before: o - 1)
            guard lo < o - 1, let recv = ev.eval(lo, o - 1) else { return nil }
            let (owners, model) = owners(for: recv)
            guard let mem = findMember(owners: owners, model: model, name: name, isCall: true, isStatic: isStaticOp, kindVariable: false),
                  mem.kind == .method, let m = mem.method else { return nil }
            return (NPSigTarget(name: m.name, params: m.params, ret: m.ret, doc: nil, dropFirst: mem.extra.hasPrefix("Eloquent scope")), mem.owner)
        }
        if o >= 1, lex.isIdent(o - 1, "new") {
            guard let (fqn, builtin) = resolveClassName(name), !builtin,
                  let mem = findMember(owners: [fqn], model: nil, name: "__construct", isCall: true, isStatic: false, kindVariable: false),
                  mem.kind == .method, let m = mem.method else { return nil }
            return (NPSigTarget(name: name, params: m.params, ret: "", doc: nil), mem.owner)
        }
        // plain function: this file, the project / vendor helper index, then the built-in table
        var fname = name
        if let b = fname.lastIndex(of: "\\") { fname = String(fname[fname.index(after: b)...]) }
        if let t = functionTargetPublic(fname) { return t }
        return nil
    }

    private func functionTargetPublic(_ name: String) -> (NPSigTarget, FTClass?)? {
        for j in 0..<max(0, lex.count - 2) where lex.isIdent(j, "function") {
            var k = j + 1
            if lex.isPunct(k, "&") { k += 1 }
            guard k < lex.count, lex.toks[k].kind == .ident, lex.text(k).caseInsensitiveCompare(name) == .orderedSame, lex.isPunct(k + 1, "(") else { continue }
            if let c = cur, c.methods.contains(where: { $0.loc == lex.toks[k].loc }) { continue }
            if j > 0, lex.toks[j - 1].kind == .ident, ["public", "protected", "private", "static", "abstract", "final"].contains(lex.text(j - 1)) { continue }
            guard let sig = NPFuncIndex.signature(ns, nameLoc: lex.toks[k].loc) else { continue }
            return (NPSigTarget(name: sig.name, params: sig.params, ret: sig.ret, doc: nil), cur)
        }
        if let f = NPFuncIndex.shared(root: fp.path).function(name), let t = NPFiles.text(f.path), let sig = NPFuncIndex.signature(t, nameLoc: f.loc) {
            return (NPSigTarget(name: sig.name, params: sig.params, ret: sig.ret, doc: nil), ev.pseudoOwner(t))
        }
        if let b = NPBuiltins.functions[name.lowercased()], let p = Self.parseSignatureText(b.signature) {
            return (NPSigTarget(name: p.name, params: p.params, ret: p.ret, doc: nil), nil)
        }
        return nil
    }

    // MARK: return / assignment

    private func returnExpectation(at retTok: Int) -> FTExpected? {
        guard let sc = ev.enclosingFunctions(retTok).first else { return nil }
        // `function name(...)\s*:\s*TYPE {` : the tokens between the parameter list's `)` and the body `{`
        let close = sc.params.1
        guard close + 1 < lex.count, lex.isPunct(close + 1, ":") else { return nil }
        var text = ""
        var q = close + 2
        while q < sc.bodyOpen, q < lex.count, q - close < 24 {
            let t = lex.toks[q]
            if t.kind == .ident || (t.kind == .punct && (t.ch == 63 || t.ch == 124 || t.ch == 38 || t.ch == 92)) { text += lex.text(q) } else { break }
            q += 1
        }
        guard !text.isEmpty else { return nil }
        return FTEval.expected(fromDeclared: text, owner: cur)
    }

    private func assignmentExpectation(eqToken eq: Int) -> FTExpected? {
        // not a comparison / compound operator: `==`, `!=`, `<=`, `>=`, `.=`, `+=` ...
        if eq >= 1, lex.toks[eq - 1].kind == .punct, lex.toks[eq - 1].loc + lex.toks[eq - 1].len == lex.toks[eq].loc,
           [61, 33, 60, 62, 46, 43, 45, 42, 47, 63, 37, 124, 38, 94].contains(lex.toks[eq - 1].ch) { return nil }
        guard eq >= 1 else { return nil }
        let lhsEnd = eq
        let lo = ev.chainStart(before: lhsEnd)
        guard lo < lhsEnd else { return nil }
        // `$obj->prop = |`: declared type of the property
        if lhsEnd - lo >= 3, lex.toks[lhsEnd - 1].kind == .ident || lex.toks[lhsEnd - 1].kind == .variable, lex.isPunct(lhsEnd - 2, code: PHPTok.arrow) {
            let member = lex.text(lhsEnd - 1)
            guard let recv = ev.eval(lo, lhsEnd - 2) else { return nil }
            let (owners, model) = owners(for: recv)
            guard let mem = findMember(owners: owners, model: model, name: member, isCall: false, isStatic: false, kindVariable: false) else { return nil }
            switch mem.kind {
            case .property:
                guard let p = mem.prop, !p.type.isEmpty else { return nil }
                return FTEval.expected(fromDeclared: p.type, owner: mem.owner)
            case .column:
                guard let vt = FTEval.columnValueType(mem.extra) else { return nil }
                return FTEval.expected(fromDeclared: vt, owner: nil)
            default: return nil
            }
        }
        // `$var = |`: the type the variable already has (an earlier typed assignment / parameter)
        if lhsEnd - lo == 1, lex.toks[lo].kind == .variable {
            let name = lex.text(lo)
            guard name != "$this", let t = ev.varType(name, at: lo, depth: 1) else { return nil }
            switch t {
            case .instance(let f): return FTExpected(classes: [f], scalars: [])
            default: return nil
            }
        }
        return nil
    }

    // MARK: Variables in scope (typed)

    /// `$name` candidates of the enclosing function with the value type each is known to have (declared parameter type or inferred).
    func typedVariables(atToken lo: Int) -> [(name: String, valueType: String?)] {
        var names: [String] = []
        var seen = Set<String>()
        let scopes = ev.enclosingFunctions(lo)
        let from = scopes.first.map { $0.params.0 } ?? 0
        var i = from
        while i < min(lo, lex.count) {
            if lex.toks[i].kind == .variable {
                let n = lex.text(i)
                if n != "$this", seen.insert(n).inserted { names.append(n) }
            }
            i += 1
            if names.count >= 60 { break }
        }
        var out: [(String, String?)] = []
        if let c = cur, !c.fqn.isEmpty, scopes.first.map({ _ in true }) ?? false { out.append(("$this", c.fqn)) }
        for n in names {
            var vt: String?
            if let t = ev.varType(n, at: min(lo, lex.count - 1), depth: 1) {
                switch t {
                case .instance(let f): vt = f
                case .collection: vt = "Illuminate\\Database\\Eloquent\\Collection"
                case .builder: vt = "Illuminate\\Database\\Eloquent\\Builder"
                case .table: vt = "Illuminate\\Database\\Query\\Builder"
                case .staticRef: vt = nil
                }
            }
            out.append((n, vt))
        }
        return out
    }
}
