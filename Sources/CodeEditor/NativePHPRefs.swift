import Foundation

// Native PHP find usages (phase 2b). No resident reference index: a request (1) identifies the symbol at the caret with
// NPResolver, (2) prefilters project files by a bounded byte scan for the name, (3) lexes every candidate once, resolves each
// name-matching token with NPResolver (light mode, no markdown) and keeps the tokens whose resolved declaration is the target
// (or, for members, a declaration in a related class: override / interface / parent). Candidates are processed in small chunks
// on the project's fast-tier queue and streamed to the caller; a CancelToken stops the loop between files.

struct NPRefSymbol {
    enum Kind: String { case classLike = "class", method, property, constant, enumCase = "enum case", function, globalConstant = "global constant", variable }
    var kind: Kind
    var name: String                 // class short name, member name (no $), function / constant name, variable with its $
    var fqn = ""                     // class FQN (class symbols) or declaring class FQN (members)
    var declPath = ""
    var declOffset = 0
    var searchNames: [String] = []   // prefilter words (alias forms of virtual members included)
    var url: URL                     // file the request started in
    var root = ""
    var scopeFn = -1                 // variables: offset of the owning `function`/`fn` token, -1 = file level
    var virtual: String?             // "scope" | "accessor" (Eloquent): usages are written differently from the declaration
    var ctorFnLoc: Int?              // promoted constructor property: offset of the constructor's `function` token
    var declNamespace = ""           // functions: namespace of the declaring file

    var inVendor: Bool { declPath.contains("/vendor/") }
    var isMember: Bool { kind == .method || kind == .property || kind == .constant || kind == .enumCase }
    var display: String {
        if kind == .classLike { return fqn }
        guard isMember else { return name }
        let short = fqn.split(separator: "\\").last.map(String.init) ?? fqn
        return short + (kind == .property ? "::$" : "::") + name
    }
}

enum NPRefRole: String { case declaration, `import`, usage, read, write, docblock, string, unresolved }

struct NPRefHit {
    enum Form { case plain, dollar, scopeShort }
    var path: String
    var range: NSRange               // exactly the text a rename replaces
    var line: Int
    var column: Int
    var snippet: String
    var role: NPRefRole
    var form = Form.plain
    var editable = true              // false for alias usages (`use A\B as C` ... `C::x()`)
}

enum NPRefIdentity {
    case symbol(NPRefSymbol)
    case unsupported(String)
    case none
}

struct NPScanOptions {
    var includeUnresolved = true
    var includeDocblocks = true
    var includeStrings = true
    var roots: Set<String>?          // rename of members: every class below one of these roots belongs to the family
    var newName: String?             // class rename: detect `use` collisions
}

struct NPFileScan {
    var hits: [NPRefHit] = []
    var conflicts: [String] = []
}

struct NPRefsOptions {
    var includeVendor = false
    var cap = 2000
    var scan = NPScanOptions()
}

struct NPRefsResult {
    var hits: [NPRefHit] = []        // resolved hits + unresolved ones (role .unresolved) at the end
    var conflicts: [String] = []
    var truncated = false
    var cancelled = false
    var candidates = 0
    var filesScanned = 0
    var resolvedCount: Int { hits.reduce(0) { $0 + ($1.role == .unresolved ? 0 : 1) } }
}

/// Class hierarchy relations on demand (fast-tier class infos), memoised per search.
final class NPRelations {
    let fp: FastProject
    private var cache: [String: Set<String>] = [:]
    /// lowercased fqn -> fqn as written (class infos are looked up case-sensitively)
    private(set) var names: [String: String] = [:]
    init(fp: FastProject) { self.fp = fp }

    static func norm(_ s: String) -> String { (s.hasPrefix("\\") ? String(s.dropFirst()) : s).lowercased() }

    func ancestors(_ fqn: String, live: FTClass? = nil) -> Set<String> {
        let key = Self.norm(fqn)
        if live == nil || Self.norm(live!.fqn) != key, let c = cache[key] { return c }
        var out = Set<String>()
        var queue = [fqn]
        var steps = 0
        while let n = queue.popLast(), steps < 80 {
            steps += 1
            guard out.insert(Self.norm(n)).inserted else { continue }
            names[Self.norm(n)] = n.hasPrefix("\\") ? String(n.dropFirst()) : n
            let c: FTClass? = (live != nil && Self.norm(live!.fqn) == Self.norm(n)) ? live : fp.classInfo(n.hasPrefix("\\") ? String(n.dropFirst()) : n)
            if let c {
                if let e = c.extends { queue.append(e) }
                queue += c.traits
                queue += c.implements
            }
        }
        if live == nil || Self.norm(live!.fqn) != key { cache[key] = out }
        return out
    }

    func related(_ a: String, _ b: String, live: FTClass? = nil) -> Bool {
        let na = Self.norm(a), nb = Self.norm(b)
        if na == nb { return true }
        return ancestors(a, live: live).contains(nb) || ancestors(b, live: live).contains(na)
    }

    func inFamily(_ owner: String, roots: Set<String>, live: FTClass? = nil) -> Bool {
        !ancestors(owner, live: live).isDisjoint(with: roots)
    }
}

private final class RefCounter {
    private let lock = NSLock()
    private var n = -1
    func next() -> Int { lock.lock(); n += 1; let v = n; lock.unlock(); return v }
}

enum NPRefs {
    // MARK: - Token helpers

    private static let classKeywords: Set<String> = ["class", "interface", "trait", "enum"]
    private static let modifiers: Set<String> = ["public", "protected", "private", "static", "abstract", "final", "readonly"]

    static func isOp(_ lex: PHPLex, _ i: Int) -> Bool { lex.isPunct(i, code: PHPTok.arrow) || lex.isPunct(i, code: PHPTok.dcolon) }

    static func prevKeyword(_ lex: PHPLex, _ i: Int) -> String? {
        var j = i - 1
        if j >= 0, lex.isPunct(j, "&") { j -= 1 }
        return j >= 0 && lex.toks[j].kind == .ident ? lex.text(j).lowercased() : nil
    }

    /// Index of the `use` keyword when token `i` belongs to an import statement / trait-use list.
    static func useStart(_ lex: PHPLex, _ i: Int) -> Int? {
        var j = i - 1, steps = 0
        while j >= 0, steps < 60 {
            let t = lex.toks[j]
            if t.kind == .ident {
                if lex.text(j) == "use" { return (j > 0 && isOp(lex, j - 1)) ? nil : j }
            } else if !(t.kind == .punct && (t.ch == 44 || t.ch == 123 || t.ch == 125)) { return nil }
            j -= 1; steps += 1
        }
        return nil
    }

    private static func lastSegment(_ s: String) -> (seg: String, offset: Int) {
        let ns = s as NSString
        let r = ns.range(of: "\\", options: .backwards)
        if r.location == NSNotFound { return (s, 0) }
        return (ns.substring(from: r.location + 1), r.location + 1)
    }

    private static func snippet(_ text: NSString, _ loc: Int) -> String {
        guard text.length > 0 else { return "" }
        let r = text.lineRange(for: NSRange(location: min(max(0, loc), text.length - 1), length: 0))
        var s = text.substring(with: r).trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count > 200 { s = String(s.prefix(200)) + "..." }
        return s
    }

