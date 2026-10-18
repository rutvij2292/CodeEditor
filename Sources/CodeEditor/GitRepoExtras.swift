import Foundation

// MARK: models

struct GitSummary: Equatable {
    var branch: String
    var ahead: Int
    var behind: Int
    var changes: Int
    var conflicts: Int
    var staged: Int
    static let empty = GitSummary(branch: "", ahead: 0, behind: 0, changes: 0, conflicts: 0, staged: 0)
}

struct GitCommit: Equatable {
    let hash: String
    let shortHash: String
    let author: String
    let relativeDate: String
    let timestamp: TimeInterval
    let refs: [String]
    let subject: String
    let parents: [String]
}

struct GitFileChange: Equatable {
    /// A, M, D, R, C, T
    let status: String
    let path: String
    let oldPath: String?
}

struct GitStash: Equatable {
    let index: Int
    let ref: String
    let message: String
    let date: Date
}

struct BlameLine: Equatable {
    let line: Int
    let hash: String
    let shortHash: String
    let author: String
    let date: Date
    let summary: String
    var isUncommitted: Bool { hash.allSatisfy { $0 == "0" } }
}

struct GitPushPreview {
    var branch: String
    var upstream: String?
    var remote: String?
    var commits: [GitCommit]
    var newBranch: Bool { upstream == nil }
}

enum GitOperation: String {
    case merge, rebase, cherryPick, revert
    var title: String {
        switch self {
        case .merge: return "Merge"
        case .rebase: return "Rebase"
        case .cherryPick: return "Cherry-pick"
        case .revert: return "Revert"
        }
    }
}

enum GitResetMode: String { case soft, mixed, hard }

// MARK: service

