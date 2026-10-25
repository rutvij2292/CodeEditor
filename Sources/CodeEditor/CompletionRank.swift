import AppKit

/// Merge / dedupe / score / sort of the candidates delivered by the providers. Pure (no UI), so the controller and the headless
/// completion benchmark (CompletionBench.swift) rank exactly the same way.
///
/// Order of two candidates, first difference wins:
///   1. match class   exact > case-sensitive prefix > case-insensitive prefix > camel-hump / word-boundary > fuzzy subsequence
///                    (words taken from the file are capped at the case-insensitive-prefix class: a real exact / case-sensitive prefix match beats a mere word)
///   2. familiarity   how often the name already occurs in this file (imports, earlier uses) + what was accepted before in this project
///   3. provider tier own members before inherited before magic, project before vendor ... (`priority`, else the leading char of `sortText`)
///   4. match score   shorter / tighter matches first
///   5. sortText, then provider order (stable: the same query always gives the same list)
enum CompletionRanker {
    struct Ranked {
        var item: CompletionItem
        var score: Int
        var order: Int
        var query: String
        var cls = 0
        var boost = 0
        var tier = 0
        var pop = 1000
    }

    struct Output {
        var ranked: [Ranked]
        var anchor: Int
    }

    /// Per-request knowledge about the document / project that the ranking uses (built once per request, not per keystroke).
    struct Context {
        var docCounts: [String: Int] = [:]
        var history: ((String) -> Int)?
        var popularity: [String: Int] = [:]
        static let empty = Context()
    }

    static let maxItems = 300

    private static let keywords: Set<String> = ["this", "self", "static", "function", "return", "foreach", "endforeach", "class", "new", "null", "true", "false", "public",
                                                 "private", "protected", "const", "var", "let", "import", "export", "from", "default", "await", "async", "namespace",
                                                 "abstract", "final", "catch", "throw", "switch", "case", "break", "continue", "while", "echo", "else", "elseif", "endif",
                                                 "typeof", "instanceof", "interface", "extends", "implements", "parent", "array", "string", "void", "undefined", "None",
                                                 "True", "False", "def", "lambda", "pass", "yield", "elif", "isset", "empty", "unset", "list", "match", "fn", "use"]

    // MARK: Document statistics

    /// Occurrence counts of the identifier-like tokens of `ns` (3...60 chars; `$` / `@` / leading `-` stripped), skipping the token under the caret.
    static func docCounts(_ ns: NSString, caret: Int) -> [String: Int] {
        var lo = 0, hi = ns.length
        if hi > 400_000 { lo = max(0, caret - 200_000); hi = min(ns.length, caret + 200_000) }
        let len = hi - lo
        guard len > 0 else { return [:] }
        var buf = [unichar](repeating: 0, count: len)
        ns.getCharacters(&buf, range: NSRange(location: lo, length: len))
        var out: [String: Int] = [:]
        out.reserveCapacity(1024)
        var i = 0
        @inline(__always) func part(_ c: unichar) -> Bool { CompletionLex.isIdent(c) || c == 45 }
        while i < len {
            let c = buf[i]
            guard part(c) || c == 36 || c == 64 else { i += 1; continue }
            var s = i
            while s < len, buf[s] == 36 || buf[s] == 64 || buf[s] == 45 { s += 1 }
            var j = s
            while j < len, part(buf[j]) { j += 1 }
            while j > s, buf[j - 1] == 45 { j -= 1 }
            let n = j - s
            let atCaret = lo + s <= caret && caret <= lo + j
            i = max(j, i + 1)
            if n < 3 || n > 60 || atCaret || (buf[s] >= 48 && buf[s] <= 57) { continue }
            if out.count > 30_000 { continue }
            let w = buf[s..<j].withUnsafeBufferPointer { String(utf16CodeUnits: $0.baseAddress!, count: n) }
            out[w, default: 0] += 1
        }
        return out
    }

    // MARK: Matching

    @inline(__always) private static func lower(_ b: UInt8) -> UInt8 { b >= 65 && b <= 90 ? b + 32 : b }

