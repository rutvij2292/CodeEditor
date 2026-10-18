import AppKit

/// Run markers and pass/fail icons in the gutter of PHP test files. One controller per open tab, attached through
/// `EditorEvents`; the text is rescanned (debounced) on edits and the icons are refreshed when results change.
enum TestGutter {
    private static var started = false
    private static var controllers: [ObjectIdentifier: TestGutterController] = [:]

    static func start() {
        guard !started else { return }
        started = true
        EditorEvents.onOpen { tab in
            guard !tab.isLargeFile, tab.url.pathExtension.lowercased() == "php" else { return }
            let c = TestGutterController(tab: tab)
            controllers[ObjectIdentifier(tab)] = c
            c.begin()
        }
        EditorEvents.onClose { tab in controllers.removeValue(forKey: ObjectIdentifier(tab))?.end() }
        EditorEvents.onSave { tab in controllers[ObjectIdentifier(tab)]?.rescan() }
    }

    static func controller(for tab: EditorTab) -> TestGutterController? { controllers[ObjectIdentifier(tab)] }
}

final class TestGutterController {
    private weak var tab: EditorTab?
    private weak var gutter: GutterView?
    private let path: String
    private(set) var tests: [DiscoveredTest] = []
    private var debounce: DispatchWorkItem?
    private static let maxBytes = 1_000_000

    init(tab: EditorTab) {
        self.tab = tab
        self.path = tab.url.standardizedFileURL.path
        self.gutter = (tab.view.subviews.first as? EditorContainer)?.gutter
    }

    func begin() {
        guard let tab, let gutter else { return }
        gutter.onIconClick = { [weak self] line in self?.iconClicked(line: line) }
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(textChanged), name: NSText.didChangeNotification, object: tab.textView)
        nc.addObserver(self, selector: #selector(resultsChanged(_:)), name: TestResultsStore.didChange, object: nil)
        rescan()
    }

    func end() {
        NotificationCenter.default.removeObserver(self)
        debounce?.cancel()
        gutter?.onIconClick = nil
        gutter?.lineIcons = [:]
    }

    @objc private func textChanged() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.rescan() }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    @objc private func resultsChanged(_ n: Notification) {
        if n.userInfo?["outputOnly"] != nil { return }
        applyIcons()
    }

    func rescan() {
        guard let tab else { return }
        let s = tab.textView.string
        tests = s.utf8.count > Self.maxBytes ? [] : TestDiscovery.discover(in: s)
        applyIcons()
    }

    private func applyIcons() {
        let store = TestResultsStore.shared
        let running = store.isRunning && (store.runningPaths?.contains(path) ?? true)
        var icons: [Int: GutterLineIcon] = [:]
        for t in tests {
            if running { icons[t.line] = .running; continue }
            switch t.kind {
            case .method, .pest:
                guard let r = store.result(for: t, in: path) else { icons[t.line] = .run; continue }
                icons[t.line] = r.isFailure ? .failed : (r.status == .skipped ? .skipped : .passed)
            case .class, .file:
                switch store.summary(in: path) {
                case .some(.failed), .some(.errored): icons[t.line] = .failed
                case .some(.passed): icons[t.line] = .passed
                case .some(.skipped): icons[t.line] = .skipped
                case .none: icons[t.line] = .run
                }
            }
        }
        gutter?.lineIcons = icons
    }

    private func iconClicked(line: Int) {
        guard let t = tests.first(where: { $0.line == line }) else { return }
        run(t)
    }

    /// Runs one discovered test (or the class / file it stands for) in the tab's project.
    func run(_ t: DiscoveredTest) {
        guard let tab else { return }
        run(TestRunner.request(for: t, file: path), in: tab)
    }

    func run(_ request: TestRequest, in tab: EditorTab) {
        if tab.isDirty { tab.save() }
        guard let root = tab.projectRoot?(), let c = TestController.controller(forRoot: root) else { return }
        c.run(request)
    }

    /// The test the caret is in: the last method/Pest test starting at or above the caret line, else the file.
    func testAtCaret() -> DiscoveredTest? {
        guard let tab else { return nil }
        let caret = tab.textView.selectedRange().location
        let ns = tab.textView.string as NSString
        var line = 1
        var i = 0
        while i < min(caret, ns.length) {
            let r = ns.range(of: "\n", options: [], range: NSRange(location: i, length: min(caret, ns.length) - i))
            if r.location == NSNotFound { break }
            line += 1; i = NSMaxRange(r)
        }
        let cases = tests.filter { $0.kind == .method || $0.kind == .pest }
        return cases.last(where: { $0.line <= line }) ?? tests.first(where: { $0.kind == .class || $0.kind == .file })
    }
}