    private static func isWrite(_ lex: PHPLex, _ i: Int) -> Bool {
        var j = i + 1
        while lex.isPunct(j, "["), lex.match[j] > j { j = lex.match[j] + 1 }
        if lex.isPunct(j, "="), !lex.isPunct(j + 1, "=") { return true }
        if j < lex.count, lex.toks[j].kind == .punct, lex.isPunct(j + 1, "="), !lex.isPunct(j + 2, "=") {
            let c = lex.toks[j].ch
            if [43, 45, 42, 47, 46, 37, 38, 124, 94].contains(c) { return true }           // + - * / . % & | ^
        }
        if lex.isPunct(j, "?"), lex.isPunct(j + 1, "?"), lex.isPunct(j + 2, "=") { return true }
        if (lex.isPunct(j, "+") && lex.isPunct(j + 1, "+")) || (lex.isPunct(j, "-") && lex.isPunct(j + 1, "-")) { return true }
        if i >= 2, (lex.isPunct(i - 1, "+") && lex.isPunct(i - 2, "+")) || (lex.isPunct(i - 1, "-") && lex.isPunct(i - 2, "-")) { return true }
        return false
    }

    private static func hit(_ path: String, _ text: NSString, _ tok: PHPTok, range: NSRange, role: NPRefRole, form: NPRefHit.Form = .plain, editable: Bool = true) -> NPRefHit {
        var line = tok.line, col = tok.col + (range.location - tok.loc)
        if range.location < tok.loc || range.location > tok.loc + tok.len || tok.kind == .string {
            let lc = NPText.lineCol(text, range.location); line = lc.line; col = lc.col
        }
        return NPRefHit(path: path, range: range, line: line, column: col, snippet: snippet(text, range.location), role: role, form: form, editable: editable)
    }

    private static func offsetHit(_ path: String, _ text: NSString, range: NSRange, role: NPRefRole, form: NPRefHit.Form = .plain, editable: Bool = true) -> NPRefHit {
        let lc = NPText.lineCol(text, range.location)
        return NPRefHit(path: path, range: range, line: lc.line, column: lc.col, snippet: snippet(text, range.location), role: role, form: form, editable: editable)
    }

    // MARK: - Identify the symbol at the caret

    /// Symlink-free absolute path (macOS /tmp, /var): every path the engine compares or returns is canonical.
    private static let canonLock = NSLock()
    private static var canonCache: [String: String] = [:]
    static func canon(_ p: String) -> String {
        canonLock.lock()
        if let c = canonCache[p] { canonLock.unlock(); return c }
        canonLock.unlock()
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        let out = realpath(p, &buf) != nil ? String(cString: buf) : p
        canonLock.lock()
        if canonCache.count > 4000 { canonCache.removeAll() }
        canonCache[p] = out
        canonLock.unlock()
        return out
    }

    static func identify(url given: URL, text: NSString, offset: Int, root rootIn: String) -> NPRefIdentity {
        let root = canon(rootIn)
        let url = URL(fileURLWithPath: canon(given.path))
        let fp = FastProject.shared(root: URL(fileURLWithPath: root))
        return fp.queue.sync { identifyOn(fp, url, text, offset, root) }
    }

    private static func classAt(_ fp: FastProject, _ url: URL, _ cur: FTClass?, _ path: String) -> FTClass? {
        if path == url.path || path == url.standardizedFileURL.path, let cur { return cur }
        return fp.classInfo(path: path)
    }

    private static func identifyOn(_ fp: FastProject, _ url: URL, _ text: NSString, _ offset: Int, _ root: String) -> NPRefIdentity {
        fp.beginRequest()
        let lex = PHPLex(text)
        let cur = FTParser.parse(text, lex: lex)
        let r = NPResolver(fp: fp, url: url, text: text, lex: lex, cur: cur)
        func fromHit(_ h: NPHit, dollarStatic: Bool, afterDColon: Bool) -> NPRefIdentity {
            switch h.kind {
            case "class":
                guard let t = h.targets.first else { return .unsupported("PHP built-in classes cannot be changed") }
                return classSymbol(fp, url, cur, t.path, root)
            case "method", "property", "enumCase", "constant" where afterDColon || h.kind != "constant":
                guard let t = h.targets.first else { return .none }
                return memberSymbol(fp, url, cur, lex, t.path, t.offset, root)
            case "constant":
                guard let t = h.targets.first else { return .unsupported("PHP built-in constants cannot be changed") }
                return globalConstant(fp, text, t.path, t.offset, root, url)
            case "function":
                guard let t = h.targets.first else { return .unsupported("PHP built-in functions cannot be changed") }
                return functionSymbol(fp, url, text, t.path, t.offset, root)
            case "column", "attribute": return .unsupported("Eloquent attributes and database columns are not supported yet")
            case "docProperty", "docMethod": return .unsupported("Members declared only in docblocks (@property / @method) are not supported")
            default: return .none
            }
        }
        guard let i = r.tokenAt(offset) else {
            if let h = r.lookup(at: offset, wantDoc: false), h.kind == "class" { return fromHit(h, dollarStatic: false, afterDColon: false) }
            return .none
        }
        let t = lex.toks[i]
        guard r.inPHP(t.loc) else { return .none }
        let w = lex.text(i)
        switch t.kind {
        case .variable:
            if w == "$this" { return .unsupported("$this cannot be renamed") }
            if let c = cur, let p = c.props.first(where: { $0.loc == t.loc }) {
                var sym = NPRefSymbol(kind: .property, name: p.name, fqn: c.fqn, declPath: url.path, declOffset: p.loc, searchNames: [p.name], url: url, root: root)
                if c.methods.contains(where: { $0.name == "__construct" }) {
                    let fn = ownerFn(r, w, i)
                    if fn >= 0, isCtorParam(lex, fn, t.loc) { sym.ctorFnLoc = fn }
                }
                return .symbol(sym)
            }
            if i > 0, lex.isPunct(i - 1, code: PHPTok.arrow) { return .unsupported("Dynamic property names cannot be resolved") }
            if i > 0, lex.isPunct(i - 1, code: PHPTok.dcolon) {
                guard let h = r.lookup(at: t.loc, wantDoc: false) else { return .none }
                return fromHit(h, dollarStatic: true, afterDColon: true)
            }
            if ["$GLOBALS", "$_GET", "$_POST", "$_SERVER", "$_SESSION", "$_COOKIE", "$_FILES", "$_ENV", "$_REQUEST", "$argv", "$argc"].contains(w) {
                return .unsupported("Superglobals cannot be renamed")
            }
            var sym = NPRefSymbol(kind: .variable, name: w, declPath: url.path, declOffset: t.loc, searchNames: [], url: url, root: root)
            let fn = ownerFn(r, w, i)
            sym.scopeFn = fn >= 0 ? lex.toks[fn].loc : -1
            return .symbol(sym)
        case .ident:
            let lower = w.lowercased()
            if let c = cur {
                if let m = c.methods.first(where: { $0.loc == t.loc }) { return memberSymbol(fp, url, cur, lex, url.path, m.loc, root, hint: m.name) }
                for (k, v) in c.declLocs where v.loc == t.loc { return memberSymbol(fp, url, cur, lex, url.path, v.loc, root, hint: String(k.drop(while: { $0 != ":" }).dropFirst())) }
                if c.nameLoc == t.loc, let pk = prevKeyword(lex, i), classKeywords.contains(pk) { return classSymbol(fp, url, cur, url.path, root) }
            }
            if prevKeyword(lex, i) == "function", !(cur?.methods.contains(where: { $0.loc == t.loc }) ?? false) {
                return functionSymbol(fp, url, text, url.path, t.loc, root)
            }
            if prevKeyword(lex, i) == "const", cur?.declLocs.values.contains(where: { $0.loc == t.loc }) != true, lex.isPunct(i + 1, "=") {
                return globalConstant(fp, text, url.path, t.loc, root, url)
            }
            if ["self", "static", "parent"].contains(lower) && !lex.isPunct(i + 1, code: PHPTok.dcolon) { return .none }
            guard let h = r.lookup(at: t.loc, wantDoc: false) else { return .none }
            return fromHit(h, dollarStatic: false, afterDColon: i > 0 && lex.isPunct(i - 1, code: PHPTok.dcolon))
        case .string:
            guard let h = r.lookup(at: offset, wantDoc: false) else { return .none }
            return fromHit(h, dollarStatic: false, afterDColon: false)
        default:
            return .none
        }
    }

