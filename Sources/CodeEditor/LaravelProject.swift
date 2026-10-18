import Foundation

/// One navigation destination. `line` and `column` are 1-based (column 1 = start of line).
struct LaravelTarget: Equatable {
    let url: URL
    let line: Int
    let column: Int
    let title: String
}

enum LaravelFS {
    static func mtime(_ path: String) -> Int64 {
        var st = stat()
        guard stat(path, &st) == 0 else { return 0 }
        return Int64(st.st_mtimespec.tv_sec) &* 1_000_000_000 &+ Int64(st.st_mtimespec.tv_nsec) &+ Int64(st.st_size)
    }
    static func exists(_ path: String) -> Bool { access(path, F_OK) == 0 }
    static func isDir(_ path: String) -> Bool {
        var st = stat()
        return stat(path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR
    }
    static func isFile(_ path: String) -> Bool { exists(path) && !isDir(path) }
    static func list(_ path: String) -> [String] { (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? [] }

    // Small LRU of recently read file contents (bounded) so repeated hover resolves do not re-read.
    private static var cache: [(path: String, stamp: Int64, text: NSString)] = []
    private static let cacheLock = NSLock()   // the fast completion tier reads files from a background queue
    static func text(_ path: String) -> NSString? {
        cacheLock.lock(); defer { cacheLock.unlock() }
        let stamp = mtime(path)
        if stamp == 0 { return nil }
        if let i = cache.firstIndex(where: { $0.path == path && $0.stamp == stamp }) {
            let e = cache.remove(at: i); cache.append(e); return e.text
        }
        guard let data = FileManager.default.contents(atPath: path), data.count < 3_000_000,
              let s = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }
        let ns = s as NSString
        cache.append((path, stamp, ns))
        var total = cache.reduce(0) { $0 + $1.text.length }
        while cache.count > 12 || total > 3_000_000, cache.count > 1 { total -= cache.removeFirst().text.length }
        return ns
    }
    static func dropTextCache() { cacheLock.lock(); cache.removeAll(); cacheLock.unlock() }

    /// 1-based (line, column) of a UTF-16 offset.
    static func lineCol(_ ns: NSString, _ offset: Int) -> (Int, Int) {
        var line = 1, ls = 0
        let end = min(offset, ns.length)
        var i = 0
        while i < end {
            if ns.character(at: i) == 10 { line += 1; ls = i + 1 }
            i += 1
        }
        return (line, end - ls + 1)
    }
}

/// Everything Laravel-specific we know about one project root. Cheap objects; heavy tables are built lazily and
/// revalidated against file mtimes.
final class LaravelProject {
    let root: URL
    private var memos: [String: (stamp: Int64, value: Any)] = [:]

    private static var projects: [String: LaravelProject] = [:]
    private static var rootCache: [String: String] = [:]   // dir -> root path ("" = none)

    init(root: URL) { self.root = root }

    var path: String { root.path }
    func abs(_ rel: String) -> String { rel.hasPrefix("/") ? rel : path + "/" + rel }
    func url(_ rel: String) -> URL { URL(fileURLWithPath: abs(rel)) }
    func relative(_ u: URL) -> String {
        let p = u.standardizedFileURL.path
        let base = root.standardizedFileURL.path
        return p.hasPrefix(base + "/") ? String(p.dropFirst(base.count + 1)) : u.lastPathComponent
    }
    func target(_ file: String, line: Int = 1, column: Int = 1) -> LaravelTarget {
        let u = URL(fileURLWithPath: file)
        return LaravelTarget(url: u, line: line, column: column, title: relative(u))
    }

    // MARK: Discovery

    static func isLaravelRoot(_ dir: String) -> Bool {
        if LaravelFS.isFile(dir + "/artisan") { return true }
        if let data = FileManager.default.contents(atPath: dir + "/composer.json"), data.count < 500_000,
           let s = String(data: data, encoding: .utf8), s.contains("laravel/framework") { return true }
        return false
    }

