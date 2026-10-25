import Foundation

// Names for Gate abilities, middleware aliases, session / cache keys. Nothing is cached here: policies and the two middleware files are
// tiny, session / cache keys come from the usage table (FastTierUsage.swift, byte capped, dropped on trim).

extension FastProject {
    static let builtinMiddleware: [String] = ["auth", "auth.basic", "auth.session", "cache.headers", "can", "guest", "password.confirm", "precognitive",
                                              "signed", "throttle", "verified", "web", "api", "bindings"]

    /// Public method names of `app/Policies/*` (and module policies): the abilities `$user->can('...')` / `@can('...')` check.
    func policyAbilities() -> [FTName] {
        var out: [FTName] = []
        var seen = Set<String>()
        var dirs = [path + "/app/Policies"]
        for m in LaravelModules.dirs(lp) { dirs.append(m.path + "/app/Policies"); dirs.append(m.path + "/Policies") }
        guard let re = NPRe.make(pattern: #"public\s+function\s+([a-z]\w*)\s*\("#) else { return out }
        for d in dirs where LaravelFS.isDir(d) {
            for f in LaravelFS.list(d).sorted() where f.hasSuffix("Policy.php") {
                guard let t = Self.read(d + "/" + f) else { continue }
                let model = String(f.dropLast(10))
                for m in re.matches(in: t as String, range: NSRange(location: 0, length: t.length)).prefix(60) {
                    let n = t.substring(with: m.range(at: 1))
                    if n.hasPrefix("__") || n == "before" || n == "after" { continue }
                    if seen.insert(n).inserted { out.append(FTName(name: n, detail: model + " policy")) }
                }
            }
        }
        return out
    }

    /// Middleware aliases: `bootstrap/app.php` (`$middleware->alias([...])`), `app/Http/Kernel.php` ($middlewareAliases / $routeMiddleware), built-ins.
    func middlewareAliases() -> [FTName] {
        var out: [FTName] = []
        var seen = Set<String>()
        guard let re = NPRe.make(pattern: #"['"]([\w.\-]+)['"]\s*=>\s*\\?[\w\\]+::class"#) else { return out }
        for rel in ["bootstrap/app.php", "app/Http/Kernel.php"] {
            guard let t = Self.read(path + "/" + rel) else { continue }
            for m in re.matches(in: t as String, range: NSRange(location: 0, length: t.length)).prefix(200) {
                let n = t.substring(with: m.range(at: 1))
                if seen.insert(n).inserted { out.append(FTName(name: n, detail: "middleware alias")) }
            }
        }
        for n in Self.builtinMiddleware where seen.insert(n).inserted { out.append(FTName(name: n, detail: "middleware")) }
        return out
    }
}

extension FUsage.View {
    /// Keys of `kind` the project (or this buffer) uses, most used first (capped).
    func names(_ k: FUsageKind, limit: Int = 600) -> [String] {
        let prefix = k.rawValue + "\u{1}"
        var rows: [(String, Int)] = []
        for key in Set(table.counts.keys).union(plus.keys) where key.hasPrefix(prefix) {
            let name = String(key.dropFirst(prefix.count))
            let c = count(k, name)
            if c > 0 { rows.append((name, c)) }
        }
        rows.sort { ($0.1, $1.0) > ($1.1, $0.0) }
        return rows.prefix(limit).map(\.0)
    }
}
