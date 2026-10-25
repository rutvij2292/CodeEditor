import AppKit

/// Headless completion-quality harness.
///
///   CE_SELFTEST=1 CE_COMPLETION_BENCH=<project>[,<project>...] [CE_COMPLETION_BENCH_N=40] [CE_COMPLETION_BENCH_ONLY=php,js]
///       [CE_COMPLETION_BENCH_OUT=<json>] [CE_COMPLETION_BENCH_MISSES=3] .build/release/CodeEditor
///
/// Takes real files of a (read-only) project, truncates them right before a sampled token (member access, static call, `new`, `use`,
/// Eloquent column / route / view / config strings, blade directives and components, HTML attributes, CSS properties, Tailwind
/// classes, JS members / imports, Python attributes / imports ...) keeping 0 or 2 typed characters of that token, then runs the same
/// providers + merge + ranking the editor uses (CompletionRegistry providers, CompletionRanker) and records whether the intended
/// token is offered, at which rank, how long it took and how noisy the list is. Prints a table (weakest category first), writes JSON.
enum CompletionBench {
    struct Sample {
        var cat: String
        var file: String
        var loc: Int            // UTF-16 offset of the first character of the expected token
        var prefix: Int         // characters of it already typed
        var expected: String
    }

    struct Result {
        var sample: Sample
        var rank: Int?          // 1-based, nil = absent
        var count: Int
        var dupLabels: Int
        var textTop5: Int
        var totalMs: Double
        var syncMs: Double
        var rankMs: Double
        var top: [String]
    }

    // MARK: - Category generators

    typealias Gen = (_ text: NSString) -> [(loc: Int, expected: String)]
    struct Cat {
        var name: String
        var kinds: Set<String>          // "php" "blade" "vue" "html" "css" "js" "py"
        var prefixes: [Int]
        var gen: Gen
    }

    private static func re(_ p: String, group: Int = 1, _ opts: NSRegularExpression.Options = [.anchorsMatchLines], minLen: Int = 1) -> Gen {
        let rx = try! NSRegularExpression(pattern: p, options: opts)
        return { t in
            var out: [(Int, String)] = []
            rx.enumerateMatches(in: t as String, range: NSRange(location: 0, length: t.length)) { m, _, _ in
                guard let m, m.numberOfRanges > group else { return }
                let r = m.range(at: group)
                guard r.location != NSNotFound, r.length >= minLen else { return }
                out.append((r.location, t.substring(with: r)))
            }
            return out
        }
    }

    /// Identifiers (with `lead` chars before the name) whose name already appeared earlier in the file: "a local that is in scope".
    private static func reused(_ declPattern: String, usagePrefix: String, minLen: Int = 5) -> Gen {
        let decl = try! NSRegularExpression(pattern: declPattern, options: [.anchorsMatchLines])
        return { t in
            var firstDecl: [String: Int] = [:]
            decl.enumerateMatches(in: t as String, range: NSRange(location: 0, length: t.length)) { m, _, _ in
                guard let m, m.numberOfRanges > 1 else { return }
                guard let r = (1..<m.numberOfRanges).map({ m.range(at: $0) }).first(where: { $0.location != NSNotFound }) else { return }
                let n = t.substring(with: r)
                if n.count >= minLen, firstDecl[n] == nil { firstDecl[n] = r.location }
            }
            var out: [(Int, String)] = []
            var used = Set<String>()
            for (name, at) in firstDecl.sorted(by: { $0.value < $1.value }) {
                var from = at + name.utf16.count
                var r = t.range(of: usagePrefix + name, options: [], range: NSRange(location: from, length: t.length - from))
                while r.location != NSNotFound {
                    let end = r.location + r.length
                    let nextOK = end >= t.length || !CompletionLex.isIdent(t.character(at: end))
                    let prevOK = r.location == 0 || !CompletionLex.isIdent(t.character(at: r.location - 1))
                    if nextOK, prevOK, r.location - at > 40 {
                        if used.insert(name).inserted { out.append((r.location + usagePrefix.utf16.count, name)) }
                        break
                    }
                    from = end
                    r = t.range(of: usagePrefix + name, options: [], range: NSRange(location: from, length: t.length - from))
                }
            }
            return out.sorted { $0.0 < $1.0 }
        }
    }

