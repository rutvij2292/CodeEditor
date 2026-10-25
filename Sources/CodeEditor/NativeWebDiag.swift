import AppKit

/// Native stylesheet diagnostics, limited to problems that are certain: structure errors of plain `.css` files (unclosed block,
/// stray `}`, unterminated comment or string). Everything semantic (unknown properties, unknown classes, ...) is left to the external
/// server because a wrong squiggle is worse than none. SCSS / Less are not checked (interpolation, `//` comments).
enum NWCssDiag {
    static func handles(_ url: URL) -> Bool {
        NativeWeb.enabled && ["css", "pcss", "postcss"].contains(url.pathExtension.lowercased())
    }

    static func analyze(_ b: NWBuf) -> [StructIssue] {
        var issues: [StructIssue] = []
        var stack: [Int] = []
        var i = 0
        let n = b.count
        while i < n, issues.count < 40 {
            let c = b[i]
            if c == 47, i + 1 < n, b[i + 1] == 42 {                            // /* ... */
                var j = i + 2
                while j + 1 < n, !(b[j] == 42 && b[j + 1] == 47) { j += 1 }
                if j + 1 >= n { issues.append(StructIssue(severity: 1, message: "Unterminated comment: `*/` expected", offset: i, length: 2)); break }
                i = j + 2; continue
            }
            if c == 34 || c == 39 {                                             // strings end at the closing quote; a raw newline ends them as an error
                var j = i + 1
                var closed = false
                while j < n {
                    let d = b[j]
                    if d == 92 { j += 2; continue }
                    if d == c { closed = true; break }
                    if d == 10 { break }
                    j += 1
                }
                if !closed { issues.append(StructIssue(severity: 1, message: "Unterminated string", offset: i, length: 1)) }
                i = closed ? j + 1 : max(j, i + 1); continue
            }
            if c == 40 {
                // unquoted url(...): its content is opaque
                var k = i
                while k > 0, NWChar.isIdent(b[k - 1]) { k -= 1 }
                if b.str(k, i).lowercased() == "url" {
                    var j = i + 1
                    while j < n, NWChar.isSpace(b[j]) { j += 1 }
                    if j < n, b[j] != 34, b[j] != 39 {
                        while j < n, b[j] != 41, b[j] != 10 { j += 1 }
                        i = j; continue
                    }
                }
            } else if c == 123 { stack.append(i) }
            else if c == 125 {
                if stack.popLast() == nil { issues.append(StructIssue(severity: 1, message: "Unexpected `}`: no block is open", offset: i, length: 1)) }
            }
            i += 1
        }
        if issues.isEmpty { for o in stack.suffix(10) { issues.append(StructIssue(severity: 1, message: "Unclosed block: `}` expected", offset: o, length: 1)) } }
        return issues
    }
}

/// Per-tab driver for `NWCssDiag`: one debounced pass after edits settle (a DispatchWorkItem, never polling), only while the window is
/// visible, only when no CSS language server is running (it reports the same errors).
final class NativeWebDiagController: NSObject {
    private(set) static var controllers: [ObjectIdentifier: NativeWebDiagController] = [:]
    private static var started = false

    static func start() {
        guard !started else { return }
        started = true
        EditorEvents.onOpen { tab in
            guard NWCssDiag.handles(tab.url), tab.view is EditorPane else { return }
            let c = NativeWebDiagController(tab: tab)
            controllers[ObjectIdentifier(tab)] = c
            c.attach()
        }
        EditorEvents.onClose { tab in controllers.removeValue(forKey: ObjectIdentifier(tab))?.detach() }
    }

    weak var tab: EditorTab?
    private var observer: NSObjectProtocol?
    private var work: DispatchWorkItem?
    private var generation = 0
    private var overlay: NativeSquiggleOverlay?
    private(set) var published = 0

    init(tab: EditorTab) { self.tab = tab }

    func attach() {
        guard let tab else { return }
        observer = NotificationCenter.default.addObserver(forName: NSText.didChangeNotification, object: tab.textView, queue: .main) { [weak self] _ in
            self?.overlay?.items = []
            self?.schedule(initial: false)
        }
        schedule(initial: true)
    }

    func detach() {
        work?.cancel()
        if let o = observer { NotificationCenter.default.removeObserver(o) }
        overlay?.removeFromSuperview(); overlay = nil
        if let tab { NativeProblems.set(url: tab.url, []) }
    }

    func schedule(initial: Bool) {
        work?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.run() }
        work = w
        DispatchQueue.main.asyncAfter(deadline: .now() + (initial ? 0.4 : PowerState.shared.scaled(0.9)), execute: w)
    }

    private func run() {
        guard let tab else { return }
        if PowerState.windowHidden(tab.view) { return }                    // re-armed by the next edit / reopening
        let text = tab.textView.string
        guard text.utf8.count <= 1_500_000, NativeWeb.enabled else { publish([], text: text); return }
        generation += 1
        let gen = generation
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let issues = NWCssDiag.analyze(NWBuf(NSString(string: text)))
            DispatchQueue.main.async {
                guard let self, gen == self.generation else { return }
                self.publish(issues, text: text)
            }
        }
    }

    private func publish(_ issues: [StructIssue], text: String) {
        guard let tab else { return }
        let ns = text as NSString
        guard ns.length == (tab.textView.string as NSString).length else { return }       // buffer changed meanwhile: a newer pass follows
        // an active CSS language server reports structure errors itself
        let serverRuns = LanguageServers.session(for: tab).map { !$0.instances.isEmpty } == true
        let shown = serverRuns ? [] : issues
        var list: [FileProblems.Diagnostic] = []
        var items: [(NSRange, Int, String)] = []
        for i in shown.prefix(40) {
            let a = LineCol(ns, i.offset), e = LineCol(ns, i.offset + max(1, i.length))
            list.append(FileProblems.Diagnostic(severity: i.severity, message: i.message, line: a.line, column: a.col, endLine: e.line, endColumn: e.col, source: "CSS", code: nil))
            items.append((NSRange(location: i.offset, length: max(1, min(i.length, ns.length - i.offset))), i.severity, i.message))
        }
        NativeProblems.set(url: tab.url, list)
        published = list.count
        let tv = tab.textView
        if items.isEmpty { overlay?.items = []; return }
        if overlay == nil || overlay?.superview !== tv {
            let o = NativeSquiggleOverlay(frame: tv.bounds)
            o.autoresizingMask = [.width, .height]
            o.textView = tv
            tv.addSubview(o)
            overlay = o
        }
        overlay?.items = items
    }
}
