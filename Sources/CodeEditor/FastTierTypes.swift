import Foundation

// Light local type resolution for the fast tier: evaluates a receiver expression (`$this->user->`, `User::query()->where(..)->`,
// `$post = Post::find(1); $post->`) over PHPLex tokens and lists the members of the resulting type, including Eloquent
// virtual members (columns from migrations, relations, scopes, accessors). Approximate by design: no generics, no flow
// analysis beyond "nearest preceding assignment / param / @var / instanceof".

indirect enum FTType {
    case instance(String)       // object of class FQN
    case staticRef(String)      // `Foo::` (also self/static/parent)
    case builder(String)        // Eloquent builder for model FQN
    case table(String)          // DB::table('x') query builder
    case collection(String?)    // collection of model FQN
}

final class FTEval {
    let fp: FastProject
    let ns: NSString
    let lex: PHPLex
    let cur: FTClass?
    private var hier: [String: [FTClass]] = [:]

    init(fp: FastProject, text: NSString, lex: PHPLex, cur: FTClass?) {
        self.fp = fp; ns = text; self.lex = lex; self.cur = cur
    }

    static let builderMethods: Set<String> = [
        "where", "orWhere", "whereIn", "whereNotIn", "orWhereIn", "whereNull", "whereNotNull", "orWhereNull", "orWhereNotNull", "whereBetween",
        "whereNotBetween", "whereDate", "whereMonth", "whereDay", "whereYear", "whereTime", "whereColumn", "whereHas", "orWhereHas",
        "whereDoesntHave", "whereRelation", "whereKey", "whereKeyNot", "whereLike", "whereAny", "whereAll", "whereNone", "whereNot", "orWhereNot",
        "whereRaw", "orWhereRaw", "whereExists", "whereNotExists", "has", "doesntHave", "orHas", "orderBy", "orderByDesc", "orderByRaw", "latest",
        "oldest", "inRandomOrder", "reorder", "with", "withCount", "withSum", "withAvg", "withMin", "withMax", "withExists", "withTrashed",
        "onlyTrashed", "withoutTrashed", "withWhereHas", "without", "select", "addSelect", "selectRaw", "distinct", "from", "groupBy", "having",
        "havingRaw", "join", "leftJoin", "rightJoin", "crossJoin", "limit", "take", "skip", "offset", "forPage", "lockForUpdate", "sharedLock",
        "query", "newQuery", "newModelQuery", "when", "unless", "tap", "withGlobalScope", "withoutGlobalScope", "withoutGlobalScopes", "withCasts",
        "union", "unionAll",
    ]
    static let singleTerminals: Set<String> = ["first", "firstOrFail", "find", "findOrFail", "findOrNew", "sole", "firstWhere", "firstOr",
                                               "firstOrCreate", "firstOrNew", "updateOrCreate", "create", "forceCreate", "make", "fresh", "replicate"]
    static let listTerminals: Set<String> = ["get", "all", "findMany", "cursor", "lazy"]
    static let paginators: Set<String> = ["paginate", "simplePaginate", "cursorPaginate"]
    static let columnMethods: Set<String> = [
        "where", "orWhere", "whereIn", "whereNotIn", "orWhereIn", "whereNull", "whereNotNull", "orWhereNull", "orWhereNotNull", "whereBetween",
        "whereNotBetween", "whereDate", "whereMonth", "whereDay", "whereYear", "whereTime", "whereColumn", "whereNot", "orWhereNot", "whereLike",
        "orderBy", "orderByDesc", "latest", "oldest", "pluck", "value", "select", "addSelect", "groupBy", "having", "min", "max", "sum", "avg",
        "average", "count", "firstWhere", "increment", "decrement", "distinct", "chunkById", "whereKey", "get", "first", "find", "findOrFail", "paginate",
    ]
    static let relationMethods: Set<String> = [
        "with", "has", "orHas", "whereHas", "orWhereHas", "doesntHave", "whereDoesntHave", "withCount", "withSum", "withAvg", "withMin", "withMax",
        "withExists", "withWhereHas", "load", "loadMissing", "loadCount", "whereRelation", "without",
    ]
    private static let sameBuilderCallbacks: Set<String> = ["where", "orWhere", "when", "unless", "tap", "whereNot", "orWhereNot", "chunk", "each"]
    private static let relationCallbacks: Set<String> = ["whereHas", "orWhereHas", "whereDoesntHave", "withWhereHas", "has", "orHas", "with",
                                                         "withCount", "load", "loadMissing", "whereRelation"]
    private static let keywords: Set<String> = ["return", "echo", "print", "if", "elseif", "while", "foreach", "for", "switch", "match", "fn",
                                                "function", "and", "or", "xor", "new", "use", "throw", "yield", "as", "else", "case", "isset", "empty", "catch"]

