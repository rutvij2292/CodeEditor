import Foundation

/// User preferences shared by the Settings window and every feature (UserDefaults-backed; in-memory when headless).
/// Setting any value posts `Prefs.didChange` with `userInfo["key"]`. Read values at use time and observe `didChange` to apply live.
enum Prefs {
    static let didChange = Notification.Name("CodeEditor.prefsDidChange")
    private static var memory: [String: Any] = [:]            // used instead of UserDefaults in headless runs

    private static func get<T>(_ key: String, _ fallback: T) -> T {
        if AppEnv.headless { return memory[key] as? T ?? fallback }
        return UserDefaults.standard.object(forKey: key) as? T ?? fallback
    }

    private static func set(_ key: String, _ value: Any) {
        if AppEnv.headless { memory[key] = value } else { UserDefaults.standard.set(value, forKey: key) }
        NotificationCenter.default.post(name: didChange, object: nil, userInfo: ["key": key])
    }

    // MARK: Editor
    /// Font family for code ("" = bundled JetBrains Mono; "System Monospaced" = the system font).
    static var editorFontName: String { get { get("editorFontName", "") } set { set("editorFontName", newValue) } }
    static var editorFontSize: Double { get { get("editorFontSize", 13) } set { set("editorFontSize", min(36, max(8, newValue))) } }
    /// Line height multiple (1.0 = font default).
    static var lineHeightMultiple: Double { get { get("lineHeightMultiple", 1.1) } set { set("lineHeightMultiple", min(2, max(0.9, newValue))) } }
    /// Colour scheme: "auto" follows the appearance using `lightScheme` / `darkScheme`; an explicit scheme id
    /// ("intellijLight", "lightLite", "darcula", "ourDark") forces that scheme (and its light/dark appearance).
    static var colorScheme: String { get { get("colorScheme", "auto") } set { set("colorScheme", newValue) } }
    static var lightScheme: String { get { get("lightScheme", "intellijLight") } set { set("lightScheme", newValue) } }   // intellijLight | lightLite
    static var darkScheme: String { get { get("darkScheme", "darcula") } set { set("darkScheme", newValue) } }           // darcula | ourDark
    /// Programming ligatures (JetBrains Mono has them; PhpStorm's default is off).
    static var editorLigatures: Bool { get { get("editorLigatures", false) } set { set("editorLigatures", newValue) } }
    static var showLineNumbers: Bool { get { get("showLineNumbers", true) } set { set("showLineNumbers", newValue) } }
    static var showIndentGuides: Bool { get { get("showIndentGuides", true) } set { set("showIndentGuides", newValue) } }
    static var highlightCurrentLine: Bool { get { get("highlightCurrentLine", true) } set { set("highlightCurrentLine", newValue) } }
    static var softWrap: Bool { get { get("softWrap", false) } set { set("softWrap", newValue) } }          // existing key
    static var rainbowBrackets: Bool { get { get("bracketPairColorization", true) } set { set("bracketPairColorization", newValue) } }  // existing key
    static var showToolbar: Bool { get { get("showToolbar", true) } set { set("showToolbar", newValue) } }
    static var showBreadcrumbs: Bool { get { get("showBreadcrumbs", true) } set { set("showBreadcrumbs", newValue) } }
    static var foldingEnabled: Bool { get { get("foldingEnabled", true) } set { set("foldingEnabled", newValue) } }
    /// Fold `use` imports / license header comments when a file opens.
    static var foldImportsOnOpen: Bool { get { get("foldImportsOnOpen", true) } set { set("foldImportsOnOpen", newValue) } }
    /// Highlight other occurrences of the identifier under the caret (read / write tints).
    static var highlightOccurrences: Bool { get { get("highlightOccurrences", true) } set { set("highlightOccurrences", newValue) } }
    /// "auto" (Low Power Mode / serious thermal state / battery <= 20 %), "always" or "off". See PowerState.
    static var powerSaver: String { get { get("powerSaver", "auto") } set { set("powerSaver", ["auto", "always", "off"].contains(newValue) ? newValue : "auto") } }
    /// Asynchronous text drawing: "auto" (big files, never in power saver / occluded, self-disables if slower), "on" or "off". See GPUAssist.
    static var gpuAssist: String { get { get("gpuAssist", "auto") } set { set("gpuAssist", ["auto", "on", "off"].contains(newValue) ? newValue : "auto") } }
    static var inlineBlame: Bool { get { get("inlineBlame", true) } set { set("inlineBlame", newValue) } }
    /// Default indentation when neither .editorconfig nor the file's own content decides.
    static var defaultIndentSize: Int { get { get("defaultIndentSize", 4) } set { set("defaultIndentSize", min(8, max(1, newValue))) } }
    static var defaultIndentUsesTabs: Bool { get { get("defaultIndentUsesTabs", false) } set { set("defaultIndentUsesTabs", newValue) } }

