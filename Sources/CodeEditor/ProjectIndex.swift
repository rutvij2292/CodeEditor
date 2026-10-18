import Foundation

/// Flat list of project files for Go to File. Scanned off the main thread; skips heavy directories.
final class ProjectIndex {
    static let skipNames: Set<String> = ["node_modules", ".git", ".build", "vendor", ".idea", ".DS_Store"]
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
        DispatchQueue.global(qos: .userInitiated).async {
            var found: [String] = []
            // The enumerator may report symlink-resolved paths (/var -> /private/var), so accept either spelling.
            var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
            let real = realpath(root.path, &buffer) != nil ? String(cString: buffer) : root.path
            let prefixes = Set([root.path, real]).map { $0.hasSuffix("/") ? $0 : $0 + "/" }
            if let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                                       options: [], errorHandler: { _, _ in true }) {
                for case let url as URL in en {
                    if Self.skipNames.contains(url.lastPathComponent) { en.skipDescendants(); continue }
                    if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { continue }
                    guard let prefix = prefixes.first(where: { url.path.hasPrefix($0) }) else { continue }
                    found.append(String(url.path.dropFirst(prefix.count)))
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
