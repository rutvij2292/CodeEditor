import Foundation

struct LaravelRouteDecl {
    let name: String
    let file: String
    let line: Int
    let col: Int
}

/// Static route table: parses routes/*.php (plus bootstrap/app.php and RouteServiceProvider include chains) for named
/// routes, honouring nested `name()` / `as` prefixes and implicit resource route names. Optionally exact via artisan.
enum LaravelRouteIndex {
    static let artisanDefaultsKey = "laravelUseArtisanRoutes"

    static func routeFiles(_ p: LaravelProject) -> [String] {
        let dir = p.abs("routes")
        var files = LaravelFS.list(dir).filter { $0.hasSuffix(".php") }.sorted().map { dir + "/" + $0 }
        files.append(p.abs("bootstrap/app.php"))
        files.append(p.abs("app/Providers/RouteServiceProvider.php"))
        return files
    }

    static func routes(_ p: LaravelProject) -> [String: LaravelRouteDecl] {
        let files = routeFiles(p)
        return p.memo("routes", stamp: p.stamp(files)) { build(p, files: files) }
    }

    // MARK: Build

    private struct Ctx { var namePrefix = "" }

    private static let verbs: Set<String> = ["get", "post", "put", "patch", "delete", "options", "any", "match", "view", "redirect",
                                             "permanentredirect", "fallback", "inertia", "livewire"]
    private static let resourceKinds: [String: [String]] = [
        "resource": ["index", "create", "store", "show", "edit", "update", "destroy"],
        "apiresource": ["index", "store", "show", "update", "destroy"],
        "singleton": ["show", "edit", "update"],
        "apisingleton": ["show", "update"],
    ]

    private static func build(_ p: LaravelProject, files: [String]) -> [String: LaravelRouteDecl] {
        var out: [String: LaravelRouteDecl] = [:]
        var visited = Set<String>()
        // Provider / bootstrap first (they may `group(base_path('routes/x.php'))` with a prefix), then the rest.
        let ordered = files.suffix(2) + files.dropLast(2)
        for f in ordered { parseFile(p, f, Ctx(), &out, &visited, depth: 0) }
        return out
    }

    private static func parseFile(_ p: LaravelProject, _ file: String, _ ctx: Ctx, _ out: inout [String: LaravelRouteDecl],
                                  _ visited: inout Set<String>, depth: Int) {
        guard depth < 6, !visited.contains(file), let text = LaravelFS.text(file), text.length < 1_500_000 else { return }
        let isRouteFile = file.contains("/routes/")
        if !isRouteFile {
            // Cheap pre-filter for provider/bootstrap files.
            if text.range(of: "Route::").location == NSNotFound, text.range(of: "$router").location == NSNotFound { return }
        }
        visited.insert(file)
        let lex = PHPLex(text)
        parseBlock(p, lex, file, 0, lex.count, ctx, &out, &visited, depth)
    }

    private static func parseBlock(_ p: LaravelProject, _ lex: PHPLex, _ file: String, _ from: Int, _ to: Int, _ ctx: Ctx,
                                   _ out: inout [String: LaravelRouteDecl], _ visited: inout Set<String>, _ depth: Int) {
        var i = from
        while i < to {
            var j = -1
            let t = lex.toks[i]
            if t.kind == .ident, lex.isPunct(i + 1, code: PHPTok.dcolon), i + 2 < to, lex.toks[i + 2].kind == .ident {
                let n = lex.text(i)
                if n == "Route" || n.hasSuffix("\\Route") || n == "Volt" { j = i + 2 }
            } else if t.kind == .variable, lex.isPunct(i + 1, code: PHPTok.arrow), i + 2 < to, lex.toks[i + 2].kind == .ident {
                let n = lex.text(i)
                if n == "$router" || n == "$route" { j = i + 2 }
            }
            guard j >= 0 else { i += 1; continue }

            var calls: [(name: String, open: Int, close: Int)] = []
            var k = j
            while k + 1 < to, lex.toks[k].kind == .ident, lex.isPunct(k + 1, "("), lex.match[k + 1] > k {
                let close = lex.match[k + 1]
                calls.append((lex.text(k).lowercased(), k + 1, close))
                k = close + 1
                if k + 1 < to, lex.isPunct(k, code: PHPTok.arrow), lex.toks[k + 1].kind == .ident { k += 1 } else { break }
            }
            guard !calls.isEmpty else { i += 1; continue }
            process(p, lex, file, calls, ctx, &out, &visited, depth)
            i = max(k, i + 1)
        }
    }

