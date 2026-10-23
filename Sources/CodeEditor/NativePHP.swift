import AppKit

/// Native PHP language service (replaces Intelephense feature by feature, see docs/native-php.md).
///
/// Built on the fast tier (PHPLex + FTParser + FTEval + VendorIndex). Phase 1: go to definition and hover. Later phases plug in
/// next to `lookup` (find usages, rename, signature help, diagnostics) and reuse `NPResolver`. Everything is on demand: one
/// request lexes the live buffer (last result memoised), reads at most a handful of PHP files (NPFiles, capped) and runs on
/// the project's fast-tier queue. No timers, no background indexing of its own.
enum NativePHP {
    static let nativeOnlyKey = "php.nativeOnly"

    /// 'Use native PHP engine only (stop Intelephense)'. Default OFF: Intelephense stays the fallback.
    static var nativeOnly: Bool {
        get { UserDefaults.standard.object(forKey: nativeOnlyKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: nativeOnlyKey) }
    }

    /// Applies the preference to running servers (stops / restarts Intelephense).
    static func setNativeOnly(_ on: Bool) {
        nativeOnly = on
        LanguageServerManager.shared.serverPreferenceChanged("intelephense")
    }

    static var enabled: Bool { FastTier.enabled }

    static func handles(_ url: URL) -> Bool {
        guard enabled else { return false }
        let e = url.pathExtension.lowercased()
        return e == "php" || e == "phtml"
    }

    // MARK: Lookup

    private static let parseLock = NSLock()
    private static var lastParse: (key: String, lex: PHPLex, cur: FTClass?)?

    static func resolver(fp: FastProject, url: URL, text: NSString) -> NPResolver {
        let key = url.path + "|\(text.length)|\(text.hash)"
        parseLock.lock()
        if let p = lastParse, p.key == key { parseLock.unlock(); return NPResolver(fp: fp, url: url, text: text, lex: p.lex, cur: p.cur) }
        parseLock.unlock()
        let lex = PHPLex(text)
        let cur = FTParser.parse(text, lex: lex)
        parseLock.lock(); lastParse = (key, lex, cur); parseLock.unlock()
        return NPResolver(fp: fp, url: url, text: text, lex: lex, cur: cur)
    }

    /// Synchronous lookup (tests, Cmd-B). Main thread callers wait on the project's fast-tier queue.
    static func lookup(url: URL, text: NSString, offset: Int, root: String? = nil) -> NPHit? {
        guard handles(url), let r = root ?? FastTier.root(for: url) else { return nil }
        let fp = FastProject.shared(root: URL(fileURLWithPath: r))
        return fp.queue.sync { resolver(fp: fp, url: url, text: text).lookup(at: offset) }
    }

    /// Asynchronous lookup for hover / link underline; `completion` runs on the main queue.
    static func lookupAsync(url: URL, text: NSString, offset: Int, completion: @escaping (NPHit?) -> Void) {
        guard handles(url), let r = FastTier.root(for: url) else { completion(nil); return }
        let fp = FastProject.shared(root: URL(fileURLWithPath: r))
        let snapshot = NSString(string: text as String)
        fp.queue.async {
            let hit = resolver(fp: fp, url: url, text: snapshot).lookup(at: offset)
            DispatchQueue.main.async { completion(hit) }
        }
    }

    /// Hover markdown for the token at `offset` (nil when native has no answer).
    static func hover(url: URL, text: NSString, offset: Int) -> String? {
        lookup(url: url, text: text, offset: offset)?.markdown
    }

    // MARK: Go to definition (called through LanguageServers.beforeDefinition)

    /// True when native handled the jump. A hit that points at the clicked declaration itself is not consumed
    /// (so Intelephense / usages can answer).
    static func goToDefinition(in tab: EditorTab, at offset: Int) -> Bool {
        guard handles(tab.url) else { return false }
        let text = tab.textView.string as NSString
        guard let hit = lookup(url: tab.url, text: text, offset: offset), !hit.targets.isEmpty else { return false }
        return open(hit, from: tab, offset: offset)
    }

    @discardableResult
    static func open(_ hit: NPHit, from tab: EditorTab, offset: Int) -> Bool {
        let here = tab.url.standardizedFileURL.path
        let targets = hit.targets.filter { !($0.path == here && NSLocationInRange($0.offset, hit.range)) }
        guard !targets.isEmpty else { return false }
        let go: (NPTarget) -> Void = { t in
            if let h = LaravelNavigator.openLocation { h(URL(fileURLWithPath: t.path), t.line, t.column) }
            else { LanguageServers.openLocation?(URL(fileURLWithPath: t.path), t.line, t.column) }
        }
        if targets.count == 1 { go(targets[0]); return true }
        guard let window = tab.textView.window else { go(targets[0]); return true }
        let items = targets.prefix(50).map { t in
            PickerItem(title: "\((t.path as NSString).lastPathComponent):\(t.line)", detail: t.path, symbol: "doc.text") { go(t) }
        }
        QuickPicker.present(over: window, placeholder: "Go to definition", items: Array(items))
        return true
    }
}