    private static func isCtorParam(_ lex: PHPLex, _ fnIdx: Int, _ varLoc: Int) -> Bool {
        var k = fnIdx + 1
        if lex.isPunct(k, "&") { k += 1 }
        guard k < lex.count, lex.toks[k].kind == .ident, lex.text(k) == "__construct", lex.isPunct(k + 1, "("), lex.match[k + 1] > k else { return false }
        return varLoc > lex.toks[k + 1].loc && varLoc < lex.toks[lex.match[k + 1]].loc
    }

    private static func classSymbol(_ fp: FastProject, _ url: URL, _ cur: FTClass?, _ path: String, _ root: String) -> NPRefIdentity {
        guard let c = classAt(fp, url, cur, path), !c.name.isEmpty else { return .none }
        return .symbol(NPRefSymbol(kind: .classLike, name: c.name, fqn: c.fqn, declPath: path, declOffset: c.nameLoc, searchNames: [c.name], url: url, root: root))
    }

    private static func lcfirst(_ s: String) -> String { s.prefix(1).lowercased() + s.dropFirst() }

    private static func memberSymbol(_ fp: FastProject, _ url: URL, _ cur: FTClass?, _ lex: PHPLex, _ path: String, _ off: Int, _ root: String, hint: String? = nil) -> NPRefIdentity {
        guard let c = classAt(fp, url, cur, path) else { return .none }
        var sym: NPRefSymbol
        if let m = c.methods.first(where: { $0.loc == off }) {
            sym = NPRefSymbol(kind: .method, name: m.name, fqn: c.fqn, declPath: path, declOffset: off, searchNames: [m.name], url: url, root: root)
            if m.name.hasPrefix("scope"), m.name.count > 5, c.scopes.contains(lcfirst(String(m.name.dropFirst(5)))) {
                sym.virtual = "scope"; sym.searchNames.append(lcfirst(String(m.name.dropFirst(5))))
            } else if m.name.hasPrefix("get"), m.name.hasSuffix("Attribute"), m.name.count > 12 {
                sym.virtual = "accessor"
                sym.searchNames.append(FTParser.snake(String(m.name.dropFirst(3).dropLast(9))))
            } else if c.accessors.contains(FTParser.snake(m.name)), m.ret.contains("Attribute") {
                sym.virtual = "accessor"; sym.searchNames.append(FTParser.snake(m.name))
            }
            return .symbol(sym)
        }
        if let p = c.props.first(where: { $0.loc == off }) {
            return .symbol(NPRefSymbol(kind: .property, name: p.name, fqn: c.fqn, declPath: path, declOffset: off, searchNames: [p.name], url: url, root: root))
        }
        for (k, v) in c.declLocs where v.loc == off {
            let isCase = k.hasPrefix("case:")
            let n = String(k.dropFirst(isCase ? 5 : 6))
            return .symbol(NPRefSymbol(kind: isCase ? .enumCase : .constant, name: n, fqn: c.fqn, declPath: path, declOffset: off, searchNames: [n], url: url, root: root))
        }
        return .unsupported("This member is declared dynamically (no declaration found)")
    }

    private static func functionSymbol(_ fp: FastProject, _ url: URL, _ text: NSString, _ path: String, _ off: Int, _ root: String) -> NPRefIdentity {
        guard let t = path == url.path ? text : NPFiles.text(path) else { return .none }
        let lex = PHPLex(t)
        var i = 0
        while i < lex.count, lex.toks[i].loc < off { i += 1 }
        guard i < lex.count, lex.toks[i].loc == off, lex.toks[i].kind == .ident else { return .none }
        let name = lex.text(i)
        var ns = ""
        if let c = FTParser.parse(t, lex: lex) { ns = c.ns } else {
            for j in 0..<max(0, lex.count - 1) where lex.isIdent(j, "namespace") && lex.toks[j + 1].kind == .ident { ns = lex.text(j + 1); break }
        }
        var sym = NPRefSymbol(kind: .function, name: name, declPath: path, declOffset: off, searchNames: [name], url: url, root: root)
        sym.declNamespace = ns
        return .symbol(sym)
    }

    private static func globalConstant(_ fp: FastProject, _ text: NSString, _ path: String, _ off: Int, _ root: String, _ url: URL) -> NPRefIdentity {
        guard let t = path == url.path ? text : NPFiles.text(path) else { return .none }
        let lex = PHPLex(t)
        var i = 0
        while i < lex.count, lex.toks[i].loc < off { i += 1 }
        guard i < lex.count else { return .none }
        let tk = lex.toks[i]
        var name = ""
        if tk.kind == .string { name = lex.strValue(i) } else if tk.kind == .ident, tk.loc == off { name = lex.text(i) }
        guard !name.isEmpty else { return .none }
        return .symbol(NPRefSymbol(kind: .globalConstant, name: name, declPath: path, declOffset: off, searchNames: [name], url: url, root: root))
    }

    // MARK: - Local variable scope

    /// Token index of the `function` / `fn` that owns variable `name` at token `i` (-1 = file level). Arrow functions inherit
    /// their parent's variables, closures only the ones in their `use (...)` list.
    static func ownerFn(_ r: NPResolver, _ name: String, _ i: Int) -> Int {
        let lex = r.lex
        for sc in r.ev.enclosingFunctions(i) {
            for q in sc.params.0..<sc.params.1 where lex.toks[q].kind == .variable && lex.text(q) == name { return sc.fn }
            if lex.text(sc.fn) == "fn" { continue }
            var k = sc.fn + 1
            if lex.isPunct(k, "&") { k += 1 }
            if lex.toks[min(k, lex.count - 1)].kind == .punct, lex.isPunct(k, "(") {            // closure (unnamed)
                let u = sc.params.1 + 1
                if lex.isIdent(u, "use"), lex.isPunct(u + 1, "("), lex.match[u + 1] > u {
                    var q = u + 2
                    var captured = false
                    while q < lex.match[u + 1] { if lex.toks[q].kind == .variable, lex.text(q) == name { captured = true; break }; q += 1 }
                    if captured { continue }
                }
            }
            return sc.fn
        }
        return -1
    }

    // MARK: - Scanning one file

    /// Lowercased UTF-16 needles and their lengths, only when every name is plain ASCII (otherwise the byte-level rejections are off).
    static func asciiNeedles(_ names: [String]) -> (needles: [[UInt16]], lengths: Set<Int>)? {
        var out: [[UInt16]] = []
        for n in names {
            guard !n.isEmpty, n.utf8.allSatisfy({ $0 < 128 }) else { return nil }
            out.append(Array(n.lowercased().utf16))
        }
        return (out, Set(out.map(\.count)))
    }

    /// Necessary condition for the string-token branches of `scanMember`: the raw token text contains one of the needles (ASCII case
    /// insensitive). Non-ASCII or very long tokens are never rejected here (the exact code decides).
    static func stringMayContain(_ text: NSString, _ t: PHPTok, _ needles: [[UInt16]], _ buf: inout [unichar]) -> Bool {
        let n = Int(t.len) - 2
        guard n > 0 else { return false }                  // strValue is "" -> skipped by the exact code too
        guard n <= 1024 else { return true }
        text.getCharacters(&buf, range: NSRange(location: Int(t.loc) + 1, length: n))
        var i = 0
        var esc = false
        while i < n { if buf[i] >= 128 { return true }; if buf[i] == 92 { esc = true }; i += 1 }
        if n >= 120, !esc { return false }                       // ASCII: Character count == n, the exact code requires < 120
        for nd in needles {
            let m = nd.count
            if m > n { continue }
            let f = nd[0]
            var a = 0
            while a <= n - m {
                var c = buf[a]; if c >= 65 && c <= 90 { c += 32 }
                if c == f {
                    var k = 1
                    while k < m { var d = buf[a + k]; if d >= 65 && d <= 90 { d += 32 }; if d != nd[k] { break }; k += 1 }
                    if k == m { return true }
                }
                a += 1
            }
        }
        return false
    }

