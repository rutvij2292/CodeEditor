import Foundation

// Native PHP symbol resolution (go to definition + hover) over the fast tier: PHPLex tokens, FTParser class info (with declaration
// offsets), FTEval receiver typing and the vendor index. One NPResolver is created per request, on the project's fast-tier queue.

struct NPTarget: Equatable {
    var path: String
    var offset: Int          // UTF-16 offset in the file
    var line: Int            // 1-based
    var column: Int          // 1-based
}

struct NPHit {
    var range: NSRange       // the token / word under the pointer
    var targets: [NPTarget]
    var markdown: String
    var kind: String         // class, method, property, const, case, function, constant, variable, column, relation, ...
}

/// A resolved class member (or Eloquent virtual member).
struct NPMember {
    enum Kind: String { case method, property, constant, enumCase, column, docProperty, docMethod, attribute }
    var kind: Kind
    var owner: FTClass
    var name: String
    var loc: Int             // in owner's file
    var declStart: Int
    var method: FTMethod?
    var prop: FTProp?
    var extra = ""           // relation description, column type, doc line ...
    var path: String?        // set when the declaration is not in owner's own file (migration columns)
    var viaDoc = false
}

final class NPResolver {
    let fp: FastProject
    let url: URL
    let ns: NSString
    let lex: PHPLex
    let cur: FTClass?
    let ev: FTEval
    let isBlade: Bool
    /// Resolve-only mode (find usages / rename): no markdown, no file reads for line numbers, no per-call revalidation.
    var light = false

    init(fp: FastProject, url: URL, text: NSString, lex: PHPLex, cur: FTClass?) {
        self.fp = fp; self.url = url; ns = text; self.lex = lex; self.cur = cur
        ev = FTEval(fp: fp, text: text, lex: lex, cur: cur)
        isBlade = url.lastPathComponent.hasSuffix(".blade.php")
    }

    static let eloquentBuilder = "Illuminate\\Database\\Eloquent\\Builder"
    static let queryBuilder = "Illuminate\\Database\\Query\\Builder"
    static let collectionClass = "Illuminate\\Support\\Collection"

    private static let reserved: Set<String> = [
        "abstract", "and", "array", "as", "break", "callable", "case", "catch", "class", "clone", "const", "continue", "declare", "default", "do", "echo",
        "else", "elseif", "empty", "enddeclare", "endfor", "endforeach", "endif", "endswitch", "endwhile", "enum", "extends", "final", "finally", "fn", "for",
        "foreach", "function", "global", "goto", "if", "implements", "include", "include_once", "instanceof", "insteadof", "interface", "isset", "list",
        "match", "namespace", "new", "or", "print", "private", "protected", "public", "readonly", "require", "require_once", "return", "static", "switch",
        "throw", "trait", "try", "unset", "use", "var", "while", "xor", "yield", "true", "false", "null", "int", "float", "string", "bool", "mixed", "void",
        "iterable", "object", "never", "php", "endphp", "endsection", "section", "yield",
    ]
    private static let typeKeywords: Set<String> = ["new", "extends", "implements", "instanceof", "insteadof", "catch", "use"]

    // MARK: Public entry

    func lookup(at offset: Int, wantDoc: Bool = true) -> NPHit? {
        light = !wantDoc
        if wantDoc { fp.beginRequest() }
        if let i = tokenAt(offset) {
            guard inPHP(lex.toks[i].loc) else { return nil }
            let t = lex.toks[i]
            let range = NSRange(location: t.loc, length: t.len)
            switch t.kind {
            case .ident: return identLookup(i, range)
            case .variable: return variableLookup(i, range)
            case .string: return stringLookup(i, range, offset: offset)
            default: return nil
            }
        }
        return commentLookup(offset)
    }

    // MARK: Token helpers

    func tokenAt(_ offset: Int) -> Int? {
        let idx = ev.tokenIndex(atOrAfter: offset)
        if idx < lex.count, lex.toks[idx].loc == offset { return idx }
        if idx > 0 {
            let p = lex.toks[idx - 1]
            if offset >= p.loc, offset < p.loc + p.len { return idx - 1 }
            if offset == p.loc + p.len, p.kind == .ident || p.kind == .variable { return idx - 1 }
        }
        return nil
    }

    func tokText(_ i: Int) -> String { lex.text(i) }
    func isOpTok(_ i: Int) -> Bool { lex.isPunct(i, code: PHPTok.arrow) || lex.isPunct(i, code: PHPTok.dcolon) }

    private func lastRange(_ s: String, before: Int) -> Int {
        guard before > 0 else { return -1 }
        let r = ns.range(of: s, options: [.backwards, .literal], range: NSRange(location: 0, length: min(before, ns.length)))
        return r.location == NSNotFound ? -1 : r.location
    }