    /// camel-hump / word-boundary match: every chunk of the query starts at a word start of the candidate (`cff` -> createFromFormat,
    /// `format` -> createFromFormat, `bgr` -> bg-red-500). ASCII only.
    static func hump(_ q: [UInt8], _ t: [UInt8]) -> Bool {
        let n = t.count, m = q.count
        guard m > 0, n >= m else { return false }
        var boundary = [Bool](repeating: false, count: n)
        for i in 0..<n {
            if i == 0 { boundary[i] = true; continue }
            let p = t[i - 1], c = t[i]
            let pu = p >= 65 && p <= 90, cu = c >= 65 && c <= 90
            let pl = p >= 97 && p <= 122
            let pd = p >= 48 && p <= 57, cd = c >= 48 && c <= 57
            if !(pu || pl || pd) { boundary[i] = true }                     // after _ - . \ / : $ space
            else if pl && cu { boundary[i] = true }                          // fooBar
            else if pu && cu, i + 1 < n, t[i + 1] >= 97 && t[i + 1] <= 122 { boundary[i] = true }   // HTMLParser -> P
            else if !pd && cd { boundary[i] = true }
        }
        var budget = 4000
        func go(_ qi: Int, _ from: Int) -> Bool {
            if qi == m { return true }
            var i = from
            while i < n {
                budget -= 1
                if budget < 0 { return false }
                if boundary[i], lower(t[i]) == q[qi] {
                    var k = 0
                    while qi + k < m, i + k < n, lower(t[i + k]) == q[qi + k] { k += 1 }
                    while k >= 1 { if go(qi + k, i + k) { return true }; k -= 1 }
                }
                i += 1
            }
            return false
        }
        return go(0, 0)
    }

    static func tier(_ it: CompletionItem) -> Int {
        if it.priority >= 0 { return it.priority }
        if it.kind == .text { return 900 }
        guard let s = it.sortText?.utf8, let c = s.first else { return 50 }
        if c >= 48 && c <= 57 {
            var v = Int(c - 48) * 10
            if s.count > 1 { let d = s[s.index(after: s.startIndex)]; if d >= 48 && d <= 57 { v += Int(d - 48) } }
            return v
        }
        if c == 126 { return 900 }
        if c >= 97 && c <= 122 { return 100 + Int(c - 97) }
        return 60
    }

    struct Q { var q: String; var ql: String; var qb: [UInt8]; var chars: [Character]; var ascii: Bool }

    /// (class, score) of an item for a query, nil = no match.
    static func match(_ item: CompletionItem, _ q: Q) -> (cls: Int, score: Int)? {
        if q.q.isEmpty { return (0, 0) }
        let t = item.filterText ?? item.label
        if !q.qb.isEmpty, !CompletionLex.subsequence(q.qb, in: t) { return nil }
        let pen = min(t.utf16.count, 60) / 4
        let isText = item.kind == .text
        if t == q.q { return isText ? nil : (5, 1000) }          // the word being typed is not a suggestion
        if t.hasPrefix(q.q) { return isText ? (3, 450 - pen) : (4, 900 - pen) }
        let tl = t.lowercased()
        if tl == q.ql { return isText ? (3, 440 - pen) : (3, 950) }
        if tl.hasPrefix(q.ql) { return isText ? (3, 430 - pen) : (3, 800 - pen) }
        if q.ascii, q.qb.count >= 2, t.utf8.count <= 80, hump(q.qb, Array(t.utf8)) {
            let f = Fuzzy.score(q.chars, in: t) ?? 0
            return (2, 100 + max(0, min(f, 500)) / 2 - pen)
        }
        guard let f = Fuzzy.score(q.chars, in: t) else { return nil }
        return (1, 100 + max(0, min(f, 500)) / 2 - pen)
    }

    private static func strip(_ s: String) -> String {
        guard let f = s.utf8.first, f == 36 || f == 64 || f == 58 || f == 45 else { return s }
        var t = Substring(s)
        while let c = t.utf8.first, c == 36 || c == 64 || c == 58 || c == 45 { t = t.dropFirst() }
        return String(t)
    }

