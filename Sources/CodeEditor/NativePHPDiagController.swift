import AppKit

/// Draws native PHP diagnostics: wavy underlines for errors / warnings / infos and a dimming veil over unused imports
/// (hint severity). A transparent overlay like the language-server one; the highlighter is never touched.
final class NPDiagOverlay: NSView {
    weak var textView: NSTextView?
    var items: [NPDiag] = [] { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer, !items.isEmpty else { return }
        let origin = tv.textContainerOrigin
        let length = tv.textStorage?.length ?? 0
        let visible = tv.visibleRect.insetBy(dx: 0, dy: -200)
        for d in items {
            let cr = NSIntersectionRange(d.range, NSRange(location: 0, length: length))
            guard cr.length > 0 else { continue }
            let gr = lm.glyphRange(forCharacterRange: cr, actualCharacterRange: nil)
            let bounds = lm.boundingRect(forGlyphRange: gr, in: tc).offsetBy(dx: origin.x, dy: origin.y)
            guard bounds.intersects(visible), bounds.intersects(dirtyRect.insetBy(dx: -4, dy: -4)) else { continue }
            if d.severity >= 4 {
                Theme.background.withAlphaComponent(0.55).setFill()
                lm.enumerateEnclosingRects(forGlyphRange: gr, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: tc) { rect, _ in
                    rect.offsetBy(dx: origin.x, dy: origin.y).fill()
                }
                continue
            }
            LSPSession.color(forSeverity: d.severity).setStroke()
            lm.enumerateEnclosingRects(forGlyphRange: gr, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: tc) { rect, _ in
                let r = rect.offsetBy(dx: origin.x, dy: origin.y)
                let y = r.maxY - 1.5
                let path = NSBezierPath()
                path.lineWidth = 1.1
                var x = r.minX
                var up = true
                path.move(to: NSPoint(x: x, y: y))
                while x < r.maxX {
                    x = min(x + 2, r.maxX)
                    path.line(to: NSPoint(x: x, y: up ? y - 1.6 : y))
                    up.toggle()
                }
                path.stroke()
            }
        }
    }
}

/// Per-tab driver: one debounced analysis after edits settle (never polling), only for PHP tabs, only while the window is
/// visible. The analysis itself runs on the project's fast-tier queue; the result is dropped if the buffer changed meanwhile.
final class NativePHPDiagController: NSObject {
    static let settingsDidChange = Notification.Name("CodeEditor.nativePHPDiagSettingsDidChange")
    private(set) static var controllers: [ObjectIdentifier: NativePHPDiagController] = [:]
    private static var started = false

