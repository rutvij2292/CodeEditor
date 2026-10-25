import AppKit

/// Native CSS / HTML / Tailwind language service (replaces vscode-html / vscode-css / the Tailwind server feature by feature,
/// see docs/native-web.md). Same shape as the native PHP engine: everything is on demand, runs on a per-project serial utility
/// queue, keeps small byte-capped caches (parsed CSS indexes, the resolved Tailwind theme) and never polls or starts a process.
/// External servers stay the fallback unless "native only" is switched on.
enum NativeWeb {
    static let enabledKey = "web.native.enabled"
    static let nativeOnlyKey = "web.nativeOnly"

    /// Master switch (default on). Off = every call here answers "no opinion" and the external servers behave as before.
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// 'Use native HTML / CSS / Tailwind only (stop the external servers)'. Default OFF: the servers stay the fallback.
    static var nativeOnly: Bool {
        get { UserDefaults.standard.object(forKey: nativeOnlyKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: nativeOnlyKey) }
    }

    static let managedServerIds: Set<String> = ["html", "css", "tailwind"]

    static func setNativeOnly(_ on: Bool) {
        nativeOnly = on
        for id in managedServerIds { LanguageServerManager.shared.serverPreferenceChanged(id) }
    }

    enum Kind { case css, html, script }

    static func kind(of url: URL) -> Kind? {
        let name = url.lastPathComponent.lowercased()
        switch url.pathExtension.lowercased() {
        case "css", "scss", "less", "pcss", "postcss": return .css
        case "html", "htm", "vue", "phtml", "svelte", "astro", "twig": return .html
        case "php": return name.hasSuffix(".blade.php") ? .html : nil
        case "jsx", "tsx", "js", "ts", "mjs": return .script
        default: return nil
        }
    }

    static func handles(_ url: URL) -> Bool { enabled && kind(of: url) != nil }

    /// True for the files hover / definition should ask us about (scripts only answer inside Tailwind class strings).
    static func handlesLookup(_ url: URL) -> Bool { handles(url) }

    static func root(for url: URL) -> String {
        let file = url.standardizedFileURL
        if let r = LanguageServers.openProjectRoot?(file) { return r.standardizedFileURL.path }
        var dir = file.deletingLastPathComponent().path
        var package = ""
        for _ in 0..<14 {
            if LaravelFS.exists(dir + "/.git") || LaravelFS.isFile(dir + "/artisan") { return dir }
            if package.isEmpty, LaravelFS.isFile(dir + "/package.json") { package = dir }
            let parent = (dir as NSString).deletingLastPathComponent
            if parent == dir || parent.isEmpty { break }
            dir = parent
        }
        return package.isEmpty ? file.deletingLastPathComponent().path : package
    }

    // MARK: Lookups (hover / definition), mirroring NativePHP.lookup / lookupAsync

    static func lookup(url: URL, text: NSString, offset: Int, root: String? = nil, usages: Bool = true) -> NPHit? {
        guard handles(url) else { return nil }
        let p = NWProject.shared(root: root ?? self.root(for: url))
        return p.queue.sync { NWService.lookup(p, url: url, text: text, offset: offset, usages: usages) }
    }

    static func lookupAsync(url: URL, text: NSString, offset: Int, completion: @escaping (NPHit?) -> Void) {
        guard handles(url) else { completion(nil); return }
        let p = NWProject.shared(root: root(for: url))
        let snapshot = NSString(string: text as String)
        p.queue.async {
            let hit = NWService.lookup(p, url: url, text: snapshot, offset: offset, usages: false)
            DispatchQueue.main.async { completion(hit) }
        }
    }

    /// Cmd-B / Cmd-click. True when native handled the jump.
    static func goToDefinition(in tab: EditorTab, at offset: Int) -> Bool {
        guard handles(tab.url) else { return false }
        let text = tab.textView.string as NSString
        guard let hit = lookup(url: tab.url, text: text, offset: offset), !hit.targets.isEmpty else { return false }
        return NativePHP.open(hit, from: tab, offset: offset)
    }

    /// Synchronous completion for tests and tools.
    static func items(for ctx: CompletionContext) -> [CompletionItem] {
        guard handles(ctx.fileURL) else { return [] }
        let p = NWProject.shared(root: root(for: ctx.fileURL))
        return p.queue.sync { NWService.complete(p, ctx) }
    }

    /// FSEvents batch hook: the next request re-validates the file lists and stamps.
    static func invalidate(root: URL) { NWProject.existing(root: root.standardizedFileURL.path)?.markDirty() }

    static func trimMemory() {
        NWProject.trimAll()
        NWHtml.dropCaches()
        malloc_zone_pressure_relief(nil, 0)
    }

    private static var hooksInstalled = false
    private static var pressureSource: DispatchSourceMemoryPressure?

