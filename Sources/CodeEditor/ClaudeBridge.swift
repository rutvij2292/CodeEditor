import AppKit

/// Per-project-window IDE integration for the Claude Code CLI (protocol notes: docs/claude-code-bridge.md).
///
/// The bridge runs a loopback WebSocket MCP server, publishes `~/.claude/ide/<port>.lock` so `claude` can find it,
/// pushes editor state (selection_changed, at_mentioned) and answers the CLI's calls (getDiagnostics, openDiff,
/// close_tab, closeAllDiffTabs). It never runs code and never touches paths outside the project folder.
final class ClaudeBridge {
    // MARK: Configuration

    /// Where lock files go. Tests point this at a temp directory; the CLI scans `~/.claude/ide`.
    static var lockDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/ide", isDirectory: true)
    /// Tests start bridges in headless runs; real windows do not (they would advertise themselves to the user's real `claude`).
    static var allowHeadlessStart = false
    static let ideName = Brand.name
    static let protocolVersions = ["2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25"]
    static let maxDiffBytes = 10 * 1024 * 1024
    static let maxSelectionChars = 200_000

    enum Status: Equatable { case off, waiting, connected(Int) }

    struct PendingDiff {
        let tabName: String
        let url: URL
        let requestID: Any
        let clientID: Int
        let proposed: String
        let original: String
    }

    enum DiffOutcome { case accept(String), reject, closed }

    // MARK: State

    let root: URL
    private(set) weak var window: ProjectWindow?
    private(set) var server: ClaudeBridgeServer?
    private(set) var lockURL: URL?
    private var clients: [Int: Bool] = [:]            // connection id -> completed initialize
    private(set) var pendingDiffs: [String: PendingDiff] = [:]
    private var diffUI: [String: ClaudeDiffWindowController] = [:]
    private var lastSelection: [String: Any]?
    private var selectionWork: DispatchWorkItem?
    private var prefsObserver: NSObjectProtocol?

    /// Replaceable for tests; defaults to the Problems store (open files only, like the Problems panel).
    var diagnosticsProvider: () -> [FileProblems]
    /// Shows the review UI for a pending diff. Default: a window with Accept / Reject (skipped when headless).
    var presentDiff: (PendingDiff) -> Void = { _ in }
    var onStatusChange: ((Status) -> Void)?
    /// Called with the user-visible notice for things the bridge did on Claude's behalf.
    var onNotice: ((String) -> Void)?
    /// When non-nil, the bridge asks this instead of showing a window (tests).
    var diffDecider: ((PendingDiff) -> DiffOutcome?)?
    /// Wire-level log of every message (tests / live verification only; message bodies are never logged otherwise).
    var trace: ((String) -> Void)?

    var isRunning: Bool { server != nil }
    var port: UInt16 { server?.port ?? 0 }
    var authToken: String { server?.authToken ?? "" }
    var connectedClients: Int { clients.values.filter { $0 }.count }
    var status: Status { !isRunning ? .off : (connectedClients > 0 ? .connected(connectedClients) : .waiting) }

    /// Environment for the docked terminal so `claude` finds and uses this window's server.
    var terminalEnvironment: [String: String] {
        guard isRunning else { return [:] }
        return ["CLAUDE_CODE_SSE_PORT": String(port), "CLAUDE_CODE_AUTO_CONNECT_IDE": "true"]
    }

    init(root: URL, window: ProjectWindow? = nil) {
        self.root = root.standardizedFileURL
        self.window = window
        self.diagnosticsProvider = { [root] in LanguageServers.problems(forRoot: root) }
        self.presentDiff = { [weak self] d in self?.presentDiffWindow(d) }
    }

    deinit {
        stop()
        if let prefsObserver { NotificationCenter.default.removeObserver(prefsObserver) }
    }

    // MARK: Lifecycle

