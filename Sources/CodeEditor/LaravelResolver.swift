import Foundation

/// What the token under a position refers to: the highlighted range plus where it leads.
struct LaravelRef {
    let range: NSRange
    let targets: [LaravelTarget]
}

/// Static resolution of Laravel references (views, routes, config, lang, components, controllers, ...) in
/// PHP / Blade / Vue / JS source text. Pure: reads project files, never runs the app.
enum LaravelResolver {
    enum FileKind { case php, blade, js }

    static func fileKind(_ url: URL) -> FileKind? {
        let n = url.lastPathComponent.lowercased()
        if n.hasSuffix(".blade.php") { return .blade }
        switch url.pathExtension.lowercased() {
        case "php": return .php
        case "vue", "js", "jsx", "ts", "tsx", "mjs", "svelte": return .js
        default: return nil
        }
    }

    // MARK: Entry

    static func resolve(text ns: NSString, offset: Int, file: URL, project p: LaravelProject) -> LaravelRef? {
        guard let kind = fileKind(file), offset >= 0, offset <= ns.length, ns.length > 0 else { return nil }
        let probe = min(offset, ns.length - 1)
        let lineRange = ns.lineRange(for: NSRange(location: probe, length: 0))
        // Window of the line around the offset (guards against minified one-line files).
        let lo = max(lineRange.location, offset - 1500), hi = min(NSMaxRange(lineRange), offset + 1500)
        let win = NSRange(location: lo, length: hi - lo)
        let line = ns.substring(with: win) as NSString
        let rel = offset - lo
        if isComment(ns, offset: offset, lineStart: lineRange.location, kind: kind) { return nil }

        // 1. Blade component / Livewire tags.
        if kind == .blade || kind == .php, let r = componentTag(line, rel, p, winLoc: lo) { return r }

        // 2. String literals.
        for cand in stringCandidates(line, rel) {
            let abs = NSRange(location: lo + cand.open + 1, length: cand.close - cand.open - 1)
            guard abs.length > 0 else { continue }
            let value = line.substring(with: NSRange(location: cand.open + 1, length: cand.close - cand.open - 1))
            let targets = stringTargets(value: value, ns: ns, openAbs: lo + cand.open, kind: kind, file: file, p)
            if !targets.isEmpty { return LaravelRef(range: abs, targets: targets) }
        }

        // 3. `Name::class`
        if let r = classConstant(line, rel, ns, p, winLoc: lo) { return r }
        return nil
    }

    // MARK: Comments

