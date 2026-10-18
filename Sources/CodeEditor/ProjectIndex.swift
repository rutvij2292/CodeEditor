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
    private(set) var files: [String] = [] { didSet { if !suppressBlob { rebuildBlob() } } }
    /// Lowercased UTF-8 of every path, concatenated, with `starts[i]..<starts[i+1]` the bytes of `files[i]` (cache-friendly
    /// prefilter for 100k-file projects; no per-keystroke String allocation).
    private var blob: [UInt8] = []
    private var starts: [Int32] = [0]
    private var suppressBlob = false
    private var scanning = false
    private var lastScan = Date.distantPast

    init(root: URL) { self.root = root }

    /// Benchmark / test hook: replaces the file list (e.g. a synthetic 100k-file project).
    func setFilesForBenchmark(_ list: [String]) { files = list }

    private func rebuildBlob() {
        let (b, st) = Self.makeBlob(files)
        blob = b; starts = st
    }

    private static func makeBlob(_ files: [String]) -> ([UInt8], [Int32]) {
        var b: [UInt8] = []
        b.reserveCapacity(files.count * 48)
        var st: [Int32] = [0]
        st.reserveCapacity(files.count + 1)
        for f in files {
            for c in f.utf8 { b.append(c >= 65 && c <= 90 ? c + 32 : c) }   // ASCII lowercase; other bytes untouched
            st.append(Int32(b.count))
        }
        return (b, st)
    }

    /// Rescans unless a scan is running or the last one is fresh.
    func refresh(force: Bool = false, completion: (() -> Void)? = nil) {
        guard !scanning, force || Date().timeIntervalSince(lastScan) > 10 else { completion?(); return }
        scanning = true
        let root = self.root
        let wantVendor = Self.includeVendor
        DispatchQueue.global(qos: .utility).async {
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
            let built = Self.makeBlob(found)
            DispatchQueue.main.async {
                self.vendorLazy = wantVendor && !includeVendor
                if self.vendorLazy { VendorIndex.shared(for: root).prewarmFiles() }
                self.suppressBlob = true
                self.files = found
                self.suppressBlob = false
                self.blob = built.0; self.starts = built.1
                self.lastScan = Date()
                self.scanning = false
                completion?()
            }
        }
    }

    /// Fuzzy file search for Go to File: cheap subsequence prefilter on lowercased paths, then best-alignment scoring of the
    /// FILE NAME first (camelCase-hump aware, like PhpStorm), falling back to the whole relative path for queries with folders.
    func search(_ query: String, limit: Int) -> [(path: String, score: Int)] {
        Perf.measure("index.search") { searchImpl(query, limit: limit) }
    }

    private func searchImpl(_ query: String, limit: Int) -> [(path: String, score: Int)] {
        let typed = query.filter { !$0.isWhitespace }
        guard !typed.isEmpty else { return [] }
        let qBytes = Array(typed.lowercased().utf8)
        let q = Array(typed.utf16)
        let lowerTyped = typed.lowercased()
        // Stage 1: subsequence prefilter over the flat lowercase byte buffer, with a cheap file-name oriented score.
        let qn = qBytes.count
        var cand: [(idx: Int32, cheap: Int32)] = []
        blob.withUnsafeBufferPointer { b in
            qBytes.withUnsafeBufferPointer { qb in
                for i in 0..<files.count {
                    var p = Int(starts[i]); let end = Int(starts[i + 1])
                    var qi = 0
                    while p < end {
                        if b[p] == qb[qi] { qi += 1; if qi == qn { break } }
                        p += 1
                    }
                    guard qi == qn else { continue }
                    // Cheap score: where does the match live? Query contiguous in the file name beats scattered.
                    var nameStart = end
                    var k = end - 1
                    while k >= Int(starts[i]) { if b[k] == 47 { nameStart = k + 1; break }; k -= 1 }
                    if k < Int(starts[i]) { nameStart = Int(starts[i]) }
                    var score: Int32 = 0
                    var m = 0
                    var t = nameStart
                    while t < end, m < qn { if b[t] == qb[m] { m += 1 }; t += 1 }
                    if m == qn { score += 20 }
                    // contiguous run in name
                    var s0 = nameStart
                    while s0 + qn <= end {
                        if b[s0] == qb[0] {
                            var e = 1
                            while e < qn, b[s0 + e] == qb[e] { e += 1 }
                            if e == qn { score += (s0 == nameStart ? 40 : 25); break }
                        }
                        s0 += 1
                    }
                    score -= Int32((end - nameStart) / 4)
                    cand.append((Int32(i), score))
                }
            }
        }
        // Stage 2: when very many files match (short queries), only the best few hundred get the exact scorer.
        let keep = max(limit * 3, 600)
        if cand.count > keep {
            cand.sort { $0.cheap != $1.cheap ? $0.cheap > $1.cheap : $0.idx < $1.idx }
            cand.removeLast(cand.count - keep)
        }
        var scored: [(path: String, score: Int, nameLength: Int)] = []
        for c in cand {
            let path = files[Int(c.idx)]
            let name = path.lastIndex(of: "/").map { String(path[path.index(after: $0)...]) } ?? path
            var score: Int
            if let ns = Fuzzy.score(q, caseAware: true, in: name) {
                score = ns + 60                                             // matches inside the file name beat path-only matches
                if name.lowercased().hasPrefix(lowerTyped) { score += 20 }
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
