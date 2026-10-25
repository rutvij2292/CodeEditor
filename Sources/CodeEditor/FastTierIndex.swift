import Foundation

// Per-project data for the fast completion tier: Laravel names (routes, views, components, config, env, lang), the
// migration-derived schema and a light PSR-4 class table. Everything lives on one serial utility queue (the private
// LaravelProject instance is not thread-safe), sections are rebuilt lazily when their input mtimes change, and
// `FastTier.invalidate` (called from the FSEvents batch handler) forces a re-check.

struct FTColumn { var name: String; var type: String }
struct FTClassRef { var short: String; var fqn: String }
struct FTName { var name: String; var detail: String }

final class FTSection<T> {
    fileprivate var stamp: Int64 = .min
    fileprivate var checkedEpoch = -1
    fileprivate(set) var value: T
    init(_ initial: T) { value = initial }
    var built: Bool { stamp != .min }
}

final class FastProject {
    private static let registryLock = NSLock()
    private static var registry: [String: FastProject] = [:]
    static func shared(root: URL) -> FastProject {
        let key = root.standardizedFileURL.path
        registryLock.lock(); defer { registryLock.unlock() }
        if let p = registry[key] { return p }
        let p = FastProject(path: key)
        registry[key] = p
        return p
    }
    static func existing(root: URL) -> FastProject? {
        registryLock.lock(); defer { registryLock.unlock() }
        return registry[root.standardizedFileURL.path]
    }

    let path: String
    let lp: LaravelProject                 // private instance: only touch on `queue`
    let isLaravel: Bool
    let queue: DispatchQueue
    private let flagLock = NSLock()
    private var dirty = true
    private var lastCheck = Date.distantPast
    private var epoch = 0

    init(path: String) {
        self.path = path
        lp = LaravelProject(root: URL(fileURLWithPath: path))
        isLaravel = LaravelProject.isLaravelRoot(path)
        queue = DispatchQueue(label: "fasttier.\(path)", qos: .utility)
    }

    func markDirty() { flagLock.lock(); dirty = true; usageDirty = true; flagLock.unlock() }

    // Usage statistics (FastTierUsage.swift): built lazily on the queue, dropped on memory trim, refreshed only when stale AND a file changed.
    private var usageTable: FUsageTable?
    private var usageDirty = false

    /// Per request view of the usage table (queue only). Builds the table on first use.
    func usageView(file: URL, live: NSString) -> FUsage.View? {
        if FUsage.off { return nil }
        flagLock.lock(); let dirtyNow = usageDirty; flagLock.unlock()
        if usageTable == nil || (dirtyNow && Date().timeIntervalSince(usageTable!.builtAt) > FUsage.staleAfter) {
            let t0 = DispatchTime.now().uptimeNanoseconds
            usageTable = FUsage.build(root: path)
            usageBuildMs = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
            flagLock.lock(); usageDirty = false; flagLock.unlock()
        }
        guard let t = usageTable, !t.counts.isEmpty else { return nil }
        return FUsage.View(table: t, file: file, live: live)
    }
    private(set) var usageBuildMs = 0.0
    var usageBytes: Int { usageTable?.approxBytes ?? 0 }
    var usageBuilt: Bool { usageTable != nil }

    /// Start of every request (on `queue`): decide whether sections re-check their stamps.
    func beginRequest() {
        flagLock.lock()
        let now = Date()
        let revalidate = dirty || now.timeIntervalSince(lastCheck) > 1.5
        if revalidate { lastCheck = now; dirty = false; epoch += 1 }
        flagLock.unlock()
        drainPrefetched()
        if revalidate {
            classCache = classCache.filter { LaravelFS.mtime($0.key) == $0.value.stamp }.mapValues { var e = $0; e.epoch = epoch; return e }
            classBytes = classCache.values.reduce(0) { $0 + $1.bytes }
            pathCache.removeAll()
        }
    }

    @inline(__always) private func section<T>(_ s: FTSection<T>, stamp: () -> Int64, build: () -> T) -> T {
        if s.built && s.checkedEpoch == epoch { return s.value }
        s.checkedEpoch = epoch
        let st = stamp()
        if s.built && st == s.stamp { return s.value }
        s.value = build()
        s.stamp = st
        return s.value
    }

    // MARK: Filesystem helpers

