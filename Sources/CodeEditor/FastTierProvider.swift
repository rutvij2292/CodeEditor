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
        NativeEngines.invalidate(root: root)            // the other native engines (web, vue, js)
        rootCache = rootCache.filter { $0.value == "" ? false : true }
    }

    /// Hot update from an FSEvents batch: the changed paths decide what is re-checked (see FastProject.noteChanged). Saving a PHP
    /// file costs one cached class; each of the other engines only reacts to the paths that can affect it.
    static func invalidate(root: URL, paths: [String]) {
        FastProject.existing(root: root)?.noteChanged(paths)
        NativeEngines.invalidate(root: root, paths: paths)
        rootCache = rootCache.filter { $0.value == "" ? false : true }
    }

    /// Project root for a file: the Laravel root, else the nearest directory with composer.json.
    static func root(for file: URL) -> String? {
        var dir = file.deletingLastPathComponent().standardizedFileURL.path
        let start = dir
        if let c = rootCache[start] { return c.isEmpty ? nil : c }
        // The project root is the nearest ancestor that is really a Laravel / Composer application (artisan or an installed vendor/).
        // A bare composer.json does not count by itself: nwidart modules (Modules/Users/composer.json) carry one each, and treating the
        // module as the project made every `App\...` import of its files "undefined". Without such an ancestor, the nearest composer.json wins.
        var result = "", firstComposer = ""
        for _ in 0..<14 {
            let hasComposer = LaravelFS.isFile(dir + "/composer.json")
            if LaravelFS.isFile(dir + "/artisan") || (hasComposer && LaravelFS.isFile(dir + "/vendor/composer/autoload_psr4.php")) { result = dir; break }
            if hasComposer, firstComposer.isEmpty { firstComposer = dir }
            let parent = (dir as NSString).deletingLastPathComponent
            if parent == dir || parent.isEmpty { break }
            dir = parent
        }
        if result.isEmpty { result = firstComposer }
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
            _ = fp.usageView(file: root.appendingPathComponent("artisan"), live: "")
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
        if state == .comment && region != .html && !(region == .php && !CompletionLex.isBlade(context)) { deliver([], false); return }
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
    private static let sessionCalls: Set<String> = ["session", "session::get", "session::has", "session::put", "session::forget", "session::pull", "session::exists", "session::flash", "session::increment"]
    private static let cacheCalls: Set<String> = ["cache", "cache::get", "cache::has", "cache::put", "cache::remember", "cache::rememberforever", "cache::forget", "cache::pull", "cache::add",
                                                  "cache::increment", "cache::decrement", "cache::missing", "cache::forever", "cache::lock"]
    private static let gateCalls: Set<String> = ["gate::allows", "gate::denies", "gate::check", "gate::any", "gate::none", "gate::authorize", "gate::inspect", "gate::define", "->can", "->cannot",
                                                 "->authorize", "@can", "@cannot", "@canany", "can", "authorize"]
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
        // `'exists:users,|` / `'in:a,b,|`: a comma inside the string, only meaningful for validation rules
        if !blade, region == .php, let open = openString(ns, caret, allowComma: true), let r = FastRules.items(ns, open: open, caret: caret, fp: fp) { return r }
        // 2. Blade component tags
        if blade, region == .html, let r = componentItems(ns, caret, fp) { return r }
        if region == .js || region == .css || region == .html && !blade { return Result(items: []) }
        if blade && region == .html { return Result(items: []) }
        if state == .comment, region == .php, !blade { return docblockItems(ctx, ns, caret: caret, fp: fp) }
        guard state == .code else { return Result(items: []) }
        // 3. PHP code: use-statements, members, class names
        return phpItems(ctx, ns, caret: caret, blade: blade, fp: fp)
    }

    // MARK: Strings

    /// Opening quote of the string literal containing the caret on this line (heuristic that also works inside HTML attributes).
    static func openString(_ ns: NSString, _ caret: Int, allowComma: Bool = false) -> Int? {
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
                    if d == 39 || d == 34 || d == 40 || d == 41 || d == 91 || d == 93 || d == 123 || d == 125 || d == 59 || (d == 44 && !allowComma) || d == 60 || d == 62 || d == 61 || d == 36 { return nil }
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

    static func enclosingCall(_ ns: NSString, openAbs: Int) -> Int? {
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
        if !blade, let r = FastRules.items(ns, open: open, caret: caret, fp: fp) { return r }      // validation rules / casts
        if !blade, let r = arrayCallableItems(ns, open: open, caret: caret, fp: fp) { return r }   // [Foo::class, '|'] / [$this, '|']
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
        } else if call.argIndex == 0, sessionCalls.contains(key) || cacheCalls.contains(key) || gateCalls.contains(key) || key == "->middleware" || key == "middleware" {
            let isGate = gateCalls.contains(key), isMW = key == "->middleware" || key == "middleware"
            let kind: FUsageKind = isGate ? .gate : (isMW ? .middleware : (sessionCalls.contains(key) ? .session : .cache))
            let uv = fp.usageView(file: ctx.fileURL, live: ctx.text as NSString)
            var seen = Set<String>()
            var fixed: [FTName] = isGate ? fp.policyAbilities() : (isMW ? fp.middlewareAliases() : [])
            fixed = fixed.filter { seen.insert($0.name).inserted }
            let label = isGate ? "ability" : (isMW ? "middleware" : (kind == .session ? "session key" : "cache key"))
            items = fixed.map { CI.make($0.name, .value, detail: $0.detail, sort: "0" + $0.name, range: range) }
            for n in (uv?.names(kind) ?? []) where seen.insert(n).inserted { items.append(CI.make(n, .value, detail: label, sort: "0" + n, range: range)) }
        } else if (FTEval.columnMethods.contains(method) || FTEval.relationMethods.contains(method)), !blade,
                  let r = modelStringItems(ctx, ns, open: open, caret: caret, method: method, fp: fp) {
            return r
        } else if FTEval.columnMethods.contains(method), !blade, call.argIndex == 0 {
            // receiver type unknown (query builder chain, dynamic model): every column of the schema, most widespread first
            var count: [String: (type: String, n: Int)] = [:]
            for cols in fp.schema().values { for c in cols { let e = count[c.name]; count[c.name] = (e?.type ?? c.type, (e?.n ?? 0) + 1) } }
            items = count.sorted { ($0.value.n, $1.key) > ($1.value.n, $0.key) }.prefix(1500).enumerated().map { i, e in
                var it = CI.make(e.key, .field, detail: e.value.type + (e.value.n > 1 ? "  \u{00D7}\(e.value.n)" : ""), doc: "Column found in \(e.value.n) table(s)", range: range)
                it.priority = 20 + min(i, 900) / 30
                return it
            }
        }
        if !items.isEmpty, let kind = usageKind(key: key, method: method, argIndex: call.argIndex, view: viewCalls[key] == call.argIndex), items.count > 1,
           let uv = fp.usageView(file: ctx.fileURL, live: ctx.text as NSString) {
            uv.apply(&items, kind: kind)
        }
        return Result(items: items)
    }

    /// `[LoginController::class, '|']` and `[$this, '|']`: the public methods of the class named just before (own methods first,
    /// inherited ones after). Route actions, middleware / event callables and `Route::resource`-style arrays all use this shape.
    private static func arrayCallableItems(_ ns: NSString, open: Int, caret: Int, fp: FastProject) -> Result? {
        if AppEnv.value("CE_COMPL_DEBUG") != nil { fputs("COMPL-DBG arrayCallable open=\(open) caret=\(caret) before=\(ns.substring(with: NSRange(location: max(0, open - 30), length: min(30, open))))\n", stderr) }
        func skipBlanks(_ i: Int) -> Int { var j = i; while j >= 0, [32, 9, 10, 13].contains(ns.character(at: j)) { j -= 1 }; return j }
        var j = skipBlanks(open - 1)
        guard j >= 0, ns.character(at: j) == 44 else { return nil }                       // `,` before the quote
        j = skipBlanks(j - 1)
        var written: String?
        let end = j + 1
        if end >= 6, ns.substring(with: NSRange(location: end - 7 >= 0 ? end - 7 : 0, length: end - (end - 7 >= 0 ? end - 7 : 0))).hasSuffix("::class") {
            var k = end - 7
            let nameEnd = k
            while k > 0, CompletionLex.isIdent(ns.character(at: k - 1)) || ns.character(at: k - 1) == 92 { k -= 1 }
            guard nameEnd > k else { return nil }
            written = ns.substring(with: NSRange(location: k, length: nameEnd - k))
            j = skipBlanks(k - 1)
        } else if end >= 5, ns.substring(with: NSRange(location: end - 5, length: 5)) == "$this" {
            written = "$this"
            j = skipBlanks(end - 6)
        } else { return nil }
        guard j >= 0, ns.character(at: j) == 91, let written else { return nil }           // the array's `[`
        let t0 = CFAbsoluteTimeGetCurrent()
        let lex = PHPLex(ns)
        guard let cur = FTParser.parse(ns, lex: lex) else { return nil }
        if AppEnv.value("CE_COMPL_DEBUG") != nil { fputs("COMPL-DBG arrayCallable lex+parse \(Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)) ms\n", stderr) }
        let fqn = written == "$this" ? cur.fqn : cur.resolve(written)
        guard !fqn.isEmpty else { return nil }
        let ev = FTEval(fp: fp, text: ns, lex: lex, cur: cur)
        let range = NSRange(location: open + 1, length: caret - open - 1)
        var items: [CompletionItem] = []
        var seen = Set<String>()
        if AppEnv.value("CE_COMPL_DEBUG") != nil { fputs("COMPL-DBG arrayCallable fqn=\(fqn) classes=\(ev.hierarchy(fqn).map { "\($0.fqn):\($0.methods.map { "\($0.name)/\($0.vis)" })" })\n", stderr) }
        for (depth, k) in ev.hierarchy(fqn).enumerated() {
            let base = k.fqn.hasSuffix("\\Controller") && depth > 0                   // the framework's base controller adds nothing useful
            for m in k.methods where m.vis == 0 && !m.name.hasPrefix("__") && seen.insert(m.name).inserted {
                var it = CI.make(m.name, .method, detail: "(" + m.params + ")" + (m.ret.isEmpty ? "" : ": " + m.ret),
                                 sort: (depth == 0 ? "0" : (base ? "2" : "1")) + m.name.lowercased(), doc: "\(k.name)::\(m.name)", range: range)
                it.priority = depth == 0 ? 10 : (base ? 60 : 30)
                items.append(it)
            }
        }
        if AppEnv.value("CE_COMPL_DEBUG") != nil { fputs("COMPL-DBG arrayCallable done \(items.count) items in \(Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)) ms\n", stderr) }
        return items.isEmpty ? nil : Result(items: items)
    }

    private static func usageKind(key: String, method: String, argIndex: Int, view: Bool) -> FUsageKind? {
        if argIndex == 0, routeCalls.contains(key) { return .route }
        if view { return .view }
        if argIndex == 0, configCalls.contains(key) { return .config }
        if argIndex == 0, envCalls.contains(key) { return .env }
        if argIndex == 0, langCalls.contains(key) { return .lang }
        if argIndex == 0 {
            if sessionCalls.contains(key) { return .session }
            if cacheCalls.contains(key) { return .cache }
            if gateCalls.contains(key) { return .gate }
            if key == "->middleware" || key == "middleware" { return .middleware }
        }
        return nil
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
            fp.usageView(file: ctx.fileURL, live: ns)?.apply(&items, kind: .rel, proximity: false)
            return Result(items: items)
        }
        let range = NSRange(location: contentStart, length: caret - contentStart)
        if case .table(let tbl) = t {
            items = (fp.schema()[tbl] ?? []).map { CI.make($0.name, .field, detail: $0.type, sort: "0" + $0.name.lowercased(), range: range) }
            fp.usageView(file: ctx.fileURL, live: ns)?.apply(&items, kind: .col, proximity: false)
            return Result(items: items)
        }
        model = model.flatMap { ev.isModel($0) ? $0 : nil }
        guard let m = model, let c = ev.hierarchy(m).first else { return nil }
        let tbl = fp.tableName(of: c)
        items = fp.columns(of: c).map { CI.make($0.name, .field, detail: $0.type, sort: "0" + $0.name.lowercased(), doc: "`\(tbl)`", range: range) }
        fp.usageView(file: ctx.fileURL, live: ns)?.apply(&items, kind: .col, proximity: false)
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
        if blade { return bladeClassItems(ctx, ns, caret: caret, fp: fp) }
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
            if case .staticRef(let f) = t, f.hasPrefix("Illuminate\\Support\\Facades\\") {
                var items = ev.facadeItems(f, prefix: prefix)
                if staticDollar { items = [] }
                return Result(items: items, incomplete: !prefix.isEmpty)
            }
            var via: String?
            if lo < opTok, lex.toks[lo].kind == .ident { via = lex.text(lo) }
            var seen = Set<String>()
            let same: Bool
            switch t {
            case .instance(let f), .staticRef(let f): same = f == cur?.fqn
            default: same = false
            }
            var items = ev.members(of: t, via: via, fromSameClass: same, staticDollar: staticDollar, onlyNames: &seen)
            var docFiltered = false
            switch t {                                                      // @method / @property tags (Carbon, IDE-helper annotated models)
            case .instance(let f): items += ev.docMemberItems(f, prefix: prefix, instance: true, seen: &seen); docFiltered = true
            case .staticRef(let f) where !staticDollar: items += ev.docMemberItems(f, prefix: prefix, instance: false, seen: &seen); docFiltered = true
            default: break
            }
            if staticDollar { let r = NSRange(location: pStart, length: caret - pStart); for i in items.indices { items[i].replaceRange = r } }
            // expected type of the whole `chain->|` expression (argument of the call being typed, `return`, typed assignment): lifts matching members
            let resolver = NPResolver(fp: fp, url: ctx.fileURL, text: ns, lex: lex, cur: cur)
            if let exp = resolver.expectedType(beforeToken: lo) {
                ev.annotate(&items, expected: exp)
                if ctx.smart { items += ev.smartChains(after: items, expected: exp) }
            }
            // how much this project talks to each member name (own-file use counts double): orders equal tiers
            if let uv = fp.usageView(file: ctx.fileURL, live: ns) { for i in items.indices { items[i].usage = uv.count(.member, items[i].label) } }
            return Result(items: items, incomplete: docFiltered && !prefix.isEmpty)
        }
        // `$|` where the surrounding code expects a type: the variables of the scope that have it (the plain variable list stays with PHPCompletion)
        if p > 0, ns.character(at: p - 1) == 36, !isColons, let typed = typedVariableItems(ns, ctx: ctx, prefixStart: p, caret: caret, fp: fp) { return typed }
        // Smart completion at the start of an expression: typed variables, chains, factories, enum cases, `new`
        if ctx.smart, !(p > 0 && [36, 92, 64].contains(ns.character(at: p - 1))), let sm = smartStartItems(ns, ctx: ctx, prefixStart: p, caret: caret, fp: fp) { return sm }
        // named arguments of the call being typed: `foo(me|` -> `message: `
        if !prefix.isEmpty || ctx.isManual, let named = FastRules.namedArgs(ctx, ns, caret: caret, fp: fp) {
            var items = named.items
            if !prefix.isEmpty, let f = prefix.unicodeScalars.first, CharacterSet.letters.contains(f), prefix.count >= 2 || ctx.isManual,
               p > 0, ns.character(at: p - 1) != 36, ns.character(at: p - 1) != 92 {
                items += classItems(prefix: prefix, ctx: ctx, ns: ns, range: ctx.prefixRange, fp: fp).items
            }
            return Result(items: items, incomplete: !prefix.isEmpty)
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
        return classItems(prefix: prefix, ctx: ctx, ns: ns, range: ctx.prefixRange, fp: fp, typed: classPositionExpectation(ns, before: t, prefixStart: p, ctx: ctx, fp: fp))
    }

    /// Types in docblock tags (`@param Fo|`, `@return Collection<int, Us|>`, `@var`, `@throws`): project / vendor / built-in classes, `use` added on accept.
    private static let docTypeRx = try! NSRegularExpression(pattern: #"@(?:param|return|var|throws|property|property-read|property-write|method|extends|implements|template-extends|mixin)\s+(?:[\w\\|<>\[\]?&,\s]*[|<,&?\s])?$"#)

    private static func docblockItems(_ ctx: CompletionContext, _ ns: NSString, caret: Int, fp: FastProject) -> Result {
        let prefix = ctx.prefix
        guard prefix.count >= 2 || ctx.isManual, let f = prefix.unicodeScalars.first, CharacterSet.letters.contains(f) else { return Result(items: []) }
        let before = CompletionLex.line(before: ctx.prefixRange.location, ns)
        // `@param Foo $x`: once a `$name` follows the type we are in the description
        guard !before.contains("$"), docTypeRx.firstMatch(in: before, range: NSRange(location: 0, length: (before as NSString).length)) != nil else { return Result(items: []) }
        if ctx.prefixRange.location > 0, ns.character(at: ctx.prefixRange.location - 1) == 92 { return Result(items: []) }
        return classItems(prefix: prefix, ctx: ctx, ns: ns, range: ctx.prefixRange, fp: fp)
    }

    /// Blade `{{ new Fo| }}` / `@php` blocks: classes inserted fully qualified (a Blade view has no `use` section to extend).
    private static func bladeClassItems(_ ctx: CompletionContext, _ ns: NSString, caret: Int, fp: FastProject) -> Result {
        let prefix = ctx.prefix
        guard prefix.count >= 2, let f = prefix.unicodeScalars.first, CharacterSet.letters.contains(f), CompletionLex.info(ctx).region == .bladeExpr else { return Result(items: []) }
        let p = ctx.prefixRange.location
        let t = CompletionLex.line(before: p, ns).trimmingCharacters(in: .whitespaces)
        guard p == 0 || ![36, 92, 64, 62, 45].contains(Int(ns.character(at: p - 1))) else { return Result(items: []) }
        guard t.hasSuffix("new") || t.hasSuffix("instanceof") || t.hasSuffix("(") || t.hasSuffix(",") else { return Result(items: []) }
        return classItems(prefix: prefix, ctx: ctx, ns: ns, range: ctx.prefixRange, fp: fp, qualified: true)
    }

    /// `new |`, `throw new |`, `catch (|`: what the surrounding code expects there (ev + expected type), nil when unknown.
    private static func classPositionExpectation(_ ns: NSString, before t: String, prefixStart p: Int, ctx: CompletionContext, fp: FastProject) -> (FTEval, FTExpected)? {
        let isNew = t.hasSuffix("new") && !(t.dropLast(3).last.map { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "$" } ?? false)
        let isCatch = t.hasSuffix("catch (") || t.hasSuffix("catch(")
        guard isNew || isCatch else { return nil }
        let lex = PHPLex(ns)
        let cur = FTParser.parse(ns, lex: lex)
        let ev = FTEval(fp: fp, text: ns, lex: lex, cur: cur)
        let at = ev.tokenIndex(atOrAfter: p)
        var lo = at
        if isNew { lo = at - 1; guard lo >= 0, lex.isIdent(lo, "new") else { return nil } }
        let r = NPResolver(fp: fp, url: ctx.fileURL, text: ns, lex: lex, cur: cur)
        guard let e = r.expectedType(beforeToken: lo) else { return nil }
        return (ev, e)
    }

    private static func smartStartItems(_ ns: NSString, ctx: CompletionContext, prefixStart p: Int, caret: Int, fp: FastProject) -> Result? {
        let lex = PHPLex(ns)
        let cur = FTParser.parse(ns, lex: lex)
        let r = NPResolver(fp: fp, url: ctx.fileURL, text: ns, lex: lex, cur: cur)
        let lo = r.ev.tokenIndex(atOrAfter: p)
        guard let exp = r.expectedType(beforeToken: lo) else { return nil }
        var items = r.smartExpressionItems(expected: exp, lo: lo, range: ctx.prefixRange, dollarTyped: false, caretPrefixIsName: true)
        items.removeAll { $0.typeMatch == 0 }
        return items.isEmpty ? nil : Result(items: items)
    }

    /// Variables in scope whose type fits the expected type at `$|` (typeMatch > 0); nil when nothing is expected / nothing fits.
    private static func typedVariableItems(_ ns: NSString, ctx: CompletionContext, prefixStart p: Int, caret: Int, fp: FastProject) -> Result? {
        let lex = PHPLex(ns)
        let cur = FTParser.parse(ns, lex: lex)
        let ev = FTEval(fp: fp, text: ns, lex: lex, cur: cur)
        let lo = ev.tokenIndex(atOrAfter: p - 1)
        let r = NPResolver(fp: fp, url: ctx.fileURL, text: ns, lex: lex, cur: cur)
        guard let exp = r.expectedType(beforeToken: lo) else { return nil }
        let range = NSRange(location: p - 1, length: caret - (p - 1))
        var items: [CompletionItem] = []
        if ctx.smart {
            items = r.smartExpressionItems(expected: exp, lo: lo, range: range, dollarTyped: true, caretPrefixIsName: true)
            items.removeAll { $0.typeMatch == 0 }
            return items.isEmpty ? nil : Result(items: items)
        }
        for v in r.typedVariables(atToken: lo) where v.valueType != nil {
            var it = CI.make(v.name, .variable, detail: v.valueType.map { ($0 as NSString).lastPathComponent } ?? "variable", range: range)
            it.valueType = v.valueType
            it.priority = 50
            items.append(it)
        }
        ev.annotate(&items, expected: exp)
        items.removeAll { $0.typeMatch == 0 }
        return items.isEmpty ? nil : Result(items: items)
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

    private static func classItems(prefix: String, ctx: CompletionContext, ns: NSString, range: NSRange, fp: FastProject, typed: (FTEval, FTExpected)? = nil, qualified: Bool = false) -> Result {
        let cands = candidates(prefix, fp: fp, limit: 40)
        guard !cands.isEmpty else { return Result(items: []) }
        let cur = FTParser.parse(ns)
        var count: [String: Int] = [:]
        for c in cands { count[c.short, default: 0] += 1 }
        var items: [CompletionItem] = []
        for c in cands {
            var insert = c.short
            var edits: [(range: NSRange, text: String)] = []
            if qualified { insert = "\\" + c.fqn } else if let cur { (insert, edits) = importEdit(c.fqn, short: c.short, cur: cur, text: ns) }
            let ambiguous = (count[c.short] ?? 0) > 1
            var it = CI.make(ambiguous ? "\(c.short) (\((c.fqn as NSString).deletingLastPathComponent.isEmpty ? namespaceOf(c.fqn) : namespaceOf(c.fqn)))" : c.short, c.kind,
                             detail: c.fqn, insert: insert, sort: (c.project ? "1" : "2") + c.short.lowercased(), doc: "`\(c.fqn)`\n\nAdds `use \(c.fqn);` when accepted.", range: range)
            if ambiguous { it.filterText = c.short }
            it.additionalEdits = edits
            // imported or same namespace: what the file already talks about; then the project, PHP built-ins, vendor packages
            let local = cur.map { namespaceOf(c.fqn) == ($0.ns.isEmpty ? "global" : $0.ns) || $0.uses.values.contains(c.fqn) } ?? false
            it.priority = local ? 0 : (c.project ? 1 : (c.builtin ? 2 : 3))
            it.valueType = c.fqn
            items.append(it)
        }
        if let (ev, e) = typed { ev.annotate(&items, expected: e) } else { for i in items.indices { items[i].valueType = nil } }
        return Result(items: items, incomplete: true)
    }

    private static func namespaceOf(_ fqn: String) -> String {
        guard let i = fqn.lastIndex(of: "\\") else { return "global" }
        return String(fqn[..<i])
    }

    /// (text to insert at the caret, extra edits) for referencing `fqn` from the file described by `cur`.
    static func importEdit(_ fqn: String, short: String, cur: FTClass, text: NSString? = nil) -> (String, [(range: NSRange, text: String)]) {
        // the real planner (alias / same namespace / conflict aware, sorted among the existing imports, `declare(strict_types)` aware, CRLF)
        if let text {
            switch PHPImports.plan(fqn: fqn, short: short, in: text, cur: cur) {
            case .edit(let e): return (short, [(e.range, e.text)])
            case .sameNamespace: return (short, [])
            case .alreadyImported: return (cur.uses.first(where: { $0.value == fqn })?.key ?? short, [])
            case .conflict: return ("\\" + fqn, [])
            case .unsupported: break
            }
        }
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
