import Foundation

/// Native JS/TS module resolution (TypeScript's "node"/"bundler" resolution, the subset that is provably the same answer):
/// relative + absolute specifiers with extension / index probing, tsconfig / jsconfig `baseUrl` + `paths` (with `extends` and
/// solution-style `references`), package.json `imports` (#x), and node_modules packages (`exports`, `types`/`typings`, `main`,
/// `@types/*`). Nothing is indexed: a request stats a handful of paths; config and package.json parses are mtime-stamped and capped.
enum NJSJSON {
    /// Parses JSON with comments and trailing commas (tsconfig style).
    static func parse(_ data: Data) -> Any? {
        guard var s = String(data: data, encoding: .utf8) else { return nil }
        if s.hasPrefix("\u{FEFF}") { s.removeFirst() }
        let u = Array(s.utf8)
        var out = [UInt8](); out.reserveCapacity(u.count)
        var i = 0, inStr = false
        while i < u.count {
            let c = u[i]
            if inStr {
                out.append(c)
                if c == 92, i + 1 < u.count { out.append(u[i + 1]); i += 2; continue }
                if c == 34 { inStr = false }
                i += 1; continue
            }
            if c == 34 { inStr = true; out.append(c); i += 1; continue }
            if c == 47, i + 1 < u.count, u[i + 1] == 47 { while i < u.count, u[i] != 10 { i += 1 }; continue }
            if c == 47, i + 1 < u.count, u[i + 1] == 42 {
                i += 2
                while i + 1 < u.count, !(u[i] == 42 && u[i + 1] == 47) { i += 1 }
                i += 2; out.append(32); continue
            }
            if c == 44 {            // trailing comma: next significant char closes a container
                var j = i + 1
                while j < u.count, u[j] == 32 || u[j] == 10 || u[j] == 13 || u[j] == 9 { j += 1 }
                if j < u.count, u[j] == 125 || u[j] == 93 { i += 1; continue }
            }
            out.append(c); i += 1
        }
        return try? JSONSerialization.jsonObject(with: Data(out), options: [.fragmentsAllowed])
    }
}

struct NJSPathRule {
    var prefix: String
    var suffix: String
    var star: Bool
    var targets: [String]
}

struct NJSConfig {
    var path: String                 // the tsconfig / jsconfig file
    var dir: String
    var baseUrl: String?             // absolute
    var rules: [NJSPathRule] = []
    var pathsBase: String            // directory the `paths` targets are relative to
    var target: String?
    var libs: [String]?
    var noLib = false
    var types: [String]?
    var hasRootDirs = false          // virtual directories (SvelteKit `$types`, ...): relative specifiers cannot be judged
}

/// One package.json, reduced to what resolution needs.
struct NJSPackage {
    var types: String?
    var main: String?
    var module: String?
    var exports: NJSOJ?
    var imports: NJSOJ?
    var name: String?
}

final class NJSModules {
    let lock = NSLock()
    var aliasCache: [String: (stamp: Int64, list: [NJSAlias])] = [:]      // vite / webpack config path -> its string aliases
    var aliasConfigForDir: [String: String] = [:]
    private var configCache: [String: (stamp: Int64, cfg: NJSConfig?)] = [:]
    private var packageCache: [String: (stamp: Int64, pkg: NJSPackage?)] = [:]
    private var configForDir: [String: String] = [:]     // dir -> config path ("" none), cleared with each epoch
    private var resolveMemo: [String: String] = [:]      // "dir|spec" -> path ("" none)
    let root: String

    init(root: String) { self.root = root }

    static let exts = [".ts", ".tsx", ".d.ts", ".js", ".jsx", ".mjs", ".cjs", ".mts", ".cts", ".d.mts", ".d.cts", ".vue", ".json"]
    /// Source extensions the language service understands (a resolved file with another extension is an asset).
    static let codeExts: Set<String> = ["ts", "tsx", "js", "jsx", "mjs", "cjs", "mts", "cts", "vue"]

    /// Request boundary: forget directory-level memos (files may have appeared / vanished since).
    func beginRequest() {
        lock.lock(); configForDir.removeAll(); aliasConfigForDir.removeAll(); resolveMemo.removeAll(); lock.unlock()
    }