    /// Text, token stream and parsed declaration of one candidate file: everything that does not need the project's fast-tier state,
    /// so it can be produced on several threads while the resolver pass runs serially on the project queue.
    struct PreparedFile {
        let path: String
        let text: NSString
        let lex: PHPLex
        let cur: FTClass?
    }

    /// Read (or take the live text), precheck that the file mentions one of the names, lex and parse. Pure: safe on any thread.
    static func prepareFile(_ sym: NPRefSymbol, path: String, text given: NSString? = nil) -> PreparedFile? {
        guard let text = given ?? FastProject.readRaw(path) else { return nil }
        // cheap precheck: the file must mention one of the names
        let names = sym.searchNames.isEmpty ? [sym.name] : sym.searchNames
        guard names.contains(where: { text.range(of: $0, options: [.caseInsensitive, .literal]).location != NSNotFound }) else { return nil }
        let lex = PHPLex(text)
        let cur = FTParser.parse(text, lex: lex)
        return PreparedFile(path: path, text: text, lex: lex, cur: cur)
    }

    /// Prepares `paths` on up to `workers` threads, results in input order.
    static func prepareFiles(_ sym: NPRefSymbol, paths: [String], live: [String: NSString], workers: Int) -> [PreparedFile?] {
        var out = [PreparedFile?](repeating: nil, count: paths.count)
        if paths.count < 2 || workers < 2 {
            for (i, p) in paths.enumerated() { out[i] = prepareFile(sym, path: p, text: live[p]) }
            return out
        }
        let counter = RefCounter()
        out.withUnsafeMutableBufferPointer { buf in
            let base = buf.baseAddress!
            DispatchQueue.concurrentPerform(iterations: min(workers, paths.count)) { _ in
                while true {
                    let i = counter.next()
                    if i >= paths.count { break }
                    base[i] = prepareFile(sym, path: paths[i], text: live[paths[i]])     // each index is written by exactly one worker
                }
            }
        }
        return out
    }

    static func scanFile(_ sym: NPRefSymbol, path: String, fp: FastProject, rel: NPRelations, text given: NSString? = nil, opts: NPScanOptions = NPScanOptions(),
                         shared: NPSharedMemo? = nil) -> NPFileScan {
        guard let pf = prepareFile(sym, path: path, text: given) else { return NPFileScan() }
        return scanPrepared(sym, pf, fp: fp, rel: rel, opts: opts, shared: shared)
    }

    static func scanPrepared(_ sym: NPRefSymbol, _ pf: PreparedFile, fp: FastProject, rel: NPRelations, opts: NPScanOptions, shared: NPSharedMemo? = nil) -> NPFileScan {
        let tD = NPStats.now()
        let path = pf.path, text = pf.text, lex = pf.lex, cur = pf.cur
        let r = NPResolver(fp: fp, url: URL(fileURLWithPath: path), text: text, lex: lex, cur: cur, shared: shared)
        var scan = NPFileScan()
        defer { NPStats.scanResolveNs &+= NPStats.now() &- tD }
        switch sym.kind {
        case .classLike: scanClass(sym, path, text, lex, cur, r, fp, rel, opts, &scan)
        case .method, .property, .constant, .enumCase: scanMember(sym, path, text, lex, cur, r, fp, rel, opts, &scan)
        case .function: scanFunction(sym, path, text, lex, cur, r, fp, &scan)
        case .globalConstant: scanGlobalConstant(sym, path, text, lex, cur, r, fp, &scan)
        case .variable: scanVariable(sym, path, text, lex, cur, r, &scan, opts)
        }
        // stable order, no duplicates
        var seen = Set<Int>()
        scan.hits = scan.hits.filter { seen.insert($0.range.location).inserted }.sorted { $0.range.location < $1.range.location }
        return scan
    }

    private static func classFQN(_ fp: FastProject, _ url: URL, _ cur: FTClass?, _ path: String) -> String? {
        if path == url.path, let cur { return cur.fqn }
        return fp.classInfo(path: path)?.fqn
    }

    // MARK: Classes

    private static func scanClass(_ sym: NPRefSymbol, _ path: String, _ text: NSString, _ lex: PHPLex, _ cur: FTClass?, _ r: NPResolver, _ fp: FastProject,
                                  _ rel: NPRelations, _ opts: NPScanOptions, _ scan: inout NPFileScan) {
        let fqnL = NPRelations.norm(sym.fqn), shortL = sym.name.lowercased()
        var aliases = Set<String>()
        if let c = cur { for (k, v) in c.uses where NPRelations.norm(v) == fqnL && k.lowercased() != shortL { aliases.insert(k.lowercased()) } }
        let url = r.url
        var touched = false
        for i in 0..<lex.count where lex.toks[i].kind == .ident {
            let t = lex.toks[i]
            let full = lex.text(i)
            let (seg, segOff) = lastSegment(full)
            let segL = seg.lowercased()
            let isAlias = aliases.contains(segL) && !full.contains("\\")
            guard segL == shortL || isAlias else { continue }
            if i > 0, isOp(lex, i - 1) { continue }
            let pk = prevKeyword(lex, i)
            if pk == "function" || pk == "const" || pk == "namespace" { continue }
            let range = NSRange(location: t.loc + segOff, length: (seg as NSString).length)
            if let c = cur, c.nameLoc == t.loc, let p = pk, classKeywords.contains(p) {
                if NPRelations.norm(c.fqn) == fqnL { scan.hits.append(hit(path, text, t, range: range, role: .declaration)); touched = true }
                continue
            }
            guard let h = r.lookup(at: t.loc, wantDoc: false), h.kind == "class", let tg = h.targets.first,
                  let f = classFQN(fp, url, cur, tg.path), NPRelations.norm(f) == fqnL else { continue }
            var role = NPRefRole.usage
            if useStart(lex, i) != nil {
                if let c = cur, c.nameLoc > 0, t.loc > c.nameLoc { role = .usage } else { role = .import }
            }
            scan.hits.append(hit(path, text, t, range: range, role: role, editable: !isAlias))
            if !isAlias { touched = true }
        }
        if opts.includeStrings {
            for i in 0..<lex.count where lex.toks[i].kind == .string {
                let raw = lex.strValue(i)
                guard raw.count > sym.name.count, raw.count < 300, raw.lowercased().contains(shortL) else { continue }
                var v = raw
                if v.hasPrefix("\\") { v.removeFirst() }
                if let cut = v.firstIndex(where: { $0 == "@" || $0 == ":" }) { v = String(v[..<cut]) }
                guard NPRelations.norm(v) == fqnL else { continue }
                let t = lex.toks[i]
                let rawText = text.substring(with: NSRange(location: t.loc, length: t.len)) as NSString
                let rr = rawText.range(of: sym.name, options: [.backwards, .caseInsensitive, .literal])
                guard rr.location != NSNotFound else { continue }
                scan.hits.append(hit(path, text, t, range: NSRange(location: t.loc + rr.location, length: rr.length), role: .string))
                touched = true
            }
        }
        if opts.includeDocblocks {
            let names = [sym.name] + aliases
            for n in names {
                var from = 0
                while from < text.length {
                    let rg = text.range(of: n, options: [.caseInsensitive, .literal], range: NSRange(location: from, length: text.length - from))
                    guard rg.location != NSNotFound else { break }
                    from = NSMaxRange(rg)
                    if rg.location > 0 {
                        let p = text.character(at: rg.location - 1)
                        if CompletionLex.isIdent(p) || p == 36 { continue }
                    }
                    if NSMaxRange(rg) < text.length, CompletionLex.isIdent(text.character(at: NSMaxRange(rg))) { continue }
                    guard insideDocblock(text, rg.location) else { continue }
                    // the written (possibly qualified) name
                    var s = rg.location
                    while s > 0, CompletionLex.isIdent(text.character(at: s - 1)) || text.character(at: s - 1) == 92 { s -= 1 }
                    let written = text.substring(with: NSRange(location: s, length: NSMaxRange(rg) - s))
                    if written.contains("\\") { if NPRelations.norm(cur?.resolve(written) ?? written) != fqnL { continue } }
                    else if let f = fp.resolveClass(written, in: cur) { if NPRelations.norm(f) != fqnL { continue } }
                    else { continue }
                    scan.hits.append(offsetHit(path, text, range: rg, role: .docblock, editable: n.lowercased() == shortL))
                    touched = true
                }
            }
        }
        if let nn = opts.newName, touched, let c = cur {
            if let imp = c.uses.first(where: { $0.key.lowercased() == nn.lowercased() }), NPRelations.norm(imp.value) != fqnL {
                scan.conflicts.append("\((path as NSString).lastPathComponent) already imports \(imp.value) as \(imp.key)")
            }
            if NPRelations.norm(c.ns).isEmpty == false, NPRelations.norm(c.fqn) != fqnL, c.name.lowercased() == nn.lowercased() {
                scan.conflicts.append("\((path as NSString).lastPathComponent) declares a class named \(nn)")
            }
        }
    }

