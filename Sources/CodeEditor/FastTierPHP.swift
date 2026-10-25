import Foundation

// Fast-tier PHP declaration parser. Built on the cheap PHPLex tokenizer (no tree-sitter tree is retained), it extracts
// just what completion needs from one PHP file: namespace, `use` imports, the first type declaration with its
// parents/traits, methods, properties, constants and the Eloquent bits (table, fillable, casts, relations, scopes).

struct FTMethod {
    var name: String
    var isStatic: Bool
    var vis: Int            // 0 public, 1 protected, 2 private
    var params: String      // "Foo $x, int $y = 1" (whitespace collapsed)
    var ret: String         // raw return type text, "" when undeclared
    var loc = 0             // UTF-16 offset of the name token (NativePHP go-to / hover)
    var declStart = 0       // offset of the first modifier / `function` (docblock lookup starts before it)
}

struct FTProp {
    var name: String
    var type: String
    var isStatic: Bool
    var vis: Int
    var loc = 0
    var declStart = 0
}

struct FTLoc { var loc: Int; var declStart: Int }

struct FTRelation {
    var name: String
    var kind: String        // hasMany, belongsTo, ...
    var related: String?    // resolved FQN
}

struct FTUseStmt {
    var fqn: String
    var alias: String
    var lineStart: Int      // UTF-16 offset of the line holding the statement
    var lineEnd: Int        // offset just after the newline that ends it
}

final class FTClass {
    var fqn = "", name = "", kind = "class", ns = ""
    var extends: String?
    var implements: [String] = []
    var traits: [String] = []
    var methods: [FTMethod] = []
    var props: [FTProp] = []
    var consts: [String] = []
    var cases: [String] = []
    var uses: [String: String] = [:]
    var useStmts: [FTUseStmt] = []
    var nsLineEnd: Int?
    var openTagEnd: Int?
    var isAbstract = false
    var nameLoc = 0                 // offset of the class name token
    var declStart = 0               // offset of the first modifier / class keyword
    var declLocs: [String: FTLoc] = [:]   // "const:NAME" / "case:NAME" -> position
    // Eloquent
    var table: String?
    var fillable: [String] = []
    var guarded: [String] = []
    var hidden: [String] = []
    var casts: [String] = []
    var castTypes: [String: String] = [:]    // attribute -> cast type text ('datetime', 'boolean', 'array', 'decimal:2' ...)
    var appends: [String] = []
    var relations: [FTRelation] = []
    var scopes: [String] = []
    var accessors: [String] = []

    /// Rough retained size (string payloads + per-member struct overhead) for the byte-capped class cache.
    var approxBytes: Int {
        var n = 400 + fqn.utf8.count + name.utf8.count + ns.utf8.count
        for m in methods { n += 120 + m.name.utf8.count + m.params.utf8.count + m.ret.utf8.count }
        for p in props { n += 100 + p.name.utf8.count + p.type.utf8.count }
        for (k, v) in castTypes { n += 60 + k.utf8.count + v.utf8.count }
        for s in traits + implements + consts + cases + fillable + guarded + hidden + casts + appends + scopes + accessors { n += 40 + s.utf8.count }
        for (k, v) in uses { n += 80 + k.utf8.count + v.utf8.count }
        n += useStmts.count * 100 + declLocs.count * 90 + relations.count * 120
        return n
    }

    /// Method by exact name, else case-insensitively (PHP method names are case-insensitive); no allocation.
    func method(named name: String) -> FTMethod? {
        for m in methods where m.name == name { return m }
        let n = name.utf8.count
        for m in methods where m.name.utf8.count == n && FTClass.equalsIgnoringASCIICase(m.name, name) { return m }
        return nil
    }

    static func equalsIgnoringASCIICase(_ a: String, _ b: String) -> Bool {
        var x = a.utf8.makeIterator(), y = b.utf8.makeIterator()
        while let c = x.next() {
            guard let d = y.next() else { return false }
            let lc = (c >= 65 && c <= 90) ? c + 32 : c, ld = (d >= 65 && d <= 90) ? d + 32 : d
            if lc != ld { return false }
        }
        return y.next() == nil
    }

    /// Resolves a name as written in this file to an FQN (no leading backslash).
    func resolve(_ written: String) -> String {
        var name = written
        if name.hasPrefix("\\") { return String(name.dropFirst()) }
        if name.hasPrefix("namespace\\") { name = String(name.dropFirst(10)) }
        let first = name.split(separator: "\\", maxSplits: 1).first.map(String.init) ?? name
        if let full = uses[first] {
            return name.count > first.count ? full + String(name.dropFirst(first.count)) : full
        }
        return ns.isEmpty ? name : ns + "\\" + name
    }

