import AppKit
import SwiftTreeSitter

/// Per-pane state EditorPane keeps for the viewer (views and constraints are created lazily, only while a viewer is shown).
struct ViewerPaneState {
    var side: NSView?
    var divider: NSView?
    var control: NSSegmentedControl?
    var halfWidth: NSLayoutConstraint?
    var fullWidth: NSLayoutConstraint?
    var contentToSide: NSLayoutConstraint?
}

/// Markdown preview and JSON / YAML structure viewer: attaches a `ViewerController` to every .md / .json / .yml tab.
/// Nothing is created for a tab until its mode leaves "source"; while the mode is "source" only the (debounced, bounded)
/// diagnostics pass runs for JSON / YAML.
final class ViewerSystem: NSObject, NSMenuItemValidation {
    static let shared = ViewerSystem()
    private(set) static var controllers: [ObjectIdentifier: ViewerController] = [:]
    private static var started = false
    /// Tests: report JSON syntax problems natively even when the JSON language server is attached.
    static var alwaysNativeJSON = false

    static func start() {
        guard !started else { return }
        started = true
        EditorEvents.onOpen { tab in
            guard let kind = ViewerKind.detect(tab.url), tab.view is EditorPane else { return }
            let c = ViewerController(tab: tab, kind: kind)
            controllers[ObjectIdentifier(tab)] = c
            c.attach()
        }
        EditorEvents.onClose { tab in controllers.removeValue(forKey: ObjectIdentifier(tab))?.detach() }
        NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main) { note in
            guard let w = note.object as? NSWindow, w.occlusionState.contains(.visible) else { return }
            for c in controllers.values where c.pane?.window === w { c.flushPending() }
        }
    }

    static func controller(for tab: EditorTab?) -> ViewerController? { tab.flatMap { controllers[ObjectIdentifier($0)] } }
    private var currentTab: EditorTab? { (NSApp.delegate as? AppDelegate)?.active?.current }
    private var currentController: ViewerController? { Self.controller(for: currentTab) }

    // MARK: Menu

    @objc func cycleMode(_ sender: Any?) { currentController.map { $0.setMode($0.mode.next) } }
    @objc func showSource(_ sender: Any?) { currentController?.setMode(.source) }
    @objc func showSplit(_ sender: Any?) { currentController?.setMode(.split) }
    @objc func showPreview(_ sender: Any?) { currentController?.setMode(.preview) }
    @objc func formatJSON(_ sender: Any?) { _ = currentTab.map { Self.formatJSON($0, minify: false) } }
    @objc func minifyJSON(_ sender: Any?) { _ = currentTab.map { Self.formatJSON($0, minify: true) } }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let c = currentController
        switch item.action {
        case #selector(formatJSON(_:)), #selector(minifyJSON(_:)): return c?.kind == .json
        case #selector(showSource(_:)): item.state = c?.mode == .source ? .on : .off; return c != nil
        case #selector(showSplit(_:)): item.state = c?.mode == .split ? .on : .off; return c != nil
        case #selector(showPreview(_:)):
            item.state = c?.mode == .preview ? .on : .off
            item.title = c.map { $0.kind.isStructured ? "Tree Only" : "Preview Only" } ?? "Preview Only"
            return c != nil
        default: return c != nil
        }
    }

    /// StatusBar affordance: (visible, label) for the current tab.
    static func statusInfo(for tab: EditorTab?) -> (visible: Bool, text: String) {
        guard let c = controller(for: tab) else { return (false, "") }
        return (true, c.mode == .source ? "Source" : (c.mode == .split ? "Split" : c.kind.previewTitle))
    }

    /// Verification (CE_VIEWER=source|split|preview [CE_VIEWER_SELECT=0,2,1] [CE_VIEWER_FILTER=text]): puts the current tab in a viewer mode.
    static func decorate(_ w: ProjectWindow, mode: String) {
        guard let c = controller(for: w.current) else { return }
        w.window.setContentSize(NSSize(width: 1400, height: 860))
        c.setMode(ViewerMode(rawValue: mode) ?? .split, persist: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            if AppEnv.value("CE_PROBE") != nil { ViewerSystem.probe(w) }
            if let l = AppEnv.value("CE_VIEWER_LINE").flatMap(Double.init) { c.scrollEditor(toLine: l); c.syncScroll() }
            if let q = AppEnv.value("CE_VIEWER_FILTER") { c.tree?.setFilter(q) }
            else if let sel = AppEnv.value("CE_VIEWER_SELECT") { c.tree?.select(positions: sel.split(separator: ",").compactMap { Int($0) }) }
        }
    }

    static func probe(_ w: ProjectWindow) {
        guard let c = controller(for: w.current), let m = c.markdown, let root = w.window.contentView else { return }
        root.layoutSubtreeIfNeeded()
        let tv = m.textView, sv = m.scroll
        fputs("PROBE mode=\(c.mode) preview frame=\(m.frame) scroll=\(sv.frame) contentSize=\(sv.contentSize) doc=\(tv.frame) max=\(tv.maxSize) min=\(tv.minSize) vres=\(tv.isVerticallyResizable) clip=\(sv.contentView.bounds)\n", stderr)
        let pt = root.convert(NSPoint(x: tv.bounds.midX, y: 100), from: tv)
        let hit = root.hitTest(pt)
        fputs("PROBE hit=\(String(describing: hit.map { type(of: $0) })) isTV=\(hit === tv)\n", stderr)
        let before = m.scrollY
        if let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -120, wheel2: 0, wheel3: 0), let ev = NSEvent(cgEvent: cg) {
            sv.scrollWheel(with: ev)
        }
        fputs("PROBE wheel before=\(before) after=\(m.scrollY)\n", stderr)
    }

    static func cycle(_ tab: EditorTab?) { controller(for: tab).map { $0.setMode($0.mode.next) } }

    // MARK: JSON formatting

    /// Format (indent from .editorconfig / the file / 4 spaces) or minify. Returns false (and flashes why) when the JSON is invalid.
    @discardableResult
    static func formatJSON(_ tab: EditorTab, minify: Bool) -> Bool {
        let text = tab.textView.string
        let bytes = Array(text.utf8)
        let tape = JSONTapeParser.parse(bytes, lenient: true)
        if let err = tape.issues.first(where: { $0.severity == 1 }) {
            let pos = LineCol(text as NSString, err.offset)
            (NSApp.delegate as? AppDelegate)?.active?.statusBar.flash("Can’t \(minify ? "minify" : "format"): \(err.message) at \(pos.line):\(pos.col)")
            return false
        }
        let unit = IndentSettings.resolve(for: tab.url, text: text).unit
        guard let out = JSONFormatter.reformat(bytes, unit: unit, minify: minify) else {
            (NSApp.delegate as? AppDelegate)?.active?.statusBar.flash("Can’t \(minify ? "minify" : "format") JSON that contains comments")
            return false
        }
        if out != text { tab.replaceText(out, actionName: minify ? "Minify JSON" : "Format JSON") }
        return true
    }

    /// Reformat Code fallback hook (⌥⌘L when no external formatter handled the file): JSON formats natively.
    static func reformat(_ tab: EditorTab) -> Bool {
        guard ViewerKind.detect(tab.url) == .json, !tab.isReadOnly else { return false }
        return formatJSON(tab, minify: false)
    }
}

