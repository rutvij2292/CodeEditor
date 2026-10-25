import AppKit

/// Native JavaScript / TypeScript language service (go to definition, hover, find usages, a few provably correct diagnostics and
/// completions). Mirrors the native PHP engine: one serial utility queue per project, everything on demand from the live buffer
/// (last parse memoised) plus byte-capped caches of compact per-file summaries, no timers and no background indexing. When native
/// has no certain answer it returns nil and the external TypeScript server answers as before.
enum NativeJS {
    static let enabledKey = "js.native"

    /// Settings > Languages: 'Native JavaScript / TypeScript engine' (default ON; OFF leaves everything to the TypeScript server).
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static let extensions: Set<String> = ["js", "jsx", "mjs", "cjs", "ts", "tsx", "mts", "cts", "vue"]

    static func handles(_ url: URL) -> Bool { enabled && extensions.contains(url.pathExtension.lowercased()) }

    // MARK: project root

    private static let rootLock = NSLock()
    private static var rootCache: [String: String] = [:]

    /// Nearest ancestor with tsconfig.json / jsconfig.json / package.json (else .git, else the file's directory).
    static func root(for file: URL) -> String {
        let start = file.deletingLastPathComponent().standardizedFileURL.path
        rootLock.lock(); if let r = rootCache[start] { rootLock.unlock(); return r }; rootLock.unlock()
        var dir = start, found = ""
        for _ in 0..<40 {
            for m in ["tsconfig.json", "jsconfig.json", "package.json", ".git"] where LaravelFS.exists(dir + "/" + m) { found = dir; break }
            if !found.isEmpty || dir == "/" { break }
            dir = (dir as NSString).deletingLastPathComponent
        }
        if found.isEmpty { found = start }
        rootLock.lock(); if rootCache.count > 200 { rootCache.removeAll() }; rootCache[start] = found; rootLock.unlock()
        return found
    }

    // MARK: live document memo

    private static let parseLock = NSLock()
    private static var last: NJSDoc?

    static func dropLastParse() { parseLock.lock(); last = nil; parseLock.unlock() }

    static func document(path: String, text: NSString) -> NJSDoc? {
        parseLock.lock()
        if let d = last, d.path == path, d.text.length == text.length, d.text === text || d.text.isEqual(text) { parseLock.unlock(); return d }
        parseLock.unlock()
        guard let d = NJSDoc(path: path, text: text) else { return nil }
        parseLock.lock(); last = d; parseLock.unlock()
        return d
    }

    static func env(url: URL, text: NSString, root: String? = nil) -> NJSEnv? {
        guard handles(url) else { return nil }
        let proj = NJSProject.shared(root: root ?? self.root(for: url))
        proj.modules.beginRequest()
        guard let d = document(path: (url.standardizedFileURL.path as NSString).standardizingPath, text: text) else { return nil }
        return NJSEnv(proj: proj, doc: d)
    }

    // MARK: lookup

    /// Synchronous lookup (tests, Cmd-B). Main thread callers wait on the project's queue.
    static func lookup(url: URL, text: NSString, offset: Int, root: String? = nil) -> NPHit? {
        guard handles(url) else { return nil }
        let proj = NJSProject.shared(root: root ?? self.root(for: url))
        return proj.queue.sync { env(url: url, text: text, root: proj.root)?.lookup(at: offset) }
    }

    static func lookupAsync(url: URL, text: NSString, offset: Int, completion: @escaping (NPHit?) -> Void) {
        guard handles(url) else { completion(nil); return }
        let proj = NJSProject.shared(root: root(for: url))
        let snapshot = NSString(string: text as String)
        proj.queue.async {
            let hit = env(url: url, text: snapshot, root: proj.root)?.lookup(at: offset)
            DispatchQueue.main.async { completion(hit) }
        }
    }

    static func goToDefinition(in tab: EditorTab, at offset: Int) -> Bool {
        guard handles(tab.url) else { return false }
        let text = tab.textView.string as NSString
        guard let hit = lookup(url: tab.url, text: text, offset: offset), !hit.targets.isEmpty else { return false }
        return NativePHP.open(hit, from: tab, offset: offset)
    }

    // MARK: memory

    /// Drops every cached summary / parse / config of the native JS engine. Safe at any time; called on memory pressure, when the
    /// app is hidden and in power-saver mode, never from a timer.
    static func trimMemory() {
        dropLastParse()
        NJSProject.trimAll()
        NJSParsers.drop()
        NPFiles.clear()
        NPText.dropTables()
        malloc_zone_pressure_relief(nil, 0)
    }

    private static var hooksInstalled = false
    private static var pressureSource: DispatchSourceMemoryPressure?

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
}
