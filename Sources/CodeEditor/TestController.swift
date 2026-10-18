import AppKit

/// Per-project-window test runner: owns the Tests panel, runs requests through `TestRunner` and records them in the store.
final class TestController: NSObject {
    private final class Weak { weak var controller: TestController?; init(_ c: TestController) { controller = c } }
    private static var all: [String: Weak] = [:]
    static func controller(forRoot root: URL) -> TestController? { all[root.standardizedFileURL.path]?.controller }

    fileprivate static var ownerKey = 0
    let root: URL
    let panel = TestPanelController()
    private let runner = TestRunner()
    private let store = TestResultsStore.shared
    /// Reveals the Tests tab (set by the window wiring).
    var showPanel: (() -> Void)?
    /// Called on the main thread when a run ends (tests).
    var onFinish: ((TestRunner.Outcome) -> Void)?

    init(root: URL) {
        self.root = root.standardizedFileURL
        super.init()
        Self.all[self.root.path] = Weak(self)
        panel.onRerun = { [weak self] in self?.rerunLast() }
        panel.onRerunFailed = { [weak self] in self?.rerunFailed() }
        panel.onStop = { [weak self] in self?.stop() }
    }

    func run(_ request: TestRequest) {
        guard !store.isRunning else { NSSound.beep(); return }
        let junit = TestRunner.junitTempPath()
        guard let command = TestRunner.command(root: root, request: request, junit: junit) else {
            store.fail(status: "No vendor/bin/pest or vendor/bin/phpunit in this project")
            showPanel?()
            return
        }
        store.begin(request, root: root)
        showPanel?()
        runner.start(command, junit: junit, onOutput: { [weak self] in self?.store.appendOutput($0) }) { [weak self] outcome in
            guard let self else { return }
            self.finished(outcome, request: request)
        }
    }

    private func finished(_ outcome: TestRunner.Outcome, request: TestRequest) {
        if outcome.cancelled {
            store.fail(status: "Cancelled")
        } else if outcome.results.isEmpty {
            store.fail(status: outcome.junitMissing ? "No results written (exit \(outcome.exitCode)); see output" : "No tests executed")
        } else {
            let r = outcome.results
            let failed = r.filter(\.isFailure).count, skipped = r.filter { $0.status == .skipped }.count
            let passed = r.count - failed - skipped
            let time = r.reduce(0) { $0 + $1.time }
            var s = "\(passed) passed"
            if failed > 0 { s += ", \(failed) failed" }
            if skipped > 0 { s += ", \(skipped) skipped" }
            store.finish(results: r, request: request, status: s + String(format: " in %.2fs", time))
        }
        onFinish?(outcome)
    }

    func rerunLast() { if let r = store.lastRequest { run(r) } }

    func rerunFailed() {
        guard let r = TestRunner.request(rerunning: store.failed) else { NSSound.beep(); return }
        run(r)
    }

    func stop() { runner.cancel() }

    func runAll() { run(TestRequest(title: "all tests")) }
}

/// Menu actions; they act on the active project window's controller.
final class TestActions: NSObject {
    static let shared = TestActions()

    private var controller: TestController? { (NSApp.delegate as? AppDelegate)?.active?.root.flatMap { TestController.controller(forRoot: $0) } }

    @objc func runAtCaret(_ sender: Any?) {
        guard let tab = (NSApp.delegate as? AppDelegate)?.active?.current, let g = TestGutter.controller(for: tab), let t = g.testAtCaret() else { NSSound.beep(); return }
        g.run(t)
    }

    @objc func runFile(_ sender: Any?) {
        guard let tab = (NSApp.delegate as? AppDelegate)?.active?.current, let g = TestGutter.controller(for: tab), !g.tests.isEmpty else { NSSound.beep(); return }
        g.run(TestRequest(title: tab.url.lastPathComponent, paths: [tab.url.standardizedFileURL.path]), in: tab)
    }

    @objc func runAll(_ sender: Any?) { controller?.runAll() }
    @objc func rerunLast(_ sender: Any?) { controller?.rerunLast() }
    @objc func rerunFailed(_ sender: Any?) { controller?.rerunFailed() }
    @objc func stop(_ sender: Any?) { controller?.stop() }
    @objc func showTests(_ sender: Any?) { controller?.showPanel?() }

    /// The top-level "Run" menu.
    static func menuItem() -> NSMenuItem {
        func item(_ title: String, _ action: Selector, _ key: String = "", _ mods: NSEvent.ModifierFlags = [.control]) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = key.isEmpty ? [] : mods
            i.target = shared
            return i
        }
        let menu = NSMenu(title: "Run")
        for i in [item("Run Test at Caret", #selector(runAtCaret(_:)), "r", [.control, .shift]),
                  item("Run Tests in File", #selector(runFile(_:))),
                  item("Run All Tests", #selector(runAll(_:))),
                  NSMenuItem.separator(),
                  item("Re-run Last Tests", #selector(rerunLast(_:)), "r"),
                  item("Re-run Failed Tests", #selector(rerunFailed(_:))),
                  item("Stop Tests", #selector(stop(_:))),
                  NSMenuItem.separator(),
                  item("Tests Tool Window", #selector(showTests(_:)), "7", [.command])] { menu.addItem(i) }
        let top = NSMenuItem(title: "Run", action: nil, keyEquivalent: "")
        top.submenu = menu
        return top
    }
}

extension ProjectWindow {
    func installTestsPanel(root: URL) {
        guard !hasToolPanel("tests") else { return }
        TestGutter.start()
        let c = TestController(root: root)
        objc_setAssociatedObject(self, &TestController.ownerKey, c, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)   // lives as long as the window
        c.showPanel = { [weak self] in self?.showToolPanel("tests") }
        c.panel.onOpen = { [weak self] path, line in
            self?.open(URL(fileURLWithPath: path), line: line)
            self?.current?.textView.goToLine(line, column: 1)
        }
        registerToolPanel(id: "tests", title: "Tests", view: c.panel.view)
        // Lives as long as the window (weak self); the token is not needed.
        _ = NotificationCenter.default.addObserver(forName: TestResultsStore.didChange, object: nil, queue: .main) { [weak self] n in
            guard n.userInfo?["outputOnly"] == nil else { return }
            let failed = TestResultsStore.shared.failed.count
            self?.setToolPanelBadge(TestResultsStore.shared.isRunning ? "…" : (failed > 0 ? "\(failed)" : nil), for: "tests")
        }
    }
}
