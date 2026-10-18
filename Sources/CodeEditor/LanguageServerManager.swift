import AppKit

// MARK: - Server table

/// One entry per language server. Adding a server = adding an entry to `LanguageServerConfig.table`.
struct LanguageServerConfig {
    let id: String
    let name: String
    let extensions: [String]                 // lowercased, no dot
    let languageIds: [String: String]        // extension -> LSP languageId
    let executables: [String]                // candidate binary names
    let args: [String]
    let rootMarkers: [String]
    let installHint: String
    let reportMissing: Bool                  // show "not found" in the status text
    let defaultTriggers: [String]
    var requireRootMarker = false             // only start when a marker file is really found (e.g. tailwind.config.js)
    let initializationOptions: (URL) -> [String: Any]
    let settings: [String: Any]              // answered to workspace/configuration (keyed by top-level section)

    func languageId(forExtension ext: String) -> String { languageIds[ext] ?? ext }

    static func licenceKey() -> String? {
        if let k = UserDefaults.standard.string(forKey: "intelephenseLicenceKey")?.trimmingCharacters(in: .whitespacesAndNewlines),
           !k.isEmpty { return k }
        let file = NSHomeDirectory() + "/intelephense/licence.txt"
        if let k = try? String(contentsOfFile: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           !k.isEmpty { return k }
        return nil
    }

    static var cacheDir: String { NSHomeDirectory() + "/Library/Caches/CodeEditor" }

    /// Locates the TypeScript `lib` directory Volar needs (global npm, then VS Code's bundled copy).
    static func typescriptLibDir() -> String? {
        let fm = FileManager.default
        var candidates: [String] = []
        let nvm = NSHomeDirectory() + "/.nvm/versions/node"
        for v in ((try? fm.contentsOfDirectory(atPath: nvm)) ?? []).sorted(by: >) {
            candidates.append("\(nvm)/\(v)/lib/node_modules/typescript/lib")
        }
        candidates += ["/opt/homebrew/lib/node_modules/typescript/lib", "/usr/local/lib/node_modules/typescript/lib",
                       "/Applications/Visual Studio Code.app/Contents/Resources/app/extensions/node_modules/typescript/lib"]
        return candidates.first { fm.fileExists(atPath: $0 + "/tsserver.js") }
    }

    static let table: [LanguageServerConfig] = [
        LanguageServerConfig(
            id: "intelephense", name: "Intelephense", extensions: ["php", "phtml"],
            languageIds: ["php": "php", "phtml": "php"], executables: ["intelephense"], args: ["--stdio"],
            rootMarkers: ["composer.json", ".git", ".phpstorm.meta.php"],
            installHint: "npm i -g intelephense", reportMissing: true,
            defaultTriggers: ["$", ">", ":", "\\", "@"],
            initializationOptions: { _ in
                try? FileManager.default.createDirectory(atPath: cacheDir + "/intelephense", withIntermediateDirectories: true)
                var o: [String: Any] = ["storagePath": cacheDir + "/intelephense", "clearCache": false]
                if let key = licenceKey() { o["licenceKey"] = key }
                return o
            },
            // `files.exclude` is deliberately NOT set: Intelephense's defaults index vendor/ (framework classes must
            // resolve) and only skip tests/node_modules/VCS dirs. `environment.includePaths` stays unset too.
            settings: ["intelephense": ["files": ["maxSize": 1_000_000], "telemetry": ["enabled": false],
                                        "diagnostics": ["enable": true], "format": ["enable": true],
                                        "completion": ["insertUseDeclaration": true, "triggerParameterHints": true],
                                        "trace": ["server": "off"]]]),
        LanguageServerConfig(
            id: "volar", name: "Vue (Volar)", extensions: ["vue"], languageIds: ["vue": "vue"],
            executables: ["vue-language-server"],
            args: ["--stdio"] + (typescriptLibDir().map { ["--tsdk=\($0)"] } ?? []),
            rootMarkers: ["package.json", "vite.config.ts", "vite.config.js", ".git"],
            installHint: "npm i -g @vue/language-server typescript", reportMissing: true,
            defaultTriggers: ["<", ".", ":", "@", "/"],
            initializationOptions: { _ in
                var o: [String: Any] = [:]
                if let lib = typescriptLibDir() { o["typescript"] = ["tsdk": lib] }
                return o
            },
            settings: [:]),
        // Not installed on the author's machine; they are silent no-ops until the binary exists.
        LanguageServerConfig(
            id: "typescript", name: "TypeScript", extensions: ["ts", "tsx", "js", "jsx", "mjs", "cjs"],
            languageIds: ["ts": "typescript", "tsx": "typescriptreact", "js": "javascript", "jsx": "javascriptreact",
                          "mjs": "javascript", "cjs": "javascript"],
            executables: ["typescript-language-server"], args: ["--stdio"],
            rootMarkers: ["tsconfig.json", "jsconfig.json", "package.json", ".git"],
            installHint: "npm i -g typescript typescript-language-server", reportMissing: false,
            defaultTriggers: [".", "\"", "'", "/", "@", "<"],
            initializationOptions: { _ in
                var o: [String: Any] = [:]
                if let lib = typescriptLibDir() { o["tsserver"] = ["path": lib + "/tsserver.js"] }
                return o
            },
            settings: [:]),
        LanguageServerConfig(
            id: "html", name: "HTML", extensions: ["html", "htm"], languageIds: ["html": "html", "htm": "html"],
            executables: ["vscode-html-language-server"], args: ["--stdio"], rootMarkers: ["package.json", ".git"],
            installHint: "npm i -g vscode-langservers-extracted", reportMissing: false,
            defaultTriggers: ["<", "/", "\"", "=", ":"],
            initializationOptions: { _ in ["provideFormatter": false] }, settings: [:]),
        LanguageServerConfig(
            id: "css", name: "CSS", extensions: ["css", "scss", "less"],
            languageIds: ["css": "css", "scss": "scss", "less": "less"],
            executables: ["vscode-css-language-server"], args: ["--stdio"], rootMarkers: ["package.json", ".git"],
            installHint: "npm i -g vscode-langservers-extracted", reportMissing: false,
            defaultTriggers: ["-", ":", "@", "."], initializationOptions: { _ in [:] }, settings: [:]),
        LanguageServerConfig(
            id: "tailwind", name: "Tailwind CSS", extensions: ["html", "vue", "php", "css", "jsx", "tsx"],
            languageIds: ["html": "html", "vue": "vue", "php": "php", "css": "css", "jsx": "javascriptreact", "tsx": "typescriptreact"],
            executables: ["tailwindcss-language-server"], args: ["--stdio"],
            rootMarkers: ["tailwind.config.js", "tailwind.config.ts", "tailwind.config.cjs", "tailwind.config.mjs"],
            installHint: "npm i -g @tailwindcss/language-server", reportMissing: false,
            defaultTriggers: ["\"", "'", "`", " ", ":", "-"], requireRootMarker: true, initializationOptions: { _ in [:] },
            settings: ["tailwindCSS": ["emmetCompletions": false]] ),
    ]

    /// Extension point for additional servers (user configuration, tests); consulted after `table`.
    static var extra: [LanguageServerConfig] = []

    static func configs(forExtension ext: String) -> [LanguageServerConfig] {
        let e = ext.lowercased()
        return (table + extra).filter { $0.extensions.contains(e) }
    }
}

// MARK: - Status

enum LanguageServerState: Equatable {
    case starting
    case indexing(String)
    case ready
    case failed(String)
    case stopped
}

struct LanguageServerStatus {
    let serverId: String
    let name: String
    let root: URL
    let state: LanguageServerState
    let rssBytes: UInt64
    /// "Intelephense: indexing 45% - 612 MB" style summary.
    var text: String {
        let mem = rssBytes > 0 ? " · \(LanguageServerStatus.format(rssBytes))" : ""
        switch state {
        case .starting: return "\(name): starting…"
        case .indexing(let p): return "\(name): \(p)\(mem)"
        case .ready: return "\(name)\(mem)"
        case .failed(let m): return m
        case .stopped: return "\(name): stopped"
        }
    }
    static func format(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / 1_048_576
        return mb >= 1024 ? String(format: "%.1f GB", mb / 1024) : String(format: "%.0f MB", mb)
    }
}

// MARK: - Instance (one process per server and project root)

final class LSPServerInstance {
    let config: LanguageServerConfig
    let root: URL
    private(set) var state: LanguageServerState = .starting
    private(set) var capabilities: [String: Any] = [:]
    private(set) var isInitialized = false
    private(set) var rss: UInt64 = 0
    private(set) var client: LSPClient?
    var sessions: [ObjectIdentifier: LSPSession] = [:]
    var restarts = 0
    var idleWork: DispatchWorkItem?
    var progress: String?
    private var generation = 0
    unowned let manager: LanguageServerManager