    /// Is `offset` inside PHP code (not template HTML)? Plain files without any `<?` tag count as PHP.
    func inPHP(_ offset: Int) -> Bool {
        if !isBlade {
            let o = lastRange("<?", before: offset + 2), c = lastRange("?>", before: offset)
            if o >= 0 { return o > c }
            return ns.range(of: "<?", options: .literal).location == NSNotFound
        }
        if lastRange("{{--", before: offset) > lastRange("--}}", before: offset) { return false }
        let o = max(lastRange("{{", before: offset), lastRange("{!!", before: offset))
        let c = max(lastRange("}}", before: offset), lastRange("!!}", before: offset))
        if o >= 0, o > c { return true }
        let p = lastRange("@php", before: offset), e = lastRange("@endphp", before: offset)
        if p >= 0, p > e, p + 4 < ns.length, ns.character(at: p + 4) != 40 { return true }
        let po = lastRange("<?", before: offset + 2), pc = lastRange("?>", before: offset)
        if po >= 0, po > pc { return true }
        // directive arguments: `@foreach ($users as $user)` -- an unbalanced "(" after an @word on this line
        let ls = max(CompletionLex.lineStart(ns, offset), offset - 400)
        let line = ns.substring(with: NSRange(location: ls, length: max(0, offset - ls))) as NSString
        var depth = 0, inDirective = false, i = 0
        while i < line.length {
            let ch = line.character(at: i)
            if ch == 64, i + 1 < line.length, CompletionLex.isIdent(line.character(at: i + 1)) {      // @word
                var j = i + 1
                while j < line.length, CompletionLex.isIdent(line.character(at: j)) { j += 1 }
                var k = j
                while k < line.length, line.character(at: k) == 32 { k += 1 }
                if k < line.length, line.character(at: k) == 40, depth == 0 { inDirective = true; depth = 0; i = k; continue }
                i = j; continue
            }
            if inDirective {
                if ch == 40 { depth += 1 } else if ch == 41 { depth -= 1; if depth == 0 { inDirective = false } }
            }
            i += 1
        }
        return inDirective && depth > 0
    }

    // MARK: Paths and texts

    func rel(_ path: String) -> String {
        let root = fp.path + "/"
        return path.hasPrefix(root) ? String(path.dropFirst(root.count)) : path
    }

    private func isCurrentFile(_ path: String) -> Bool { path == url.standardizedFileURL.path || path == url.path }

    func path(of k: FTClass) -> String? {
        if k === cur { return url.path }
        return fp.classPath(k.fqn)
    }

    func text(ofFile path: String) -> NSString? { isCurrentFile(path) ? ns : NPFiles.text(path) }

    func text(of k: FTClass) -> NSString? {
        if k === cur { return ns }
        guard let p = fp.classPath(k.fqn) else { return nil }
        return NPFiles.text(p)
    }

    func target(path: String, offset: Int) -> NPTarget? {
        if light { return NPTarget(path: path, offset: offset, line: 0, column: 0) }
        guard let t = text(ofFile: path) else { return NPTarget(path: path, offset: offset, line: 1, column: 1) }
        let (l, c) = NPText.lineCol(t, offset)
        return NPTarget(path: path, offset: offset, line: l, column: c)
    }

    func originLine(owner: String?, path: String?, offset: Int?) -> String {
        var parts: [String] = []
        if let owner, !owner.isEmpty { parts.append("`" + owner + "`") }
        if let path {
            var loc = rel(path)
            if let offset, let t = text(ofFile: path) { loc += ":\(NPText.lineCol(t, offset).line)" }
            parts.append("`" + loc + "`")
        }
        return parts.isEmpty ? "" : parts.joined(separator: "  \n")
    }

    // MARK: Identifiers

    private func prevKeyword(_ i: Int) -> String? {
        i > 0 && lex.toks[i - 1].kind == .ident ? lex.text(i - 1).lowercased() : nil
    }

    private func identLookup(_ i: Int, _ range: NSRange) -> NPHit? {
        let w = tokText(i)
        let lower = w.lowercased()
        if i > 0, isOpTok(i - 1) { return memberLookup(i, range) }
        // declarations of the current file
        if let pk = prevKeyword(i) {
            if ["class", "interface", "trait", "enum"].contains(pk), let c = cur, c.name == w, !(i > 1 && lex.isIdent(i - 2, "new")) {
                return declHit(c, range)
            }
            if pk == "function" { return methodDeclHover(i, range) }
            if pk == "const" || pk == "namespace" { return nil }
        }
        if Self.reserved.contains(lower), !["self", "static", "parent"].contains(lower) {
            // `static`/`self` handled below; plain keywords have no symbol. (`list`, `array` etc. are keywords.)
            return nil
        }
        if lower == "self" || lower == "static" || lower == "parent" { return classHit(w, range) }
        if let u = useStatementStart(i) { return useLookup(i, u, range) }
        let nextParen = lex.isPunct(i + 1, "(")
        let nextDC = lex.isPunct(i + 1, code: PHPTok.dcolon)
        let typeCtx = isTypeContext(i)
        if typeCtx && prevKeyword(i) == "new" || (typeCtx && !nextParen) || nextDC { if let h = classHit(w, range) { return h } }
        if nextParen { return functionHit(w, range) ?? (typeCtx ? classHit(w, range) : nil) }
        if let h = classHit(w, range) { return h }
        return constantHit(w, range)
    }

