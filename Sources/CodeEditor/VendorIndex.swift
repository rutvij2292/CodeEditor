import Foundation

/// One vendor class/interface/trait/enum (or, for lazy member search, a member of one).
struct VendorEntry {
    let fqn: String                 // Illuminate\Http\Request
    let package: String             // laravel/framework
    let version: String             // v11.9.2 (may be empty)
    let relativePath: String        // path relative to the project root (symlink spelling, e.g. vendor/laravel/framework/src/...)
    let path: String                // absolute path
    var kind: CodeSymbol.Kind
    let isAbstract: Bool
    let isFinal: Bool
    let score: Int
    var member: CodeSymbol? = nil   // set for member hits (method/property/constant)

    var shortName: String { member?.name ?? String(fqn.split(separator: "\\").last ?? Substring(fqn)) }
    var namespace: String {
        guard let i = fqn.lastIndex(of: "\\") else { return "" }
        return String(fqn[..<i])
    }
    /// Picker detail line (the picker truncates from the left, so the tag goes last): `Illuminate\Http · laravel/framework 11.9 · vendor`.
    var detail: String {
        let pkg = version.isEmpty ? package : "\(package) \(version.hasPrefix("v") ? String(version.dropFirst()) : version)"
        let scope = member != nil ? fqn : namespace
        return [scope, pkg, "vendor"].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// Composer `vendor/` index for Go to Class / Symbol / File. Class names come from Composer metadata into a compact,
/// memory-mapped on-disk table (see VendorFormat); members are extracted lazily per file.
final class VendorIndex {
    // MARK: settings / registry

    /// Merge vendor classes into Go to Class / Go to Symbol (default on). Go to File lists vendor files only with `ProjectIndex.includeVendor`.
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "vendorIndex.enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "vendorIndex.enabled") }
    }
    static var cacheDirectory = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Caches/CodeEditor/vendor-index", isDirectory: true)

    private static let registryLock = NSLock()
    private static var registry: [String: VendorIndex] = [:]

    static func shared(for root: URL) -> VendorIndex {
        let key = root.standardizedFileURL.path
        registryLock.lock(); defer { registryLock.unlock() }
        if let i = registry[key] { return i }
        let i = VendorIndex(root: root.standardizedFileURL)
        registry[key] = i
        return i
    }

    /// Call when composer.lock / vendor/composer/installed.json changed (or after composer install/update).
    static func invalidate(root: URL) { shared(for: root).refreshIfNeeded(force: true) }

    private static var markerCache: [String: Bool] = [:]
    /// True for files below a Composer `vendor/` directory (integrator: open these tabs read-only with a banner).
    static func isLibraryFile(_ url: URL) -> Bool {
        let comps = url.standardizedFileURL.pathComponents
        guard comps.count > 1 else { return false }
        for (i, c) in comps.enumerated() where c == "vendor" && i + 1 < comps.count - 0 {
            let base = "/" + comps[1...i].joined(separator: "/")
            registryLock.lock(); let cached = markerCache[base]; registryLock.unlock()
            let ok = cached ?? (VendorBuilder.exists(base + "/autoload.php") || VendorBuilder.isDir(base + "/composer"))
            if cached == nil { registryLock.lock(); markerCache[base] = ok; registryLock.unlock() }
            if ok { return true }
        }
        return false
    }

    // MARK: instance state

    let root: URL
    private let lock = NSLock()
    private var table: VendorTable?
    private var building = false
    private var lastCheck = Date.distantPast
    private let queue = DispatchQueue(label: "vendor-index", qos: .utility)
    private var kindCache: [String: (CodeSymbol.Kind, UInt8)] = [:]
    private var symbolCache: [String: [CodeSymbol]] = [:]
    private var symbolOrder: [String] = []
    private var filePackages: [(name: String, rootRel: String, rootAbs: String)]?
    private var fileBlobs: [String: Data] = [:]
    private var fileOrder: [String] = []
    private var fileBytes = 0
    static let fileCacheLimit = 6_000_000

    init(root: URL) { self.root = root }

    var cacheFile: URL {
        VendorIndex.cacheDirectory.appendingPathComponent(String(format: "%016llx.bin", VendorFormat.fnv(root.path)))
    }

    var classCount: Int { lock.lock(); defer { lock.unlock() }; return table?.count ?? 0 }
    var isBuilding: Bool { lock.lock(); defer { lock.unlock() }; return building }
    var isReady: Bool { lock.lock(); defer { lock.unlock() }; return table != nil }

    // MARK: loading / building

    private func loadCache() -> VendorTable? {
        guard let d = try? Data(contentsOf: cacheFile, options: .alwaysMapped) else { return nil }
        guard let t = VendorTable(data: d) else { try? FileManager.default.removeItem(at: cacheFile); return nil }
        return t
    }

    /// Loads the cache synchronously when nothing is loaded yet (a few ms: it only maps the file).
    private func ensureLoaded() {
        lock.lock(); let have = table != nil; lock.unlock()
        guard !have, let t = loadCache() else { return }
        lock.lock(); if table == nil { table = t }; lock.unlock()
    }

    /// Checks the cache key (composer.lock hash, installed.json mtime, index version) and rebuilds in the background
    /// when it changed. Cheap enough to call on every project open / picker open (throttled to once per 3 s unless forced).
    func refreshIfNeeded(force: Bool = false, completion: (() -> Void)? = nil) {
        lock.lock()
        if building || (!force && Date().timeIntervalSince(lastCheck) < 3) { lock.unlock(); completion.map { c in DispatchQueue.main.async(execute: c) }; return }
        building = true; lastCheck = Date()
        lock.unlock()
        queue.async { [self] in
            defer {
                lock.lock(); building = false; lock.unlock()
                if let completion { DispatchQueue.main.async(execute: completion) }
            }
            let rootPath = root.path
            let sources = VendorBuilder.discoverSources(root: rootPath)
            lock.lock(); filePackages = nil; lock.unlock()
            if sources.isEmpty { lock.lock(); table = nil; lock.unlock(); return }
            let key = VendorBuilder.currentKey(sources)
            lock.lock(); var current = table; lock.unlock()
            if current == nil { current = loadCache() }
            if let current, current.key == key {
                lock.lock(); table = current; lock.unlock()
                return
            }
            if let current { lock.lock(); table = current; lock.unlock() }   // serve stale results while rebuilding
            var data = autoreleasepool { () -> Data in
                let built = VendorBuilder.build(root: rootPath, sources: sources, old: current)
                return VendorFormat.serialize(key: built.key, packages: built.packages)
            }
            defer { data = Data(); malloc_zone_pressure_relief(nil, 0) }   // give the transient build memory back
            let fm = FileManager.default
            try? fm.createDirectory(at: VendorIndex.cacheDirectory, withIntermediateDirectories: true)
            let tmp = cacheFile.appendingPathExtension("tmp\(getpid())")
            if (try? data.write(to: tmp)) != nil {
                _ = try? fm.replaceItemAt(cacheFile, withItemAt: tmp)
                if let t = loadCache() { lock.lock(); table = t; kindCache = [:]; lock.unlock(); return }
            }
            if let t = VendorTable(data: data) { lock.lock(); table = t; kindCache = [:]; lock.unlock() }
        }
    }

    /// Test helper: block until the current refresh finished.
    func waitUntilIdle() { while isBuilding { usleep(2000) } }

    // MARK: search

    private static let sepChars: Set<UInt8> = [47, 46, 95, 45, 32]

    /// Byte-level port of `Fuzzy.score` (text compared lowercased, `\` treated as `/`) plus a bonus for an exact short name.
    static func score(query q: [UInt8], text: UnsafeBufferPointer<UInt8>) -> Int? {
        let n = text.count
        @inline(__always) func norm(_ c: UInt8) -> UInt8 { c == 92 ? 47 : c }
        @inline(__always) func low(_ c: UInt8) -> UInt8 { c >= 65 && c <= 90 ? c + 32 : c }
        @inline(__always) func isUp(_ c: UInt8) -> Bool { c >= 65 && c <= 90 }
        var qi = 0, score = 0, prev = -2, first = -1
        var i = 0
        while i < n && qi < q.count {
            let c = norm(text[i])
            if low(c) == q[qi] {
                var s = 1
                if i == prev + 1 { s += 5 }
                if i == 0 || sepChars.contains(norm(text[i - 1])) { s += 8 }
                else if isUp(c) && !isUp(text[i - 1]) { s += 6 }
                score += s; prev = i
                if first < 0 { first = i }
                qi += 1
            }
            i += 1
        }
        guard qi == q.count else { return nil }
        // contiguous occurrence?
        if q.count <= n {
            var k = 0
            outer: while k + q.count <= n {
                for j in 0..<q.count where low(norm(text[k + j])) != q[j] { k += 1; continue outer }
                score += 20; break
            }
        }
        var nameStart = 0
        for j in stride(from: n - 1, through: 0, by: -1) where norm(text[j]) == 47 { nameStart = j + 1; break }
        if first >= nameStart { score += 25 }
        if n - nameStart == q.count, nameStart + q.count == n {
            var same = true
            for j in 0..<q.count where low(norm(text[nameStart + j])) != q[j] { same = false; break }
            if same { score += 30 }
        }
        return score - n / 8
    }

    static func normalizedQuery(_ s: String) -> [UInt8] {
        s.utf8.filter { $0 != 32 && $0 != 9 }.map { $0 == 92 ? 47 : ($0 >= 65 && $0 <= 90 ? $0 + 32 : $0) }
    }

    /// Fuzzy class search over the mapped table. `typesOnly == false` additionally searches members of the best-matching
    /// classes and of recently opened vendor files (lazy, needs >= 3 characters).
    func search(_ query: String, limit: Int, typesOnly: Bool) -> [VendorEntry] {
        var out = searchTypes(query, limit: limit)
        if !typesOnly, query.filter({ !$0.isWhitespace }).count >= 3 {
            out.append(contentsOf: searchMembers(query, limit: max(0, limit - out.count)))
        }
        return Array(out.prefix(limit))
    }

    private static func better(_ a: (score: Int, len: Int, index: Int), _ b: (score: Int, len: Int, index: Int)) -> Bool {
        (a.score, -a.len, -a.index) > (b.score, -b.len, -b.index)
    }

    func searchTypes(_ query: String, limit: Int) -> [VendorEntry] {
        ensureLoaded()
        let q = Self.normalizedQuery(query)
        lock.lock(); let t = table; lock.unlock()
        guard let t, !q.isEmpty, limit > 0 else { return [] }
        var hits: [(score: Int, len: Int, index: Int)] = []
        t.scanNames { i, bytes in
            // cheap subsequence prefilter
            var qi = 0
            for b in bytes {
                let c = b == 92 ? 47 : (b >= 65 && b <= 90 ? b + 32 : b)
                if c == q[qi] { qi += 1; if qi == q.count { break } }
            }
            guard qi == q.count, let s = Self.score(query: q, text: bytes) else { return }
            hits.append((s, bytes.count, i))
            if hits.count >= max(4096, limit * 4) { hits.sort(by: Self.better); hits.removeSubrange(limit...) }   // keep memory bounded
        }
        hits.sort(by: Self.better)
        var out: [VendorEntry] = []
        for (rank, h) in hits.prefix(limit).enumerated() {
            guard let r = t.row(h.index) else { continue }
            var e = entry(from: r, table: t, score: h.score)
            if rank < 25 { e = resolvingKind(e) }
            out.append(e)
        }
        return out
    }

    private func entry(from r: VendorTable.Row, table t: VendorTable, score: Int) -> VendorEntry {
        let p = t.package(r.pkg)
        let rel = r.rel.isEmpty ? p.root : p.root + "/" + r.rel
        let abs = rel.hasPrefix("/") ? rel : root.path + "/" + rel
        let kind: CodeSymbol.Kind
        switch VendorFormat.Kind(rawValue: r.kind) ?? .unknown {
        case .interface: kind = .interface
        case .trait: kind = .trait
        case .enum: kind = .enum
        default: kind = .class
        }
        var e = VendorEntry(fqn: r.fqn, package: p.name, version: p.version, relativePath: rel, path: abs, kind: kind,
                            isAbstract: r.flags & VendorFormat.flagAbstract != 0, isFinal: r.flags & VendorFormat.flagFinal != 0, score: score)
        if r.kind == 0 {
            lock.lock(); let k = kindCache[abs + "|" + r.fqn]; lock.unlock()
            if let k { e.kind = k.0 }
        }
        return e
    }

    /// Exact FQN lookup (binary search); handles a leading backslash. Used for go-to-definition style jumps.
    func find(fqn: String) -> [VendorEntry] {
        ensureLoaded()
        lock.lock(); let t = table; lock.unlock()
        guard let t else { return [] }
        return t.find(fqn: fqn).compactMap { t.row($0).map { entry(from: $0, table: t, score: 0) } }
    }

    // MARK: kind resolution (declaration keyword read lazily from the file head, only for displayed rows)

    private func resolvingKind(_ e: VendorEntry) -> VendorEntry {
        let key = e.path + "|" + e.fqn
        lock.lock(); let known = kindCache[key]; lock.unlock()
        if known != nil { return e }
        guard let fh = FileHandle(forReadingAtPath: e.path) else { return e }
        let head = fh.readData(ofLength: 48 * 1024)
        fh.closeFile()
        let text = String(decoding: head, as: UTF8.self)
        let name = NSRegularExpression.escapedPattern(for: e.shortName)
        guard let re = try? NSRegularExpression(pattern: "^[ \\t]*((?:(?:abstract|final|readonly)[ \\t]+)*)(class|interface|trait|enum)[ \\t]+\(name)\\b",
                                                options: [.anchorsMatchLines]),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return e }
        let ns = text as NSString
        let mods = ns.substring(with: m.range(at: 1)), kw = ns.substring(with: m.range(at: 2))
        let kind: CodeSymbol.Kind = kw == "interface" ? .interface : kw == "trait" ? .trait : kw == "enum" ? .enum : .class
        var flags: UInt8 = 0
        if mods.contains("abstract") { flags |= VendorFormat.flagAbstract }
        if mods.contains("final") { flags |= VendorFormat.flagFinal }
        lock.lock()
        if kindCache.count > 4000 { kindCache.removeAll() }
        kindCache[key] = (kind, flags)
        lock.unlock()
        var out = e
        out.kind = kind
        return VendorEntry(fqn: out.fqn, package: out.package, version: out.version, relativePath: out.relativePath, path: out.path,
                           kind: kind, isAbstract: flags & VendorFormat.flagAbstract != 0, isFinal: flags & VendorFormat.flagFinal != 0,
                           score: out.score)
    }

