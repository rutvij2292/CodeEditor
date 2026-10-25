import Foundation

/// The import graph of a project, only as much as find usages needs: per file the module specifiers it imports / re-exports, found by a
/// byte-level scan (no parse), cached by mtime+size and capped. A symbol declared in file D can only be named in files that import D
/// directly, or import a file that re-exports it, so a search parses just those files instead of everything that contains the name.
struct NJSEdge {
    var spec: String
    var reexport: Bool          // `export ... from`, `export * from`, `module.exports = require(...)`
    var binding: Bool           // default / namespace / require binding: the local name is arbitrary, so the file can't be found by the symbol's name
}

final class NJSFileScan {
    var stamp: Int64 = 0
    var edges: [NJSEdge] = []
    var exportsList = false     // `export { a }` / `export default someIdentifier`: may re-export an imported binding
    var cfgStamp: Int64 = 0
    var resolved: [String?] = []
    var rechecked = false       // loaded from disk: unresolved specifiers were looked up again in this process
    var cost: Int { 120 + edges.reduce(0) { $0 + $1.spec.utf8.count + 40 } }
}

enum NJSScanner {
    @inline(__always) private static func isIdent(_ c: UInt8) -> Bool { (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 36 || c >= 128 }
    private static func word(_ b: UnsafeBufferPointer<UInt8>, endingAt end: Int, _ w: StaticString) -> Bool {
        let n = w.utf8CodeUnitCount
        let s = end - n
        guard s >= 0, end <= b.count else { return false }
        let p = w.utf8Start
        for i in 0..<n where b[s + i] != p[i] { return false }
        return s == 0 || !isIdent(b[s - 1])
    }
    private static func has(_ b: UnsafeBufferPointer<UInt8>, at i: Int, _ w: StaticString) -> Bool {
        let n = w.utf8CodeUnitCount
        guard i >= 0, i + n <= b.count else { return false }
        let p = w.utf8Start
        for k in 0..<n where b[i + k] != p[k] { return false }
        return i + n == b.count || !isIdent(b[i + n])
    }
    private static func contains(_ b: UnsafeBufferPointer<UInt8>, from: Int, to: Int, _ w: StaticString) -> Bool {
        let n = w.utf8CodeUnitCount
        var i = max(0, from)
        while i + n <= min(to, b.count) { if b[i] == w.utf8Start[0], has2(b, i, w) { return true }; i += 1 }
        return false
    }
    private static func has2(_ b: UnsafeBufferPointer<UInt8>, _ i: Int, _ w: StaticString) -> Bool {
        let p = w.utf8Start
        for k in 0..<w.utf8CodeUnitCount where b[i + k] != p[k] { return false }
        return true
    }

    /// Very long lines on average: bundled / minified code.
    static func looksMinified(_ b: UnsafeBufferPointer<UInt8>) -> Bool {
        let n = min(b.count, 100_000)
        guard n >= 20_000 else { return false }
        var lines = 1
        for i in 0..<n where b[i] == 10 { lines += 1 }
        return n / lines > 400
    }

    static func scan(_ text: NSString) -> NJSFileScan {
        var s = text as String
        return s.withUTF8 { scan($0) }
    }

    /// Specifiers of every import form in UTF-8 `b` (no parse; imports are ASCII punctuation around the string).
    static func scan(_ b: UnsafeBufferPointer<UInt8>) -> NJSFileScan {
        let out = NJSFileScan()
        let n = b.count
        guard n > 0, n < 3_000_000 else { return out }
        var i = 0
        while i < n {
            let c = b[i]
            if c == 101, i == 0 || !isIdent(b[i - 1]), has(b, at: i, "export") {          // export
                var j = i + 6
                while j < n, b[j] == 32 || b[j] == 9 || b[j] == 10 || b[j] == 13 { j += 1 }
                if j < n, b[j] == 123 { out.exportsList = true }
                else if has(b, at: j, "default") {
                    j += 7
                    while j < n, b[j] == 32 || b[j] == 9 { j += 1 }
                    if j < n, isIdent(b[j]), !(has(b, at: j, "function") || has(b, at: j, "class") || has(b, at: j, "async") || has(b, at: j, "abstract")
                        || has(b, at: j, "interface") || has(b, at: j, "enum") || has(b, at: j, "await") || has(b, at: j, "new") || has(b, at: j, "typeof")) { out.exportsList = true }
                }
                i += 6; continue
            }
            if c == 39 || c == 34 || c == 96 {
                // a module specifier: `from 'x'`, `import 'x'`, `require('x')`, `import('x')`
                var j = i - 1
                while j >= 0, b[j] == 32 || b[j] == 9 || b[j] == 10 || b[j] == 13 { j -= 1 }
                var kind = 0                       // 1 from, 2 bare import, 3 call
                var keywordEnd = j + 1
                if j >= 3, word(b, endingAt: j + 1, "from") { kind = 1 }
                else if j >= 5, word(b, endingAt: j + 1, "import") { kind = 2 }
                else if j >= 0, b[j] == 40 {
                    var k = j - 1
                    while k >= 0, b[k] == 32 { k -= 1 }
                    if word(b, endingAt: k + 1, "require") || word(b, endingAt: k + 1, "import") { kind = 3; keywordEnd = k + 1 }
                }
                if kind != 0 {
                    var e = i + 1
                    while e < n, e - i < 400, b[e] != c, b[e] != 10 { e += 1 }
                    if e < n, b[e] == c, e > i + 1 {
                        let spec = String(decoding: UnsafeBufferPointer(rebasing: b[(i + 1)..<e]), as: UTF8.self)
                        var reexport = false, binding = false
                        if kind == 1 {
                            // nearest `import` / `export` keyword before `from`
                            var k = j - 4, found = 0, kwStart = 0
                            while k >= 0, j - k < 4000 {
                                if b[k] == 116, k >= 5, word(b, endingAt: k + 1, "export") { found = 2; kwStart = k + 1; break }       // 't' of export / import
                                if b[k] == 116, k >= 5, word(b, endingAt: k + 1, "import") { found = 1; kwStart = k + 1; break }
                                k -= 1
                            }
                            reexport = found == 2
                            if found == 1 {
                                var p = kwStart
                                while p < j - 3, b[p] == 32 || b[p] == 10 || b[p] == 13 || b[p] == 9 { p += 1 }
                                if has(b, at: p, "type") { p += 4; while p < j - 3, b[p] == 32 { p += 1 } }
                                binding = p < j - 3 && b[p] != 123            // `import X`, `import * as X`, `import X, { y }`
                            }
                        } else if kind == 3 {
                            binding = true
                            var k = keywordEnd - 8, seen = 0
                            while k >= 0, seen < 60 { if b[k] == 10 { break }; k -= 1; seen += 1 }
                            reexport = contains(b, from: max(0, k), to: keywordEnd, "exports")
                        }
                        out.edges.append(NJSEdge(spec: spec, reexport: reexport, binding: binding))
                        i = e + 1; continue
                    }
                }
            }
            i += 1
        }
        return out
    }
}

/// Per-project cache of file scans (LRU-ish: wiped when over the cap) and candidate computation.
final class NJSImportGraph {
    private let lock = NSLock()
    private var scans: [String: NJSFileScan] = [:]
    private var cost = 0
    var misses = 0
    static let maxCost = 3_000_000