    /// `new X`, `extends X`, `: X` return types, `?X`/`X|Y` unions, params (`X $y`), attributes, implements lists.
    private func isTypeContext(_ i: Int) -> Bool {
        if let pk = prevKeyword(i), Self.typeKeywords.contains(pk), pk != "use" { return true }
        if lex.toks[i + 1 < lex.count ? i + 1 : i].kind == .variable, i + 1 < lex.count { return true }
        if i + 2 < lex.count, lex.isPunct(i + 1, "&") || lex.isPunct(i + 1, "."), lex.toks[i + 2].kind == .variable { return true }
        if i > 0, lex.toks[i - 1].kind == .punct {
            let p = lex.toks[i - 1].ch
            if p == 63 || p == 124 { return true }                                   // ? |
            if p == 58, i > 1, lex.isPunct(i - 2, ")") { return true }                // ): Type
            if p == 91, i > 1, lex.isPunct(i - 2, "#") { return true }                // #[Attr
        }
        // `implements A, B` / `extends A, B`
        var j = i - 1, steps = 0
        while j >= 0, steps < 40 {
            let t = lex.toks[j]
            if t.kind == .ident {
                let w = lex.text(j)
                if w == "implements" || w == "extends" { return true }
            } else if !(t.kind == .punct && t.ch == 44) { break }
            j -= 1; steps += 1
        }
        return false
    }

    /// Index of the `use` keyword when token `i` is part of an import statement / trait-use list.
    private func useStatementStart(_ i: Int) -> Int? {
        var j = i - 1, steps = 0
        while j >= 0, steps < 60 {
            let t = lex.toks[j]
            if t.kind == .ident {
                if lex.text(j) == "use" { return (j > 0 && isOpTok(j - 1)) ? nil : j }
            } else if !(t.kind == .punct && (t.ch == 44 || t.ch == 123 || t.ch == 125)) { return nil }
            j -= 1; steps += 1
        }
        return nil
    }

    private func useLookup(_ i: Int, _ useIdx: Int, _ range: NSRange) -> NPHit? {
        if useIdx + 1 < lex.count, lex.isIdent(useIdx + 1, "function") || lex.isIdent(useIdx + 1, "const") { return nil }
        let w = tokText(i)
        // after `as`: alias name
        if i > 0, lex.isIdent(i - 1, "as"), let full = cur?.uses[w] { return classHit(full.hasPrefix("\\") ? full : "\\" + full, range) }
        var fqn = w
        // group use: `use A\B\{C, D}` -- prefix is the ident before `{`
        var j = i - 1
        while j > useIdx, !lex.isPunct(j, "{") { j -= 1 }
        if j > useIdx, lex.isPunct(j, "{"), j > 0, lex.toks[j - 1].kind == .ident { fqn = tokText(j - 1) + w }
        if let c = cur, c.kind == "class" || c.kind == "trait" || c.kind == "enum", isInsideClassBody(i), let f = c.uses[w] { fqn = f }
        return classHit(fqn.hasPrefix("\\") ? fqn : "\\" + fqn, range)
    }

    private func isInsideClassBody(_ i: Int) -> Bool { cur.map { _ in lex.toks[i].loc > (cur?.nameLoc ?? Int.max) } ?? false }

    // MARK: Classes

    func resolveClassName(_ written: String) -> (fqn: String, builtin: Bool)? {
        var w = written
        let lower = w.lowercased()
        if lower == "self" || lower == "static" { return cur.flatMap { $0.fqn.isEmpty ? nil : ($0.fqn, false) } }
        if lower == "parent" { return cur?.extends.map { ($0, false) } }
        if let c = cur, !c.fqn.isEmpty, c.resolve(w) == c.fqn { return (c.fqn, false) }
        if let f = fp.resolveClass(w, in: cur) { return (f, false) }
        if w.hasPrefix("\\") { w.removeFirst() }
        let short = w.split(separator: "\\").last.map(String.init) ?? w
        if NPBuiltins.classes[w] != nil || (!w.contains("\\") || w.hasPrefix("Random")) && NPBuiltins.classes[short] != nil { return (NPBuiltins.classes[w] != nil ? w : short, true) }
        return nil
    }

    func classHit(_ written: String, _ range: NSRange) -> NPHit? {
        guard let (fqn, builtin) = resolveClassName(written) else { return nil }
        if builtin {
            let kind = NPBuiltins.classes[fqn] ?? "class"
            return NPHit(range: range, targets: [], markdown: "```php\n\(kind) \(fqn)\n```\n\nPHP built-in \(kind).", kind: "class")
        }
        return classHit(fqn: fqn, range)
    }

    func classHit(fqn: String, _ range: NSRange) -> NPHit? {
        var k: FTClass?
        var path: String?
        if let c = cur, c.fqn == fqn { k = c; path = url.path }
        else if let p = fp.classPath(fqn) { path = p; k = fp.classInfo(path: p) }
        guard let k, let path else { return nil }
        return declHit(k, range, path: path)
    }

    private func declHit(_ k: FTClass, _ range: NSRange, path given: String? = nil) -> NPHit? {
        guard let path = given ?? self.path(of: k) else { return nil }
        let offset = k.name.isEmpty ? 0 : k.nameLoc
        var targets: [NPTarget] = []
        if let t = target(path: path, offset: offset) { targets.append(t) }
        return NPHit(range: range, targets: targets, markdown: classMarkdown(k, path: path), kind: "class")
    }