    // MARK: lazy symbols

    /// Symbols (types + members) of one vendor file; extracted on demand and kept in a small LRU.
    func symbols(inFile path: String) -> [CodeSymbol] {
        lock.lock()
        if let c = symbolCache[path] { symbolOrder.removeAll { $0 == path }; symbolOrder.append(path); lock.unlock(); return c }
        lock.unlock()
        guard let d = try? Data(contentsOf: URL(fileURLWithPath: path)), d.count <= SymbolIndex.maxFileSize,
              let text = String(data: d, encoding: .utf8) ?? String(data: d, encoding: .isoLatin1) else { return [] }
        SymbolExtractor.prime()
        let syms = SymbolExtractor.symbols(in: text, fileExtension: (path as NSString).pathExtension)
        lock.lock()
        symbolCache[path] = syms; symbolOrder.append(path)
        while symbolOrder.count > 48 { symbolCache[symbolOrder.removeFirst()] = nil }
        lock.unlock()
        return syms
    }

    /// 1-based line of the class declaration (opens the file's symbols lazily); 1 when unknown.
    func declarationLine(of e: VendorEntry) -> Int {
        if let m = e.member { return m.line }
        return symbols(inFile: e.path).first { $0.isType && $0.name == e.shortName }?.line ?? 1
    }