    static func insideDocblock(_ text: NSString, _ loc: Int) -> Bool {
        let before = NSRange(location: 0, length: loc)
        let o = text.range(of: "/**", options: [.backwards, .literal], range: before)
        guard o.location != NSNotFound else { return false }
        let c = text.range(of: "*/", options: [.backwards, .literal], range: NSRange(location: o.location, length: loc - o.location))
        return c.location == NSNotFound
    }

    // MARK: Members

    private static func memberDeclKind(_ k: FTClass, _ sym: NPRefSymbol, loc: Int) -> Bool {
        switch sym.kind {
        case .method: return k.methods.contains { $0.loc == loc }
        case .property: return k.props.contains { $0.loc == loc }
        case .constant: return k.declLocs["const:" + sym.name]?.loc == loc
        case .enumCase: return k.declLocs["case:" + sym.name]?.loc == loc
        default: return false
        }
    }

    private static func scanMember(_ sym: NPRefSymbol, _ path: String, _ text: NSString, _ lex: PHPLex, _ cur: FTClass?, _ r: NPResolver, _ fp: FastProject,
                                   _ rel: NPRelations, _ opts: NPScanOptions, _ scan: inout NPFileScan) {
        let url = r.url
        let nameL = sym.name.lowercased()
        let aliasL = Set(sym.searchNames.map { $0.lowercased() })
        func related(_ owner: String) -> Bool {
            if let roots = opts.roots { return rel.inFamily(owner, roots: roots, live: cur) }
            return rel.related(owner, sym.fqn, live: cur)
        }
        // Cheap rejection before any String is built: the token length must be one of the searched names' lengths (ASCII names only).
        let fastNames = NPRefs.asciiNeedles(sym.kind == .method ? Array(aliasL) + [nameL] : [sym.name])
        for i in 0..<lex.count {
            let t = lex.toks[i]
            guard t.kind == .ident || t.kind == .variable else { continue }
            if let f = fastNames, !f.lengths.contains(t.kind == .variable ? Int(t.len) - 1 : Int(t.len)) { continue }
            let w = lex.text(i)
            let isVar = t.kind == .variable
            let word = isVar ? String(w.dropFirst()) : w
            switch sym.kind {
            case .method: guard !isVar, aliasL.contains(word.lowercased()) || word.lowercased() == nameL else { continue }
            case .property: guard word == sym.name else { continue }
            default: guard !isVar, word == sym.name else { continue }
            }
            let isAliasForm = sym.kind == .method && word.lowercased() != nameL
            // declarations in this file
            if let c = cur, !isAliasForm, memberDeclKind(c, sym, loc: t.loc) {
                if related(c.fqn) {
                    scan.hits.append(hit(path, text, t, range: NSRange(location: t.loc, length: t.len), role: .declaration, form: isVar ? .dollar : .plain))
                }
                continue
            }
            // usages need a member operator
            guard i > 0 else { continue }
            let viaArrow = lex.isPunct(i - 1, code: PHPTok.arrow), viaDC = lex.isPunct(i - 1, code: PHPTok.dcolon)
            guard viaArrow || viaDC else { continue }
            if isVar, !viaDC { continue }
            if !isVar, sym.kind == .property, viaDC, lex.isPunct(i + 1, "(") { continue }
            let rangeStart = isVar ? t.loc : t.loc
            let range = NSRange(location: rangeStart, length: t.len)
            let form: NPRefHit.Form = isVar ? .dollar : (isAliasForm ? .scopeShort : .plain)
            if let h = r.lookup(at: t.loc, wantDoc: false), let tg = h.targets.first {
                guard let owner = classAt(fp, url, cur, tg.path), memberDeclKind(owner, sym, loc: tg.offset) || aliasDeclKind(owner, sym, tg.offset) else { continue }
                guard related(owner.fqn) else { continue }
                var role = NPRefRole.usage
                if sym.kind == .property || sym.kind == .constant { role = isWrite(lex, i) ? .write : .read }
                scan.hits.append(hit(path, text, t, range: range, role: role, form: form))
            } else if opts.includeUnresolved, sym.kind == .method || sym.kind == .property {
                scan.hits.append(hit(path, text, t, range: range, role: .unresolved, form: form))
            }
        }
        // array callables and relation names written as strings: [Foo::class, 'method'], [$this, 'method'], with('relation')
        if sym.kind == .method {
            var sbuf = [unichar](repeating: 0, count: 1024)
            for i in 0..<lex.count where lex.toks[i].kind == .string {
                if let f = fastNames, !NPRefs.stringMayContain(text, lex.toks[i], f.needles, &sbuf) { continue }
                let v = lex.strValue(i)
                guard !v.isEmpty, v.count < 120 else { continue }
                let t = lex.toks[i]
                let inner = NSRange(location: t.loc + 1, length: max(0, t.len - 2))
                if aliasL.contains(v.lowercased()) || v.lowercased() == nameL, i >= 3, lex.isPunct(i - 1, ",") {
                    var ownerFqn: String?
                    if lex.isIdent(i - 2, "class"), lex.isPunct(i - 3, code: PHPTok.dcolon), i >= 4, lex.toks[i - 4].kind == .ident,
                       let h = r.lookup(at: lex.toks[i - 4].loc, wantDoc: false), h.kind == "class", let tg = h.targets.first {
                        ownerFqn = classFQN(fp, url, cur, tg.path)
                    } else if lex.toks[i - 2].kind == .variable, lex.text(i - 2) == "$this" { ownerFqn = cur?.fqn }
                    if let o = ownerFqn, related(o) {
                        scan.hits.append(hit(path, text, t, range: inner, role: .string))
                    }
                } else if v.lowercased().contains(nameL), v.contains(".") || v.lowercased() == nameL {
                    // dotted relation chains in with('a.b')
                    var pos = 0
                    for seg in v.split(separator: ".", omittingEmptySubsequences: false) {
                        let l = (seg as NSString).length
                        if seg.lowercased() == nameL, let h = r.lookup(at: inner.location + pos, wantDoc: false), let tg = h.targets.first,
                           let owner = classAt(fp, url, cur, tg.path), memberDeclKind(owner, sym, loc: tg.offset), related(owner.fqn) {
                            scan.hits.append(hit(path, text, t, range: NSRange(location: inner.location + pos, length: l), role: .string))
                        }
                        pos += l + 1
                    }
                } else if v.lowercased() == nameL, let h = r.lookup(at: inner.location, wantDoc: false), let tg = h.targets.first,
                          let owner = classAt(fp, url, cur, tg.path), memberDeclKind(owner, sym, loc: tg.offset), related(owner.fqn) {
                    scan.hits.append(hit(path, text, t, range: inner, role: .string))
                }
            }
        }
    }