    /// Entries of `dir` that do not start with a dot, with their directory flag (symlinks are resolved like `stat`). One `readdir` pass using
    /// the entry type: no per-entry `stat` and no URL enumerator (`FileManager.contentsOfDirectory` + `isDir` cost ~50 ms for an app + Modules tree).
    /// `fileSuffix`: nil returns directories only (no String is built for files), otherwise the files whose name ends with it ("" = all files).
    static func readEntries(_ dir: String, fileSuffix: [UInt8]? = []) -> [(name: String, isDir: Bool)] {
        guard let d = opendir(dir) else { return [] }
        defer { closedir(d) }
        var out: [(name: String, isDir: Bool)] = []
        while let e = readdir(d) {
            let len = Int(e.pointee.d_namlen)
            let type = e.pointee.d_type
            // quick checks on the raw name bytes: hidden entries, and for plain files the suffix
            let (hidden, suffixOK) = withUnsafePointer(to: &e.pointee.d_name) { $0.withMemoryRebound(to: UInt8.self, capacity: len + 1) { b -> (Bool, Bool) in
                if b[0] == 46 { return (true, false) }                   // ".", ".." and hidden entries
                guard let suf = fileSuffix else { return (false, false) }
                if suf.count > len { return (false, false) }
                for i in 0..<suf.count where b[len - suf.count + i] != suf[i] { return (false, false) }
                return (false, true)
            } }
            if hidden { continue }
            if type == UInt8(DT_REG), !suffixOK { continue }              // a file we do not want: no allocation
            let name = withUnsafePointer(to: &e.pointee.d_name) { $0.withMemoryRebound(to: CChar.self, capacity: len + 1) { String(cString: $0) } }
            var isDir = type == UInt8(DT_DIR)
            if type == UInt8(DT_LNK) || type == UInt8(DT_UNKNOWN) { isDir = LaravelFS.isDir(dir + "/" + name) }
            if !isDir, !suffixOK { continue }
            out.append((name, isDir))
        }
        return out
    }

    /// Order independent: depends on the mtime of every directory below `dir` (adding / removing / renaming an entry changes it), not on listing order.
    private static func dirStamp(_ dir: String, depth: Int = 0, files: Bool = false) -> Int64 {
        var acc = UInt64(bitPattern: LaravelFS.mtime(dir)) &* 0x9E37_79B9_7F4A_7C15
        guard depth < 8 else { return Int64(bitPattern: acc) }
        for e in readEntries(dir, fileSuffix: files ? [] : nil) {
            let p = dir + "/" + e.name
            if e.isDir { acc = acc &+ UInt64(bitPattern: dirStamp(p, depth: depth + 1, files: files)) &* 31 }
            else if files { acc = acc &+ UInt64(bitPattern: LaravelFS.mtime(p)) }
        }
        return Int64(bitPattern: acc)
    }

    static func files(in dir: String, ext: String, depth: Int = 0, rel: String = "") -> [String] {
        var out: [String] = []
        guard depth < 8 else { return out }
        for e in readEntries(dir, fileSuffix: Array(ext.utf8)).sorted(by: { $0.name < $1.name }) {
            if e.isDir { out += files(in: dir + "/" + e.name, ext: ext, depth: depth + 1, rel: rel + e.name + "/") }
            else if e.name.hasSuffix(ext) { out.append(rel + e.name) }
        }
        return out
    }

    /// `transform` over `items` on up to 4 threads, results in input order (sequential for tiny inputs / power saver).
    static func parallelMap<A, B>(_ items: [A], _ transform: (A) -> B) -> [B] {
        let workers = min(PowerState.shared.maxWorkers, 4, items.count)
        guard workers > 1 else { return items.map(transform) }
        var out = [B?](repeating: nil, count: items.count)
        let counter = NPCounter()
        withoutActuallyEscaping(transform) { tf in
            out.withUnsafeMutableBufferPointer { buf in
                let base = buf.baseAddress!
                DispatchQueue.concurrentPerform(iterations: workers) { _ in
                    while true {
                        let i = counter.next()
                        if i >= items.count { break }
                        base[i] = tf(items[i])
                    }
                }
            }
        }
        return out.map { $0! }
    }

    private func abs(_ rel: String) -> String { path + "/" + rel }

    // MARK: Routes

    private let routesSec = FTSection<[FTName]>([])
    func routeNames() -> [FTName] {
        guard isLaravel else { return [] }
        return section(routesSec, stamp: { self.lp.stamp(LaravelRouteIndex.routeFiles(self.lp)) }) {
            LaravelRouteIndex.routes(lp).values.map { FTName(name: $0.name, detail: ($0.file as NSString).lastPathComponent + ":\($0.line)") }
                .sorted { $0.name < $1.name }
        }
    }

    // MARK: Views / components / livewire / inertia

    private let viewsSec = FTSection<[String]>([])
    func viewNames() -> [String] {
        section(viewsSec, stamp: { LaravelModules.dirs(self.lp).reduce(Self.dirStamp(self.abs("resources/views"))) { $0 &+ Self.dirStamp($1.path + "/resources/views") &* 7 } }) {
            var out: [String] = []
            var seen = Set<String>()
            for f in Self.files(in: abs("resources/views"), ext: ".blade.php") {
                let n = String(f.dropLast(10)).replacingOccurrences(of: "/", with: ".")
                if seen.insert(n).inserted { out.append(n) }
            }
            // modules: `items::reports.pdf` (namespaced, as registered by loadViewsFrom) and the plain name some modules publish
            for m in LaravelModules.dirs(lp) {
                for sub in ["resources/views", "Resources/views"] where LaravelFS.isDir(m.path + "/" + sub) {
                    for f in Self.files(in: m.path + "/" + sub, ext: ".blade.php") {
                        let n = String(f.dropLast(10)).replacingOccurrences(of: "/", with: ".")
                        if seen.insert(m.lower + "::" + n).inserted { out.append(m.lower + "::" + n) }
                        if seen.insert(n).inserted { out.append(n) }
                    }
                }
            }
            return out
        }
    }