    func short(_ fqn: String) -> String { fqn.split(separator: "\\").last.map(String.init) ?? fqn }

    private func classMarkdown(_ k: FTClass, path: String) -> String {
        if light { return "" }
        var sig = ""
        if k.isAbstract { sig += "abstract " }
        sig += k.kind + " " + (k.name.isEmpty ? k.fqn : k.name)
        if let e = k.extends { sig += " extends " + short(e) }
        if !k.implements.isEmpty {
            sig += (k.kind == "interface" ? " extends " : " implements ") + k.implements.prefix(5).map(short).joined(separator: ", ")
            if k.implements.count > 5 { sig += ", ..." }
        }
        var out = "```php\n" + (k.ns.isEmpty ? "" : "namespace \(k.ns);\n\n") + sig + "\n```"
        if k.kind == "enum", !k.cases.isEmpty {
            out += "\n\nCases: " + k.cases.prefix(12).map { "`\($0)`" }.joined(separator: ", ") + (k.cases.count > 12 ? ", ..." : "")
        }
        if let t = text(ofFile: path), let d = NPDoc.leading(t, before: k.declStart) {
            let md = NPDoc.parse(d.text, start: d.start).markdown()
            if !md.isEmpty { out += "\n\n" + md }
        }
        out += "\n\n" + originLine(owner: nil, path: path, offset: k.nameLoc)
        return out
    }

    // MARK: Methods declared in the current file (hover only)

    private func methodDeclHover(_ i: Int, _ range: NSRange) -> NPHit? {
        guard let c = cur else { return nil }
        let loc = lex.toks[i].loc
        if let m = c.methods.first(where: { $0.loc == loc }) {
            let mem = NPMember(kind: .method, owner: c, name: m.name, loc: m.loc, declStart: m.declStart, method: m)
            return NPHit(range: range, targets: [], markdown: memberMarkdown(mem), kind: "method")
        }
        return nil
    }

    // MARK: Functions and constants

    private func functionHit(_ written: String, _ range: NSRange) -> NPHit? {
        var name = written
        if name.hasPrefix("\\") { name.removeFirst() }
        if let b = name.lastIndex(of: "\\") { name = String(name[name.index(after: b)...]) }
        guard !name.isEmpty else { return nil }
        // 1. function declared in this file
        var found: NPFuncIndex.Found?
        for j in 0..<max(0, lex.count - 2) where lex.isIdent(j, "function") {
            var k = j + 1
            if lex.isPunct(k, "&") { k += 1 }
            guard k < lex.count, lex.toks[k].kind == .ident, tokText(k).caseInsensitiveCompare(name) == .orderedSame, lex.isPunct(k + 1, "(") else { continue }
            if let c = cur, c.methods.contains(where: { $0.loc == lex.toks[k].loc }) { continue }
            if j > 0, lex.toks[j - 1].kind == .ident, ["public", "protected", "private", "static", "abstract", "final"].contains(tokText(j - 1)) { continue }
            found = NPFuncIndex.Found(path: url.path, loc: lex.toks[k].loc, declStart: lex.toks[j].loc)
            break
        }
        // 2. helper files from composer (app/helpers.php, Laravel's own helpers, ...)
        if found == nil { found = NPFuncIndex.shared(root: fp.path).function(name) }
        if let f = found, let t = text(ofFile: f.path) {
            var md = ""
            if let sig = NPFuncIndex.signature(t, nameLoc: f.loc) {
                md = "```php\nfunction \(sig.name)(\(sig.params))" + (sig.ret.isEmpty ? "" : ": " + sig.ret) + "\n```"
            }
            if let d = NPDoc.leading(t, before: f.declStart) {
                let m = NPDoc.parse(d.text, start: d.start).markdown()
                if !m.isEmpty { md += "\n\n" + m }
            }
            md += "\n\n" + originLine(owner: nil, path: f.path, offset: f.loc)
            return NPHit(range: range, targets: target(path: f.path, offset: f.loc).map { [$0] } ?? [], markdown: md, kind: "function")
        }
        if light, let f = found { return NPHit(range: range, targets: [NPTarget(path: f.path, offset: f.loc, line: 0, column: 0)], markdown: "", kind: "function") }
        // 3. documented built-ins (no source to jump to)
        if let b = NPBuiltins.functions[name.lowercased()] {
            return NPHit(range: range, targets: [], markdown: "```php\nfunction \(b.signature)\n```\n\n\(b.doc)\n\nPHP built-in function.", kind: "function")
        }
        return nil
    }

    private func constantHit(_ written: String, _ range: NSRange) -> NPHit? {
        var name = written
        if name.hasPrefix("\\") { name.removeFirst() }
        if let b = name.lastIndex(of: "\\") { name = String(name[name.index(after: b)...]) }
        if light, let f = NPFuncIndex.shared(root: fp.path).constant(name) { return NPHit(range: range, targets: [NPTarget(path: f.path, offset: f.loc, line: 0, column: 0)], markdown: "", kind: "constant") }
        if let f = NPFuncIndex.shared(root: fp.path).constant(name), let t = text(ofFile: f.path) {
            let line = NPText.lineText(t, f.loc)
            let md = "```php\n\(line)\n```\n\n" + originLine(owner: nil, path: f.path, offset: f.loc)
            return NPHit(range: range, targets: target(path: f.path, offset: f.loc).map { [$0] } ?? [], markdown: md, kind: "constant")
        }
        if let d = NPBuiltins.constants[name] {
            return NPHit(range: range, targets: [], markdown: "```php\nconst \(name)\n```\n\n\(d)\n\nPHP built-in constant.", kind: "constant")
        }
        return nil
    }