    init(config: LanguageServerConfig, root: URL, manager: LanguageServerManager) {
        self.config = config
        self.root = root
        self.manager = manager
    }

    var key: String { config.id + "|" + root.path }
    var uri: String { root.absoluteString.hasSuffix("/") ? String(root.absoluteString.dropLast()) : root.absoluteString }

    var status: LanguageServerStatus {
        var s = state
        if s == .ready, let p = progress { s = .indexing(p) }
        return LanguageServerStatus(serverId: config.id, name: config.name, root: root, state: s, rssBytes: rss)
    }

    private static let forceFullSync = ProcessInfo.processInfo.environment["CE_LSP_FULLSYNC"] != nil
    /// TextDocumentSyncKind the server wants: 0 none, 1 full, 2 incremental.
    var syncKind: Int {
        if Self.forceFullSync { return 1 }   // CE_LSP_FULLSYNC=1: debugging aid
        let v = capabilities["textDocumentSync"]
        if let n = v as? NSNumber { return n.intValue }
        if let d = v as? [String: Any], let n = d["change"] as? NSNumber { return n.intValue }
        return 1
    }

    func supports(_ capability: String) -> Bool {
        guard isInitialized, let v = capabilities[capability] else { return false }
        if let b = v as? Bool { return b }
        return v is [String: Any]
    }

