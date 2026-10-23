import Foundation

/// A top-level `use` import entry.
struct NPImport {
    var kind: String            // class, function, const
    var fqn: String             // no leading backslash
    var alias: String
    var nameTok: Int
    var range: NSRange          // name .. alias
    var viaGroup: Bool
}

/// A class-like declaration found in the file.
struct NPTypeDecl {
    var keyword: Int            // index of class / interface / trait / enum token
    var name: String?           // nil for anonymous classes
    var open: Int               // index of "{"
    var close: Int
    var anonymous: Bool
    var kind: String
}

/// Token-level facts shared by every native diagnostic rule: brace kinds, imports, namespace, declared types.
final class NPDiagContext {
    let fp: FastProject
    let url: URL
    let ns: NSString
    let lex: PHPLex
    let toks: [PHPTok]
    let n: Int
    let classSeverity: Int

    /// Per token: 0 top level / namespace braces, 1 directly inside a class-like body, 2 inside any other braces.
    private(set) var kind: [UInt8]
    private(set) var typeDecls: [NPTypeDecl] = []
    private(set) var imports: [NPImport] = []
    private(set) var inImport: [Bool]
    private(set) var namespace = ""
    private(set) var namespaceCount = 0
    private(set) var localTypes = Set<String>()        // lowercased FQNs declared in this file
    private var words: [String?]
    static let filesLock = NSLock()
    static var filesCache: [String: (stamp: Int64, names: Set<String>)] = [:]

    init(fp: FastProject, url: URL, text: NSString, lex: PHPLex, classSeverity: Int) {
        self.fp = fp; self.url = url; ns = text; self.lex = lex; toks = lex.toks; n = lex.count; self.classSeverity = classSeverity
        kind = [UInt8](repeating: 0, count: lex.count)
        inImport = [Bool](repeating: false, count: lex.count)
        words = [String?](repeating: nil, count: lex.count)
        prepare()
    }

    /// Function scopes and variable classification, built once per pass.
    lazy var flow: NPFlow = NPFlow(self)
    /// Named functions declared outside class bodies: (keyword index, name token index).
    lazy var localFunctions: [(Int, Int)] = {
        var out: [(Int, Int)] = []
        for i in 0..<n where toks[i].kind == .ident && kind[i] != 1 && !isMember(i) && !inImport[i] && lower(i) == "function" {
            var j = i + 1
            if punct(j, "&") { j += 1 }
            if isIdent(j), j + 1 < n, punct(j + 1, "(") { out.append((i, j)) }
        }
        return out
    }()

    // MARK: Token helpers

    func text(_ i: Int) -> String {
        if let w = words[i] { return w }
        let w = lex.text(i)
        words[i] = w
        return w
    }
    func lower(_ i: Int) -> String { text(i).lowercased() }
    func isIdent(_ i: Int) -> Bool { i >= 0 && i < n && toks[i].kind == .ident }
    func kw(_ i: Int, _ s: String) -> Bool { i >= 0 && i < n && toks[i].kind == .ident && toks[i].len == s.utf16.count && lower(i) == s }
    func punct(_ i: Int, _ c: Character) -> Bool { lex.isPunct(i, c) }
    func isArrow(_ i: Int) -> Bool { lex.isPunct(i, code: PHPTok.arrow) }
    func isDColon(_ i: Int) -> Bool { lex.isPunct(i, code: PHPTok.dcolon) }
    func isFat(_ i: Int) -> Bool { lex.isPunct(i, code: PHPTok.fat) }
    func range(_ i: Int) -> NSRange { NSRange(location: toks[i].loc, length: toks[i].len) }
    func isVariable(_ i: Int) -> Bool { i >= 0 && i < n && toks[i].kind == .variable }
    /// Previous token is `->`, `?->` or `::` (the token is a member name, not a free-standing name).
    func isMember(_ i: Int) -> Bool { i > 0 && (isArrow(i - 1) || isDColon(i - 1)) }
    func match(_ i: Int) -> Int { lex.match[i] }

    // MARK: Preparation