    // MARK: Hierarchy

    func hierarchy(_ fqn: String) -> [FTClass] {
        if let h = hier[fqn] { return h }
        var out: [FTClass] = []
        var seen = Set<String>()
        func visit(_ name: String, depth: Int) {
            guard depth < 14, out.count < 60, seen.insert(name).inserted else { return }
            let c: FTClass? = (name == cur?.fqn && cur != nil) ? cur : fp.classInfo(name)
            guard let c else { return }
            out.append(c)
            for t in c.traits { visit(t, depth: depth + 1) }
            if let e = c.extends { visit(e, depth: depth + 1) }
            if c.kind == "interface" || c.kind == "enum" { for i in c.implements { visit(i, depth: depth + 1) } }
        }
        visit(fqn, depth: 0)
        hier[fqn] = out
        return out
    }

    func findMethod(_ fqn: String, _ name: String) -> (FTClass, FTMethod)? {
        for k in hierarchy(fqn) { if let m = k.methods.first(where: { $0.name == name }) { return (k, m) } }
        return nil
    }
    func findProp(_ fqn: String, _ name: String) -> (FTClass, FTProp)? {
        for k in hierarchy(fqn) { if let p = k.props.first(where: { $0.name == name }) { return (k, p) } }
        return nil
    }
    func findRelation(_ fqn: String, _ name: String) -> FTRelation? {
        for k in hierarchy(fqn) { if let r = k.relations.first(where: { $0.name == name }) { return r } }
        return nil
    }
    func isModel(_ fqn: String) -> Bool { hierarchy(fqn).first.map { fp.isModel($0) } ?? false }

    func modelFQN(_ t: FTType) -> String? {
        switch t {
        case .instance(let f), .staticRef(let f), .builder(let f): return isModel(f) ? f : nil
        case .collection(let f): return f
        case .table: return nil
        }
    }

    // MARK: Token helpers

    func tokenIndex(atOrAfter loc: Int) -> Int {
        var lo = 0, hi = lex.count
        while lo < hi { let mid = (lo + hi) / 2; if lex.toks[mid].loc < loc { lo = mid + 1 } else { hi = mid } }
        return lo
    }

    private func isOp(_ i: Int) -> Bool { lex.isPunct(i, code: PHPTok.arrow) || lex.isPunct(i, code: PHPTok.dcolon) }
    private func isKeyword(_ i: Int) -> Bool { lex.toks[i].kind == .ident && Self.keywords.contains(lex.text(i)) }

    /// First token of the member chain that ends right before token `hi`.
    func chainStart(before hi: Int) -> Int {
        var i = hi - 1
        var guardCount = 0
        while i >= 0, guardCount < 200 {
            guardCount += 1
            let t = lex.toks[i]
            if t.kind == .punct, t.ch == 41 {                      // )
                let j = lex.match[i]
                guard j >= 0 else { return i + 1 }
                if j >= 1, lex.toks[j - 1].kind == .ident, !isKeyword(j - 1) { i = j - 1; continue }
                return j
            }
            if t.kind == .punct, t.ch == 93 {                       // ]
                let j = lex.match[i]
                guard j >= 1 else { return i + 1 }
                i = j - 1; continue
            }
            if t.kind == .ident || t.kind == .variable {
                if i >= 1, isOp(i - 1), i >= 2 { i -= 2; continue }
                if t.kind == .ident, i >= 1, lex.isIdent(i - 1, "new") { return i - 1 }
                return i
            }
            return i + 1
        }
        return max(0, i + 1)
    }

    func argTokens(_ open: Int) -> (Int, Int)? {
        guard lex.isPunct(open, "("), lex.match[open] > open else { return nil }
        return (open + 1, lex.match[open])
    }

    private func firstClassConst(_ a: Int, _ b: Int) -> String? {
        guard a + 2 < b, lex.toks[a].kind == .ident, lex.isPunct(a + 1, code: PHPTok.dcolon), lex.isIdent(a + 2, "class") else { return nil }
        return lex.text(a)
    }