    func clear() { lock.lock(); scans.removeAll(); cost = 0; built = nil; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return scans.count }

    func scan(_ path: String, stamp: Int64, live: NSString?, cfgStamp: Int64, modules: NJSModules) -> NJSFileScan? {
        if live == nil {
            lock.lock()
            if let s = scans[path], s.stamp == stamp, s.cfgStamp == cfgStamp {
                lock.unlock()
                if !s.rechecked {                  // a file added since the scan may satisfy a specifier that did not resolve then
                    for (k, r) in s.resolved.enumerated() where r == nil { s.resolved[k] = modules.resolve(s.edges[k].spec, from: path) }
                    s.rechecked = true
                }
                return s
            }
            lock.unlock()
        }
        lock.lock(); misses += 1; lock.unlock()
        let s: NJSFileScan
        if let live {
            var str = live as String
            s = str.withUTF8 { NJSScanner.looksMinified($0) ? NJSFileScan() : NJSScanner.scan($0) }
        } else {
            // memory mapped: the scan reads the page cache directly, no copy of the file is made
            guard let d = try? Data(contentsOf: URL(fileURLWithPath: path), options: .alwaysMapped) else { return nil }
            if d.count > 1_500_000 { let e = NJSFileScan(); e.stamp = stamp; e.cfgStamp = cfgStamp; return e }      // bundles: no useful imports
            s = d.withUnsafeBytes { raw in
                let b = raw.bindMemory(to: UInt8.self)
                return NJSScanner.looksMinified(b) ? NJSFileScan() : NJSScanner.scan(b)
            }
        }
        s.stamp = stamp; s.cfgStamp = cfgStamp
        s.resolved = s.edges.map { modules.resolve($0.spec, from: path) }
        if live == nil {
            lock.lock()
            if let old = scans[path] { cost -= old.cost }
            if cost > NJSImportGraph.maxCost { scans.removeAll(); cost = 0 }
            scans[path] = s; cost += s.cost
            lock.unlock()
        }
        return s
    }

    struct Candidates {
        var files: Set<String>
        var viaBinding: Set<String>        // files importing a reachable module through a default / namespace / require binding
    }

