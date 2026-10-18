import Foundation

/// Flat list of project files for Go to File. Scanned off the main thread; skips heavy directories.
final class ProjectIndex {
    /// Hidden from the file tree.
    static let treeHidden: Set<String> = ["node_modules", ".git", ".build", "vendor", ".idea", ".DS_Store"]
    /// Not indexed for Go to File and ignored by the file watcher. Entries with "/" match two consecutive path components.
    static let skipNames: Set<String> = treeHidden.union([
        "storage/framework", "storage/logs", "bootstrap/cache", "public/build", "public/hot",
        ".next", ".nuxt", "dist", "coverage", ".cache", ".phpunit.cache",
    ])
    /// Index (and watch) `vendor` too. View menu: "Include vendor in Go to File".
    static var includeVendor: Bool {
        get { UserDefaults.standard.bool(forKey: "includeVendor") }
        set { UserDefaults.standard.set(newValue, forKey: "includeVendor") }
    }

    /// Whether a path relative to the project root lies in a skipped directory (or is a skipped file).
    static func isSkipped(relativePath: String, includeVendor: Bool = ProjectIndex.includeVendor) -> Bool {
        let parts = relativePath.split(separator: "/").map(String.init)
        for (i, name) in parts.enumerated() {
            if name == "vendor", includeVendor { continue }
            if skipNames.contains(name) { return true }
            if i + 1 < parts.count, skipNames.contains(name + "/" + parts[i + 1]) { return true }
        }
        return false
    }

    /// Absolute-path variant (accepts `/private/var` and `/var` spellings of the root).
    static func isSkipped(path: String, under root: URL, includeVendor: Bool = ProjectIndex.includeVendor) -> Bool {
        let base = VCSKind.canonical(root.path), p = VCSKind.canonical(path)
        guard p.hasPrefix(base + "/") else { return false }
        return isSkipped(relativePath: String(p.dropFirst(base.count + 1)), includeVendor: includeVendor)
    }

    let root: URL
    private(set) var files: [String] = [] { didSet { lower = files.map { $0.lowercased() } } }
    private var lower: [String] = []
    private var scanning = false
    private var lastScan = Date.distantPast

    init(root: URL) { self.root = root }

    /// Rescans unless a scan is running or the last one is fresh.
    func refresh(force: Bool = false, completion: (() -> Void)? = nil) {
        guard !scanning, force || Date().timeIntervalSince(lastScan) > 10 else { completion?(); return }
        scanning = true
        let root = self.root
        let includeVendor = Self.includeVendor
        DispatchQueue.global(qos: .userInitiated).async {
            var found: [String] = []
            // The enumerator may report symlink-resolved paths (/var -> /private/var), so accept either spelling.
            var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
            let real = realpath(root.path, &buffer) != nil ? String(cString: buffer) : root.path
            let prefixes = Set([root.path, real]).map { $0.hasSuffix("/") ? $0 : $0 + "/" }
            if let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                                       options: [], errorHandler: { _, _ in true }) {
                for case let url as URL in en {
                    guard let prefix = prefixes.first(where: { url.path.hasPrefix($0) }) else { continue }
                    let rel = String(url.path.dropFirst(prefix.count))
                    let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                    if Self.isSkipped(relativePath: rel, includeVendor: includeVendor) {
                        if isDir { en.skipDescendants() }
                        continue
                    }
                    if isDir { continue }
                    found.append(rel)
                    if found.count >= 100_000 { break }
                }
            }
            found.sort { $0.localizedStandardCompare($1) == .orderedAscending }
            DispatchQueue.main.async {
                self.files = found
                self.lastScan = Date()
                self.scanning = false
                completion?()
            }
        }
    }

    /// Fuzzy file search for Go to File: cheap subsequence prefilter on lowercased paths, full scoring on survivors.
    func search(_ query: String, limit: Int) -> [(path: String, score: Int)] {
        let q = Array(query.lowercased().filter { !$0.isWhitespace })
        guard !q.isEmpty else { return [] }
        let qBytes = Array(String(q).utf8)
        var scored: [(path: String, score: Int)] = []
        for (i, text) in lower.enumerated() {
            var qi = 0
            for b in text.utf8 where qi < qBytes.count && b == qBytes[qi] { qi += 1 }
            guard qi == qBytes.count, let score = Fuzzy.score(q, in: files[i]) else { continue }
            scored.append((files[i], score))
        }
        scored.sort { $0.score > $1.score }
        return Array(scored.prefix(limit))
    }
}