    // MARK: Evaluation

    func eval(_ lo: Int, _ hi: Int, depth: Int = 0) -> FTType? {
        guard lo < hi, lo < lex.count, depth < 6 else { return nil }
        var i = lo
        var t: FTType?
        let first = lex.toks[lo]
        if first.kind == .variable {
            let name = lex.text(lo)
            i += 1
            if name == "$this" { t = cur.flatMap { $0.fqn.isEmpty ? nil : .instance($0.fqn) } }
            else { t = varType(name, at: lo, depth: depth + 1) }
        } else if lex.isPunct(lo, "("), lex.match[lo] > lo {
            t = eval(lo + 1, lex.match[lo], depth: depth + 1)
            i = lex.match[lo] + 1
        } else if lex.isIdent(lo, "new"), lo + 1 < lex.count, lex.toks[lo + 1].kind == .ident {
            let w = lex.text(lo + 1)
            let l = w.lowercased()
            if l == "static" || l == "self" { t = cur.map { .instance($0.fqn) } }
            else if let f = fp.resolveClass(w, in: cur) { t = .instance(f) }
            i = lo + 2
            if lex.isPunct(i, "("), lex.match[i] > i { i = lex.match[i] + 1 }
        } else if first.kind == .ident {
            let w = lex.text(lo)
            if lo + 1 < lex.count, lex.isPunct(lo + 1, code: PHPTok.dcolon) {
                let l = w.lowercased()
                if l == "self" || l == "static" { t = cur.map { .staticRef($0.fqn) } }
                else if l == "parent" { t = cur?.extends.map { .staticRef($0) } }
                else if let f = fp.resolveClass(w, in: cur) { t = .staticRef(f) }
                i = lo + 1
            } else if lex.isPunct(lo + 1, "("), lex.match[lo + 1] > lo + 1 {
                let open = lo + 1
                switch w.lowercased() {
                case "app", "resolve", "make":
                    if let (a, b) = argTokens(open), let n = firstClassConst(a, b), let f = fp.resolveClass(n, in: cur) { t = .instance(f) }
                case "now", "today": t = .instance("Illuminate\\Support\\Carbon")
                case "request": t = .instance("Illuminate\\Http\\Request")
                case "collect": t = .collection(nil)
                default: break
                }
                i = lex.match[open] + 1
            } else { return nil }
        } else { return nil }
        while i < hi, let cur0 = t {
            if lex.isPunct(i, code: PHPTok.arrow) || lex.isPunct(i, code: PHPTok.dcolon) {
                let isStaticOp = lex.isPunct(i, code: PHPTok.dcolon)
                i += 1
                guard i < lex.count, lex.toks[i].kind == .ident || lex.toks[i].kind == .variable else { return nil }
                let member = lex.toks[i].kind == .variable ? String(lex.text(i).dropFirst()) : lex.text(i)
                i += 1
                var args: (Int, Int)?
                var isCall = false
                if i < lex.count, lex.isPunct(i, "("), lex.match[i] > i { isCall = true; args = argTokens(i); i = lex.match[i] + 1 }
                t = step(cur0, member, isCall: isCall, isStatic: isStaticOp, args: args)
            } else if lex.isPunct(i, "["), lex.match[i] > i {
                if case .collection(let m)? = t, let m { t = .instance(m) } else { t = nil }
                i = lex.match[i] + 1
            } else { break }
        }
        return i >= hi ? t : nil
    }

    private func relationType(_ r: FTRelation, call: Bool) -> FTType? {
        guard let rel = r.related else { return nil }
        if call { return .builder(rel) }
        return FTParser.singleRelations.contains(r.kind) ? .instance(rel) : .collection(rel)
    }

    private func methodReturn(_ owner: FTClass, _ m: FTMethod, selfType: String, isStatic: Bool) -> FTType? {
        let raw = m.ret
        guard !raw.isEmpty else { return nil }
        let first = FTClass.firstClassName(raw) ?? ""
        let l = first.lowercased()
        if l == "static" || l == "self" || l == "$this" { return .instance(selfType) }
        guard let f = owner.classType(raw), !f.isEmpty else { return nil }
        if let r = fp.resolveClass(f, in: nil) { return .instance(r) }
        return nil
    }