    private let compSec = FTSection<[FTName]>([])
    /// Blade tag names for `<x-…>` (anonymous + class based) and `livewire:…`.
    func componentNames() -> [FTName] {
        section(compSec, stamp: { Self.dirStamp(self.abs("resources/views/components")) &+ Self.dirStamp(self.abs("app/View/Components")) &+ Self.dirStamp(self.abs("app/Livewire")) &+ Self.dirStamp(self.abs("app/Http/Livewire")) }) {
            var out: [FTName] = []
            var seen = Set<String>()
            func add(_ n: String, _ d: String) { if seen.insert(n).inserted { out.append(FTName(name: n, detail: d)) } }
            for f in Self.files(in: abs("resources/views/components"), ext: ".blade.php") {
                var n = String(f.dropLast(10)).replacingOccurrences(of: "/", with: ".")
                if n.hasSuffix(".index") { n = String(n.dropLast(6)) }
                add("x-" + n, "component")
            }
            for f in Self.files(in: abs("app/View/Components"), ext: ".php") {
                let parts = String(f.dropLast(4)).split(separator: "/").map { FTParser.snake(String($0)).replacingOccurrences(of: "_", with: "-") }
                add("x-" + parts.joined(separator: "."), "class component")
            }
            for base in ["app/Livewire", "app/Http/Livewire"] {
                for f in Self.files(in: abs(base), ext: ".php") {
                    let parts = String(f.dropLast(4)).split(separator: "/").map { FTParser.snake(String($0)).replacingOccurrences(of: "_", with: "-") }
                    add("livewire:" + parts.joined(separator: "."), "livewire")
                }
            }
            return out
        }
    }

    private let inertiaSec = FTSection<[String]>([])
    func inertiaPages() -> [String] {
        let dirs = ["resources/js/Pages", "resources/js/pages", "resources/ts/Pages", "resources/ts/pages"]
        return section(inertiaSec, stamp: { dirs.reduce(Int64(0)) { $0 &+ Self.dirStamp(self.abs($1)) } }) {
            var out: [String] = []
            for d in dirs where LaravelFS.isDir(abs(d)) {
                for ext in [".vue", ".tsx", ".jsx", ".svelte"] {
                    for f in Self.files(in: abs(d), ext: ext) { out.append(String(f.dropLast(ext.count))) }
                }
                if !out.isEmpty { break }
            }
            return out
        }
    }

    // MARK: Config / env / lang

    private let configSec = FTSection<[String]>([])
    func configKeys() -> [String] {
        let dir = abs("config")
        // (config key prefix, file): config/*.php, plus Modules/<Name>/config/config.php merged under the lower-case module name
        func sources() -> [(base: String, path: String)] {
            var r: [(String, String)] = LaravelFS.list(dir).sorted().filter { $0.hasSuffix(".php") }.map { (String($0.dropLast(4)), dir + "/" + $0) }
            for m in LaravelModules.dirs(lp) {
                let cdir = m.path + "/config"
                for f in LaravelFS.list(cdir).sorted() where f.hasSuffix(".php") {
                    let n = String(f.dropLast(4))
                    r.append((n == "config" ? m.lower : m.lower + "." + n, cdir + "/" + f))
                }
            }
            return r
        }
        return section(configSec, stamp: { self.lp.stamp(sources().map(\.path)) &+ LaravelFS.mtime(dir) &+ Int64(sources().count) }) {
            var out: [String] = []
            var seenBase = Set<String>()
            for (base, path) in sources() where seenBase.insert(base).inserted {
                guard let t = Self.read(path) else { continue }
                out.append(base)
                let keys = PHPArrayKeys.parse(PHPLex(t))
                for k in keys.keys.sorted() {
                    if let last = k.split(separator: ".").last, last.allSatisfy(\.isNumber) { continue }
                    out.append(base + "." + k)
                }
            }
            return out
        }
    }

    static func read(_ path: String) -> NSString? {
        let t0 = NPStats.now()
        defer { NPStats.readNs &+= NPStats.now() &- t0; NPStats.reads += 1 }
        return readRaw(path)
    }

    /// Same as `read` without the (unsynchronised) diagnostics counters: safe on worker threads.
    static func readRaw(_ path: String) -> NSString? {
        guard let d = FileManager.default.contents(atPath: path), d.count < 2_000_000 else { return nil }
        // A real (CF backed) NSString: O(1) character access, unlike a bridged Swift String whose UTF-16 view needs breadcrumbs.
        return NSString(data: d, encoding: String.Encoding.utf8.rawValue) ?? NSString(data: d, encoding: String.Encoding.isoLatin1.rawValue)
    }