    /// Starts (or stops) the server according to Settings; keeps following later changes of the preference.
    func followPreference() {
        if prefsObserver == nil {
            prefsObserver = NotificationCenter.default.addObserver(forName: Prefs.didChange, object: nil, queue: .main) { [weak self] n in
                guard (n.userInfo?["key"] as? String) == "claudeBridgeEnabled" else { return }
                self?.applyPreference()
            }
        }
        applyPreference()
    }

    func applyPreference() {
        if Prefs.claudeBridgeEnabled, !AppEnv.headless || Self.allowHeadlessStart { _ = start() } else { stop() }
        window?.terminalPanel?.extraEnvironment = terminalEnvironment
    }

    @discardableResult
    func start() -> Bool {
        if isRunning { return true }
        let s = ClaudeBridgeServer()
        s.onConnect = { [weak self] id in self?.clients[id] = false; self?.statusChanged() }
        s.onDisconnect = { [weak self] id in self?.clientGone(id) }
        s.onMessage = { [weak self] id, text in self?.handle(text, from: id) }
        guard s.start() else { return false }
        server = s
        Self.removeStaleLocks()
        guard writeLock(port: s.port, token: s.authToken) else { s.stop(); server = nil; return false }
        statusChanged()
        return true
    }

    func stop() {
        for name in Array(pendingDiffs.keys) { finishDiff(name, .closed, reply: false) }
        selectionWork?.cancel()
        let was = server != nil
        server?.stop()
        server = nil
        clients = [:]
        removeLock()
        if was { statusChanged() }
    }

    /// Releases the preference observer too (window closing).
    func shutdown() {
        stop()
        if let prefsObserver { NotificationCenter.default.removeObserver(prefsObserver) }
        prefsObserver = nil
    }

    private func statusChanged() { onStatusChange?(status) }

    private func clientGone(_ id: Int) {
        clients[id] = nil
        for (name, d) in pendingDiffs where d.clientID == id { finishDiff(name, .closed, reply: false) }
        statusChanged()
    }

    // MARK: Lock file

    private static let lockPathsLock = NSLock()
    private static var lockPaths: [String] = []
    private static var atexitInstalled = false