    private static func firstString(_ lex: PHPLex, _ open: Int, _ close: Int) -> Int? {
        let i = open + 1
        return i < close && lex.toks[i].kind == .string ? i : nil
    }

    /// Indices of string tokens inside a call's args (flattened, one level of array).
    private static func strings(_ lex: PHPLex, _ open: Int, _ close: Int) -> [String] {
        var r: [String] = []
        var i = open + 1
        while i < close {
            if lex.toks[i].kind == .string, !lex.isPunct(i + 1, code: PHPTok.fat) { r.append(lex.strValue(i)) }
            i += 1
        }
        return r
    }

    /// Value of `'key' => 'string'` inside an array literal range.
    private static func arrayString(_ lex: PHPLex, _ open: Int, _ close: Int, key: String) -> String? {
        var i = open + 1
        while i + 2 < close {
            if lex.toks[i].kind == .string, lex.strValue(i) == key, lex.isPunct(i + 1, code: PHPTok.fat), lex.toks[i + 2].kind == .string {
                return lex.strValue(i + 2)
            }
            i += 1
        }
        return nil
    }

    private static func process(_ p: LaravelProject, _ lex: PHPLex, _ file: String, _ calls: [(name: String, open: Int, close: Int)],
                                _ ctx: Ctx, _ out: inout [String: LaravelRouteDecl], _ visited: inout Set<String>, _ depth: Int) {
        guard let d = calls.firstIndex(where: { verbs.contains($0.name) || $0.name == "group" || resourceKinds[$0.name] != nil
                                                 || $0.name == "resources" || $0.name == "apiresources" }) else { return }
        var ctx2 = ctx
        for c in calls[..<d] where c.name == "name" || c.name == "as" {
            if let s = firstString(lex, c.open, c.close) { ctx2.namePrefix += lex.strValue(s) }
        }
        let def = calls[d]
        let after = calls[(d + 1)...]

        if def.name == "group" {
            // Route::group([... 'as' => 'x.' ...], function () {...})
            if lex.isPunct(def.open + 1, "["), lex.match[def.open + 1] > 0 {
                let ao = def.open + 1, ac = lex.match[ao]
                if let a = arrayString(lex, ao, ac, key: "as") { ctx2.namePrefix += a }
            }
            var b = -1
            var q = def.open + 1
            while q < def.close {
                if lex.isIdent(q, "function") || lex.isIdent(q, "fn") {
                    var r = q + 1
                    while r < def.close, !lex.isPunct(r, "{") { r += 1 }
                    if r < def.close { b = r }
                    break
                }
                q += 1
            }
            if b >= 0, lex.match[b] > b {
                parseBlock(p, lex, file, b + 1, lex.match[b], ctx2, &out, &visited, depth + 1)
                return
            }
            // ->group(base_path('routes/x.php')) / __DIR__.'/x.php'
            var expr: String?
            for r in (def.open + 1)..<def.close where lex.toks[r].kind == .ident {
                let n = lex.text(r)
                if n == "base_path" || n == "app_path" || n == "resource_path", lex.isPunct(r + 1, "("), let e = lex.match[r + 1] as Int?, e > r {
                    let src = lex.ns.substring(with: NSRange(location: lex.toks[r].loc, length: lex.toks[e].loc + 1 - lex.toks[r].loc))
                    expr = src; break
                }
                if n == "__DIR__", r + 2 < def.close, lex.isPunct(r + 1, "."), lex.toks[r + 2].kind == .string {
                    expr = "__DIR__ . '" + lex.strValue(r + 2) + "'"; break
                }
            }
            if let expr, let path = p.evalPathExpr(expr, relativeTo: file) {
                parseFile(p, path, ctx2, &out, &visited, depth: depth + 1)
            }
            return
        }

        if verbs.contains(def.name) {
            for c in after where c.name == "name" {
                guard let s = firstString(lex, c.open, c.close) else { continue }
                let name = ctx2.namePrefix + lex.strValue(s)
                out[name] = LaravelRouteDecl(name: name, file: file, line: lex.toks[s].line, col: lex.toks[s].col + 1)
            }
            return
        }

        // resource / apiResource / singleton / resources
        if def.name == "resources" || def.name == "apiresources" {
            let ao = def.open + 1
            guard lex.isPunct(ao, "["), lex.match[ao] > ao else { return }
            let actions = resourceKinds[def.name == "resources" ? "resource" : "apiresource"]!
            var i = ao + 1
            while i < lex.match[ao] {
                if lex.toks[i].kind == .string, lex.isPunct(i + 1, code: PHPTok.fat) {
                    addResource(lex, i, lex.strValue(i), actions, [:], "", ctx2, file, &out)
                }
                if lex.toks[i].kind == .punct, [40, 91, 123].contains(lex.toks[i].ch), lex.match[i] > i { i = lex.match[i] }
                i += 1
            }
            return
        }
        guard let s = firstString(lex, def.open, def.close), var actions = resourceKinds[def.name] else { return }
        var overrides: [String: String] = [:]
        var namePrefix = ""
        for c in after {
            switch c.name {
            case "only":
                let only = Set(strings(lex, c.open, c.close)); actions = actions.filter { only.contains($0) }
            case "except":
                let ex = Set(strings(lex, c.open, c.close)); actions = actions.filter { !ex.contains($0) }
            case "names":
                if lex.isPunct(c.open + 1, "[") {
                    var i = c.open + 2
                    while i + 2 < c.close {
                        if lex.toks[i].kind == .string, lex.isPunct(i + 1, code: PHPTok.fat), lex.toks[i + 2].kind == .string {
                            overrides[lex.strValue(i)] = lex.strValue(i + 2)
                        }
                        i += 1
                    }
                } else if let s2 = firstString(lex, c.open, c.close) { namePrefix = lex.strValue(s2) }
            default: break
            }
        }
        addResource(lex, s, lex.strValue(s), actions, overrides, namePrefix, ctx2, file, &out)
    }