    private let envSec = FTSection<[FTName]>([])
    func envKeys() -> [FTName] {
        section(envSec, stamp: { LaravelFS.mtime(self.abs(".env")) &+ LaravelFS.mtime(self.abs(".env.example")) &* 31 }) {
            var out: [FTName] = []
            var seen = Set<String>()
            for name in [".env", ".env.example"] {
                guard let t = Self.read(abs(name)) else { continue }
                t.enumerateLines { line, _ in
                    var s = Substring(line).drop(while: { $0 == " " || $0 == "\t" })
                    if s.hasPrefix("export ") { s = s.dropFirst(7) }
                    guard !s.hasPrefix("#"), let eq = s.firstIndex(of: "=") else { return }
                    let k = s[..<eq].trimmingCharacters(in: .whitespaces)
                    if !k.isEmpty, seen.insert(k).inserted { out.append(FTName(name: k, detail: name)) }
                }
            }
            return out
        }
    }

    private let langSec = FTSection<[String]>([])
    func langKeys() -> [String] {
        let bases = ["lang", "resources/lang"].map(abs)
        return section(langSec, stamp: { bases.reduce(Int64(0)) { $0 &+ Self.dirStamp($1, files: true) } }) {
            var out: [String] = []
            for base in bases where LaravelFS.isDir(base) {
                var locale = "en"
                if let t = Self.read(abs("config/app.php")),
                   let re = NPRe.make(pattern: #"'locale'\s*=>\s*(?:env\(\s*'[^']*'\s*,\s*)?'([\w-]+)'"#),
                   let m = re.firstMatch(in: t as String, range: NSRange(location: 0, length: t.length)) { locale = t.substring(with: m.range(at: 1)) }
                if !LaravelFS.isDir(base + "/" + locale) { locale = "en" }
                if !LaravelFS.isDir(base + "/" + locale), let d = LaravelFS.list(base).first(where: { LaravelFS.isDir(base + "/" + $0) }) { locale = d }
                for f in LaravelFS.list(base + "/" + locale).sorted() where f.hasSuffix(".php") {
                    guard let t = Self.read(base + "/" + locale + "/" + f) else { continue }
                    let file = String(f.dropLast(4))
                    for k in PHPArrayKeys.parse(PHPLex(t)).keys.sorted() {
                        if let last = k.split(separator: ".").last, last.allSatisfy(\.isNumber) { continue }
                        out.append(file + "." + k)
                    }
                }
                for jf in [locale + ".json", "en.json"] {
                    if let d = FileManager.default.contents(atPath: base + "/" + jf), d.count < 2_000_000,
                       let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                        out += obj.keys.sorted()
                        break
                    }
                }
                break
            }
            return out
        }
    }

    // MARK: Schema (migrations)

    private let schemaSec = FTSection<[String: [FTColumn]]>([:])
    /// Migration directories: the app's `database/migrations` plus a module's `database/migrations` (nwidart-style
    /// `Modules/X/app/` PSR-4 roots keep migrations next to the `app` directory).
    func migrationDirs() -> [String] {
        var dirs = [abs("database/migrations")]
        var seen = Set(dirs)
        for entry in lp.psr4 {
            for d in entry.dirs where !d.contains("/vendor/") {
                let trimmed = d.hasSuffix("/") ? String(d.dropLast()) : d
                var cands = [(trimmed as NSString).deletingLastPathComponent + "/database/migrations", trimmed + "/database/migrations"]
                // `"Modules\\": "Modules/"`: every module directory next to its own database/migrations
                let kids = LaravelFS.list(trimmed)
                if kids.count <= 200 { cands += kids.map { trimmed + "/" + $0 + "/database/migrations" } }
                for cand in cands where seen.insert(cand).inserted && LaravelFS.isDir(cand) { dirs.append(cand) }
            }
        }
        return dirs
    }

    /// Every migration file of every migration directory, in migration order (timestamped file names sort chronologically across modules).
    func migrationFiles() -> [String] {
        var out: [String] = []
        for dir in migrationDirs() { for f in LaravelFS.list(dir) where f.hasSuffix(".php") { out.append(dir + "/" + f) } }
        return out.sorted { ($0 as NSString).lastPathComponent < ($1 as NSString).lastPathComponent }
    }

    func schema() -> [String: [FTColumn]] {
        guard isLaravel else { return [:] }
        return section(schemaSec, stamp: {
            let dirs = self.migrationDirs()
            var files: [String] = []
            for dir in dirs { files += LaravelFS.list(dir).sorted().map { dir + "/" + $0 } }
            return dirs.reduce(self.lp.stamp(files)) { $0 &+ LaravelFS.mtime($1) }
        }) {
            var tables: [String: [FTColumn]] = [:]
            // read + lex on several threads (a modular app has ~100 migrations); the column bookkeeping stays sequential (alters follow creates)
            let lexes = Self.parallelMap(self.migrationFiles()) { f in Self.read(f).map { PHPLex($0) } }
            for lex in lexes { if let lex { FTSchema.apply(lex: lex, to: &tables) } }
            return tables
        }
    }

    // MARK: Project classes (PSR-4)