    /// Strips nullable/union noise from a raw type and resolves the first class-like member; nil for scalars/unknown.
    func classType(_ raw: String) -> String? {
        FTClass.firstClassName(raw).map { resolveSpecial($0) }
    }

    private func resolveSpecial(_ n: String) -> String {
        let l = n.lowercased()
        if l == "self" || l == "static" || l == "$this" { return fqn }
        if l == "parent" { return extends ?? "" }
        return resolve(n)
    }

    static let builtinTypes: Set<String> = ["int", "float", "string", "bool", "array", "mixed", "void", "null", "callable", "iterable",
                                            "object", "never", "false", "true", "integer", "boolean", "double", "resource"]

    static func firstClassName(_ raw: String) -> String? {
        for part in raw.split(whereSeparator: { $0 == "|" || $0 == "&" || $0 == "(" || $0 == ")" }) {
            var p = part.trimmingCharacters(in: .whitespaces)
            if p.hasPrefix("?") { p.removeFirst() }
            if p.isEmpty || builtinTypes.contains(p.lowercased()) { continue }
            return p
        }
        return nil
    }
}

enum FTParser {
    static let relationKinds: Set<String> = ["hasOne", "hasMany", "belongsTo", "belongsToMany", "morphTo", "morphOne", "morphMany",
                                             "morphToMany", "morphedByMany", "hasOneThrough", "hasManyThrough"]
    static let singleRelations: Set<String> = ["hasOne", "belongsTo", "morphTo", "morphOne", "hasOneThrough"]
    private static let modifiers: Set<String> = ["public", "protected", "private", "static", "abstract", "final", "readonly", "var"]
    private static let eloquentArrays: Set<String> = ["table", "fillable", "guarded", "hidden", "casts", "appends"]

    static func snake(_ s: String) -> String {
        var out = ""
        for (i, ch) in s.enumerated() {
            if ch.isUppercase {
                if i > 0, let last = out.last, last != "_" { out.append("_") }
                out.append(contentsOf: ch.lowercased())
            } else { out.append(ch) }
        }
        return out
    }

    static func parse(_ text: NSString, lex given: PHPLex? = nil) -> FTClass? {
        let lex = given ?? PHPLex(text)
        let n = lex.count
        let c = FTClass()
        var i = 0
        func tokEnd(_ k: Int) -> Int { lex.toks[k].loc + lex.toks[k].len }
        func lineEnd(after loc: Int) -> Int {
            let r = text.lineRange(for: NSRange(location: min(loc, max(0, text.length - 1)), length: 0))
            return r.upperBound
        }
        // <?php open tag end
        if n >= 3, lex.isPunct(0, "<"), lex.isPunct(1, "?"), lex.isIdent(2, "php") { c.openTagEnd = lineEnd(after: lex.toks[2].loc) }
        var declIndex = -1
        while i < n {
            if lex.toks[i].kind == .ident {
                let w = lex.text(i)
                if w == "namespace", i + 1 < n, lex.toks[i + 1].kind == .ident, !lex.isPunct(i - 1, code: PHPTok.dcolon), !lex.isPunct(i - 1, code: PHPTok.arrow) {
                    c.ns = lex.text(i + 1)
                    if lex.isPunct(i + 2, ";") { c.nsLineEnd = lineEnd(after: lex.toks[i + 2].loc) }
                    i += 2; continue
                }
                if w == "use", i + 1 < n, lex.toks[i + 1].kind == .ident, !lex.isPunct(i - 1, code: PHPTok.arrow) {
                    parseUse(lex, text, &i, c)
                    continue
                }
                if (w == "class" || w == "interface" || w == "trait" || w == "enum"), i + 1 < n, lex.toks[i + 1].kind == .ident,
                   !lex.isPunct(i - 1, code: PHPTok.dcolon), !lex.isIdent(i - 1, "new"), !lex.isPunct(i - 1, code: PHPTok.arrow) {
                    declIndex = i
                    break
                }
            }
            // skip balanced blocks at top level (functions, if) but not a leading `namespace X { }`
            if lex.toks[i].kind == .punct, [40, 91, 123].contains(lex.toks[i].ch), lex.match[i] > i { i = lex.match[i] + 1 } else { i += 1 }
        }
        guard declIndex >= 0 else { return c }
        c.kind = lex.text(declIndex)
        c.name = lex.text(declIndex + 1)
        c.nameLoc = lex.toks[declIndex + 1].loc
        c.declStart = lex.toks[declIndex].loc
        c.fqn = c.ns.isEmpty ? c.name : c.ns + "\\" + c.name
        var j = declIndex - 1
        while j >= 0, lex.toks[j].kind == .ident, ["abstract", "final", "readonly"].contains(lex.text(j)) {
            if lex.text(j) == "abstract" { c.isAbstract = true }
            c.declStart = lex.toks[j].loc
            j -= 1
        }
        // header
        var k = declIndex + 2
        var mode = ""
        var open = -1
        while k < n {
            let t = lex.toks[k]
            if t.kind == .punct, t.ch == 123 { open = k; break }
            if t.kind == .ident {
                let w = lex.text(k)
                if w == "extends" || w == "implements" { mode = w }
                else if mode == "extends" {
                    if c.kind == "interface" { c.implements.append(c.resolve(w)) } else if c.extends == nil { c.extends = c.resolve(w) }
                } else if mode == "implements" { c.implements.append(c.resolve(w)) }
            }
            k += 1
        }
        guard open >= 0 else { return c }
        let close = lex.match[open] > open ? lex.match[open] : n
        parseBody(lex, text, c, open + 1, close)
        return c
    }