    private func writeLock(port: UInt16, token: String) -> Bool {
        let dir = Self.lockDirectory
        let fm = FileManager.default
        do { try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) } catch { return false }
        var folders = [root.path]
        // realpath(3): Foundation's resolvingSymlinksInPath() strips /private, so /var/... would not resolve to /private/var/...
        if let rp = realpath(root.path, nil) {
            let real = String(cString: rp)
            free(rp)
            if real != root.path { folders.append(real) }
        }
        let body: [String: Any] = ["pid": Int(getpid()), "workspaceFolders": folders, "ideName": Self.ideName,
                                   "transport": "ws", "runningInWindows": false, "authToken": token]
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else { return false }
        let final = dir.appendingPathComponent("\(port).lock")
        let tmp = dir.appendingPathComponent(".\(port).tmp")
        guard fm.createFile(atPath: tmp.path, contents: data, attributes: [.posixPermissions: 0o600]) else { return false }
        chmod(tmp.path, 0o600)
        _ = try? fm.removeItem(at: final)
        do { try fm.moveItem(at: tmp, to: final) } catch { try? fm.removeItem(at: tmp); return false }
        lockURL = final
        Self.lockPathsLock.lock()
        Self.lockPaths.append(final.path)
        if !Self.atexitInstalled { Self.atexitInstalled = true; atexit { ClaudeBridge.removeAllLocksAtExit() } }
        Self.lockPathsLock.unlock()
        return true
    }

    private func removeLock() {
        guard let lockURL else { return }
        try? FileManager.default.removeItem(at: lockURL)
        Self.lockPathsLock.lock()
        Self.lockPaths.removeAll { $0 == lockURL.path }
        Self.lockPathsLock.unlock()
        self.lockURL = nil
    }

    /// Quit path (also registered with atexit): leaves no lock file behind.
    static func removeAllLocksAtExit() {
        lockPathsLock.lock()
        let paths = lockPaths
        lockPaths = []
        lockPathsLock.unlock()
        for p in paths { unlink(p) }
    }

    /// Deletes lock files written by this app whose process is gone (crash / force quit).
    static func removeStaleLocks() {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: lockDirectory.path) else { return }
        for name in names where name.hasSuffix(".lock") {
            let url = lockDirectory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  obj["ideName"] as? String == ideName, let pid = obj["pid"] as? Int else { continue }
            if kill(pid_t(pid), 0) != 0, errno == ESRCH { try? fm.removeItem(at: url) }
        }
    }

    // MARK: JSON-RPC

    private func json(_ object: [String: Any]) -> String? {
        guard let d = try? JSONSerialization.data(withJSONObject: object), let s = String(data: d, encoding: .utf8) else { return nil }
        return s
    }

    private func reply(_ id: Any, result: [String: Any], to client: Int) {
        if let s = json(["jsonrpc": "2.0", "id": id, "result": result]) { trace?("-> \(client): \(s.prefix(300))"); server?.send(s, to: client) }
    }

    private func replyError(_ id: Any, code: Int, _ message: String, to client: Int) {
        if let s = json(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]) { trace?("-> \(client): \(s.prefix(300))"); server?.send(s, to: client) }
    }

    private func notify(_ method: String, _ params: [String: Any], to ids: [Int]? = nil) {
        guard let s = json(["jsonrpc": "2.0", "method": method, "params": params]) else { return }
        trace?("-> *: \(s.prefix(300))")
        server?.broadcast(s, to: ids ?? clients.filter { $0.value }.map(\.key))
    }

    static func textResult(_ texts: String...) -> [String: Any] { ["content": texts.map { ["type": "text", "text": $0] }] }
    static func errorResult(_ text: String) -> [String: Any] { ["content": [["type": "text", "text": text]], "isError": true] }

    func handle(_ text: String, from client: Int) {
        trace?("<- \(client): \(text.prefix(400))")
        guard let data = text.data(using: .utf8), let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        guard let method = msg["method"] as? String else { return }       // responses to us are never expected
        let params = msg["params"] as? [String: Any] ?? [:]
        guard let id = msg["id"] else { notification(method, params, from: client); return }
        switch method {
        case "initialize":
            let asked = params["protocolVersion"] as? String ?? ""
            reply(id, result: ["protocolVersion": Self.protocolVersions.contains(asked) ? asked : Self.protocolVersions[2],
                               "capabilities": ["tools": ["listChanged": false]],
                               "serverInfo": ["name": Self.ideName, "version": "1.0"]], to: client)
        case "ping": reply(id, result: [:], to: client)
        case "tools/list": reply(id, result: ["tools": Self.toolDefinitions], to: client)
        case "tools/call":
            guard let name = params["name"] as? String else { replyError(id, code: -32602, "Missing tool name", to: client); return }
            callTool(name, params["arguments"] as? [String: Any] ?? [:], id: id, client: client)
        default: replyError(id, code: -32601, "Method not found", to: client)
        }
    }

    private func notification(_ method: String, _ params: [String: Any], from client: Int) {
        switch method {
        case "notifications/initialized", "ide_connected":
            guard clients[client] != nil else { return }
            let first = clients[client] == false
            clients[client] = true
            if first { statusChanged(); sendSelection(force: true, to: [client]) }
        default: break      // unknown notifications (log_event, notifications/message, ...) are ignored
        }
    }

    // MARK: Tools

    static let toolDefinitions: [[String: Any]] = [
        ["name": "getDiagnostics",
         "description": "Get language diagnostics (errors, warnings) for open files in the editor. Optionally pass a file:// URI.",
         "inputSchema": ["type": "object", "properties": ["uri": ["type": "string", "description": "file:// URI; omit for all open files"]]]],
        ["name": "openDiff",
         "description": "Open a diff of a file against proposed contents and wait for the user to accept or reject it.",
         "inputSchema": ["type": "object",
                         "properties": ["old_file_path": ["type": "string"], "new_file_path": ["type": "string"],
                                        "new_file_contents": ["type": "string"], "tab_name": ["type": "string"]],
                         "required": ["old_file_path", "new_file_path", "new_file_contents", "tab_name"]]],
        ["name": "close_tab",
         "description": "Close a diff tab opened by openDiff.",
         "inputSchema": ["type": "object", "properties": ["tab_name": ["type": "string"]], "required": ["tab_name"]]],
        ["name": "closeAllDiffTabs",
         "description": "Close every diff tab opened by openDiff.",
         "inputSchema": ["type": "object", "properties": [String: Any]()]],
    ]

    private func callTool(_ name: String, _ args: [String: Any], id: Any, client: Int) {
        guard clients[client] != nil else { return }
        switch name {
        case "getDiagnostics": reply(id, result: getDiagnostics(uri: args["uri"] as? String), to: client)
        case "openDiff": openDiff(args, id: id, client: client)
        case "close_tab":
            guard let tab = args["tab_name"] as? String else { reply(id, result: Self.errorResult("tab_name required"), to: client); return }
            finishDiff(tab, .closed, reply: true)
            reply(id, result: Self.textResult("TAB_CLOSED"), to: client)
        case "closeAllDiffTabs":
            let n = pendingDiffs.count
            for tab in Array(pendingDiffs.keys) { finishDiff(tab, .closed, reply: true) }
            reply(id, result: Self.textResult("CLOSED_\(n)_DIFF_TABS"), to: client)
        default: replyError(id, code: -32601, "Unknown tool: \(name)", to: client)    // includes executeCode: never offered
        }
    }

    /// True when `url` (after resolving symlinks) is inside the project folder.
    func isInsideProject(_ url: URL) -> Bool {
        let rootReal = root.resolvingSymlinksInPath().path
        var p = url.standardizedFileURL
        // Resolve through the deepest existing ancestor so brand-new files are checked too.
        var tail: [String] = []
        while !FileManager.default.fileExists(atPath: p.path), p.path != "/" { tail.insert(p.lastPathComponent, at: 0); p = p.deletingLastPathComponent() }
        var real = p.resolvingSymlinksInPath()
        for t in tail { real.appendPathComponent(t) }
        return real.path == rootReal || real.path.hasPrefix(rootReal + "/")
    }

    // MARK: getDiagnostics

    private static func severityName(_ s: Int) -> String {
        switch s { case 1: return "Error"; case 2: return "Warning"; case 3: return "Info"; default: return "Hint" }
    }

    func getDiagnostics(uri: String?) -> [String: Any] {
        var files = diagnosticsProvider().filter { isInsideProject($0.url) }
        if let uri, !uri.isEmpty {
            guard let u = URL(string: uri), u.isFileURL else { return Self.errorResult("Invalid uri") }
            guard isInsideProject(u) else { return Self.textResult("[]") }
            let want = u.standardizedFileURL.path
            files = files.filter { $0.url.standardizedFileURL.path == want }
            if files.isEmpty { files = [FileProblems(url: u, diagnostics: [])] }
        }
        let out: [[String: Any]] = files.map { f in
            ["uri": f.url.absoluteString,
             "diagnostics": f.diagnostics.map { d -> [String: Any] in
                 var o: [String: Any] = ["message": d.message, "severity": Self.severityName(d.severity),
                                         "range": ["start": ["line": max(0, d.line - 1), "character": max(0, d.column - 1)],
                                                   "end": ["line": max(0, d.endLine - 1), "character": max(0, d.endColumn - 1)]]]
                 if let s = d.source, !s.isEmpty { o["source"] = s }
                 if let c = d.code, !c.isEmpty { o["code"] = c }
                 return o
             }]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: out), let text = String(data: data, encoding: .utf8) else { return Self.textResult("[]") }
        return Self.textResult(text)
    }

    // MARK: openDiff

    private func openDiff(_ args: [String: Any], id: Any, client: Int) {
        guard let newPath = args["new_file_path"] as? String, let contents = args["new_file_contents"] as? String,
              let tab = args["tab_name"] as? String, !tab.isEmpty else {
            reply(id, result: Self.errorResult("openDiff needs new_file_path, new_file_contents and tab_name"), to: client); return
        }
        let url = URL(fileURLWithPath: newPath).standardizedFileURL
        guard newPath.hasPrefix("/"), isInsideProject(url) else {
            reply(id, result: Self.errorResult("Path is outside the project folder"), to: client); return
        }
        guard contents.utf8.count <= Self.maxDiffBytes else { reply(id, result: Self.errorResult("Proposed contents too large"), to: client); return }
        if pendingDiffs[tab] != nil { finishDiff(tab, .closed, reply: true) }
        let original = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let diff = PendingDiff(tabName: tab, url: url, requestID: id, clientID: client, proposed: contents, original: original)
        pendingDiffs[tab] = diff
        // Jump to the first change only when the file was not open yet; an open buffer keeps the user's caret and scroll.
        let alreadyOpen = window?.editors[url.standardizedFileURL.path] != nil
        revealWithoutStealingFocus(url, line: alreadyOpen ? nil : Self.firstChangedLine(old: original, new: contents))
        onNotice?("Claude proposes changes to \(url.lastPathComponent) \u{2013} review the diff")
        if let decider = diffDecider {
            if let outcome = decider(diff) { finishDiff(tab, outcome, reply: true) }
        } else if !AppEnv.headless {
            presentDiff(diff)
        }
    }

    /// 1-based first line where the two texts differ.
    static func firstChangedLine(old: String, new: String) -> Int {
        let a = old.components(separatedBy: "\n"), b = new.components(separatedBy: "\n")
        for i in 0..<min(a.count, b.count) where a[i] != b[i] { return i + 1 }
        return min(a.count, b.count) + 1
    }

    /// Settles the diff: on accept the file is written (the CLI expects the IDE to save), then the pending
    /// `openDiff` call is answered with the protocol's FILE_SAVED / DIFF_REJECTED / TAB_CLOSED results.
    func finishDiff(_ tab: String, _ outcome: DiffOutcome, reply sendReply: Bool) {
        guard let d = pendingDiffs.removeValue(forKey: tab) else { return }
        if let ui = diffUI.removeValue(forKey: tab) { ui.detach(); ui.close() }
        var result: [String: Any]
        switch outcome {
        case .accept(let text):
            do {
                try Self.writeAccepted(text, to: d.url)
                window?.editors[d.url.standardizedFileURL.path]?.reloadIfChangedOnDisk()
                result = Self.textResult("FILE_SAVED", text)
            } catch {
                result = Self.errorResult("Could not save \(d.url.lastPathComponent): \(error.localizedDescription)")
            }
        case .reject: result = Self.textResult("DIFF_REJECTED")
        case .closed: result = Self.textResult("TAB_CLOSED")
        }
        if sendReply { reply(d.requestID, result: result, to: d.clientID) }
    }

    static func writeAccepted(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileIO.write(Data(text.utf8), to: url)
    }

    private func presentDiffWindow(_ d: PendingDiff) {
        let ui = ClaudeDiffWindowController(diff: d) { [weak self] outcome in self?.finishDiff(d.tabName, outcome, reply: true) }
        diffUI[d.tabName] = ui
        ui.show()
    }

    /// Opens a file Claude refers to; keeps keyboard focus where it was when that was the terminal.
    func revealWithoutStealingFocus(_ url: URL, line: Int?) {
        guard let w = window else { return }
        let previous = w.window.firstResponder
        w.open(url, line: line)
        if let previous, !(previous is CodeTextView), previous !== w.window.firstResponder { w.window.makeFirstResponder(previous) }
    }

    // MARK: Editor -> Claude

    /// Call whenever the active editor / caret / selection may have changed (cheap; debounced).
    func editorStateChanged() {
        guard isRunning, connectedClients > 0 else { return }
        selectionWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.sendSelection(force: false, to: nil) }
        selectionWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    /// The `selection_changed` params for the active editor (0-based line / UTF-16 character, as LSP), or nil without an editor.
    func selectionPayload() -> [String: Any]? {
        guard let editor = window?.current else { return nil }
        let tv = editor.textView
        let ns = tv.string as NSString
        let sel = tv.selectedRange()
        func position(_ offset: Int) -> [String: Any] {
            let off = min(max(0, offset), ns.length)
            let lr = ns.lineRange(for: NSRange(location: off, length: 0))
            var line = 0, i = 0
            while i < lr.location { if ns.character(at: i) == 10 { line += 1 }; i += 1 }
            return ["line": line, "character": off - lr.location]
        }
        var text = sel.length > 0 ? ns.substring(with: sel) : ""
        if text.count > Self.maxSelectionChars { text = String(text.prefix(Self.maxSelectionChars)) }
        return ["selection": ["start": position(sel.location), "end": position(sel.location + sel.length)],
                "text": text, "filePath": editor.url.standardizedFileURL.path]
    }

    func sendSelection(force: Bool, to ids: [Int]?) {
        guard let payload = selectionPayload() else { return }
        if !force, let last = lastSelection, NSDictionary(dictionary: last).isEqual(to: payload) { return }
        lastSelection = payload
        notify("selection_changed", payload, to: ids)
    }

    /// `at_mentioned` for the CLI prompt (1-based inclusive lines; the protocol is 0-based). False when no CLI is connected.
    @discardableResult
    func sendMention(url: URL, startLine: Int?, endLine: Int?) -> Bool {
        guard connectedClients > 0 else { return false }
        var params: [String: Any] = ["filePath": url.standardizedFileURL.path]
        if let s = startLine { params["lineStart"] = max(0, s - 1); params["lineEnd"] = max(0, (endLine ?? s) - 1) }
        notify("at_mentioned", params)
        return true
    }

    /// `@path`, `@path#L12` or `@path#L12-15 ` exactly as the CLI's own mention syntax (verified in the CLI source).
    static func mentionText(path: String, start: Int?, end: Int?) -> String {
        var p = path
        if let s = start { p += (end ?? s) > s ? "#L\(s)-\(end ?? s)" : "#L\(s)" }
        return TerminalBridge.mention(p) + " "
    }
}