    func trim() {
        lock.lock(); configCache.removeAll(); packageCache.removeAll(); configForDir.removeAll(); aliasConfigForDir.removeAll(); resolveMemo.removeAll(); lock.unlock()
    }

    var cachedCount: Int { lock.lock(); defer { lock.unlock() }; return configCache.count + packageCache.count }

    // MARK: file probing

    private static func isFile(_ p: String) -> Bool {
        var st = stat()
        return stat(p, &st) == 0 && (st.st_mode & S_IFMT) == S_IFREG
    }

    private static func isDir(_ p: String) -> Bool { LaravelFS.isDir(p) }

    /// TypeScript's extension replacement for `./x.js` -> x.ts, x.tsx, x.d.ts.
    private static func jsReplacements(_ base: String) -> [String]? {
        for (from, to) in [(".js", [".ts", ".tsx", ".d.ts"]), (".jsx", [".tsx"]), (".mjs", [".mts", ".d.mts"]), (".cjs", [".cts", ".d.cts"])] where base.hasSuffix(from) {
            let stem = String(base.dropLast(from.count))
            return to.map { stem + $0 }
        }
        return nil
    }

    /// On a case-insensitive volume `./itemsRoutes` finds `ItemsRoutes.js`; the real spelling is what a tab / the server uses.
    /// Only a pure case difference is adopted (symlink resolution such as /var -> /private/var is not).
    static func canonicalCase(_ p: String) -> String {
        let fd = open(p, O_RDONLY | O_EVTONLY)
        guard fd >= 0 else { return p }
        defer { close(fd) }
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(fd, F_GETPATH, &buf) == 0 else { return p }
        var real = String(cString: buf)
        if real.hasPrefix("/private/"), !p.hasPrefix("/private/") { real = String(real.dropFirst(8)) }      // /var -> /private/var is not a case change
        return real != p && real.lowercased() == p.lowercased() ? real : p
    }

    static func isTS(_ p: String) -> Bool {
        p.hasSuffix(".ts") || p.hasSuffix(".tsx") || p.hasSuffix(".mts") || p.hasSuffix(".cts")
    }

    /// A path used as a module: the exact file, extension probes, then the directory (package.json main / types, index.*).
    /// `tsOnly`: accept TypeScript sources / declarations only (TypeScript looks for those before it falls back to plain JS).
    func tryModule(_ base: String, preferTypes: Bool = false, tsOnly: Bool = false, depth: Int = 0) -> String? {
        func ok(_ p: String) -> Bool { NJSModules.isFile(p) && (!tsOnly || NJSModules.isTS(p)) }
        if ok(base) {
            if preferTypes, let rep = NJSModules.jsReplacements(base) { for r in rep where NJSModules.isFile(r) { return r } }
            return base
        }
        if let rep = NJSModules.jsReplacements(base) { for r in rep where NJSModules.isFile(r) { return r } }
        for e in NJSModules.exts where ok(base + e) { return base + e }
        guard NJSModules.isDir(base) else { return nil }
        if depth < 3, let pkg = package(at: base + "/package.json") {
            for f in [pkg.types, pkg.main, pkg.module].compactMap({ $0 }) {
                let p = NJSModules.join(base, f)
                if p != base, let r = tryModule(p, preferTypes: true, tsOnly: tsOnly, depth: depth + 1) { return r }
            }
        }
        for e in NJSModules.exts where ok(base + "/index" + e) { return base + "/index" + e }
        return nil
    }

    static func join(_ dir: String, _ rel: String) -> String {
        if rel.hasPrefix("/") { return (rel as NSString).standardizingPath }
        return ((dir as NSString).appendingPathComponent(rel) as NSString).standardizingPath
    }

    // MARK: tsconfig

    private func readFile(_ p: String) -> Data? {
        guard let h = FileHandle(forReadingAtPath: p) else { return nil }
        defer { try? h.close() }
        let d = h.readData(ofLength: 2_000_000)
        return d
    }

    private func rawConfig(_ path: String, depth: Int = 0) -> (dict: [String: Any], stamp: Int64)? {
        guard depth < 6, let data = readFile(path), let obj = NJSJSON.parse(data) as? [String: Any] else { return nil }
        return (obj, LaravelFS.mtime(path))
    }

