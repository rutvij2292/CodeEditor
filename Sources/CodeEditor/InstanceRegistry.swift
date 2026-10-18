import Foundation

/// Cross-process registry of which Kode instance has which project open, so the same folder is never opened twice
/// (a second request focuses the owner instead) and only one instance owns session restore.
/// One small JSON file per project (`instances/projects/<hash>.json`) plus `instances/primary.json`, created atomically
/// (O_EXCL). Entries whose PID is gone (crash / force quit) are treated as stale and removed on the next look.
enum InstanceRegistry {
    struct Entry: Codable, Equatable {
        var pid: Int
        var path: String
    }
    enum Claim: Equatable {
        case claimed
        case heldBy(pid_t)
    }

    /// Overridable so tests never touch the real Application Support folder.
    static var directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("CodeEditor/instances")
    /// Tests flip this; verification runs (CE_SNAPSHOT / CE_SELFTEST) otherwise never read or write the registry.
    static var forceEnabled = false
    static var enabled: Bool { forceEnabled || !AppEnv.headless }
    /// This process; tests substitute another PID to play a second instance.
    static var pid: pid_t = getpid()

    static func isAlive(_ pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno != ESRCH      // EPERM still means the process exists
    }

    private static var projectsDirectory: URL { directory.appendingPathComponent("projects", isDirectory: true) }
    private static var primaryURL: URL { directory.appendingPathComponent("primary.json") }
    private static func entryURL(_ root: URL) -> URL {
        projectsDirectory.appendingPathComponent(SessionStore.hash(root.standardizedFileURL.path) + ".json")
    }

    private static func read(_ url: URL) -> Entry? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Entry.self, from: data)
    }

    /// Creates `url` exclusively with this process's entry; a live foreign owner wins, a stale or own entry is replaced/kept.
    private static func claimFile(_ url: URL, path: String) -> Claim {
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(Entry(pid: Int(pid), path: path)) else { return .claimed }
        for _ in 0..<4 {
            let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
            if fd >= 0 {
                _ = data.withUnsafeBytes { write(fd, $0.baseAddress, data.count) }
                close(fd)
                return .claimed
            }
            guard let e = read(url) else {
                // Unreadable or mid-write by another process: if it stays unreadable, treat it as stale.
                usleep(5_000)
                if read(url) == nil { try? fm.removeItem(at: url) }
                continue
            }
            if pid_t(e.pid) == pid { return .claimed }
            if isAlive(pid_t(e.pid)) { return .heldBy(pid_t(e.pid)) }
            try? fm.removeItem(at: url)
        }
        return .claimed
    }

    private static func releaseFile(_ url: URL) {
        if let e = read(url), pid_t(e.pid) == pid { try? FileManager.default.removeItem(at: url) }
    }

    /// The live OTHER process that has `root` open, if any (stale entries are cleaned up).
    static func owner(of root: URL) -> pid_t? {
        guard enabled else { return nil }
        let url = entryURL(root)
        guard let e = read(url), pid_t(e.pid) != pid else { return nil }
        if isAlive(pid_t(e.pid)) { return pid_t(e.pid) }
        try? FileManager.default.removeItem(at: url)
        return nil
    }

    @discardableResult
    static func claim(_ root: URL) -> Claim {
        guard enabled else { return .claimed }
        return claimFile(entryURL(root), path: root.standardizedFileURL.path)
    }

    static func release(_ root: URL) {
        guard enabled else { return }
        releaseFile(entryURL(root))
    }

    /// Drops every claim this process holds (quit).
    static func releaseAll() {
        guard enabled, let names = try? FileManager.default.contentsOfDirectory(atPath: projectsDirectory.path) else { return }
        for n in names where n.hasSuffix(".json") { releaseFile(projectsDirectory.appendingPathComponent(n)) }
    }

    /// Live projects held by any process (path -> pid); stale entries are removed.
    static func liveProjects() -> [String: pid_t] {
        guard enabled, let names = try? FileManager.default.contentsOfDirectory(atPath: projectsDirectory.path) else { return [:] }
        var out: [String: pid_t] = [:]
        for n in names where n.hasSuffix(".json") {
            let url = projectsDirectory.appendingPathComponent(n)
            guard let e = read(url) else { continue }
            if isAlive(pid_t(e.pid)) { out[e.path] = pid_t(e.pid) } else { try? FileManager.default.removeItem(at: url) }
        }
        return out
    }

    /// The primary instance owns session restore (the reopen-windows list). True when this process is (now) the primary;
    /// always true when the registry is disabled.
    static func claimPrimary() -> Bool {
        guard enabled else { return true }
        return claimFile(primaryURL, path: "") == .claimed
    }

    static func releasePrimary() {
        guard enabled else { return }
        releaseFile(primaryURL)
    }
}
