import Foundation

/// What the user accepted from the completion popup, per project: a tiny frecency table (<= 6 projects x 150 names, a few KB)
/// that nudges those names up in the ranking. Loaded lazily on the first completion, written only when something is accepted
/// (no timers, no polling).
final class CompletionHistory {
    static let shared = CompletionHistory()

    private static let defaultsKey = "completion.history.v1"
    private static let maxProjects = 6, maxNames = 150

    private var loaded = false
    private var projects: [String: [String: Int]] = [:]
    private var recent: [String] = []                       // project keys, most recent last
    private var keyCache: [String: String] = [:]            // directory -> project key

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard !AppEnv.headless || ProcessInfo.processInfo.environment["CE_COMPLETION_HISTORY"] != nil,
              let s = UserDefaults.standard.string(forKey: Self.defaultsKey), let d = s.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
        projects = (o["p"] as? [String: [String: Int]]) ?? [:]
        recent = (o["r"] as? [String]) ?? []
    }

    private func save() {
        guard !AppEnv.headless else { return }
        guard let d = try? JSONSerialization.data(withJSONObject: ["p": projects, "r": recent]), let s = String(data: d, encoding: .utf8) else { return }
        UserDefaults.standard.set(s, forKey: Self.defaultsKey)
    }

    /// Nearest ancestor of `url` that looks like a project root (cached per directory).
    func projectKey(for url: URL) -> String {
        let dir = url.deletingLastPathComponent().path
        if let k = keyCache[dir] { return k }
        let fm = FileManager.default
        var d = dir, found = ""
        for _ in 0..<14 {
            for marker in [".git", "composer.json", "package.json", "pyproject.toml", "requirements.txt"] where fm.fileExists(atPath: d + "/" + marker) { found = d; break }
            if !found.isEmpty { break }
            let parent = (d as NSString).deletingLastPathComponent
            if parent == d || parent.isEmpty { break }
            d = parent
        }
        if found.isEmpty { found = "~" + url.pathExtension.lowercased() }
        if keyCache.count > 200 { keyCache.removeAll() }
        keyCache[dir] = found
        return found
    }

    /// 0 = never accepted here, 1 = once, 2 = repeatedly.
    func level(_ name: String, project: String) -> Int {
        load()
        guard let n = projects[project]?[name] else { return 0 }
        return n >= 3 ? 2 : 1
    }

    func record(_ name: String, project: String) {
        load()
        var p = projects[project] ?? [:]
        p[name, default: 0] += 1
        if p.count > Self.maxNames {                         // age: halve everything, drop what fell to zero
            for (k, v) in p { if v <= 1 { p[k] = nil } else { p[k] = v / 2 } }
            if p.count > Self.maxNames { p = Dictionary(uniqueKeysWithValues: p.sorted { $0.value > $1.value }.prefix(Self.maxNames).map { ($0.key, $0.value) }) }
        }
        projects[project] = p
        recent.removeAll { $0 == project }
        recent.append(project)
        while recent.count > Self.maxProjects, let old = recent.first { recent.removeFirst(); projects[old] = nil }
        save()
    }

    func reset() { projects = [:]; recent = []; loaded = true; UserDefaults.standard.removeObject(forKey: Self.defaultsKey) }
}