    /// Eloquent scopes / accessors: the lookup lands on `scopeFoo` / `getFooAttribute`, which is the symbol's own declaration.
    private static func aliasDeclKind(_ k: FTClass, _ sym: NPRefSymbol, _ loc: Int) -> Bool {
        sym.kind == .method && k.methods.contains { $0.loc == loc }
    }

    // MARK: Functions and constants

    private static func scanFunction(_ sym: NPRefSymbol, _ path: String, _ text: NSString, _ lex: PHPLex, _ cur: FTClass?, _ r: NPResolver, _ fp: FastProject, _ scan: inout NPFileScan) {
        let nameL = sym.name.lowercased()
        for i in 0..<lex.count where lex.toks[i].kind == .ident {
            let t = lex.toks[i]
            let (seg, segOff) = lastSegment(lex.text(i))
            guard seg.lowercased() == nameL else { continue }
            if i > 0, isOp(lex, i - 1) { continue }
            let range = NSRange(location: t.loc + segOff, length: (seg as NSString).length)
            let pk = prevKeyword(lex, i)
            if pk == "function" {
                if cur?.methods.contains(where: { $0.loc == t.loc }) == true { continue }
                if path == sym.declPath { scan.hits.append(hit(path, text, t, range: range, role: .declaration)) }
                continue
            }
            if pk == "new" || pk == "const" || pk == "class" || pk == "namespace" { continue }
            if let u = useStart(lex, i) {
                guard u + 1 < lex.count, lex.isIdent(u + 1, "function") else { continue }
                var full = lex.text(i)
                if full.hasPrefix("\\") { full.removeFirst() }
                if NPRelations.norm(full) == NPRelations.norm(sym.declNamespace.isEmpty ? sym.name : sym.declNamespace + "\\" + sym.name) {
                    scan.hits.append(hit(path, text, t, range: range, role: .import))
                }
                continue
            }
            guard lex.isPunct(i + 1, "(") else { continue }
            guard let h = r.lookup(at: t.loc, wantDoc: false), h.kind == "function", let tg = h.targets.first, canon(tg.path) == sym.declPath else { continue }
            scan.hits.append(hit(path, text, t, range: range, role: .usage))
        }
    }

    private static func scanGlobalConstant(_ sym: NPRefSymbol, _ path: String, _ text: NSString, _ lex: PHPLex, _ cur: FTClass?, _ r: NPResolver, _ fp: FastProject, _ scan: inout NPFileScan) {
        for i in 0..<lex.count {
            let t = lex.toks[i]
            if t.kind == .string, path == sym.declPath, t.loc == sym.declOffset, lex.strValue(i) == sym.name {
                scan.hits.append(hit(path, text, t, range: NSRange(location: t.loc + 1, length: t.len - 2), role: .declaration)); continue
            }
            guard t.kind == .ident else { continue }
            let (seg, segOff) = lastSegment(lex.text(i))
            guard seg == sym.name else { continue }
            if i > 0, isOp(lex, i - 1) { continue }
            let range = NSRange(location: t.loc + segOff, length: (seg as NSString).length)
            if prevKeyword(lex, i) == "const", t.loc == sym.declOffset { scan.hits.append(hit(path, text, t, range: range, role: .declaration)); continue }
            if lex.isPunct(i + 1, "(") || prevKeyword(lex, i) == "function" || prevKeyword(lex, i) == "const" || useStart(lex, i) != nil { continue }
            guard let h = r.lookup(at: t.loc, wantDoc: false), h.kind == "constant", let tg = h.targets.first, canon(tg.path) == sym.declPath else { continue }
            scan.hits.append(hit(path, text, t, range: range, role: .usage))
        }
    }

    // MARK: Variables

    private static func scanVariable(_ sym: NPRefSymbol, _ path: String, _ text: NSString, _ lex: PHPLex, _ cur: FTClass?, _ r: NPResolver, _ scan: inout NPFileScan, _ opts: NPScanOptions) {
        let name = sym.name
        func owns(_ i: Int) -> Bool {
            let fn = ownerFn(r, name, i)
            return (fn >= 0 ? lex.toks[fn].loc : -1) == sym.scopeFn
        }
        var lo = 0, hi = lex.count
        if sym.scopeFn >= 0 {
            // limit the walk to the owning function's token range
            var fnIdx = -1
            for i in 0..<lex.count where lex.toks[i].loc == sym.scopeFn { fnIdx = i; break }
            guard fnIdx >= 0 else { return }
            lo = fnIdx
            var k = fnIdx + 1
            if lex.isPunct(k, "&") { k += 1 }
            if k < lex.count, lex.toks[k].kind == .ident { k += 1 }
            var end = lex.count
            if lex.isPunct(k, "("), lex.match[k] > k {
                var b = lex.match[k] + 1
                while b < lex.count, !lex.isPunct(b, "{"), !lex.isPunct(b, ";"), !lex.isPunct(b, code: PHPTok.fat) { b += 1; if b - lex.match[k] > 80 { break } }
                if lex.isPunct(b, "{"), lex.match[b] > b { end = lex.match[b] + 1 }
                else if lex.isPunct(b, code: PHPTok.fat) {
                    var e = b + 1, d = 0
                    while e < lex.count {
                        let t = lex.toks[e]
                        if t.kind == .punct {
                            if [40, 91, 123].contains(t.ch) { d += 1 } else if [41, 93, 125].contains(t.ch) { if d == 0 { break }; d -= 1 }
                            else if (t.ch == 44 || t.ch == 59), d == 0 { break }
                        }
                        e += 1
                    }
                    end = e
                }
            }
            hi = min(lex.count, end)
        }
        guard lo < hi else { return }
        for i in lo..<hi {
            let t = lex.toks[i]
            if t.kind == .variable, lex.text(i) == name {
                if i > 0, lex.isPunct(i - 1, code: PHPTok.arrow) || lex.isPunct(i - 1, code: PHPTok.dcolon) { continue }
                guard owns(i) else { continue }
                var role = NPRefRole.read
                if isWrite(lex, i) { role = .write }
                if let pk = prevKeyword(lex, i), pk == "as" { role = .write }
                scan.hits.append(hit(path, text, t, range: NSRange(location: t.loc, length: t.len), role: role, form: .dollar))
            } else if t.kind == .string, t.len > name.count {
                let first = text.character(at: t.loc)
                guard first == 34 || first == 60 else { continue }                    // " or <<<
                let raw = text.substring(with: NSRange(location: t.loc, length: t.len)) as NSString
                var from = 0
                var any = false
                while from < raw.length {
                    let rg = raw.range(of: name, options: .literal, range: NSRange(location: from, length: raw.length - from))
                    guard rg.location != NSNotFound else { break }
                    from = NSMaxRange(rg)
                    if NSMaxRange(rg) < raw.length, CompletionLex.isIdent(raw.character(at: NSMaxRange(rg))) { continue }
                    if rg.location > 0, raw.character(at: rg.location - 1) == 92 { continue }
                    if !any { guard owns(i) else { break }; any = true }
                    scan.hits.append(offsetHit(path, text, range: NSRange(location: t.loc + rg.location, length: rg.length), role: .read, form: .dollar))
                }
            }
        }
        // @param / @var tags of the owning function's docblock
        if opts.includeDocblocks, sym.scopeFn >= 0, text.length > 0 {
            var fnIdx = -1
            for i in 0..<lex.count where lex.toks[i].loc == sym.scopeFn { fnIdx = i; break }
            var s = fnIdx
            while s > 0, lex.toks[s - 1].kind == .ident, modifiers.contains(lex.text(s - 1).lowercased()) { s -= 1 }
            if fnIdx >= 0, lex.isIdent(fnIdx, "function"), let d = NPDoc.leading(text, before: lex.toks[s].loc) {
                let raw = d.text as NSString
                var from = 0
                while from < raw.length {
                    let rg = raw.range(of: name, options: .literal, range: NSRange(location: from, length: raw.length - from))
                    guard rg.location != NSNotFound else { break }
                    from = NSMaxRange(rg)
                    if NSMaxRange(rg) < raw.length, CompletionLex.isIdent(raw.character(at: NSMaxRange(rg))) { continue }
                    let ls = raw.lineRange(for: NSRange(location: rg.location, length: 0))
                    let line = raw.substring(with: ls)
                    guard line.contains("@param") || line.contains("@var") else { continue }
                    scan.hits.append(offsetHit(path, text, range: NSRange(location: d.start + rg.location, length: rg.length), role: .docblock, form: .dollar))
                }
            }
        }
        // declaration marker: parameters
        for k in 0..<scan.hits.count {
            let loc = scan.hits[k].range.location
            if loc == sym.declOffset, scan.hits[k].role != .docblock, isParam(lex, loc) { scan.hits[k].role = .declaration }
        }
    }

