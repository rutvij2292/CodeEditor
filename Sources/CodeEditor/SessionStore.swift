import Foundation

/// Per-project window state, restored when the project is opened again.
struct Session: Codable, Equatable {
    struct TabState: Codable, Equatable {
        var path: String
        var caret: Int
        var scrollY: Double
    }
    struct BottomState: Codable, Equatable {
        var visible: Bool
        var selected: String?
        var height: Double
    }
    var tabs: [TabState] = []
    var selected: String?
    /// x, y, width, height
    var windowFrame: [Double]?
    var sidebarWidth: Double?
    var bottom: BottomState?
    var expanded: [String] = []
}

enum SessionStore {
    /// Overridable so tests never touch the real Application Support folder.
    static var directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("CodeEditor/sessions")
    /// Tests flip this instead of setting CE_RESTORE.
    static var forceEnabled = false

    /// Verification runs (CE_SNAPSHOT / CE_SELFTEST) never read or write sessions unless CE_RESTORE=1.
    static var enabled: Bool {
        if forceEnabled { return true }
        if let v = getenv("CE_RESTORE"), String(cString: v) == "1" { return true }
        return !AppEnv.headless
    }

    /// Stable 64-bit FNV-1a of the project path (Swift's own hashing is randomized per launch).
    static func hash(_ path: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in path.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return String(h, radix: 16)
    }

    static func fileURL(for root: URL) -> URL { directory.appendingPathComponent(hash(root.standardizedFileURL.path) + ".json") }

    static func save(_ session: Session, for root: URL) {
        guard enabled else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(session).write(to: fileURL(for: root), options: .atomic)
        } catch {
            fputs("session save failed: \(error)\n", stderr)
        }
    }

    static func load(for root: URL) -> Session? {
        guard enabled, let data = try? Data(contentsOf: fileURL(for: root)) else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    // Windows that were open when the app quit (reopened on next launch).

    private static let reopenKey = "reopenWindows"
    private static let reopenRoots = "openWindowRoots"

    static var reopenOnLaunch: Bool {
        get { UserDefaults.standard.object(forKey: reopenKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: reopenKey) }
    }

    static func rememberOpenWindows(_ roots: [URL]) {
        guard enabled else { return }
        UserDefaults.standard.set(roots.map(\.path), forKey: reopenRoots)
    }

    static func windowsToReopen() -> [URL] {
        guard enabled, reopenOnLaunch else { return [] }
        return (UserDefaults.standard.stringArray(forKey: reopenRoots) ?? [])
            .filter { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }
}