    var triggerCharacters: [String] {
        if let c = capabilities["completionProvider"] as? [String: Any], let t = c["triggerCharacters"] as? [String] { return t }
        return config.defaultTriggers
    }

    func setState(_ s: LanguageServerState) {
        state = s
        manager.statusChanged()
    }

    // MARK: Launch

    func launch() {
        generation += 1
        let gen = generation
        isInitialized = false
        capabilities = [:]
        progress = nil
        guard let exe = manager.resolveExecutable(config.executables) else {
            setState(.failed("\(config.executables[0]) not found (\(config.installHint))"))
            return
        }
        setState(.starting)
        let client = LSPClient()
        self.client = client
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (manager.extraPathDirs(for: exe) + (env["PATH"] ?? "/usr/bin:/bin").split(separator: ":").map(String.init))
            .joined(separator: ":")
        let settings = config.settings
        let folder: [String: Any] = ["uri": uri, "name": root.lastPathComponent]
        client.onServerRequest = { method, params in
            switch method {
            case "window/workDoneProgress/create", "client/registerCapability", "client/unregisterCapability",
                 "window/showMessageRequest", "workspace/diagnostic/refresh", "workspace/semanticTokens/refresh",
                 "workspace/inlayHint/refresh", "workspace/codeLens/refresh", "window/showDocument":
                return NSNull()
            case "workspace/workspaceFolders": return [folder]
            case "workspace/applyEdit":
                // Runs on the client queue; edits touch AppKit buffers so hop to main (main never blocks on this queue).
                var out: [String: Any] = ["applied": false, "failureReason": "editor unavailable"]
                let work = { out = LSPEdits.handleApplyEdit(params) }
                if Thread.isMainThread { work() } else { DispatchQueue.main.sync(execute: work) }
                return out
            case "workspace/configuration":
                let items = ((params as? [String: Any])?["items"] as? [[String: Any]]) ?? []
                return items.map { item -> Any in
                    let section = (item["section"] as? String) ?? ""
                    var node: Any? = settings
                    for part in section.split(separator: ".") { node = (node as? [String: Any])?[String(part)] }
                    if section.isEmpty { return settings }
                    return node ?? NSNull()
                }
            default: return LSPClient.unhandled
            }
        }
        client.onNotification = { [weak self] method, params in
            guard let self, gen == self.generation else { return }
            self.handleNotification(method, params)
        }
        client.onExit = { [weak self] status, requested in
            guard let self, gen == self.generation else { return }
            self.manager.instanceExited(self, status: status, requested: requested)
        }
        do {
            try client.start(executable: exe, arguments: config.args, environment: env, cwd: root)
        } catch {
            setState(.failed("\(config.name) failed to start: \(error.localizedDescription)"))
            return
        }
        let params: [String: Any] = [
            "processId": Int(ProcessInfo.processInfo.processIdentifier),
            "clientInfo": ["name": "CodeEditor", "version": "1"],
            "rootUri": uri, "rootPath": root.path,
            "workspaceFolders": [folder],
            "initializationOptions": config.initializationOptions(root),
            "capabilities": Self.clientCapabilities,
            "trace": "off",
        ]
        client.request("initialize", params, timeout: 90) { [weak self] result in
            guard let self, gen == self.generation else { return }
            switch result {
            case .success(let value):
                self.capabilities = ((value as? [String: Any])?["capabilities"] as? [String: Any]) ?? [:]
                self.isInitialized = true
                client.notify("initialized", [String: Any]())
                if !settings.isEmpty { client.notify("workspace/didChangeConfiguration", ["settings": settings]) }
                self.setState(.ready)
                self.manager.instanceReady(self)
            case .failure(let e):
                self.setState(.failed("\(self.config.name) failed to initialize: \(e.message)"))
                client.shutdown()
            }
        }
    }