    /// Loads one config applying `extends` (own values win).
    private func loadConfig(_ path: String, depth: Int = 0) -> NJSConfig? {
        guard depth < 6, let (raw, _) = rawConfig(path) else { return nil }
        let dir = (path as NSString).deletingLastPathComponent
        var cfg = NJSConfig(path: path, dir: dir, baseUrl: nil, rules: [], pathsBase: dir)
        var parentDefinesPaths = false
        var exts: [String] = []
        if let e = raw["extends"] as? String { exts = [e] } else if let es = raw["extends"] as? [String] { exts = es }
        for e in exts {
            var target: String?
            if e.hasPrefix(".") || e.hasPrefix("/") {
                var p = NJSModules.join(dir, e)
                if !p.hasSuffix(".json") { p += ".json" }
                if NJSModules.isFile(p) { target = p }
            } else {
                var d = dir
                while true {
                    for cand in [d + "/node_modules/" + e, d + "/node_modules/" + e + ".json", d + "/node_modules/" + e + "/tsconfig.json"] where NJSModules.isFile(cand) { target = cand; break }
                    if target != nil || d == "/" || d.isEmpty { break }
                    d = (d as NSString).deletingLastPathComponent
                }
            }
            if let t = target, let parent = loadConfig(t, depth: depth + 1) {
                if parent.baseUrl != nil { cfg.baseUrl = parent.baseUrl }
                if parent.hasRootDirs { cfg.hasRootDirs = true }
                cfg.target = parent.target; cfg.libs = parent.libs; cfg.noLib = parent.noLib; cfg.types = parent.types
                if !parent.rules.isEmpty { cfg.rules = parent.rules; cfg.pathsBase = parent.pathsBase; parentDefinesPaths = true }
            }
        }
        _ = parentDefinesPaths
        if let co = raw["compilerOptions"] as? [String: Any] {
            if co["rootDirs"] != nil { cfg.hasRootDirs = true }
            if let t = co["target"] as? String { cfg.target = t }
            if let l = co["lib"] as? [String] { cfg.libs = l }
            if let n = co["noLib"] as? Bool { cfg.noLib = n }
            if let t = co["types"] as? [String] { cfg.types = t }
            if let b = co["baseUrl"] as? String { cfg.baseUrl = NJSModules.join(dir, b) }
            if let paths = co["paths"] as? [String: Any] {
                cfg.rules = []
                for (k, v) in paths {
                    guard let targets = v as? [String] else { continue }
                    if let star = k.firstIndex(of: "*") {
                        cfg.rules.append(NJSPathRule(prefix: String(k[..<star]), suffix: String(k[k.index(after: star)...]), star: true, targets: targets))
                    } else {
                        cfg.rules.append(NJSPathRule(prefix: k, suffix: "", star: false, targets: targets))
                    }
                }
                cfg.rules.sort { $0.prefix.count > $1.prefix.count }
                cfg.pathsBase = dir        // fixed below once baseUrl is final
                cfg.pathsBase = cfg.baseUrl ?? dir
            } else if !cfg.rules.isEmpty, cfg.baseUrl != nil, co["baseUrl"] != nil {
                cfg.pathsBase = cfg.baseUrl ?? cfg.pathsBase
            }
        }
        return cfg
    }

    func config(at path: String) -> NJSConfig? {
        let stamp = LaravelFS.mtime(path)
        lock.lock()
        if let c = configCache[path], c.stamp == stamp { lock.unlock(); return c.cfg }
        lock.unlock()
        let cfg = loadConfig(path)
        lock.lock()
        if configCache.count > 32 { configCache.removeAll() }
        configCache[path] = (stamp, cfg)
        lock.unlock()
        return cfg
    }

    /// The tsconfig / jsconfig governing `dir` (nearest ancestor, never above the root unless the file is outside it).
    func configPath(for dir: String) -> String? {
        lock.lock(); if let c = configForDir[dir] { lock.unlock(); return c.isEmpty ? nil : c }; lock.unlock()
        var d = dir, found = ""
        for _ in 0..<40 {
            for n in ["tsconfig.json", "jsconfig.json"] where NJSModules.isFile(d + "/" + n) { found = d + "/" + n; break }
            if !found.isEmpty || d == "/" || d.isEmpty { break }
            d = (d as NSString).deletingLastPathComponent
        }
        lock.lock(); configForDir[dir] = found; lock.unlock()
        return found.isEmpty ? nil : found
    }