    /// Event driven trimming (memory pressure, app hidden, power saver); never from a timer.
    static func installMemoryHooks() {
        guard !hooksInstalled else { return }
        hooksInstalled = true
        let src = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global(qos: .utility))
        src.setEventHandler { trimMemory() }
        src.resume()
        pressureSource = src
        let nc = NotificationCenter.default
        nc.addObserver(forName: PowerState.didChange, object: nil, queue: .main) { _ in
            if PowerState.shared.saver { DispatchQueue.global(qos: .utility).async { trimMemory() } }
        }
        nc.addObserver(forName: NSApplication.didHideNotification, object: nil, queue: .main) { _ in
            DispatchQueue.global(qos: .utility).async { trimMemory() }
        }
    }

    // Roots whose Tailwind setup native resolved (read by the old built-in Tailwind provider to stay silent there).
    private static let activeLock = NSLock()
    private static var activeRoots = Set<String>()
    static func noteTailwind(root: String, active: Bool) {
        activeLock.lock(); defer { activeLock.unlock() }
        if active { activeRoots.insert(root) } else { activeRoots.remove(root) }
    }
    static func tailwindActive(for url: URL) -> Bool {
        guard enabled else { return false }
        let r = root(for: url)
        activeLock.lock(); defer { activeLock.unlock() }
        return activeRoots.contains(r)
    }

    static func register() {
        CompletionRegistry.register(NativeWebProvider(), forExtensions: ["css", "scss", "less", "pcss", "postcss", "html", "htm", "vue", "phtml",
                                                                          "svelte", "astro", "twig", "php", "jsx", "tsx", "js", "ts", "mjs"])
    }
}

/// UTF-16 snapshot of a document: O(1) character access without NSString bridging costs.
struct NWBuf {
    let ns: NSString
    let u: [unichar]
    init(_ ns: NSString) {
        self.ns = ns
        var b = [unichar](repeating: 0, count: ns.length)
        if ns.length > 0 { ns.getCharacters(&b, range: NSRange(location: 0, length: ns.length)) }
        u = b
    }
    var count: Int { u.count }
    subscript(i: Int) -> unichar { u[i] }
    func str(_ a: Int, _ b: Int) -> String {
        let lo = max(0, min(a, u.count)), hi = max(lo, min(b, u.count))
        return u[lo..<hi].withUnsafeBufferPointer { String(utf16CodeUnits: $0.baseAddress ?? UnsafePointer(bitPattern: 1)!, count: hi - lo) }
    }
}

enum NWChar {
    @inline(__always) static func isNameStart(_ c: unichar) -> Bool { (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || c == 95 || c > 127 }
    @inline(__always) static func isDigit(_ c: unichar) -> Bool { c >= 48 && c <= 57 }
    /// CSS identifier character (letters, digits, `-`, `_`).
    @inline(__always) static func isIdent(_ c: unichar) -> Bool { isNameStart(c) || isDigit(c) || c == 45 }
    @inline(__always) static func isSpace(_ c: unichar) -> Bool { c == 32 || c == 10 || c == 9 || c == 13 || c == 12 }

    static func identStart(_ b: NWBuf, _ from: Int, floor: Int = 0) -> Int {
        var s = min(from, b.count)
        while s > floor, isIdent(b[s - 1]) { s -= 1 }
        return s
    }
    static func identEnd(_ b: NWBuf, _ from: Int) -> Int {
        var e = from
        while e < b.count, isIdent(b[e]) { e += 1 }
        return e
    }
}

// MARK: - Per-project state

/// One per project root. All mutable state is touched only on `queue` (serial, utility QoS) except the dirty flag.
final class NWProject {
    private static let registryLock = NSLock()
    private static var registry: [String: NWProject] = [:]

    static func shared(root: String) -> NWProject {
        registryLock.lock(); defer { registryLock.unlock() }
        if let p = registry[root] { return p }
        let p = NWProject(root: root)
        registry[root] = p
        return p
    }
    static func existing(root: String) -> NWProject? {
        registryLock.lock(); defer { registryLock.unlock() }
        return registry[root]
    }
    static func trimAll() {
        registryLock.lock(); let all = Array(registry.values); registryLock.unlock()
        for p in all { p.queue.async { p.dropCaches() } }
    }

    let root: String
    let queue: DispatchQueue
    private let flagLock = NSLock()
    private var dirty = true

    init(root: String) {
        self.root = root
        queue = DispatchQueue(label: "nativeweb.\(root)", qos: .utility)
    }

    func markDirty() { flagLock.lock(); dirty = true; flagLock.unlock() }
    private func takeDirty() -> Bool { flagLock.lock(); defer { flagLock.unlock() }; let d = dirty; dirty = false; return d }

    // MARK: file lists (lazy; rebuilt when dirty or older than `listTTL`)

    static let skipDirs: Set<String> = ["node_modules", "vendor", ".git", "storage", ".idea", ".vscode", "dist", "build", "coverage", "target", "__pycache__",
                                        ".venv", ".next", ".nuxt", ".svelte-kit", ".cache", "bower_components", "tmp", "temp", "logs", ".turbo", ".output"]
    static let cssExts: Set<String> = ["css", "scss", "less", "pcss", "postcss"]
    static let markupExts: Set<String> = ["html", "htm", "vue", "phtml", "svelte", "astro", "twig", "jsx", "tsx", "js", "ts", "mjs"]
    static let maxListed = 6000
    private static let listTTL: TimeInterval = 600     // safety net only: FSEvents batches call markDirty()

