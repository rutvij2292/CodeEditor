import Foundation

/// Flat list of project files for Go to File. Scanned off the main thread; skips heavy directories.
final class ProjectIndex {
    static let skipNames: Set<String> = ["node_modules", ".git", ".build", "vendor", ".idea", ".DS_Store"]
    let root: URL
    private(set) var files: [String] = []
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
            let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
            if let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                                       options: [], errorHandler: { _, _ in true }) {
                for case let url as URL in en {
                    if Self.skipNames.contains(url.lastPathComponent) { en.skipDescendants(); continue }
                    if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { continue }
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
}