    /// Members of the classes best matching the query (`Request::input`, `Request input` or just `input` among recently
    /// opened vendor files). Never parses more than `maxFiles` files per call.
    func searchMembers(_ query: String, limit: Int, maxFiles: Int = 12) -> [VendorEntry] {
        guard limit > 0 else { return [] }
        var classPart: String? = nil, memberPart = query
        for sep in ["::", "->", "#"] {
            if let r = query.range(of: sep) { classPart = String(query[..<r.lowerBound]); memberPart = String(query[r.upperBound...]); break }
        }
        let mq = Self.normalizedQuery(memberPart)
        var files: [(VendorEntry, [CodeSymbol])] = []
        var seen = Set<String>()
        let candidates = searchTypes(classPart ?? query, limit: maxFiles)
        for c in candidates where seen.insert(c.path).inserted { files.append((c, symbols(inFile: c.path))) }
        if classPart == nil {
            lock.lock(); let cached = symbolOrder.reversed(); lock.unlock()
            for p in cached where seen.insert(p).inserted {
                lock.lock(); let syms = symbolCache[p] ?? []; lock.unlock()
                if let t = syms.first(where: { $0.isType }) {
                    files.append((VendorEntry(fqn: (t.container.map { $0 + "\\" } ?? "") + t.name, package: "", version: "", relativePath: p, path: p,
                                              kind: t.kind, isAbstract: false, isFinal: false, score: 0), syms))
                }
            }
        }
        var out: [VendorEntry] = []
        for (c, syms) in files {
            for s in syms where !s.isType && s.kind != .namespace && s.container != nil {
                let score: Int
                if mq.isEmpty { score = 0 }
                else if let sc = s.name.utf8.withContiguousStorageIfAvailable({ Self.score(query: mq, text: $0) }) ?? nil { score = sc }
                else { continue }
                var e = c
                e = VendorEntry(fqn: c.fqn, package: c.package, version: c.version, relativePath: c.relativePath, path: c.path,
                                kind: s.kind, isAbstract: false, isFinal: false, score: score + c.score / 4, member: s)
                out.append(e)
            }
        }
        out.sort { $0.score > $1.score }
        return Array(out.prefix(limit))
    }