    var dbg = (misses: 0, externals: 0, projectMs: 0.0, extMs: 0.0, bfsMs: 0.0, entries: 0)

    private var built: (key: Int, scanned: [String: NJSFileScan], reverse: [String: [(String, NJSEdge)]])?
    private var loadedFromDisk = false
    private var missesAtSave = 0

    typealias Built = (scanned: [String: NJSFileScan], reverse: [String: [(String, NJSEdge)]])

    /// The reverse import graph for the exact state `stateKey` (stamps + live buffers), built once and reused while it is unchanged.
    /// The first build of a process starts from the on-disk scan cache, so a relaunch only stats the files.
    func ensureBuilt(files: [String], live: [String: NSString], modules: NJSModules, stateKey: Int) -> Built {
        let cfg = modules.configStamp()
        var h = Hasher(); h.combine(stateKey); h.combine(cfg); h.combine(LaravelFS.mtime(modules.root + "/node_modules"))
        let key = h.finalize()
        lock.lock(); let cached = built; let needLoad = !loadedFromDisk; loadedFromDisk = true; lock.unlock()
        if let c = cached, c.key == key { return (c.scanned, c.reverse) }
        if needLoad { loadFromDisk(root: modules.root) }
        let t0 = NPStats.now()
        var scanned: [String: NJSFileScan] = [:]
        var reverse: [String: [(String, NJSEdge)]] = [:]
        // reading + scanning 600 files is I/O and byte crunching: split it over the cores
        let chunk = max(1, files.count / (ProcessInfo.processInfo.activeProcessorCount * 4))
        let chunks = (files.count + chunk - 1) / chunk
        let slots = NJSSlots<[(String, NJSFileScan?)]>(chunks)
        let body: (Int) -> Void = { c in
            var mine: [(String, NJSFileScan?)] = []
            for f in files[(c * chunk)..<min(files.count, (c + 1) * chunk)] {
                mine.append((f, self.scan(f, stamp: LaravelFS.mtime(f), live: live[f], cfgStamp: cfg, modules: modules)))
            }
            slots.set(c, mine)
        }
        if chunks > 1 && files.count > 24 { NJSRefs.parallel(chunks, body) } else { for c in 0..<chunks { body(c) } }
        for part in slots.values {
            for (f, s) in part ?? [] {
                guard let s else { continue }
                scanned[f] = s
                for (k, e) in s.edges.enumerated() { if let t = s.resolved[k] { reverse[t, default: []].append((f, e)) } }
            }
        }
        let t1 = NPStats.now()
        dbg.projectMs = Double(t1 &- t0) / 1e6
        // Files outside the enumerated project (node_modules typings) take part when a project file imports them: their own
        // re-export chains (`vue` -> runtime-dom -> runtime-core -> reactivity) are what connects a declaration to its users.
        var work: [String] = []
        var queued = Set(files)
        func enqueue(_ s: NJSFileScan) { for t in s.resolved { if let t, NJSEnv.isCode(t), queued.insert(t).inserted { work.append(t) } } }
        for s in scanned.values { enqueue(s) }
        var externals = 0
        while let x = work.popLast(), externals < 4000 {
            externals += 1
            guard let s = scan(x, stamp: LaravelFS.mtime(x), live: nil, cfgStamp: cfg, modules: modules) else { continue }
            scanned[x] = s
            for (k, e) in s.edges.enumerated() { if let t = s.resolved[k] { reverse[t, default: []].append((x, e)) } }
            if s.exportsList || s.edges.contains(where: { $0.reexport }) { enqueue(s) }      // only re-exporting files can lead further
        }
        dbg.extMs = Double(NPStats.now() &- t1) / 1e6; dbg.entries = count
        lock.lock(); built = (key, scanned, reverse); lock.unlock()
        saveToDiskIfNeeded(root: modules.root)
        return (scanned, reverse)
    }

    /// Files that can refer to a symbol declared in `declFiles`. `members`: any import chain counts (a type can reach a file through
    /// other modules' signatures); otherwise only re-exporting chains do.
    func candidates(declFiles: [String], members: Bool, files: [String], live: [String: NSString], modules: NJSModules, stateKey: Int) -> Candidates {
        let (scanned, reverse) = ensureBuilt(files: files, live: live, modules: modules, stateKey: stateKey)
        let t2 = NPStats.now()
        defer { dbg.bfsMs = Double(NPStats.now() &- t2) / 1e6 }
        var reach = Set(declFiles)
        var queue = declFiles
        var out = Candidates(files: [], viaBinding: [])
        while let f = queue.popLast() {
            for (g, e) in reverse[f] ?? [] {
                out.files.insert(g)
                if e.binding { out.viaBinding.insert(g) }
                if members || e.reexport || scanned[g]?.exportsList == true, reach.insert(g).inserted { queue.append(g) }
            }
        }
        return out
    }