    private static func isParam(_ lex: PHPLex, _ loc: Int) -> Bool {
        var i = 0
        while i < lex.count, lex.toks[i].loc < loc { i += 1 }
        guard i < lex.count, lex.toks[i].loc == loc else { return false }
        var d = 0, j = i - 1
        while j >= 0, i - j < 40 {
            if lex.toks[j].kind == .punct {
                let c = lex.toks[j].ch
                if c == 41 || c == 93 { d += 1 } else if c == 91 { if d > 0 { d -= 1 } } else if c == 40 { if d == 0 { break }; d -= 1 }
                else if c == 59 || c == 123 || c == 125 { return false }
            }
            j -= 1
        }
        guard j >= 1, lex.isPunct(j, "(") else { return false }
        if lex.toks[j - 1].kind == .ident { return j >= 2 && (lex.isIdent(j - 2, "function") || lex.isPunct(j - 2, "&")) || lex.isIdent(j - 1, "fn") || lex.isIdent(j - 1, "function") }
        return false
    }

    // MARK: - Candidate files (bounded byte prefilter)

    /// Every `.php` / `.phtml` file under `root` (skip rules of `FindEngine.listFiles`: `.git`, `.DS_Store` and `ProjectIndex.skipNames` single names;
    /// vendor walked without skip rules), as a directory walk that only allocates Strings for directories and matching files
    /// (the generic walk allocated two paths per entry and cost 33 ms on a 2 700 entry project). Same set and spelling as `phpFilesViaEngine`.
    static func phpFiles(root: String, includeVendor: Bool, filter: ((String) -> Bool)? = nil) -> [String] {
        var out = walkPHP(realPath(root), skip: ProjectIndex.skipNames, filter: filter)
        out.sort()
        if includeVendor, LaravelFS.isDir(root + "/vendor") {
            var v = walkPHP(realPath(root + "/vendor"), skip: [], filter: filter)
            v.sort()
            out += v
        }
        return out
    }

    private static func realPath(_ p: String) -> String {
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        return realpath(p, &buf) != nil ? String(cString: buf) : p
    }

    /// Parallel directory walk (a work stack shared by up to 8 workers; one directory read costs ~20 us, a Laravel project has ~1 500 of them).
    /// `filter` (when given) runs on the worker that found the file, right after its directory was read, so the file reads of the content
    /// prefilter overlap with the directory walk instead of following it.
    private static func walkPHP(_ top: String, skip: Set<String>, filter: ((String) -> Bool)? = nil) -> [String] {
        let cond = NSCondition()
        var stack = [top]
        var active = 0
        var out: [String] = []
        var seen = 0
        let workers = max(1, min(PowerState.shared.maxWorkers, 8))
        DispatchQueue.concurrentPerform(iterations: workers) { _ in
            var mine: [String] = []
            while true {
                cond.lock()
                while stack.isEmpty, active > 0 { cond.wait() }
                guard let dir = stack.popLast() else { cond.unlock(); break }     // empty and nobody can add more
                let capped = seen >= 300_000
                active += 1
                cond.unlock()
                var subs: [String] = [], count = 0
                if !capped {
                    let before = mine.count
                    readPHPDir(dir, skip: skip, subdirs: &subs, files: &mine, count: &count)
                    if let filter, mine.count > before {
                        var keep = Array(mine[..<before])
                        for p in mine[before...] where filter(p) { keep.append(p) }
                        mine = keep
                    }
                }
                cond.lock()
                seen += count
                stack += subs
                active -= 1
                cond.broadcast()
                cond.unlock()
            }
            cond.lock(); out += mine; cond.unlock()
        }
        return out
    }

    private static func readPHPDir(_ dir: String, skip: Set<String>, subdirs: inout [String], files: inout [String], count: inout Int) {
        guard let d = opendir(dir) else { return }
        defer { closedir(d) }
        while let e = readdir(d) {
            let len = Int(e.pointee.d_namlen)
            let (isDot, isPHP) = withUnsafePointer(to: &e.pointee.d_name) { tup in
                tup.withMemoryRebound(to: UInt8.self, capacity: len + 1) { b -> (Bool, Bool) in
                    if b[0] == 46, len == 1 || (len == 2 && b[1] == 46) { return (true, false) }
                    let php = len >= 4 && b[len - 4] == 46 && b[len - 3] == 112 && b[len - 2] == 104 && b[len - 1] == 112
                    let phtml = len >= 6 && b[len - 6] == 46 && b[len - 5] == 112 && b[len - 4] == 104 && b[len - 3] == 116 && b[len - 2] == 109 && b[len - 1] == 108
                    return (false, php || phtml)
                }
            }
            if isDot { continue }
            var type = e.pointee.d_type
            if type == UInt8(DT_REG) || type == UInt8(DT_LNK) {
                count += 1
                guard isPHP else { continue }                 // a skipNames entry never ends in .php, so no name test is needed for files
                let name = withUnsafePointer(to: &e.pointee.d_name) { $0.withMemoryRebound(to: CChar.self, capacity: len + 1) { String(cString: $0) } }
                files.append(dir + "/" + name)
                continue
            }
            let name = withUnsafePointer(to: &e.pointee.d_name) { $0.withMemoryRebound(to: CChar.self, capacity: len + 1) { String(cString: $0) } }
            if name == ".git" || name == ".DS_Store" { continue }
            if skip.contains(name) { continue }
            let full = dir + "/" + name
            if type == UInt8(DT_UNKNOWN) {
                var st = stat()
                if lstat(full, &st) == 0 { type = (st.st_mode & S_IFMT) == S_IFDIR ? UInt8(DT_DIR) : (st.st_mode & S_IFMT) == S_IFLNK ? UInt8(DT_LNK) : UInt8(DT_REG) }
            }
            if type == UInt8(DT_DIR) { subdirs.append(full) }
            else if type == UInt8(DT_REG) || type == UInt8(DT_LNK) {
                count += 1
                if isPHP { files.append(full) }
            }
        }
    }