    /// Config that applies to `file`; for solution-style tsconfigs (references) the referenced config that carries paths.
    func config(for file: String) -> NJSConfig? {
        guard let p = configPath(for: (file as NSString).deletingLastPathComponent), let cfg = config(at: p) else { return nil }
        if !cfg.rules.isEmpty || cfg.baseUrl != nil { return cfg }
        guard let (raw, _) = rawConfig(p), let refs = raw["references"] as? [[String: Any]] else { return cfg }
        for r in refs {
            guard let rp = r["path"] as? String else { continue }
            var path = NJSModules.join(cfg.dir, rp)
            if NJSModules.isDir(path) { path += "/tsconfig.json" } else if !path.hasSuffix(".json") { path += ".json" }
            if let c = config(at: path), !c.rules.isEmpty || c.baseUrl != nil { return c }
        }
        return cfg
    }

    // MARK: package.json

    func package(at path: String) -> NJSPackage? {
        let stamp = LaravelFS.mtime(path)
        if stamp == 0 { return nil }
        lock.lock()
        if let c = packageCache[path], c.stamp == stamp { lock.unlock(); return c.pkg }
        lock.unlock()
        var pkg: NJSPackage?
        if let d = readFile(path), case .o(let pairs)? = NJSOJ.parse(d) {
            func val(_ k: String) -> NJSOJ? { pairs.first { $0.0 == k }?.1 }
            func str(_ k: String) -> String? { if case .s(let v)? = val(k) { return v }; return nil }
            pkg = NJSPackage(types: str("types") ?? str("typings"), main: str("main"), module: str("module"), exports: val("exports"), imports: val("imports"), name: str("name"))
        }
        lock.lock()
        if packageCache.count > 64 { packageCache.removeAll() }
        packageCache[path] = (stamp, pkg)
        lock.unlock()
        return pkg
    }

    // MARK: resolution

    /// Resolves `spec` as imported from `file` to an absolute path, or nil.
    func resolve(_ spec: String, from file: String) -> String? {
        let dir = (file as NSString).deletingLastPathComponent
        let key = dir + "|" + spec
        lock.lock(); if let m = resolveMemo[key] { lock.unlock(); return m.isEmpty ? nil : m }; lock.unlock()
        let r = resolveUncached(spec, dir: dir, file: file).map { NJSModules.canonicalCase($0) }
        lock.lock(); if resolveMemo.count > 6000 { resolveMemo.removeAll() }; resolveMemo[key] = r ?? ""; lock.unlock()
        return r
    }

    private func resolveUncached(_ spec: String, dir: String, file: String) -> String? {
        if spec.hasPrefix("./") || spec.hasPrefix("../") || spec == "." || spec == ".." { return tryModule(NJSModules.join(dir, spec)) }
        if spec.hasPrefix("/") { return tryModule(NJSModules.join("/", spec)) }
        if spec.hasPrefix("#") { return resolvePackageImport(spec, dir: dir) }
        if let cfg = config(for: file) {
            // longest matching `paths` rule first
            for rule in cfg.rules {
                var captured: String?
                if rule.star {
                    if spec.hasPrefix(rule.prefix), spec.hasSuffix(rule.suffix), spec.count >= rule.prefix.count + rule.suffix.count {
                        captured = String(spec.dropFirst(rule.prefix.count).dropLast(rule.suffix.count))
                    }
                } else if spec == rule.prefix { captured = "" }
                guard let cap = captured else { continue }
                for t in rule.targets {
                    let sub = rule.star ? t.replacingOccurrences(of: "*", with: cap) : t
                    if let r = tryModule(NJSModules.join(cfg.pathsBase, sub), preferTypes: true) { return r }
                }
                break      // TypeScript stops at the best matching pattern
            }
            if let b = cfg.baseUrl, let r = tryModule(NJSModules.join(b, spec)) { return r }
        }
        if let r = resolveBundlerAlias(spec, dir: dir) { return r }
        return resolveBare(spec, dir: dir)
    }

    private static func splitBare(_ spec: String) -> (name: String, sub: String) {
        let parts = spec.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if spec.hasPrefix("@"), parts.count >= 2 { return (parts[0] + "/" + parts[1], parts.dropFirst(2).joined(separator: "/")) }
        return (parts[0], parts.dropFirst().joined(separator: "/"))
    }