    private func handleNotification(_ method: String, _ params: Any?) {
        let p = params as? [String: Any]
        switch method {
        case "textDocument/publishDiagnostics":
            if let p { manager.diagnosticsReceived(from: self, params: p) }
        case "indexingStarted":
            progress = "indexing…"; refreshRSS(); manager.statusChanged()
        case "indexingEnded":
            progress = nil; refreshRSS(); manager.statusChanged()
        case "$/progress":
            guard let v = p?["value"] as? [String: Any], let kind = v["kind"] as? String else { return }
            if kind == "end" { progress = nil }
            else {
                var text = (v["message"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "indexing"
                if let pct = (v["percentage"] as? NSNumber)?.intValue { text += " \(pct)%" }
                progress = text
            }
            if progress != nil, Date().timeIntervalSince(lastRSS) > 1.5 { refreshRSS() }
            manager.statusChanged()
        case "tsserver/request":
            // Volar 3 asks the client to forward requests to a tsserver carrying @vue/typescript-plugin.
            // We run none, so answer "no result": Volar falls back to its tsconfig-less HTML/CSS/template services.
            if let a = params as? [Any], let inner = a.first as? [Any], let id = inner.first {
                client?.notify("tsserver/response", [[id, NSNull()]])
            }
        case "window/showMessage", "window/logMessage":
            LSPLog.log("\(config.id): \((p?["message"] as? String) ?? "")")
        default: break
        }
    }

    private var lastRSS = Date.distantPast
    func refreshRSS() {
        lastRSS = Date()
        guard let c = client, c.isRunning else { rss = 0; return }
        rss = LSPProcessInfo.treeResidentBytes(of: c.pid)
    }

    func stop() {
        generation += 1   // ignore any further callbacks from the old process
        idleWork?.cancel()
        client?.shutdown()
        client = nil
        isInitialized = false
        rss = 0
        state = .stopped
    }

    func killNow() { client?.kill() }

    private static let clientCapabilities: [String: Any] = [
        "workspace": ["workspaceFolders": true, "configuration": true, "applyEdit": true,
                      "workspaceEdit": ["documentChanges": true],
                      "didChangeWatchedFiles": ["dynamicRegistration": false],
                      "didChangeConfiguration": ["dynamicRegistration": false]],
        "window": ["workDoneProgress": true, "showMessage": ["messageActionItem": ["additionalPropertiesSupport": false]]],
        "textDocument": [
            "synchronization": ["didSave": true, "dynamicRegistration": false],
            "completion": [
                "contextSupport": true,
                "completionItem": [
                    "snippetSupport": true, "documentationFormat": ["markdown", "plaintext"],
                    "deprecatedSupport": true, "tagSupport": ["valueSet": [1]],
                    "resolveSupport": ["properties": ["documentation", "detail", "additionalTextEdits"]],
                    "labelDetailsSupport": true,
                ],
                "completionItemKind": ["valueSet": Array(1...25)],
            ],
            "hover": ["contentFormat": ["markdown", "plaintext"]],
            "signatureHelp": [
                "contextSupport": true,
                "signatureInformation": ["documentationFormat": ["markdown", "plaintext"],
                                         "parameterInformation": ["labelOffsetSupport": true],
                                         "activeParameterSupport": true],
            ],
            "definition": ["linkSupport": true],
            "references": [:] as [String: Any],
            "rename": ["prepareSupport": true],
            "formatting": [:] as [String: Any],
            "rangeFormatting": [:] as [String: Any],
            "publishDiagnostics": ["relatedInformation": false, "versionSupport": true, "tagSupport": ["valueSet": [1, 2]]],
        ],
    ]
}

// MARK: - Manager

final class LanguageServerManager {
    static let shared = LanguageServerManager()
    static let statusDidChange = Notification.Name("CodeEditor.languageServerStatusDidChange")

    /// Seconds with no open file of the server's languages before it is shut down (CE_LSP_IDLE_SECONDS overrides).
    var idleTimeout: TimeInterval = TimeInterval(AppEnv.value("CE_LSP_IDLE_SECONDS") ?? "") ?? 600
    /// Base delay for crash restarts (doubles each time, max 3 restarts).
    var restartBackoff: TimeInterval = 1

    private(set) var instances: [String: LSPServerInstance] = [:]
    private(set) var sessions: [ObjectIdentifier: LSPSession] = [:]
    private var execCache: [String: String?] = [:]
    private var rssTimer: Timer?
    private var started = false
    /// path -> serverId -> diagnostics (small; cleared when the file closes)
    private(set) var diagnostics: [String: [String: [LSPDiagnostic]]] = [:]

    func start() {
        guard !started else { return }
        started = true
        EditorEvents.onOpen { [weak self] tab in self?.tabOpened(tab) }
        EditorEvents.onClose { [weak self] tab in self?.tabClosed(tab) }
        EditorEvents.onSave { [weak self] tab in self?.sessions[ObjectIdentifier(tab)]?.didSave() }
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, let win = n.object as? NSWindow else { return }
            for s in self.sessions.values where s.tab?.textView.window === win { self.detach(s) }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { [weak self] _ in
            self?.instances.values.forEach { $0.killNow() }
        }
    }

    // MARK: Tabs

    private func tabOpened(_ tab: EditorTab) {
        let ext = tab.url.pathExtension.lowercased()
        let configs = LanguageServerConfig.configs(forExtension: ext)
        guard !configs.isEmpty else { return }
        let id = ObjectIdentifier(tab)
        guard sessions[id] == nil else { return }
        let session = LSPSession(tab: tab, manager: self)
        sessions[id] = session
        for config in configs {
            if !config.reportMissing, resolveExecutable(config.executables) == nil { continue }
            guard let root = projectRoot(for: tab.url, config: config) else { continue }
            let inst = instance(for: config, root: root)
            session.instances.append(inst)
            inst.sessions[id] = session
            inst.idleWork?.cancel(); inst.idleWork = nil
            if inst.isInitialized { session.didOpen(in: inst) }
        }
        session.installUI()
        statusChanged()
    }

    private func tabClosed(_ tab: EditorTab) {
        if let s = sessions[ObjectIdentifier(tab)] { detach(s) }
    }

    func detach(_ session: LSPSession) {
        guard let tab = session.tab ?? nil, sessions[ObjectIdentifier(tab)] === session else {
            sessions = sessions.filter { $0.value !== session }
            return
        }
        sessions[ObjectIdentifier(tab)] = nil
        let path = session.url.standardizedFileURL.path
        session.close()
        if diagnostics[path] != nil { diagnostics[path] = nil; problemsChanged() }
        for inst in session.instances {
            inst.sessions[ObjectIdentifier(tab)] = nil
            if inst.sessions.isEmpty { scheduleIdle(inst) }
        }
        statusChanged()
    }

    func session(forURL url: URL) -> LSPSession? {
        let p = url.standardizedFileURL.path
        return sessions.values.first { $0.url.standardizedFileURL.path == p }
    }

    // MARK: Instances

    private func instance(for config: LanguageServerConfig, root: URL) -> LSPServerInstance {
        let key = config.id + "|" + root.path
        if let i = instances[key] {
            if case .failed = i.state { resetExecutableCache(); i.launch() }
            return i
        }
        let inst = LSPServerInstance(config: config, root: root, manager: self)
        instances[key] = inst
        inst.launch()
        ensureTimer()
        return inst
    }

    func instanceReady(_ inst: LSPServerInstance) {
        for s in inst.sessions.values { s.didOpen(in: inst) }
        inst.refreshRSS()
    }

    func instanceExited(_ inst: LSPServerInstance, status: Int32, requested: Bool) {
        inst.refreshRSS()
        guard !requested else { return }
        LSPLog.log("\(inst.config.id) exited unexpectedly (\(status))")
        for s in inst.sessions.values { s.instanceRestarting(inst) }
        if inst.sessions.isEmpty { instances[inst.key] = nil; return }
        if inst.restarts < 3 {
            let delay = restartBackoff * pow(2, Double(inst.restarts))
            inst.restarts += 1
            inst.stop()
            statusChanged()
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak inst] in
                guard let self, let inst, self.instances[inst.key] === inst, !inst.sessions.isEmpty else { return }
                inst.launch()
            }
        } else {
            inst.stop()
            inst.setState(.failed("\(inst.config.name) crashed repeatedly; reopen the file to retry"))
            statusChanged()
        }
    }

