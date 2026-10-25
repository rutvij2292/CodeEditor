import AppKit

/// Per-tab driver of the native Python diagnostics: one debounced analysis after edits settle (never polling), only for Python
/// tabs, only while the window is visible, on the project's queue. Draws with the same overlay as the PHP diagnostics.
final class NativePyDiagController: NSObject {
    static let settingsDidChange = Notification.Name("CodeEditor.nativePyDiagSettingsDidChange")
    private(set) static var controllers: [ObjectIdentifier: NativePyDiagController] = [:]
    private static var started = false

    static func start() {
        guard !started else { return }
        started = true
        EditorEvents.onOpen { tab in
            guard NativePy.handles(tab.url), tab.view is EditorPane else { return }
            let c = NativePyDiagController(tab: tab)
            controllers[ObjectIdentifier(tab)] = c
            c.attach()
        }
        EditorEvents.onClose { tab in controllers.removeValue(forKey: ObjectIdentifier(tab))?.detach() }
        NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main) { note in
            guard let w = note.object as? NSWindow, w.occlusionState.contains(.visible) else { return }
            for c in controllers.values where c.tab?.textView.window === w { c.flushPending() }
        }
        NotificationCenter.default.addObserver(forName: settingsDidChange, object: nil, queue: .main) { _ in
            for c in controllers.values { c.schedule(initial: false) }
        }
    }

    static func hoverDiagnostics(for tab: EditorTab?) -> [LSPDiagnostic] {
        guard let tab, let c = controllers[ObjectIdentifier(tab)] else { return [] }
        return c.hoverList
    }

    weak var tab: EditorTab?
    private var observers: [NSObjectProtocol] = []
    private var work: DispatchWorkItem?
    private var generation = 0
    private var pending = false
    private var needsInitial = true
    private(set) var overlay: NPDiagOverlay?
    private(set) var all: [NPDiag] = [] { didSet { hoverList = all.map { LSPDiagnostic(range: $0.range, severity: $0.severity, message: $0.message, source: "Python", code: $0.code) } } }
    private(set) var hoverList: [LSPDiagnostic] = []
    private(set) var passes = 0

    init(tab: EditorTab) { self.tab = tab }

    func attach() {
        guard let tab else { return }
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSText.didChangeNotification, object: tab.textView, queue: .main) { [weak self] _ in
            self?.needsInitial = false
            self?.schedule(initial: false)
        })
        if let storage = tab.textView.textStorage {
            observers.append(nc.addObserver(forName: NSTextStorage.didProcessEditingNotification, object: storage, queue: .main) { [weak self] n in
                guard let s = n.object as? NSTextStorage, s.editedMask.contains(.editedCharacters) else { return }
                self?.shift(edited: s.editedRange, delta: s.changeInLength)
            })
        }
        observers.append(nc.addObserver(forName: NSTextView.didChangeSelectionNotification, object: tab.textView, queue: .main) { [weak self] _ in
            guard let self, self.needsInitial else { return }
            self.needsInitial = false
            self.schedule(initial: true)
        })
        if (NSApp.delegate as? AppDelegate)?.active?.current === tab || AppEnv.headless { needsInitial = false; schedule(initial: true) }
    }

    func detach() {
        work?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        overlay?.removeFromSuperview(); overlay = nil
        if let tab { NativeProblems.set(url: tab.url, []) }
        all = []
    }

    func schedule(initial: Bool) {
        work?.cancel()
        let delay = initial ? 0.5 : PowerState.shared.scaled(0.9)
        let w = DispatchWorkItem { [weak self] in self?.run() }
        work = w
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: w)
    }

    func flushPending() {
        guard pending else { return }
        pending = false
        schedule(initial: true)
    }

    private func run() {
        guard let tab else { return }
        if PowerState.windowHidden(tab.textView) { pending = true; return }
        let text = tab.textView.string
        let url = tab.url
        let groups = PyDiagGroup.enabledSet
        guard NativePy.handles(url), !groups.isEmpty, !tab.isLargeFile else { apply([], text: text); return }
        generation += 1
        let gen = generation
        let snapshot = NSString(string: text)
        let project = NativePy.project(for: url)
        project.queue.async { [weak self] in
            let list = PyDiag.analyze(project: project, url: url, text: snapshot, groups: groups)
            DispatchQueue.main.async {
                guard let self, gen == self.generation else { return }
                self.apply(list, text: text)
            }
        }
    }

    func apply(_ list: [NPDiag], text: String) {
        guard let tab else { return }
        guard (tab.textView.string as NSString).length == (text as NSString).length else { return }
        passes += 1
        all = list
        let table = NPLineStarts(text as NSString)
        let diags = list.map { d -> FileProblems.Diagnostic in
            let a = table.position(of: d.range.location), b = table.position(of: NSMaxRange(d.range))
            return FileProblems.Diagnostic(severity: d.severity, message: d.message, line: a.line, column: a.col, endLine: b.line, endColumn: b.col, source: "Python", code: d.code)
        }
        NativeProblems.set(url: tab.url, diags)
        let tv = tab.textView
        if list.isEmpty { overlay?.items = []; return }
        if overlay == nil || overlay?.superview !== tv {
            let o = NPDiagOverlay(frame: tv.bounds)
            o.autoresizingMask = [.width, .height]
            o.textView = tv
            tv.addSubview(o)
            overlay = o
        }
        overlay?.items = list
    }

    private func shift(edited: NSRange, delta: Int) {
        guard !all.isEmpty else { return }
        let oldEnd = edited.location + edited.length - delta
        func moved(_ d: NPDiag) -> NPDiag {
            var d = d
            let s = d.range.location, e = NSMaxRange(d.range)
            if e <= edited.location { return d }
            if s >= oldEnd { d.range.location = s + delta; return d }
            let newEnd = max(s, e + delta)
            d.range = NSRange(location: min(s, edited.location), length: max(0, newEnd - min(s, edited.location)))
            return d
        }
        all = all.map(moved)
        overlay?.items = all
    }

    var squiggleCount: Int { overlay?.items.count ?? 0 }
}
