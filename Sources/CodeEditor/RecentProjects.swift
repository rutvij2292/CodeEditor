import Foundation

enum RecentProjects {
    private static let key = "recentProjects"

    static var all: [URL] {
        (UserDefaults.standard.stringArray(forKey: key) ?? [])
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    static func add(_ url: URL) {
        guard !AppEnv.headless else { return }
        var paths = (UserDefaults.standard.stringArray(forKey: key) ?? []).filter { $0 != url.path }
        paths.insert(url.path, at: 0)
        UserDefaults.standard.set(Array(paths.prefix(15)), forKey: key)
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
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