    private func scheduleIdle(_ inst: LSPServerInstance) {
        inst.idleWork?.cancel()
        let work = DispatchWorkItem { [weak self, weak inst] in
            guard let self, let inst, inst.sessions.isEmpty else { return }
            LSPLog.log("idle shutdown \(inst.key)")
            inst.stop()
            self.instances[inst.key] = nil
            self.statusChanged()
        }
        inst.idleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + idleTimeout, execute: work)
    }

    /// Stops every server now (tests / explicit user action).
    func stopAll() {
        for inst in instances.values { inst.stop() }
        instances.removeAll()
        statusChanged()
    }

    // MARK: Status

    func statusChanged() {
        NotificationCenter.default.post(name: Self.statusDidChange, object: nil)
    }

    private func ensureTimer() {
        guard rssTimer == nil else { return }
        rssTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self else { return }
            for (id, s) in self.sessions where s.tab == nil { self.sessions[id] = nil; self.detach(s) }
            for i in self.instances.values { i.refreshRSS() }
            self.statusChanged()
            if self.instances.isEmpty { self.rssTimer?.invalidate(); self.rssTimer = nil }
        }
        rssTimer?.tolerance = 2
    }

    func statuses() -> [LanguageServerStatus] {
        instances.values.map { $0.status }.sorted { ($0.root.path, $0.name) < ($1.root.path, $1.name) }
    }

    func statusText(forRoot root: URL) -> String {
        let rp = root.standardizedFileURL.path
        let parts = statuses().filter { s in
            let sp = s.root.path
            return sp == rp || sp.hasPrefix(rp + "/") || rp.hasPrefix(sp + "/")
        }.filter { s in
            if case .failed = s.state { return LanguageServerConfig.table.first { $0.id == s.serverId }?.reportMissing ?? false }
            return true
        }.map(\.text)
        return parts.joined(separator: "  |  ")
    }

    // MARK: Diagnostics

    private var problemsPosted = false
    /// Coalesced `LanguageServers.problemsDidChange` (main thread).
    func problemsChanged() {
        guard !problemsPosted else { return }
        problemsPosted = true
        DispatchQueue.main.async { [weak self] in
            self?.problemsPosted = false
            NotificationCenter.default.post(name: LanguageServers.problemsDidChange, object: nil)
        }
    }

    func diagnosticsReceived(from inst: LSPServerInstance, params: [String: Any]) {
        guard let uri = params["uri"] as? String, let url = URL(string: uri), url.isFileURL else { return }
        let raw = (params["diagnostics"] as? [[String: Any]]) ?? []
        let version = (params["version"] as? NSNumber)?.intValue
        guard let session = session(forURL: url) else { return }
        session.setDiagnostics(raw, serverId: inst.config.id, version: version)
    }

    func recordDiagnostics(for session: LSPSession, serverId: String) {
        diagnostics[session.url.standardizedFileURL.path, default: [:]][serverId] = session.diagnostics(for: serverId)
        statusChanged()
        problemsChanged()
    }

    /// Cheap file-event forwarding for the integrator (created=1, changed=2, deleted=3).
    func fileEvents(_ events: [(url: URL, type: Int)]) {
        for inst in instances.values where inst.isInitialized {
            let rp = inst.root.path + "/"
            let changes = events.filter { $0.url.path.hasPrefix(rp) }.map { ["uri": $0.url.absoluteString, "type": $0.type] as [String: Any] }
            if !changes.isEmpty { inst.client?.notify("workspace/didChangeWatchedFiles", ["changes": changes]) }
        }
    }

    func diagnosticCounts(for url: URL) -> (errors: Int, warnings: Int) {
        guard let all = diagnostics[url.standardizedFileURL.path] else { return (0, 0) }
        var e = 0, w = 0
        for d in all.values.joined() { if d.severity == 1 { e += 1 } else if d.severity == 2 { w += 1 } }
        return (e, w)
    }

    // MARK: Roots and executables

    func projectRoot(for file: URL, config: LanguageServerConfig) -> URL? {
        let markers = config.rootMarkers
        let fm = FileManager.default
        let home = NSHomeDirectory()
        var dir = file.deletingLastPathComponent().standardizedFileURL
        while dir.path != "/" && dir.path != home {
            if markers.contains(where: { fm.fileExists(atPath: dir.appendingPathComponent($0).path) }) { return dir }
            dir = dir.deletingLastPathComponent()
        }
        return config.requireRootMarker ? nil : file.deletingLastPathComponent().standardizedFileURL
    }

    private func searchDirs() -> [String] {
        let fm = FileManager.default
        var dirs = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let nvm = NSHomeDirectory() + "/.nvm/versions/node"
        let versions = ((try? fm.contentsOfDirectory(atPath: nvm)) ?? []).sorted {
            $0.compare($1, options: .numeric) == .orderedDescending
        }
        dirs += versions.map { "\(nvm)/\($0)/bin" }
        dirs += ["/opt/homebrew/bin", "/usr/local/bin", NSHomeDirectory() + "/.volta/bin", NSHomeDirectory() + "/.bun/bin",
                 NSHomeDirectory() + "/.npm-global/bin"]
        return dirs
    }

    func resolveExecutable(_ names: [String]) -> String? {
        let key = names.joined(separator: ",")
        if let cached = execCache[key] { return cached }
        let fm = FileManager.default
        var found: String?
        outer: for name in names {
            for d in searchDirs() where fm.isExecutableFile(atPath: d + "/" + name) { found = d + "/" + name; break outer }
        }
        execCache[key] = .some(found)
        return found
    }

    /// Directories prepended to PATH so `#!/usr/bin/env node` scripts find node next to the server script.
    func extraPathDirs(for exe: String) -> [String] {
        var dirs = [(exe as NSString).deletingLastPathComponent]
        if let node = resolveExecutable(["node"]) { dirs.append((node as NSString).deletingLastPathComponent) }
        dirs += ["/opt/homebrew/bin", "/usr/local/bin"]
        return dirs
    }

    /// Forget negative executable lookups (e.g. after the user installs a server).
    func resetExecutableCache() { execCache.removeAll() }
}