    private let classesSec = FTSection<[FTClassRef]>([])
    func projectClasses() -> [FTClassRef] {
        let composer = abs("composer.json")
        return section(classesSec, stamp: {
            var h = Hasher()
            h.combine(LaravelFS.mtime(composer))
            let dirs = self.lp.psr4.flatMap { $0.dirs.filter { !$0.contains("/vendor/") } }
            // one task per PSR-4 root (an app plus a dozen modules): the stamps are summed, so the order does not matter
            for st in Self.parallelMap(dirs, { Self.dirStamp($0) }) { h.combine(st) }
            return Int64(h.finalize())
        }) {
            var out: [FTClassRef] = []
            var seen = Set<String>()
            let psr4 = lp.psr4
            var roots: [String] = []
            for (_, dirs) in psr4 { for d in dirs where !d.contains("/vendor/") && LaravelFS.isDir(d) { roots.append(d) } }
            let listed = Self.parallelMap(roots, { Self.files(in: $0, ext: ".php") })
            var k = 0
            for (prefix, dirs) in psr4 {
                for d in dirs where !d.contains("/vendor/") && LaravelFS.isDir(d) {
                    let fs = listed[k]; k += 1
                    for f in fs {
                        let rel = String(f.dropLast(4))
                        let short = (rel as NSString).lastPathComponent
                        guard let c = short.first, c.isUppercase else { continue }
                        let fqn = prefix + rel.replacingOccurrences(of: "/", with: "\\")
                        if seen.insert(fqn).inserted { out.append(FTClassRef(short: short, fqn: fqn)) }
                    }
                }
            }
            return out
        }
    }

    // MARK: Class info cache

    /// Parsed class declarations, least recently used evicted once the cache holds more than `maxClasses` entries or `maxClassBytes`
    /// (estimated retained bytes) -- vendor classes like Carbon / Eloquent Builder are large, so the byte cap is what matters.
    private struct ClassEntry { var stamp: Int64; var cls: FTClass?; var bytes: Int; var tick: Int; var epoch: Int }
    private var classCache: [String: ClassEntry] = [:]
    private var classBytes = 0
    private var classTick = 0
    static let maxClasses = 400
    static let maxClassBytes = 6_000_000
    var cachedClassCount: Int { classCache.count }
    var cachedClassBytes: Int { classBytes }
    private var pathCache: [String: String] = [:]      // fqn -> path ("" = unresolved)
    private var shortCache: [String: String?] = [:]

    func classPath(_ fqn: String) -> String? {
        let name = fqn.hasPrefix("\\") ? String(fqn.dropFirst()) : fqn
        if let p = pathCache[name] { return p.isEmpty ? nil : p }
        let t0 = NPStats.now()
        defer { NPStats.pathNs &+= NPStats.now() &- t0 }
        var found = lp.classFile(name)
        if found == nil { found = PHPStubs.classPath(name) }     // PHP built-ins (bundled stubs) win over vendor polyfills
        if found == nil, VendorIndex.enabled {
            found = VendorIndex.shared(for: URL(fileURLWithPath: path)).find(fqn: name).first(where: { LaravelFS.isFile($0.path) })?.path
        }
        pathCache[name] = found ?? ""
        return found
    }

    private static func timedParse(_ t: NSString) -> FTClass? {
        let t0 = NPStats.now()
        defer { NPStats.parseNs &+= NPStats.now() &- t0; NPStats.parses += 1 }
        return FTParser.parse(t)
    }

    func classInfo(path file: String) -> FTClass? {
        if PHPStubs.isStubFile(file) {      // immutable bundled files: own bounded cache, no per-project copy
            return PHPStubs.classInfo(path: file) { Self.read(file).flatMap { Self.timedParse($0) } }
        }
        classTick += 1
        // The file's mtime is re-checked once per validation epoch (`beginRequest`: at most every 1.5 s, or right after a file-change
        // notification), not on every call: a find usages / hierarchy walk used to `stat` the same few vendor files thousands of times.
        if var c = classCache[file] {
            if c.epoch == epoch { c.tick = classTick; classCache[file] = c; return c.cls }
            if c.stamp == LaravelFS.mtime(file) { c.tick = classTick; c.epoch = epoch; classCache[file] = c; return c.cls }
        }
        let st = LaravelFS.mtime(file)
        if let slot = takePrefetched(file) {          // read + parsed on a worker thread: wait for it instead of doing the work again
            slot.group.wait()
            if slot.ok, slot.stamp == st {
                store(file, slot.cls, stamp: st)
                return slot.cls
            }
        }
        guard let t = Self.read(file) else { return nil }
        let cls = Self.timedParse(t)
        store(file, cls, stamp: st)
        return cls
    }

    private func store(_ file: String, _ cls: FTClass?, stamp st: Int64) {
        if let old = classCache[file] { classBytes -= old.bytes }
        let bytes = cls?.approxBytes ?? 64
        classCache[file] = ClassEntry(stamp: st, cls: cls, bytes: bytes, tick: classTick, epoch: epoch)
        classBytes += bytes
        if classCache.count > Self.maxClasses || classBytes > Self.maxClassBytes { evictClasses(keeping: file) }
    }

    // MARK: Parallel prefetch of the classes a hierarchy walk is about to need

