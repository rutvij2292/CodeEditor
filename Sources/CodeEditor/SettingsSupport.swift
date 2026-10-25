import AppKit
import CoreText
import Security

// MARK: - Keychain

/// Minimal generic-password Keychain wrapper. Values are never logged.
struct KeychainItem {
    var service: String
    var account: String

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    func read() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func write(_ value: String) -> Bool {
        let data = Data(value.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var q = query
        q[kSecValueData as String] = data
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    func delete() -> Bool {
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

/// The Intelephense licence key. Stored in the macOS Keychain (service "CodeEditor.intelephense") by the Settings window.
enum IntelephenseLicence {
    /// Swappable so tests never touch the real Keychain item.
    static var item = KeychainItem(service: "CodeEditor.intelephense", account: "licence")

    /// The key to pass as `licenceKey` in Intelephense's initializationOptions: Keychain first, then the legacy
    /// sources (`intelephenseLicenceKey` default, ~/intelephense/licence.txt). nil when none is configured.
    static func current() -> String? {
        if let k = item.read()?.trimmingCharacters(in: .whitespacesAndNewlines), !k.isEmpty { return k }
        if let k = UserDefaults.standard.string(forKey: "intelephenseLicenceKey")?.trimmingCharacters(in: .whitespacesAndNewlines), !k.isEmpty { return k }
        if let k = try? String(contentsOfFile: NSHomeDirectory() + "/intelephense/licence.txt", encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !k.isEmpty { return k }
        return nil
    }

    static var isInKeychain: Bool { item.read().map { !$0.isEmpty } ?? false }

    @discardableResult
    static func save(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, item.write(trimmed) else { return false }
        Prefs.intelephenseLicenceConfigured = true
        return true
    }

    static func remove() {
        item.delete()
        Prefs.intelephenseLicenceConfigured = false
    }
}

// MARK: - Fonts

enum FontCatalog {
    /// Name stored in `Prefs.editorFontName` for the default.
    static let systemMonospaced = "System Monospaced"
    private static var cache: [String]?
    private static let queue = DispatchQueue(label: "CodeEditor.fontCatalog", qos: .userInitiated)

    /// Installed families whose faces are fixed-pitch, sorted. Computed once, off the main thread.
    static func monospacedFamilies(completion: @escaping ([String]) -> Void) {
        if let cache { completion(cache); return }
        queue.async {
            let list = computeMonospacedFamilies()
            DispatchQueue.main.async { cache = list; completion(list) }
        }
    }

    static func computeMonospacedFamilies() -> [String] {
        guard let names = CTFontManagerCopyAvailableFontFamilyNames() as? [String] else { return [] }
        var out: [String] = []
        for name in names where !name.hasPrefix(".") {
            let desc = CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute: name] as CFDictionary)
            let font = CTFontCreateWithFontDescriptor(desc, 12, nil)
            guard (CTFontCopyFamilyName(font) as String).caseInsensitiveCompare(name) == .orderedSame else { continue }
            if CTFontGetSymbolicTraits(font).contains(.traitMonoSpace) { out.append(name) }
        }
        return out.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

// MARK: - Memory and disk

enum SystemStats {
    /// The app's own physical footprint (what Activity Monitor's "Memory" column shows).
    static func physFootprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? info.phys_footprint : 0
    }

    static func megabytes(_ bytes: UInt64) -> String { LanguageServerStatus.format(bytes) }

    /// Total size of regular files under `url` (walks on the calling queue).
    static func directorySize(_ url: URL) -> UInt64 {
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]) else { return 0 }
        var total: UInt64 = 0
        for case let f as URL in e {
            guard let v = try? f.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]), v.isRegularFile == true else { continue }
            total += UInt64(v.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}

// MARK: - Defaults

/// Settings that are not (only) in `Prefs`: where each Settings pane's "Restore Defaults" writes.
enum SettingsDefaults {
    static let generalPrefs: [String] = []
    static let editorPrefs = ["editorFontName", "editorFontSize", "lineHeightMultiple", "showLineNumbers", "showIndentGuides",
                              "highlightCurrentLine", "softWrap", "bracketPairColorization", "showBreadcrumbs", "foldingEnabled",
                              "foldImportsOnOpen", "inlineBlame", "defaultIndentSize", "defaultIndentUsesTabs",
                              "completionMinChars", "completionDelayMs"]
    static let terminalPrefs = ["terminalDock", "terminalFontName", "terminalFontSize", "terminalCursorStyle", "terminalScrollback",
                                "terminalShell", "terminalAgents", "terminalNotifyOnIdle", "terminalAgentAlerts"]

    static func restoreGeneral() {
        Theme.setMode(.system)
        AutoSave.focusLossEnabled = true
        AutoSave.tabSwitchEnabled = true
        AutoSave.idleSeconds = 0
        SessionStore.reopenOnLaunch = true
        Formatter.formatOnSave = false
        ProjectIndex.includeVendor = false
        Prefs.reset(["powerSaver", "gpuAssist", "openProjectsIn"])
    }

    static func restoreEditor() {
        Prefs.reset(editorPrefs)     // includes softWrap and bracketPairColorization (same storage as the editor reads)
        NotificationCenter.default.post(name: CodeTextView.softWrapDidChange, object: nil)
        setRainbowBrackets(true)
    }

    static func restoreLanguages() {
        for s in LanguageServers.serverIds { UserDefaults.standard.removeObject(forKey: LanguageServerPrefs.key(s.id)) }
        UserDefaults.standard.removeObject(forKey: NativePHP.nativeOnlyKey)
        NativePHPDiag.resetPrefs()
        UserDefaults.standard.removeObject(forKey: NativePy.enabledKey)
        PyDiagGroup.resetPrefs()
        UserDefaults.standard.removeObject(forKey: NativeWeb.enabledKey)
        UserDefaults.standard.removeObject(forKey: NativeWeb.nativeOnlyKey)
        UserDefaults.standard.removeObject(forKey: NativeJS.enabledKey)
        UserDefaults.standard.removeObject(forKey: NativeJSDiag.enabledKey)
    }

    static func restoreTerminal() {
        Prefs.reset(terminalPrefs)
        UserDefaults.standard.removeObject(forKey: "terminal.agentCommand")
    }

    static func resetAll() {
        restoreGeneral(); restoreEditor(); restoreLanguages(); restoreTerminal()
        UserDefaults.standard.removeObject(forKey: "themeMode")
        for key in ["autoSaveOnFocusLoss", "autoSaveOnTabSwitch", "autoSaveIdleSeconds", "reopenWindows", "formatOnSave", "includeVendor", "openProjectsIn"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

// MARK: - Appliers for preferences whose owner needs a poke

/// Writes `Prefs.softWrap` and tells every editor to re-apply it.
func setSoftWrap(_ on: Bool) {
    Prefs.softWrap = on
    NotificationCenter.default.post(name: CodeTextView.softWrapDidChange, object: nil)
}

/// Rainbow brackets: the colouriser owns its in-memory flag, so go through its toggle (it writes the same defaults key).
func setRainbowBrackets(_ on: Bool) {
    if BracketColorizer.enabled != on { BracketColorizer.shared.toggleBracketColorization(nil) }
}