    // MARK: Go to File (lazy per-package listing)

    private func packagesForFiles() -> [(name: String, rootRel: String, rootAbs: String)] {
        lock.lock(); let cached = filePackages; lock.unlock()
        if let cached { return cached }
        var out: [(String, String, String)] = []
        for s in VendorBuilder.discoverSources(root: root.path) {
            for p in VendorBuilder.readPackages(s) {
                out.append((p.name, VendorBuilder.relativeToProject(p.root, root.path), p.root))
            }
        }
        lock.lock(); filePackages = out; lock.unlock()
        return out
    }

    private func blob(for p: (name: String, rootRel: String, rootAbs: String)) -> Data {
        lock.lock()
        if let b = fileBlobs[p.rootAbs] { fileOrder.removeAll { $0 == p.rootAbs }; fileOrder.append(p.rootAbs); lock.unlock(); return b }
        lock.unlock()
        var bytes = [UInt8]()
        let prefix = (p.rootRel.hasPrefix("/") ? p.rootRel : p.rootRel) + "/"
        VendorBuilder.walkAll(p.rootAbs, skip: { $0 == "node_modules" || $0 == ".git" }) { rel in
            bytes.append(contentsOf: prefix.utf8); bytes.append(contentsOf: rel.utf8); bytes.append(10)
        }
        let d = Data(bytes)
        lock.lock()
        fileBlobs[p.rootAbs] = d; fileOrder.append(p.rootAbs); fileBytes += d.count
        while fileBytes > Self.fileCacheLimit, fileOrder.count > 1 {
            let old = fileOrder.removeFirst()
            if let b = fileBlobs.removeValue(forKey: old) { fileBytes -= b.count }
        }
        lock.unlock()
        return d
    }