    private static func classTokens(_ t: NSString) -> [(loc: Int, expected: String)] {
        let rx = try! NSRegularExpression(pattern: "\\bclass=\"([^\"{}$<>]*)\"")
        let tok = try! NSRegularExpression(pattern: "(?<![\\w:\\-\\[./])([a-z][a-z0-9]*(?:-[a-z0-9]+(?:\\.[0-9]+)?|/[0-9]+)+)(?![\\w\\-:\\[])")
        var out: [(Int, String)] = []
        rx.enumerateMatches(in: t as String, range: NSRange(location: 0, length: t.length)) { m, _, _ in
            guard let m else { return }
            let r = m.range(at: 1)
            tok.enumerateMatches(in: t as String, range: r) { tm, _, _ in
                guard let tm else { return }
                let tr = tm.range(at: 1)
                // only classes that follow at least one other class (a populated list), as in real editing
                if tr.location > r.location { out.append((tr.location, t.substring(with: tr))) }
            }
        }
        return out
    }

    static let categories: [Cat] = {
        let phpKinds: Set<String> = ["php"]
        var c: [Cat] = []
        func add(_ n: String, _ k: Set<String>, p: [Int] = [2], _ g: @escaping Gen) { c.append(Cat(name: n, kinds: k, prefixes: p, gen: g)) }
        // PHP
        add("php.this", phpKinds, p: [0, 2], re("\\$this->([A-Za-z_]\\w*)"))
        add("php.member", phpKinds, p: [0, 2], re("\\$(?!this\\b)[A-Za-z_]\\w*->([A-Za-z_]\\w*)"))
        add("php.chain", phpKinds, p: [0, 2], re("\\)->([A-Za-z_]\\w*)"))
        add("php.static", phpKinds, p: [0, 2], re("\\b[A-Z]\\w*::(?!class\\b)([A-Za-z_]\\w*)"))
        add("php.new", phpKinds, re("\\bnew\\s+([A-Z]\\w*)"))
        add("php.use", phpKinds, re("^use\\s+[\\w\\\\]+\\\\(\\w+);"))
        add("php.var", phpKinds, reused("\\$([A-Za-z_]\\w*)\\s*=[^=>]", usagePrefix: "$", minLen: 4))
        add("php.func", phpKinds, re("(?<![>:\\w$\\\\])((?:array|str|preg|json|mb)_\\w+|in_array|implode|explode|number_format|is_[a-z]+)\\(", minLen: 4))
        add("php.namedarg", phpKinds, re("[(,]\\s*([a-z][A-Za-z]\\w*):\\s(?!:)", minLen: 3))
        add("php.column", phpKinds, p: [0, 2], re("->(?:where|orderBy|pluck|whereIn|select|value|whereNull|whereNotNull)\\(\\s*'(\\w+)'", minLen: 3))
        add("php.route", phpKinds, p: [0, 2], re("\\broute\\(\\s*'([\\w.\\-]+)'", minLen: 4))
        add("php.view", phpKinds, p: [0, 2], re("\\bview\\(\\s*'([\\w.\\-]+)'", minLen: 4))
        add("php.config", phpKinds, p: [0, 2], re("\\bconfig\\(\\s*'([\\w.\\-]+)'", minLen: 4))
        add("php.rule", phpKinds, p: [0, 2], re("'[\\w.*]+'\\s*=>\\s*'(required|nullable|string|integer|numeric|email|exists|unique|array|boolean|date|sometimes|confirmed)\\b", minLen: 4))
        // Blade
        let blade: Set<String> = ["blade"]
        add("blade.directive", blade, p: [0, 2], re("(?:^|\\s)@([a-z]\\w{2,})\\b"))
        add("blade.component", blade, p: [0, 2], re("<x-([\\w.\\-]+)", minLen: 3))
        add("blade.var", blade, re("\\{\\{\\s*\\$([A-Za-z_]\\w*)", minLen: 3))
        add("blade.viewname", blade, re("@(?:extends|include|includeIf)\\(\\s*'([\\w.\\-]+)'", minLen: 4))
        // HTML (blade / vue / html)
        let htmlKinds: Set<String> = ["blade", "html", "vue"]
        add("html.tag", htmlKinds, p: [0, 2], re("<([a-z][a-z0-9]*)(?=[\\s>])", minLen: 2))
        add("html.attr", htmlKinds, p: [0, 2], re("<[a-z][\\w-]*(?:\\s+[\\w\\-:@.]+=\"[^\"]*\")*\\s+([a-z][\\w\\-]*)=\"", minLen: 3))
        add("html.type", htmlKinds, p: [0, 2], re("<input[^>]*\\stype=\"([a-z]+)\"", minLen: 3))
        // CSS
        let cssKinds: Set<String> = ["css"]
        add("css.prop", cssKinds, re("^[ \\t]+([a-z][a-z\\-]+):\\s", minLen: 4))
        add("css.value", cssKinds, p: [0, 2], re("^[ \\t]+(?:display|position|overflow|cursor|text-align|flex-direction|justify-content|align-items|font-weight|text-transform|white-space|visibility|float|box-sizing):\\s*([a-z][a-z\\-]+)\\s*;", minLen: 3))
        add("css.atrule", cssKinds, re("^\\s*@([a-z\\-]+)\\b", minLen: 4))
        // Tailwind
        add("tw.class", htmlKinds, p: [3], { classTokens($0) })
        // JS / TS
        let js: Set<String> = ["js", "vue-script"]
        add("js.member", js, p: [0, 2], re("(?<![\\w.$)\\]\"'`/])[a-z_$][\\w$]*\\.([A-Za-z_$][\\w$]*)"))
        add("js.this", js, p: [0, 2], re("\\bthis\\.([A-Za-z_$][\\w$]*)"))
        add("js.builtin", js, p: [0, 2], re("\\b(?:console|document|window|Math|JSON|Object|Array|Promise)\\.([A-Za-z_]\\w*)", minLen: 3))
        add("js.ident", js, reused("\\b(?:const|let|var|function)\\s+([A-Za-z_$][\\w$]*)", usagePrefix: ""))
        add("js.importpath", js, re("from\\s+['\"]\\.{1,2}/(?:[\\w.\\-]+/)*([\\w.\\-]+)['\"]", minLen: 4))
        add("js.importname", js, re("^import\\s+\\{[^}]*?\\b([A-Z]\\w{3,})\\b[^}]*\\}\\s+from", minLen: 4))
        // Python
        let py: Set<String> = ["py"]
        add("py.self", py, p: [0, 2], re("\\bself\\.([A-Za-z_]\\w*)"))
        add("py.member", py, p: [0, 2], re("(?<![\\w.])(?!self\\b)[a-z_]\\w*\\.([A-Za-z_]\\w*)\\b(?!\\s*\\()", minLen: 3))
        add("py.call", py, p: [0, 2], re("(?<![\\w.])(?!self\\b)[a-z_]\\w*\\.([A-Za-z_]\\w*)\\(", minLen: 3))
        add("py.import", py, re("^from\\s+[\\w.]+\\s+import\\s+(\\w+)", minLen: 3))
        add("py.module", py, re("^(?:from|import)\\s+(?:[\\w]+\\.)*(\\w+)", minLen: 3))
        add("py.ident", py, reused("^\\s*(?:def|class|async def)\\s+([A-Za-z_]\\w*)|^([a-z_]\\w{3,})\\s*=[^=]", usagePrefix: ""))
        return c
    }()

