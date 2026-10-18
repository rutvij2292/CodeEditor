import AppKit
import Network

/// In-process WebSocket client for the bridge tests (acts like `claude`: subprotocol "mcp" + the auth header).
final class ClaudeTestClient {
    let connection: NWConnection
    private let queue = DispatchQueue(label: "kode.claude-test-client")
    private let lock = NSLock()
    private var _ready = false, _failed = false
    private var _messages: [[String: Any]] = []
    var ready: Bool { lock.lock(); defer { lock.unlock() }; return _ready }
    var failed: Bool { lock.lock(); defer { lock.unlock() }; return _failed }
    var messages: [[String: Any]] { lock.lock(); defer { lock.unlock() }; return _messages }

    init(port: UInt16, token: String?, headerName: String = "X-Claude-Code-Ide-Authorization") {
        let ws = NWProtocolWebSocket.Options()
        if let token { ws.setAdditionalHeaders([(name: headerName, value: token)]) }
        ws.setSubprotocols(["mcp"])
        let params = NWParameters.tcp
        params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        // A URL endpoint is required: with host/port the upgrade request is malformed and the server aborts.
        connection = NWConnection(to: .url(URL(string: "ws://127.0.0.1:\(port)")!), using: params)
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready: self.lock.lock(); self._ready = true; self.lock.unlock(); self.receive()
            case .failed, .cancelled, .waiting: self.lock.lock(); self._failed = true; self.lock.unlock()
            default: break
            }
        }
        connection.start(queue: queue)
    }

    private func receive() {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                self.lock.lock(); self._messages.append(obj); self.lock.unlock()
            }
            if error == nil { self.receive() }
        }
    }

    func clearMessages() { lock.lock(); _messages.removeAll(); lock.unlock() }

    func send(_ obj: [String: Any]) {
        guard let d = try? JSONSerialization.data(withJSONObject: obj) else { return }
        let meta = NWProtocolWebSocket.Metadata(opcode: .text)
        connection.send(content: d, contentContext: .init(identifier: "t", metadata: [meta]), isComplete: true, completion: .idempotent)
    }

    func request(_ id: Int, _ method: String, _ params: [String: Any] = [:]) {
        send(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
    }

    func notify(_ method: String, _ params: [String: Any] = [:]) { send(["jsonrpc": "2.0", "method": method, "params": params]) }

    func response(_ id: Int) -> [String: Any]? { messages.first { ($0["id"] as? Int) == id } }
    func notifications(_ method: String) -> [[String: Any]] { messages.filter { ($0["method"] as? String) == method } }
    func close() { connection.cancel() }
}

/// Tiny sequential script: `run` steps execute on the main queue, `wait` steps poll without blocking it (the bridge
/// answers on the main queue, so a test cannot spin the run loop from inside a main-queue block).
private final class ClaudeScript {
    private enum Step { case run(() -> Void), wait(TimeInterval, () -> Bool) }
    private var steps: [Step] = []
    func run(_ f: @escaping () -> Void) { steps.append(.run(f)) }
    func wait(_ timeout: TimeInterval = 3, _ cond: @escaping () -> Bool) { steps.append(.wait(timeout, cond)) }
    func go(_ done: @escaping () -> Void) {
        var i = 0
        func next() {
            guard i < steps.count else { done(); return }
            let step = steps[i]; i += 1
            switch step {
            case .run(let f): f(); next()
            case .wait(let t, let cond):
                let end = Date().addingTimeInterval(t)
                func poll() { if cond() || Date() > end { next() } else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { poll() } } }
                poll()
            }
        }
        next()
    }
}

extension SelfTest {
    private static func resultText(_ r: [String: Any]?, _ i: Int = 0) -> String? {
        let content = (r?["result"] as? [String: Any])?["content"] as? [[String: Any]]
        guard let content, content.indices.contains(i) else { return nil }
        return content[i]["text"] as? String
    }

    private static func isErrorResult(_ r: [String: Any]?) -> Bool { (r?["result"] as? [String: Any])?["isError"] as? Bool == true }