    func step(_ t: FTType, _ member: String, isCall: Bool, isStatic: Bool, args: (Int, Int)?) -> FTType? {
        switch t {
        case .table(let tbl):
            if Self.builderMethods.contains(member) { return .table(tbl) }
            if Self.listTerminals.contains(member) { return .collection(nil) }
            return nil
        case .collection(let m):
            switch member {
            case "first", "last", "firstWhere", "find", "sole", "pop", "shift", "random", "firstOrFail": return m.map { .instance($0) }
            case "filter", "where", "whereIn", "sortBy", "sortByDesc", "reverse", "values", "take", "skip", "unique", "reject", "slice", "merge", "each", "tap",
                 "load", "loadMissing", "push", "sort", "whereNotNull", "keyBy", "forPage", "chunk":
                return .collection(m)
            default: return nil
            }
        case .builder(let m):
            return builderStep(m, member, isCall: isCall, args: args)
        case .instance(let f), .staticRef(let f):
            if isModel(f) {
                if let r = findRelation(f, member), !(isStatic) { return relationType(r, call: isCall) }
                if hierarchy(f).contains(where: { $0.scopes.contains(member) }) { return .builder(f) }
                if f != "Illuminate\\Support\\Facades\\DB", findMethod(f, member) == nil || Self.builderMethods.contains(member) || Self.singleTerminals.contains(member) {
                    if let r = builderStep(f, member, isCall: isCall, args: args) { return r }
                }
            }
            if f == "Illuminate\\Support\\Facades\\DB", member == "table", let (a, b) = args, a < b, lex.toks[a].kind == .string { return .table(lex.strValue(a)) }
            if isCall {
                if let (owner, m) = findMethod(f, member) {
                    var selfT = f
                    if case .staticRef = t { selfT = f }
                    return methodReturn(owner, m, selfType: selfT, isStatic: isStatic)
                }
            } else if let (owner, p) = findProp(f, member), !p.type.isEmpty, let ct = owner.classType(p.type), let r = fp.resolveClass(ct, in: nil) {
                return .instance(r)
            }
            return nil
        }
    }

    private func builderStep(_ m: String, _ member: String, isCall: Bool, args: (Int, Int)?) -> FTType? {
        if Self.singleTerminals.contains(member), isCall {
            if member == "find", let (a, _) = args, lex.isPunct(a, "[") { return .collection(m) }
            return .instance(m)
        }
        if Self.listTerminals.contains(member) { return .collection(m) }
        if Self.paginators.contains(member) { return .instance("Illuminate\\Pagination\\LengthAwarePaginator") }
        if Self.builderMethods.contains(member) || hierarchy(m).contains(where: { $0.scopes.contains(member) }) { return .builder(m) }
        return nil
    }

    // MARK: Variables

    private struct FnScope { var fn: Int; var params: (Int, Int); var bodyOpen: Int; var bodyClose: Int }

    private func enclosingFunctions(_ at: Int) -> [FnScope] {
        var out: [FnScope] = []
        var i = at - 1
        var steps = 0
        while i >= 0, steps < 60_000 {
            steps += 1
            if lex.toks[i].kind == .ident, (lex.text(i) == "function" || lex.text(i) == "fn") {
                var k = i + 1
                if lex.isPunct(k, "&") { k += 1 }
                if k < lex.count, lex.toks[k].kind == .ident, lex.text(i) == "function" { k += 1 }
                if lex.isPunct(k, "("), lex.match[k] > k {
                    let pc = lex.match[k]
                    var b = pc + 1
                    var bodyOpen = -1, bodyClose = -1
                    if lex.text(i) == "fn" {
                        var q = b
                        while q < lex.count, !lex.isPunct(q, code: PHPTok.fat) { q += 1; if q - b > 12 { break } }
                        // arrow fn: scope extends to the end of the expression
                        var e = q + 1
                        var d = 0
                        while e < lex.count {
                            let t = lex.toks[e]
                            if t.kind == .punct {
                                if [40, 91, 123].contains(t.ch) { d += 1 } else if [41, 93, 125].contains(t.ch) { if d == 0 { break }; d -= 1 }
                                else if (t.ch == 44 || t.ch == 59), d == 0 { break }
                            }
                            e += 1
                        }
                        bodyOpen = q; bodyClose = e
                    } else {
                        while b < lex.count, !lex.isPunct(b, "{"), !lex.isPunct(b, ";") { b += 1; if b - pc > 60 { break } }
                        if lex.isPunct(b, "{") { bodyOpen = b; bodyClose = lex.match[b] > b ? lex.match[b] : lex.count }
                    }
                    if bodyOpen >= 0, (at > k && at <= bodyClose) { out.append(FnScope(fn: i, params: (k + 1, pc), bodyOpen: bodyOpen, bodyClose: bodyClose)) }
                    if lex.text(i) == "function", bodyOpen >= 0, out.last?.fn == i, lex.isIdent(i - 1, "static") == false, isMethodDecl(i) { break }
                }
            }
            i -= 1
        }
        return out
    }

