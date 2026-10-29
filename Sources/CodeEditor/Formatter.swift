import AppKit

/// Real code formatting: project tool (Pint / PHP-CS-Fixer / Prettier) first, then the language server, else unavailable.
/// Public API is main-thread; completions fire on the main thread exactly once.
enum Formatter {
    enum Result {
        case formatted(tool: String)
        case unchanged(tool: String)
        case unavailable(reason: String)
        case failed(tool: String, message: String)
    }

    struct Diagnostics {
        var tool: String
        var file: String
        var duration: TimeInterval
        var exitStatus: Int32
        var stderr: String
        var outcome: String
        var date = Date()
    }

    // MARK: Settings and state

    static let formatOnSaveKey = "formatOnSave"
    static var formatOnSave: Bool {
        get { UserDefaults.standard.bool(forKey: formatOnSaveKey) }
        set { UserDefaults.standard.set(newValue, forKey: formatOnSaveKey) }
    }
    /// Hard timeout for one tool run.
    static var timeout: TimeInterval = 10
    static let maxBytes = 1_000_000
    /// Last run (for a future "Format log").
    private(set) static var diagnostics: Diagnostics?
    private(set) static var history: [Diagnostics] = []

    // LSP seams (replaced by stubs in verification).
    static var lspSupportsFormatting: (URL) -> Bool = { LanguageServers.supportsFormatting(for: $0) }
    static var lspFormatDocument: (EditorTab, @escaping (Bool) -> Void) -> Bool = { LanguageServers.formatDocument(in: $0, completion: $1) }
    static var lspFormatSelection: (EditorTab, @escaping (Bool) -> Void) -> Bool = { LanguageServers.formatSelection(in: $0, completion: $1) }
    static func lspName(for url: URL) -> String {
        LanguageServerManager.shared.session(forURL: url)?.instance(supporting: "documentFormattingProvider")?.config.name ?? "LSP"
    }

    private final class Job {
        let proc = FormatProcess()
        var finished = false
        var completion: ((Result) -> Void)?
        let tool: String
        init(tool: String, completion: @escaping (Result) -> Void) { self.tool = tool; self.completion = completion }
        func finish(_ r: Result) {
            guard !finished else { return }
            finished = true
            let c = completion
            completion = nil
            c?(r)
        }
    }
    private static var jobs: [ObjectIdentifier: Job] = [:]
    private static var started = false
    private static var saving = Set<ObjectIdentifier>()

    // MARK: Queries

    static func canFormat(_ tab: EditorTab) -> Bool {
        FormatTools.detect(for: tab.url) != nil || lspSupportsFormatting(tab.url)
    }

    static func statusText(for tab: EditorTab) -> String {
        if let tool = FormatTools.detect(for: tab.url) {
            if tool.kind == .prettier, let v = FormatTools.prettierVersion(tool) {
                let parts = v.split(separator: ".")
                return "Prettier " + parts.prefix(2).joined(separator: ".")
            }
            return tool.name
        }
        if lspSupportsFormatting(tab.url) { return lspName(for: tab.url) }
        return "none"
    }

    // MARK: Entry points

    static func format(_ tab: EditorTab, completion: @escaping (Result) -> Void) {
        run(tab, range: nil, completion: completion)
    }

    static func formatSelection(_ tab: EditorTab, completion: @escaping (Result) -> Void) {
        let sel = tab.textView.selectedRange()
        guard sel.length > 0 else { completion(.unavailable(reason: "No selection")); return }
        run(tab, range: sel, completion: completion)
    }

