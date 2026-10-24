import Foundation

/// PHP built-in stubs (classes, interfaces, enums, functions, constants of PHP 8.3 and the common extensions), derived from JetBrains'
/// phpstorm-stubs (Apache-2.0) by scripts/make-php-stubs.py and shipped as `PhpStubs/` (Contents/Resources in the .app, the repo root
/// for `swift build`). See docs/native-php.md, "Built-in stubs".
///
/// Footprint rules: nothing is read until the first lookup. `index.txt` (sorted, tab separated, ~600 KB) is memory mapped and
/// binary-searched in place (no dictionary), a lookup touches a few pages. A class is one small file that the normal fast-tier
/// parser reads on demand; parsed stub classes live in a 24-entry cache of their own. Functions and constants are grouped per upstream
/// file (<= ~60 KB) and read through the shared 6-entry `NPFiles` text cache.
struct PHPStubEntry {
    /// "c" class-like, "f" function, "k" constant.
    var kind: Character
    var name: String
    /// Absolute path of the stub file.
    var path: String
    /// UTF-16 offset of the name in the stub file.
    var loc: Int
    /// UTF-16 offset of the declaration start (after its docblock).
    var declStart: Int
    /// class: class / interface / trait / enum; function and constant: extension.
    var extra: String
    /// Function only: `name(params): ret`.
    var signature: String
}

enum PHPStubs {
    static let dirName = "PhpStubs"
    /// Set by self-tests to point at another directory (nil = locate the bundled one).
    static var rootOverride: String?

    // MARK: Location

    private static let lock = NSLock()
    private static var resolvedRoot: String?
    private static var rootResolved = false
    private static var indexData: Data?
    private static var indexTried = false
    private(set) static var lookupCount = 0
    private(set) static var classParseCount = 0

    /// Absolute directory of the stubs, resolved once (bundle Resources, then walking up from the executable for `swift build` / tests).
    static var root: String? {
        lock.lock(); defer { lock.unlock() }
        return rootLocked()
    }

    private static func rootLocked() -> String? {
        if let o = rootOverride { return o }
        if rootResolved { return resolvedRoot }
        rootResolved = true
        let fm = FileManager.default
        func ok(_ u: URL) -> Bool { fm.fileExists(atPath: u.appendingPathComponent("index.txt").path) }
        if let env = ProcessInfo.processInfo.environment["CE_PHP_STUBS"], ok(URL(fileURLWithPath: env)) { resolvedRoot = env; return env }
        if let res = Bundle.main.resourceURL?.appendingPathComponent(dirName), ok(res) { resolvedRoot = res.path; return res.path }
        var url = Bundle.main.executableURL?.deletingLastPathComponent()
        for _ in 0..<7 {
            guard let u = url else { break }
            let c = u.appendingPathComponent(dirName)
            if ok(c) { resolvedRoot = c.path; return c.path }
            url = u.deletingLastPathComponent()
        }
        return nil
    }

    /// True when `path` lies inside the stub directory (cheap textual pre-check, then the real root).
    static func isStubFile(_ path: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let r = rootLocked() else { return false }
        if r != slashRoot.0 { slashRoot = (r, r + "/") }
        return path.hasPrefix(slashRoot.1)
    }
    private static var slashRoot: (String, String) = ("", "")

    static var isLoaded: Bool { lock.lock(); defer { lock.unlock() }; return indexData != nil }

    /// Drops the mapped index and the parsed class cache (tests; also frees memory on demand).
    static func reset() {
        lock.lock()
        indexData = nil; indexTried = false; lookupCount = 0; classParseCount = 0
        rootResolved = false; resolvedRoot = nil
        lock.unlock()
        cacheLock.lock(); classCache.removeAll(); classOrder.removeAll(); cacheLock.unlock()
    }

    private static func loadIndexLocked() -> Data? {
        if let d = indexData { return d }
        if indexTried { return nil }
        indexTried = true
        guard let r = rootLocked(), let d = try? Data(contentsOf: URL(fileURLWithPath: r + "/index.txt"), options: .alwaysMapped) else { return nil }
        indexData = d
        return d
    }

    // MARK: Lookup