    private func isMethodDecl(_ fnIdx: Int) -> Bool {
        // `function name(` (named => method or top-level function) ends the outward search
        var k = fnIdx + 1
        if lex.isPunct(k, "&") { k += 1 }
        return k < lex.count && lex.toks[k].kind == .ident
    }

    /// Param types by name for the params token range.
    private func paramType(_ name: String, _ range: (Int, Int)) -> (type: String, found: Bool) {
        var depth = 0
        var segStart = range.0
        var i = range.0
        func seg(_ a: Int, _ b: Int) -> (String, Bool)? {
            guard a < b else { return nil }
            var type = ""
            for q in a..<b {
                let t = lex.toks[q]
                if t.kind == .variable { return lex.text(q) == name ? (type, true) : nil }
                if t.kind == .ident { let w = lex.text(q); if !["public", "private", "protected", "readonly"].contains(w) { type += w } }
                else if t.kind == .punct, t.ch == 63 || t.ch == 124 { type += lex.text(q) }
            }
            return nil
        }
        while i <= range.1 {
            let atEnd = i == range.1
            if !atEnd, lex.toks[i].kind == .punct {
                let ch = lex.toks[i].ch
                if [40, 91, 123].contains(ch) { depth += 1 } else if [41, 93, 125].contains(ch) { depth -= 1 }
            }
            if atEnd || (lex.toks[i].kind == .punct && lex.toks[i].ch == 44 && depth == 0) {
                if let r = seg(segStart, i) { return r }
                segStart = i + 1
            }
            i += 1
        }
        return ("", false)
    }

    func varType(_ name: String, at tok: Int, depth: Int) -> FTType? {
        guard depth < 6 else { return nil }
        let scopes = enclosingFunctions(tok)
        let atLoc = lex.toks[min(tok, lex.count - 1)].loc
        var candidates: [(loc: Int, type: FTType?)] = []
        func scan(from lo: Int, to hi: Int) {
            var i = hi - 1
            while i >= lo {
                let t = lex.toks[i]
                if t.kind == .variable, lex.text(i) == name, !(i > 0 && isOp(i - 1)) {
                    if lex.isPunct(i + 1, "="), !lex.isPunct(i + 2, "="), !lex.isPunct(i + 2, code: PHPTok.fat), !lex.isPunct(i - 1, "=") {
                        var e = i + 2
                        var d = 0
                        while e < lex.count {
                            let k = lex.toks[e]
                            if k.kind == .punct {
                                if [40, 91, 123].contains(k.ch), lex.match[e] > e { e = lex.match[e] + 1; continue }
                                if (k.ch == 59 || k.ch == 41 || k.ch == 93 || k.ch == 125), d == 0 { break }
                            }
                            e += 1
                        }
                        candidates.append((lex.toks[i].loc, eval(i + 2, e, depth: depth + 1)))
                        return
                    }
                    if lex.isIdent(i - 1, "as") {
                        // foreach (EXPR as $x)
                        var s = i - 2
                        var d = 0
                        while s >= lo {
                            let k = lex.toks[s]
                            if k.kind == .punct, k.ch == 41 || k.ch == 93 || k.ch == 125 { d += 1 }
                            if k.kind == .punct, k.ch == 40 || k.ch == 91 || k.ch == 123 { if d == 0 { break }; d -= 1 }
                            s -= 1
                        }
                        if s >= lo, lex.isPunct(s, "("), s > 0, lex.isIdent(s - 1, "foreach"), let et = eval(s + 1, i - 1, depth: depth + 1) {
                            if case .collection(let m) = et, let m { candidates.append((lex.toks[i].loc, .instance(m))) } else { candidates.append((lex.toks[i].loc, nil)) }
                            return
                        }
                    }
                    if i + 2 < lex.count, lex.isIdent(i + 1, "instanceof"), lex.toks[i + 2].kind == .ident, let f = fp.resolveClass(lex.text(i + 2), in: cur) {
                        candidates.append((lex.toks[i].loc, .instance(f)))
                        return
                    }
                }
                i -= 1
            }
        }
        var startLoc = 0
        for sc in scopes {
            let pt = paramType(name, sc.params)
            if pt.found {
                if !pt.type.isEmpty, let c = cur ?? Optional(FTClass()), let ct = c.classType(pt.type), let f = fp.resolveClass(ct, in: nil) {
                    candidates.append((lex.toks[sc.fn].loc, .instance(f)))
                } else if pt.type.isEmpty, let t = callbackParamType(sc, depth: depth) {
                    candidates.append((lex.toks[sc.fn].loc, t))
                }
                scan(from: sc.bodyOpen, to: tok)
                startLoc = lex.toks[sc.fn].loc
                break
            }
            scan(from: sc.bodyOpen, to: tok)
            startLoc = lex.toks[sc.fn].loc
            if !candidates.isEmpty { break }
        }
        if scopes.isEmpty { scan(from: 0, to: tok) }
        // @var Type $name docblocks between the function start and here
        if atLoc > startLoc {
            let rng = NSRange(location: startLoc, length: atLoc - startLoc)
            let pat = "@var\\s+([\\\\\\w|?]+)\\s+\\$" + NSRegularExpression.escapedPattern(for: String(name.dropFirst())) + "\\b"
            if let re = try? NSRegularExpression(pattern: pat), let m = re.matches(in: ns as String, range: rng).last {
                let raw = ns.substring(with: m.range(at: 1))
                if let ct = (cur ?? FTClass()).classType(raw), let f = fp.resolveClass(ct, in: nil) { candidates.append((m.range.location, .instance(f))) }
            }
        }
        return candidates.max(by: { $0.loc < $1.loc })?.type
    }