    /// A class file being read and parsed on a worker thread (see `prefetch`).
    final class PrefetchSlot {
        let group = DispatchGroup()
        var cls: FTClass?
        var ok = false
        var stamp: Int64 = 0
    }
    private let prefetchLock = NSLock()
    private var prefetched: [String: PrefetchSlot] = [:]
    static let maxPrefetchPending = 48

    private func takePrefetched(_ file: String) -> PrefetchSlot? {
        prefetchLock.lock(); defer { prefetchLock.unlock() }
        return prefetched.removeValue(forKey: file)
    }

    /// Starts reading + parsing the (library) classes `names` on background threads when they are not cached yet. The cold walk over a big
    /// vendor hierarchy (Carbon: 31 files, an Eloquent model: 35) then overlaps the file reads and parses of the classes it will visit next;
    /// `classInfo(path:)` picks the result up (or waits for it). Nothing here is polled and nothing stays resident beyond the normal class
    /// cache: results nobody asked for are moved into it (LRU, byte capped) by the next `beginRequest`. Must run on `queue`.
    func prefetch(_ names: [String]) {
        guard names.count > 0, PowerState.shared.maxWorkers >= 2 else { return }
        var jobs: [(String, PrefetchSlot)] = []
        for n in names {
            guard let p = classPath(n), classCache[p] == nil, !PHPStubs.isStubFile(p) else { continue }
            prefetchLock.lock()
            if prefetched[p] == nil, prefetched.count < Self.maxPrefetchPending {
                let s = PrefetchSlot()
                s.group.enter()
                prefetched[p] = s
                jobs.append((p, s))
            }
            prefetchLock.unlock()
        }
        for (p, slot) in jobs {
            DispatchQueue.global(qos: .userInitiated).async {
                let st = LaravelFS.mtime(p)
                if let t = Self.readRaw(p) { slot.cls = FTParser.parse(t); slot.ok = true }
                slot.stamp = st
                slot.group.leave()
            }
        }
    }

    /// Moves finished, unclaimed prefetch results into the class cache (queue only).
    private func drainPrefetched() {
        prefetchLock.lock()
        let all = prefetched
        prefetchLock.unlock()
        for (file, slot) in all where slot.group.wait(timeout: .now()) == .success {
            prefetchLock.lock(); let removed = prefetched.removeValue(forKey: file); prefetchLock.unlock()
            guard removed === slot, slot.ok, classCache[file] == nil else { continue }
            classTick += 1
            store(file, slot.cls, stamp: slot.stamp)
        }
    }

    /// Drops the least recently used quarter (at least) until both caps hold again; the entry just stored stays.
    private func evictClasses(keeping keep: String) {
        let order = classCache.sorted { $0.value.tick < $1.value.tick }.map(\.key)
        var i = 0
        while i < order.count, classCache.count > Self.maxClasses * 3 / 4 || classBytes > Self.maxClassBytes * 3 / 4 {
            if order[i] != keep, let e = classCache.removeValue(forKey: order[i]) { classBytes -= e.bytes }
            i += 1
        }
    }

    /// Frees parsed classes and the name caches (memory trim). Runs on the project's queue.
    func dropCaches() {
        classCache.removeAll(); classBytes = 0
        prefetchLock.lock(); prefetched.removeAll(); prefetchLock.unlock()
        pathCache.removeAll(); shortCache.removeAll()
        usageTable = nil
    }

    static func trimAll() {
        registryLock.lock(); let all = Array(registry.values); registryLock.unlock()
        for p in all { p.queue.async { p.dropCaches() } }
    }

    func classInfo(_ fqn: String) -> FTClass? {
        guard let p = classPath(fqn) else { return nil }
        return classInfo(path: p)
    }

    static let facadeAliases: [String: String] = {
        var d: [String: String] = [:]
        for n in ["App", "Artisan", "Auth", "Blade", "Broadcast", "Bus", "Cache", "Config", "Context", "Cookie", "Crypt", "Date", "DB", "Event", "File",
                  "Gate", "Hash", "Http", "Lang", "Log", "Mail", "Notification", "Password", "Process", "Queue", "RateLimiter", "Redirect", "Redis",
                  "Request", "Response", "Route", "Schedule", "Schema", "Session", "Storage", "URL", "Validator", "View", "Vite", "Concurrency", "Pipeline"] {
            d[n] = "Illuminate\\Support\\Facades\\" + n
        }
        d["Str"] = "Illuminate\\Support\\Str"; d["Arr"] = "Illuminate\\Support\\Arr"; d["Collection"] = "Illuminate\\Support\\Collection"
        d["Carbon"] = "Illuminate\\Support\\Carbon"; d["Number"] = "Illuminate\\Support\\Number"; d["Eloquent"] = "Illuminate\\Database\\Eloquent\\Model"
        return d
    }()

