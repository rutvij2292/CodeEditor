import AppKit

/// Git status classes used to colour tree rows and tab titles. Folders take the strongest class of their contents:
/// conflict > modified > added > untracked.
enum VCSKind: Int, Comparable {
    case untracked = 1, added, modified, conflict

    static func < (a: VCSKind, b: VCSKind) -> Bool { a.rawValue < b.rawValue }

    var color: NSColor {
        switch self {
        case .conflict: return .systemRed
        case .modified: return .systemBlue
        case .added: return .systemGreen
        case .untracked: return .systemBrown
        }
    }

    /// nil for deletions (nothing to colour).
    init?(_ change: GitChange) {
        if change.isConflict { self = .conflict }
        else if change.isUntracked { self = .untracked }
        else if change.index == "A" { self = .added }
        else if change.index == "D" || change.work == "D" { return nil }
        else { self = .modified }
    }

    /// Absolute path -> kind, for changed files and every folder above them (up to the repo root).
    static func kinds(for map: [String: GitChange], repoRoot: URL) -> [String: VCSKind] {
        var result: [String: VCSKind] = [:]
        func raise(_ path: String, _ kind: VCSKind) {
            if let current = result[path], current >= kind { return }
            result[path] = kind
        }
        for (rel, change) in map {
            guard let kind = VCSKind(change) else { continue }
            var path = repoRoot.appendingPathComponent(rel).path
            raise(path, kind)
            while let slash = path.lastIndex(of: "/"), path.count > repoRoot.path.count {
                path = String(path[..<slash])
                raise(path, kind)
            }
        }
        return result
    }

    /// `/private/var/...` and `/var/...` name the same file; compare on one spelling.
    static func canonical(_ path: String) -> String {
        for prefix in ["/private/var", "/private/tmp", "/private/etc"] where path.hasPrefix(prefix) { return String(path.dropFirst(8)) }
        return path
    }
}