    private static func isComment(_ ns: NSString, offset: Int, lineStart: Int, kind: FileKind) -> Bool {
        let prefix = ns.substring(with: NSRange(location: lineStart, length: min(offset, ns.length) - lineStart)) as NSString
        let trimmed = prefix.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*") || trimmed.hasPrefix("{{--") || trimmed.hasPrefix("<!--") { return true }
        if kind == .php, trimmed.hasPrefix("#"), !trimmed.hasPrefix("#[") { return true }
        func quotesEven(_ upTo: Int) -> Bool {
            var s = 0, d = 0, i = 0
            while i < upTo {
                let c = prefix.character(at: i)
                if c == 92 { i += 2; continue }
                if c == 39, d % 2 == 0 { s += 1 } else if c == 34, s % 2 == 0 { d += 1 }
                i += 1
            }
            return s % 2 == 0 && d % 2 == 0
        }
        var r = prefix.range(of: "//")
        while r.location != NSNotFound {
            let before: unichar = r.location > 0 ? prefix.character(at: r.location - 1) : 0
            if before != 58, quotesEven(r.location), kind != .blade || true { return true }
            let next = r.location + 2
            r = prefix.range(of: "//", options: [], range: NSRange(location: next, length: prefix.length - next))
        }
        if kind == .php {
            var h = prefix.range(of: "#")
            while h.location != NSNotFound {
                let nextIsBracket = h.location + 1 < prefix.length && prefix.character(at: h.location + 1) == 91
                if !nextIsBracket, quotesEven(h.location) { return true }
                let next = h.location + 1
                h = prefix.range(of: "#", options: [], range: NSRange(location: next, length: prefix.length - next))
            }
        }
        // Multi-line block comments: last "/*" (or "{{--" / "<!--") before the offset not closed before it.
        let back = max(0, offset - 4000)
        let window = NSRange(location: back, length: min(offset, ns.length) - back)
        for (open, close) in [("/*", "*/"), ("{{--", "--}}"), ("<!--", "-->")] where kind != .js || open != "{{--" {
            let o = ns.range(of: open, options: .backwards, range: window)
            guard o.location != NSNotFound else { continue }
            let afterOpen = NSRange(location: NSMaxRange(o), length: window.location + window.length - NSMaxRange(o))
            if ns.range(of: close, options: [], range: afterOpen).location != NSNotFound { continue }
            // Ignore an opener that sits inside a string on its own line.
            let ls = ns.lineRange(for: NSRange(location: o.location, length: 0)).location
            let pre = ns.substring(with: NSRange(location: ls, length: o.location - ls)) as NSString
            var s = 0, d = 0
            for i in 0..<pre.length { let c = pre.character(at: i); if c == 39 { s += 1 } else if c == 34 { d += 1 } }
            if s % 2 == 0, d % 2 == 0 { return true }
        }
        return false
    }

    // MARK: Strings

    struct StringCand { let open: Int; let close: Int; let quote: unichar }

    /// Plausible string literals around `rel` (indexes within `line`), innermost first.
    static func stringCandidates(_ line: NSString, _ rel: Int) -> [StringCand] {
        var out: [StringCand] = []
        let n = line.length
        func isQuote(_ i: Int, _ q: unichar) -> Bool {
            guard i >= 0, i < n, line.character(at: i) == q else { return false }
            var b = 0, k = i - 1
            while k >= 0, line.character(at: k) == 92 { b += 1; k -= 1 }
            return b % 2 == 0
        }
        for q: unichar in [39, 34, 96] {
            var opens: [Int] = [], closes: [Int] = []
            // quote under the caret may open or close
            if rel < n, isQuote(rel, q) { opens.append(rel); closes.append(rel) }
            var a = rel - 1
            while a >= 0, !isQuote(a, q) { a -= 1 }
            if a >= 0, rel - a < 400 { opens.append(a) }
            var b = rel + 1
            while b < n, !isQuote(b, q) { b += 1 }
            if b < n, b - rel < 400 { closes.append(b) }
            for o in opens {
                for c in closes where c > o && (c - o) < 400 {
                    // the pair must contain no other unescaped same-type quote
                    var clean = true
                    var k = o + 1
                    while k < c { if isQuote(k, q) { clean = false; break }; k += 1 }
                    if clean, atArgumentPosition(line, o) { out.append(StringCand(open: o, close: c, quote: q)) }
                }
            }
        }
        return out.sorted { ($0.close - $0.open) < ($1.close - $1.open) }
    }

    private static func atArgumentPosition(_ line: NSString, _ open: Int) -> Bool {
        var i = open - 1
        while i >= 0, line.character(at: i) == 32 || line.character(at: i) == 9 { i -= 1 }
        if i < 0 { return true }   // string starts the line: continuation of a multi-line call
        let c = line.character(at: i)
        if c == 40 || c == 44 || c == 91 || c == 58 { return true }    // ( , [ :
        if c == 61, i == 0 || ![33, 60, 62, 61].contains(line.character(at: i - 1)) { return true }   // simple assignment
        if c == 62, i > 0, line.character(at: i - 1) == 61 { return true }   // =>
        // `from 'x'` / `import 'x'`
        let head = line.substring(to: i + 1)
        return head.hasSuffix("from") || head.hasSuffix("import")
    }

    // MARK: Call context

    struct CallContext {
        var key: String         // normalised lowercase call key, e.g. "view", "route::view", "->route", "@include"
        var argIndex: Int
        var inArray: Bool
    }

    /// Finds the call enclosing the string that starts at `openAbs`, scanning backwards (up to a few lines).
    static func callContext(_ ns: NSString, openAbs: Int) -> CallContext? {
        let start = max(0, openAbs - 2500)
        let u = ns.substring(with: NSRange(location: start, length: openAbs - start)) as NSString
        var depth = 0, commas = 0, inArray = false
        var i = u.length - 1
        var lines = 0
        while i >= 0 {
            let c = u.character(at: i)
            if c == 10 { lines += 1; if lines > 8 { return nil } }
            if c == 39 || c == 34 {
                var j = i - 1
                while j >= 0, !(u.character(at: j) == c && (j == 0 || u.character(at: j - 1) != 92)) { j -= 1 }
                i = j >= 0 ? j - 1 : i - 1
                continue
            }
            switch c {
            case 41, 93, 125: depth += 1
            case 40, 91, 123:
                if depth > 0 { depth -= 1; break }
                if c == 123 { return nil }
                if c == 91 { inArray = true; commas = 0; break }
                let key = callKey(u, parenAt: i)
                if key == "array" { inArray = true; commas = 0; break }
                if let key { return CallContext(key: key, argIndex: commas, inArray: inArray) }
                commas = 0
            case 44: if depth == 0 { commas += 1 }
            case 59: if depth == 0 { return nil }
            default: break
            }
            i -= 1
        }
        return nil
    }

    private static func isWordChar(_ c: unichar) -> Bool {
        (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 92 || c == 64 || c >= 0x80
    }

    private static func callKey(_ u: NSString, parenAt p: Int) -> String? {
        var i = p - 1
        while i >= 0, u.character(at: i) == 32 || u.character(at: i) == 9 || u.character(at: i) == 10 { i -= 1 }
        let end = i + 1
        while i >= 0, isWordChar(u.character(at: i)) { i -= 1 }
        guard end > i + 1 else { return nil }
        var name = u.substring(with: NSRange(location: i + 1, length: end - i - 1))
        if name.hasPrefix("\\") { name.removeFirst() }
        let method = name.lowercased()
        var j = i
        while j >= 0, u.character(at: j) == 32 { j -= 1 }
        if j >= 1, u.character(at: j) == 58, u.character(at: j - 1) == 58 {         // ::
            var k = j - 2
            let e2 = k + 1
            while k >= 0, isWordChar(u.character(at: k)) { k -= 1 }
            let cls = u.substring(with: NSRange(location: k + 1, length: e2 - k - 1))
            let last = cls.split(separator: "\\").last.map(String.init) ?? cls
            return last.lowercased() + "::" + method
        }
        if j >= 1, u.character(at: j) == 62, u.character(at: j - 1) == 45 { return "->" + method }   // ->
        if method == "function" || method == "fn" || method == "if" || method == "foreach" || method == "while" || method == "for"
            || method == "switch" || method == "match" || method == "catch" { return nil }
        return method
    }

    // MARK: String -> targets

    private static let viewCalls: [String: Int] = [
        "view": 0, "view::make": 0, "view::exists": 0, "view::first": 0, "view::composer": 0, "view::creator": 0, "route::view": 1,
        "@include": 0, "@includeif": 0, "@includewhen": 1, "@includeunless": 1, "@includefirst": 0, "@includeisolated": 0,
        "@extends": 0, "@component": 0, "@each": 0, "@embed": 0, "@componentfirst": 0, "->view": 0, "->markdown": 0,
        "response::view": 0,
    ]
    private static let inertiaCalls: [String: Int] = ["inertia::render": 0, "inertia": 0, "route::inertia": 1, "inertia::modal": 0]
    private static let routeCalls: Set<String> = ["route", "to_route", "route::has", "->route", "url::route", "redirect::route",
                                                  "route::currentroutenamed", "->routeis", "route::is"]
    private static let configCalls: Set<String> = ["config", "config::get", "config::has", "config::string", "config::integer",
                                                   "config::boolean", "config::array", "config::float", "config::set"]
    private static let envCalls: Set<String> = ["env", "env::get"]
    private static let langCalls: Set<String> = ["__", "trans", "trans_choice", "@lang", "@choice", "lang::get", "lang::has", "lang::choice",
                                                 "lang::hasforlocale", "->trans", "$t", "t"]
    private static let publicAssetCalls: Set<String> = ["asset", "secure_asset", "mix", "public_path"]
    private static let rootAssetCalls: Set<String> = ["vite::asset", "@vite", "vite::content", "base_path"]
    private static let pathCalls: [String: String] = ["resource_path": "resources", "app_path": "app", "config_path": "config",
                                                      "database_path": "database", "storage_path": "storage", "lang_path": "lang"]
    private static let gateCalls: Set<String> = ["gate::allows", "gate::denies", "gate::check", "gate::any", "gate::none", "gate::authorize",
                                                 "gate::inspect", "gate::has", "@can", "@cannot", "@canany", "->can", "->cannot", "->cant"]
    private static let middlewareCalls: Set<String> = ["->middleware", "route::middleware", "->withoutmiddleware", "route::withoutmiddleware",
                                                       "middleware"]
    private static let livewireCalls: Set<String> = ["@livewire", "livewire::mount"]
    private static let verbCalls: Set<String> = ["route::get", "route::post", "route::put", "route::patch", "route::delete",
                                                 "route::options", "route::any"]

    static func stringTargets(value: String, ns: NSString, openAbs: Int, kind: FileKind, file: URL, _ p: LaravelProject) -> [LaravelTarget] {
        guard value.count <= 300, !value.contains("$"), !value.contains("{{"), !value.contains("\n") else { return [] }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        let ctx = callContext(ns, openAbs: openAbs)

        // JS imports.
        if kind == .js, isImportString(ns, openAbs: openAbs, ctx: ctx) {
            return resolveImport(value, from: file, p)
        }

        var out: [LaravelTarget] = []
        func add(_ ts: [LaravelTarget]) { for t in ts where !out.contains(t) { out.append(t) } }

        if let ctx {
            let key = ctx.key
            if let idx = viewCalls[key], ctx.argIndex == idx, !ctx.inArray || ["view::first", "@includefirst", "@componentfirst"].contains(key) {
                add(viewTargets(value, p))
            } else if let idx = inertiaCalls[key], ctx.argIndex == idx, !ctx.inArray {
                add(inertiaTargets(value, p))
            } else if routeCalls.contains(key), ctx.argIndex == 0, !ctx.inArray {
                add(routeTargets(value, p))
            } else if configCalls.contains(key), ctx.argIndex == 0, !ctx.inArray {
                add(configTargets(value, p))
            } else if envCalls.contains(key), ctx.argIndex == 0, !ctx.inArray {
                add(envTargets(value, p))
            } else if langCalls.contains(key), ctx.argIndex == 0, !ctx.inArray {
                add(langTargets(value, p))
            } else if publicAssetCalls.contains(key), ctx.argIndex == 0, !ctx.inArray {
                add(publicTargets(value, key == "public_path", p))
            } else if rootAssetCalls.contains(key), ctx.argIndex == 0 {
                add(rootTargets(value, p))
            } else if let base = pathCalls[key], ctx.argIndex == 0, !ctx.inArray {
                add(pathTargets(base, value, p))
            } else if gateCalls.contains(key), ctx.argIndex == 0 {
                add(gateTargets(value, p))
            } else if middlewareCalls.contains(key) {
                add(middlewareTargets(value, p))
            } else if livewireCalls.contains(key), ctx.argIndex == 0, !ctx.inArray {
                add(livewireTargets(value, p))
            } else if verbCalls.contains(key) || key == "route::match" || key == "->uses" {
                // Route::controller(X::class)->group(fn () => Route::get('/', 'show'))
                if ctx.argIndex >= (key == "route::match" ? 2 : 1), looksLikeMethodName(value) {
                    if let (cls, _) = enclosingController(ns, before: openAbs, p) { add(controllerMethod(cls, value, p)) }
                }
            }
        }
        // `[UserController::class, 'show']`
        if out.isEmpty, looksLikeMethodName(value), let cls = classBeforeInArray(ns, openAbs: openAbs) {
            add(controllerMethod(cls, value, p, fileText: ns))
        }
        if out.isEmpty { add(classStringTargets(value, ns, p)) }
        return out
    }

    private static func looksLikeMethodName(_ s: String) -> Bool {
        guard let f = s.unicodeScalars.first, CharacterSet.letters.contains(f) || f == "_" else { return false }
        return s.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "_" }
    }

    /// `Foo::class,` directly before the string inside the same array.
    private static func classBeforeInArray(_ ns: NSString, openAbs: Int) -> String? {
        let start = max(0, openAbs - 300)
        let s = ns.substring(with: NSRange(location: start, length: openAbs - start)) as NSString
        guard let re = try? NSRegularExpression(pattern: #"([\\\w]+)::class\s*,\s*$"#),
              let m = re.firstMatch(in: s as String, range: NSRange(location: 0, length: s.length)) else { return nil }
        return s.substring(with: m.range(at: 1))
    }

    /// `Route::controller(X::class)` that precedes the position in the same file.
    private static func enclosingController(_ ns: NSString, before: Int, _ p: LaravelProject) -> (String, Int)? {
        let start = max(0, before - 20_000)
        let s = ns.substring(with: NSRange(location: start, length: before - start))
        guard let re = try? NSRegularExpression(pattern: #"controller\(\s*([\\\w]+)::class\s*\)"#) else { return nil }
        let ms = re.matches(in: s, range: NSRange(location: 0, length: (s as NSString).length))
        guard let m = ms.last else { return nil }
        return ((s as NSString).substring(with: m.range(at: 1)), m.range.location)
    }

    // MARK: Views

    static func viewTargets(_ name: String, _ p: LaravelProject) -> [LaravelTarget] {
        guard let f = p.viewFile(name) else { return [] }
        return [p.target(f)]
    }

    static func inertiaTargets(_ name: String, _ p: LaravelProject) -> [LaravelTarget] {
        guard !name.contains(" ") else { return [] }
        let variants = Set([name, name.replacingOccurrences(of: ".", with: "/")])
        for dir in ["resources/js/Pages", "resources/js/pages", "resources/ts/Pages", "resources/ts/pages", "resources/js/Views"] {
            for v in variants {
                for ext in ["vue", "jsx", "tsx", "js", "ts", "svelte"] {
                    let f = p.abs(dir + "/" + v + "." + ext)
                    if LaravelFS.isFile(f) { return [p.target(f)] }
                }
            }
        }
        // A Blade view of that name is a fine fallback (Inertia disabled / shared names).
        return []
    }

    // MARK: Routes

    static func routeTargets(_ name: String, _ p: LaravelProject) -> [LaravelTarget] {
        guard let decl = LaravelRouteIndex.routes(p)[name] else { return [] }
        var out = [p.target(decl.file, line: decl.line, column: decl.col)]
        if let exact = LaravelRouteIndex.artisanRoutes(p)?[name], !out.contains(exact) { out.append(exact) }
        return out
    }

    // MARK: Config / env / lang

    private static func keyTable(_ p: LaravelProject, file: String) -> [String: PHPArrayKeys.Loc] {
        p.memo("keys:" + file, stamp: LaravelFS.mtime(file)) { () -> [String: PHPArrayKeys.Loc] in
            guard let t = LaravelFS.text(file) else { return [:] }
            return PHPArrayKeys.parse(PHPLex(t))
        }
    }

    static func configTargets(_ key: String, _ p: LaravelProject) -> [LaravelTarget] {
        var segs = key.split(separator: ".", omittingEmptySubsequences: true).map(String.init)
        guard let first = segs.first, first.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else { return [] }
        segs.removeFirst()
        var file = p.abs("config/\(first).php")
        if !LaravelFS.isFile(file) {
            guard let vendor = p.vendorPackages.lazy.map({ $0 + "/config/\(first).php" }).first(where: LaravelFS.isFile) else { return [] }
            file = vendor
        }
        if segs.isEmpty { return [p.target(file)] }
        let table = keyTable(p, file: file)
        var n = segs.count
        while n > 0 {
            if let loc = table[segs[0..<n].joined(separator: ".")] { return [p.target(file, line: loc.line, column: loc.col)] }
            n -= 1
        }
        return []
    }

    static func envTargets(_ key: String, _ p: LaravelProject) -> [LaravelTarget] {
        guard !key.isEmpty, key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return [] }
        for name in [".env", ".env.example"] {
            let f = p.abs(name)
            let table: [String: Int] = p.memo("env:" + f, stamp: LaravelFS.mtime(f)) {
                var t: [String: Int] = [:]
                guard let text = LaravelFS.text(f) else { return t }
                var n = 0
                text.enumerateLines { line, _ in
                    n += 1
                    var s = Substring(line).drop(while: { $0 == " " || $0 == "\t" })
                    if s.hasPrefix("export ") { s = s.dropFirst(7) }
                    guard !s.hasPrefix("#"), let eq = s.firstIndex(of: "=") else { return }
                    let k = s[..<eq].trimmingCharacters(in: .whitespaces)
                    if t[k] == nil { t[k] = n }
                }
                return t
            }
            if let line = table[key] { return [p.target(f, line: line)] }
        }
        return []
    }

    private static func locales(_ p: LaravelProject) -> [String] {
        var order: [String] = []
        if let t = LaravelFS.text(p.abs("config/app.php")),
           let re = try? NSRegularExpression(pattern: #"'locale'\s*=>\s*(?:env\(\s*'[^']*'\s*,\s*)?'([\w-]+)'"#),
           let m = re.firstMatch(in: t as String, range: NSRange(location: 0, length: t.length)) {
            order.append(t.substring(with: m.range(at: 1)))
        }
        order.append("en")
        for base in ["lang", "resources/lang"] {
            for e in LaravelFS.list(p.abs(base)) where LaravelFS.isDir(p.abs(base + "/" + e)) { order.append(e) }
        }
        var seen = Set<String>()
        return order.filter { seen.insert($0).inserted }
    }

    static func langTargets(_ key: String, _ p: LaravelProject) -> [LaravelTarget] {
        let hasSpace = key.contains(" ")
        var pkg: String?
        var rest = key
        if let r = key.range(of: "::") { pkg = String(key[..<r.lowerBound]); rest = String(key[r.upperBound...]) }
        let bases = ["lang", "resources/lang"]
        let locs = locales(p)

        func php() -> [LaravelTarget] {
            let segs = rest.split(separator: ".", omittingEmptySubsequences: true).map(String.init)
            guard segs.count >= 2, !hasSpace else { return [] }
            let file = segs[0], path = segs[1...].joined(separator: ".")
            for loc in locs {
                var cands: [String] = []
                if let pkg {
                    for b in bases { cands.append(p.abs("\(b)/vendor/\(pkg)/\(loc)/\(file).php")) }
                    for d in p.vendorPackages where (d as NSString).lastPathComponent.contains(pkg) {
                        cands.append("\(d)/resources/lang/\(loc)/\(file).php"); cands.append("\(d)/lang/\(loc)/\(file).php")
                    }
                } else {
                    for b in bases { cands.append(p.abs("\(b)/\(loc)/\(file).php")) }
                }
                for f in cands where LaravelFS.isFile(f) {
                    if let l = keyTable(p, file: f)[path] { return [p.target(f, line: l.line, column: l.col)] }
                }
            }
            return []
        }
        func json() -> [LaravelTarget] {
            guard pkg == nil else { return [] }
            let needle = "\"" + key.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
            for loc in locs {
                for b in bases {
                    let f = p.abs("\(b)/\(loc).json")
                    guard let t = LaravelFS.text(f) else { continue }
                    var from = 0
                    while from < t.length {
                        let r = t.range(of: needle, options: [], range: NSRange(location: from, length: t.length - from))
                        guard r.location != NSNotFound else { break }
                        // must be followed by a colon
                        var e = NSMaxRange(r)
                        while e < t.length, [32, 9, 10, 13].contains(t.character(at: e)) { e += 1 }
                        if e < t.length, t.character(at: e) == 58 {
                            let (l, c) = LaravelFS.lineCol(t, r.location + 1)
                            return [p.target(f, line: l, column: c)]
                        }
                        from = NSMaxRange(r)
                    }
                }
            }
            return []
        }
        return hasSpace ? (json() + php()) : (php() + json())
    }

    // MARK: Assets / paths

    static func publicTargets(_ value: String, _ isPublicPath: Bool, _ p: LaravelProject) -> [LaravelTarget] {
        var rel = value
        guard !rel.hasPrefix("http"), !rel.hasPrefix("//"), !rel.contains("..") else { return [] }
        if let q = rel.firstIndex(where: { $0 == "?" || $0 == "#" }) { rel = String(rel[..<q]) }
        rel = rel.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !rel.isEmpty else { return [] }
        for base in ["public", "public/build", "storage/app/public", "resources"] {
            let f = p.abs(base + "/" + rel)
            if LaravelFS.isFile(f) { return [p.target(f)] }
        }
        return []
    }

    static func rootTargets(_ value: String, _ p: LaravelProject) -> [LaravelTarget] {
        guard !value.hasPrefix("http"), !value.contains("..") else { return [] }
        let rel = value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !rel.isEmpty else { return [] }
        let f = p.abs(rel)
        return LaravelFS.isFile(f) ? [p.target(f)] : (LaravelFS.isFile(p.abs("public/" + rel)) ? [p.target(p.abs("public/" + rel))] : [])
    }

    static func pathTargets(_ base: String, _ value: String, _ p: LaravelProject) -> [LaravelTarget] {
        guard !value.contains("..") else { return [] }
        let rel = value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let f = p.abs(base + (rel.isEmpty ? "" : "/" + rel))
        return LaravelFS.isFile(f) ? [p.target(f)] : []
    }

    // MARK: Gates / middleware

    static func gateTargets(_ ability: String, _ p: LaravelProject) -> [LaravelTarget] {
        let files = p.providerFiles
        let table: [String: (String, Int, Int)] = p.memo("gates", stamp: p.stamp(files)) {
            var t: [String: (String, Int, Int)] = [:]
            guard let re = try? NSRegularExpression(pattern: #"Gate::define\(\s*['"]([^'"]+)['"]"#) else { return t }
            for f in files {
                guard let text = LaravelFS.text(f) else { continue }
                re.enumerateMatches(in: text as String, range: NSRange(location: 0, length: text.length)) { m, _, _ in
                    guard let m else { return }
                    let (l, c) = LaravelFS.lineCol(text, m.range(at: 1).location)
                    t[text.substring(with: m.range(at: 1))] = (f, l, c)
                }
            }
            return t
        }
        guard let e = table[ability] else { return [] }
        return [p.target(e.0, line: e.1, column: e.2)]
    }

    static func middlewareTargets(_ value: String, _ p: LaravelProject) -> [LaravelTarget] {
        let name = String(value.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        if name == "can", let rest = value.split(separator: ":", maxSplits: 1).last, value.contains(":") {
            return gateTargets(String(rest.split(separator: ",").first ?? ""), p)
        }
        guard !name.isEmpty else { return [] }
        let files = [p.abs("app/Http/Kernel.php"), p.abs("bootstrap/app.php")]
        let table: [String: (file: String, line: Int, col: Int, cls: String?)] = p.memo("middleware", stamp: p.stamp(files)) {
            var t: [String: (file: String, line: Int, col: Int, cls: String?)] = [:]
            guard let re = try? NSRegularExpression(pattern: #"['"]([\w.-]+)['"]\s*=>\s*(?:([\\\w]+)::class|\[)"#) else { return t }
            for f in files {
                guard let text = LaravelFS.text(f) else { continue }
                re.enumerateMatches(in: text as String, range: NSRange(location: 0, length: text.length)) { m, _, _ in
                    guard let m else { return }
                    let (l, c) = LaravelFS.lineCol(text, m.range(at: 1).location)
                    var cls: String?
                    if m.range(at: 2).location != NSNotFound {
                        cls = p.resolveClass(text.substring(with: m.range(at: 2)), fileText: text).first
                    }
                    t[text.substring(with: m.range(at: 1))] = (f, l, c, cls)
                }
            }
            return t
        }
        guard let e = table[name] else { return [] }
        if let cls = e.cls { return [p.target(cls, line: p.classDeclaration(file: cls).0, column: p.classDeclaration(file: cls).1)] }
        return [p.target(e.file, line: e.line, column: e.col)]
    }

    // MARK: Classes / controllers

    static func controllerMethod(_ written: String, _ method: String, _ p: LaravelProject, fileText: NSString? = nil) -> [LaravelTarget] {
        let files = p.resolveClass(written, fileText: fileText, extraNamespaces: ["App\\Http\\Controllers"])
        guard let f = files.first else { return [] }
        if let loc = p.methodLocation(file: f, method: method) { return [p.target(f, line: loc.0, column: loc.1)] }
        // Method inherited / missing: land on the class declaration.
        let d = p.classDeclaration(file: f)
        return [p.target(f, line: d.0, column: d.1)]
    }

    /// `'UserController@show'`, `'App\\Models\\User'`.
    static func classStringTargets(_ value: String, _ ns: NSString, _ p: LaravelProject) -> [LaravelTarget] {
        let v = value.replacingOccurrences(of: "\\\\", with: "\\")
        guard let re = try? NSRegularExpression(pattern: #"^\\?([A-Za-z_][\w]*(?:\\[A-Za-z_]\w*)*)(?:@(\w+))?$"#),
              let m = re.firstMatch(in: v, range: NSRange(location: 0, length: (v as NSString).length)) else { return [] }
        let cls = (v as NSString).substring(with: m.range(at: 1))
        let hasMethod = m.range(at: 2).location != NSNotFound
        // Plain words ("users") are not class references: need '@method' or a namespace separator + capital.
        guard hasMethod || (cls.contains("\\") && cls.first!.isUppercase) else { return [] }
        let prefix = v.hasPrefix("\\") ? "\\" : ""
        if hasMethod { return controllerMethod(prefix + cls, (v as NSString).substring(with: m.range(at: 2)), p, fileText: ns) }
        guard let f = p.resolveClass(prefix + cls, fileText: ns).first else { return [] }
        let d = p.classDeclaration(file: f)
        return [p.target(f, line: d.0, column: d.1)]
    }

    private static func classConstant(_ line: NSString, _ rel: Int, _ ns: NSString, _ p: LaravelProject, winLoc: Int) -> LaravelRef? {
        guard let re = try? NSRegularExpression(pattern: #"([\\A-Za-z_][\\\w]*)::class\b"#) else { return nil }
        for m in re.matches(in: line as String, range: NSRange(location: 0, length: line.length)) {
            let r = m.range(at: 1)
            guard rel >= r.location, rel <= NSMaxRange(r) else { continue }
            let name = line.substring(with: r)
            guard let f = p.resolveClass(name, fileText: ns).first else { return nil }
            let d = p.classDeclaration(file: f)
            return LaravelRef(range: NSRange(location: winLoc + r.location, length: r.length),
                              targets: [p.target(f, line: d.0, column: d.1)])
        }
        return nil
    }

    // MARK: Components

    private static func studly(_ s: String) -> String {
        s.split(whereSeparator: { $0 == "-" || $0 == "_" }).map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
    }
    private static func studlyPath(_ dotted: String, sep: String) -> String {
        dotted.split(separator: ".").map { studly(String($0)) }.joined(separator: sep)
    }

    private static func componentTag(_ line: NSString, _ rel: Int, _ p: LaravelProject, winLoc: Int) -> LaravelRef? {
        guard let re = try? NSRegularExpression(pattern: #"</?((?:x-|livewire:)[\w.:\-]+)"#) else { return nil }
        for m in re.matches(in: line as String, range: NSRange(location: 0, length: line.length)) {
            let r = m.range(at: 1)
            guard rel >= r.location, rel <= NSMaxRange(r) else { continue }
            let tag = line.substring(with: r)
            let targets: [LaravelTarget]
            if tag.hasPrefix("livewire:") { targets = livewireTargets(String(tag.dropFirst(9)), p) }
            else { targets = componentTargets(String(tag.dropFirst(2)), p) }
            if targets.isEmpty { return nil }
            return LaravelRef(range: NSRange(location: winLoc + r.location, length: r.length), targets: targets)
        }
        return nil
    }

    static func componentTargets(_ name: String, _ p: LaravelProject) -> [LaravelTarget] {
        if name.hasPrefix("slot") || name.hasPrefix("dynamic-component") || name.isEmpty { return [] }
        var prefix: String?
        var comp = name
        if let r = name.range(of: "::") { prefix = String(name[..<r.lowerBound]); comp = String(name[r.upperBound...]) }
        guard !comp.isEmpty else { return [] }
        let reg = p.componentRegistry
        var out: [LaravelTarget] = []

        // Class-based.
        var classFile: String?
        if let fq = reg.aliases[name] { classFile = p.classFile(fq) }
        if classFile == nil, let prefix {
            for nsName in reg.namespaces[prefix] ?? [] {
                if let f = p.classFile(nsName + "\\" + studlyPath(comp, sep: "\\")) { classFile = f; break }
            }
        }
        if classFile == nil, prefix == nil {
            let direct = p.abs("app/View/Components/" + studlyPath(comp, sep: "/") + ".php")
            classFile = LaravelFS.isFile(direct) ? direct : p.classFile("App\\View\\Components\\" + studlyPath(comp, sep: "\\"))
        }
        if let cf = classFile {
            let d = p.classDeclaration(file: cf)
            out.append(p.target(cf, line: d.0, column: d.1))
            // The class's view: view('...') in render(), else the default components.* view.
            var viewName: String?
            if let t = LaravelFS.text(cf), let re = try? NSRegularExpression(pattern: #"\bview\(\s*['"]([^'"]+)['"]"#),
               let m = re.firstMatch(in: t as String, range: NSRange(location: 0, length: t.length)) {
                viewName = t.substring(with: m.range(at: 1))
            }
            let candidates = [viewName, "components." + comp.replacingOccurrences(of: "/", with: ".")].compactMap { $0 }
            for v in candidates { if let f = p.viewFile(v) { out.append(p.target(f)); break } }
            return out
        }

        // Anonymous.
        let rel = comp.replacingOccurrences(of: ".", with: "/")
        let leaf = rel.split(separator: "/").last.map(String.init) ?? rel
        var dirs: [String] = []
        if let prefix {
            dirs.append(p.abs("resources/views/vendor/\(prefix)/components"))
            for d in p.viewDirs(namespace: prefix).dropFirst() { dirs.append(d + "/components") }
            for a in reg.anonymous where a.prefix == prefix { dirs.append(a.dir) }
        } else {
            dirs.append(p.abs("resources/views/components"))
            for a in reg.anonymous where a.prefix == nil { dirs.append(a.dir) }
        }
        for d in dirs {
            for cand in ["\(rel)", "\(rel)/index", "\(rel)/\(leaf)"] {
                for ext in [".blade.php", ".php"] {
                    let f = d + "/" + cand + ext
                    if LaravelFS.isFile(f) { return [p.target(f)] }
                }
            }
        }
        return []
    }

    static func livewireTargets(_ name: String, _ p: LaravelProject) -> [LaravelTarget] {
        guard !name.contains("::"), !name.isEmpty, !name.hasPrefix("is"), name != "styles", name != "scripts" else { return [] }
        let rel = studlyPath(name, sep: "/")
        for base in ["app/Livewire", "app/Http/Livewire"] {
            let f = p.abs(base + "/" + rel + ".php")
            if LaravelFS.isFile(f) {
                let d = p.classDeclaration(file: f)
                return [p.target(f, line: d.0, column: d.1)]
            }
        }
        // Volt / view-only component.
        for v in ["livewire." + name, "components." + name, "pages." + name] { if let f = p.viewFile(v) { return [p.target(f)] } }
        return []
    }

    // MARK: JS imports

    private static func isImportString(_ ns: NSString, openAbs: Int, ctx: CallContext?) -> Bool {
        if let ctx, ctx.key == "require" || ctx.key == "import" { return true }
        let start = max(0, openAbs - 400)
        let head = (ns.substring(with: NSRange(location: start, length: openAbs - start)) as NSString)
            .trimmingCharacters(in: .whitespaces)
        return head.hasSuffix("from") || head.hasSuffix("import") || head.hasSuffix("import(") || head.hasSuffix("require(")
    }

    /// `@` alias target dir(s) (vite.config / jsconfig / tsconfig, default resources/js).
    static func jsAliases(_ p: LaravelProject) -> [(alias: String, dir: String)] {
        let files = ["vite.config.js", "vite.config.ts", "vite.config.mjs", "jsconfig.json", "tsconfig.json"].map { p.abs($0) }
        return p.memo("jsAliases", stamp: p.stamp(files)) {
            var out: [(String, String)] = []
            for f in files where LaravelFS.isFile(f) {
                guard let t = LaravelFS.text(f) as NSString? else { continue }
                let s = t as String
                if f.hasSuffix(".json") {
                    if let re = try? NSRegularExpression(pattern: #""([^"*]+)/\*"\s*:\s*\[\s*"([^"*]+)/?\*?""#) {
                        re.enumerateMatches(in: s, range: NSRange(location: 0, length: t.length)) { m, _, _ in
                            guard let m else { return }
                            let a = t.substring(with: m.range(at: 1)), d = t.substring(with: m.range(at: 2))
                            out.append((a + "/", (p.abs(d) as NSString).standardizingPath))
                        }
                    }
                } else if let re = try? NSRegularExpression(pattern: #"['"]?([@~][\w/]*)['"]?\s*:\s*[^,}\n]*?['"]([^'"]*(?:resources|src|js|assets)[^'"]*)['"]"#) {
                    re.enumerateMatches(in: s, range: NSRange(location: 0, length: t.length)) { m, _, _ in
                        guard let m else { return }
                        let a = t.substring(with: m.range(at: 1))
                        var d = t.substring(with: m.range(at: 2))
                        if d.hasPrefix("/") && !d.hasPrefix(p.path) { d = String(d.dropFirst()) }
                        out.append((a.hasSuffix("/") ? a : a + "/", (p.abs(d) as NSString).standardizingPath))
                    }
                }
            }
            if !out.contains(where: { $0.0 == "@/" }) { out.append(("@/", p.abs("resources/js"))) }
            if !out.contains(where: { $0.0 == "~/" }) { out.append(("~/", p.abs("resources/js"))) }
            return out
        }
    }

    static func resolveImport(_ spec: String, from file: URL, _ p: LaravelProject) -> [LaravelTarget] {
        var base: String?
        if spec.hasPrefix(".") {
            base = ((file.deletingLastPathComponent().path + "/" + spec) as NSString).standardizingPath
        } else {
            for (alias, dir) in jsAliases(p) where spec.hasPrefix(alias) {
                base = dir + "/" + spec.dropFirst(alias.count)
                break
            }
        }
        guard let base else { return [] }
        let exts = ["", ".vue", ".js", ".jsx", ".ts", ".tsx", ".mjs", ".svelte", ".json", ".css", ".scss"]
        for e in exts where LaravelFS.isFile(base + e) { return [p.target(base + e)] }
        for idx in ["index.js", "index.ts", "index.vue", "index.jsx", "index.tsx"] where LaravelFS.isFile(base + "/" + idx) {
            return [p.target(base + "/" + idx)]
        }
        return []
    }
}