    /// Resolves `written` (as typed in `cur`'s file) to an existing class FQN, with fallbacks for unimported names.
    func resolveClass(_ written: String, in cur: FTClass?) -> String? {
        var cands: [String] = []
        if let cur { cands.append(cur.resolve(written)) } else { cands.append(written.hasPrefix("\\") ? String(written.dropFirst()) : written) }
        if !written.contains("\\") {
            if let a = Self.facadeAliases[written] { cands.append(a) }
            cands.append("App\\Models\\" + written)
        }
        for c in cands where classPath(c) != nil { return c }
        if let a = Self.facadeAliases[written], written == "DB" || written == "Auth" { return a }   // facades resolve by name even without vendor/
        guard !written.contains("\\") else { return nil }
        if let hit = shortCache[written] { return hit }
        var result: String?
        let matches = projectClasses().filter { $0.short == written }
        if matches.count == 1 { result = matches[0].fqn }
        shortCache[written] = result
        return result
    }

    // MARK: Eloquent helpers

    static func pluralize(_ w: String) -> String {
        let irregular = ["person": "people", "child": "children", "man": "men", "woman": "women", "mouse": "mice", "goose": "geese", "foot": "feet", "tooth": "teeth"]
        if let r = irregular[w] { return r }
        for (k, v) in irregular where w.hasSuffix("_" + k) { return String(w.dropLast(k.count)) + v }
        if let last = w.last {
            if last == "y", w.count > 1, !"aeiou".contains(w[w.index(w.endIndex, offsetBy: -2)]) { return String(w.dropLast()) + "ies" }
            if w.hasSuffix("s") || w.hasSuffix("x") || w.hasSuffix("z") || w.hasSuffix("ch") || w.hasSuffix("sh") { return w + "es" }
        }
        return w + "s"
    }

    func tableName(of c: FTClass) -> String {
        if let t = c.table { return t }
        var cur: FTClass? = c
        var hops = 0
        while let k = cur, hops < 6 {      // `$table` inherited from an app base model
            if let t = k.table { return t }
            cur = k.extends.flatMap { classInfo($0) }; hops += 1
        }
        return Self.pluralize(FTParser.snake(c.name))
    }

    func isModel(_ c: FTClass) -> Bool {
        var cur: FTClass? = c
        var hops = 0
        while let k = cur, hops < 12 {
            guard let e = k.extends else { return false }
            if e == "Illuminate\\Database\\Eloquent\\Model" || e.hasSuffix("\\Authenticatable") || e.hasSuffix("\\Pivot") { return true }
            if let n = e.split(separator: "\\").last, n == "Model" { return true }
            cur = classInfo(e); hops += 1
        }
        return false
    }

    /// Model attribute names: migration columns plus fillable/casts/hidden/appends/accessors, across the model's parents.
    func columns(of c: FTClass) -> [FTColumn] {
        var out = schema()[tableName(of: c)] ?? []
        var seen = Set(out.map(\.name))
        var cur: FTClass? = c
        var hops = 0
        while let k = cur, hops < 6 {
            for n in k.fillable + k.casts + k.hidden + k.appends + k.accessors where seen.insert(n).inserted { out.append(FTColumn(name: n, type: "attribute")) }
            cur = k.extends.flatMap { classInfo($0) }; hops += 1
        }
        return out
    }
}

// MARK: - Migration parsing

enum FTSchema {
    static let columnTypes: Set<String> = [
        "string", "text", "longText", "mediumText", "tinyText", "char", "integer", "bigInteger", "tinyInteger", "smallInteger", "mediumInteger",
        "unsignedInteger", "unsignedBigInteger", "unsignedTinyInteger", "unsignedSmallInteger", "unsignedMediumInteger", "boolean", "date",
        "dateTime", "dateTimeTz", "time", "timeTz", "timestamp", "timestampTz", "year", "decimal", "unsignedDecimal", "float", "double", "json",
        "jsonb", "uuid", "ulid", "binary", "enum", "set", "ipAddress", "macAddress", "foreignId", "foreignUuid", "foreignUlid", "increments",
        "bigIncrements", "tinyIncrements", "smallIncrements", "mediumIncrements", "geometry", "geography", "point", "lineString", "polygon",
        "multiPoint", "multiLineString", "multiPolygon", "geometryCollection", "vector", "rawColumn",
    ]

    private static func strings(_ lex: PHPLex, _ open: Int) -> [String] {
        guard lex.isPunct(open, "("), lex.match[open] > open else { return [] }
        var out: [String] = []
        for i in (open + 1)..<lex.match[open] where lex.toks[i].kind == .string { out.append(lex.strValue(i)) }
        return out
    }

    /// Applies the `up()` bodies of one migration file to `tables` (in migration order).
    static func apply(_ text: NSString, to tables: inout [String: [FTColumn]]) { apply(lex: PHPLex(text), to: &tables) }

