import AppKit

// The seam between the editor and the native language engines (PHP, Python, JS / TS, Vue, HTML / CSS / Tailwind).
// Every place that used to chain `NativeX.handles(url) || NativeY.handles(url)` asks `NativeEngines` (NativeEngines.swift) instead.
// An engine is one small adapter that forwards to its own implementation; adding or removing an engine is one line in the list
// there. See docs/native-engines.md for what a future plugin would implement.

/// Outcome of a signature-help request (engine-neutral: the payload is an LSP `SignatureHelp` dictionary for `LSPUIParse.signature`).
enum NativeSigOutcome {
    case help([String: Any])
    case notInCall          // the caret is not inside call parentheses: nobody can answer
    case unknown            // inside a call native cannot resolve: the language server may know
}

/// Outcome of Shift-F6.
enum NativeRenameOutcome {
    case handled
    case notNative          // fall back to the language server
    case refused(String)    // native recognised the symbol but cannot rename it safely
}

/// Built-in (non-native) completion providers an engine may take over for a file.
enum NativeBuiltinCompletionTopic { case html, css, tailwind }

/// A declarative Settings > Languages block. `title == nil` continues the previous section (no new heading).
struct NativeSettingsSection {
    var title: String?
    var items: [NativeSettingsItem]
}

enum NativeSettingsItem {
    case toggle(NativeSettingsToggle)
    case choice(NativeSettingsChoice)
}

/// A checkbox row (control column; no label column).
struct NativeSettingsToggle {
    var title: String
    var accessibility: String
    var help: String?
    var get: () -> Bool
    var set: (Bool) -> Void
}

/// A pop-up row with a label in the label column.
struct NativeSettingsChoice {
    var label: String
    var accessibility: String
    var options: [String]
    var get: () -> Int
    var set: (Int) -> Void
}

protocol NativeEngine {
    /// Stable identifier ("php", "python", "js", "vue", "web").
    var id: String { get }
    var displayName: String { get }
    /// Lookup order (hover, Cmd-hover underline, Cmd-B, find usages, signature help): lower asks first, ties keep list order.
    var priority: Int { get }
    /// Completion providers register in this order (stable sort of the list); the PHP engine is last so it wins score ties.
    var completionRank: Int { get }
    /// True when a hit with empty markdown still counts as the answer (PHP, Python) instead of falling through.
    var emptyHoverIsAnswer: Bool { get }
    /// True when the Cmd-hover underline covers the hit's own range instead of the word under the pointer (Vue).
    var underlinesHitRange: Bool { get }
    /// True when files of this engine need the language-server session UI (hover, Cmd-click) even without any external server.
    var providesSessionUI: Bool { get }
    var supportsSignatureHelp: Bool { get }

    func handles(_ url: URL) -> Bool
    /// Hover and Cmd-hover underline. Completes on the main queue; nil declines so the next engine, then the server, is asked.
    func lookup(url: URL, text: NSString, offset: Int, completion: @escaping (NPHit?) -> Void)
    func goToDefinition(in tab: EditorTab, at offset: Int) -> Bool
    /// True when native took the request (results arrive asynchronously).
    func findUsages(_ w: ProjectWindow, tab: EditorTab) -> Bool
    func rename(_ w: ProjectWindow) -> NativeRenameOutcome
    func signatureHelp(url: URL, text: NSString, caret: Int, completion: @escaping (NativeSigOutcome) -> Void)
    func hoverDiagnostics(for tab: EditorTab?) -> [LSPDiagnostic]

    func registerCompletion()
    func startDiagnostics()
    /// File-system change in a project (FSEvents batch).
    func invalidate(root: URL)
    func trimMemory()
    func installMemoryHooks()

    var settingsSections: [NativeSettingsSection] { get }
    /// Removes every preference this engine owns (Settings > Languages > Restore defaults).
    func resetPrefs()
    /// True when this engine replaces the external server `id` (LanguageServerPrefs.isEnabled / launch). `root` is nil when asked
    /// generically; root-specific rules apply only when it is given.
    func suppressesServer(_ id: String, root: URL?) -> Bool
    func suppressesBuiltinCompletion(_ topic: NativeBuiltinCompletionTopic, for url: URL) -> Bool
}

extension NativeEngine {
    var completionRank: Int { 0 }
    var emptyHoverIsAnswer: Bool { false }
    var underlinesHitRange: Bool { false }
    var providesSessionUI: Bool { false }
    var supportsSignatureHelp: Bool { false }
    func goToDefinition(in tab: EditorTab, at offset: Int) -> Bool { false }
    func findUsages(_ w: ProjectWindow, tab: EditorTab) -> Bool { false }
    func rename(_ w: ProjectWindow) -> NativeRenameOutcome { .notNative }
    func signatureHelp(url: URL, text: NSString, caret: Int, completion: @escaping (NativeSigOutcome) -> Void) { completion(.unknown) }
    func hoverDiagnostics(for tab: EditorTab?) -> [LSPDiagnostic] { [] }
    func registerCompletion() {}
    func startDiagnostics() {}
    func invalidate(root: URL) {}
    func trimMemory() {}
    func installMemoryHooks() {}
    var settingsSections: [NativeSettingsSection] { [] }
    func resetPrefs() {}
    func suppressesServer(_ id: String, root: URL?) -> Bool { false }
    func suppressesBuiltinCompletion(_ topic: NativeBuiltinCompletionTopic, for url: URL) -> Bool { false }
}