    /// Untyped closure param inside a builder callback (`where(function ($q) {`, `whereHas('posts', fn ($q) =>`).
    private func callbackParamType(_ sc: FnScope, depth: Int) -> FTType? {
        // enclosing call parens of the closure
        var i = sc.fn - 1
        var d = 0
        var comma = 0
        while i >= 0 {
            let t = lex.toks[i]
            if t.kind == .punct {
                if [41, 93, 125].contains(t.ch) { if lex.match[i] > 0 { i = lex.match[i] - 1; continue } }
                if t.ch == 40 { if d == 0 { break }; d -= 1 }
                if t.ch == 44 { comma += 1 }
                if t.ch == 59 || t.ch == 123 || t.ch == 91 { return nil }
            }
            i -= 1
        }
        guard i >= 1, lex.toks[i - 1].kind == .ident, i >= 2, isOp(i - 2) else { return nil }
        let method = lex.text(i - 1)
        let lo = chainStart(before: i - 2)
        guard let recv = eval(lo, i - 2, depth: depth + 1) else { return nil }
        if Self.sameBuilderCallbacks.contains(method) {
            switch recv {
            case .builder(let m): return .builder(m)
            case .instance(let m), .staticRef(let m): return isModel(m) ? .builder(m) : nil
            case .table(let t): return .table(t)
            default: return nil
            }
        }
        if Self.relationCallbacks.contains(method), let (a, b) = argTokens(i), a < b, lex.toks[a].kind == .string, let model = modelFQN(recv) {
            return relatedModel(model, lex.strValue(a)).map { .builder($0) }
        }
        return nil
    }

    func relatedModel(_ model: String, _ dotted: String) -> String? {
        var m = model
        for seg in dotted.split(separator: ".") {
            guard let r = findRelation(m, String(seg)), let rel = r.related else { return nil }
            m = rel
        }
        return m
    }

    // MARK: Member listing

    private static let eloquentBuilder = "Illuminate\\Database\\Eloquent\\Builder"
    private static let queryBuilder = "Illuminate\\Database\\Query\\Builder"
    private static let collectionClass = "Illuminate\\Support\\Collection"