    /// The Laravel project containing `file`, if any (walks up at most 12 directories).
    static func find(for file: URL) -> LaravelProject? {
        var dir = file.deletingLastPathComponent().standardizedFileURL.path
        let start = dir
        if let cached = rootCache[start] { return cached.isEmpty ? nil : project(at: cached) }
        var result = ""
        for _ in 0..<12 {
            if isLaravelRoot(dir) { result = dir; break }
            let parent = (dir as NSString).deletingLastPathComponent
            if parent == dir || parent.isEmpty { break }
            dir = parent
        }
        if rootCache.count > 200 { rootCache.removeAll() }
        rootCache[start] = result
        return result.isEmpty ? nil : project(at: result)
    }

    static func project(at path: String) -> LaravelProject {
        if let p = projects[path] { return p }
        let p = LaravelProject(root: URL(fileURLWithPath: path))
        projects[path] = p
        return p
    }

    static func invalidate(root: URL) {
        let p = root.standardizedFileURL.path
        projects[p]?.memos.removeAll()
        rootCache = rootCache.filter { $0.value != p && $0.value != "" }
        LaravelFS.dropTextCache()
    }

    // MARK: Memoisation (stamp = mtime hash of the inputs)

    func stamp(_ paths: [String]) -> Int64 {
        var h = Hasher()
        for p in paths { h.combine(LaravelFS.mtime(p)) }
        return Int64(h.finalize())
    }

    func memo<T>(_ key: String, stamp: Int64, _ build: () -> T) -> T {
        if let m = memos[key], m.stamp == stamp, let v = m.value as? T { return v }
        let v = build()
        if memos.count > 80 { memos.removeAll() }
        memos[key] = (stamp, v)
        return v
    }

    // MARK: PSR-4 / classes

    /// (prefix with trailing backslash, absolute dirs) sorted by prefix length (longest first).
    var psr4: [(prefix: String, dirs: [String])] {
        let composer = abs("composer.json"), vendorMap = abs("vendor/composer/autoload_psr4.php")
        return memo("psr4", stamp: stamp([composer, vendorMap])) {
            var map: [String: [String]] = [:]
            if let data = FileManager.default.contents(atPath: composer),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for key in ["autoload", "autoload-dev"] {
                    guard let psr = (json[key] as? [String: Any])?["psr-4"] as? [String: Any] else { continue }
                    for (prefix, v) in psr {
                        let dirs = (v as? [String]) ?? (v as? String).map { [$0] } ?? []
                        map[prefix, default: []] += dirs.map { abs(($0 as NSString).standardizingPath) }
                    }
                }
            }
            if map["App\\"] == nil, LaravelFS.isDir(abs("app")) { map["App\\"] = [abs("app")] }
            if let ns = LaravelFS.text(vendorMap),
               let re = try? NSRegularExpression(pattern: #"'((?:[^'\\]|\\.)*)'\s*=>\s*array\((.*)\)"#) {
                let dirRe = try? NSRegularExpression(pattern: #"\$(vendorDir|baseDir)\s*\.\s*'([^']*)'"#)
                re.enumerateMatches(in: ns as String, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
                    guard let m else { return }
                    let prefix = ns.substring(with: m.range(at: 1)).replacingOccurrences(of: "\\\\", with: "\\")
                    let body = ns.substring(with: m.range(at: 2))
                    dirRe?.enumerateMatches(in: body, range: NSRange(location: 0, length: (body as NSString).length)) { dm, _, _ in
                        guard let dm else { return }
                        let b = (body as NSString)
                        let base = b.substring(with: dm.range(at: 1)) == "vendorDir" ? self.abs("vendor") : self.path
                        map[prefix, default: []].append(base + b.substring(with: dm.range(at: 2)))
                    }
                }
            }
            return map.map { ($0.key, $0.value) }.sorted { $0.0.count > $1.0.count }
        }
    }

    /// Absolute file of a fully qualified class name, if it exists.
    func classFile(_ fqcn: String) -> String? {
        let name = fqcn.hasPrefix("\\") ? String(fqcn.dropFirst()) : fqcn
        for (prefix, dirs) in psr4 where name.hasPrefix(prefix) {
            let rest = String(name.dropFirst(prefix.count)).replacingOccurrences(of: "\\", with: "/")
            for d in dirs {
                let f = d + "/" + rest + ".php"
                if LaravelFS.isFile(f) { return f }
            }
        }
        return nil
    }

    struct UseInfo { var namespace = ""; var aliases: [String: String] = [:] }