    private static func addResource(_ lex: PHPLex, _ tok: Int, _ resource: String, _ actions: [String], _ overrides: [String: String],
                                    _ namePrefix: String, _ ctx: Ctx, _ file: String, _ out: inout [String: LaravelRouteDecl]) {
        let base = resource.split(separator: "/").last.map(String.init) ?? resource
        for a in actions {
            let local = overrides[a] ?? "\(namePrefix.isEmpty ? base : namePrefix).\(a)"
            let name = ctx.namePrefix + local
            out[name] = LaravelRouteDecl(name: name, file: file, line: lex.toks[tok].line, col: lex.toks[tok].col + 1)
        }
    }

    // MARK: Artisan (exact, opt-in)

    /// `php artisan route:list --json` mapped to (action -> controller file/method), cached by routes/* mtimes.
    /// Returns nil when disabled, php is missing, or the command fails/times out (callers fall back to the static table).
    static func artisanRoutes(_ p: LaravelProject) -> [String: LaravelTarget]? {
        guard UserDefaults.standard.bool(forKey: artisanDefaultsKey), LaravelFS.isFile(p.abs("artisan")) else { return nil }
        let files = routeFiles(p)
        return p.memo("artisanRoutes", stamp: p.stamp(files)) { () -> [String: LaravelTarget]? in
            let candidates = [NSHomeDirectory() + "/Library/Application Support/Herd/bin/php", "/opt/homebrew/bin/php", "/usr/local/bin/php", "/usr/bin/php"]
            guard let php = candidates.first(where: { LaravelFS.isFile($0) }) else { return nil }
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: php)
            proc.arguments = ["artisan", "route:list", "--json"]
            proc.currentDirectoryURL = p.root
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = FileHandle.nullDevice
            do { try proc.run() } catch { return nil }
            var data = Data()
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global().async { data = pipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
            if group.wait(timeout: .now() + 15) == .timedOut { proc.terminate(); return nil }
            guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
            var out: [String: LaravelTarget] = [:]
            for r in arr {
                guard let name = r["name"] as? String, !name.isEmpty, let action = r["action"] as? String else { continue }
                let parts = action.components(separatedBy: "@")
                guard let file = p.classFile(parts[0]) else { continue }
                let method = parts.count > 1 ? parts[1] : "__invoke"
                let loc = p.methodLocation(file: file, method: method) ?? p.classDeclaration(file: file)
                out[name] = p.target(file, line: loc.0, column: loc.1)
            }
            return out
        }
    }
}
