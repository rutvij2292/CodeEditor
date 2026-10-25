import AppKit
import SwiftTreeSitter

/// Native Python language service (no pyright / pylsp process). Built on the tree-sitter Python grammar: a file is parsed once
/// into a small outline (NativePyOutline) and the syntax tree is dropped; resolution (names, members, imports, venv /
/// site-packages / stdlib discovery) happens on demand in NativePyResolve. Work runs on a per-project serial utility queue,
/// outlines live in a byte-capped cache (NativePyCache), nothing runs on a timer and memory is released on pressure / hide.
/// Features: go to definition, hover with docstrings (this file + NativePyLookup), find usages (NativePyRefs), completion
/// (NativePyComplete), conservative diagnostics (NativePyDiag).
enum NativePy {
    static let enabledKey = "py.native.enabled"

    /// 'Use native Python engine'. Default ON: there is no other Python language service.
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static let maxBufferChars = 1_500_000

    static func handles(_ url: URL) -> Bool {
        guard enabled else { return false }
        let e = url.pathExtension.lowercased()
        return e == "py" || e == "pyi" || e == "pyw"
    }

    static func project(for url: URL) -> PyProject {
        PyProject.shared(root: PyEnvDiscovery.projectRoot(for: url))
    }

    // MARK: Live buffer

    /// Only on the project's queue. Parses `text` (memoised for the last buffer) and returns the context, outline and tree.
    static func prepare(_ project: PyProject, url: URL, text: NSString) -> (ctx: PyCtx, file: PyFile, tree: MutableTree)? {
        installMemoryHooks()
        if text.length > maxBufferChars { return nil }          // generated / data files: not worth parsing for a language service
        let path = url.standardizedFileURL.path
        let key = path + "|\(text.length)|\(text.hash)"
        if project.liveKey == key, let f = project.liveFile, let t = project.liveTree {
            return (PyCtx(project: project, livePath: path, live: f), f, t)
        }
        guard let parser = project.parser, let tree = parser.parse(text as String), let root = tree.rootNode else { return nil }
        let owned = NSString(string: text as String)
        let f = PyOutlineBuilder(path: path, ns: owned, root: root).file
        f.live = owned
        PyCache.drop(path)                      // the stale on-disk outline of the open file must not be used by other requests
        project.liveKey = key; project.liveFile = f; project.liveTree = tree
        return (PyCtx(project: project, livePath: path, live: f), f, tree)
    }

    // MARK: Lookup

    static func lookup(url: URL, text: NSString, offset: Int) -> NPHit? {
        guard handles(url) else { return nil }
        let p = project(for: url)
        return p.queue.sync { lookupOnQueue(p, url: url, text: text, offset: offset) }
    }

    private static func lookupOnQueue(_ p: PyProject, url: URL, text: NSString, offset: Int) -> NPHit? {
        guard let (ctx, file, tree) = prepare(p, url: url, text: text), let root = tree.rootNode else { return nil }
        return PyResolver(ctx: ctx).lookupHit(file: file, root: root, ns: file.live ?? text, offset: offset)
    }

    static func lookupAsync(url: URL, text: NSString, offset: Int, completion: @escaping (NPHit?) -> Void) {
        guard handles(url) else { completion(nil); return }
        let p = project(for: url)
        let snapshot = NSString(string: text as String)
        p.queue.async {
            let hit = lookupOnQueue(p, url: url, text: snapshot, offset: offset)
            DispatchQueue.main.async { completion(hit) }
        }
    }

    static func hover(url: URL, text: NSString, offset: Int) -> String? { lookup(url: url, text: text, offset: offset)?.markdown }

    // MARK: Go to definition (LanguageServers.beforeDefinition)

    /// True when native handled the jump. On a declaration itself it shows the usages instead (like PyCharm).
    static func goToDefinition(in tab: EditorTab, at offset: Int) -> Bool {
        guard handles(tab.url) else { return false }
        let text = tab.textView.string as NSString
        guard let hit = lookup(url: tab.url, text: text, offset: offset), !hit.targets.isEmpty else { return false }
        let here = tab.url.standardizedFileURL.path
        let others = hit.targets.filter { !($0.path == here && NSLocationInRange($0.offset, hit.range)) }
        if others.isEmpty {
            tab.textView.setSelectedRange(NSRange(location: hit.range.location, length: 0))
            return NativePyUI.findUsages(tab: tab)
        }
        return NativePHP.open(hit, from: tab, offset: offset)
    }

    // MARK: Memory

    static func trimMemory() {
        PyCache.clear()
        PyProject.trimAll()
        malloc_zone_pressure_relief(nil, 0)
    }

    private static var hooksInstalled = false
    private static var pressureSource: DispatchSourceMemoryPressure?
    private static let hookLock = NSLock()

    /// Event driven trimming (never a timer): memory pressure, all windows hidden / app hidden, power saver on. Installed on first use.
    static func installMemoryHooks() {
        hookLock.lock()
        if hooksInstalled { hookLock.unlock(); return }
        hooksInstalled = true
        hookLock.unlock()
        let src = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global(qos: .utility))
        src.setEventHandler { trimMemory() }
        src.resume()
        pressureSource = src
        DispatchQueue.main.async {
            let nc = NotificationCenter.default
            nc.addObserver(forName: PowerState.didChange, object: nil, queue: .main) { _ in
                if PowerState.shared.saver { DispatchQueue.global(qos: .utility).async { trimMemory() } }
            }
            nc.addObserver(forName: NSApplication.didHideNotification, object: nil, queue: .main) { _ in
                DispatchQueue.global(qos: .utility).async { trimMemory() }
            }
            nc.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main) { _ in
                guard !AppEnv.headless else { return }
                let anyVisible = NSApp.windows.contains { $0.isVisible && $0.occlusionState.contains(.visible) && !$0.isMiniaturized }
                if !anyVisible { DispatchQueue.global(qos: .utility).async { trimMemory() } }
            }
        }
    }

    /// Registered through the engine registry (NativeEngines.swift: PythonEngine).
    static func registerCompletion() {
        CompletionRegistry.register(NativePyCompletionProvider(), forExtensions: ["py", "pyi", "pyw"])
    }
}