    func useInfo(_ text: NSString) -> UseInfo {
        var info = UseInfo()
        let s = text as String
        let scope = s.count > 40_000 ? String(s.prefix(40_000)) : s
        for line in scope.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("namespace ") {
                info.namespace = line.dropFirst(10).trimmingCharacters(in: CharacterSet(charactersIn: "; \r\t"))
            } else if line.hasPrefix("use ") {
                var body = line.dropFirst(4).trimmingCharacters(in: CharacterSet(charactersIn: "; \r\t"))
                if body.hasPrefix("function ") || body.hasPrefix("const ") { continue }
                var groupPrefix = ""
                if let o = body.firstIndex(of: "{"), let c = body.lastIndex(of: "}") {
                    groupPrefix = String(body[..<o]); body = String(body[body.index(after: o)..<c])
                }
                for part in body.split(separator: ",") {
                    let p = part.trimmingCharacters(in: .whitespaces)
                    let bits = p.components(separatedBy: " as ")
                    let full = (groupPrefix + bits[0].trimmingCharacters(in: .whitespaces)).trimmingCharacters(in: CharacterSet(charactersIn: "\\"))
                    let alias = bits.count > 1 ? bits[1].trimmingCharacters(in: .whitespaces)
                                               : String(full.split(separator: "\\").last ?? "")
                    if !alias.isEmpty { info.aliases[alias] = full }
                }
            }
        }
        return info
    }

    /// Candidate files for a class reference as written in `text`'s file (imports, namespace, Laravel defaults).
    func resolveClass(_ written: String, fileText: NSString?, extraNamespaces: [String] = []) -> [String] {
        var name = written
        if name.hasPrefix("\\") { return classFile(name).map { [$0] } ?? [] }
        if name.isEmpty || ["self", "static", "parent", "class"].contains(name.lowercased()) { return [] }
        var candidates: [String] = []
        let info = fileText.map(useInfo) ?? UseInfo()
        let first = String(name.split(separator: "\\").first ?? "")
        if let full = info.aliases[first] {
            name = name.contains("\\") ? full + "\\" + name.dropFirst(first.count + 1) : full
            candidates.append(name)
        } else {
            if !info.namespace.isEmpty { candidates.append(info.namespace + "\\" + name) }
            candidates.append(name)
        }
        for ns in extraNamespaces + ["App\\Http\\Controllers", "App\\Models", "App"] { candidates.append(ns + "\\" + name) }
        var seen = Set<String>(), out: [String] = []
        for c in candidates {
            if let f = classFile(c), seen.insert(f).inserted { out.append(f) }
        }
        return out
    }

    func methodLocation(file: String, method: String) -> (Int, Int)? {
        guard let t = LaravelFS.text(file) else { return nil }
        let pat = #"function\s+&?\s*("# + NSRegularExpression.escapedPattern(for: method) + #")\s*\("#
        guard let re = try? NSRegularExpression(pattern: pat),
              let m = re.firstMatch(in: t as String, range: NSRange(location: 0, length: t.length)) else { return nil }
        return LaravelFS.lineCol(t, m.range(at: 1).location)
    }