struct LineCol {
    let line: Int, col: Int
    init(_ ns: NSString, _ offset: Int) {
        let o = max(0, min(offset, ns.length))
        var line = 1, start = 0
        var i = 0
        while i < o {
            if ns.character(at: i) == 10 { line += 1; start = i + 1 }
            i += 1
        }
        self.line = line; col = o - start + 1
    }
}

/// Token-level JSON pretty printer / minifier that keeps key order, number spelling and string escapes untouched.
enum JSONFormatter {
    static func reformat(_ b: [UInt8], unit: String, minify: Bool) -> String? {
        var out: [UInt8] = []
        out.reserveCapacity(b.count + b.count / 4)
        let u = Array(unit.utf8)
        var level = 0
        var i = 0
        let n = b.count
        func newline() { out.append(10); for _ in 0..<level { out.append(contentsOf: u) } }
        func isWS(_ c: UInt8) -> Bool { c == 32 || c == 9 || c == 10 || c == 13 }
        func nextSignificant(_ from: Int) -> Int {
            var j = from
            while j < n, isWS(b[j]) { j += 1 }
            return j
        }
        func isDelimiter(_ c: UInt8) -> Bool { isWS(c) || c == 44 || c == 58 || c == 123 || c == 125 || c == 91 || c == 93 || c == 34 || c == 39 || c == 47 }
        var hadContent = false
        while i < n {
            let c = b[i]
            if isWS(c) { i += 1; continue }
            switch c {
            case 123, 91:
                let j = nextSignificant(i + 1)
                if j < n, b[j] == (c == 123 ? 125 : 93) {
                    out.append(c); out.append(b[j]); i = j + 1
                } else {
                    out.append(c); level += 1; i += 1
                    if !minify { newline() }
                }
            case 125, 93:
                level -= 1
                if level < 0 { return nil }
                if !minify { newline() }
                out.append(c); i += 1
            case 44:
                let j = nextSignificant(i + 1)
                i += 1
                if j < n, b[j] == 125 || b[j] == 93 { continue }          // drop a trailing comma
                out.append(44)
                if !minify { newline() }
            case 58:
                out.append(58); if !minify { out.append(32) }; i += 1
            case 34, 39:
                let q = c
                out.append(c); i += 1
                while i < n {
                    let d = b[i]
                    out.append(d); i += 1
                    if d == 92, i < n { out.append(b[i]); i += 1; continue }
                    if d == q { break }
                }
            case 47:
                if minify { return nil }
                guard i + 1 < n else { return nil }
                if !out.isEmpty, out.last != 10, out.last != 32 { out.append(32) }
                if b[i + 1] == 47 {
                    while i < n, b[i] != 10 { out.append(b[i]); i += 1 }
                    newline()
                } else {
                    while i + 1 < n, !(b[i] == 42 && b[i + 1] == 47) || i < 2 { out.append(b[i]); i += 1 }
                    if i + 1 < n { out.append(42); out.append(47); i += 2 }
                    out.append(32)
                }
            default:
                while i < n, !isDelimiter(b[i]) { out.append(b[i]); i += 1 }
            }
            hadContent = true
        }
        guard level == 0, hadContent else { return nil }
        while out.last == 32 || out.last == 10 { out.removeLast() }
        out.append(10)
        return String(decoding: out, as: UTF8.self)
    }
}