    /// TypeScript's `typesRoot` caches filled by automatic type acquisition (read only here, nothing is downloaded).
    private static var ataDirs: [String] = {
        let base = NSHomeDirectory() + "/Library/Caches/typescript"
        guard let vs = try? FileManager.default.contentsOfDirectory(atPath: base) else { return [] }
        return vs.sorted().last.map { [base + "/" + $0 + "/node_modules"] } ?? []      // newest only: older caches belong to other TypeScript versions
    }()

    private func resolveBare(_ spec: String, dir: String) -> String? {
        let (name, sub) = NJSModules.splitBare(spec)
        guard !name.isEmpty else { return nil }
        let mangled = name.hasPrefix("@") ? String(name.dropFirst()).replacingOccurrences(of: "/", with: "__") : name
        // 1. declarations: the package itself, then @types/<name>, walking up the node_modules chain
        var d = dir
        var pkgDirsSeen: [String] = []
        for _ in 0..<60 {
            let nm = d + "/node_modules"
            if NJSModules.isDir(nm) {
                let pkgDir = nm + "/" + name
                if NJSModules.isDir(pkgDir) { pkgDirsSeen.append(pkgDir); if let r = resolveInPackage(pkgDir, sub: sub, tsOnly: true) { return r } }
                let typesDir = nm + "/@types/" + mangled
                if NJSModules.isDir(typesDir), let r = resolveInPackage(typesDir, sub: sub, tsOnly: true) { return r }
            }
            if d == "/" || d.isEmpty { break }
            d = (d as NSString).deletingLastPathComponent
        }
        for nm in NJSModules.ataDirs {
            let typesDir = nm + "/@types/" + mangled
            if NJSModules.isDir(typesDir), let r = resolveInPackage(typesDir, sub: sub, tsOnly: true) { return r }
        }
        // 2. plain JavaScript of the package
        for pkgDir in pkgDirsSeen { if let r = resolveInPackage(pkgDir, sub: sub, tsOnly: false) { return r } }
        return nil
    }

    private func resolveInPackage(_ pkgDir: String, sub: String, tsOnly: Bool) -> String? {
        let pkg = package(at: pkgDir + "/package.json")
        if let ex = pkg?.exports {
            if let r = resolveExportsMap(ex, key: sub.isEmpty ? "." : "./" + sub, pkgDir: pkgDir, tsOnly: tsOnly) { return r }
            // a package with `exports` does not expose other paths; types fallbacks below still fire for `.`
            if !sub.isEmpty { return nil }
        }
        if sub.isEmpty {
            for f in [pkg?.types, pkg?.main, pkg?.module].compactMap({ $0 }) {
                let p = NJSModules.join(pkgDir, f)
                if let r = tryModule(p, preferTypes: true, tsOnly: tsOnly) { return r }
            }
            return tryModule(pkgDir + "/index", tsOnly: tsOnly)
        }
        return tryModule(pkgDir + "/" + sub, preferTypes: true, tsOnly: tsOnly)
    }

    private func resolvePackageImport(_ spec: String, dir: String) -> String? {
        var d = dir
        for _ in 0..<40 {
            if let pkg = package(at: d + "/package.json") {
                if let imps = pkg.imports { return resolveExportsMap(imps, key: spec, pkgDir: d, tsOnly: false) }
                if pkg.name != nil || d == root { return nil }
            }
            if d == "/" || d.isEmpty { break }
            d = (d as NSString).deletingLastPathComponent
        }
        return nil
    }

    /// Conditions an ES-module importer matches, in no particular order: the FIRST matching key of an exports object wins (TypeScript / Node).
    private static let conditions: Set<String> = ["types", "import", "default"]

