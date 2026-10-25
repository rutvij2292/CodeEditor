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

/// Memo shared by the resolvers of one multi-file request (find usages / rename): docblock queries and class hierarchies of library
/// classes do not depend on the file being resolved, so thousands of lookups in hundreds of files parse / walk each of them once.
/// Entries never involve the file's own (possibly unsaved) class: those stay in the per-resolver caches. Lives for one request,
/// only touched on the project's queue.
final class NPSharedMemo {
    static let cap = 3000
    var docs: [String: NPDoc] = [:]
    var classDocs: [String: NPDoc] = [:]
    var hier: [String: [FTClass]] = [:]
    func trimIfNeeded() {
        if docs.count > Self.cap { docs.removeAll() }
        if classDocs.count > Self.cap { classDocs.removeAll() }
        if hier.count > Self.cap { hier.removeAll() }
    }
}

/// See `FTEval.hierarchy`. A Sequence; `all` / `count` force the complete list.
final class FTHier: Sequence {
    private unowned let ev: FTEval?
    private let rootName: String
    private(set) var out: [FTClass] = []
    private var stack: [(name: String, depth: Int)]
    private var seen = Set<String>()
    private(set) var done = false

    init(ev: FTEval, fqn: String) { self.ev = ev; rootName = fqn; stack = [(fqn, 0)] }
    init(done list: [FTClass]) { ev = nil; rootName = ""; stack = []; out = list; done = true }

    /// Loads the next class of the walk; false when the walk is complete.
    @discardableResult
    private func advance() -> Bool {
        guard !done, let ev else { return false }
        while let (name, depth) = stack.popLast() {
            guard depth < 14, out.count < 60, seen.insert(name).inserted else { continue }
            let c: FTClass? = (name == ev.cur?.fqn && ev.cur != nil) ? ev.cur : ev.fp.classInfo(name)
            guard let c else { continue }
            out.append(c)
            var kids = c.traits
            if let e = c.extends { kids.append(e) }
            if c.kind == "interface" || c.kind == "enum" { kids += c.implements }
            for k in kids.reversed() { stack.append((k, depth + 1)) }      // popped in the order the recursive walk visited them
            if !kids.isEmpty { ev.fp.prefetch(kids) }                      // read + parse the next classes in parallel
            return true
        }
        done = true
        ev.hierarchyComplete(rootName, out)
        return false
    }

    func element(_ i: Int) -> FTClass? {
        while out.count <= i, advance() {}
        return i < out.count ? out[i] : nil
    }
    var first: FTClass? { element(0) }
    var all: [FTClass] { while advance() {}; return out }
    var count: Int { all.count }
    var isEmpty: Bool { first == nil }

    func makeIterator() -> AnyIterator<FTClass> {
        var i = 0
        return AnyIterator { [self] in
            guard let k = element(i) else { return nil }
            i += 1
            return k
        }
    }
}

final class FTEval {
    let fp: FastProject
    var shared: NPSharedMemo?
    let ns: NSString
    let lex: PHPLex
    let cur: FTClass?
    private var hier: [String: FTHier] = [:]
    // Per-request caches / state for the docblock-aware inference (NativePHPSigTypes.swift).
    var docCache: [String: NPDoc] = [:]
    var authGuard: String?
    var authModelCache: [String: String] = [:]
    var ctorPropCache: [String: String] = [:]
    var facadeRootCache: [String: String] = [:]

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
    static let keywords: Set<String> = ["return", "echo", "print", "if", "elseif", "while", "foreach", "for", "switch", "match", "fn",
                                                "function", "and", "or", "xor", "new", "use", "throw", "yield", "as", "else", "case", "isset", "empty", "catch"]

    // MARK: Hierarchy

    /// Lazily materialised class hierarchy (traits, parent, interfaces' parents, depth first, same order and caps as the former eager walk).
    /// Callers that only need the first class that declares a member stop early, so a cold lookup into a big vendor hierarchy
    /// (Carbon: 31 files) reads and parses only the classes up to the match.
    func hierarchy(_ fqn: String) -> FTHier {
        if let h = hier[fqn] { return h }
        let h: FTHier
        if let sh = shared?.hier[fqn], cur == nil || !sh.contains(where: { $0.fqn == cur!.fqn }) { h = FTHier(done: sh) }
        else { h = FTHier(ev: self, fqn: fqn) }
        hier[fqn] = h
        return h
    }