    func classDeclaration(file: String) -> (Int, Int) {
        guard let t = LaravelFS.text(file),
              let re = try? NSRegularExpression(pattern: #"\b(?:class|interface|trait|enum)\s+(\w+)"#),
              let m = re.firstMatch(in: t as String, range: NSRange(location: 0, length: min(t.length, 60_000))) else { return (1, 1) }
        return LaravelFS.lineCol(t, m.range(at: 1).location)
    }

    // MARK: Vendor packages

    /// Absolute dirs of `vendor/<vendor>/<package>`.
    var vendorPackages: [String] {
        let v = abs("vendor")
        return memo("vendorPkgs", stamp: LaravelFS.mtime(v) &+ LaravelFS.mtime(v + "/composer/installed.json")) {
            var out: [String] = []
            for vendor in LaravelFS.list(v) where !vendor.hasPrefix(".") && vendor != "composer" && vendor != "bin" {
                let vp = v + "/" + vendor
                guard LaravelFS.isDir(vp) else { continue }
                for pkg in LaravelFS.list(vp) where !pkg.hasPrefix(".") { out.append(vp + "/" + pkg) }
            }
            return out
        }
    }

    // MARK: Views

    var providerFiles: [String] {
        let dir = abs("app/Providers")
        return LaravelFS.list(dir).filter { $0.hasSuffix(".php") }.sorted().map { dir + "/" + $0 }
    }

    /// Evaluates `__DIR__.'/x'`, `base_path('x')`, `resource_path('x')`, `app_path('x')` style path expressions.
    func evalPathExpr(_ expr: String, relativeTo file: String) -> String? {
        let e = expr.trimmingCharacters(in: .whitespacesAndNewlines)
        func quoted(_ s: String) -> String? {
            let m = s.trimmingCharacters(in: .whitespaces)
            guard m.count >= 2, let q = m.first, q == "'" || q == "\"", m.last == q else { return nil }
            return String(m.dropFirst().dropLast())
        }
        if e.hasPrefix("__DIR__") {
            let rest = e.dropFirst(7).trimmingCharacters(in: .whitespaces)
            guard rest.hasPrefix("."), let q = quoted(String(rest.dropFirst())) else { return (file as NSString).deletingLastPathComponent }
            return ((((file as NSString).deletingLastPathComponent) + q) as NSString).standardizingPath
        }
        let funcs: [(String, String)] = [("base_path", ""), ("resource_path", "resources"), ("app_path", "app"),
                                         ("public_path", "public"), ("config_path", "config"), ("database_path", "database")]
        for (fn, base) in funcs where e.hasPrefix(fn + "(") {
            let inner = String(e.dropFirst(fn.count + 1).prefix(while: { $0 != ")" }))
            let sub = quoted(inner) ?? ""
            let joined = [path, base, sub].filter { !$0.isEmpty }.joined(separator: "/")
            return (joined as NSString).standardizingPath
        }
        return nil
    }

    /// view namespace -> absolute directories, from `loadViewsFrom(..., 'ns')` in app providers.
    var viewNamespaces: [String: [String]] {
        let files = providerFiles
        return memo("viewNS", stamp: stamp(files)) {
            var out: [String: [String]] = [:]
            guard let re = try? NSRegularExpression(pattern: #"loadViewsFrom\(\s*(.+?)\s*,\s*['"]([^'"]+)['"]\s*\)"#) else { return out }
            for f in files {
                guard let t = LaravelFS.text(f) else { continue }
                re.enumerateMatches(in: t as String, range: NSRange(location: 0, length: t.length)) { m, _, _ in
                    guard let m, let dir = self.evalPathExpr(t.substring(with: m.range(at: 1)), relativeTo: f) else { return }
                    out[t.substring(with: m.range(at: 2)), default: []].append(dir)
                }
            }
            return out
        }
    }

    private static let builtinViewNS: [String: String] = [
        "mail": "vendor/laravel/framework/src/Illuminate/Mail/resources/views/html",
        "notifications": "vendor/laravel/framework/src/Illuminate/Notifications/resources/views",
        "pagination": "vendor/laravel/framework/src/Illuminate/Pagination/resources/views",
    ]

    /// Directories that can hold views of `ns` (override first).
    func viewDirs(namespace ns: String?) -> [String] {
        guard let ns else { return [abs("resources/views")] }
        var dirs = [abs("resources/views/vendor/" + ns)]
        dirs += viewNamespaces[ns] ?? []
        if let b = Self.builtinViewNS[ns] { dirs.append(abs(b)) }
        let lowered = ns.lowercased()
        for pkg in vendorPackages {
            let name = ((pkg as NSString).lastPathComponent).lowercased()
            guard name == lowered || name == "laravel-" + lowered || name.hasSuffix("-" + lowered) || name.hasPrefix(lowered + "-") else { continue }
            for sub in ["resources/views", "src/resources/views", "views", "src/views"] where LaravelFS.isDir(pkg + "/" + sub) {
                dirs.append(pkg + "/" + sub)
            }
        }
        return dirs
    }

    static let viewExtensions = [".blade.php", ".php", ".html"]

    /// First existing view file for `name` (`a.b.c` or `pkg::a.b`).
    func viewFile(_ name: String) -> String? {
        var ns: String?
        var rest = name
        if let r = name.range(of: "::") { ns = String(name[..<r.lowerBound]); rest = String(name[r.upperBound...]) }
        guard !rest.isEmpty, !rest.contains(" "), !rest.hasPrefix("."), !rest.hasSuffix(".") else { return nil }
        let rel = rest.replacingOccurrences(of: ".", with: "/")
        for dir in viewDirs(namespace: ns) {
            for ext in Self.viewExtensions {
                let f = dir + "/" + rel + ext
                if LaravelFS.isFile(f) { return f }
            }
        }
        return nil
    }

    // MARK: Blade component registrations

    struct ComponentRegistry {
        var aliases: [String: String] = [:]                 // alias -> FQCN
        var namespaces: [String: [String]] = [:]            // prefix -> PHP namespaces
        var anonymous: [(dir: String, prefix: String?)] = []
    }

    var componentRegistry: ComponentRegistry {
        let files = providerFiles
        return memo("components", stamp: stamp(files)) {
            var reg = ComponentRegistry()
            let aliasRe = try? NSRegularExpression(pattern: #"Blade::component\(\s*['"]([^'"]+)['"]\s*,\s*([\\\w]+)::class"#)
            let nsRe = try? NSRegularExpression(pattern: #"componentNamespace\(\s*['"]([^'"]+)['"]\s*,\s*['"]([^'"]+)['"]"#)
            let anonRe = try? NSRegularExpression(pattern: #"anonymousComponentPath\(\s*(.+?)\s*(?:,\s*['"]([^'"]*)['"])?\s*\)\s*;"#)
            for f in files {
                guard let t = LaravelFS.text(f) else { continue }
                let s = t as String, full = NSRange(location: 0, length: t.length)
                let info = self.useInfo(t)
                aliasRe?.enumerateMatches(in: s, range: full) { m, _, _ in
                    guard let m else { return }
                    let cls = t.substring(with: m.range(at: 2))
                    let first = String(cls.split(separator: "\\").first ?? "")
                    let fq = info.aliases[first].map { cls.contains("\\") ? $0 + "\\" + cls.dropFirst(first.count + 1) : $0 }
                        ?? (cls.hasPrefix("\\") ? cls : (info.namespace.isEmpty ? cls : info.namespace + "\\" + cls))
                    reg.aliases[t.substring(with: m.range(at: 1))] = fq
                }
                nsRe?.enumerateMatches(in: s, range: full) { m, _, _ in
                    guard let m else { return }
                    let ns = t.substring(with: m.range(at: 1)).replacingOccurrences(of: "\\\\", with: "\\")
                    reg.namespaces[t.substring(with: m.range(at: 2)), default: []].append(ns)
                }
                anonRe?.enumerateMatches(in: s, range: full) { m, _, _ in
                    guard let m, let dir = self.evalPathExpr(t.substring(with: m.range(at: 1)), relativeTo: f) else { return }
                    let prefix = m.range(at: 2).location != NSNotFound ? t.substring(with: m.range(at: 2)) : nil
                    reg.anonymous.append((dir, prefix))
                }
            }
            return reg
        }
    }
}

/// Cheap name tables for completion providers.
enum LaravelIndex {
    /// `users.index`, `layouts.app`, ... for every Blade view under resources/views (cached ~5 s and until invalidated).
    static func viewNames(root: URL) -> [String] {
        let project = LaravelProject.project(at: root.standardizedFileURL.path)
        let dir = project.abs("resources/views")
        let ticks = Int64(Date().timeIntervalSince1970 / 5)
        return project.memo("viewNames", stamp: LaravelFS.mtime(dir) &+ ticks) {
            var names: [String] = []
            guard let en = FileManager.default.enumerator(atPath: dir) else { return names }
            for case let rel as String in en {
                guard rel.hasSuffix(".blade.php") || rel.hasSuffix(".php") else { continue }
                if rel.hasPrefix("vendor/") { continue }
                let base = rel.hasSuffix(".blade.php") ? String(rel.dropLast(10)) : String(rel.dropLast(4))
                names.append(base.replacingOccurrences(of: "/", with: "."))
            }
            return names.sorted()
        }
    }

    static func routeNames(root: URL) -> [String] {
        let project = LaravelProject.project(at: root.standardizedFileURL.path)
        return LaravelRouteIndex.routes(project).keys.sorted()
    }
}
