import AppKit

/// Native "fast tier" PHP + Laravel completion. Registered as one more CompletionProvider (see CompletionSystem), so the
/// controller merges/dedupes its items with Intelephense's. Work runs on a per-project serial utility queue.
enum FastTier {
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "fastTier.enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "fastTier.enabled") }
    }

    private static var rootCache: [String: String] = [:]     // dir -> project root ("" = none); main thread only

    static func register() {
        CompletionRegistry.register(FastTierProvider(), forExtensions: ["php", "phtml"])
    }

    /// FSEvents batch handler hook: forces the next request to re-validate its sections.
    static func invalidate(root: URL) {
        FastProject.existing(root: root)?.markDirty()
        rootCache = rootCache.filter { $0.value == "" ? false : true }
    }

    /// Project root for a file: the Laravel root, else the nearest directory with composer.json.
    static func root(for file: URL) -> String? {
        var dir = file.deletingLastPathComponent().standardizedFileURL.path
        let start = dir
        if let c = rootCache[start] { return c.isEmpty ? nil : c }
        var result = ""
        for _ in 0..<14 {
            if LaravelFS.isFile(dir + "/composer.json") || LaravelFS.isFile(dir + "/artisan") { result = dir; break }
            let parent = (dir as NSString).deletingLastPathComponent
            if parent == dir || parent.isEmpty { break }
            dir = parent
        }
        if rootCache.count > 300 { rootCache.removeAll() }
        rootCache[start] = result
        return result.isEmpty ? nil : result
    }

    /// Background warm-up (call when a project opens): builds the cheap sections at utility QoS.
    static func warm(root: URL) {
        guard enabled else { return }
        let fp = FastProject.shared(root: root)
        fp.queue.async {
            fp.beginRequest()
            _ = fp.routeNames(); _ = fp.viewNames(); _ = fp.configKeys(); _ = fp.schema(); _ = fp.projectClasses()
        }
    }

    /// Synchronous entry for tests and tools: computes the fast-tier items for a completion context.
    static func items(for ctx: CompletionContext) -> [CompletionItem] {
        guard let r = root(for: ctx.fileURL) else { return [] }
        let fp = FastProject.shared(root: URL(fileURLWithPath: r))
        let region = CompletionLex.info(ctx).region
        let state = CompletionLex.state(ctx)
        return fp.queue.sync { FastEngine.run(ctx, region: region, state: state, fp: fp).items }
    }
}

final class FastTierProvider: CompletionProvider {
    let triggerCharacters = ["'", "\"", ".", "-", ":", ">", "\\"]
    private var token = 0

    func complete(_ context: CompletionContext, deliver: @escaping ([CompletionItem], Bool) -> Void) {
        token += 1
        let mine = token
        guard FastTier.enabled, let r = FastTier.root(for: context.fileURL) else { deliver([], false); return }
        CompletionLex.resetCache()
        let region = CompletionLex.info(context).region
        let state = CompletionLex.state(context)
        if state == .comment && region != .html { deliver([], false); return }
        let fp = FastProject.shared(root: URL(fileURLWithPath: r))
        fp.queue.async { [weak self] in
            guard let self, self.token == mine else { return }
            let res = FastEngine.run(context, region: region, state: state, fp: fp)
            guard self.token == mine else { return }
            deliver(res.items, res.incomplete)
        }
    }

    func cancel() { token += 1 }
}

// MARK: - Engine

enum FastEngine {
    struct Result { var items: [CompletionItem]; var incomplete = false }

    private static let viewCalls: [String: Int] = [
        "view": 0, "view::make": 0, "view::exists": 0, "view::first": 0, "route::view": 1, "@include": 0, "@includeif": 0, "@includewhen": 1,
        "@includeunless": 1, "@includefirst": 0, "@extends": 0, "@component": 0, "@each": 0, "@embed": 0, "->view": 0, "->markdown": 0, "response::view": 0,
    ]
    private static let inertiaCalls: [String: Int] = ["inertia::render": 0, "inertia": 0, "route::inertia": 1, "inertia::modal": 0]
    private static let routeCalls: Set<String> = ["route", "to_route", "route::has", "url::route", "redirect::route", "route::currentroutenamed", "->routeis",
                                                  "route::is", "redirect()->route", "->route"]
    private static let configCalls: Set<String> = ["config", "config::get", "config::has", "config::string", "config::integer", "config::boolean",
                                                   "config::array", "config::float", "config::set"]
    private static let envCalls: Set<String> = ["env", "env::get"]
    private static let langCalls: Set<String> = ["__", "trans", "trans_choice", "@lang", "@choice", "lang::get", "lang::has", "lang::choice", "->trans"]