    // MARK: - Files

    private static let skipDirs: Set<String> = ["vendor", "node_modules", "storage", "public", ".git", "dist", "build", "__pycache__", ".venv", "venv", "cache", ".idea",
                                                "graphify-out", "docs", "document", ".next", "coverage"]

    private static func files(in root: String) -> [String] {
        var out: [String] = []
        guard let en = FileManager.default.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { return [] }
        for case let url as URL in en {
            let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if v?.isDirectory == true { if skipDirs.contains(url.lastPathComponent) { en.skipDescendants() }; continue }
            let ext = url.pathExtension.lowercased()
            guard ["php", "js", "mjs", "ts", "tsx", "jsx", "vue", "html", "css", "scss", "py"].contains(ext), (v?.fileSize ?? 0) < 250_000 else { continue }
            if url.lastPathComponent.hasSuffix(".min.js") || url.lastPathComponent.hasSuffix(".d.ts") { continue }
            out.append(url.path)
        }
        return out.sorted()
    }

    private static func kinds(of path: String) -> [String] {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "php": return path.hasSuffix(".blade.php") ? ["blade", "html"] : ["php"]
        case "vue": return ["vue", "html", "vue-script"]
        case "html": return ["html"]
        case "css", "scss": return ["css"]
        case "js", "mjs", "ts", "tsx", "jsx": return ["js"]
        case "py": return ["py"]
        default: return []
        }
    }

    /// Script block of a .vue file (so JS categories do not fire in the template).
    private static func region(_ t: NSString, tag: String) -> NSRange? {
        let o = t.range(of: "<\(tag)")
        guard o.location != NSNotFound else { return nil }
        let gt = t.range(of: ">", options: [], range: NSRange(location: o.location, length: t.length - o.location))
        guard gt.location != NSNotFound else { return nil }
        let c = t.range(of: "</\(tag)>", options: [], range: NSRange(location: gt.location, length: t.length - gt.location))
        guard c.location != NSNotFound else { return nil }
        return NSRange(location: gt.location + 1, length: c.location - gt.location - 1)
    }

    /// Samples on comment lines (docblocks, commented-out code) say nothing about completion.
    private static func inComment(_ t: NSString, _ loc: Int) -> Bool {
        let lr = t.lineRange(for: NSRange(location: min(loc, max(0, t.length - 1)), length: 0))
        var i = lr.location
        while i < loc, t.character(at: i) == 32 || t.character(at: i) == 9 { i += 1 }
        guard i < t.length else { return false }
        let c = t.character(at: i), d = i + 1 < t.length ? t.character(at: i + 1) : 0
        if c == 35 { return true }                                     // # (php / python comment; css ids never start a declaration line)
        if c == 42 { return true }                                     // * (docblock body)
        if c == 47, d == 47 || d == 42 { return true }                 // // and /*
        if c == 123, d == 123, i + 2 < t.length, t.character(at: i + 2) == 45 { return true }   // {{--
        if c == 60, d == 33 { return true }                            // <!--
        return false
    }

    private static func read(_ path: String) -> NSString? { try? NSString(contentsOfFile: path, encoding: String.Encoding.utf8.rawValue) }

    // MARK: - Sampling

    private static func collect(root: String, only: Set<String>, perCat: Int) -> [Sample] {
        let all = files(in: root)
        var pool: [String: [(file: String, loc: Int, exp: String)]] = [:]
        for f in all {
            guard let t = read(f) else { continue }
            let ks = Set(kinds(of: f))
            for cat in categories where !cat.kinds.isDisjoint(with: ks) {
                if !only.isEmpty, !only.contains(where: { cat.name.hasPrefix($0) }) { continue }
                var found = cat.gen(t)
                if cat.kinds.contains("vue-script"), f.hasSuffix(".vue") {
                    guard let r = region(t, tag: "script") else { continue }
                    found = found.filter { NSLocationInRange($0.loc, r) }
                } else if f.hasSuffix(".vue"), cat.kinds.contains("html"), !cat.kinds.contains("vue-script") {
                    if let r = region(t, tag: "template") { found = found.filter { NSLocationInRange($0.loc, r) } }
                } else if cat.name.hasPrefix("css."), !f.hasSuffix(".css"), !f.hasSuffix(".scss") { continue }
                found = found.filter { !inComment(t, $0.loc) }
                // at most 3 per file per category: a spread over many files beats many samples of one file
                let step = max(1, found.count / 3)
                for (i, m) in found.enumerated() where i % step == 0 { pool[cat.name, default: []].append((f, m.loc, m.expected)) }
            }
        }
        var out: [Sample] = []
        for cat in categories {
            let p = pool[cat.name] ?? []
            guard !p.isEmpty else { continue }
            let stride = max(1, p.count / perCat)
            for (i, m) in p.enumerated() where i % stride == 0 && i / stride < perCat {
                for pre in cat.prefixes where m.exp.utf16.count > pre || pre == 0 {
                    out.append(Sample(cat: cat.name, file: m.file, loc: m.loc, prefix: pre, expected: m.exp))
                }
            }
        }
        return out
    }

    // MARK: - Evaluation

    private static func norms(_ s: String) -> [String] {
        var a = [s]
        var t = s
        while let f = t.unicodeScalars.first, "$@:<!".unicodeScalars.contains(f) { t.removeFirst() }
        a.append(t)
        if let i = t.firstIndex(where: { "(=:\" ".contains($0) }) { a.append(String(t[..<i])) }
        return a
    }

    static func matches(_ item: CompletionItem, expected e: String) -> Bool {
        var cands = norms(item.label)
        if let f = item.filterText { cands += norms(f) }
        for c in cands {
            if c == e { return true }
            if c.hasSuffix("\\" + e) || c.hasSuffix("/" + e) { return true }
            let noExt = (c as NSString).deletingPathExtension
            if noExt == (e as NSString).deletingPathExtension, c.contains(".") && e.contains(".") == false { return true }
            if c == "x-" + e { return true }
        }
        return false
    }

    /// CE_COMPLETION_BENCH_LEGACY=1: the ranking before CompletionRanker v2 (score = match quality only), kept for before/after tables.
    private static let legacy = AppEnv.value("CE_COMPLETION_BENCH_LEGACY") != nil

    private static func legacyRank(results: [(items: [CompletionItem], incomplete: Bool)?], text ns: NSString, caret: Int, anchor: Int) -> CompletionRanker.Output {
        let defaultStart = CompletionLex.runStart(ns, caret, CompletionLex.isIdent)
        var cache: [Int: CompletionRanker.Q] = [:]
        var out: [CompletionRanker.Ranked] = []
        var seen: [String: Int] = [:]
        var order = 0
        func score(_ item: CompletionItem, _ q: CompletionRanker.Q) -> Int? {
            if q.q.isEmpty { return 0 }
            let t = item.filterText ?? item.label
            if !q.qb.isEmpty, !CompletionLex.subsequence(q.qb, in: t) { return nil }
            let pen = min(t.utf16.count, 60) / 4
            if t == q.q { return 1000 }
            if t.hasPrefix(q.q) { return 900 - pen }
            let tl = t.lowercased()
            if tl == q.ql { return 950 }
            if tl.hasPrefix(q.ql) { return 800 - pen }
            guard let f = Fuzzy.score(q.chars, in: t) else { return nil }
            return 100 + max(0, min(f, 500)) / 2 - pen
        }
        for res in results {
            guard let res else { continue }
            for item in res.items {
                let start = item.replaceRange?.location ?? defaultStart
                guard start >= 0, start <= caret else { continue }
                let q: CompletionRanker.Q
                if let c = cache[start] { q = c } else {
                    let s = ns.substring(with: NSRange(location: start, length: caret - start))
                    let ql = s.lowercased().replacingOccurrences(of: " ", with: "")
                    let ascii = ql.utf8.allSatisfy { $0 < 128 }
                    q = CompletionRanker.Q(q: s, ql: ql, qb: ascii ? Array(ql.utf8) : [], chars: Array(ql), ascii: ascii)
                    cache[start] = q
                }
                guard let sc = score(item, q) else { continue }
                let key = item.label + "\u{1}" + item.kind.rawValue
                let r = CompletionRanker.Ranked(item: item, score: sc, order: order, query: q.q)
                if let idx = seen[key] { if sc >= out[idx].score { out[idx].item = item; out[idx].score = sc }; continue }
                seen[key] = out.count
                out.append(r)
                order += 1
            }
        }
        var nonText = Set<String>()
        for r in out where r.item.kind != .text { nonText.insert(r.item.label) }
        if !nonText.isEmpty { out.removeAll { $0.item.kind == .text && nonText.contains($0.item.label) } }
        out.sort { a, b in
            if a.score != b.score { return a.score > b.score }
            let sa = a.item.sortText ?? a.item.label.lowercased(), sb = b.item.sortText ?? b.item.label.lowercased()
            if sa != sb { return sa < sb }
            return a.order < b.order
        }
        if out.count > 300 { out.removeLast(out.count - 300) }
        return CompletionRanker.Output(ranked: out, anchor: anchor)
    }

    private static var undelivered: [String: Int] = [:]
    private static func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e6 }

    private static func evaluate(_ s: Sample, text: NSString, includeLSP: Bool) -> Result {
        let caret = s.loc + s.prefix
        let ctxText = text.substring(to: min(caret, text.length))
        let ns = ctxText as NSString
        let ext = (s.file as NSString).pathExtension.lowercased()
        let start = CompletionLex.runStart(ns, ns.length, CompletionLex.isIdent)
        var trig: String? = nil
        if s.prefix == 0, start > 0 { trig = ns.substring(with: NSRange(location: start - 1, length: 1)) }
        let ctx = CompletionContext(text: ctxText, caret: ns.length, fileURL: URL(fileURLWithPath: s.file), fileExtension: ext, triggerCharacter: trig,
                                    isManual: false, prefixRange: NSRange(location: start, length: ns.length - start))
        let c0 = now()
        let rctx = CompletionRanker.Context(docCounts: CompletionRanker.docCounts(ns, caret: ns.length), history: nil, popularity: CompletionPopularity.table(ext: ext, blade: s.file.hasSuffix(".blade.php")))
        let ctxMs = now() - c0
        let providers = CompletionRegistry.providers(forExtension: ext).filter { includeLSP || !($0 is LSPCompletionProvider) }
        providers.forEach { $0.cancel() }
        CompletionLex.resetCache()
        var box = [(items: [CompletionItem], incomplete: Bool)?](repeating: nil, count: providers.count)
        var got = Set<Int>()
        let lock = NSLock()
        let t0 = now()
        for (i, p) in providers.enumerated() {
            p.complete(ctx) { items, inc in
                // not hopped to the main queue (the bench itself runs inside a main-queue block, which cannot drain nested)
                lock.lock(); box[i] = (items, inc); got.insert(i); lock.unlock()
            }
        }
        let sync = now() - t0 + ctxMs
        func gotCount() -> Int { lock.lock(); defer { lock.unlock() }; return got.count }
        while gotCount() < providers.count, now() - t0 < 1500 { Thread.sleep(forTimeInterval: 0.0002) }
        let total = now() - t0
        lock.lock(); let results = box; let gotSet = got; lock.unlock()
        if gotSet.count < providers.count {
            for (i, p) in providers.enumerated() where !gotSet.contains(i) { undelivered[String(describing: type(of: p)), default: 0] += 1 }
        }
        let r0 = now()
        let out = legacy ? legacyRank(results: results, text: ns, caret: ns.length, anchor: start) : CompletionRanker.rank(results: results, text: ns, caret: ns.length, anchor: start, context: rctx)
        let rankMs = now() - r0
        var rank: Int?
        for (i, r) in out.ranked.enumerated() where matches(r.item, expected: s.expected) { rank = i + 1; break }
        var labels = Set<String>(), dups = 0
        for r in out.ranked where !labels.insert(r.item.label).inserted { dups += 1 }
        let textTop5 = out.ranked.prefix(5).filter { $0.item.kind == .text }.count
        return Result(sample: s, rank: rank, count: out.ranked.count, dupLabels: dups, textTop5: textTop5, totalMs: total, syncMs: sync, rankMs: rankMs,
                      top: out.ranked.prefix(5).map { $0.item.label })
    }

    private static func pct(_ a: [Double], _ p: Double) -> Double { a.isEmpty ? 0 : a.sorted()[min(a.count - 1, Int(Double(a.count) * p))] }

    struct Agg {
        var n = 0, top1 = 0, top5 = 0, found = 0
        var mrr = 0.0
        var total: [Double] = [], sync: [Double] = [], rank: [Double] = []
        var count = 0, dups = 0, text5 = 0
        mutating func add(_ r: Result, timed: Bool) {
            n += 1
            if let k = r.rank { found += 1; mrr += 1 / Double(k); if k == 1 { top1 += 1 }; if k <= 5 { top5 += 1 } }
            if timed { total.append(r.totalMs); sync.append(r.syncMs); rank.append(r.rankMs) }
            count += r.count; dups += r.dupLabels; text5 += r.textTop5
        }
    }

    private static func line(_ name: String, _ a: Agg) -> String {
        let n = Double(max(1, a.n))
        func pc(_ v: Int) -> String { String(format: "%5.1f%%", Double(v) * 100 / n) }
        return name.padding(toLength: 18, withPad: " ", startingAt: 0)
            + String(format: "%4d  ", a.n) + "found " + pc(a.found) + "  top1 " + pc(a.top1) + "  top5 " + pc(a.top5)
            + String(format: "  MRR %.3f  p50 %6.1f  p95 %6.1f  sync95 %6.1f  rank95 %5.2f ms  items %5.0f  dup %4.1f  text5 %.2f",
                     a.mrr / n, pct(a.total, 0.5), pct(a.total, 0.95), pct(a.sync, 0.95), pct(a.rank, 0.95), Double(a.count) / n, Double(a.dups) / n, Double(a.text5) / n)
    }

    // MARK: - Entry

    static func run(_ spec: String) {
        let perCat = Int(AppEnv.value("CE_COMPLETION_BENCH_N") ?? "40") ?? 40
        let only = Set((AppEnv.value("CE_COMPLETION_BENCH_ONLY") ?? "").split(separator: ",").map(String.init))
        let maxMiss = Int(AppEnv.value("CE_COMPLETION_BENCH_MISSES") ?? "0") ?? 0
        let includeLSP = AppEnv.value("CE_COMPLETION_BENCH_LSP") != nil
        var allResults: [Result] = []
        for root in spec.split(separator: ",").map(String.init) {
            let t0 = now()
            let rootURL = URL(fileURLWithPath: root)
            if FileManager.default.fileExists(atPath: root + "/composer.json") || FileManager.default.fileExists(atPath: root + "/artisan") {
                FastTier.warm(root: rootURL)
                VendorIndex.shared(for: rootURL).refreshIfNeeded(force: true)
                VendorIndex.shared(for: rootURL).waitUntilIdle()
            }
            var samples = collect(root: root, only: only, perCat: perCat)
            // group by file for read reuse; keep category order stable for the warm-up rule below
            samples.sort { ($0.file, $0.loc) < ($1.file, $1.loc) }
            fputs("CBENCH project \(root): \(samples.count) samples collected in \(Int(now() - t0)) ms\n", stderr)
            var warmSeen: [String: Int] = [:]
            var results: [Result] = []
            var cache: (String, NSString)?
            for s in samples {
                let text: NSString
                if let c = cache, c.0 == s.file { text = c.1 } else { guard let t = read(s.file) else { continue }; cache = (s.file, t); text = t }
                let r = evaluate(s, text: text, includeLSP: includeLSP)
                let key = s.cat + "/\(s.prefix)"
                warmSeen[key, default: 0] += 1
                results.append(r)
                if results.count % 250 == 0 { fputs("CBENCH progress \(results.count)/\(samples.count) (\(Int(now() - t0)) ms)\n", stderr) }
            }
            if !undelivered.isEmpty { fputs("CBENCH providers that never delivered (1.5 s timeout): \(undelivered)\n", stderr) }
            // latency from the second half of each category (first requests pay lazy index builds: reported separately)
            var seen: [String: Int] = [:]
            var byCat: [String: [Int: Agg]] = [:]
            var firsts: [Double] = []
            for r in results {
                let key = r.sample.cat + "/\(r.sample.prefix)"
                seen[key, default: 0] += 1
                let timed = seen[key]! > 2
                if !timed { firsts.append(r.totalMs) }
                byCat[r.sample.cat, default: [:]][r.sample.prefix, default: Agg()].add(r, timed: timed)
            }
            fputs("CBENCH cold-ish first requests: p50 \(String(format: "%.1f", pct(firsts, 0.5))) ms max \(String(format: "%.1f", firsts.max() ?? 0)) ms\n", stderr)
            var rows: [(Double, String)] = []
            for (cat, m) in byCat { for (p, a) in m { rows.append((a.mrr / Double(max(1, a.n)), line("\(cat)@\(p)", a))) } }
            fputs("CBENCH \(root) (prefix = characters already typed; weakest first)\n", stderr)
            for r in rows.sorted(by: { $0.0 < $1.0 }) { fputs("CBENCH \(r.1)\n", stderr) }
            // per-language summary
            var lang: [String: Agg] = [:]
            for r in results {
                let l = String(r.sample.cat.split(separator: ".")[0])
                lang[l, default: Agg()].add(r, timed: true)
                lang[l + "@\(r.sample.prefix)", default: Agg()].add(r, timed: true)
            }
            for k in lang.keys.sorted() { fputs("CBENCH LANG \(line(k, lang[k]!))\n", stderr) }
            if maxMiss > 0 {
                var shown: [String: Int] = [:]
                for r in results where r.rank == nil || r.rank! > 5 {
                    let key = r.sample.cat + "@\(r.sample.prefix)"
                    guard shown[key, default: 0] < maxMiss else { continue }
                    shown[key, default: 0] += 1
                    let rel = r.sample.file.hasPrefix(root) ? String(r.sample.file.dropFirst(root.count + 1)) : r.sample.file
                    fputs("CBENCH MISS \(key) \(rel) expected '\(r.sample.expected)' rank \(r.rank.map(String.init) ?? "-") of \(r.count) top: \(r.top.joined(separator: " | "))\n", stderr)
                }
            }
            allResults += results
        }
        if let out = AppEnv.value("CE_COMPLETION_BENCH_OUT") {
            let rows: [[String: Any]] = allResults.map {
                ["cat": $0.sample.cat, "file": $0.sample.file, "loc": $0.sample.loc, "prefix": $0.sample.prefix, "expected": $0.sample.expected,
                 "rank": $0.rank ?? 0, "count": $0.count, "ms": $0.totalMs, "syncMs": $0.syncMs, "rankMs": $0.rankMs, "top": $0.top]
            }
            if let d = try? JSONSerialization.data(withJSONObject: ["rows": rows], options: [.prettyPrinted]) { try? d.write(to: URL(fileURLWithPath: out)) }
        }
        exit(0)
    }
}