    /// Warms the per-package listing cache in the background (call when Go to File opens with includeVendor).
    func prewarmFiles() {
        queue.async { [self] in for p in packagesForFiles() { _ = blob(for: p) } }
    }

    /// Fuzzy file search over vendor files (paths relative to the project root). Walks uncached packages on demand.
    func searchFiles(_ query: String, limit: Int) -> [(path: String, score: Int)] {
        let q = Self.normalizedQuery(query)
        guard !q.isEmpty, limit > 0 else { return [] }
        var hits: [(path: String, score: Int)] = []
        for p in packagesForFiles() {
            let d = blob(for: p)
            d.withUnsafeBytes { raw in
                let buf = raw.bindMemory(to: UInt8.self)
                var start = 0
                for i in 0..<buf.count where buf[i] == 10 {
                    let line = UnsafeBufferPointer(rebasing: buf[start..<i])
                    start = i + 1
                    var qi = 0
                    for b in line {
                        let c = b >= 65 && b <= 90 ? b + 32 : b
                        if c == q[qi] { qi += 1; if qi == q.count { break } }
                    }
                    guard qi == q.count, let s = Self.score(query: q, text: line) else { continue }
                    hits.append((String(decoding: line, as: UTF8.self), s))
                }
            }
        }
        hits.sort { $0.score > $1.score }
        return Array(hits.prefix(limit))
    }

    /// True when the project's vendor tree is small enough to be listed inline by ProjectIndex (<= `limit` files).
    static func vendorIsSmall(root: URL, limit: Int = 3000) -> Bool {
        var n = 0
        var small = true
        let vendor = root.path + "/vendor"
        guard VendorBuilder.isDir(vendor) else { return true }
        VendorBuilder.walkAll(vendor, skip: { $0 == "node_modules" || $0 == ".git" }, limit: limit) { _ in n += 1; if n > limit { small = false } }
        return small
    }
}