    private func resolveExportsMap(_ exports: NJSOJ, key: String, pkgDir: String, tsOnly: Bool) -> String? {
        var target: NJSOJ?
        var star: String?
        if case .o(let pairs) = exports, pairs.contains(where: { $0.0.hasPrefix(".") || $0.0.hasPrefix("#") }) {
            if let t = pairs.first(where: { $0.0 == key }) { target = t.1 }
            else {
                var best: (len: Int, key: String, value: NJSOJ)?
                for (k, v) in pairs {
                    guard let s = k.firstIndex(of: "*") else { continue }
                    let pre = String(k[..<s]), suf = String(k[k.index(after: s)...])
                    if key.hasPrefix(pre), key.hasSuffix(suf), key.count >= pre.count + suf.count, best == nil || pre.count > best!.len { best = (pre.count, k, v) }
                }
                if let b = best, let s = b.key.firstIndex(of: "*") {
                    let pre = String(b.key[..<s]), suf = String(b.key[b.key.index(after: s)...])
                    star = String(key.dropFirst(pre.count).dropLast(suf.count))
                    target = b.value
                }
            }
        } else if key == "." { target = exports }          // conditions (or a plain string / array) at the top level
        guard let t = target, let path = pickCondition(t, star: star) else { return nil }
        return tryModule(NJSModules.join(pkgDir, path), preferTypes: true, tsOnly: tsOnly)
    }

    private func pickCondition(_ t: NJSOJ, star: String?) -> String? {
        switch t {
        case .s(let s): return star.map { s.replacingOccurrences(of: "*", with: $0) } ?? s
        case .a(let arr): for x in arr { if let r = pickCondition(x, star: star) { return r } }; return nil
        case .o(let pairs):
            for (k, v) in pairs where NJSModules.conditions.contains(k) { if let r = pickCondition(v, star: star) { return r } }
            return nil
        case .n: return nil
        }
    }
}

/// Order preserving JSON (package.json `exports` objects are matched by key order, which NSDictionary loses).
indirect enum NJSOJ {
    case s(String), o([(String, NJSOJ)]), a([NJSOJ]), n

    static func parse(_ data: Data) -> NJSOJ? {
        let u = [UInt8](data)
        var i = 0
        func ws() { while i < u.count, u[i] == 32 || u[i] == 10 || u[i] == 13 || u[i] == 9 || (i == 0 && u[i] == 0xEF) || u[i] == 0xBB || u[i] == 0xBF { i += 1 } }
        func str() -> String? {
            guard i < u.count, u[i] == 34 else { return nil }
            i += 1
            var out = [UInt8]()
            while i < u.count, u[i] != 34 {
                if u[i] == 92, i + 1 < u.count {
                    i += 1
                    switch u[i] {
                    case 110: out.append(10)
                    case 116: out.append(9)
                    case 117:
                        if i + 4 < u.count, let v = UInt32(String(decoding: u[(i + 1)...(i + 4)], as: UTF8.self), radix: 16), let sc = Unicode.Scalar(v) { out += Array(String(Character(sc)).utf8) }
                        i += 4
                    default: out.append(u[i])
                    }
                } else { out.append(u[i]) }
                i += 1
            }
            i += 1
            return String(decoding: out, as: UTF8.self)
        }
        func value(_ depth: Int) -> NJSOJ? {
            guard depth < 40 else { return nil }
            ws()
            guard i < u.count else { return nil }
            switch u[i] {
            case 34: return str().map { .s($0) }
            case 123:
                i += 1
                var pairs: [(String, NJSOJ)] = []
                ws()
                if i < u.count, u[i] == 125 { i += 1; return .o(pairs) }
                while i < u.count {
                    ws()
                    guard let k = str() else { return nil }
                    ws()
                    guard i < u.count, u[i] == 58 else { return nil }
                    i += 1
                    guard let v = value(depth + 1) else { return nil }
                    pairs.append((k, v))
                    ws()
                    if i < u.count, u[i] == 44 { i += 1; continue }
                    if i < u.count, u[i] == 125 { i += 1; return .o(pairs) }
                    return nil
                }
                return nil
            case 91:
                i += 1
                var arr: [NJSOJ] = []
                ws()
                if i < u.count, u[i] == 93 { i += 1; return .a(arr) }
                while i < u.count {
                    guard let v = value(depth + 1) else { return nil }
                    arr.append(v)
                    ws()
                    if i < u.count, u[i] == 44 { i += 1; continue }
                    if i < u.count, u[i] == 93 { i += 1; return .a(arr) }
                    return nil
                }
                return nil
            default:
                while i < u.count, u[i] != 44, u[i] != 125, u[i] != 93 { i += 1 }     // number / true / false / null
                return .n
            }
        }
        return value(0)
    }
}