    private(set) var cssFiles: [String] = []        // absolute paths
    private(set) var markupFiles: [String] = []     // absolute paths (blade.php included)
    private var listStamp = Date.distantPast
    private var listed = false
    var walkNs: UInt64 = 0

    private func ensureLists() {
        if listed, !takeDirty(), Date().timeIntervalSince(listStamp) < Self.listTTL { return }
        _ = takeDirty()
        let t0 = NPStats.now()
        var css: [String] = [], markup: [String] = []
        var stack: [(String, Int)] = [(root, 0)]
        var visited = 0
        while let (dir, depth) = stack.popLast(), visited < 60_000 {
            for e in FastProject.readEntries(dir, fileSuffix: []) {
                visited += 1
                if e.isDir {
                    if depth < 10, !Self.skipDirs.contains(e.name), !(dir == root + "/public" && e.name == "build") { stack.append((dir + "/" + e.name, depth + 1)) }
                    continue
                }
                let lower = e.name.lowercased()
                guard let dot = lower.lastIndex(of: ".") else { continue }
                let ext = String(lower[lower.index(after: dot)...])
                if Self.cssExts.contains(ext) {
                    if lower.hasSuffix(".min.css") { continue }
                    if css.count < Self.maxListed { css.append(dir + "/" + e.name) }
                } else if Self.markupExts.contains(ext) || lower.hasSuffix(".blade.php") {
                    if lower.hasSuffix(".min.js") || lower.hasSuffix(".d.ts") { continue }
                    if markup.count < Self.maxListed { markup.append(dir + "/" + e.name) }
                }
            }
        }
        css.sort(); markup.sort()
        cssFiles = css; markupFiles = markup
        listStamp = Date(); listed = true; listEpoch += 1
        walkNs = NPStats.now() &- t0
    }

    /// True once the project tree has been walked (tests: ordinary JS / tag completions must not trigger it).
    var isListed: Bool { listed }
    var allCSSFiles: [String] { ensureLists(); return cssFiles }
    var allMarkupFiles: [String] { ensureLists(); return markupFiles }

    // MARK: CSS index cache (file count and size capped; a request that touches more files than fit never evicts its own entries)

    private var cssCache: [String: (stamp: Int64, index: NWCssIndex, used: Int)] = [:]
    static let maxCSSIndexes = 160
    static let maxIndexedFileBytes = 1_500_000
    static let maxIndexBytes = 8_000_000
    private var cssBytes = 0
    private var requestSeq = 0

    /// Called at the start of every service request (on `queue`).
    func beginRequest() { requestSeq += 1 }

    func cssIndex(path: String) -> NWCssIndex? {
        let st = LaravelFS.mtime(path)
        if var c = cssCache[path], c.stamp == st {
            c.used = requestSeq
            cssCache[path] = c
            return c.index
        }
        guard st != 0, let text = FastProject.readRaw(path), text.length <= Self.maxIndexedFileBytes else { return nil }
        let idx = NWCss.index(NWBuf(text), lang: NWCss.lang(path: path))
        if let old = cssCache.removeValue(forKey: path) { cssBytes -= old.index.approxBytes }
        // make room by evicting entries not used during this request; when none is old enough the new index is simply not cached
        while cssCache.count >= Self.maxCSSIndexes || cssBytes + idx.approxBytes > Self.maxIndexBytes {
            guard let victim = cssCache.min(by: { $0.value.used < $1.value.used }), victim.value.used < requestSeq else { return idx }
            cssBytes -= victim.value.index.approxBytes
            cssCache.removeValue(forKey: victim.key)
        }
        cssCache[path] = (st, idx, requestSeq)
        cssBytes += idx.approxBytes
        return idx
    }

    var cachedIndexCount: Int { cssCache.count }

    /// Every CSS file's index (cold: parses each file once, capped by the cache; later requests only stat).
    func allCSSIndexes() -> [(path: String, index: NWCssIndex)] {
        var out: [(String, NWCssIndex)] = []
        for p in allCSSFiles { if let i = cssIndex(path: p) { out.append((p, i)) } }
        return out
    }

    // MARK: Tailwind (resolved lazily, invalidated by the stamps of its input files)

    var tailwindStates: [String: NWTailwindState] = [:]
    var tailwindBuildNs: UInt64 = 0
    /// Bumped whenever the file lists are rebuilt (Tailwind inputs are re-discovered then).
    private(set) var listEpoch = 0

    /// The Tailwind setup that applies to files under `near` (nil: the project does not use Tailwind).
    func tailwind(near: String? = nil) -> NWTailwind? {
        ensureLists()
        let tw = NWTailwindLoader.resolve(self, near: near)
        NativeWeb.noteTailwind(root: root, active: tw != nil)
        return tw
    }

    func dropCaches() {
        cssCache.removeAll(); cssBytes = 0
        cssFiles = []; markupFiles = []; listed = false
        tailwindStates.removeAll()
    }
}