    /// Where "Open Project" goes when this instance already has a project: "same" (a window here) or "new" (its own process).
    static var openProjectsIn: String { get { get("openProjectsIn", "same") } set { set("openProjectsIn", newValue == "new" ? "new" : "same") } }

    // MARK: Viewers (Markdown preview, JSON/YAML tree)
    /// View mode remembered per file type: "source" | "split" | "preview". See ViewerKinds.swift.
    static func viewerMode(_ kind: String, fallback: String) -> String { get("viewerMode." + kind, fallback) }
    static func setViewerMode(_ kind: String, _ mode: String) { set("viewerMode." + kind, mode) }

    // MARK: Terminal
    /// Where the terminal lives: "right" (docked beside the editor) or "bottom" (tab in the bottom panel).
    static var terminalDock: String { get { get("terminalDock", "right") } set { set("terminalDock", newValue == "bottom" ? "bottom" : "right") } }
    static var terminalFontName: String { get { get("terminalFontName", "") } set { set("terminalFontName", newValue) } }
    static var terminalFontSize: Double { get { get("terminalFontSize", 12) } set { set("terminalFontSize", min(30, max(8, newValue))) } }
    static var terminalCursorStyle: String { get { get("terminalCursorStyle", "block") } set { set("terminalCursorStyle", newValue) } }   // block | beam | underline
    static var terminalScrollback: Int { get { get("terminalScrollback", 5000) } set { set("terminalScrollback", min(100_000, max(500, newValue))) } }
    /// Shell executable ("" = $SHELL).
    static var terminalShell: String { get { get("terminalShell", "") } set { set("terminalShell", newValue) } }
    /// Extra AI CLI launchers shown in the terminal's Run menu, one per line as `Title|command`.
    static var terminalAgents: String { get { get("terminalAgents", "") } set { set("terminalAgents", newValue) } }
    /// Show a badge/bounce when a background terminal tab produced output and then went quiet (an agent finished).
    static var terminalNotifyOnIdle: Bool { get { get("terminalNotifyOnIdle", true) } set { set("terminalNotifyOnIdle", newValue) } }

    /// Claude Code IDE bridge: loopback-only server + ~/.claude/ide lock file so the `claude` CLI can connect (default on).
    static var claudeBridgeEnabled: Bool { get { get("claudeBridgeEnabled", true) } set { set("claudeBridgeEnabled", newValue) } }

    // MARK: Completion
    /// Identifier characters typed before the completion popup opens on its own (1...4).
    static var completionMinChars: Int { get { get("completionMinChars", 2) } set { set("completionMinChars", min(4, max(1, newValue))) } }
    /// Delay in milliseconds before the automatic completion popup opens (0...1000).
    static var completionDelayMs: Int { get { get("completionDelayMs", 40) } set { set("completionDelayMs", min(1000, max(0, newValue))) } }

    // MARK: Language intelligence
    /// Intelephense licence key (stored in the Keychain by the Settings window; this only caches presence).
    static var intelephenseLicenceConfigured: Bool { get { get("intelephenseLicenceConfigured", false) } set { set("intelephenseLicenceConfigured", newValue) } }

    // MARK: Maintenance (Settings window)
    /// Every key above, for "Restore Defaults" and tests.
    static let allKeys: [String] = [
        "editorFontName", "editorFontSize", "lineHeightMultiple", "colorScheme", "lightScheme", "darkScheme", "editorLigatures", "showLineNumbers", "showIndentGuides", "highlightCurrentLine",
        "softWrap", "bracketPairColorization", "showBreadcrumbs", "showToolbar", "foldingEnabled", "foldImportsOnOpen", "highlightOccurrences", "inlineBlame", "powerSaver", "gpuAssist",
        "defaultIndentSize", "defaultIndentUsesTabs",
        "terminalDock", "terminalFontName", "terminalFontSize", "terminalCursorStyle", "terminalScrollback", "terminalShell",
        "terminalAgents", "terminalNotifyOnIdle", "claudeBridgeEnabled", "completionMinChars", "completionDelayMs", "intelephenseLicenceConfigured",
        "viewerMode.markdown", "viewerMode.json", "viewerMode.yaml",
    ]

    /// Removes the stored values (back to defaults) and posts `didChange` once per key.
    static func reset(_ keys: [String]) {
        for key in keys {
            if AppEnv.headless { memory[key] = nil } else { UserDefaults.standard.removeObject(forKey: key) }
            NotificationCenter.default.post(name: didChange, object: nil, userInfo: ["key": key])
        }
    }
}
