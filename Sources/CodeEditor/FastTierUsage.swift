import Foundation

// Usage statistics for the string completions (config('..'), route('..'), view('..'), __('..'), env('..'), where('column'), with('relation'),
// session / cache keys, Gate abilities, middleware names): how often the project itself uses each key, so the big lists rank "what this
// codebase reaches for" first instead of alphabetically. One lazy scan of the project's own sources (never vendor), ONE dictionary of
// at most `maxEntries` keys (about 0.5 MB), dropped on memory trim and rebuilt on demand, no timers, no polling.
//
// Ranking input for one request = project counts MINUS the current file's saved contribution PLUS the live buffer's contribution
// (so the call being typed never votes for itself and a key used earlier in this very file is a strong signal), plus a cheap
// proximity bonus (key segments that match the module / controller / view names of the current file).

enum FUsageKind: String { case config, route, view, lang, env, col, rel, session, cache, gate, middleware, member }

struct FUsageTable {
    var counts: [String: UInt16] = [:]
    var builtAt = Date()
    var approxBytes: Int { counts.count * 96 }
    @inline(__always) static func key(_ k: FUsageKind, _ name: String) -> String { k.rawValue + "\u{1}" + name }
    func count(_ k: FUsageKind, _ name: String) -> Int { Int(counts[Self.key(k, name)] ?? 0) }
}

enum FUsage {
    /// A/B switch for the benchmark: CE_COMPLETION_SMART_OFF=1 turns usage ranking and expected-type ranking off in the same binary.
    static let off = AppEnv.value("CE_COMPLETION_SMART_OFF") != nil
    private static let knobs = AppEnv.value("CE_USAGE_KNOBS") ?? ""
    static let proxCap = Int(knobs.components(separatedBy: ",").first(where: { $0.hasPrefix("cap=") })?.dropFirst(4) ?? "6") ?? 6
    static let noLastPop = knobs.contains("nolast")
    static let noBranch = knobs.contains("nobranch")
    static let proxWeight = Int(knobs.components(separatedBy: ",").first(where: { $0.hasPrefix("pw=") })?.dropFirst(3) ?? "2") ?? 2
    static let maxEntries = 7000
    static let maxFiles = 6000
    static let maxFileBytes = 300_000
    /// A table older than this is rebuilt on the next request after a file change notification (not on a timer).
    static let staleAfter: TimeInterval = 600

    private static let skipDirs: Set<String> = ["vendor", "node_modules", "storage", "public", "build", "dist", "cache", "bootstrap", "tests", "test", "stubs"]
    private static let scanExts: [String] = [".php", ".vue", ".js", ".ts", ".jsx", ".tsx"]
    private static let roots = ["app", "routes", "resources", "Modules", "src", "lang"]

    private static let rx: NSRegularExpression = {
        let cols = "where|orWhere|orderBy|orderByDesc|pluck|whereIn|whereNull|whereNotNull|select|value|groupBy|latest|oldest|whereBetween|whereDate|whereNotIn|orWhereIn|addSelect"
        let rels = "with|whereHas|has|withCount|load|doesntHave|orWhereHas|loadMissing|whereDoesntHave"
        let p = "(?:(?<![\\w$>:])(config|route|to_route|view|__|trans|trans_choice|env|session|cache)"
            + "|\\b(Config|Lang|View|URL|Redirect|Cache|Session|Gate|Route)::(\\w+)"
            + "|->(route|routeIs|view|can|cannot|authorize|middleware|\(cols)|\(rels))"
            + "|@(extends|include|includeIf|component|lang|choice|can|cannot|canany))"
            + "\\s*\\(\\s*['\"]([^'\"\\\\\\n]{1,100})['\"]"
        return try! NSRegularExpression(pattern: p)
    }()

    /// `->name` / `::name` (methods and properties) in PHP sources: how much the project talks to each member name.
    private static let memberRx = try! NSRegularExpression(pattern: "(?:->|::)([A-Za-z_]\\w{2,40})")
    static let maxMemberEntries = 2500