    private func prepare() {
        // Brace kinds.
        var stack: [UInt8] = []
        for i in 0..<n {
            let t = toks[i]
            if t.kind == .punct, t.ch == 123 {
                kind[i] = stack.last ?? 0
                let k = braceKind(i)
                stack.append(k)
                continue
            }
            if t.kind == .punct, t.ch == 125 {
                if !stack.isEmpty { stack.removeLast() }
                kind[i] = stack.last ?? 0
                continue
            }
            kind[i] = stack.last ?? 0
        }
        // Type declarations, namespace, imports.
        for i in 0..<n where toks[i].kind == .ident {
            let l = lower(i)
            if (l == "class" || l == "interface" || l == "trait" || l == "enum"), !isMember(i) {
                declare(i, l)
            } else if l == "namespace", kind[i] == 0, !isMember(i) {
                if i + 1 < n, isIdent(i + 1) { namespaceCount += 1; if namespaceCount == 1 { namespace = trimSlash(text(i + 1)) } }
                else if i + 1 < n, punct(i + 1, "{") { namespaceCount += 1 }
            }
        }
        for i in 0..<n where toks[i].kind == .ident && kind[i] == 0 && !inImport[i] && lower(i) == "use" && !isMember(i) {
            if i + 1 < n, !punct(i + 1, "(") { parseImport(i) }
        }
        for d in typeDecls { if let nm = d.name { localTypes.insert((namespace.isEmpty ? nm : namespace + "\\" + nm).lowercased()) } }
    }

    private func trimSlash(_ s: String) -> String {
        var s = s
        if s.hasPrefix("\\") { s.removeFirst() }
        if s.hasSuffix("\\") { s.removeLast() }
        return s
    }

    private func braceKind(_ b: Int) -> UInt8 {
        var j = b - 1
        var steps = 0
        while j >= 0, steps < 400 {
            let t = toks[j]
            if t.kind == .punct, t.ch == 59 || t.ch == 123 || t.ch == 125 { return 2 }
            if t.kind == .ident, !isMember(j) {
                let l = lower(j)
                switch l {
                case "class", "interface", "trait": return 1
                case "enum": if j + 1 < b, isIdent(j + 1) { return 1 }
                case "namespace": return 0
                case "function", "fn": return 2
                default: break
                }
            }
            j -= 1; steps += 1
        }
        return 2
    }

    private func declare(_ i: Int, _ l: String) {
        // anonymous: `new class (...) extends X {`
        var anon = false
        if l == "class", i > 0, kw(i - 1, "new") { anon = true }
        var name: String?
        var j = i + 1
        if !anon {
            guard j < n, isIdent(j) else { return }
            let nm = text(j)
            if l == "class" || l == "enum", ["extends", "implements"].contains(nm.lowercased()) { anon = true } else { name = nm }
        }
        // find the body brace
        var steps = 0
        while j < n, steps < 400 {
            let t = toks[j]
            if t.kind == .punct, t.ch == 123 { break }
            if t.kind == .punct, t.ch == 59 { return }
            if t.kind == .punct, t.ch == 40, lex.match[j] > j { j = lex.match[j] }
            j += 1; steps += 1
        }
        guard j < n, lex.match[j] > j else { return }
        typeDecls.append(NPTypeDecl(keyword: i, name: name, open: j, close: lex.match[j], anonymous: anon, kind: l))
    }

    private func parseImport(_ i: Int) {
        var j = i + 1
        var impKind = "class"
        if kw(j, "function") { impKind = "function"; j += 1 } else if kw(j, "const") { impKind = "const"; j += 1 }
        var entries: [NPImport] = []
        var guardCount = 0
        parse: while j < n, guardCount < 200 {
            guardCount += 1
            guard isIdent(j) else { break }
            let raw = text(j)
            if raw.hasSuffix("\\"), j + 1 < n, punct(j + 1, "{") {
                let prefix = trimSlash(raw)
                let close = lex.match[j + 1]
                guard close > j + 1 else { break parse }
                var k = j + 2
                while k < close {
                    var kd = impKind
                    if kw(k, "function"), isIdent(k + 1) { kd = "function"; k += 1 } else if kw(k, "const"), isIdent(k + 1) { kd = "const"; k += 1 }
                    guard isIdent(k) else { k += 1; continue }
                    let nameTok = k
                    let full = prefix + "\\" + trimSlash(text(k))
                    var alias = String(full.split(separator: "\\").last ?? "")
                    var end = toks[k].loc + toks[k].len
                    k += 1
                    if kw(k, "as"), isIdent(k + 1) { alias = text(k + 1); end = toks[k + 1].loc + toks[k + 1].len; k += 2 }
                    entries.append(NPImport(kind: kd, fqn: full, alias: alias, nameTok: nameTok,
                                            range: NSRange(location: toks[nameTok].loc, length: end - toks[nameTok].loc), viaGroup: true))
                    if punct(k, ",") { k += 1 }
                }
                j = close + 1
            } else {
                let full = trimSlash(raw)
                let nameTok = j
                var alias = String(full.split(separator: "\\").last ?? "")
                var end = toks[j].loc + toks[j].len
                j += 1
                if kw(j, "as"), isIdent(j + 1) { alias = text(j + 1); end = toks[j + 1].loc + toks[j + 1].len; j += 2 }
                entries.append(NPImport(kind: impKind, fqn: full, alias: alias, nameTok: nameTok,
                                        range: NSRange(location: toks[nameTok].loc, length: end - toks[nameTok].loc), viaGroup: false))
            }
            if punct(j, ",") { j += 1; continue }
            break
        }
        // statement end
        var e = j
        while e < n, !punct(e, ";"), e < j + 4 { e += 1 }
        for k in i...min(e, n - 1) { inImport[k] = true }
        imports += entries
    }