    private static func parseUse(_ lex: PHPLex, _ text: NSString, _ i: inout Int, _ c: FTClass) {
        let n = lex.count
        let start = i
        var j = i + 1
        if lex.isIdent(j, "function") || lex.isIdent(j, "const") {
            while j < n, !lex.isPunct(j, ";") { j += 1 }
            i = j + 1; return
        }
        var items: [(String, String)] = []
        var prefix = ""
        var current = ""
        var alias: String?
        func flush() {
            guard !current.isEmpty else { return }
            let full = (prefix + current).trimmingCharacters(in: CharacterSet(charactersIn: "\\"))
            let a = alias ?? String(full.split(separator: "\\").last ?? "")
            if !a.isEmpty { items.append((full, a)) }
            current = ""; alias = nil
        }
        var afterAs = false
        while j < n, !lex.isPunct(j, ";") {
            let t = lex.toks[j]
            if t.kind == .ident {
                let w = lex.text(j)
                if w == "as" { afterAs = true }
                else if afterAs { alias = w; afterAs = false }
                else if lex.isPunct(j + 1, "{") { prefix = w }      // group: `use A\B\{C, D}`
                else { current = w }
            } else if t.kind == .punct, t.ch == 44 { flush() }
            j += 1
            if j >= n { break }
            if lex.isPunct(j, "}") { flush() }
        }
        flush()
        let endLoc = j < n ? lex.toks[j].loc : text.length
        let ls = text.lineRange(for: NSRange(location: lex.toks[start].loc, length: 0)).location
        let le = text.lineRange(for: NSRange(location: min(endLoc, max(0, text.length - 1)), length: 0)).upperBound
        for (full, a) in items {
            c.uses[a] = full
            c.useStmts.append(FTUseStmt(fqn: full, alias: a, lineStart: ls, lineEnd: le))
        }
        i = j + 1
    }