    // MARK: on-disk scan cache (~/Library/Caches/CodeEditor/native-js/<project hash>.graph)

    static let diskVersion: UInt32 = 1
    static var cacheDirectory = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Caches/CodeEditor/native-js", isDirectory: true)

    static func cacheFile(_ root: String) -> URL {
        var h: UInt64 = 0xcbf29ce484222325                       // FNV-1a: stable across launches (Hasher is seeded per process)
        for b in root.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return cacheDirectory.appendingPathComponent(String(h, radix: 16) + ".graph")
    }

    private func saveToDiskIfNeeded(root: String) {
        lock.lock()
        let fresh = misses - missesAtSave
        missesAtSave = misses
        let snapshot = scans
        lock.unlock()
        guard fresh > 0, !snapshot.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async {
            var d = Data()
            func u16(_ v: Int) { var x = UInt16(min(v, 65535)); withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
            func u32(_ v: UInt32) { var x = v; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
            func i64(_ v: Int64) { var x = v; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
            func str(_ s: String) { let u = Array(s.utf8.prefix(65535)); u16(u.count); d.append(contentsOf: u) }
            d.append(contentsOf: Array("NJG".utf8)); u32(NJSImportGraph.diskVersion); u32(UInt32(snapshot.count))
            for (path, s) in snapshot {
                str(path); i64(s.stamp); i64(s.cfgStamp); d.append(s.exportsList ? 1 : 0); u16(s.edges.count)
                for (k, e) in s.edges.enumerated() {
                    str(e.spec); d.append((e.reexport ? 1 : 0) | (e.binding ? 2 : 0))
                    str(k < s.resolved.count ? (s.resolved[k] ?? "") : "")
                }
            }
            try? FileManager.default.createDirectory(at: NJSImportGraph.cacheDirectory, withIntermediateDirectories: true)
            try? d.write(to: NJSImportGraph.cacheFile(root), options: .atomic)
        }
    }

    private func loadFromDisk(root: String) {
        guard let d = try? Data(contentsOf: NJSImportGraph.cacheFile(root), options: .alwaysMapped), d.count > 11 else { return }
        var loaded: [String: NJSFileScan] = [:]
        var cost = 0
        d.withUnsafeBytes { raw in
            let b = raw.bindMemory(to: UInt8.self)
            var i = 0
            func u16() -> Int? { guard i + 2 <= b.count else { return nil }; defer { i += 2 }; return Int(b[i]) | Int(b[i + 1]) << 8 }
            func u32() -> UInt32? { guard i + 4 <= b.count else { return nil }; defer { i += 4 }; return UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24 }
            func i64() -> Int64? {
                guard i + 8 <= b.count else { return nil }
                var v: UInt64 = 0
                for k in 0..<8 { v |= UInt64(b[i + k]) << UInt64(8 * k) }
                i += 8
                return Int64(bitPattern: v)
            }
            func str() -> String? { guard let n = u16(), i + n <= b.count else { return nil }; defer { i += n }; return String(decoding: UnsafeBufferPointer(rebasing: b[i..<(i + n)]), as: UTF8.self) }
            guard b.count > 11, b[0] == 78, b[1] == 74, b[2] == 71 else { return }
            i = 3
            guard u32() == NJSImportGraph.diskVersion, let n = u32() else { return }
            for _ in 0..<Int(n) {
                guard let path = str(), let stamp = i64(), let cfg = i64(), i < b.count else { return }
                let s = NJSFileScan()
                s.stamp = stamp; s.cfgStamp = cfg; s.exportsList = b[i] == 1; i += 1
                guard let ec = u16() else { return }
                for _ in 0..<ec {
                    guard let spec = str(), i < b.count else { return }
                    let f = b[i]; i += 1
                    guard let r = str() else { return }
                    s.edges.append(NJSEdge(spec: spec, reexport: f & 1 != 0, binding: f & 2 != 0))
                    s.resolved.append(r.isEmpty ? nil : r)
                }
                // an edge that did not resolve may resolve today (a file was added): look those up again
                loaded[path] = s
                cost += s.cost
            }
        }
        lock.lock()
        if scans.isEmpty { scans = loaded; self.cost = cost; missesAtSave = misses }
        lock.unlock()
    }
}

extension NJSModules {
    /// Changes whenever a file that decides how specifiers resolve changes.
    func configStamp() -> Int64 {
        var h: Int64 = 17
        for n in ["tsconfig.json", "jsconfig.json", "package.json"] + NJSModules.aliasConfigNames { h = h &* 31 &+ LaravelFS.mtime(root + "/" + n) }
        return h
    }
}