// MARK: - Native diagnostics store

/// Syntax problems found natively (JSON / YAML). Merged into the Problems panel by LanguageServers.problems(forRoot:).
enum NativeProblems {
    private static var byPath: [String: FileProblems] = [:]

    static func set(url: URL, _ list: [FileProblems.Diagnostic]) {
        let path = url.standardizedFileURL.path
        let had = byPath[path] != nil
        if list.isEmpty { byPath[path] = nil } else { byPath[path] = FileProblems(url: url.standardizedFileURL, diagnostics: list) }
        if had || !list.isEmpty { NotificationCenter.default.post(name: LanguageServers.problemsDidChange, object: nil) }
    }

    static func problems(forRoot root: URL, excluding seen: Set<String>) -> [FileProblems] {
        let rp = root.standardizedFileURL.path
        return byPath.values.filter { ($0.url.path.hasPrefix(rp + "/") || $0.url.path == rp) && !seen.contains($0.url.path) }
    }

    static func diagnostics(forPath path: String) -> [FileProblems.Diagnostic] { byPath[path]?.diagnostics ?? [] }
}

/// Wavy underlines for native diagnostics (a transparent overlay like the language-server one; the highlighter is untouched).
final class NativeSquiggleOverlay: NSView {
    weak var textView: NSTextView?
    var items: [(range: NSRange, severity: Int, message: String)] = [] { didSet { needsDisplay = true; toolTip = nil } }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer, !items.isEmpty else { return }
        let origin = tv.textContainerOrigin
        let length = tv.textStorage?.length ?? 0
        for d in items {
            let cr = NSIntersectionRange(d.range, NSRange(location: 0, length: length))
            guard cr.length > 0 else { continue }
            let gr = lm.glyphRange(forCharacterRange: cr, actualCharacterRange: nil)
            LSPSession.color(forSeverity: d.severity).setStroke()
            lm.enumerateEnclosingRects(forGlyphRange: gr, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: tc) { rect, _ in
                let r = rect.offsetBy(dx: origin.x, dy: origin.y)
                guard r.intersects(dirtyRect.insetBy(dx: -4, dy: -4)) else { return }
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

// MARK: - Controller

final class ViewerController: NSObject {
    weak var tab: EditorTab?
    let kind: ViewerKind
    private(set) var mode: ViewerMode = .source
    private(set) var markdown: MarkdownPreviewView?
    private(set) var svg: SVGPreviewView?
    private(set) var tree: StructureTreeView?
    private(set) var overlay: NativeSquiggleOverlay?
    private var observers: [NSObjectProtocol] = []
    private var visibleObservers: [NSObjectProtocol] = []
    private var work: DispatchWorkItem?
    private var generation = 0
    private var pending = false
    private var syncScheduled = false
    private var previewSyncScheduled = false
    /// Which pane the user last scrolled; a queued sync only runs if its source pane is still the driver.
    private enum Driver { case editor, preview }
    private var driver = Driver.editor
    private var editorSuppress = 0
    /// Scroll syncs actually applied since the last reset (tests: loop / coalescing checks).
    private(set) var syncStats = (toPreview: 0, toEditor: 0)
    func resetSyncStats() { syncStats = (0, 0) }
    private var editorY: CGFloat = 0
    private var revealWork: DispatchWorkItem?
    private var lineStarts: [Int]?
    private var diagItems: [(range: NSRange, severity: Int, message: String)] = []
    /// Last measurements (tests, reports).
    private(set) var lastParseMs = 0.0
    private(set) var lastRenderMs = 0.0
    private(set) var refreshCount = 0
    private(set) var lastTape: StructTape?

    var pane: EditorPane? { tab?.view as? EditorPane }

    init(tab: EditorTab, kind: ViewerKind) { self.tab = tab; self.kind = kind }

    func attach() {
        guard let tab, let pane else { return }
        installControl(in: pane)
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSText.didChangeNotification, object: tab.textView, queue: .main) { [weak self] _ in
            self?.lineStarts = nil
            self?.textEdited()
        })
        if kind.isStructured, let storage = tab.textView.textStorage {
            observers.append(nc.addObserver(forName: NSTextStorage.didProcessEditingNotification, object: storage, queue: .main) { [weak self] n in
                guard let s = n.object as? NSTextStorage, s.editedMask.contains(.editedCharacters) else { return }
                self?.shiftDiagnostics(edited: s.editedRange, delta: s.changeInLength)
            })
        }
        observers.append(nc.addObserver(forName: Theme.didChange, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.mode != .source else { return }
            self.markdown?.restyle(); self.svg?.restyle()
            self.refreshNow()
        })
        setMode(kind.mode, persist: false)
        if kind.isStructured { scheduleDiagnostics(initial: true) }
    }

    func detach() {
        work?.cancel(); revealWork?.cancel()
        removeVisibleObservers()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        overlay?.removeFromSuperview(); overlay = nil
        if let tab { NativeProblems.set(url: tab.url, []) }
        pane?.viewerState.control?.removeFromSuperview()
        teardownSide()
    }

    // MARK: Mode and layout

    private func installControl(in pane: EditorPane) {
        let c = NSSegmentedControl(labels: ["Source", "Split", kind.previewTitle], trackingMode: .selectOne, target: self, action: #selector(segmentChanged(_:)))
        c.controlSize = .small
        c.segmentStyle = .rounded
        c.font = .systemFont(ofSize: 11)
        c.translatesAutoresizingMaskIntoConstraints = false
        c.toolTip = "View mode (\u{2303}\u{2325}\u{2318}V cycles)"
        pane.addSubview(c)
        NSLayoutConstraint.activate([
            c.trailingAnchor.constraint(equalTo: pane.trailingAnchor, constant: -10),
            c.topAnchor.constraint(equalTo: pane.breadcrumbBar.topAnchor, constant: 2),
        ])
        pane.viewerState.control = c
    }

    @objc private func segmentChanged(_ sender: NSSegmentedControl) { setMode(ViewerMode(segment: sender.selectedSegment)) }

    func setMode(_ new: ViewerMode, persist: Bool = true) {
        guard let pane else { return }
        let old = mode
        mode = new
        pane.viewerState.control?.selectedSegment = new.segment
        if persist { kind.mode = new }
        if new == .source {
            removeVisibleObservers()
            pane.contentTrailing.isActive = false
            teardownSide()
            pane.contentView.isHidden = false
            pane.contentTrailing.isActive = true
            if old != .source { pane.window?.makeFirstResponder(tab?.textView) }
        } else {
            ensureSide(in: pane)
            let split = new == .split
            pane.viewerState.halfWidth?.isActive = split
            pane.viewerState.fullWidth?.isActive = !split
            pane.contentView.isHidden = !split
            if old == .source { addVisibleObservers() }
            refreshNow()
            if !split { pane.window?.makeFirstResponder(sideFocusView) }
        }
        pane.needsLayout = true
        pane.layoutSubtreeIfNeeded()
        (NSApp.delegate as? AppDelegate)?.active?.refreshStatus()
        if new == .split, kind == .markdown { syncScroll() }
    }

    private var sideFocusView: NSView? { markdown?.textView ?? svg?.textViewForFocus ?? tree?.outline }

    private func ensureSide(in pane: EditorPane) {
        guard pane.viewerState.side == nil else { return }
        let side: NSView
        if kind == .markdown {
            let m = MarkdownPreviewView()
            m.fileURL = tab?.url
            m.onOpenFile = { url in (NSApp.delegate as? AppDelegate)?.active?.open(url) }
            if let tab { PlanSupport.attach(m, tab: tab) }
            markdown = m; side = m
        } else if kind == .svg {
            let v = SVGPreviewView()
            svg = v; side = v
        } else {
            let t = StructureTreeView()
            t.onJump = { [weak self] range in self?.jump(to: range) }
            tree = t; side = t
        }
        side.translatesAutoresizingMaskIntoConstraints = false
        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = Theme.palette.divider.cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false
        pane.addSubview(side, positioned: .below, relativeTo: pane.viewerState.control)
        pane.addSubview(divider, positioned: .below, relativeTo: pane.viewerState.control)
        let half = side.widthAnchor.constraint(equalTo: pane.widthAnchor, multiplier: 0.5)
        let full = side.widthAnchor.constraint(equalTo: pane.widthAnchor)
        let link = pane.contentView.trailingAnchor.constraint(equalTo: side.leadingAnchor)
        pane.contentTrailing.isActive = false
        NSLayoutConstraint.activate([
            side.topAnchor.constraint(equalTo: pane.contentView.topAnchor), side.bottomAnchor.constraint(equalTo: pane.bottomAnchor),
            side.trailingAnchor.constraint(equalTo: pane.trailingAnchor), link,
            divider.topAnchor.constraint(equalTo: side.topAnchor), divider.bottomAnchor.constraint(equalTo: side.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: side.leadingAnchor), divider.widthAnchor.constraint(equalToConstant: 1),
        ])
        pane.viewerState.side = side; pane.viewerState.divider = divider
        pane.viewerState.halfWidth = half; pane.viewerState.fullWidth = full; pane.viewerState.contentToSide = link
    }

    private func teardownSide() {
        guard let pane else { return }
        let st = pane.viewerState
        st.halfWidth?.isActive = false; st.fullWidth?.isActive = false; st.contentToSide?.isActive = false
        st.side?.removeFromSuperview(); st.divider?.removeFromSuperview()
        pane.viewerState.side = nil; pane.viewerState.divider = nil
        pane.viewerState.halfWidth = nil; pane.viewerState.fullWidth = nil; pane.viewerState.contentToSide = nil
        markdown = nil; svg = nil; tree = nil; lastTape = nil
    }

    private func addVisibleObservers() {
        guard let tab, visibleObservers.isEmpty else { return }
        let nc = NotificationCenter.default
        if kind == .markdown {
            tab.scrollView.contentView.postsBoundsChangedNotifications = true
            editorY = tab.scrollView.contentView.bounds.minY
            // queue: nil delivers synchronously, so `editorSuppress` reliably marks programmatic scrolls.
            visibleObservers.append(nc.addObserver(forName: NSView.boundsDidChangeNotification, object: tab.scrollView.contentView, queue: nil) { [weak self] _ in
                guard let self, self.editorSuppress == 0, let y = self.tab?.scrollView.contentView.bounds.minY, abs(y - self.editorY) >= 0.5 else { return }
                self.editorY = y
                self.driver = .editor
                self.scheduleSync()
            })
            markdown?.onUserScroll = { [weak self] in self?.driver = .preview; self?.scheduleSyncFromPreview() }
        } else if kind.isStructured {
            visibleObservers.append(nc.addObserver(forName: NSTextView.didChangeSelectionNotification, object: tab.textView, queue: .main) { [weak self] _ in
                self?.scheduleReveal()
            })
        }
    }

    private func removeVisibleObservers() {
        markdown?.onUserScroll = nil
        visibleObservers.forEach(NotificationCenter.default.removeObserver)
        visibleObservers = []
    }

    // MARK: Refresh (debounced, only while visible)

    private func textEdited() {
        if mode == .source { if kind.isStructured { scheduleDiagnostics(initial: false) }; return }
        work?.cancel()
        let delay = PowerState.shared.scaled(kind == .markdown || kind == .svg ? 0.2 : 0.3)
        let w = DispatchWorkItem { [weak self] in self?.refreshNow() }
        work = w
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: w)
    }

    func flushPending() { if pending { pending = false; if mode == .source { if kind.isStructured { scheduleDiagnostics(initial: false) } } else { refreshNow() } } }

    /// Parses / renders now (also the test entry point). Hidden windows defer until they are visible again (no polling).
    func refreshNow() {
        guard let tab, mode != .source else { return }
        if PowerState.windowHidden(pane) { pending = true; return }
        generation += 1
        let gen = generation
        let text = tab.textView.string
        refreshCount += 1
        switch kind {
        case .markdown:
            guard text.utf16.count <= 1_500_000 else { markdown?.showMessage("Preview is disabled for Markdown files over 1.5 MB."); return }
            let t0 = CFAbsoluteTimeGetCurrent()
            let syncParse = text.utf16.count < 30_000 || AppEnv.headless
            let finish: ([MDBlock]) -> Void = { [weak self] blocks in
                guard let self, gen == self.generation, let m = self.markdown else { return }
                self.lastParseMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                m.show(blocks: blocks)
                self.lastRenderMs = m.lastRenderMs
                self.syncScroll()
            }
            if syncParse { finish(MarkdownParser.parse(text)) }
            else { DispatchQueue.global(qos: .userInitiated).async { let b = MarkdownParser.parse(text); DispatchQueue.main.async { finish(b) } } }
        case .svg:
            svg?.show(svg: text)
        case .json:
            let lenient = JSONFlavor.isLenient(tab.url)
            let t0 = CFAbsoluteTimeGetCurrent()
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let tape = JSONTapeParser.parse(Array(text.utf8), lenient: lenient)
                let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                DispatchQueue.main.async { self?.finishStructured(tape, gen: gen, ms: ms, text: text) }
            }
        case .yaml:
            guard text.utf8.count <= YAMLTapeBuilder.maxBytes else { tree?.show(tape: nil, message: "YAML files over 3 MB are not shown as a tree"); return }
            guard let language = Languages.grammar(forKey: "yaml")?.language else { return }
            let t0 = CFAbsoluteTimeGetCurrent()
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let tape = YAMLTapeBuilder.parse(text, language: language)
                let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                DispatchQueue.main.async { self?.finishStructured(tape, gen: gen, ms: ms, text: text) }
            }
        }
    }

    private func finishStructured(_ tape: StructTape, gen: Int, ms: Double, text: String) {
        guard gen == generation else { return }
        lastParseMs = ms
        lastTape = tape
        let t0 = CFAbsoluteTimeGetCurrent()
        let err = tape.issues.first { $0.severity == 1 }
        tree?.show(tape: tape, message: err.map { "\($0.message) at \(LineCol(text as NSString, $0.offset).line):\(LineCol(text as NSString, $0.offset).col)" })
        lastRenderMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        publish(tape.issues, text: text)
        if mode == .split { scheduleReveal() }
    }

    // MARK: Scroll sync / reveal / jump

    private func scheduleSync() {
        guard !syncScheduled else { return }
        syncScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.syncScheduled = false
            if self.driver == .editor { self.syncStats.toPreview += 1; self.syncScroll() }
        }
    }

    private func scheduleSyncFromPreview() {
        guard !previewSyncScheduled, mode == .split else { return }
        previewSyncScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.previewSyncScheduled = false
            if self.driver == .preview { self.syncStats.toEditor += 1; self.syncEditorFromPreview() }
        }
    }

    /// Preview -> editor: the inverse of `syncScroll`.
    func syncEditorFromPreview() {
        guard kind == .markdown, mode == .split, let m = markdown, !PowerState.windowHidden(pane) else { return }
        scrollEditor(toLine: m.sourceLine(atScrollY: m.scrollY))
    }

    /// Scrolls the editor so (fractional) source line `line` is at its top; exact inverse of `editorTopLine`.
    func scrollEditor(toLine line: Double) {
        guard let tv = tab?.textView, let clip = tab?.scrollView.contentView, let lm = tv.layoutManager else { return }
        _ = self.line(of: 0)
        let starts = lineStarts ?? [0]
        let li = min(max(0, Int(line.rounded(.down))), starts.count - 1)
        let frac = min(0.99, max(0, line - Double(li)))
        var y: CGFloat = 0
        let len = (tv.string as NSString).length
        if (li > 0 || frac > 0), len > 0, lm.numberOfGlyphs > 0 {
            // Lay out up to the target so the Y is exact (estimates would shift later and bounce the sync back); bounded for huge files.
            let at = min(starts[li], len - 1)
            lm.ensureLayout(forCharacterRange: NSRange(location: at > 400_000 ? at : 0, length: at > 400_000 ? 1 : at + 1))
            let glyph = lm.glyphIndexForCharacter(at: at)
            let rect = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            y = tv.textContainerOrigin.y + rect.minY + CGFloat(frac) * rect.height
        }
        y = min(max(0, y), max(0, tv.frame.height - clip.bounds.height))
        guard abs(y - clip.bounds.minY) >= 0.5 else { return }
        editorSuppress += 1
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: y))
        tab?.scrollView.reflectScrolledClipView(clip)
        editorSuppress -= 1
        editorY = clip.bounds.minY
    }

    /// Editor's top visible source line (fractional), via a cached line-start table.
    func editorTopLine() -> Double {
        guard let tv = tab?.textView, let clip = tab?.scrollView.contentView, let lm = tv.layoutManager, let tc = tv.textContainer else { return 0 }
        let y = clip.bounds.minY
        if y <= 1 { return 0 }
        let p = NSPoint(x: tv.textContainerInset.width + 1, y: y - tv.textContainerOrigin.y + 1)
        var frac = 0.0
        let glyph = lm.glyphIndex(for: p, in: tc, fractionOfDistanceThroughGlyph: nil)
        let rect = lm.lineFragmentRect(forGlyphAt: min(glyph, max(0, lm.numberOfGlyphs - 1)), effectiveRange: nil)
        if rect.height > 0 { frac = min(0.99, max(0, Double((y - tv.textContainerOrigin.y - rect.minY) / rect.height))) }
        let idx = lm.characterIndexForGlyph(at: min(glyph, max(0, lm.numberOfGlyphs - 1)))
        return Double(line(of: idx)) + frac
    }

    private func line(of offset: Int) -> Int {
        if lineStarts == nil {
            let ns = (tab?.textView.string ?? "") as NSString
            var starts = [0]
            var i = 0
            let n = ns.length
            while i < n {
                let r = ns.range(of: "\n", range: NSRange(location: i, length: n - i))
                if r.location == NSNotFound { break }
                starts.append(r.location + 1); i = r.location + 1
            }
            lineStarts = starts
        }
        let s = lineStarts!
        var lo = 0, hi = s.count - 1
        while lo < hi { let mid = (lo + hi + 1) / 2; if s[mid] <= offset { lo = mid } else { hi = mid - 1 } }
        return lo
    }

    func syncScroll() {
        guard kind == .markdown, mode == .split, let m = markdown, !PowerState.windowHidden(pane) else { return }
        m.scroll(toSourceLine: editorTopLine())
    }

    private func scheduleReveal() {
        guard mode == .split, tree != nil else { return }
        revealWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self, let tv = self.tab?.textView else { return }
            self.tree?.reveal(offset: tv.selectedRange().location)
        }
        revealWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: w)
    }

    private func jump(to range: NSRange) {
        guard let tv = tab?.textView else { return }
        let len = (tv.string as NSString).length
        guard range.location <= len else { return }
        let r = NSRange(location: range.location, length: min(range.length, len - range.location))
        tv.setSelectedRange(NSRange(location: r.location, length: 0))
        tv.scrollRangeToVisible(NSRange(location: r.location, length: 0))
        if mode == .split, let t = tab, r.length > 0, r.length < 4000 { t.flash([r], duration: 0.9) }
    }

    // MARK: Diagnostics (JSON / YAML)

    private func scheduleDiagnostics(initial: Bool) {
        guard let tab, kind.isStructured else { return }
        work?.cancel()
        let delay = initial ? 0.3 : PowerState.shared.scaled(0.8)
        let w = DispatchWorkItem { [weak self] in self?.runDiagnostics() }
        work = w
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: w)
        _ = tab
    }

    private func runDiagnostics() {
        guard let tab, mode == .source else { return }
        if PowerState.windowHidden(pane) { pending = true; return }
        let text = tab.textView.string
        guard text.utf8.count <= 1_500_000 else { publish([], text: text); return }
        generation += 1
        let gen = generation
        let lenient = JSONFlavor.isLenient(tab.url)
        let kind = self.kind
        let language = kind == .yaml ? Languages.grammar(forKey: "yaml")?.language : nil
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let issues: [StructIssue]
            if kind == .json { issues = JSONTapeParser.parse(Array(text.utf8), lenient: lenient, maxNodes: 20_000).issues }
            else if let language { issues = YAMLTapeBuilder.parse(text, language: language, maxNodes: 20_000).issues }
            else { issues = [] }
            DispatchQueue.main.async {
                guard let self, gen == self.generation else { return }
                self.publish(issues, text: text)
            }
        }
    }

    /// Issues -> Problems panel entries + squiggles. Offsets refer to `text` (the buffer when it was parsed).
    func publish(_ issues: [StructIssue], text: String) {
        guard let tab else { return }
        // The JSON language server (when installed and running) already reports syntax errors.
        let issues = kind == .json && !ViewerSystem.alwaysNativeJSON && LanguageServers.session(for: tab).map({ !$0.instances.isEmpty }) == true ? [] : issues
        let ns = text as NSString
        let current = (tab.textView.string as NSString).length
        guard ns.length == current else { return }          // buffer changed while parsing: a newer pass will follow
        var list: [FileProblems.Diagnostic] = []
        var items: [(NSRange, Int, String)] = []
        for i in issues.prefix(50) {
            let a = LineCol(ns, i.offset), b = LineCol(ns, i.offset + max(1, i.length))
            list.append(FileProblems.Diagnostic(severity: i.severity, message: i.message, line: a.line, column: a.col, endLine: b.line, endColumn: b.col,
                                                source: kind == .json ? "JSON" : "YAML", code: nil))
            items.append((NSRange(location: i.offset, length: max(1, min(i.length, ns.length - i.offset))), i.severity, i.message))
        }
        NativeProblems.set(url: tab.url, list)
        diagItems = items
        showSquiggles()
    }

    private func showSquiggles() {
        guard let tv = tab?.textView else { return }
        if diagItems.isEmpty { overlay?.items = []; return }
        if overlay == nil || overlay?.superview !== tv {
            let o = NativeSquiggleOverlay(frame: tv.bounds)
            o.autoresizingMask = [.width, .height]
            o.textView = tv
            tv.addSubview(o)
            overlay = o
        }
        overlay?.items = diagItems
    }

    var squiggleCount: Int { overlay?.items.count ?? 0 }

    private func shiftDiagnostics(edited: NSRange, delta: Int) {
        guard !diagItems.isEmpty else { return }
        let oldEnd = edited.location + edited.length - delta
        diagItems = diagItems.map { d in
            var d = d
            let s = d.range.location, e = NSMaxRange(d.range)
            if e <= edited.location { return d }
            if s >= oldEnd { d.range.location = s + delta; return d }
            let newEnd = max(s, e + delta)
            d.range = NSRange(location: min(s, edited.location), length: max(0, newEnd - min(s, edited.location)))
            return d
        }
        overlay?.items = diagItems
    }
}