    private static let colSet: Set<String> = Set("where|orWhere|orderBy|orderByDesc|pluck|whereIn|whereNull|whereNotNull|select|value|groupBy|latest|oldest|whereBetween|whereDate|whereNotIn|orWhereIn|addSelect".split(separator: "|").map(String.init))
    private static let relSet: Set<String> = Set("with|whereHas|has|withCount|load|doesntHave|orWhereHas|loadMissing|whereDoesntHave".split(separator: "|").map(String.init))

    private static func kind(helper: String?, facade: String?, method: String?, arrow: String?, directive: String?) -> FUsageKind? {
        if let h = helper {
            switch h {
            case "config": return .config
            case "route", "to_route": return .route
            case "view": return .view
            case "__", "trans", "trans_choice": return .lang
            case "env": return .env
            case "session": return .session
            default: return .cache
            }
        }
        if let f = facade, let m = method {
            switch f {
            case "Config": return .config
            case "Lang": return .lang
            case "View": return .view
            case "URL", "Redirect": return m == "route" ? .route : nil
            case "Route": return m == "has" || m == "is" || m == "currentRouteNamed" ? .route : nil
            case "Cache": return .cache
            case "Session": return .session
            case "Gate": return .gate
            default: return nil
            }
        }
        if let a = arrow {
            if a == "route" || a == "routeIs" { return .route }
            if a == "view" { return .view }
            if a == "can" || a == "cannot" || a == "authorize" { return .gate }
            if a == "middleware" { return .middleware }
            if colSet.contains(a) { return .col }
            if relSet.contains(a) { return .rel }
            return nil
        }
        if let d = directive {
            switch d {
            case "lang", "choice": return .lang
            case "can", "cannot", "canany": return .gate
            default: return .view
            }
        }
        return nil
    }

    /// Occurrences of every recognised key in `text` (per-key cap 20 so a generated file cannot drown the rest).
    static func scan(_ text: NSString, into out: inout [String: UInt16], members: Bool = false) {
        guard text.length > 0, text.length < maxFileBytes * 2 else { return }
        if members {
            memberRx.enumerateMatches(in: text as String, options: [], range: NSRange(location: 0, length: text.length)) { m, _, _ in
                guard let m else { return }
                let kk = FUsageTable.key(.member, text.substring(with: m.range(at: 1)))
                let v = out[kk] ?? 0
                if v < 20 { out[kk] = v + 1 }
            }
        }
        rx.enumerateMatches(in: text as String, options: [], range: NSRange(location: 0, length: text.length)) { m, _, _ in
            guard let m else { return }
            func g(_ i: Int) -> String? { let r = m.range(at: i); return r.location == NSNotFound ? nil : text.substring(with: r) }
            guard var key = g(6), let k = kind(helper: g(1), facade: g(2), method: g(3), arrow: g(4), directive: g(5)) else { return }
            if k == .middleware { key = String(key.split(separator: ":").first ?? Substring(key)) }
            if k == .col, key.hasSuffix(".") || key.contains(" ") { return }
            let kk = FUsageTable.key(k, key)
            let v = out[kk] ?? 0
            if v < 20 { out[kk] = v + 1 }
        }
    }

    private static func walk(_ dir: String, depth: Int, into out: inout [String]) {
        guard depth < 9, out.count < maxFiles else { return }
        for e in FastProject.readEntries(dir, fileSuffix: []) {
            if e.isDir {
                if skipDirs.contains(e.name) || e.name == "node_modules" { continue }
                walk(dir + "/" + e.name, depth: depth + 1, into: &out)
            } else if scanExts.contains(where: { e.name.hasSuffix($0) }), !e.name.hasSuffix(".min.js"), !e.name.hasSuffix(".d.ts") {
                out.append(dir + "/" + e.name)
                if out.count >= maxFiles { return }
            }
        }
    }