    static func run(_ ctx: CompletionContext, region: CompletionLex.Region, state: CompletionLex.State, fp: FastProject) -> Result {
        fp.beginRequest()
        let ns = ctx.text as NSString
        let caret = min(ctx.caret, ns.length)
        let blade = CompletionLex.isBlade(ctx)

        // 1. Laravel string arguments (PHP and Blade)
        if let open = openString(ns, caret) {
            if region == .js || region == .css { return Result(items: []) }
            return stringItems(ctx, ns, open: open, caret: caret, blade: blade, fp: fp)
        }
        // 2. Blade component tags
        if blade, region == .html, let r = componentItems(ns, caret, fp) { return r }
        if region == .js || region == .css || region == .html && !blade { return Result(items: []) }
        if blade && region == .html { return Result(items: []) }
        guard state == .code else { return Result(items: []) }
        // 3. PHP code: use-statements, members, class names
        return phpItems(ctx, ns, caret: caret, blade: blade, fp: fp)
    }

    // MARK: Strings

    /// Opening quote of the string literal containing the caret on this line (heuristic that also works inside HTML attributes).
    static func openString(_ ns: NSString, _ caret: Int) -> Int? {
        let ls = max(CompletionLex.lineStart(ns, caret), caret - 300)
        var j = caret - 1
        while j >= ls {
            let c = ns.character(at: j)
            if c == 39 || c == 34 {
                if j > ls, ns.character(at: j - 1) == 92 { j -= 1; continue }
                // content between quote and caret must look like a key
                var k = j + 1
                while k < caret {
                    let d = ns.character(at: k)
                    if d == 39 || d == 34 || d == 40 || d == 41 || d == 91 || d == 93 || d == 123 || d == 125 || d == 59 || d == 44 || d == 60 || d == 62 || d == 61 || d == 36 { return nil }
                    k += 1
                }
                // opener is preceded by ( , [ => = . ? : or whitespace-after-those
                var b = j - 1
                while b >= ls, ns.character(at: b) == 32 || ns.character(at: b) == 9 { b -= 1 }
                guard b >= ls else { return nil }
                let p = ns.character(at: b)
                if p == 40 || p == 44 || p == 91 || p == 61 || p == 62 || p == 46 || p == 63 || p == 58 { return j }
                return nil
            }
            j -= 1
        }
        return nil
    }

    private static func enclosingCall(_ ns: NSString, openAbs: Int) -> Int? {
        let start = max(0, openAbs - 2500)
        let u = ns.substring(with: NSRange(location: start, length: openAbs - start)) as NSString
        var depth = 0
        var i = u.length - 1
        while i >= 0 {
            let c = u.character(at: i)
            if c == 39 || c == 34 {
                var j = i - 1
                while j >= 0, !(u.character(at: j) == c && (j == 0 || u.character(at: j - 1) != 92)) { j -= 1 }
                i = j >= 0 ? j - 1 : i - 1
                continue
            }
            switch c {
            case 41, 93, 125: depth += 1
            case 40: if depth == 0 { return start + i }; depth -= 1
            case 91: if depth > 0 { depth -= 1 }
            case 123: if depth == 0 { return nil }; depth -= 1
            case 59: if depth == 0 { return nil }
            default: break
            }
            i -= 1
        }
        return nil
    }

    private static func names<S: Sequence>(_ list: S, kind: CompletionKind, range: NSRange, detail: String = "", prefix: String = "") -> [CompletionItem] where S.Element == String {
        list.map { var it = CI.make($0, kind, detail: detail, sort: "0" + $0.lowercased(), range: range); it.filterText = prefix.isEmpty ? nil : $0; return it }
    }

