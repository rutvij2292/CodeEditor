import AppKit

/// Public face of the LSP client. AppDelegate calls `start()` at launch; everything is lazy after that.
enum LanguageServers {
    /// Integrator hook: open `url` at a 1-based line/column (e.g. ProjectWindow.open(url, line:)).
    static var openLocation: ((URL, _ line: Int, _ column: Int) -> Void)?

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
    /// Shuts every language server down (e.g. a "Stop language servers" menu item).
    static func stopAll() { LanguageServerManager.shared.stopAll() }
}
