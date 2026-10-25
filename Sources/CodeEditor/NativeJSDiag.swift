import AppKit
import SwiftTreeSitter

/// Native JS / TS diagnostics, only rules that cannot be wrong:
///  - a relative import / export-from / require / import() whose target does not exist (no file, extension probe, directory index);
///  - an import binding that is never referenced (hint, dimmed), skipped for .vue (template usage) and for JSX files' `React`.
/// Syntax errors and type errors are deliberately not reported (tree-sitter is not the TypeScript parser).
enum NativeJSDiag {
    static let enabledKey = "js.diag"
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }
    static let maxBytes = 800_000
    static let maxResults = 100

    static func analyze(env: NJSEnv) -> [NPDiag] {
        let doc = env.doc
        guard doc.text.length <= maxBytes else { return [] }
        let ns = doc.text
        let isTS = doc.lang != .js
        let cfg = env.proj.modules.config(for: env.path)
        let judgeModules = cfg?.hasRootDirs != true
        var out: [NPDiag] = []
        var used = Set<String>()
        var comments = ""
        var hasJSX = false
        var stack: [Node] = [doc.root]
        var importNodes: [Node] = []
        while let n = stack.popLast() {
            let k = n.kind
            switch k {
            case "identifier", "type_identifier", "shorthand_property_identifier": used.insert(n.text(ns))
            case "comment": comments += n.text(ns) + "\n"
            case "jsx_element", "jsx_self_closing_element", "jsx_fragment": hasJSX = true
            case "import_statement":
                importNodes.append(n)
                if judgeModules, let src = n.field("source") { checkSpecifier(src, env: env, isTS: isTS, into: &out) }
                continue                                   // bindings of an import are not usages
            case "export_statement":
                if judgeModules, let src = n.field("source") { checkSpecifier(src, env: env, isTS: isTS, into: &out) }
            case "call_expression":
                if judgeModules, let f = n.field("function"), let a = n.field("arguments"), let str = a.kids.first, str.kind == "string",
                   f.kind == "import" || (f.kind == "identifier" && f.text(ns) == "require") { checkSpecifier(str, env: env, isTS: isTS, into: &out) }
            default: break
            }
            if n.namedChildCount > 0 { stack.append(contentsOf: n.kids) }
        }
        // unused import bindings
        if !doc.isVue, !env.path.hasSuffix(".d.ts") {
            for s in doc.summary.order where s.kind == .import && s.impName != "=" {
                guard importNodes.contains(where: { s.loc >= $0.start && s.loc < $0.end }) else { continue }
                if used.contains(s.name) { continue }
                if hasJSX, ["React", "h", "Fragment", "Preact"].contains(s.name) { continue }
                if comments.range(of: s.name) != nil { continue }
                out.append(NPDiag(range: NSRange(location: s.loc, length: s.len), severity: 4, message: "'\(s.name)' is declared but its value is never read.",
                                  code: "unused-import", group: .imports))
            }
        }
        return NativePHPDiag.finish(Array(out.prefix(maxResults * 2)))
    }

    private static func checkSpecifier(_ str: Node, env: NJSEnv, isTS: Bool, into out: inout [NPDiag]) {
        guard str.kind == "string", let frag = str.kids.first(where: { $0.kind == "string_fragment" }) else { return }
        let spec = frag.text(env.doc.text)
        guard spec.hasPrefix("./") || spec.hasPrefix("../") || spec == "." || spec == ".." else { return }
        if spec.contains("?") || spec.contains("!") || spec.contains("*") || spec.contains("${") || spec.contains("\\") { return }
        guard env.proj.modules.resolve(spec, from: env.path) == nil else { return }
        out.append(NPDiag(range: frag.range, severity: isTS ? 1 : 2, message: "Cannot find module '\(spec)' or its corresponding type declarations.",
                          code: "module-not-found", group: .imports))
    }

    static func analyze(url: URL, text: NSString) -> [NPDiag] {
        guard enabled, NativeJS.handles(url), text.length > 0 else { return [] }
        let proj = NJSProject.shared(root: NativeJS.root(for: url))
        return proj.queue.sync { () -> [NPDiag] in
            guard let env = NativeJS.env(url: url, text: text, root: proj.root) else { return [] }
            return analyze(env: env)
        }
    }

    static func diagnostics(_ list: [NPDiag], in ns: NSString) -> [FileProblems.Diagnostic] {
        let table = NPLineStarts(ns)
        return list.map { d in
            let a = table.position(of: d.range.location), b = table.position(of: NSMaxRange(d.range))
            return FileProblems.Diagnostic(severity: d.severity, message: d.message, line: a.line, column: a.col, endLine: b.line, endColumn: b.col, source: "JS", code: d.code)
        }
    }
}

/// Per-tab driver: one debounced analysis after edits settle (never polling), only for visible JS / TS tabs.
final class NativeJSDiagController: NSObject {
    private(set) static var controllers: [ObjectIdentifier: NativeJSDiagController] = [:]
    private static var started = false

    static func start() {
        guard !started else { return }
        started = true
        EditorEvents.onOpen { tab in
            guard NativeJS.handles(tab.url), tab.view is EditorPane else { return }
            let c = NativeJSDiagController(tab: tab)
            controllers[ObjectIdentifier(tab)] = c
            c.attach()
        }
        EditorEvents.onClose { tab in controllers.removeValue(forKey: ObjectIdentifier(tab))?.detach() }
        NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main) { note in
            guard let w = note.object as? NSWindow, w.occlusionState.contains(.visible) else { return }
            for c in controllers.values where c.tab?.textView.window === w { c.flushPending() }
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
    private var applying = false
    private(set) var overlay: NPDiagOverlay?
    private(set) var all: [NPDiag] = []
    private(set) var visible: [NPDiag] = [] { didSet { hoverList = visible.map { LSPDiagnostic(range: $0.range, severity: $0.severity, message: $0.message, source: "JS", code: $0.code) } } }
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

    func schedule(initial: Bool) {
        work?.cancel()
        let delay = initial ? 0.6 : PowerState.shared.scaled(1.0)
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
        guard NativeJSDiag.enabled, !tab.isLargeFile else { apply([], text: text); return }
        generation += 1
        let gen = generation
        let url = tab.url
        let snapshot = NSString(string: text)
        let proj = NJSProject.shared(root: NativeJS.root(for: url))
        proj.queue.async { [weak self] in
            guard let env = NativeJS.env(url: url, text: snapshot, root: proj.root) else { return }
            let list = NativeJSDiag.analyze(env: env)
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
        applying = true
        NativeProblems.set(url: tab.url, NativeJSDiag.diagnostics(list, in: text as NSString))
        applying = false
        refilter()
    }

    private func refilter() {
        guard let tab else { return }
        guard !all.isEmpty else { visible = []; overlay?.items = []; return }
        var shown = all
        let lsp = NativePHPDiagController.lspDiagnostics(for: tab)
        if !lsp.isEmpty {
            let conv = NativeJSDiag.diagnostics(all, in: tab.textView.string as NSString)
            let keep = Set(NativePHPDiag.dedupe(conv, against: lsp).map { "\($0.line):\($0.column):\($0.code ?? "")" })
            shown = zip(all, conv).filter { keep.contains("\($0.1.line):\($0.1.column):\($0.1.code ?? "")") }.map { $0.0 }
        }
        visible = shown
        let tv = tab.textView
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
}
