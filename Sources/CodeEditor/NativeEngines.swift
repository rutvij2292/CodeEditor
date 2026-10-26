import AppKit

/// The registry of native language engines: the ONE place that lists them, and the dispatch every editor feature goes through.
/// Adding / removing an engine is one line in `builtin`; a future plugin loader appends with `register(_:)`.
enum NativeEngines {
    /// The engines in list order (= Settings order, fan-out order). Lookup order is by `priority`.
    private static let builtin: [NativeEngine] = [
        PHPEngine(), PythonEngine(), WebEngine(), JSEngine(), VueEngine(),
    ]

    private static let lock = NSLock()
    private static var list: [NativeEngine] = builtin
    private static var byPriority: [NativeEngine] = sortedByPriority(builtin)

    private static func sortedByPriority(_ l: [NativeEngine]) -> [NativeEngine] {
        l.enumerated().sorted { ($0.element.priority, $0.offset) < ($1.element.priority, $1.offset) }.map(\.element)
    }

    static var all: [NativeEngine] { lock.lock(); defer { lock.unlock() }; return list }
    private static var ordered: [NativeEngine] { lock.lock(); defer { lock.unlock() }; return byPriority }

    /// Appends an engine (plugin loader). A second engine with the same id replaces the first.
    static func register(_ e: NativeEngine) {
        lock.lock(); defer { lock.unlock() }
        list.removeAll { $0.id == e.id }
        list.append(e)
        byPriority = sortedByPriority(list)
    }

    /// Test hook: runs `body` with exactly these engines.
    static func withEngines<T>(_ engines: [NativeEngine], _ body: () -> T) -> T {
        lock.lock(); let saved = (list, byPriority); list = engines; byPriority = sortedByPriority(engines); lock.unlock()
        defer { lock.lock(); (list, byPriority) = saved; lock.unlock() }
        return body()
    }

    static func engine(id: String) -> NativeEngine? { all.first { $0.id == id } }

    /// The engines that handle `url`, in lookup order.
    static func engines(for url: URL) -> [NativeEngine] { ordered.filter { $0.handles(url) } }
    static func handles(_ url: URL) -> Bool { ordered.contains { $0.handles(url) } }
    static func handles(_ url: URL, engine id: String) -> Bool { engine(id: id)?.handles(url) ?? false }
    static func needsSessionUI(_ url: URL) -> Bool { ordered.contains { $0.providesSessionUI && $0.handles(url) } }

    // MARK: Lookup (hover, Cmd-hover underline)

    /// Asks the engines that handle `url` one after the other until one's hit passes `accept`; the rest are not asked. The result is
    /// (nil, nil) when none answered, so the caller falls through to the external server. `stale` stops the chain early.
    static func lookup(url: URL, text: NSString, offset: Int, stale: @escaping () -> Bool = { false },
                       accept: @escaping (NPHit, NativeEngine) -> Bool,
                       completion: @escaping (NPHit?, NativeEngine?) -> Void) {
        step(engines(for: url), 0, url, text, offset, stale, accept, completion)
    }

    private static func step(_ es: [NativeEngine], _ i: Int, _ url: URL, _ text: NSString, _ offset: Int, _ stale: @escaping () -> Bool,
                             _ accept: @escaping (NPHit, NativeEngine) -> Bool, _ done: @escaping (NPHit?, NativeEngine?) -> Void) {
        guard i < es.count else { done(nil, nil); return }
        let e = es[i]
        e.lookup(url: url, text: text, offset: offset) { hit in
            if let hit, accept(hit, e) { done(hit, e); return }
            if stale() { return }
            step(es, i + 1, url, text, offset, stale, accept, done)
        }
    }

    // MARK: Navigation

    static func goToDefinition(in tab: EditorTab, at offset: Int) -> Bool {
        for e in engines(for: tab.url) where e.goToDefinition(in: tab, at: offset) { return true }
        return false
    }

    static func findUsages(_ w: ProjectWindow, tab: EditorTab) -> Bool {
        for e in ordered where e.findUsages(w, tab: tab) { return true }
        return false
    }

    static func rename(_ w: ProjectWindow) -> NativeRenameOutcome {
        for e in ordered {
            let r = e.rename(w)
            if case .notNative = r { continue }
            return r
        }
        return .notNative
    }

    /// The engine that answers signature help for `url`, if any.
    static func signatureEngine(for url: URL) -> NativeEngine? { ordered.first { $0.supportsSignatureHelp && $0.handles(url) } }

    // MARK: Fan-out

    static func hoverDiagnostics(for tab: EditorTab?) -> [LSPDiagnostic] { all.flatMap { $0.hoverDiagnostics(for: tab) } }

    static func registerCompletions() {
        for e in all.enumerated().sorted(by: { ($0.element.completionRank, $0.offset) < ($1.element.completionRank, $1.offset) }) { e.element.registerCompletion() }
    }

    /// App launch: diagnostics drivers and the event-driven memory hooks.
    static func start() { for e in all { e.startDiagnostics(); e.installMemoryHooks() } }

    static func invalidate(root: URL) { for e in all { e.invalidate(root: root) } }
    static func invalidate(root: URL, paths: [String]) { for e in all { e.invalidate(root: root, paths: paths) } }
    static func trimMemory() { for e in all { e.trimMemory() } }
    static func resetPrefs() { for e in all { e.resetPrefs() } }

    static func allowsLinkHighlight(_ url: URL) -> Bool { all.allSatisfy { $0.allowsLinkHighlight(for: url) } }
    static func suppressesServer(_ id: String, root: URL? = nil) -> Bool { all.contains { $0.suppressesServer(id, root: root) } }
    static func suppressesBuiltinCompletion(_ topic: NativeBuiltinCompletionTopic, for url: URL) -> Bool {
        all.contains { $0.suppressesBuiltinCompletion(topic, for: url) }
    }

    static var settingsSections: [NativeSettingsSection] { all.flatMap(\.settingsSections) }
}