    static func familiarity(_ item: CompletionItem, _ ctx: Context) -> Int {
        var lvl = 0
        let key = strip(item.label)
        if let n = ctx.docCounts[key] { lvl = n >= 4 ? 3 : (n >= 2 ? 2 : 1) }
        if let h = ctx.history { lvl += h(key) }
        return min(lvl, 4)
    }

    // MARK: Rank

    static func rank(results: [(items: [CompletionItem], incomplete: Bool)?], text ns: NSString, caret rawCaret: Int, anchor: Int,
                     context: Context = .empty) -> Output {
        let caret = min(rawCaret, ns.length)
        let defaultStart = CompletionLex.runStart(ns, caret, CompletionLex.isIdent)
        var cache: [Int: Q] = [:]
        var out: [Ranked] = []
        var seen: [String: Int] = [:]
        var order = 0
        var minStart = defaultStart
        for res in results {
            guard let res else { continue }
            for item in res.items {
                let start = item.replaceRange?.location ?? defaultStart
                guard start >= 0, start <= caret else { continue }
                let q: Q
                if let c = cache[start] { q = c } else {
                    let s = ns.substring(with: NSRange(location: start, length: caret - start))
                    let ql = s.lowercased().replacingOccurrences(of: " ", with: "")
                    let ascii = ql.utf8.allSatisfy { $0 < 128 }
                    q = Q(q: s, ql: ql, qb: ascii ? Array(ql.utf8) : [], chars: Array(ql), ascii: ascii)
                    cache[start] = q
                }
                guard let m = match(item, q) else { continue }
                minStart = min(minStart, start)
                let key = item.label + "\u{1}" + item.kind.rawValue
                var r = Ranked(item: item, score: m.score, order: order, query: q.q, cls: m.cls)
                r.tier = tier(item)
                r.boost = familiarity(item, context)
                if !context.popularity.isEmpty { r.pop = context.popularity[item.label] ?? context.popularity[strip(item.label)] ?? 1000 }
                if let idx = seen[key] {
                    let o = out[idx]
                    // the same symbol from two providers: keep the better tier / richer one (later provider wins a tie)
                    if (r.cls, -r.tier, r.score) >= (o.cls, -o.tier, o.score) { r.order = o.order; out[idx] = r }
                    continue
                }
                seen[key] = out.count
                out.append(r)
                order += 1
            }
        }
        // words of the file add nothing next to a real symbol of the same name; and after `->` / `::` / `.` they are only a fallback
        var nonText = Set<String>()
        for r in out where r.item.kind != .text { nonText.insert(r.item.label) }
        if !nonText.isEmpty { out.removeAll { $0.item.kind == .text && nonText.contains($0.item.label) } }
        // after `->` / `::` / `.` a language keyword from the file is never the member
        if isMemberContext(ns, defaultStart) { out.removeAll { $0.item.kind == .text && keywords.contains($0.item.label) } }
        out.sort { a, b in
            if a.cls != b.cls { return a.cls > b.cls }
            if a.boost != b.boost { return a.boost > b.boost }
            if a.tier != b.tier { return a.tier < b.tier }
            if a.pop != b.pop { return a.pop < b.pop }
            if a.score != b.score { return a.score > b.score }
            let sa = a.item.sortText ?? a.item.label.lowercased(), sb = b.item.sortText ?? b.item.label.lowercased()
            if sa != sb { return sa < sb }
            return a.order < b.order
        }
        if out.count > maxItems { out.removeLast(out.count - maxItems) }
        return Output(ranked: out, anchor: min(anchor, minStart))
    }

    /// The prefix sits right after a member-access operator (`->`, `?->`, `::`, `.` after an identifier or `)` / `]`).
    static func isMemberContext(_ ns: NSString, _ start: Int) -> Bool {
        guard start >= 1 else { return false }
        let c = ns.character(at: start - 1)
        if c == 62, start >= 2, ns.character(at: start - 2) == 45 { return true }                         // ->
        if c == 58, start >= 2, ns.character(at: start - 2) == 58 { return true }                         // ::
        if c == 46, start >= 2 {                                                                          // .
            let p = ns.character(at: start - 2)
            return CompletionLex.isIdent(p) || p == 41 || p == 93
        }
        return false
    }
}