    /// Reference implementation (the generic `FindEngine` walk); kept for the equivalence self-test.
    static func phpFilesViaEngine(root: String, includeVendor: Bool) -> [String] {
        let engine = FindEngine(root: URL(fileURLWithPath: root), files: { [] })
        func isPHP(_ p: String) -> Bool { p.hasSuffix(".php") || p.hasSuffix(".phtml") }
        var out = engine.listFiles(FindOptions(query: "x")).map(\.path).filter(isPHP)
        if includeVendor, LaravelFS.isDir(root + "/vendor") {
            var o = FindOptions(query: "x")
            o.includeIgnored = true
            o.directory = URL(fileURLWithPath: root + "/vendor")
            out += engine.listFiles(o).map(\.path).filter(isPHP)
        }
        return out
    }

    /// Files that contain one of `needles` (ASCII case-insensitive), plus `extra` paths. Files are mmapped, nothing is kept.
    static func candidates(root: String, needles: [String], includeVendor: Bool, extra: [String], cancel: CancelToken?) -> [String] {
        let tL = NPStats.now()
        defer { NPStats.candTotalNs = NPStats.now() &- tL }
        let pats: [[UInt8]] = needles.map { Array($0.utf8).map { ($0 >= 65 && $0 <= 90) ? $0 + 32 : $0 } }.filter { !$0.isEmpty }
        guard !pats.isEmpty else { return extra }
        // The directory walk and the content prefilter run together: each walker thread reads (into a reused buffer, no mmap) the PHP files
        // of the directory it just listed and keeps those that mention a needle.
        let tls = NPReadBuffers()
        var found = phpFiles(root: root, includeVendor: includeVendor, filter: { path in
            if cancel?.isCancelled == true { return false }
            return tls.withBuffer { buf in
                guard let n = readFile(path, into: &buf, limit: 4_000_000) else { return false }
                return buf.withUnsafeBufferPointer { raw -> Bool in
                    for p in pats where containsCI(raw.baseAddress!, n, p) { return true }
                    return false
                }
            }
        })
        var seen = Set(found)
        for e in extra where seen.insert(e).inserted { found.append(e) }
        return found.sorted()
    }

    /// Reads a whole file (< `limit` bytes) into `buf` (grown as needed, reused across calls). nil when unreadable or too big (the old mmap
    /// prefilter skipped those too); an empty file reads as 0 bytes.
    private static func readFile(_ path: String, into buf: inout [UInt8], limit: Int) -> Int? {
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, st.st_size < limit else { return nil }
        let size = Int(st.st_size)
        if size == 0 { return nil }                                  // nothing to find (an empty mmap failed before as well)
        if buf.count < size { buf = [UInt8](repeating: 0, count: max(size, 64 * 1024)) }
        var got = 0
        let ok: Bool = buf.withUnsafeMutableBytes { raw in
            while got < size {
                let r = read(fd, raw.baseAddress! + got, size - got)
                if r <= 0 { break }
                got += r
            }
            return got == size
        }
        return ok ? size : nil
    }

    @inline(__always) private static func lowerByte(_ b: UInt8) -> UInt8 { (b >= 65 && b <= 90) ? b + 32 : b }

    private static func containsCI(_ p: UnsafePointer<UInt8>, _ n: Int, _ needle: [UInt8]) -> Bool {
        let m = needle.count
        guard m <= n else { return false }
        let n0 = needle[0]
        var i = 0
        let last = n - m
        while i <= last {
            if lowerByte(p[i]) == n0 {
                var k = 1
                while k < m, lowerByte(p[i + k]) == needle[k] { k += 1 }
                if k == m { return true }
            }
            i += 1
        }
        return false
    }

    // MARK: - Whole search

    /// Blocking search (run it off the main thread in the app). `onBatch` gets the hits of each processed chunk.
    static func collect(_ sym: NPRefSymbol, options: NPRefsOptions = NPRefsOptions(), liveTexts liveTextsIn: [String: NSString] = [:], cancel: CancelToken? = nil,
                        onBatch: (([NPRefHit], _ done: Int, _ total: Int) -> Void)? = nil) -> NPRefsResult {
        let fp = FastProject.shared(root: URL(fileURLWithPath: sym.root))
        var result = NPRefsResult()
        let rel = NPRelations(fp: fp)
        var liveTexts: [String: NSString] = [:]
        for (k, v) in liveTextsIn { liveTexts[canon(k)] = v }
        var paths: [String]
        if sym.kind == .variable {
            paths = [sym.declPath]
        } else {
            var extra = Array(liveTexts.keys.filter { $0.hasSuffix(".php") || $0.hasSuffix(".phtml") })
            if !sym.declPath.isEmpty { extra.append(sym.declPath) }
            paths = candidates(root: sym.root, needles: sym.searchNames.isEmpty ? [sym.name] : sym.searchNames, includeVendor: options.includeVendor, extra: extra, cancel: cancel)
        }
        result.candidates = paths.count
        var unresolved: [NPRefHit] = []
        var index = 0
        let shared = NPSharedMemo()
        let workers = max(1, min(PowerState.shared.maxWorkers, 4))
        let chunkSize = workers > 1 ? 12 : 6
        func chunkAt(_ i: Int) -> [String] { Array(paths[min(i, paths.count)..<min(paths.count, i + chunkSize)]) }
        // Double buffered: the next chunk is read / lexed / parsed on worker threads while the current one is resolved on the project queue.
        var pending: [PreparedFile?]? = paths.isEmpty ? nil : prepareFiles(sym, paths: chunkAt(0), live: liveTexts, workers: workers)
        while index < paths.count {
            if cancel?.isCancelled == true { result.cancelled = true; break }
            let chunk = chunkAt(index)
            index += chunk.count
            let current = pending ?? []
            var nextBox: [PreparedFile?]?
            let group = DispatchGroup()
            if index < paths.count {
                let nextPaths = chunkAt(index)
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    nextBox = prepareFiles(sym, paths: nextPaths, live: liveTexts, workers: workers)
                    group.leave()
                }
            }
            var batch: [NPRefHit] = []
            fp.queue.sync {
                fp.beginRequest()
                for pf in current {
                    guard let pf else { continue }
                    let s = scanPrepared(sym, pf, fp: fp, rel: rel, opts: options.scan, shared: shared)
                    batch += s.hits
                    result.conflicts += s.conflicts
                }
            }
            group.wait()
            pending = nextBox
            result.filesScanned += chunk.count
            let resolved = batch.filter { $0.role != .unresolved }
            unresolved += batch.filter { $0.role == .unresolved }
            if result.resolvedCount + resolved.count > options.cap {
                result.hits += resolved.prefix(options.cap - result.resolvedCount)
                result.truncated = true
                onBatch?(Array(resolved.prefix(options.cap)), index, paths.count)
                break
            }
            result.hits += resolved
            if !resolved.isEmpty { onBatch?(resolved, index, paths.count) }
        }
        result.hits += unresolved.prefix(200)
        return result
    }

    /// Runs `collect` on a background queue; callbacks arrive on the main queue. Returns the cancel token.
    @discardableResult
    static func collectAsync(_ sym: NPRefSymbol, options: NPRefsOptions = NPRefsOptions(), liveTexts: [String: NSString] = [:],
                             onBatch: (([NPRefHit], Int, Int) -> Void)? = nil, done: @escaping (NPRefsResult) -> Void) -> CancelToken {
        let token = CancelToken()
        DispatchQueue.global(qos: .userInitiated).async {
            let r = collect(sym, options: options, liveTexts: liveTexts, cancel: token) { hits, d, t in
                DispatchQueue.main.async { if !token.isCancelled { onBatch?(hits, d, t) } }
            }
            DispatchQueue.main.async { if !token.isCancelled { done(r) } }
        }
        return token
    }
}