    private static func stringItems(_ ctx: CompletionContext, _ ns: NSString, open: Int, caret: Int, blade: Bool, fp: FastProject) -> Result {
        let range = NSRange(location: open + 1, length: caret - open - 1)
        guard let call = LaravelResolver.callContext(ns, openAbs: open) else { return Result(items: []) }
        let key = call.key
        var method = key.components(separatedBy: CharacterSet(charactersIn: ":->")).last(where: { !$0.isEmpty }) ?? key
        if let paren = enclosingCall(ns, openAbs: open) {     // original casing (callContext lowercases)
            var q = paren - 1
            while q >= 0, [32, 9, 10, 13].contains(ns.character(at: q)) { q -= 1 }
            let id = CompletionLex.identBefore(ns, q + 1)
            if id.lowercased() == method { method = id }
        }
        var items: [CompletionItem] = []
        if call.argIndex == 0, routeCalls.contains(key), fp.isLaravel {
            items = fp.routeNames().map { CI.make($0.name, .value, detail: $0.detail, sort: "0" + $0.name, doc: "Route `\($0.name)`", range: range) }
        } else if let idx = viewCalls[key], call.argIndex == idx {
            items = names(fp.viewNames(), kind: .file, range: range, detail: "view")
        } else if let idx = inertiaCalls[key], call.argIndex == idx {
            items = names(fp.inertiaPages(), kind: .file, range: range, detail: "inertia page")
        } else if call.argIndex == 0, configCalls.contains(key) {
            items = names(fp.configKeys(), kind: .property, range: range, detail: "config")
        } else if call.argIndex == 0, envCalls.contains(key) {
            items = fp.envKeys().map { CI.make($0.name, .constant, detail: $0.detail, sort: "0" + $0.name, range: range) }
        } else if call.argIndex == 0, langCalls.contains(key) {
            items = names(fp.langKeys(), kind: .value, range: range, detail: "lang")
        } else if (FTEval.columnMethods.contains(method) || FTEval.relationMethods.contains(method)), !blade,
                  let r = modelStringItems(ctx, ns, open: open, caret: caret, method: method, fp: fp) {
            return r
        }
        return Result(items: items)
    }

    /// `where('`, `orderBy('`, `with('posts.` ...: columns / relations of the receiver's model (or DB::table).
    private static func modelStringItems(_ ctx: CompletionContext, _ ns: NSString, open: Int, caret: Int, method: String, fp: FastProject) -> Result? {
        guard let paren = enclosingCall(ns, openAbs: open) else { return nil }
        var q = paren - 1
        while q >= 0, [32, 9, 10, 13].contains(ns.character(at: q)) { q -= 1 }
        let ident = CompletionLex.identBefore(ns, q + 1)
        guard ident == method || ident.lowercased() == method.lowercased() else { return nil }
        let lex = PHPLex(ns)
        let cur = FTParser.parse(ns, lex: lex)
        let ev = FTEval(fp: fp, text: ns, lex: lex, cur: cur)
        let identStart = q + 1 - ident.utf16.count
        let opTok = ev.tokenIndex(atOrAfter: identStart) - 1
        guard opTok >= 1, lex.isPunct(opTok, code: PHPTok.arrow) || lex.isPunct(opTok, code: PHPTok.dcolon) else { return nil }
        let lo = ev.chainStart(before: opTok)
        guard let t = ev.eval(lo, opTok) else { return nil }
        var contentStart = open + 1
        var model = ev.modelFQN(t)
        var items: [CompletionItem] = []
        if FTEval.relationMethods.contains(method) {
            guard var m = model else { return nil }
            // dotted: complete the last segment against the model reached through the earlier ones
            let typed = ns.substring(with: NSRange(location: open + 1, length: caret - open - 1))
            if let dot = typed.lastIndex(of: ".") {
                let head = String(typed[..<dot])
                guard let r = ev.relatedModel(m, head) else { return nil }
                m = r
                contentStart = open + 1 + head.utf16.count + 1
            }
            let range = NSRange(location: contentStart, length: caret - contentStart)
            var seen = Set<String>()
            for k in ev.hierarchy(m) { for r in k.relations where seen.insert(r.name).inserted {
                items.append(CI.make(r.name, .property, detail: r.kind + (r.related.map { " " + ($0 as NSString).lastPathComponent } ?? ""), sort: "0" + r.name.lowercased(), range: range))
            } }
            return Result(items: items)
        }
        let range = NSRange(location: contentStart, length: caret - contentStart)
        if case .table(let tbl) = t {
            items = (fp.schema()[tbl] ?? []).map { CI.make($0.name, .field, detail: $0.type, sort: "0" + $0.name.lowercased(), range: range) }
            return Result(items: items)
        }
        model = model.flatMap { ev.isModel($0) ? $0 : nil }
        guard let m = model, let c = ev.hierarchy(m).first else { return nil }
        let tbl = fp.tableName(of: c)
        items = fp.columns(of: c).map { CI.make($0.name, .field, detail: $0.type, sort: "0" + $0.name.lowercased(), doc: "`\(tbl)`", range: range) }
        return Result(items: items)
    }

