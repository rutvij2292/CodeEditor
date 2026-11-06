import AppKit

/// Rules and per-file analysis for the Problems panel's "Project Errors" tab.
enum ProjectProblemScanner {
    static let maxProblems = 5000
    static let maxFileBytes = 5_000_000
    /// Directory names never scanned (anywhere in the tree): dependencies, build output, caches, IDE folders.
    static let skipDirs: Set<String> = ["vendor", "node_modules", ".git", "storage", "dist", "build", ".next", ".nuxt", "coverage",
                                        ".idea", ".vscode", ".build", "__pycache__"]
    /// Test hook: replaces the real analyzers (any file is then read as text and passed to it).
    /// Number of files `analyzeFile` actually read (test probe: files no engine handles must not be read).
    static var filesRead = 0
    static var analyzerOverride: ((URL, NSString) -> [FileProblems.Diagnostic])?

    /// `relativePath` is relative to the project root.
    static func shouldSkip(relativePath: String, isDirectory: Bool) -> Bool {
        let parts = relativePath.split(separator: "/").map(String.init)
        guard let last = parts.last else { return false }
        let dirs = isDirectory ? parts : Array(parts.dropLast())
        for (i, d) in dirs.enumerated() {
            if skipDirs.contains(d) { return true }
            if i + 1 < dirs.count, (d == "public" && dirs[i + 1] == "build") || (d == "bootstrap" && dirs[i + 1] == "cache") { return true }
        }
        if isDirectory, parts.count >= 2, (parts[parts.count - 2] == "public" && last == "build") || (parts[parts.count - 2] == "bootstrap" && last == "cache") { return true }
        if !isDirectory { let l = last.lowercased(); return l.hasSuffix(".min.js") || l.hasSuffix(".min.css") || l.hasSuffix(".map") }
        return false
    }
}

/// One user-started scan of a project. Walks the tree on a utility queue, one file at a time, keeps only the problems.
final class ProjectScan {
    let root: URL
    /// (files scanned, problems so far); main queue, every 20 files.
    var onProgress: ((Int, Int) -> Void)?
    /// (results sorted by path, wasCancelled); callback queue.
    var onFinish: (([FileProblems], Bool) -> Void)?
    /// Evaluated on the main queue between files; while true the scan waits (no timer: a short sleep loop on the scan queue).
    var isPaused: (() -> Bool)?
    /// Queue the callbacks run on (main by default; tests use their own).
    var callbackQueue: DispatchQueue = .main

    private let lock = NSLock()
    private var _cancelled = false
    private let queue = DispatchQueue(label: "kode.project-scan", qos: .utility)

    init(root: URL) { self.root = root }

    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return _cancelled }
    func cancel() { lock.lock(); _cancelled = true; lock.unlock() }

    func start() {
        queue.async { [self] in
            var results: [FileProblems] = []
            var total = 0, scanned = 0
            let rootPath = root.path
            let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsPackageDescendants])
            while let url = en?.nextObject() as? URL {
                if cancelled || total >= ProjectProblemScanner.maxProblems { break }
                var rel = url.path
                if rel.hasPrefix(rootPath + "/") { rel = String(rel.dropFirst(rootPath.count + 1)) }
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                if ProjectProblemScanner.shouldSkip(relativePath: rel, isDirectory: isDir) { if isDir { en?.skipDescendants() }; continue }
                if isDir { continue }
                while !cancelled, let paused = isPaused, DispatchQueue.main.sync(execute: paused) { usleep(300_000) }
                if cancelled { break }
                scanned += 1
                if var f = ProjectScan.analyzeFile(url: url, root: root) {
                    let room = ProjectProblemScanner.maxProblems - total
                    if f.diagnostics.count > room { f.diagnostics = Array(f.diagnostics.prefix(room)) }
                    total += f.diagnostics.count
                    results.append(f)
                }
                if scanned % 20 == 0 { let (s, t) = (scanned, total); callbackQueue.async { self.onProgress?(s, t) } }
            }
            let wasCancelled = cancelled
            results.sort { $0.url.path < $1.url.path }
            let (s, t) = (scanned, total)
            callbackQueue.async {
                self.onProgress?(s, t)
                let finish = self.onFinish
                self.onProgress = nil; self.onFinish = nil          // drop the callbacks (they may capture this scan's owner)
                finish?(results, wasCancelled)
            }
        }
    }

    /// Reads and analyses one file with the native engine that handles it. nil: unreadable, binary, over the size cap, no engine, or
    /// no problems. The text is dropped when this returns. Safe to call from any background queue (also used when a file is saved).
    static func analyzeFile(url: URL, root: URL) -> FileProblems? {
        guard ProjectProblemScanner.analyzerOverride != nil || NativePHPDiag.handles(url) || NativeJS.handles(url) || NativePy.handles(url) else { return nil }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        guard size > 0, size <= ProjectProblemScanner.maxFileBytes, let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              !data.prefix(8000).contains(0), let str = String(data: data, encoding: .utf8) else { return nil }
        ProjectProblemScanner.filesRead += 1
        let ns = NSString(string: str)
        var list: [FileProblems.Diagnostic] = []
        if let hook = ProjectProblemScanner.analyzerOverride {
            list = hook(url, ns)
        } else if NativePHPDiag.handles(url) {
            let groups = NativePHPDiag.enabledGroups
            guard !groups.isEmpty else { return nil }
            let found: [NPDiag]
            if let r = FastTier.root(for: url) {
                let fp = FastProject.shared(root: URL(fileURLWithPath: r))
                found = fp.queue.sync { NativePHPDiag.analyze(url: url, text: ns, fp: fp, groups: groups) }
            } else {
                found = NativePHPDiag.analyze(url: url, text: ns, fp: nil, groups: groups)
            }
            list = NativePHPDiag.diagnostics(found, in: ns)
        } else if NativeJS.handles(url) {
            list = NativeJSDiag.diagnostics(NativeJSDiag.analyze(url: url, text: ns), in: ns)
        } else if NativePy.handles(url) {
            let groups = PyDiagGroup.enabledSet
            guard !groups.isEmpty else { return nil }
            let project = NativePy.project(for: url)
            let found = project.queue.sync { PyDiag.analyze(project: project, url: url, text: ns, groups: groups) }
            let table = NPLineStarts(ns)
            list = found.map { d in
                let a = table.position(of: d.range.location), b = table.position(of: NSMaxRange(d.range))
                return FileProblems.Diagnostic(severity: d.severity, message: d.message, line: a.line, column: a.col, endLine: b.line, endColumn: b.col, source: "Python", code: d.code)
            }
        }
        return list.isEmpty ? nil : FileProblems(url: url.standardizedFileURL, diagnostics: list)
    }
}