    // MARK: Variables

    private func typeDescription(_ t: FTType) -> String {
        switch t {
        case .instance(let f): return f
        case .staticRef(let f): return "class-string<\(f)>"
        case .builder(let m): return "Eloquent Builder<\(m)>"
        case .table(let tbl): return "Query Builder (table \(tbl))"
        case .collection(let m): return m.map { "Collection<\($0)>" } ?? "Collection"
        }
    }

    private func variableLookup(_ i: Int, _ range: NSRange) -> NPHit? {
        let name = tokText(i)
        if i > 0, lex.isPunct(i - 1, code: PHPTok.dcolon) { return memberLookup(i, range) }      // Foo::$static
        if name == "$this" {
            guard let c = cur, !c.fqn.isEmpty else { return nil }
            return classHit(fqn: c.fqn, range)
        }
        var md = "```php\n(variable) \(name)"
        if let t = ev.varType(name, at: i, depth: 0) { md += ": " + typeDescription(t) }
        md += "\n```"
        var targets: [NPTarget] = []
        if let d = variableDeclaration(name, at: i), d != lex.toks[i].loc, let t = target(path: url.path, offset: d) { targets = [t] }
        else if variableDeclaration(name, at: i) == nil, let t = ev.varType(name, at: i, depth: 0) {
            // no local declaration (e.g. a Blade view variable): fall back to the type's class
            switch t {
            case .instance(let f), .staticRef(let f): if let h = classHit(fqn: f, range) { targets = h.targets }
            default: break
            }
        }
        return NPHit(range: range, targets: targets, markdown: md, kind: "variable")
    }

    /// Offset of the declaring occurrence (parameter, assignment, foreach/as, catch) in the enclosing function / file.
    private func variableDeclaration(_ name: String, at tok: Int) -> Int? {
        let scopes = ev.enclosingFunctions(tok)
        func isDecl(_ q: Int) -> Bool {
            if lex.isPunct(q + 1, "="), !lex.isPunct(q + 2, "="), !lex.isPunct(q + 2, code: PHPTok.fat), !lex.isPunct(q - 1, "=") { return true }
            if q > 0, lex.isIdent(q - 1, "as") { return true }
            if q > 0, lex.isPunct(q - 1, code: PHPTok.fat) { return false }
            return false
        }
        for sc in scopes {
            for q in sc.params.0..<sc.params.1 where lex.toks[q].kind == .variable && tokText(q) == name { return lex.toks[q].loc }
            var q = tok - 1
            var best: Int?
            while q >= sc.bodyOpen {
                if lex.toks[q].kind == .variable, tokText(q) == name, !(q > 0 && isOpTok(q - 1)), isDecl(q) { best = lex.toks[q].loc }
                q -= 1
            }
            if best != nil { return best }
        }
        if scopes.isEmpty {
            var q = 0
            while q < tok {
                if lex.toks[q].kind == .variable, tokText(q) == name, !(q > 0 && isOpTok(q - 1)), isDecl(q) { return lex.toks[q].loc }
                q += 1
            }
        }
        return nil
    }

    // MARK: Strings (class names, relation names, column names)

