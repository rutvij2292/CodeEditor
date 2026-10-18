import AppKit

/// Public face of the LSP client. AppDelegate calls `start()` at launch; everything is lazy after that.
enum LanguageServers {
    /// Integrator hook: open `url` at a 1-based line/column (e.g. ProjectWindow.open(url, line:)).
    static var openLocation: ((URL, _ line: Int, _ column: Int) -> Void)?

    /// Called FIRST by both Cmd-click and Cmd-B (go to definition) with the click / caret UTF-16 offset in the tab's text.
    /// Return true to consume the event (the LSP definition request is skipped), false/nil to continue as usual.
    /// Root of the open project window that contains `url` (longest match), if any. Files under vendor/ or node_modules/ then share
    /// the project's language server instead of starting a second one for the nested package (each costs 150–600 MB and re-indexes).
    static var openProjectRoot: ((URL) -> URL?)?
    static var beforeDefinition: ((_ tab: EditorTab, _ utf16Offset: Int) -> Bool)?
    /// Cmd-hover shows LSP docs for the token; return true here for tokens `beforeDefinition` would handle to suppress that.
    static var suppressHoverUnderline: ((_ tab: EditorTab, _ utf16Offset: Int) -> Bool)?

    /// Posted (main thread) whenever any server's state, progress or memory changes.
    static let statusDidChange = LanguageServerManager.statusDidChange

    // problemsDidChange, problems(forRoot:), nextProblem: LSPProblems.swift. findUsages/rename/format: LSPFeatures.swift.

    static func start() {
        let mgr = LanguageServerManager.shared
        mgr.start()
        for config in LanguageServerConfig.table {
            CompletionRegistry.register(LSPCompletionProvider(serverId: config.id), forExtensions: config.extensions)
        }
    }

    /// One-line summary for a status bar, e.g. "Intelephense: indexing 40% · 610 MB". Empty if nothing relevant runs.
    static func statusText(forRoot root: URL) -> String { LanguageServerManager.shared.statusText(forRoot: root) }
    static func statuses() -> [LanguageServerStatus] { LanguageServerManager.shared.statuses() }
    static func diagnosticCounts(for url: URL) -> (errors: Int, warnings: Int) {
        LanguageServerManager.shared.diagnosticCounts(for: url)
    }
    /// created = 1, changed = 2, deleted = 3.
    static func fileEvents(_ events: [(url: URL, type: Int)]) { LanguageServerManager.shared.fileEvents(events) }
    /// Shuts every language server down (e.g. a "Stop language servers" menu item). Open files lose their server
    /// attachment until `restartAll(forRoot:)` or the file is reopened.
    static func stopAll() { LanguageServerManager.shared.stopAll() }
    /// "Restart language servers": relaunches the servers of the project at `root` and re-sends its open files.
    static func restartAll(forRoot root: URL) { LanguageServerManager.shared.restartAll(forRoot: root) }
    /// Per-server on/off switch persisted as `lsp.<id>.enabled` (ids: intelephense, volar, typescript, html, css, json, tailwind).
    static func isEnabled(_ serverId: String) -> Bool { LanguageServerPrefs.isEnabled(serverId) }
    static func setEnabled(_ serverId: String, _ on: Bool) {
        LanguageServerPrefs.setEnabled(serverId, on)
        LanguageServerManager.shared.serverPreferenceChanged(serverId)
    }
    static var serverIds: [(id: String, name: String)] { LanguageServerConfig.table.map { ($0.id, $0.name) } }
    /// True when the file is too big for a language server (> 2 MB or flagged `EditorTab.isLargeFile`).
    static func isLargeFile(_ tab: EditorTab) -> Bool { LanguageServerManager.isLargeFile(tab) }
    /// Optional: installs TypeScript 5 + the Vue TypeScript plugin into ~/Library/Application Support/CodeEditor/servers
    /// for machines without any tsserver (the editor never does this on its own).
    static func installPrivateTypeScript(completion: @escaping (Bool) -> Void) { LanguageServerLaunch.installPrivateTypeScript(completion: completion) }
}