    private static func entry(from line: ArraySlice<UInt8>, root r: String) -> PHPStubEntry? {
        let f = line.split(separator: 9, omittingEmptySubsequences: false)
        guard f.count >= 7, let k = f[0].first else { return nil }
        func s(_ x: ArraySlice<UInt8>) -> String { String(decoding: x, as: UTF8.self) }
        return PHPStubEntry(kind: Character(UnicodeScalar(k)), name: s(f[2]), path: r + "/" + s(f[3]), loc: Int(s(f[4])) ?? 0, declStart: Int(s(f[5])) ?? 0,
                            extra: s(f[6]), signature: f.count > 7 ? s(f[7]) : "")
    }

    /// Lines whose first bytes equal `prefix` ("c\tdatetime\t" for an exact name, "c\tdat" for a prefix scan), at most `limit`.
    private static func scan(_ prefix: String, limit: Int) -> [PHPStubEntry] {
        lock.lock()
        lookupCount += 1
        let data = loadIndexLocked()
        let r = rootLocked()
        lock.unlock()
        guard let data, let r else { return [] }
        let key = Array(prefix.utf8)
        var out: [PHPStubEntry] = []
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let b = raw.bindMemory(to: UInt8.self)
            let n = b.count
            // compare the line starting at `s` with `key`: <0 line < key, 0 line has the key as prefix, >0 line > key
            func cmp(_ s: Int) -> Int {
                var i = 0
                while i < key.count {
                    if s + i >= n || b[s + i] == 10 { return -1 }
                    if b[s + i] != key[i] { return b[s + i] < key[i] ? -1 : 1 }
                    i += 1
                }
                return 0
            }
            var lo = 0, hi = n
            while lo < hi {
                let mid = (lo + hi) / 2
                var s = mid
                while s > lo, b[s - 1] != 10 { s -= 1 }
                if cmp(s) < 0 {
                    var e = s
                    while e < n, b[e] != 10 { e += 1 }
                    lo = e + 1
                } else { hi = s }
            }
            var p = lo
            while p < n, out.count < limit, cmp(p) == 0 {
                var e = p
                while e < n, b[e] != 10 { e += 1 }
                if let en = entry(from: ArraySlice(b[p..<e]), root: r) { out.append(en) }
                p = e + 1
            }
        }
        return out
    }

    private static func norm(_ s: String) -> String { s.hasPrefix("\\") ? String(s.dropFirst()) : s }

    static func classEntry(_ fqn: String) -> PHPStubEntry? { scan("c\t" + norm(fqn).lowercased() + "\t", limit: 1).first }
    static func functionEntry(_ name: String) -> PHPStubEntry? { scan("f\t" + norm(name).lowercased() + "\t", limit: 1).first }
    static func constantEntry(_ name: String) -> PHPStubEntry? { scan("k\t" + norm(name) + "\t", limit: 1).first }

    static func hasClass(_ fqn: String) -> Bool { classEntry(fqn) != nil }
    static func classPath(_ fqn: String) -> String? { classEntry(fqn)?.path }

    /// Names starting with `prefix` (case-insensitive for classes and functions, case-sensitive for constants).
    static func search(kind: Character, prefix: String, limit: Int) -> [PHPStubEntry] {
        let p = kind == "k" ? prefix : prefix.lowercased()
        return scan(String(kind) + "\t" + p, limit: limit)
    }

    // MARK: Parsed class cache (bounded)

    private static let cacheLock = NSLock()
    private static var classCache: [String: FTClass?] = [:]
    private static var classOrder: [String] = []
    static let maxCachedClasses = 24

    /// Frees the parsed stub classes (the mapped index stays: it is file backed and clean).
    static func dropParsed() { cacheLock.lock(); classCache.removeAll(); classOrder.removeAll(); cacheLock.unlock() }

    static var cachedClassCount: Int { cacheLock.lock(); defer { cacheLock.unlock() }; return classCache.count }

    /// Parsed class of a stub file (`path` from `classPath`), cached up to `maxCachedClasses` (oldest dropped first).
    static func classInfo(path: String, parse: () -> FTClass?) -> FTClass? {
        cacheLock.lock()
        if let hit = classCache[path] {
            if let i = classOrder.firstIndex(of: path) { classOrder.remove(at: i); classOrder.append(path) }
            cacheLock.unlock()
            return hit
        }
        cacheLock.unlock()
        let cls = parse()
        lock.lock(); classParseCount += 1; lock.unlock()
        cacheLock.lock(); defer { cacheLock.unlock() }
        classCache[path] = .some(cls)
        classOrder.append(path)
        while classOrder.count > maxCachedClasses { classCache.removeValue(forKey: classOrder.removeFirst()) }
        return cls
    }
}