    static func apply(lex: PHPLex, to tables: inout [String: [FTColumn]]) {
        let n = lex.count
        // up() body ranges
        var ranges: [(Int, Int)] = []
        for i in 0..<max(0, n - 3) where lex.isIdent(i, "function") && lex.isIdent(i + 1, "up") && lex.isPunct(i + 2, "(") {
            var k = lex.match[i + 2] + 1
            while k < n, !lex.isPunct(k, "{"), !lex.isPunct(k, ";") { k += 1 }
            if k < n, lex.isPunct(k, "{"), lex.match[k] > k { ranges.append((k + 1, lex.match[k])) }
        }
        if ranges.isEmpty { ranges = [(0, n)] }
        for (lo, hi) in ranges {
            var i = lo
            while i < hi {
                guard lex.toks[i].kind == .ident, i > 0, lex.isPunct(i - 1, code: PHPTok.dcolon) || lex.isPunct(i - 1, code: PHPTok.arrow), lex.isPunct(i + 1, "(") else { i += 1; continue }
                let m = lex.text(i)
                // must hang off `Schema`
                var fromSchema = false
                for b in max(0, i - 10)..<i where lex.isIdent(b, "Schema") { fromSchema = true; break }
                guard fromSchema else { i += 1; continue }
                let open = i + 1
                let close = lex.match[open]
                guard close > open else { i += 1; continue }
                switch m {
                case "create", "table":
                    guard let first = (open + 1 < close && lex.toks[open + 1].kind == .string) ? lex.strValue(open + 1) : nil else { break }
                    if m == "create" { tables[first] = [] }
                    var k = open + 2
                    var bodyOpen = -1
                    while k < close { if lex.isPunct(k, "{") { bodyOpen = k; break }; k += 1 }
                    var param = "$table"
                    for q in (open + 2)..<close where lex.toks[q].kind == .variable { param = lex.text(q); break }
                    if bodyOpen >= 0, lex.match[bodyOpen] > bodyOpen {
                        columns(lex, bodyOpen + 1, lex.match[bodyOpen], param, &tables, first)
                    } else if lex.isIdent(open + 2, "fn") || lex.isIdent(open + 4, "fn") {
                        columns(lex, open + 2, close, param, &tables, first)
                    }
                case "drop", "dropIfExists":
                    if let t = strings(lex, open).first { tables[t] = nil }
                case "rename":
                    let s = strings(lex, open)
                    if s.count == 2, let v = tables[s[0]] { tables[s[1]] = v; tables[s[0]] = nil }
                default: break
                }
                i = close + 1
            }
        }
    }

    private static func columns(_ lex: PHPLex, _ lo: Int, _ hi: Int, _ param: String, _ tables: inout [String: [FTColumn]], _ table: String) {
        var cols = tables[table] ?? []
        func add(_ name: String, _ type: String) {
            if let idx = cols.firstIndex(where: { $0.name == name }) { cols[idx].type = type } else { cols.append(FTColumn(name: name, type: type)) }
        }
        var i = lo
        while i + 3 < hi {
            if lex.toks[i].kind == .variable, lex.text(i) == param, lex.isPunct(i + 1, code: PHPTok.arrow), lex.toks[i + 2].kind == .ident, lex.isPunct(i + 3, "(") {
                let m = lex.text(i + 2)
                let open = i + 3
                let args = strings(lex, open)
                let first = (open + 1 < hi && lex.toks[open + 1].kind == .string) ? args.first : nil
                switch m {
                case "id": add(first ?? "id", "id")
                case "timestamps", "timestampsTz", "nullableTimestamps": add("created_at", "timestamp"); add("updated_at", "timestamp")
                case "softDeletes", "softDeletesTz": add(first ?? "deleted_at", "timestamp")
                case "rememberToken": add("remember_token", "string")
                case "morphs", "nullableMorphs", "uuidMorphs", "nullableUuidMorphs", "ulidMorphs", "nullableUlidMorphs":
                    if let f = first { add(f + "_type", "string"); add(f + "_id", "morph") }
                case "dropColumn", "dropColumns":
                    for a in args { cols.removeAll { $0.name == a } }
                case "renameColumn":
                    if args.count == 2, let idx = cols.firstIndex(where: { $0.name == args[0] }) { cols[idx].name = args[1] }
                case "dropTimestamps", "dropTimestampsTz": cols.removeAll { $0.name == "created_at" || $0.name == "updated_at" }
                case "dropSoftDeletes", "dropSoftDeletesTz": cols.removeAll { $0.name == "deleted_at" }
                case "dropRememberToken": cols.removeAll { $0.name == "remember_token" }
                default:
                    if columnTypes.contains(m), let f = first { add(f, m) }
                }
                i = lex.match[open] > open ? lex.match[open] + 1 : i + 4
                continue
            }
            i += 1
        }
        tables[table] = cols
    }
}


/// nwidart/laravel-modules style layout: `Modules/<Name>/{routes,config,resources/views,app,...}` (also lower-case `modules/`).
enum LaravelModules {
    struct Dir { var name: String; var lower: String; var path: String }

    static func dirs(_ p: LaravelProject) -> [Dir] {
        var out: [Dir] = []
        for base in ["Modules", "modules"] {
            let b = p.abs(base)
            guard LaravelFS.isDir(b) else { continue }
            for n in LaravelFS.list(b).sorted() where !n.hasPrefix(".") && LaravelFS.isDir(b + "/" + n) {
                out.append(Dir(name: n, lower: n.lowercased(), path: b + "/" + n))
                if out.count >= 200 { return out }
            }
        }
        return out
    }
}