    private func stringLookup(_ i: Int, _ range: NSRange, offset: Int) -> NPHit? {
        let v = lex.strValue(i)
        guard !v.isEmpty, v.count < 160 else { return nil }
        if v.contains("\\"), v.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "\\" }),
           let h = classHit(fqn: v.hasPrefix("\\") ? String(v.dropFirst()) : v, NSRange(location: range.location + 1, length: max(0, range.length - 2))) { return h }
        // string argument of a model query method
        var q = i - 1, depth = 0
        while q >= 0, i - q < 40 {
            let t = lex.toks[q]
            if t.kind == .punct {
                if t.ch == 41 || t.ch == 93 { depth += 1 }
                else if t.ch == 91 { if depth == 0 { /* array arg */ } else { depth -= 1 } }
                else if t.ch == 40 { if depth == 0 { break }; depth -= 1 }
                else if t.ch == 59 || t.ch == 123 { return nil }
            }
            q -= 1
        }
        guard q >= 2, lex.isPunct(q, "("), lex.toks[q - 1].kind == .ident, isOpTok(q - 2) else { return nil }
        let method = tokText(q - 1)
        let isRelation = FTEval.relationMethods.contains(method), isColumn = FTEval.columnMethods.contains(method)
        guard isRelation || isColumn else { return nil }
        let lo = ev.chainStart(before: q - 2)
        guard let recv = ev.eval(lo, q - 2), let model = ev.modelFQN(recv) else { return nil }
        let inner = NSRange(location: range.location + 1, length: max(0, range.length - 2))
        if isRelation {
            // dotted: pick the segment under the pointer and resolve through preceding relations
            let parts = v.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            var idx = 0, pos = range.location + 1
            for (n, p) in parts.enumerated() { if offset >= pos, offset <= pos + p.count { idx = n; break }; pos += p.count + 1 }
            var m = model
            for p in parts.prefix(idx) { guard let r = ev.findRelation(m, p), let rel = r.related else { return nil }; m = rel }
            let seg = parts[idx]
            if let mem = findMember(owners: [m], model: m, name: seg, isCall: true, isStatic: false, kindVariable: false), mem.kind == .method {
                return memberHit(mem, NSRange(location: pos, length: seg.count))
            }
        }
        if isColumn, let mem = findMember(owners: [model], model: model, name: v, isCall: false, isStatic: false, kindVariable: false), mem.kind == .column || mem.kind == .attribute {
            return memberHit(mem, inner)
        }
        return nil
    }

    // MARK: Comments

    private func commentLookup(_ offset: Int) -> NPHit? {
        guard !isBlade, offset < ns.length else { return nil }
        func isW(_ c: unichar) -> Bool { CompletionLex.isIdent(c) || c == 92 }
        guard isW(ns.character(at: offset)) || (offset > 0 && isW(ns.character(at: offset - 1))) else { return nil }
        var s = offset, e = offset
        if !(offset < ns.length && isW(ns.character(at: offset))) { s -= 1; e -= 1 }
        while s > 0, isW(ns.character(at: s - 1)) { s -= 1 }
        while e < ns.length, isW(ns.character(at: e)) { e += 1 }
        let lineStart = CompletionLex.lineStart(ns, s)
        let before = ns.substring(with: NSRange(location: lineStart, length: s - lineStart)).trimmingCharacters(in: .whitespaces)
        guard before.hasPrefix("*") || before.hasPrefix("/**") else { return nil }
        let word = ns.substring(with: NSRange(location: s, length: e - s))
        guard let f = word.unicodeScalars.first, CharacterSet.uppercaseLetters.contains(f) || word.contains("\\") else { return nil }
        // tolerate `Type[]`, `Type|null`: the word already excludes them
        return classHit(word, NSRange(location: s, length: e - s))
    }

    // MARK: Members

    private func memberLookup(_ i: Int, _ range: NSRange) -> NPHit? {
        let opTok = i - 1
        let isStaticOp = lex.isPunct(opTok, code: PHPTok.dcolon)
        let lo = ev.chainStart(before: opTok)
        guard lo < opTok, let recv = ev.eval(lo, opTok) else { return nil }
        let isVar = lex.toks[i].kind == .variable
        let name = isVar ? String(tokText(i).dropFirst()) : tokText(i)
        let isCall = lex.isPunct(i + 1, "(")
        if isStaticOp, !isVar, name == "class" {
            switch recv {
            case .instance(let f), .staticRef(let f): return classHit(fqn: f, range)
            default: return nil
            }
        }
        var owners: [String] = []
        var model: String?
        switch recv {
        case .instance(let f), .staticRef(let f):
            owners = [f]
            if ev.isModel(f) { model = f }
        case .builder(let m): model = m; owners = [Self.eloquentBuilder, Self.queryBuilder]
        case .table: owners = [Self.queryBuilder]
        case .collection: owners = [Self.collectionClass]
        }
        guard let mem = findMember(owners: owners, model: model, name: name, isCall: isCall, isStatic: isStaticOp, kindVariable: isVar) else { return nil }
        return memberHit(mem, range)
    }

    /// All classes to search for a member: the hierarchy (traits, parents, interfaces), then @mixin/@see targets for facades.
    func searchClasses(_ owner: String) -> [FTClass] {
        var out: [FTClass] = []
        var seen = Set<String>()
        func add(_ k: FTClass) { if seen.insert(k.fqn).inserted { out.append(k) } }
        let h = ev.hierarchy(owner)
        for k in h { add(k) }
        for k in h { for i in k.implements.prefix(8) { for ik in ev.hierarchy(i) { add(ik) } } }
        return out
    }

    private func docTagClasses(_ k: FTClass, facade: Bool) -> [String] {
        guard let t = text(of: k), let d = NPDoc.leading(t, before: k.declStart) else { return [] }
        let doc = NPDoc.parse(d.text, start: d.start)
        return doc.sees.compactMap { s -> String? in
            guard s.hasPrefix("\\") || s.contains("\\"), s.first != "h" else { return nil }
            return fp.resolveClass(s, in: k).map { $0 }
        }
    }

    func findMember(owners: [String], model: String?, name: String, isCall: Bool, isStatic: Bool, kindVariable: Bool) -> NPMember? {
        var visited = Set<String>()
        var queue = owners
        var extraDocOwners: [FTClass] = []
        var idx = 0
        let lname = name.lowercased()
        while idx < queue.count, idx < 12 {
            let owner = queue[idx]; idx += 1
            guard visited.insert(owner).inserted else { continue }
            let classes = searchClasses(owner)
            for k in classes {
                if kindVariable || (!isCall && isStatic) {
                    if let p = k.props.first(where: { $0.name == name }), p.isStatic || kindVariable {
                        return NPMember(kind: .property, owner: k, name: name, loc: p.loc, declStart: p.declStart, prop: p)
                    }
                }
                if isStatic, !isCall, !kindVariable {
                    if let l = k.declLocs["const:" + name] { return NPMember(kind: .constant, owner: k, name: name, loc: l.loc, declStart: l.declStart) }
                    if let l = k.declLocs["case:" + name] { return NPMember(kind: .enumCase, owner: k, name: name, loc: l.loc, declStart: l.declStart) }
                }
                if isCall {
                    if let m = k.methods.first(where: { $0.name == name }) ?? k.methods.first(where: { $0.name.lowercased() == lname }) {
                        return NPMember(kind: .method, owner: k, name: m.name, loc: m.loc, declStart: m.declStart, method: m)
                    }
                } else if !isStatic {
                    if let p = k.props.first(where: { $0.name == name && !$0.isStatic }) { return NPMember(kind: .property, owner: k, name: name, loc: p.loc, declStart: p.declStart, prop: p) }
                }
            }
            // Eloquent virtual members
            if let model, owner == model || owners.contains(model) {
                let mh = ev.hierarchy(model)
                if isCall {
                    for k in mh where k.scopes.contains(name) {
                        let sname = "scope" + name.prefix(1).uppercased() + name.dropFirst()
                        if let m = k.methods.first(where: { $0.name == sname }) {
                            return NPMember(kind: .method, owner: k, name: sname, loc: m.loc, declStart: m.declStart, method: m, extra: "Eloquent scope `\(name)`")
                        }
                    }
                } else if !isStatic {
                    for k in mh {
                        if let r = k.relations.first(where: { $0.name == name }), let m = k.methods.first(where: { $0.name == name }) {
                            let rel = r.related.map { "(\(short($0)))" } ?? ""
                            return NPMember(kind: .method, owner: k, name: name, loc: m.loc, declStart: m.declStart, method: m, extra: "Eloquent relation: `\(r.kind)\(rel)`")
                        }
                    }
                    for k in mh where k.accessors.contains(name) {
                        let camel = name.split(separator: "_").enumerated().map { $0.offset == 0 ? String($0.element) : $0.element.prefix(1).uppercased() + $0.element.dropFirst() }.joined()
                        let studly = camel.prefix(1).uppercased() + camel.dropFirst()
                        for cand in ["get\(studly)Attribute", camel] {
                            if let m = k.methods.first(where: { $0.name == cand }) {
                                return NPMember(kind: .method, owner: k, name: cand, loc: m.loc, declStart: m.declStart, method: m, extra: "Eloquent accessor for `\(name)`")
                            }
                        }
                    }
                    if let c = mh.first {
                        if let col = fp.columns(of: c).first(where: { $0.name == name }) {
                            let table = fp.tableName(of: c)
                            if let (mp, off) = migrationColumn(table: table, column: name) {
                                return NPMember(kind: .column, owner: c, name: name, loc: off, declStart: off, extra: "\(col.type)|\(table)", path: mp)
                            }
                            for k in mh {
                                for (arr, pn) in [(k.fillable, "fillable"), (k.casts, "casts"), (k.hidden, "hidden"), (k.appends, "appends"), (k.guarded, "guarded")] where arr.contains(name) {
                                    if let p = k.props.first(where: { $0.name == pn }) {
                                        return NPMember(kind: .attribute, owner: k, name: name, loc: p.loc, declStart: p.declStart, extra: "\(col.type)|\(table)")
                                    }
                                }
                            }
                            return NPMember(kind: .attribute, owner: c, name: name, loc: c.nameLoc, declStart: c.declStart, extra: "\(col.type)|\(table)")
                        }
                    }
                }
            }
            // @mixin / @see targets (facades and IDE-helper style models)
            if let first = classes.first {
                let isFacade = classes.contains { $0.fqn.hasSuffix("\\Facades\\Facade") } || first.fqn.contains("\\Facades\\")
                for k in classes.prefix(isFacade ? 3 : 1) { for t in docTagClasses(k, facade: isFacade) where !visited.contains(t) && !queue.contains(t) { queue.append(t) } }
                extraDocOwners.append(contentsOf: classes.prefix(4))
            }
            // Eloquent forwards unknown calls to the query builder
            if let model, owner == model, isCall || !isStatic, !queue.contains(Self.eloquentBuilder) {
                if isCall { queue.append(Self.eloquentBuilder); queue.append(Self.queryBuilder) }
            }
        }
        // @property / @method tags in the owner's docblocks (IDE-helper annotations, facade @method static ...)
        var seenDoc = Set<String>()
        for k in extraDocOwners where seenDoc.insert(k.fqn).inserted {
            guard let t = text(of: k), let d = NPDoc.leading(t, before: k.declStart) else { continue }
            let doc = NPDoc.parse(d.text, start: d.start)
            if isCall, let m = doc.methods.first(where: { $0.name == name }) {
                return NPMember(kind: .docMethod, owner: k, name: name, loc: m.loc, declStart: m.loc, extra: m.line)
            }
            if !isCall, let p = doc.props.first(where: { $0.name == name }) {
                return NPMember(kind: .docProperty, owner: k, name: name, loc: p.loc, declStart: p.loc, extra: p.type)
            }
        }
        return nil
    }

    // MARK: Migration columns

    private func migrationColumn(table: String, column: String) -> (String, Int)? {
        let dir = fp.path + "/database/migrations"
        let all = LaravelFS.list(dir).filter { $0.hasSuffix(".php") }.sorted()
        guard !all.isEmpty else { return nil }
        let esc = NSRegularExpression.escapedPattern(for: column)
        var patterns = ["->\\w+\\(\\s*['\"]\(esc)['\"]"]
        switch column {
        case "id": patterns.insert("->id\\(", at: 0)
        case "created_at", "updated_at": patterns.insert("->(?:timestamps|timestampsTz|nullableTimestamps)\\(", at: 0)
        case "deleted_at": patterns.insert("->softDeletes(?:Tz)?\\(", at: 0)
        case "remember_token": patterns.insert("->rememberToken\\(", at: 0)
        default:
            if column.hasSuffix("_type") || column.hasSuffix("_id") {
                let base = NSRegularExpression.escapedPattern(for: String(column.dropLast(column.hasSuffix("_type") ? 5 : 3)))
                patterns.append("->(?:nullable|uuid|ulid)?[mM]orphs\\(\\s*['\"]\(base)['\"]")
            }
        }
        let regexes = patterns.compactMap { try? NSRegularExpression(pattern: $0) }
        let tableQuoted = ["'" + table + "'", "\"" + table + "\""]
        let preferred = all.filter { $0.contains(table) }
        for list in [preferred, all.filter { !$0.contains(table) }] {
            for f in list {
                guard let t = NPFiles.text(dir + "/" + f), tableQuoted.contains(where: { t.range(of: $0).location != NSNotFound }) else { continue }
                for re in regexes {
                    if let m = re.firstMatch(in: t as String, range: NSRange(location: 0, length: t.length)) {
                        // point at the quoted column name when present, else the method name
                        var off = m.range.location + 2
                        let sub = t.substring(with: m.range)
                        if let q = sub.range(of: "'" + column) ?? sub.range(of: "\"" + column) { off = m.range.location + sub.utf16.distance(from: sub.startIndex, to: q.lowerBound) + 1 }
                        return (dir + "/" + f, off)
                    }
                }
            }
        }
        return nil
    }

    // MARK: Member output

    func memberHit(_ mem: NPMember, _ range: NSRange) -> NPHit? {
        guard let path = mem.path ?? self.path(of: mem.owner) else { return nil }
        var targets: [NPTarget] = []
        if let t = target(path: path, offset: mem.loc) { targets.append(t) }
        return NPHit(range: range, targets: targets, markdown: memberMarkdown(mem), kind: mem.kind == .method ? "method" : mem.kind.rawValue)
    }

    private func visWord(_ v: Int) -> String { v == 2 ? "private " : v == 1 ? "protected " : "public " }

    private func memberMarkdown(_ mem: NPMember) -> String {
        if light { return "" }
        var sig = ""
        var docNS: NSString?
        let docPos = mem.declStart
        let ownerPath = mem.path ?? path(of: mem.owner)
        if mem.path == nil, let ownerPath { docNS = text(ofFile: ownerPath) }
        switch mem.kind {
        case .method:
            let m = mem.method!
            sig = visWord(m.vis) + (m.isStatic ? "static " : "") + "function \(m.name)(\(m.params))" + (m.ret.isEmpty ? "" : ": " + m.ret)
        case .property:
            let p = mem.prop!
            sig = visWord(p.vis) + (p.isStatic ? "static " : "") + (p.type.isEmpty ? "" : p.type + " ") + "$" + p.name
        case .constant, .enumCase:
            if let t = docNS { sig = NPText.lineText(t, mem.loc, maxLen: 160) }
            if sig.isEmpty { sig = "const \(mem.name)" }
        case .column:
            let parts = mem.extra.split(separator: "|").map(String.init)
            sig = "(column) \(mem.name): \(parts.first ?? "")"
            docNS = nil
        case .attribute:
            let parts = mem.extra.split(separator: "|").map(String.init)
            sig = "(attribute) \(mem.name): \(parts.first ?? "")"
            docNS = nil
        case .docProperty:
            sig = "(property) \(mem.extra) $\(mem.name)"
            docNS = nil
        case .docMethod:
            sig = "(method) " + mem.extra
            docNS = nil
        }
        var out = "```php\n\(sig)\n```"
        if let docNS, let d = NPDoc.leading(docNS, before: docPos) {
            var doc = NPDoc.parse(d.text, start: d.start)
            if mem.kind == .property, let v = doc.varType, doc.summary.isEmpty { doc.summary = "`\(v)`" }
            let md = doc.markdown()
            if !md.isEmpty { out += "\n\n" + md }
        }
        switch mem.kind {
        case .column:
            let parts = mem.extra.split(separator: "|").map(String.init)
            out += "\n\nColumn of table `\(parts.count > 1 ? parts[1] : "")` on `\(mem.owner.name)`."
        case .attribute:
            let parts = mem.extra.split(separator: "|").map(String.init)
            out += "\n\nModel attribute (table `\(parts.count > 1 ? parts[1] : "")`)."
        default: break
        }
        if !mem.extra.isEmpty, mem.kind == .method { out += "\n\n" + mem.extra }
        out += "\n\n" + originLine(owner: mem.owner.fqn, path: ownerPath, offset: mem.loc)
        return out
    }
}