    fileprivate func hierarchyComplete(_ fqn: String, _ out: [FTClass]) {
        if let shared, cur == nil || !out.contains(where: { $0.fqn == cur!.fqn }) { shared.hier[fqn] = out; shared.trimIfNeeded() }
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

    /// Top-level `a ? b : c`, `a ?: c` (branches b / c) or `a ?? c` as token ranges to evaluate; nil for any other expression.
    private func branches(_ lo: Int, _ hi: Int) -> [(Int, Int)]? {
        var i = lo
        var coalesce: Int?
        while i < hi {
            let t = lex.toks[i]
            if t.kind == .punct {
                if [40, 91, 123].contains(t.ch), lex.match[i] > i { i = lex.match[i] + 1; continue }
                if t.ch == 63 {
                    if lex.isPunct(i + 1, "?") { if coalesce == nil { coalesce = i }; i += 2; continue }
                    var nest = 0, j = i + 1
                    while j < hi {
                        let k = lex.toks[j]
                        if k.kind == .punct {
                            if [40, 91, 123].contains(k.ch), lex.match[j] > j { j = lex.match[j] + 1; continue }
                            if k.ch == 63 { if lex.isPunct(j + 1, "?") { j += 2; continue }; nest += 1 }
                            else if k.ch == 58 { if nest == 0 { return [i + 1 == j ? (lo, i) : (i + 1, j), (j + 1, hi)] }; nest -= 1 }
                        }
                        j += 1
                    }
                    return nil
                }
            }
            i += 1
        }
        if let c = coalesce { return [(lo, c), (c + 2, hi)] }
        return nil
    }

    private func typeKey(_ t: FTType) -> String {
        switch t {
        case .instance(let f): return "i" + f
        case .staticRef(let f): return "s" + f
        case .builder(let f): return "b" + f
        case .table(let f): return "t" + f
        case .collection(let f): return "c" + (f ?? "")
        }
    }

    func eval(_ lo: Int, _ hi: Int, depth: Int = 0) -> FTType? {
        guard lo < hi, lo < lex.count, depth < 9 else { return nil }
        if let parts = branches(lo, hi) {
            // both branches agree, or only one is known (the other is unknown, not different)
            var found: FTType?
            for p in parts where p.0 < p.1 {
                guard let t = eval(p.0, p.1, depth: depth + 1) else { continue }
                if let f = found, typeKey(f) != typeKey(t) { return nil }
                found = t
            }
            return found
        }
        authGuard = nil
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
                    else { t = containerHelper(w.lowercased(), args: argTokens(open)) }
                case "now", "today": t = .instance("Illuminate\\Support\\Carbon")
                case "request": t = .instance("Illuminate\\Http\\Request")
                case "collect": t = .collection(nil)
                case "auth":
                    authGuard = nil
                    if let (a, b) = argTokens(open), a < b, lex.toks[a].kind == .string { authGuard = lex.strValue(a) }
                    t = .instance(Self.guardFQN)
                default: t = functionReturn(w, args: argTokens(open))
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

    private func methodReturn(_ owner: FTClass, _ m: FTMethod, selfType: String, isStatic: Bool, args: (Int, Int)? = nil) -> FTType? {
        refineReturn(declaredReturn(owner, m, selfType: selfType, isStatic: isStatic), owner: owner, m: m, selfType: selfType, args: args)
    }

    private func declaredReturn(_ owner: FTClass, _ m: FTMethod, selfType: String, isStatic: Bool) -> FTType? {
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
            if let au = authStep(f, member, isCall: isCall, args: args) { return au }
            if case .staticRef = t, !isCall || member == "from" || member == "tryFrom", let k = hierarchy(f).first, k.kind == "enum",
               k.cases.contains(member) || member == "from" || member == "tryFrom" { return .instance(f) }     // Status::Draft, Status::from('x')
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
                    return methodReturn(owner, m, selfType: f, isStatic: isStatic, args: args)
                }
                if case .staticRef = t, let root = facadeRoot(f), findMethod(root, member) != nil {
                    return step(.instance(root), member, isCall: isCall, isStatic: false, args: args)
                }
                return docMemberType(f, member, isCall: true)
            } else if let (owner, p) = findProp(f, member) {
                return propType(owner, p, selfType: f)
            }
            return docMemberType(f, member, isCall: false)
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

    struct FnScope { var fn: Int; var params: (Int, Int); var bodyOpen: Int; var bodyClose: Int }

    func enclosingFunctions(_ at: Int) -> [FnScope] {
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

    /// `[$a, $b] = RHS;` / `list($a, $b) = RHS;` with the variable at token `i`: the position in the list and the RHS token range.
    private func listDestructure(_ i: Int, lo: Int) -> (rhs: Int, end: Int, index: Int)? {
        guard i > lo, lex.toks[i - 1].kind == .punct, [91, 44, 40].contains(lex.toks[i - 1].ch),
              i + 1 < lex.count, lex.toks[i + 1].kind == .punct, [93, 44, 41].contains(lex.toks[i + 1].ch) else { return nil }
        var s = i - 1, idx = 0
        while s >= lo {
            let k = lex.toks[s]
            if k.kind == .punct {
                if k.ch == 41 || k.ch == 93 || k.ch == 125 { if lex.match[s] >= lo, lex.match[s] < s { s = lex.match[s] - 1; continue }; return nil }
                if k.ch == 91 || k.ch == 123 || k.ch == 40 { break }
                if k.ch == 44 { idx += 1 } else if k.ch == 59 || k.ch == PHPTok.fat { return nil }
            }
            s -= 1
        }
        guard s >= lo, s > 0 else { return nil }
        let open = lex.toks[s]
        let prev = lex.toks[s - 1]
        if open.ch == 91 {
            if prev.kind == .variable || prev.kind == .ident || prev.kind == .string { return nil }
            if prev.kind == .punct, prev.ch == 93 || prev.ch == 41 || prev.ch == PHPTok.arrow || prev.ch == PHPTok.dcolon { return nil }
        } else if !(open.ch == 40 && prev.kind == .ident && lex.text(s - 1).lowercased() == "list") { return nil }
        let close = lex.match[s]
        guard close > s, lex.isPunct(close + 1, "="), !lex.isPunct(close + 2, "="), !lex.isPunct(close + 2, code: PHPTok.fat) else { return nil }
        var e = close + 2
        while e < lex.count {
            let k = lex.toks[e]
            if k.kind == .punct {
                if [40, 91, 123].contains(k.ch), lex.match[e] > e { e = lex.match[e] + 1; continue }
                if k.ch == 59 || k.ch == 41 || k.ch == 93 || k.ch == 125 { break }
            }
            e += 1
        }
        return (close + 2, e, idx)
    }

    /// Type of element `index` of the array a call returns, for `$this->name(..)` / `self::name(..)` calls whose method sits in this file and
    /// ends in `return [ a, b, c ];` (positional elements only).
    private func listElementType(_ lo: Int, _ hi: Int, index: Int, depth: Int) -> FTType? {
        guard depth < 9, hi - lo >= 5, lex.isPunct(hi - 1, ")"), lex.match[hi - 1] > lo else { return nil }
        let open = lex.match[hi - 1]
        guard open >= lo + 3, lex.toks[open - 1].kind == .ident, lex.isPunct(open - 2, code: PHPTok.arrow) || lex.isPunct(open - 2, code: PHPTok.dcolon), open - 3 == lo else { return nil }
        let recv = lex.text(lo).lowercased()
        guard recv == "$this" || recv == "self" || recv == "static" else { return nil }
        let name = lex.text(open - 1)
        var fn = -1
        for j in 0..<(lex.count - 2) where lex.toks[j].kind == .ident && lex.text(j) == "function" && lex.toks[j + 1].kind == .ident && lex.text(j + 1) == name && lex.isPunct(j + 2, "(") { fn = j; break }
        guard fn >= 0 else { return nil }
        var b = lex.match[fn + 2] + 1
        while b < lex.count, !lex.isPunct(b, "{"), !lex.isPunct(b, ";") { b += 1 }
        guard b < lex.count, lex.isPunct(b, "{"), lex.match[b] > b else { return nil }
        var arr = -1, j = b + 1
        while j < lex.match[b] {
            let k = lex.toks[j]
            if k.kind == .punct, [40, 91, 123].contains(k.ch), lex.match[j] > j { j = lex.match[j] + 1; continue }
            if k.kind == .ident, lex.text(j) == "return" { arr = lex.isPunct(j + 1, "[") ? j + 1 : -1 }
            j += 1
        }
        guard arr >= 0, lex.match[arr] > arr else { return nil }
        let items = splitArgs((arr + 1, lex.match[arr]))
        guard index < items.count else { return nil }
        for it in items where it.0 < it.1 && (lex.isPunct(it.0, ".") || (it.0..<it.1).contains(where: { lex.isPunct($0, code: PHPTok.fat) })) { return nil }
        return eval(items[index].0, items[index].1, depth: depth + 1)
    }

    func varType(_ name: String, at tok: Int, depth: Int) -> FTType? {
        guard depth < 9 else { return nil }
        let scopes = enclosingFunctions(tok)
        let atLoc = lex.toks[min(tok, lex.count - 1)].loc
        var candidates: [(loc: Int, type: FTType?)] = []
        let asciiLen: Int32 = name.utf8.allSatisfy({ $0 < 128 }) ? Int32(name.utf8.count) : -1     // ASCII names: the token length must match before any String is built
        func scan(from lo: Int, to hi: Int) {
            var i = hi - 1
            while i >= lo {
                let t = lex.toks[i]
                if t.kind != .variable || (asciiLen >= 0 && t.len != asciiLen) { i -= 1; continue }
                if t.kind == .variable, lex.text(i) == name, !(i > 0 && isOp(i - 1)) {
                    if let ld = listDestructure(i, lo: lo) {
                        candidates.append((lex.toks[i].loc, listElementType(ld.rhs, ld.end, index: ld.index, depth: depth + 1)))
                        return
                    }
                    if lex.isPunct(i + 1, "="),!lex.isPunct(i + 2, "="), !lex.isPunct(i + 2, code: PHPTok.fat), !lex.isPunct(i - 1, "=") {
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
                    if i >= 2, lex.toks[i - 1].kind == .ident {
                        // catch (A | \\B $e): the first class names the variable
                        var s = i - 1
                        var first = s
                        while s >= lo, lex.toks[s].kind == .ident || lex.isPunct(s, "|") { if lex.toks[s].kind == .ident { first = s }; s -= 1 }
                        if s >= lo, s > 0, lex.isPunct(s, "("), lex.isIdent(s - 1, "catch"), let f = fp.resolveClass(lex.text(first), in: cur) {
                            candidates.append((lex.toks[i].loc, .instance(f)))
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
                if let dt = docParamType(sc.fn, name, declared: pt.type) {
                    candidates.append((lex.toks[sc.fn].loc, dt))
                } else if !pt.type.isEmpty, let c = cur ?? Optional(FTClass()), let ct = c.classType(pt.type), let f = fp.resolveClass(ct, in: nil) {
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
            let hasVarTag = ns.range(of: "@var", options: .literal, range: rng).location != NSNotFound      // the regex needs a literal `@var`
            let pat = "@var\\s+((?:[^\\s$<]|<[^>]*>)+)\\s+\\$" + NSRegularExpression.escapedPattern(for: String(name.dropFirst())) + "\\b"
            if hasVarTag, let re = NPRe.make(pattern: pat), let m = re.matches(in: ns as String, range: rng).last {
                let raw = ns.substring(with: m.range(at: 1))
                if let t = typeFromDoc(raw, owner: cur, selfType: cur?.fqn ?? "") {
                    // a docblock directly above `$name = ...` overrides that assignment's inferred type
                    var loc = m.range.location
                    let after = NSRange(location: NSMaxRange(m.range), length: min(240, ns.length - NSMaxRange(m.range)))
                    let close = ns.range(of: "*/", options: .literal, range: after)
                    if close.location != NSNotFound {
                        var q = NSMaxRange(close)
                        while q < ns.length, [32, 9, 10, 13].contains(ns.character(at: q)) { q += 1 }
                        if q + name.utf16.count <= ns.length, ns.substring(with: NSRange(location: q, length: name.utf16.count)) == name { loc = q + 1 }
                    }
                    candidates.append((loc, t))
                }
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
        var it = CI.make(m.name, .method, detail: detail, insert: noArgs ? m.name + "()" : CI.callInsert(m.name, params: m.params), snippet: !noArgs, sort: sort + m.name.lowercased(),
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
