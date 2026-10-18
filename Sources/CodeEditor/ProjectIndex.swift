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

    /// Whether `path` lies inside a Composer vendor directory (library file; tabs should open read-only).
    static func isVendor(path: String) -> Bool { VendorIndex.isLibraryFile(URL(fileURLWithPath: path)) }

    let root: URL
    /// With includeVendor and a large vendor tree, vendor files are not loaded into `files`; `search` lists them lazily instead.
    private(set) var vendorLazy = false
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
        let wantVendor = Self.includeVendor
        DispatchQueue.global(qos: .userInitiated).async {
            let includeVendor = wantVendor && VendorIndex.vendorIsSmall(root: root)
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
                self.vendorLazy = wantVendor && !includeVendor
                if self.vendorLazy { VendorIndex.shared(for: root).prewarmFiles() }
                self.files = found
                self.lastScan = Date()
                self.scanning = false
                completion?()
            }
        }
    }

    /// Fuzzy file search for Go to File: cheap subsequence prefilter on lowercased paths, then best-alignment scoring of the
    /// FILE NAME first (camelCase-hump aware, like PhpStorm), falling back to the whole relative path for queries with folders.
    func search(_ query: String, limit: Int) -> [(path: String, score: Int)] {
        let typed = query.filter { !$0.isWhitespace }
        guard !typed.isEmpty else { return [] }
        let qBytes = Array(typed.lowercased().utf8)
        let q = Array(typed.utf16)
        var scored: [(path: String, score: Int, nameLength: Int)] = []
        for (i, text) in lower.enumerated() {
            var qi = 0
            for b in text.utf8 where qi < qBytes.count && b == qBytes[qi] { qi += 1 }
            guard qi == qBytes.count else { continue }
            let path = files[i]
            let name = path.lastIndex(of: "/").map { String(path[path.index(after: $0)...]) } ?? path
            var score: Int
            if let ns = Fuzzy.score(q, caseAware: true, in: name) {
                score = ns + 60                                             // matches inside the file name beat path-only matches
                if name.lowercased().hasPrefix(typed.lowercased()) { score += 20 }
            } else if let ps = Fuzzy.score(q, caseAware: true, in: path) {
                score = ps
            } else { continue }
            scored.append((path, score - Self.noisePenalty(path), name.count))
        }
        scored.sort { a, b in
            if a.score != b.score { return a.score > b.score }
            if a.nameLength != b.nameLength { return a.nameLength < b.nameLength }
            return a.path.count < b.path.count
        }
        return scored.prefix(limit).map { ($0.path, $0.score) }
    }

    /// Application code should outrank tests, docs, build output and fixtures when names match equally well.
    private static func noisePenalty(_ path: String) -> Int {
        if path.hasPrefix("tests/") || path.contains("/tests/") || path.contains("/Tests/") { return 6 }
        if path.hasPrefix("docs/") || path.hasSuffix(".md") { return 8 }
        if path.hasPrefix("storage/") || path.contains("/storage/") { return 14 }
        if path.hasPrefix("public/") || path.contains("/dist/") || path.contains("/build/") { return 10 }
        return 0
    }
}