    static func start() {
        guard !started else { return }
        started = true
        NPDiagSyntax.prime()
        EditorEvents.onOpen { tab in
            guard NativePHPDiag.handles(tab.url), tab.view is EditorPane else { return }
            let c = NativePHPDiagController(tab: tab)
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

    static func controller(for tab: EditorTab?) -> NativePHPDiagController? { tab.flatMap { controllers[ObjectIdentifier($0)] } }

    /// Diagnostics the editor hover should show at `offset` (native findings of the tab, deduplicated against Intelephense).
    static func hoverDiagnostics(for url: URL) -> [LSPDiagnostic] {
        guard let c = controllers.values.first(where: { $0.tab?.url.standardizedFileURL == url.standardizedFileURL }) else { return [] }
        return c.visible.map { LSPDiagnostic(range: $0.range, severity: $0.severity, message: $0.message, source: "PHP", code: $0.code) }
    }

    weak var tab: EditorTab?
    private var observers: [NSObjectProtocol] = []
    private var work: DispatchWorkItem?
    private var generation = 0
    private var pending = false
    private var needsInitial = true
    private var applying = false
    private(set) var overlay: NPDiagOverlay?
    /// Last analysis result and the subset shown (no duplicate of a language-server finding).
    private(set) var all: [NPDiag] = []
    private(set) var visible: [NPDiag] = []
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
        // A tab restored in the background is analysed the first time the user touches it.
        observers.append(nc.addObserver(forName: NSTextView.didChangeSelectionNotification, object: tab.textView, queue: .main) { [weak self] _ in
            guard let self, self.needsInitial else { return }
            self.needsInitial = false
            self.schedule(initial: true)
        })
        observers.append(nc.addObserver(forName: LanguageServers.problemsDidChange, object: nil, queue: .main) { [weak self] _ in
            guard let self, !self.applying, !self.all.isEmpty else { return }
            self.refilter()
        })
        if (NSApp.delegate as? AppDelegate)?.active?.current === tab || AppEnv.headless { needsInitial = false; schedule(initial: true) }
    }

    func detach() {
        work?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        overlay?.removeFromSuperview(); overlay = nil
        if let tab { NativeProblems.set(url: tab.url, []) }
        all = []; visible = []
    }

    // MARK: Scheduling

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
        let ns = text as NSString
        let url = tab.url
        let groups = NativePHPDiag.enabledGroups
        guard !groups.isEmpty, !tab.isLargeFile else { apply([], text: text); return }
        generation += 1
        let gen = generation
        let severity = NativePHPDiag.classSeverity
        let snapshot = NSString(string: text)
        if let r = FastTier.root(for: url) {
            let fp = FastProject.shared(root: URL(fileURLWithPath: r))
            fp.queue.async { [weak self] in
                let list = NativePHPDiag.analyze(url: url, text: snapshot, fp: fp, groups: groups, classSeverity: severity)
                DispatchQueue.main.async {
                    guard let self, gen == self.generation else { return }
                    self.apply(list, text: text)
                }
            }
        } else {
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let list = NativePHPDiag.analyze(url: url, text: snapshot, fp: nil, groups: groups, classSeverity: severity)
                DispatchQueue.main.async {
                    guard let self, gen == self.generation else { return }
                    self.apply(list, text: text)
                }
            }
        }
        _ = ns
    }

    /// Main thread. `text` is the buffer that was analysed; a changed buffer means a newer pass is on its way.
    func apply(_ list: [NPDiag], text: String) {
        guard let tab else { return }
        guard (tab.textView.string as NSString).length == (text as NSString).length else { return }
        passes += 1
        all = list
        let diags = NativePHPDiag.diagnostics(list, in: text as NSString)
        applying = true
        NativeProblems.set(url: tab.url, diags)
        applying = false
        refilter()
    }

    /// Recomputes what is drawn: native findings the language server does not already report.
    private func refilter() {
        guard let tab else { return }
        guard !all.isEmpty else { visible = []; overlay?.items = []; return }
        var shown = all
        let lsp = NativePHPDiagController.lspDiagnostics(for: tab)
        if !lsp.isEmpty {
            let ns = tab.textView.string as NSString
            let conv = NativePHPDiag.diagnostics(all, in: ns)
            let keep = Set(NativePHPDiag.dedupe(conv, against: lsp).map { "\($0.line):\($0.column):\($0.code ?? "")" })
            shown = zip(all, conv).filter { keep.contains("\($0.1.line):\($0.1.column):\($0.1.code ?? "")") }.map { $0.0 }
        }
        visible = shown
        guard let tv = Optional(tab.textView) else { return }
        if shown.isEmpty { overlay?.items = []; return }
        if overlay == nil || overlay?.superview !== tv {
            let o = NPDiagOverlay(frame: tv.bounds)
            o.autoresizingMask = [.width, .height]
            o.textView = tv
            tv.addSubview(o)
            overlay = o
        }
        overlay?.items = shown
    }

    static func lspDiagnostics(for tab: EditorTab) -> [FileProblems.Diagnostic] {
        guard let s = LanguageServers.session(for: tab) else { return [] }
        let list = s.allDiagnostics
        guard !list.isEmpty else { return [] }
        let table = LSPLineTable(s.text as NSString)
        return list.map { d in
            let a = table.position(of: d.range.location), b = table.position(of: NSMaxRange(d.range))
            return FileProblems.Diagnostic(severity: d.severity, message: d.message, line: a.line + 1, column: a.character + 1,
                                           endLine: b.line + 1, endColumn: b.character + 1, source: d.source, code: d.code)
        }
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
        visible = visible.map(moved)
        overlay?.items = visible
    }

    var squiggleCount: Int { overlay?.items.count ?? 0 }
}
