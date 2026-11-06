import Foundation

/// Plumbing behind the Git menu: tags, remotes, worktrees, patches, clone. No UI, no state, no polling.
struct GitRemote: Equatable { var name: String; var url: String }
struct GitWorktree: Equatable { var path: String; var branch: String?; var isMain: Bool }

extension GitRepo {
    // MARK: tags

    func tags() throws -> [String] {
        try text(["tag", "--list", "--sort=-creatordate"]).split(separator: "\n").map(String.init)
    }

    /// Lightweight tag, or annotated when `message` is non-empty.
    func createTag(_ name: String, at rev: String?, message: String?) throws {
        var args = ["tag"]
        if let m = message, !m.trimmingCharacters(in: .whitespaces).isEmpty { args += ["-a", "-m", m] }
        args.append(name)
        if let rev, !rev.isEmpty { args.append(rev) }
        try git(args)
    }

    func deleteTag(_ name: String) throws { try git(["tag", "-d", name]) }

    // MARK: remotes

    func remoteList() throws -> [GitRemote] {
        try text(["remote", "-v"]).split(separator: "\n").compactMap { line in
            let p = line.split(whereSeparator: { $0 == "\t" || $0 == " " })
            guard p.count >= 3, p[2] == "(fetch)" else { return nil }
            return GitRemote(name: String(p[0]), url: String(p[1]))
        }
    }

    func addRemote(_ name: String, url: String) throws { try git(["remote", "add", name, url]) }
    func removeRemote(_ name: String) throws { try git(["remote", "remove", name]) }
    func setRemoteURL(_ name: String, url: String) throws { try git(["remote", "set-url", name, url]) }
    func renameRemote(_ old: String, to new: String) throws { try git(["remote", "rename", old, new]) }

    // MARK: worktrees

    func worktreeList() throws -> [GitWorktree] {
        var out: [GitWorktree] = []
        var path: String?, branch: String?
        func flush() { if let p = path { out.append(GitWorktree(path: p, branch: branch, isMain: out.isEmpty)) }; path = nil; branch = nil }
        for line in try text(["worktree", "list", "--porcelain"]).split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("worktree ") { flush(); path = String(line.dropFirst(9)) }
            else if line.hasPrefix("branch ") { branch = String(line.dropFirst(7)).replacingOccurrences(of: "refs/heads/", with: "") }
            else if line.isEmpty { flush() }
        }
        flush()
        return out
    }

    /// New worktree on a brand-new branch started at `start` (HEAD when nil).
    func addWorktree(at path: String, newBranch: String, start: String?) throws {
        try git(["worktree", "add", "-b", newBranch, path] + (start.map { [$0] } ?? []))
    }

    func removeWorktree(_ path: String, force: Bool) throws {
        try git(["worktree", "remove"] + (force ? ["--force"] : []) + [path])
    }

    // MARK: patches

    /// Unified diff of everything uncommitted (staged + unstaged, untracked files included as new files), or just `paths`.
    func patchOfLocalChanges(paths: [String]? = nil) throws -> String {
        let status = try status()
        let selected = paths.map(Set.init)
        let untracked = status.filter { $0.isUntracked && (selected?.contains($0.path) ?? true) }.map(\.path)
        // intent-to-add makes `git diff HEAD` include untracked files; undone straight after
        if !untracked.isEmpty { try git(["add", "-N", "--"] + untracked) }
        defer { if !untracked.isEmpty { _ = try? git(["reset", "-q", "--"] + untracked) } }
        let data = try git(["diff", "HEAD", "--binary", "--no-color"] + (paths.map { ["--"] + $0 } ?? []))
        return String(decoding: data, as: UTF8.self)
    }

    func applyPatch(_ file: URL, checkOnly: Bool) throws {
        try git(["apply"] + (checkOnly ? ["--check"] : []) + ["--whitespace=nowarn", file.path])
    }

    // MARK: clone

    /// `git clone url dest` run from `dest`'s parent; returns the new repo root.
    @discardableResult
    static func clone(url: String, into dest: URL) throws -> URL {
        let parent = dest.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try execute(["clone", "--", url, dest.path], in: parent)
        return dest
    }
}