    /// Registers the format-on-save hook (call once from AppDelegate).
    static func start() {
        guard !started else { return }
        started = true
        // The login-shell PATH lookup can take seconds with a heavy .zshrc; do it once in the background so the first format/save is instant.
        if !AppEnv.headless { DispatchQueue.global(qos: .utility).async { _ = FormatTools.resolveLoginPATH() } }
        EditorEvents.onWillSave { tab, proceed in
            guard formatOnSave, !tab.textView.hasMarkedText(), !tab.isReadOnly, !tab.isLargeFile,
                  tab.textView.string.utf8.count <= maxBytes,
                  FormatTools.detect(for: tab.url) != nil, !saving.contains(ObjectIdentifier(tab)) else { proceed(); return }
            let id = ObjectIdentifier(tab)
            saving.insert(id)
            var done = false
            func finish() {
                guard !done else { return }
                done = true
                saving.remove(id)
                proceed()
            }
            // Time-box: a formatter problem must never block a save.
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout + 2) {
                if !done { jobs[id]?.proc.cancel(); jobs[id]?.finish(.unchanged(tool: "timeout")); finish() }
            }
            run(tab, range: nil, allowLSP: false) { _ in finish() }
        }
    }

    // MARK: Core

    private static func run(_ tab: EditorTab, range: NSRange?, allowLSP: Bool = true, completion: @escaping (Result) -> Void) {
        let tv = tab.textView
        let id = ObjectIdentifier(tab)
        if tv.hasMarkedText() { completion(.unavailable(reason: "Text composition in progress")); return }
        if tab.isReadOnly { completion(.unavailable(reason: "File is read-only")); return }
        let snapshot = tv.string
        if snapshot.utf8.count > maxBytes { completion(.unavailable(reason: "File is larger than 1 MB")); return }

        var detected = FormatTools.detect(for: tab.url)
        if detected?.kind == .nativeBlade { detected?.indent = IndentSettings.resolve(for: tab.url, text: snapshot) }
        let tool = detected
        if let tool, range == nil || tool.kind == .prettier || tool.kind == .nativeBlade {
            jobs[id]?.proc.cancel()
            jobs[id]?.finish(.unchanged(tool: tool.name))
            let job = Job(tool: tool.name, completion: completion)
            jobs[id] = job
            let url = tab.url
            let started = Date()
            let timeout = self.timeout
            DispatchQueue.global(qos: .userInitiated).async {
                let lf = snapshot.replacingOccurrences(of: "\r\n", with: "\n")
                let r = execute(tool, url: url, text: lf, range: range.map { normalizedRange($0, in: snapshot) }, timeout: timeout, proc: job.proc)
                DispatchQueue.main.async {
                    if jobs[id] === job { jobs[id] = nil }
                    guard !job.finished else { return }
                    let dur = Date().timeIntervalSince(started)
                    func log(_ outcome: String) {
                        record(Diagnostics(tool: tool.name, file: url.path, duration: dur, exitStatus: r.status, stderr: r.stderr, outcome: outcome))
                    }
                    switch r.kind {
                    case .failed(let msg):
                        log("failed: " + msg)
                        job.finish(.failed(tool: tool.name, message: msg))
                    case .text(let out):
                        guard tv.string == snapshot else { log("discarded (buffer changed)"); job.finish(.unchanged(tool: tool.name)); return }
                        if let problem = unsafe(old: snapshot, new: out) {
                            log("failed: " + problem)
                            job.finish(.failed(tool: tool.name, message: problem)); return
                        }
                        let applied = apply(out, to: tab, snapshot: snapshot)
                        log(applied ? "formatted" : "unchanged")
                        job.finish(applied ? .formatted(tool: tool.name) : .unchanged(tool: tool.name))
                    }
                }
            }
            return
        }
        guard allowLSP else { completion(.unavailable(reason: "No project formatter")); return }
        // LSP fallback
        guard lspSupportsFormatting(tab.url) else {
            completion(.unavailable(reason: tool == nil ? "No formatter found (Pint, PHP-CS-Fixer, Prettier) and no language server formats this file"
                                                     : "\(tool!.name) cannot format a selection"))
            return
        }
        let name = lspName(for: tab.url)
        var once = false
        let done: (Bool) -> Void = { ok in
            DispatchQueue.main.async {
                guard !once else { return }
                once = true
                if !ok { completion(.failed(tool: name, message: "The language server could not format this file")); return }
                completion(tv.string == snapshot ? .unchanged(tool: name) : .formatted(tool: name))
            }
        }
        let dispatched = range == nil ? lspFormatDocument(tab, done) : lspFormatSelection(tab, done)
        if !dispatched { once = true; completion(.unavailable(reason: range == nil ? "The language server does not support formatting" : "The language server does not support range formatting")) }
    }

    private static func record(_ d: Diagnostics) {
        diagnostics = d
        history.append(d)
        if history.count > 50 { history.removeFirst(history.count - 50) }
    }

    // MARK: Execution (background)

    private struct Executed {
        enum Kind { case text(String), failed(String) }
        var kind: Kind
        var status: Int32 = 0
        var stderr = ""
    }

    private static func firstLine(_ data: Data) -> String {
        let s = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    }

    private static func execute(_ tool: FormatTool, url: URL, text: String, range: NSRange?, timeout: TimeInterval, proc: FormatProcess) -> Executed {
        let env = FormatTools.environment()
        func interpret(_ o: FormatProcess.Output, _ name: String) -> Executed? {
            let err = String(decoding: o.stderr, as: UTF8.self)
            if let e = o.launchError { return Executed(kind: .failed("could not launch \(name): \(e)"), stderr: err) }
            if o.cancelled { return Executed(kind: .failed("cancelled"), status: o.status, stderr: err) }
            if o.timedOut { return Executed(kind: .failed("\(name) timed out after \(Int(timeout)) s"), status: o.status, stderr: err) }
            if o.truncated { return Executed(kind: .failed("\(name) produced too much output"), status: o.status, stderr: err) }
            if o.status != 0 {
                var msg = firstLine(o.stderr)
                if msg.isEmpty { msg = firstLine(o.stdout) }
                return Executed(kind: .failed(msg.isEmpty ? "\(name) exited with status \(o.status)" : msg), status: o.status, stderr: err)
            }
            return nil
        }

        switch tool.kind {
        case .nativeBlade:
            let indent = tool.indent ?? IndentSettings.preferred
            let lines = range.map { BladeFormatter.lineRange(for: $0, in: text) }
            return Executed(kind: .text(BladeFormatter.format(text, useTabs: indent.useTabs, size: indent.size, lines: lines)))

        case .prettier:
            var args = ["--stdin-filepath", url.path]
            if let range { args += ["--range-start", String(range.location), "--range-end", String(NSMaxRange(range))] }
            if let plugin = tool.plugin { args += ["--plugin=\(plugin)"] }
            let o = proc.runSync(exe: tool.exe, args: args, cwd: tool.cwd, env: env, stdin: Data(text.utf8), timeout: timeout)
            if let bad = interpret(o, "Prettier") { return bad }
            return Executed(kind: .text(String(decoding: o.stdout, as: UTF8.self)), status: o.status, stderr: String(decoding: o.stderr, as: UTF8.self))

        case .pint, .phpCSFixer:
            // Neither tool reads stdin: format a temp copy that mirrors the relative path, then read it back.
            let fm = FileManager.default
            let dir = fm.temporaryDirectory.appendingPathComponent("ce-format-\(UUID().uuidString)")
            defer { try? fm.removeItem(at: dir) }
            let rootPath = tool.cwd.standardizedFileURL.path + "/"
            let rel = url.standardizedFileURL.path.hasPrefix(rootPath) ? String(url.standardizedFileURL.path.dropFirst(rootPath.count)) : url.lastPathComponent
            let temp = dir.appendingPathComponent(rel)
            do {
                try fm.createDirectory(at: temp.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(text.utf8).write(to: temp)
            } catch { return Executed(kind: .failed("could not create temp file: \(error.localizedDescription)")) }

            var exe = tool.exe
            var args: [String] = []
            if tool.viaPHP {
                guard let php = FormatTools.which("php") else { return Executed(kind: .failed("php not found on PATH")) }
                exe = php
                args = [tool.exe.path]
            }
            if tool.kind == .pint {
                args += [temp.path]
                if let cfg = tool.config { args += ["--config=\(cfg.path)"] }
            } else {
                args += ["fix", temp.path, "--using-cache=no", "--quiet", "--no-interaction"]
                args += [tool.config.map { "--config=\($0.path)" } ?? "--rules=@PSR12"]
            }
            let o = proc.runSync(exe: exe, args: args, cwd: tool.cwd, env: env, stdin: nil, timeout: timeout)
            if let bad = interpret(o, tool.name) { return bad }
            guard let data = try? Data(contentsOf: temp) else { return Executed(kind: .failed("\(tool.name) removed the file"), status: o.status) }
            return Executed(kind: .text(String(decoding: data, as: UTF8.self)), status: o.status, stderr: String(decoding: o.stderr, as: UTF8.self))
        }
    }

    /// Prettier counts UTF-16 offsets in the LF-only text it receives.
    private static func normalizedRange(_ r: NSRange, in s: String) -> NSRange {
        guard s.contains("\r\n") else { return r }
        let ns = s as NSString
        func lf(_ upTo: Int) -> Int {
            let prefix = ns.substring(to: min(upTo, ns.length))
            return (prefix.replacingOccurrences(of: "\r\n", with: "\n") as NSString).length
        }
        let a = lf(r.location), b = lf(NSMaxRange(r))
        return NSRange(location: a, length: b - a)
    }

    // MARK: Safety guard

    /// Returns a reason when the tool output must not be applied.
    static func unsafe(old: String, new: String) -> String? {
        if new.isEmpty && !old.isEmpty { return "formatter returned empty output" }
        let o = old.utf8.count, n = new.utf8.count
        if o > 0, Double(n) < Double(o) * 0.1 {
            let strip: (String) -> [UInt8] = { $0.utf8.filter { $0 > 32 } }
            if strip(old) != strip(new) { return "formatter output shrank by more than 90%" }
        }
        return nil
    }

    // MARK: Applying

    struct Edit { var range: NSRange; var text: String }

    /// Minimal line diff (then common prefix/suffix trimmed per hunk) in UTF-16 offsets, ascending.
    static func minimalEdits(old: String, new: String) -> [Edit] {
        let a = DiffEngine.splitLines(old), b = DiffEngine.splitLines(new)
        let ids = DiffEngine.intern([a, b])
        let ops = DiffEngine.edit(ids[0], ids[1], maxD: 2000)
        var edits: [Edit] = []
        var i = 0, j = 0, off = 0, k = 0
        while k < ops.count {
            if ops[k] == .equal { off += a[i].utf16.count; i += 1; j += 1; k += 1; continue }
            var dels = 0, ins = 0
            while k < ops.count, ops[k] != .equal {
                if ops[k] == .delete { dels += 1 } else { ins += 1 }
                k += 1
            }
            // Equal-sized hunks are split per line so unrelated lines (and the caret) are left alone.
            let groups: [(Range<Int>, Range<Int>)] = dels == ins
                ? (0..<dels).map { ((i + $0)..<(i + $0 + 1), (j + $0)..<(j + $0 + 1)) }
                : [(i..<(i + dels), j..<(j + ins))]
            for (ar, br) in groups {
                let oldText = a[ar].joined(), newText = b[br].joined()
                let oc = Array(oldText), nc = Array(newText)
                var pre = 0
                while pre < oc.count, pre < nc.count, oc[pre] == nc[pre] { pre += 1 }
                var suf = 0
                while suf < oc.count - pre, suf < nc.count - pre, oc[oc.count - 1 - suf] == nc[nc.count - 1 - suf] { suf += 1 }
                let prefixLen = String(oc[0..<pre]).utf16.count
                let oldMid = String(oc[pre..<(oc.count - suf)]), newMid = String(nc[pre..<(nc.count - suf)])
                if !(oldMid.isEmpty && newMid.isEmpty) {
                    edits.append(Edit(range: NSRange(location: off + prefixLen, length: oldMid.utf16.count), text: newMid))
                }
                off += oldText.utf16.count
            }
            i += dels; j += ins
        }
        return edits
    }

    private static func map(_ pos: Int, through edits: [Edit]) -> Int {
        var delta = 0
        for e in edits {
            if pos <= e.range.location { break }
            if pos >= NSMaxRange(e.range) { delta += (e.text as NSString).length - e.range.length; continue }
            return e.range.location + delta + min(pos - e.range.location, (e.text as NSString).length)
        }
        return pos + delta
    }

    /// Applies `newText` as minimal edits in one undo group; keeps selection and scroll. Returns whether anything changed.
    @discardableResult
    static func apply(_ newText: String, to tab: EditorTab, snapshot: String) -> Bool {
        let tv = tab.textView
        var out = newText.replacingOccurrences(of: "\r\n", with: "\n")
        if snapshot.contains("\r\n") { out = out.replacingOccurrences(of: "\n", with: "\r\n") }
        let edits = minimalEdits(old: snapshot, new: out)
        guard !edits.isEmpty else { return false }
        let sel = tv.selectedRange()
        let start = map(sel.location, through: edits), end = map(NSMaxRange(sel), through: edits)
        let clip = tab.scrollView.contentView
        let origin = clip.bounds.origin

        tv.breakUndoCoalescing()
        tv.undoManager?.beginUndoGrouping()
        for e in edits.reversed() {
            guard tv.shouldChangeText(in: e.range, replacementString: e.text) else { continue }
            tv.textStorage?.replaceCharacters(in: e.range, with: NSAttributedString(string: e.text, attributes: tv.typingAttributes))
            tv.didChangeText()
        }
        tv.undoManager?.setActionName("Format")
        tv.undoManager?.endUndoGrouping()

        let len = (tv.string as NSString).length
        let s = min(start, len)
        tv.setSelectedRange(NSRange(location: s, length: max(0, min(end, len) - s)))
        clip.scroll(to: origin)
        tab.scrollView.reflectScrolledClipView(clip)
        return true
    }
}