extension GitRepo {
    /// `.git` is a file in linked worktrees (and submodules).
    var isLinkedWorktree: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path, isDirectory: &isDir) && !isDir.boolValue
    }

    // MARK: operations in progress

    func operationInProgress() -> GitOperation? {
        let dir = gitDir
        func has(_ n: String) -> Bool { FileManager.default.fileExists(atPath: dir.appendingPathComponent(n).path) }
        if has("rebase-merge") || has("rebase-apply") { return .rebase }
        if has("CHERRY_PICK_HEAD") { return .cherryPick }
        if has("REVERT_HEAD") { return .revert }
        if has("MERGE_HEAD") { return .merge }
        return nil
    }

    func continueOperation(_ op: GitOperation) throws {
        switch op {
        case .merge: try git(["commit", "--no-edit"])
        case .rebase: try git(["rebase", "--continue"])
        case .cherryPick: try git(["cherry-pick", "--continue"])
        case .revert: try git(["revert", "--continue"])
        }
    }

    func abortOperation(_ op: GitOperation) throws {
        switch op {
        case .merge: try git(["merge", "--abort"])
        case .rebase: try git(["rebase", "--abort"])
        case .cherryPick: try git(["cherry-pick", "--abort"])
        case .revert: try git(["revert", "--abort"])
        }
    }

    // MARK: push preview

    func pushPreview() throws -> GitPushPreview {
        let info = try branchInfo()
        if info.detached { throw GitError(message: "HEAD is detached; check out a branch to push") }
        if !hasHead { throw GitError(message: "Nothing to push: no commits yet") }
        if let up = info.upstream,
           let commits = try? logCommits(["@{u}..HEAD"], limit: 200) {
            let remote = up.split(separator: "/").first.map(String.init)
            return GitPushPreview(branch: info.name, upstream: up, remote: remote, commits: commits)
        }
        let remotes = try text(["remote"]).split(separator: "\n").map(String.init)
        guard let remote = remotes.contains("origin") ? "origin" : remotes.first else {
            throw GitError(message: "No remote configured")
        }
        // no upstream: everything not yet on that remote
        let commits = try logCommits(["HEAD", "--not", "--remotes=\(remote)"], limit: 200)
        return GitPushPreview(branch: info.name, upstream: nil, remote: remote, commits: commits)
    }

    // MARK: log

    private static let logFormat = "--format=%x1e%H%x1f%h%x1f%an%x1f%ar%x1f%ct%x1f%D%x1f%s%x1f%P"

    private func parseCommits(_ data: Data) -> [GitCommit] {
        String(decoding: data, as: UTF8.self).split(separator: "\u{1e}").compactMap { rec in
            let f = rec.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 8 else { return nil }
            let refs = f[5].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return GitCommit(hash: f[0].trimmingCharacters(in: .whitespacesAndNewlines), shortHash: f[1], author: f[2], relativeDate: f[3],
                             timestamp: TimeInterval(f[4]) ?? 0, refs: refs, subject: f[6],
                             parents: f[7].split(separator: " ").map(String.init))
        }
    }

    func logCommits(_ revArgs: [String], skip: Int = 0, limit: Int, extra: [String] = [], paths: [String] = [],
                    stdin: Data? = nil) throws -> [GitCommit] {
        var args = ["log", Self.logFormat, "--max-count=\(limit)", "--no-color"]
        if skip > 0 { args.append("--skip=\(skip)") }
        args += extra + revArgs
        if !paths.isEmpty { args += ["--"] + paths }
        return parseCommits(try git(args, optionalLocks: true, input: stdin))
    }

    /// One page of history for the current branch. `query` matches message, author or hash prefix (case-insensitive).
    /// `path` + `follow` lists the history of one file across renames.
    func log(skip: Int, limit: Int, query: String? = nil, path: String? = nil, follow: Bool = false) throws -> [GitCommit] {
        guard hasHead else { return [] }
        let paths = path.map { [$0] } ?? []
        let q = query?.trimmingCharacters(in: .whitespaces) ?? ""
        if q.isEmpty {
            return try logCommits(["HEAD"], skip: skip, limit: limit, extra: follow && path != nil ? ["--follow"] : [], paths: paths)
        }
        // git ANDs --grep and --author, so collect both hash sets and show the union
        var hashes: [String] = []
        var seen = Set<String>()
        func collect(_ extra: [String]) throws {
            var args = ["log", "--format=%H", "--max-count=5000", "-i", "--fixed-strings"] + extra + ["HEAD"]
            if !paths.isEmpty { args += ["--"] + paths }
            for h in try text(args).split(separator: "\n") where seen.insert(String(h)).inserted { hashes.append(String(h)) }
        }
        try collect(["--grep=\(q)"])
        try collect(["--author=\(q)"])
        if q.count >= 4, q.allSatisfy({ $0.isHexDigit }),
           let full = try? text(["rev-parse", "--verify", "-q", q + "^{commit}"]).trimmingCharacters(in: .whitespacesAndNewlines),
           !full.isEmpty, seen.insert(full).inserted { hashes.append(full) }
        guard !hashes.isEmpty else { return [] }
        return try logCommits([], skip: skip, limit: limit, extra: ["--no-walk=sorted", "--stdin"],
                              stdin: Data(hashes.joined(separator: "\n").utf8))
    }

    /// Files changed by a commit (against its first parent).
    func commitFiles(_ rev: String) throws -> [GitFileChange] {
        let data = try git(["show", "--first-parent", "-m", "--name-status", "-M", "--format=", "-z", rev], optionalLocks: true)
        let t = data.split(separator: 0, omittingEmptySubsequences: true).map { String(decoding: $0, as: UTF8.self) }
        var out: [GitFileChange] = []
        var i = 0
        while i < t.count {
            let st = t[i]; i += 1
            let letter = String(st.prefix(1))
            if letter == "R" || letter == "C" {
                guard i + 1 < t.count else { break }
                out.append(GitFileChange(status: letter, path: t[i + 1], oldPath: t[i])); i += 2
            } else {
                guard i < t.count else { break }
                out.append(GitFileChange(status: letter, path: t[i], oldPath: nil)); i += 1
            }
        }
        return out
    }

    /// Content of `path` at `rev`; nil when the file does not exist there.
    func content(of path: String, at rev: String) throws -> String? {
        guard let data = try? git(["show", "\(rev):\(path)"]) else { return nil }
        if data.count > Self.maxTextBytes { throw GitError(message: "File too large to diff") }
        if data.prefix(8000).contains(0) { throw GitError(message: "Binary file") }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }

    /// Old and new content of one file of a commit for a side-by-side diff.
    func commitDiffSides(rev: String, file: GitFileChange) throws -> (old: String, new: String) {
        let parent = (try? text(["rev-parse", "--verify", "-q", rev + "^"]))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let old = parent.isEmpty ? "" : (try content(of: file.oldPath ?? file.path, at: parent) ?? "")
        let new = try content(of: file.path, at: rev) ?? ""
        return (old, new)
    }

    // MARK: history rewriting / navigation

    func checkoutRevision(_ rev: String) throws { try git(["checkout", "--detach", rev]) }

    func createBranch(_ name: String, at rev: String, checkout: Bool) throws {
        if checkout { try git(["checkout", "-b", name, rev]) } else { try git(["branch", name, rev]) }
    }

    private func isMergeCommit(_ rev: String) -> Bool {
        let line = (try? text(["rev-list", "--parents", "-n", "1", rev])) ?? ""
        return line.split(separator: " ").count > 2
    }

    func cherryPick(_ rev: String) throws {
        try git(["cherry-pick"] + (isMergeCommit(rev) ? ["-m", "1"] : []) + [rev])
    }

    func revertCommit(_ rev: String) throws {
        try git(["revert", "--no-edit"] + (isMergeCommit(rev) ? ["-m", "1"] : []) + [rev])
    }

    func reset(to rev: String, mode: GitResetMode) throws { try git(["reset", "--\(mode.rawValue)", rev]) }

    // MARK: stash

    func stashPush(message: String, includeUntracked: Bool) throws {
        let before = try stashList().count
        var args = ["stash", "push"]
        if includeUntracked { args.append("--include-untracked") }
        let m = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if !m.isEmpty { args += ["-m", m] }
        try git(args)
        if try stashList().count == before { throw GitError(message: "No local changes to save") }
    }

    func stashList() throws -> [GitStash] {
        let out = try text(["stash", "list", "--format=%gd%x1f%gs%x1f%ct"])
        return out.split(separator: "\n").enumerated().compactMap { (i, line) in
            let f = line.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 3 else { return nil }
            return GitStash(index: i, ref: f[0], message: f[1], date: Date(timeIntervalSince1970: TimeInterval(f[2]) ?? 0))
        }
    }

    func stashApply(index: Int) throws { try git(["stash", "apply", "stash@{\(index)}"]) }
    func stashPop(index: Int) throws { try git(["stash", "pop", "stash@{\(index)}"]) }
    func stashDrop(index: Int) throws { try git(["stash", "drop", "stash@{\(index)}"]) }

    // MARK: blame

    func blame(path: String) throws -> [BlameLine] {
        parseBlame(try git(["blame", "--porcelain", "--", path], optionalLocks: true))
    }

    /// Blame of an unsaved buffer: the content replaces the working copy (`--contents -`).
    func blameForBuffer(path: String, content: String) throws -> [BlameLine] {
        parseBlame(try git(["blame", "--porcelain", "--contents", "-", "--", path], optionalLocks: true, input: Data(content.utf8)))
    }

    private func parseBlame(_ data: Data) -> [BlameLine] {
        struct Meta { var author = "", time: TimeInterval = 0, summary = "" }
        var metas: [String: Meta] = [:]
        var out: [BlameLine] = []
        var cur: (hash: String, line: Int)?
        var curMeta = Meta()
        for sub in String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(sub)
            if line.hasPrefix("\t") {
                guard let c = cur else { continue }
                let m = metas[c.hash] ?? curMeta
                metas[c.hash] = m
                out.append(BlameLine(line: c.line, hash: c.hash, shortHash: String(c.hash.prefix(8)), author: m.author,
                                     date: Date(timeIntervalSince1970: m.time), summary: m.summary))
                cur = nil
                continue
            }
            if cur == nil {
                let p = line.split(separator: " ")
                if p.count >= 3, p[0].count == 40, let final = Int(p[2]) {
                    cur = (String(p[0]), final)
                    curMeta = metas[String(p[0])] ?? Meta()
                }
                continue
            }
            if line.hasPrefix("author ") { curMeta.author = String(line.dropFirst(7)) }
            else if line.hasPrefix("author-time ") { curMeta.time = TimeInterval(line.dropFirst(12)) ?? 0 }
            else if line.hasPrefix("summary ") { curMeta.summary = String(line.dropFirst(8)) }
            if let c = cur, line.hasPrefix("summary ") { metas[c.hash] = curMeta }
        }
        return out
    }

    // MARK: hooks

    private static let gitVersion: (Int, Int)? = {
        guard let out = try? execute(["--version"], in: URL(fileURLWithPath: "/")) else { return nil }
        let nums = String(decoding: out, as: UTF8.self).split(separator: " ").compactMap { w -> (Int, Int)? in
            let p = w.split(separator: ".")
            guard p.count >= 2, let a = Int(p[0]), let b = Int(p[1]) else { return nil }
            return (a, b)
        }
        return nums.first
    }()

    static var supportsHookRun: Bool {
        guard let v = gitVersion else { return false }
        return v.0 > 2 || (v.0 == 2 && v.1 >= 36)
    }

    func hookExists(_ name: String) -> Bool {
        guard let p = (try? text(["rev-parse", "--git-path", "hooks/\(name)"]))?.trimmingCharacters(in: .whitespacesAndNewlines),
              !p.isEmpty else { return false }
        let url = p.hasPrefix("/") ? URL(fileURLWithPath: p) : root.appendingPathComponent(p)
        return FileManager.default.isExecutableFile(atPath: url.path)
    }

    func runHook(_ name: String, args: [String], env: [String: String], notes: inout [String]) throws {
        guard hookExists(name) else { return }
        guard Self.supportsHookRun else {
            notes.append("The \(name) hook was skipped: running hooks for partial commits needs git 2.36 or newer.")
            return
        }
        do { try git(["hook", "run", "--ignore-missing", name, "--"] + args, env: env) }
        catch let e as GitError { throw GitError(message: "\(name) hook failed:\n\(e.message)") }
    }
}