    // MARK: Namespace-aware names

    /// Resolves a name as written to an FQN (no leading backslash) using class imports, else the file namespace.
    func resolve(_ written: String) -> (fqn: String, viaImport: NPImport?) {
        if written.hasPrefix("\\") { return (String(written.dropFirst()), nil) }
        var name = written
        if name.lowercased().hasPrefix("namespace\\") { name = String(name.dropFirst(10)); return (namespace.isEmpty ? name : namespace + "\\" + name, nil) }
        let first = name.split(separator: "\\", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? name
        let fl = first.lowercased()
        if let imp = imports.first(where: { $0.kind == "class" && $0.alias.lowercased() == fl }) {
            let rest = name.count > first.count ? String(name.dropFirst(first.count)) : ""
            return (imp.fqn + rest, imp)
        }
        return (namespace.isEmpty ? name : namespace + "\\" + name, nil)
    }

    // MARK: Word usage (docblocks, strings and code all count as a use of an import)

    /// Lowercased first path segment of every word in the text outside `use` statements.
    lazy var wordSet: Set<String> = {
        var skip: [NSRange] = []
        var i = 0
        while i < n {
            if inImport[i] {
                var e = i
                while e + 1 < n, inImport[e + 1] { e += 1 }
                skip.append(NSRange(location: toks[i].loc, length: toks[e].loc + toks[e].len - toks[i].loc))
                i = e + 1
            } else { i += 1 }
        }
        var words = Set<String>()
        let len = ns.length
        var buf = [unichar](repeating: 0, count: len)
        if len > 0 { ns.getCharacters(&buf, range: NSRange(location: 0, length: len)) }
        func isWordChar(_ c: unichar) -> Bool { (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c >= 0x80 }
        var k = 0, si = 0
        while k < len {
            if si < skip.count, k >= skip[si].location { k = max(k, NSMaxRange(skip[si])); si += 1; continue }
            if isWordChar(buf[k]), !(k > 0 && buf[k - 1] == 36) {
                var e = k
                while e < len, isWordChar(buf[e]) { e += 1 }
                words.insert(String(utf16CodeUnits: Array(buf[k..<e]), count: e - k).lowercased())
                k = e
            } else if buf[k] == 36 {
                k += 1
                while k < len, isWordChar(buf[k]) { k += 1 }
            } else { k += 1 }
        }
        return words
    }()

    /// `$names` that follow an `@var` tag anywhere (docblock type assertions for variables defined by magic).
    lazy var docVarNames: Set<String> = {
        var vars = Set<String>()
        var from = 0
        var guardCount = 0
        while guardCount < 400 {
            guardCount += 1
            let r1 = ns.range(of: "@var", options: .literal, range: NSRange(location: from, length: ns.length - from))
            let r2 = ns.range(of: "@param", options: .literal, range: NSRange(location: from, length: ns.length - from))
            let r = (r1.location == NSNotFound || (r2.location != NSNotFound && r2.location < r1.location)) ? r2 : r1
            guard r.location != NSNotFound else { break }
            let line = ns.lineRange(for: r)
            let s = ns.substring(with: NSRange(location: r.location, length: NSMaxRange(line) - r.location))
            var cur = s[...]
            while let d = cur.firstIndex(of: "$") {
                var e = cur.index(after: d)
                while e < cur.endIndex, cur[e].isLetter || cur[e].isNumber || cur[e] == "_" { e = cur.index(after: e) }
                if e > cur.index(after: d) { vars.insert(String(cur[d..<e])) }
                cur = cur[e...]
            }
            from = NSMaxRange(r)
        }
        return vars
    }()
}