    // MARK: Blade components

    private static let componentRegex = try! NSRegularExpression(pattern: #"</?((?:x-|livewire:)[\w.:\-]*)$"#)

    private static func componentItems(_ ns: NSString, _ caret: Int, _ fp: FastProject) -> Result? {
        let ls = max(CompletionLex.lineStart(ns, caret), caret - 200)
        let line = ns.substring(with: NSRange(location: ls, length: caret - ls))
        guard let m = componentRegex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) else { return nil }
        let tag = NSRange(location: ls + m.range(at: 1).location, length: m.range(at: 1).length)
        let comps = fp.componentNames()
        let items = comps.map { c -> CompletionItem in
            var it = CI.make(c.name, .class, detail: c.detail, sort: "0" + c.name, range: tag)
            it.insertText = c.name
            return it
        }
        return Result(items: items)
    }

    // MARK: PHP

    private static func phpItems(_ ctx: CompletionContext, _ ns: NSString, caret: Int, blade: Bool, fp: FastProject) -> Result {
        let p = ctx.prefixRange.location
        let prefix = ctx.prefix
        let before = CompletionLex.line(before: p, ns)
        // use statements
        if !blade, let re = try? NSRegularExpression(pattern: #"^\s*use\s+([\\\w]*)$"#),
           let m = re.firstMatch(in: CompletionLex.line(before: caret, ns), range: NSRange(location: 0, length: (CompletionLex.line(before: caret, ns) as NSString).length)) {
            let line = CompletionLex.line(before: caret, ns) as NSString
            let typed = line.substring(with: m.range(at: 1))
            return useStatementItems(typed: typed, range: NSRange(location: caret - typed.utf16.count, length: typed.utf16.count), fp: fp)
        }
        if blade { return Result(items: []) }
        // member access
        let nullsafe = before.hasSuffix("?->")
        let isArrow = before.hasSuffix("->")
        let isColons = before.hasSuffix("::")
        var staticDollar = false
        var opLen = nullsafe ? 3 : 2
        var pStart = p
        if !isArrow, !isColons, p > 0, ns.character(at: p - 1) == 36, CompletionLex.before(ns, p - 1, "::") { staticDollar = true; pStart = p - 1; opLen = 2 }
        if isArrow || isColons || staticDollar {
            let opLoc = pStart - opLen
            let lex = PHPLex(ns)
            let cur = FTParser.parse(ns, lex: lex)
            let ev = FTEval(fp: fp, text: ns, lex: lex, cur: cur)
            let opTok = ev.tokenIndex(atOrAfter: opLoc)
            guard opTok >= 1, opTok < lex.count, lex.toks[opTok].loc == opLoc else { return Result(items: []) }
            let lo = ev.chainStart(before: opTok)
            guard let t = ev.eval(lo, opTok) else { return Result(items: []) }
            if case .staticRef(let f) = t, f.hasPrefix("Illuminate\\Support\\Facades\\") { return Result(items: []) }
            var via: String?
            if lo < opTok, lex.toks[lo].kind == .ident { via = lex.text(lo) }
            var seen = Set<String>()
            let same: Bool
            switch t {
            case .instance(let f), .staticRef(let f): same = f == cur?.fqn
            default: same = false
            }
            var items = ev.members(of: t, via: via, fromSameClass: same, staticDollar: staticDollar, onlyNames: &seen)
            if staticDollar { let r = NSRange(location: pStart, length: caret - pStart); for i in items.indices { items[i].replaceRange = r } }
            return Result(items: items)
        }
        // class names
        guard !prefix.isEmpty || ctx.isManual else { return Result(items: []) }
        if p > 0 {
            let c = ns.character(at: p - 1)
            if c == 36 || c == 92 || c == 64 { return Result(items: []) }     // $var, \Qualified, @directive
        }
        guard let f = prefix.unicodeScalars.first, CharacterSet.letters.contains(f) || prefix.isEmpty else { return Result(items: []) }
        let t = before.trimmingCharacters(in: .whitespaces)
        for kw in ["function", "class", "interface", "trait", "enum", "const", "namespace", "case", "->", "::", "use"] where t.hasSuffix(kw) && !(kw == "use") { return Result(items: []) }
        if prefix.count < 2 && !ctx.isManual { return Result(items: []) }
        return classItems(prefix: prefix, ctx: ctx, ns: ns, range: ctx.prefixRange, fp: fp)
    }

    private static func kind(of e: VendorEntry) -> CompletionKind {
        switch e.kind { case .interface: return .interface; case .enum: return .enum; default: return .class }
    }

    private struct Cand { var short: String; var fqn: String; var kind: CompletionKind; var project: Bool; var builtin = false }

    private static func candidates(_ query: String, fp: FastProject, limit: Int) -> [Cand] {
        let q = query.lowercased()
        var out: [Cand] = []
        var prefixHits: [Cand] = [], fuzzyHits: [Cand] = []
        for c in fp.projectClasses() {
            let l = c.short.lowercased()
            if l.hasPrefix(q) { prefixHits.append(Cand(short: c.short, fqn: c.fqn, kind: .class, project: true)) }
            else if CompletionLex.subsequence(Array(q.utf8), in: c.short) { fuzzyHits.append(Cand(short: c.short, fqn: c.fqn, kind: .class, project: true)) }
        }
        prefixHits.sort { $0.short.count < $1.short.count }
        out += prefixHits.prefix(limit) + fuzzyHits.prefix(max(0, limit / 2))
        if VendorIndex.enabled {
            let seen = Set(out.map(\.fqn))
            for e in VendorIndex.shared(for: fp.lp.root).searchTypes(query, limit: limit) where !seen.contains(e.fqn) {
                out.append(Cand(short: e.shortName, fqn: e.fqn, kind: kind(of: e), project: false))
            }
        }
        let have = Set(out.map(\.fqn))
        for e in PHPStubs.search(kind: "c", prefix: query, limit: limit) where !have.contains(e.name) { out.append(stubCand(e)) }
        return out
    }

    private static func stubCand(_ e: PHPStubEntry) -> Cand {
        let k: CompletionKind = e.extra == "interface" ? .interface : e.extra == "enum" ? .enum : .class
        return Cand(short: e.name.split(separator: "\\").last.map(String.init) ?? e.name, fqn: e.name, kind: k, project: false, builtin: true)
    }

    private static func useStatementItems(typed: String, range: NSRange, fp: FastProject) -> Result {
        guard !typed.isEmpty else { return Result(items: []) }
        let tq = Array(typed.lowercased().utf8)
        var cands: [Cand] = []
        for c in fp.projectClasses() where CompletionLex.subsequence(tq, in: c.fqn) { cands.append(Cand(short: c.short, fqn: c.fqn, kind: .class, project: true)) }
        cands.sort { ($0.fqn.lowercased().hasPrefix(typed.lowercased()) ? 0 : 1, $0.fqn.count) < ($1.fqn.lowercased().hasPrefix(typed.lowercased()) ? 0 : 1, $1.fqn.count) }
        cands = Array(cands.prefix(60))
        if VendorIndex.enabled {
            let seen = Set(cands.map(\.fqn))
            for e in VendorIndex.shared(for: fp.lp.root).searchTypes(typed, limit: 40) where !seen.contains(e.fqn) { cands.append(Cand(short: e.shortName, fqn: e.fqn, kind: kind(of: e), project: false)) }
        }
        let have = Set(cands.map(\.fqn))
        for e in PHPStubs.search(kind: "c", prefix: typed.hasPrefix("\\") ? String(typed.dropFirst()) : typed, limit: 20) where !have.contains(e.name) { cands.append(stubCand(e)) }
        let items = cands
            .map { c -> CompletionItem in
                var it = CI.make(c.fqn, c.kind, detail: c.project ? "project" : (c.builtin ? "php" : "vendor"), insert: c.fqn, sort: (c.project ? "1" : "2") + c.short.lowercased(), range: range)
                it.filterText = c.fqn
                return it
            }
        return Result(items: items, incomplete: true)
    }

    private static func classItems(prefix: String, ctx: CompletionContext, ns: NSString, range: NSRange, fp: FastProject) -> Result {
        let cands = candidates(prefix, fp: fp, limit: 40)
        guard !cands.isEmpty else { return Result(items: []) }
        let cur = FTParser.parse(ns)
        var count: [String: Int] = [:]
        for c in cands { count[c.short, default: 0] += 1 }
        var items: [CompletionItem] = []
        for c in cands {
            var insert = c.short
            var edits: [(range: NSRange, text: String)] = []
            if let cur { (insert, edits) = importEdit(c.fqn, short: c.short, cur: cur) }
            let ambiguous = (count[c.short] ?? 0) > 1
            var it = CI.make(ambiguous ? "\(c.short) (\((c.fqn as NSString).deletingLastPathComponent.isEmpty ? namespaceOf(c.fqn) : namespaceOf(c.fqn)))" : c.short, c.kind,
                             detail: c.fqn, insert: insert, sort: (c.project ? "1" : "2") + c.short.lowercased(), doc: "`\(c.fqn)`\n\nAdds `use \(c.fqn);` when accepted.", range: range)
            if ambiguous { it.filterText = c.short }
            it.additionalEdits = edits
            items.append(it)
        }
        return Result(items: items, incomplete: true)
    }

    private static func namespaceOf(_ fqn: String) -> String {
        guard let i = fqn.lastIndex(of: "\\") else { return "global" }
        return String(fqn[..<i])
    }

    /// (text to insert at the caret, extra edits) for referencing `fqn` from the file described by `cur`.
    static func importEdit(_ fqn: String, short: String, cur: FTClass) -> (String, [(range: NSRange, text: String)]) {
        let ns = namespaceOf(fqn) == "global" ? "" : namespaceOf(fqn)
        if ns == cur.ns { return (short, []) }
        if cur.uses.values.contains(fqn) { return (cur.uses.first(where: { $0.value == fqn })?.key ?? short, []) }
        if cur.uses[short] != nil { return ("\\" + fqn, []) }
        if cur.ns.isEmpty, ns.isEmpty { return (short, []) }
        let line = "use \(fqn);\n"
        var stmts: [FTUseStmt] = []
        var seenLines = Set<Int>()
        for s in cur.useStmts where seenLines.insert(s.lineStart).inserted { stmts.append(s) }
        if let after = stmts.first(where: { $0.fqn.lowercased() > fqn.lowercased() }) {
            return (short, [(NSRange(location: after.lineStart, length: 0), line)])
        }
        if let last = stmts.last { return (short, [(NSRange(location: last.lineEnd, length: 0), line)]) }
        if let n = cur.nsLineEnd { return (short, [(NSRange(location: n, length: 0), "\n" + line)]) }
        if let o = cur.openTagEnd { return (short, [(NSRange(location: o, length: 0), "\n" + line)]) }
        return ("\\" + fqn, [])
    }
}