// MARK: - ProjectWindow integration

extension ProjectWindow {
    /// Creates the bridge for this window (started per Settings) and wires it to the status bar and terminal.
    func installClaudeBridge() {
        guard let root, claudeBridge == nil else { return }
        let bridge = ClaudeBridge(root: root, window: self)
        bridge.onStatusChange = { [weak self] status in self?.statusBar.setClaude(status) }
        bridge.onNotice = { [weak self] text in self?.statusBar.flash(text, seconds: 8) }
        claudeBridge = bridge
        bridge.followPreference()
    }

    /// Sends the current selection (or the file when nothing is selected) to Claude as an @-mention. With a connected CLI the
    /// mention is inserted by the CLI itself (at_mentioned); otherwise it is pasted into the terminal prompt.
    @discardableResult
    func sendMentionToClaude() -> String? {
        guard let root, let editor = current else { statusBar.flash("No file to send to Claude"); return nil }
        let tv = editor.textView
        let sel = tv.selectedRange()
        var start: Int?, end: Int?
        if sel.length > 0 { let r = TerminalBridge.lineRange(in: tv.string as NSString, selection: sel); start = r.start; end = r.end }
        if claudeBridge?.sendMention(url: editor.url, startLine: start, endLine: end) == true {
            statusBar.flash("Sent to Claude: \(editor.url.lastPathComponent)\(start.map { ":\($0)" } ?? "")")
            return "at_mentioned"
        }
        let text = ClaudeBridge.mentionText(path: TerminalBridge.relativePath(editor.url, root: root), start: start, end: end)
        sendToTerminal(text)
        return text
    }
}
