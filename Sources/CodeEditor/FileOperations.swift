import Foundation

/// A change made through the file tree that open tabs, the index and Git status must follow.
enum FileChange: Equatable {
    case created(URL)
    case moved(from: URL, to: URL)      // rename and move
    case deleted(URL)
}

/// File-system operations behind the tree's context menu and drag-and-drop. Pure (no UI) so they can be tested headless.
enum FileOperations {
    enum OpError: Error, LocalizedError {
        case invalidName(String), exists(String), intoItself
        var errorDescription: String? {
            switch self {
            case .invalidName(let n): return "“\(n)” is not a valid file name."
            case .exists(let n): return "“\(n)” already exists."
            case .intoItself: return "A folder cannot be moved into itself."
            }
        }
    }

    /// Replaces moving to the Trash in tests.
    static var trasher: (URL) throws -> Void = { url in try FileManager.default.trashItem(at: url, resultingItemURL: nil) }

    static func isValid(name: String) -> Bool {
        let t = name.trimmingCharacters(in: .whitespaces)
        return !t.isEmpty && t != "." && t != ".." && !t.contains("/") && !t.contains(":") && !t.contains("\0")
    }

    @discardableResult
    static func createFile(named name: String, in dir: URL) throws -> URL {
        guard isValid(name: name) else { throw OpError.invalidName(name) }
        let url = dir.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: url.path) else { throw OpError.exists(name) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard FileManager.default.createFile(atPath: url.path, contents: Data()) else { throw CocoaError(.fileWriteUnknown) }
        return url
    }

    @discardableResult
    static func createFolder(named name: String, in dir: URL) throws -> URL {
        guard isValid(name: name) else { throw OpError.invalidName(name) }
        let url = dir.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: url.path) else { throw OpError.exists(name) }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    static func rename(_ url: URL, to newName: String) throws -> URL {
        guard isValid(name: newName) else { throw OpError.invalidName(newName) }
        let dest = url.deletingLastPathComponent().appendingPathComponent(newName)
        if dest.path == url.path { return url }
        // A case-only rename names the same file on a case-insensitive volume.
        let caseOnly = dest.path.lowercased() == url.path.lowercased()
        guard caseOnly || !FileManager.default.fileExists(atPath: dest.path) else { throw OpError.exists(newName) }
        try FileManager.default.moveItem(at: url, to: dest)
        return dest
    }

    /// "a.txt" -> "a copy.txt" -> "a copy 2.txt".
    static func copyName(for url: URL, in dir: URL) -> URL {
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        func candidate(_ n: Int) -> URL {
            let name = n == 1 ? "\(stem) copy" : "\(stem) copy \(n)"
            return dir.appendingPathComponent(ext.isEmpty ? name : name + "." + ext)
        }
        var n = 1
        while FileManager.default.fileExists(atPath: candidate(n).path) { n += 1 }
        return candidate(n)
    }

    @discardableResult
    static func duplicate(_ url: URL) throws -> URL {
        let dest = copyName(for: url, in: url.deletingLastPathComponent())
        try FileManager.default.copyItem(at: url, to: dest)
        return dest
    }

    static func trash(_ url: URL) throws { try trasher(url) }

    /// True when `dir` is `url` itself or inside it.
    static func isInside(_ dir: URL, of url: URL) -> Bool {
        dir.path == url.path || dir.path.hasPrefix(url.path + "/")
    }

    @discardableResult
    static func move(_ url: URL, toDirectory dir: URL, overwrite: Bool = false) throws -> URL {
        if isInside(dir, of: url) { throw OpError.intoItself }
        let dest = dir.appendingPathComponent(url.lastPathComponent)
        if dest.path == url.path { return url }
        if FileManager.default.fileExists(atPath: dest.path) {
            guard overwrite else { throw OpError.exists(dest.lastPathComponent) }
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: url, to: dest)
        return dest
    }

    @discardableResult
    static func copy(_ url: URL, toDirectory dir: URL, overwrite: Bool = false) throws -> URL {
        if isInside(dir, of: url) { throw OpError.intoItself }
        let dest = dir.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: dest.path) {
            guard overwrite else { throw OpError.exists(dest.lastPathComponent) }
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: url, to: dest)
        return dest
    }

    /// Where `path` ends up after `old` moved to `new` (nil if unaffected). Handles files inside moved folders.
    static func remap(path: String, from old: String, to new: String) -> String? {
        if path == old { return new }
        if path.hasPrefix(old + "/") { return new + path.dropFirst(old.count) }
        return nil
    }

    /// Relative path of `url` under `root`, or the full path when outside.
    static func relativePath(_ url: URL, to root: URL?) -> String {
        guard let root, url.path.hasPrefix(root.path + "/") else { return url.path }
        return String(url.path.dropFirst(root.path.count + 1))
    }
}
