import Foundation

enum RecentProjects {
    private static let key = "recentProjects"
    static let limit = 15
    /// Tests substitute a throwaway suite / lock file and enable writes while headless.
    static var store: UserDefaults = .standard
    static var lockURL: URL = InstanceRegistry.directory.appendingPathComponent("recents.lock")
    static var forceEnabled = false

    static var all: [URL] {
        (store.stringArray(forKey: key) ?? [])
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    /// `path` moved to the front of `existing` (deduped, capped at `limit`).
    static func merged(_ existing: [String], adding path: String) -> [String] {
        Array(([path] + existing.filter { $0 != path }).prefix(limit))
    }

    /// Read-modify-write under an inter-process lock, re-reading the stored list inside it, so concurrent Kode
    /// instances adding projects at the same moment don't drop each other's entries.
    static func add(_ url: URL) {
        guard !AppEnv.headless || forceEnabled else { return }
        withLock {
            store.synchronize()
            store.set(merged(store.stringArray(forKey: key) ?? [], adding: url.path), forKey: key)
            store.synchronize()
        }
    }

    static func clear() { withLock { store.removeObject(forKey: key); store.synchronize() } }

    private static func withLock(_ body: () -> Void) {
        try? FileManager.default.createDirectory(at: lockURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(lockURL.path, O_RDWR | O_CREAT, 0o600)
        if fd >= 0 { flock(fd, LOCK_EX) }
        body()
        if fd >= 0 { flock(fd, LOCK_UN); close(fd) }
    }
}

/// Recently opened files per project, so Recent Files also lists files whose tabs were closed.
enum RecentFiles {
    private static func key(_ root: URL) -> String { "recentFiles:" + root.path }

    static func all(for root: URL) -> [String] {
        (UserDefaults.standard.stringArray(forKey: key(root)) ?? []).filter { FileManager.default.fileExists(atPath: $0) }
    }

    static func add(_ file: URL, in root: URL) {
        guard !AppEnv.headless else { return }
        var paths = (UserDefaults.standard.stringArray(forKey: key(root)) ?? []).filter { $0 != file.path }
        paths.insert(file.path, at: 0)
        UserDefaults.standard.set(Array(paths.prefix(50)), forKey: key(root))
    }
}