    private func methodItem(_ m: FTMethod, sort: String, owner: String) -> CompletionItem {
        let noArgs = m.params.isEmpty
        let detail = "(" + m.params + ")" + (m.ret.isEmpty ? "" : ": " + m.ret)
        var it = CI.make(m.name, .method, detail: detail, insert: noArgs ? m.name + "()" : m.name + "($1)$0", snippet: !noArgs, sort: sort + m.name.lowercased(),
                         doc: "```php\n\(m.name)\(detail)\n```\n\(owner)")
        it.deprecated = false
        return it
    }

    func members(of t: FTType, via: String?, fromSameClass: Bool, staticDollar: Bool, onlyNames: inout Set<String>) -> [CompletionItem] {
        var out: [CompletionItem] = []
        func add(_ it: CompletionItem) { if onlyNames.insert(it.kind.rawValue + ":" + it.label).inserted { out.append(it) } }
        func classMembers(_ fqn: String, instance: Bool, includeAll: Bool, base: String) {
            for (idx, k) in hierarchy(fqn).enumerated() {
                let own = idx == 0 || (fromSameClass && k.kind == "trait")
                func visible(_ vis: Int) -> Bool { vis == 0 || (vis == 1 && fromSameClass) || (vis == 2 && own && fromSameClass) }
                for m in k.methods where visible(m.vis) && !m.name.hasPrefix("__") && (instance || m.isStatic || includeAll) {
                    add(methodItem(m, sort: base + (m.isStatic == instance ? "b" : "a"), owner: k.fqn))
                }
                if instance {
                    for p in k.props where !p.isStatic && visible(p.vis) { add(CI.make(p.name, .property, detail: p.type, sort: base + "a" + p.name.lowercased(), doc: k.fqn)) }
                } else {
                    for c in k.consts { add(CI.make(c, .constant, detail: k.name, sort: base + "a" + c.lowercased())) }
                    for c in k.cases { add(CI.make(c, .enumMember, detail: k.name, sort: base + "a" + c.lowercased())) }
                    if staticDollar { for p in k.props where p.isStatic && visible(p.vis) { add(CI.make("$" + p.name, .property, detail: p.type, sort: base + "a" + p.name.lowercased())) } }
                }
            }
        }
        func builderMembers(_ model: String?, base: String) {
            if let model {
                for k in hierarchy(model) { for s in k.scopes { add(CI.make(s, .method, detail: "scope", insert: s + "($1)$0", snippet: true, sort: base + "a" + s.lowercased(), doc: "Eloquent scope on \(k.name)")) } }
            }
            var found = false
            for b in [Self.eloquentBuilder, Self.queryBuilder] {
                let h = hierarchy(b)
                if h.isEmpty { continue }
                found = true
                for k in h { for m in k.methods where m.vis == 0 && !m.name.hasPrefix("__") { add(methodItem(m, sort: base + "c", owner: k.fqn)) } }
            }
            if !found { for l in CI.lines(CompletionData.eloquentStatic) { var it = CI.member(l, kind: .method, sort: base + "c"); it.sortText = base + "c" + it.label.lowercased(); add(it) } }
        }
        switch t {
        case .instance(let f):
            classMembers(f, instance: true, includeAll: false, base: "0")
            if let c = hierarchy(f).first, isModel(f) {
                for col in fp.columns(of: c) { add(CI.make(col.name, .field, detail: col.type, sort: "0a" + col.name.lowercased(), doc: "Column of `\(fp.tableName(of: c))`")) }
                for k in hierarchy(f) { for r in k.relations { add(CI.make(r.name, .property, detail: r.kind + (r.related.map { " " + (($0 as NSString).lastPathComponent) } ?? ""), sort: "0a" + r.name.lowercased(), doc: "Eloquent relation")) } }
                builderMembers(f, base: "1")
            }
        case .staticRef(let f):
            let viaL = (via ?? "").lowercased()
            let all = viaL == "self" || viaL == "static" || viaL == "parent"
            classMembers(f, instance: false, includeAll: all, base: "0")
            if !staticDollar { add(CI.make("class", .constant, detail: "class name", sort: "0z")) }
            if isModel(f), !staticDollar { builderMembers(f, base: "1") }
        case .builder(let m):
            builderMembers(m, base: "0")
        case .table:
            builderMembers(nil, base: "0")
        case .collection:
            for k in hierarchy(Self.collectionClass) { for m in k.methods where m.vis == 0 && !m.name.hasPrefix("__") { add(methodItem(m, sort: "0", owner: k.fqn)) } }
        }
        return out
    }
}