    /// Scans the project (on the project's queue; several threads, power saver aware via parallelMap).
    static func build(root: String) -> FUsageTable {
        var files: [String] = []
        for r in roots where LaravelFS.isDir(root + "/" + r) { walk(root + "/" + r, depth: 0, into: &files) }
        let parts = FastProject.parallelMap(chunk(files, 24)) { group -> [String: UInt16] in
            var d: [String: UInt16] = [:]
            for f in group {
                guard let a = try? FileManager.default.attributesOfItem(atPath: f), (a[.size] as? Int ?? 0) < maxFileBytes,
                      let t = try? NSString(contentsOfFile: f, encoding: String.Encoding.utf8.rawValue) else { continue }
                scan(t, into: &d, members: f.hasSuffix(".php"))
            }
            return d
        }
        var all: [String: UInt16] = [:]
        for p in parts { for (k, v) in p { all[k] = UInt16(min(Int(all[k] ?? 0) + Int(v), 60_000)) } }
        if all.count > maxEntries {
            // keep the most used; keys used once are the first to go (they carry the least signal). Member names have their own cap.
            let sorted = all.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            var keep: [(key: String, value: UInt16)] = []
            var members = 0
            let memberPrefix = FUsageKind.member.rawValue + "\u{1}"
            for e in sorted {
                if e.key.hasPrefix(memberPrefix) { if members >= maxMemberEntries { continue }; members += 1 }
                keep.append(e)
                if keep.count >= maxEntries { break }
            }
            all = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        return FUsageTable(counts: all)
    }

    private static func chunk(_ a: [String], _ n: Int) -> [[String]] {
        stride(from: 0, to: a.count, by: n).map { Array(a[$0..<min($0 + n, a.count)]) }
    }

    // MARK: Per request ranking

    /// Words of the current file's path that name a feature: `Modules/Items/.../ProductReportController.php` -> items, product, report.
    static func fileTokens(_ url: URL) -> [String] {
        var out: [String] = []
        let comps = url.deletingPathExtension().pathComponents.suffix(6)
        let skip: Set<String> = ["app", "http", "controllers", "controller", "resources", "views", "livewire", "models", "model", "src", "index", "blade", "php", "routes", "web",
                                 "api", "modules", "users", "components", "pages", "show", "create", "edit", "form", "list", "lang", "config", "services", "service"]
        for c in comps {
            var word = "", words: [String] = []
            for ch in c {
                if ch.isUppercase, !word.isEmpty, word.last?.isLowercase == true { words.append(word); word = "" }
                if ch.isLetter || ch.isNumber { word.append(ch) } else if !word.isEmpty { words.append(word); word = "" }
            }
            if !word.isEmpty { words.append(word) }
            for w in words {
                var l = w.lowercased()
                if l.count < 4 || skip.contains(l) { continue }
                if l.hasSuffix("ies") { l = String(l.dropLast(3)) + "y" } else if l.hasSuffix("s") { l = String(l.dropLast()) }
                out.append(l)
            }
        }
        return Array(Set(out))
    }

    private static func singular(_ s: Substring) -> String {
        var l = s.lowercased()
        if l.hasSuffix("ies") { l = String(l.dropLast(3)) + "y" } else if l.hasSuffix("s"), l.count > 3 { l = String(l.dropLast()) }
        return l
    }

    /// How strongly a key belongs to the current file: every word of the key (split at . : - _ /) that is also a word of the file's path
    /// counts 2, 3 in the leading segment (the module / namespace of the key). Capped at 8.
    static func proximity(_ key: String, tokens: [String]) -> Int {
        guard !tokens.isEmpty else { return 0 }
        var score = 0
        var seg = 0
        var start = key.startIndex
        var i = key.startIndex
        func word(_ r: Range<String.Index>) {
            let w = key[r]
            guard w.count >= 4 else { return }
            if tokens.contains(singular(w)) { score += seg == 0 ? 3 : 2 }
        }
        while i < key.endIndex {
            let c = key[i]
            if c == "." || c == ":" || c == "-" || c == "_" || c == "/" {
                if start < i { word(start..<i) }
                if c == "." || c == ":" { seg += 1 }
                start = key.index(after: i)
            }
            i = key.index(after: i)
        }
        if start < key.endIndex { word(start..<key.endIndex) }
        return min(score, proxCap)
    }

    /// Provider tier (`CompletionItem.priority`, lower = earlier) for a key used `n` times with proximity `prox` (+ sibling bonus).
    static func tier(count n: Int, prox: Int) -> Int {
        let score = 3 * log2(Double(1 + n)) + Double(proxWeight * prox)
        return max(0, 100 - Int(score * 3))
    }

    /// Per request view of the table: project counts without the current file's saved contribution, plus the live buffer's.
    struct View {
        var table: FUsageTable
        var minus: [String: UInt16] = [:]
        var plus: [String: UInt16] = [:]
        var tokens: [String] = []
        /// "everything but the last dotted segment" of the keys this buffer already uses, per kind: `config('a.b.x')` makes `a.b.*` likely.
        var siblings: [FUsageKind: Set<String>] = [:]

        init(table: FUsageTable, file: URL, live: NSString) {
            self.table = table
            tokens = FUsage.fileTokens(file)
            if let t = try? NSString(contentsOfFile: file.path, encoding: String.Encoding.utf8.rawValue) { FUsage.scan(t, into: &minus, members: file.pathExtension == "php") }
            FUsage.scan(live, into: &plus, members: file.pathExtension == "php")
            for kk in plus.keys {
                let parts = kk.split(separator: "\u{1}", maxSplits: 1)
                guard parts.count == 2, let k = FUsageKind(rawValue: String(parts[0])), let dot = parts[1].lastIndex(of: ".") else { continue }
                siblings[k, default: []].insert(String(parts[1][..<dot]))
            }
        }

        func count(_ k: FUsageKind, _ name: String) -> Int {
            let kk = FUsageTable.key(k, name)
            return max(0, Int(table.counts[kk] ?? 0) - Int(minus[kk] ?? 0)) + Int(plus[kk] ?? 0) * 2
        }

        func siblingBonus(_ k: FUsageKind, _ name: String) -> Int {
            guard let set = siblings[k], !set.isEmpty else { return 0 }
            var n = name
            var bonus = 0
            while let dot = n.lastIndex(of: ".") {
                n = String(n[..<dot])
                if set.contains(n) { bonus = max(bonus, n.contains(".") ? 4 : 2) }
            }
            return bonus
        }

        /// Sets `priority` of every item (label = key) of this kind. Items of keys nobody uses keep a neutral tier below every used one.
        /// Dotted kinds (config / lang / route) demote unused branch nodes (`analytics` when `analytics.x` exists: rarely the intended key);
        /// the last segment's popularity (`.index` vs `.restore`) breaks ties between otherwise unused keys.
        func apply(_ items: inout [CompletionItem], kind k: FUsageKind, key: (CompletionItem) -> String = { $0.label }, proximity useProx: Bool = true) {
            let dotted = k == .config || k == .lang || k == .route
            var branches = Set<String>()
            var lastPop: [Substring: Int] = [:]
            if dotted {
                for it in items {
                    let name = key(it)
                    var n = Substring(name)
                    while let dot = n.lastIndex(of: ".") { n = n[..<dot]; if !branches.insert(String(n)).inserted { break } }
                    if let dot = name.lastIndex(of: ".") { lastPop[name[name.index(after: dot)...], default: 0] += 1 + count(k, name) }
                }
            }
            for i in items.indices {
                let name = key(items[i])
                let c = count(k, name)
                let prox = (useProx ? FUsage.proximity(name, tokens: tokens) : 0) + siblingBonus(k, name)
                var t = FUsage.tier(count: c, prox: prox)
                if dotted {
                    if c == 0, !FUsage.noBranch, branches.contains(name) { t += 12 }
                    if !FUsage.noLastPop, let dot = name.lastIndex(of: "."), let p = lastPop[name[name.index(after: dot)...]] { t = max(0, t - Int(log2(Double(1 + p)))) }
                }
                items[i].priority = t
            }
        }
    }
}