    private static func parseBody(_ lex: PHPLex, _ text: NSString, _ c: FTClass, _ from: Int, _ to: Int) {
        var k = from
        var mods = Set<String>()
        var typeText = ""
        var declStart = -1
        func reset() { mods.removeAll(); typeText = ""; declStart = -1 }
        func vis() -> Int { mods.contains("private") ? 2 : mods.contains("protected") ? 1 : 0 }
        while k < to {
            let t = lex.toks[k]
            switch t.kind {
            case .punct:
                if t.ch == 35, lex.isPunct(k + 1, "["), lex.match[k + 1] > k { k = lex.match[k + 1] + 1; continue }   // #[Attribute]
                if t.ch == 59 { reset(); k += 1; continue }
                if [40, 91, 123].contains(t.ch), lex.match[k] > k { k = lex.match[k] + 1; continue }
                typeText += lex.text(k)
                k += 1
            case .ident:
                let w = lex.text(k)
                if declStart < 0 { declStart = t.loc }
                if modifiers.contains(w) { mods.insert(w); k += 1; continue }
                if w == "use" && typeText.isEmpty {
                    k += 1
                    while k < to, !lex.isPunct(k, ";"), !lex.isPunct(k, "{") {
                        if lex.toks[k].kind == .ident { c.traits.append(c.resolve(lex.text(k))) }
                        k += 1
                    }
                    if k < to, lex.isPunct(k, "{"), lex.match[k] > k { k = lex.match[k] + 1 } else { k += 1 }
                    reset(); continue
                }
                if w == "const" && typeText.isEmpty {
                    var name = ""
                    var nameLoc = 0
                    k += 1
                    while k < to, !lex.isPunct(k, ";") {
                        if lex.isPunct(k, "=") { break }
                        if lex.toks[k].kind == .ident { name = lex.text(k); nameLoc = lex.toks[k].loc }
                        k += 1
                    }
                    if !name.isEmpty { c.consts.append(name); c.declLocs["const:" + name] = FTLoc(loc: nameLoc, declStart: declStart) }
                    while k < to, !lex.isPunct(k, ";") {
                        if lex.toks[k].kind == .punct, [40, 91, 123].contains(lex.toks[k].ch), lex.match[k] > k { k = lex.match[k] + 1 } else { k += 1 }
                    }
                    k += 1; reset(); continue
                }
                if w == "case", c.kind == "enum", k + 1 < to, lex.toks[k + 1].kind == .ident {
                    c.cases.append(lex.text(k + 1))
                    c.declLocs["case:" + lex.text(k + 1)] = FTLoc(loc: lex.toks[k + 1].loc, declStart: declStart)
                    while k < to, !lex.isPunct(k, ";") { k += 1 }
                    k += 1; reset(); continue
                }
                if w == "function" {
                    k = parseFunction(lex, text, c, k, to, mods: mods, declStart: declStart)
                    reset(); continue
                }
                typeText += (typeText.isEmpty || typeText.hasSuffix("?") || typeText.hasSuffix("|") ? "" : " ") + w
                k += 1
            case .variable:
                let name = String(lex.text(k).dropFirst())
                c.props.append(FTProp(name: name, type: typeText, isStatic: mods.contains("static"), vis: vis(), loc: t.loc, declStart: declStart < 0 ? t.loc : declStart))
                k += 1
                if lex.isPunct(k, "="), eloquentArrays.contains(name) {
                    k = parseDefault(lex, c, name, k + 1, to)
                }
                while k < to, !lex.isPunct(k, ";") {
                    if lex.toks[k].kind == .punct, [40, 91, 123].contains(lex.toks[k].ch), lex.match[k] > k { k = lex.match[k] + 1 } else { k += 1 }
                }
                k += 1; reset()
            default:
                k += 1
            }
        }
    }

    private static func parseDefault(_ lex: PHPLex, _ c: FTClass, _ name: String, _ at: Int, _ to: Int) -> Int {
        var k = at
        var arr = -1
        if lex.isPunct(k, "[") { arr = k }
        else if lex.isIdent(k, "array"), lex.isPunct(k + 1, "(") { arr = k + 1 }
        if name == "table" {
            if k < to, lex.toks[k].kind == .string { c.table = lex.strValue(k) }
            return k
        }
        guard arr >= 0, lex.match[arr] > arr else { return k }
        let end = lex.match[arr]
        var keysOnly = name == "casts"
        var i = arr + 1
        var values: [String] = []
        while i < end {
            if lex.toks[i].kind == .string {
                if keysOnly { if lex.isPunct(i + 1, code: PHPTok.fat) { values.append(lex.strValue(i)); if i + 2 < end, lex.toks[i + 2].kind == .string { c.castTypes[lex.strValue(i)] = lex.strValue(i + 2) } } }
                else { values.append(lex.strValue(i)) }
                if keysOnly, lex.isPunct(i + 1, code: PHPTok.fat) { i += 2; continue }
            } else if lex.toks[i].kind == .punct, [40, 91, 123].contains(lex.toks[i].ch), lex.match[i] > i { i = lex.match[i] + 1; continue }
            i += 1
        }
        keysOnly = false
        switch name {
        case "fillable": c.fillable = values
        case "guarded": c.guarded = values
        case "hidden": c.hidden = values
        case "casts": c.casts = values
        case "appends": c.appends = values
        default: break
        }
        return end + 1
    }

    private static func parseFunction(_ lex: PHPLex, _ text: NSString, _ c: FTClass, _ at: Int, _ to: Int, mods: Set<String>, declStart: Int = -1) -> Int {
        var k = at + 1
        if lex.isPunct(k, "&") { k += 1 }
        guard k < to, lex.toks[k].kind == .ident else { return k }
        let name = lex.text(k)
        let nameTok = k
        k += 1
        guard lex.isPunct(k, "("), lex.match[k] > k else { return k }
        let pOpen = k, pClose = lex.match[k]
        let paramsText = text.substring(with: NSRange(location: lex.toks[pOpen].loc + 1, length: max(0, lex.toks[pClose].loc - lex.toks[pOpen].loc - 1)))
        let params = paramsText.split(whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == "\t" || $0 == " " }).joined(separator: " ")
        let isStatic = mods.contains("static")
        let vis = mods.contains("private") ? 2 : mods.contains("protected") ? 1 : 0
        if name == "__construct" { promoted(lex, c, pOpen + 1, pClose) }
        k = pClose + 1
        var ret = ""
        if lex.isPunct(k, ":") {
            k += 1
            while k < to, !lex.isPunct(k, "{"), !lex.isPunct(k, ";") {
                ret += lex.text(k)
                k += 1
            }
        }
        c.methods.append(FTMethod(name: name, isStatic: isStatic, vis: vis, params: params, ret: ret, loc: lex.toks[nameTok].loc,
                                  declStart: declStart < 0 ? lex.toks[at].loc : declStart))
        var bodyFrom = -1, bodyTo = -1
        if k < to, lex.isPunct(k, "{"), lex.match[k] > k { bodyFrom = k + 1; bodyTo = lex.match[k]; k = lex.match[k] + 1 } else { k += 1 }