    static func claudeChecks(app: AppDelegate, w: ProjectWindow, dir: URL, done: @escaping () -> Void) {
        let fm = FileManager.default
        let lockDir = fm.temporaryDirectory.appendingPathComponent("ce-claude-locks-\(getpid())")
        let savedLockDir = ClaudeBridge.lockDirectory
        ClaudeBridge.lockDirectory = lockDir

        // --- pure protocol helpers
        check("claude: mention text is the CLI's @file#Lstart-end syntax",
              ClaudeBridge.mentionText(path: "app/A.php", start: 3, end: 7) == "@app/A.php#L3-7 "
              && ClaudeBridge.mentionText(path: "a.php", start: 4, end: 4) == "@a.php#L4 "
              && ClaudeBridge.mentionText(path: "a.php", start: nil, end: nil) == "@a.php ")
        check("claude: first changed line", ClaudeBridge.firstChangedLine(old: "a\nb\nc", new: "a\nB\nc") == 2
              && ClaudeBridge.firstChangedLine(old: "a", new: "a\nb") == 2)
        check("claude: tokens are random and compared exactly",
              ClaudeBridgeServer.makeToken() != ClaudeBridgeServer.makeToken() && ClaudeBridgeServer.tokensEqual("abc", "abc")
              && !ClaudeBridgeServer.tokensEqual("abc", "abd") && !ClaudeBridgeServer.tokensEqual("abc", "abcd"))
        check("claude: executeCode is never advertised",
              !ClaudeBridge.toolDefinitions.contains { ($0["name"] as? String) == "executeCode" })

        // --- fixture
        let file = dir.appendingPathComponent("claude-target.php")
        let original = "<?php\n$a = 1;\n$b = 2;\n$c = 3;\n"
        try? original.write(to: file, atomically: true, encoding: .utf8)
        w.open(file)
        let editor = w.current!
        let savedBridge = w.claudeBridge
        let bridge = ClaudeBridge(root: dir, window: w)
        w.claudeBridge = bridge
        bridge.diagnosticsProvider = {
            [FileProblems(url: file, diagnostics: [.init(severity: 1, message: "Undefined variable $x", line: 3, column: 5, endLine: 3, endColumn: 7, source: "intelephense", code: "P1008")])]
        }

        check("claude: bridge off until started", !bridge.isRunning && bridge.status == .off && bridge.terminalEnvironment.isEmpty)
        check("claude: server starts on loopback", bridge.start() && bridge.port != 0)
        guard bridge.isRunning else { w.claudeBridge = savedBridge; ClaudeBridge.lockDirectory = savedLockDir; done(); return }

        let lock = lockDir.appendingPathComponent("\(bridge.port).lock")
        let lockJSON = (try? Data(contentsOf: lock)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let perms = (try? fm.attributesOfItem(atPath: lock.path))?[.posixPermissions] as? Int
        check("claude: lock file exists with mode 0600", perms == 0o600)
        check("claude: lock file has pid, folders, ideName, ws transport, token",
              lockJSON?["pid"] as? Int == Int(getpid()) && (lockJSON?["workspaceFolders"] as? [String])?.contains(dir.standardizedFileURL.path) == true
              && lockJSON?["ideName"] as? String == Brand.name && lockJSON?["transport"] as? String == "ws"
              && lockJSON?["authToken"] as? String == bridge.authToken && lockJSON?["runningInWindows"] as? Bool == false)
        check("claude: terminal env points claude at this server",
              bridge.terminalEnvironment["CLAUDE_CODE_SSE_PORT"] == String(bridge.port)
              && bridge.terminalEnvironment["CLAUDE_CODE_AUTO_CONNECT_IDE"] == "true")
        check("claude: waiting status before a CLI connects", bridge.status == .waiting)

        let s = ClaudeScript()
        var noToken: ClaudeTestClient!, badToken: ClaudeTestClient!, wrongHeader: ClaudeTestClient!, client: ClaudeTestClient!
        let tv = editor.textView
        let proposed = "<?php\n$a = 10;\n$b = 2;\n$c = 3;\n"
        let tabA = "✻ [Claude Code] claude-target.php (abc) ⧉"
        let fresh = dir.appendingPathComponent("claude-new/sub/new.txt")
        let port = bridge.port, token = bridge.authToken

        // --- handshake auth
        s.run {
            noToken = ClaudeTestClient(port: port, token: nil)
            badToken = ClaudeTestClient(port: port, token: "not-the-token")
            wrongHeader = ClaudeTestClient(port: port, token: token, headerName: "Authorization")
        }
        s.wait { bridge.server!.rejectedHandshakes >= 3 }
        s.run {
            check("claude: handshake without token / wrong token / wrong header is rejected",
                  bridge.server!.rejectedHandshakes >= 3 && !noToken.ready && !badToken.ready && !wrongHeader.ready && bridge.connectedClients == 0)
            [noToken, badToken, wrongHeader].forEach { $0.close() }
            client = ClaudeTestClient(port: port, token: token)
        }
        s.wait { client.ready }
        s.run { check("claude: handshake with the right token succeeds", client.ready)
            client.request(1, "initialize", ["protocolVersion": "2025-06-18", "capabilities": [:], "clientInfo": ["name": "test", "version": "0"]]) }

        // --- JSON-RPC round trip
        s.wait { client.response(1) != nil }
        s.run {
            let r = client.response(1)?["result"] as? [String: Any]
            check("claude: initialize returns version, tools capability and server info",
                  r?["protocolVersion"] as? String == "2025-06-18" && (r?["capabilities"] as? [String: Any])?["tools"] != nil
                  && (r?["serverInfo"] as? [String: Any])?["name"] as? String == Brand.name)
            client.notify("notifications/initialized")
            client.notify("ide_connected", ["pid": 123])
        }
        s.wait { bridge.status == .connected(1) }
        s.run {
            check("claude: status becomes connected", bridge.status == .connected(1))
            client.request(2, "tools/list")
            client.request(3, "tools/call", ["name": "executeCode", "arguments": ["code": "print(1)"]])
            client.request(4, "bogus/method")
            client.request(5, "ping")
        }
        s.wait { client.response(2) != nil && client.response(3) != nil && client.response(4) != nil && client.response(5) != nil }
        s.run {
            let names = ((client.response(2)?["result"] as? [String: Any])?["tools"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
            check("claude: tools/list offers diagnostics + diff tools only", Set(names) == ["getDiagnostics", "openDiff", "close_tab", "closeAllDiffTabs"])
            check("claude: unknown tool and method are errors, ping works",
                  (client.response(3)?["error"] as? [String: Any]) != nil && (client.response(4)?["error"] as? [String: Any])?["code"] as? Int == -32601
                  && client.response(5)?["result"] != nil)
            client.request(6, "tools/call", ["name": "getDiagnostics", "arguments": [:]])
            client.request(7, "tools/call", ["name": "getDiagnostics", "arguments": ["uri": file.absoluteString]])
            client.request(8, "tools/call", ["name": "getDiagnostics", "arguments": ["uri": "file:///etc/hosts"]])
        }

        // --- getDiagnostics
        s.wait { client.response(6) != nil && client.response(7) != nil && client.response(8) != nil }
        s.run {
            let diag = Self.resultText(client.response(6)).flatMap { $0.data(using: .utf8) }.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] }
            let d0 = (diag?.first?["diagnostics"] as? [[String: Any]])?.first
            let start = (d0?["range"] as? [String: Any])?["start"] as? [String: Int]
            check("claude: getDiagnostics returns uri + LSP-shaped diagnostics (0-based, severity names)",
                  diag?.count == 1 && (diag?.first?["uri"] as? String)?.hasSuffix("claude-target.php") == true
                  && d0?["severity"] as? String == "Error" && d0?["message"] as? String == "Undefined variable $x"
                  && start?["line"] == 2 && start?["character"] == 4 && d0?["source"] as? String == "intelephense")
            check("claude: getDiagnostics(uri) filters to that file; outside-project uri yields nothing",
                  Self.resultText(client.response(7))?.contains("Undefined variable") == true && Self.resultText(client.response(8)) == "[]")
            tv.setSelectedRange(NSRange(location: 6, length: 7))       // "$a = 1;" on line 2
            client.clearMessages()
            bridge.editorStateChanged()
        }

        // --- selection_changed
        s.wait { !client.notifications("selection_changed").isEmpty }
        s.run {
            let sel = client.notifications("selection_changed").last?["params"] as? [String: Any]
            let ss = (sel?["selection"] as? [String: Any])?["start"] as? [String: Int], se = (sel?["selection"] as? [String: Any])?["end"] as? [String: Int]
            check("claude: selection_changed is pushed with file, 0-based range and text",
                  sel?["filePath"] as? String == file.standardizedFileURL.path && sel?["text"] as? String == "$a = 1;"
                  && ss?["line"] == 1 && ss?["character"] == 0 && se?["line"] == 1 && se?["character"] == 7)
            client.clearMessages()
            check("claude: sendMention goes through at_mentioned when connected", bridge.sendMention(url: file, startLine: 2, endLine: 3))
        }

        // --- at_mentioned
        s.wait { !client.notifications("at_mentioned").isEmpty }
        s.run {
            let m = client.notifications("at_mentioned").last?["params"] as? [String: Any]
            check("claude: at_mentioned uses absolute path and 0-based lines",
                  m?["filePath"] as? String == file.standardizedFileURL.path && m?["lineStart"] as? Int == 1 && m?["lineEnd"] as? Int == 2)
            tv.setSelectedRange(NSRange(location: original.utf16.count - 3, length: 0))     // caret before the "3" of the last line
            client.clearMessages()
            client.request(10, "tools/call", ["name": "openDiff", "arguments": ["old_file_path": file.path, "new_file_path": file.path,
                                                                              "new_file_contents": proposed, "tab_name": tabA]])
        }

        // --- openDiff accept (jump to file, write, reload preserving caret + undo)
        s.wait { bridge.pendingDiffs.count == 1 }
        s.run {
            check("claude: openDiff waits for a decision", bridge.pendingDiffs.count == 1 && client.response(10) == nil)
            check("claude: openDiff reveals the file", w.current?.url.standardizedFileURL == file.standardizedFileURL)
            bridge.finishDiff(tabA, .accept(proposed), reply: true)
        }
        s.wait { client.response(10) != nil }
        s.run {
            check("claude: accept answers FILE_SAVED + final contents",
                  Self.resultText(client.response(10), 0) == "FILE_SAVED" && Self.resultText(client.response(10), 1) == proposed)
            check("claude: accepted edit is on disk and in the open buffer", ((try? String(contentsOf: file)) ?? "") == proposed && editor.textView.string == proposed)
            check("claude: caret keeps its place in the text after the reload", editor.textView.selectedRange().location == proposed.utf16.count - 3)
            check("claude: reload is undoable", editor.textView.undoManager?.canUndo == true)
            client.clearMessages()
            client.request(11, "tools/call", ["name": "openDiff", "arguments": ["old_file_path": file.path, "new_file_path": file.path,
                                                                              "new_file_contents": "REJECT ME\n", "tab_name": "t2"]])
        }

        // --- reject / close_tab / outside project
        s.wait { bridge.pendingDiffs["t2"] != nil }
        s.run { bridge.finishDiff("t2", .reject, reply: true) }
        s.wait { client.response(11) != nil }
        s.run {
            check("claude: reject answers DIFF_REJECTED and leaves the file alone",
                  Self.resultText(client.response(11)) == "DIFF_REJECTED" && ((try? String(contentsOf: file)) ?? "") == proposed)
            client.request(12, "tools/call", ["name": "openDiff", "arguments": ["old_file_path": file.path, "new_file_path": file.path,
                                                                              "new_file_contents": "closed\n", "tab_name": "t3"]])
        }
        s.wait { bridge.pendingDiffs["t3"] != nil }
        s.run { client.request(13, "tools/call", ["name": "close_tab", "arguments": ["tab_name": "t3"]]) }
        s.wait { client.response(12) != nil && client.response(13) != nil }
        s.run {
            check("claude: close_tab settles the pending diff with TAB_CLOSED",
                  Self.resultText(client.response(12)) == "TAB_CLOSED" && bridge.pendingDiffs.isEmpty && ((try? String(contentsOf: file)) ?? "") == proposed)
            client.request(14, "tools/call", ["name": "openDiff", "arguments": ["old_file_path": "/etc/hosts", "new_file_path": "/etc/hosts",
                                                                              "new_file_contents": "x", "tab_name": "t4"]])
            client.request(15, "tools/call", ["name": "openDiff", "arguments": ["old_file_path": "../escape", "new_file_path": "../escape",
                                                                              "new_file_contents": "x", "tab_name": "t5"]])
        }
        s.wait { client.response(14) != nil && client.response(15) != nil }
        s.run {
            check("claude: openDiff outside the project (absolute or relative) is refused",
                  Self.isErrorResult(client.response(14)) && Self.isErrorResult(client.response(15)) && bridge.pendingDiffs.isEmpty)
            bridge.diffDecider = { d in .accept(d.proposed) }
            client.request(16, "tools/call", ["name": "openDiff", "arguments": ["old_file_path": fresh.path, "new_file_path": fresh.path,
                                                                              "new_file_contents": "hello\n", "tab_name": "t6"]])
        }

        // --- brand-new file decided by the hook
        s.wait { client.response(16) != nil }
        s.run {
            check("claude: accepting a new-file diff creates it",
                  Self.resultText(client.response(16)) == "FILE_SAVED" && ((try? String(contentsOf: fresh)) ?? "") == "hello\n")
            bridge.diffDecider = nil
            client.close()
        }

        // --- the real review window (built, never shown): Accept returns the proposal text, Reject and closing reject
        s.run {
            let pd = ClaudeBridge.PendingDiff(tabName: "ui", url: file, requestID: 1, clientID: 1, proposed: "new\n", original: "old\n")
            var outcomes: [String] = []
            func tag(_ o: ClaudeBridge.DiffOutcome) { switch o { case .accept(let t): outcomes.append("accept:" + t); case .reject: outcomes.append("reject"); case .closed: outcomes.append("closed") } }
            let a = ClaudeDiffWindowController(diff: pd, onOutcome: tag), b = ClaudeDiffWindowController(diff: pd, onOutcome: tag)
            let c = ClaudeDiffWindowController(diff: pd, onOutcome: tag)
            check("claude: diff window shows the proposal on the editable side", a.proposalText == "new\n")
            a.accept(); a.accept()                 // second call is ignored
            b.reject()
            c.close()                              // closing without choosing rejects
            check("claude: diff window Accept/Reject/close map to accept(text)/reject/reject", outcomes == ["accept:new\n", "reject", "reject"])
        }

        // --- disconnect / stale locks / stop / preference
        s.wait { bridge.status == .waiting }
        s.run {
            check("claude: status returns to waiting when the CLI disconnects", bridge.status == .waiting)
            check("claude: mention falls back (false) with no CLI connected", !bridge.sendMention(url: file, startLine: 1, endLine: 1))
            let dead = lockDir.appendingPathComponent("59990.lock"), live = lockDir.appendingPathComponent("59991.lock"), foreign = lockDir.appendingPathComponent("59992.lock")
            func body(_ pid: Int, _ name: String) -> Data {
                (try? JSONSerialization.data(withJSONObject: ["pid": pid, "workspaceFolders": ["/x"], "ideName": name, "transport": "ws", "authToken": "t"])) ?? Data()
            }
            try? body(2_000_000_000, Brand.name).write(to: dead)
            try? body(Int(getpid()), Brand.name).write(to: live)
            try? body(2_000_000_000, "VS Code").write(to: foreign)
            ClaudeBridge.removeStaleLocks()
            check("claude: stale cleanup removes only our dead locks",
                  !fm.fileExists(atPath: dead.path) && fm.fileExists(atPath: live.path) && fm.fileExists(atPath: foreign.path))
            try? fm.removeItem(at: live); try? fm.removeItem(at: foreign)
            bridge.stop()
            check("claude: stop removes the lock file and closes the server", !fm.fileExists(atPath: lock.path) && bridge.status == .off)

            let savedEnabled = Prefs.claudeBridgeEnabled
            Prefs.claudeBridgeEnabled = false
            ClaudeBridge.allowHeadlessStart = true
            bridge.applyPreference()
            check("claude: Settings toggle off keeps the bridge stopped and writes no lock",
                  !bridge.isRunning && ((try? fm.contentsOfDirectory(atPath: lockDir.path)) ?? []).filter { $0.hasSuffix(".lock") }.isEmpty)
            Prefs.claudeBridgeEnabled = true
            bridge.applyPreference()
            check("claude: Settings toggle on starts it and feeds the terminal env",
                  bridge.isRunning && w.terminalPanel?.extraEnvironment["CLAUDE_CODE_SSE_PORT"] == String(bridge.port))
            Prefs.claudeBridgeEnabled = savedEnabled
            ClaudeBridge.allowHeadlessStart = false
            bridge.applyPreference()
            check("claude: headless runs never start a bridge on their own", !bridge.isRunning && w.terminalPanel?.extraEnvironment.isEmpty == true)
            bridge.shutdown()
            w.claudeBridge = savedBridge
            ClaudeBridge.lockDirectory = savedLockDir
            try? fm.removeItem(at: lockDir)
        }
        s.go {
            if let live = AppEnv.value("CE_CLAUDE_LIVE") { claudeLive(control: URL(fileURLWithPath: live), w: w, dir: dir, done: done) } else { done() }
        }
    }

    /// Manual harness (CE_SELFTEST=1 CE_CLAUDE_LIVE=<control dir>): serves a real bridge for the temp project in the real
    /// `~/.claude/ide`, writes `info.json` + `trace.log` into the control dir and runs until `stop` appears there (max 240 s).
    /// Diffs are auto-accepted. Used to exercise the real `claude` CLI headlessly; never part of the normal run.
    private static func claudeLive(control: URL, w: ProjectWindow, dir: URL, done: @escaping () -> Void) {
        let fm = FileManager.default
        let bridge = ClaudeBridge(root: dir, window: w)
        let savedBridge = w.claudeBridge
        w.claudeBridge = bridge
        let log = control.appendingPathComponent("trace.log")
        fm.createFile(atPath: log.path, contents: nil)
        let handle = try? FileHandle(forWritingTo: log)
        bridge.trace = { line in handle?.write(Data((line + "\n").utf8)) }
        bridge.diagnosticsProvider = {
            [FileProblems(url: dir.appendingPathComponent("hello.php"), diagnostics: [.init(severity: 1, message: "LIVE-TEST-DIAGNOSTIC-4711", line: 2, column: 1, endLine: 2, endColumn: 5, source: "kode", code: nil)])]
        }
        bridge.diffDecider = { d in
            bridge.trace?("DECIDE accept \(d.url.path)")
            return .accept(d.proposed)
        }
        guard bridge.start() else { check("claude live: bridge starts", false); done(); return }
        let info: [String: Any] = ["port": Int(bridge.port), "root": dir.path, "token": bridge.authToken]
        try? JSONSerialization.data(withJSONObject: info).write(to: control.appendingPathComponent("info.json"))
        let end = Date().addingTimeInterval(240)
        func poll() {
            if fm.fileExists(atPath: control.appendingPathComponent("stop").path) || Date() > end {
                bridge.shutdown(); w.claudeBridge = savedBridge; try? handle?.close(); done()
            } else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { poll() } }
        }
        poll()
    }
}