        // Eloquent facts
        if vis != 2, !isStatic {
            if name.hasPrefix("scope"), name.count > 5, let f = name.dropFirst(5).first, f.isUppercase {
                let s = String(name.dropFirst(5))
                c.scopes.append(s.prefix(1).lowercased() + s.dropFirst())
            } else if name.hasPrefix("get"), name.hasSuffix("Attribute"), name.count > 12 {
                c.accessors.append(snake(String(name.dropFirst(3).dropLast(9))))
            } else if ret.hasSuffix("Attribute"), bodyFrom >= 0 {
                c.accessors.append(snake(name))
            }
        }
        if bodyFrom >= 0, !isStatic {
            var kind: String?
            var related: String?
            var q = bodyFrom
            while q < bodyTo {
                if lex.isPunct(q, code: PHPTok.arrow), q + 2 < bodyTo, lex.toks[q + 1].kind == .ident, relationKinds.contains(lex.text(q + 1)), lex.isPunct(q + 2, "(") {
                    kind = lex.text(q + 1)
                    let a = q + 3
                    if a < bodyTo {
                        if lex.toks[a].kind == .ident, lex.isPunct(a + 1, code: PHPTok.dcolon), lex.isIdent(a + 2, "class") { related = c.resolve(lex.text(a)) }
                        else if lex.toks[a].kind == .string { related = c.resolve(lex.strValue(a)) }
                    }
                    break
                }
                q += 1
            }
            if let kind { c.relations.append(FTRelation(name: name, kind: kind, related: related)) }
            else if let r = relationKinds.first(where: { ret.hasSuffix(String($0.prefix(1).uppercased() + $0.dropFirst())) }) {
                c.relations.append(FTRelation(name: name, kind: r, related: nil))
            }
            if name == "casts", bodyFrom >= 0 {
                var q2 = bodyFrom
                while q2 < bodyTo {
                    if lex.toks[q2].kind == .string, lex.isPunct(q2 + 1, code: PHPTok.fat) {
                        c.casts.append(lex.strValue(q2))
                        if q2 + 2 < bodyTo, lex.toks[q2 + 2].kind == .string { c.castTypes[lex.strValue(q2)] = lex.strValue(q2 + 2) }
                    }
                    q2 += 1
                }
            }
        }
        return k
    }

    private static func promoted(_ lex: PHPLex, _ c: FTClass, _ from: Int, _ to: Int) {
        var depth = 0
        var segStart = from
        var i = from
        func seg(_ a: Int, _ b: Int) {
            guard a < b else { return }
            var v = 0, isProm = false
            var varLoc = 0
            var type = ""
            var name: String?
            for q in a..<b {
                let t = lex.toks[q]
                if t.kind == .ident {
                    let w = lex.text(q)
                    if w == "private" { v = 2; isProm = true } else if w == "protected" { v = 1; isProm = true }
                    else if w == "public" || w == "readonly" { isProm = true }
                    else if name == nil { type += w }
                } else if t.kind == .variable, name == nil { name = String(lex.text(q).dropFirst()); varLoc = t.loc }
                else if t.kind == .punct, name == nil, t.ch == 63 || t.ch == 124 { type += lex.text(q) }
            }
            if isProm, let name { c.props.append(FTProp(name: name, type: type, isStatic: false, vis: v, loc: varLoc, declStart: lex.toks[a].loc)) }
        }
        while i < to {
            let t = lex.toks[i]
            if t.kind == .punct {
                if [40, 91, 123].contains(t.ch) { depth += 1 } else if [41, 93, 125].contains(t.ch) { depth -= 1 }
                else if t.ch == 44, depth == 0 { seg(segStart, i); segStart = i + 1 }
            }
            i += 1
        }
        seg(segStart, to)
    }
}
