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

/// Narrowing of the log list: author substring, earliest date, one path.
struct GitLogFilter: Equatable {
    var user: String?
    var since: Date?
    var path: String?
    var isActive: Bool { user != nil || since != nil || path != nil }

    private static let iso: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f
    }()
    /// git arguments for the user / date parts (paths go after `--`).
    var arguments: [String] {
        var a: [String] = []
        if let user { a += ["--author=\(user)", "--fixed-strings"] }
        if let since { a.append("--since=\(Self.iso.string(from: since))") }
        return a
    }
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
    var authorMail = ""
    var committerTime: TimeInterval = 0
    var boundary = false
    var previousHash: String?
    var previousPath: String?
    var isUncommitted: Bool { hash.allSatisfy { $0 == "0" } }
}

/// One commit of a blame result (strings are stored once per commit, not once per line).
struct BlameCommit: Equatable {
    let hash: String
    var author = "", mail = "", summary = "", filename = ""
    var authorTime: TimeInterval = 0, committerTime: TimeInterval = 0
    var boundary = false
    var previousHash: String?, previousPath: String?
    var shortHash: String { String(hash.prefix(8)) }
    var isUncommitted: Bool { hash.allSatisfy { $0 == "0" } }
    var date: Date { Date(timeIntervalSince1970: authorTime) }
}

/// Compact blame of one file: a commit table plus one table index per line (4 bytes per line).
struct BlameData: Equatable {
    var commits: [BlameCommit] = []
    var lineCommit: [UInt32] = []
    var lineCount: Int { lineCommit.count }
    func commitIndex(atLine line: Int) -> Int? {
        guard line >= 0, line < lineCommit.count else { return nil }
        let i = Int(lineCommit[line])
        return i < commits.count ? i : nil
    }
    func commit(atLine line: Int) -> BlameCommit? { commitIndex(atLine: line).map { commits[$0] } }
    /// Approximate resident size.
    var approximateBytes: Int {
        lineCommit.count * 4 + commits.reduce(0) { $0 + 160 + $1.author.utf8.count + $1.mail.utf8.count + $1.summary.utf8.count + $1.filename.utf8.count }
    }
    var lines: [BlameLine] {
        lineCommit.enumerated().compactMap { (i, c) in
            guard Int(c) < commits.count else { return nil }
            let m = commits[Int(c)]
            return BlameLine(line: i + 1, hash: m.hash, shortHash: m.shortHash, author: m.author, date: m.date, summary: m.summary,
                             authorMail: m.mail, committerTime: m.committerTime, boundary: m.boundary,
                             previousHash: m.previousHash, previousPath: m.previousPath)
        }
    }
}

/// Full commit details for the blame popover.
struct GitCommitInfo: Equatable {
    let hash: String
    let author: String
    let mail: String
    let authorTime: TimeInterval
    let message: String
    let fileCount: Int
    let parents: [String]
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

    /// Short name of the current branch's upstream ("origin/main"), nil when it has none.
    func upstreamName() -> String? { (try? branchInfo())?.upstream }

    func pushPreview() throws -> GitPushPreview {
        let info = try branchInfo()
        if info.detached { throw GitError(message: "HEAD is detached; check out a branch to push") }
        if !hasHead { throw GitError(message: "Nothing to push: no commits yet") }
        if let up = info.upstream, (try? pushTarget(info).sameName) == true,
           let commits = try? logCommits(["@{u}..HEAD"], limit: 200) {
            let remote = up.split(separator: "/").first.map(String.init)
            return GitPushPreview(branch: info.name, upstream: up, remote: remote, commits: commits)
        }
        let remote = try pushTarget(info).remote
        // no (same-named) upstream: everything not yet on that remote
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
                             parents: f[7].split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\r" }).map(String.init))
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

    /// One page of history for `rev` (default: the current branch). `query` matches message, author or hash prefix (case-insensitive).
    /// `path` + `follow` lists the history of one file across renames.
    func log(skip: Int, limit: Int, query: String? = nil, path: String? = nil, follow: Bool = false, rev: String = "HEAD",
             filter: GitLogFilter = GitLogFilter()) throws -> [GitCommit] {
        guard hasHead else { return [] }
        let paths = (path ?? filter.path).map { [$0] } ?? []
        let filterArgs = filter.arguments
        let q = query?.trimmingCharacters(in: .whitespaces) ?? ""
        if q.isEmpty {
            return try logCommits([rev], skip: skip, limit: limit, extra: (follow && path != nil ? ["--follow"] : ["--topo-order"]) + filterArgs, paths: paths)
        }
        // git ANDs --grep and --author, so collect both hash sets and show the union
        var hashes: [String] = []
        var seen = Set<String>()
        func collect(_ extra: [String]) throws {
            var args = ["log", "--format=%H", "--max-count=5000", "-i", "--fixed-strings"] + extra + filterArgs + [rev]
            if !paths.isEmpty { args += ["--"] + paths }
            for h in try text(args).split(separator: "\n") where seen.insert(String(h)).inserted { hashes.append(String(h)) }
        }
        try collect(["--grep=\(q)"])
        if filter.user == nil { try collect(["--author=\(q)"]) }
        if q.count >= 4, q.allSatisfy({ $0.isHexDigit }),
           let full = try? text(["rev-parse", "--verify", "-q", q + "^{commit}"]).trimmingCharacters(in: .whitespacesAndNewlines),
           !full.isEmpty, seen.insert(full).inserted { hashes.append(full) }
        guard !hashes.isEmpty else { return [] }
        return try logCommits([], skip: skip, limit: limit, extra: ["--no-walk=sorted", "--stdin"],
                              stdin: Data(hashes.joined(separator: "\n").utf8))
    }

    /// Author names in the recent history, most active first (for the log's User filter).
    func recentAuthors(limit: Int = 30) -> [String] {
        guard hasHead, let out = try? text(["log", "--format=%an", "--max-count=3000", "--no-color"]) else { return [] }
        var counts: [String: Int] = [:]
        for n in out.split(separator: "\n") { counts[String(n), default: 0] += 1 }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(limit).map(\.key)
    }

    /// Files changed by a commit (against its first parent).
    func commitFiles(_ rev: String) throws -> [GitFileChange] {
        parseNameStatus(try git(["show", "--first-parent", "-m", "--name-status", "-M", "--format=", "-z", rev], optionalLocks: true))
    }

    /// Files changed across everything a push would send: against the upstream, or from before the oldest new commit.
    func pushChangedFiles(_ p: GitPushPreview) -> [GitFileChange] {
        guard let base = pushBase(p) else { return [] }
        guard let data = try? git(["diff", "--name-status", "-M", "-z", base, "HEAD"], optionalLocks: true) else { return [] }
        return parseNameStatus(data)
    }

    /// The revision a push is compared against (the empty tree for a root commit).
    func pushBase(_ p: GitPushPreview) -> String? {
        if let up = p.upstream { return up }
        guard let oldest = p.commits.last else { return nil }
        return oldest.parents.isEmpty ? "4b825dc642cb6eb9a060e54bf8d69288fbee4904" : oldest.hash + "^"
    }

    private func parseNameStatus(_ data: Data) -> [GitFileChange] {
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

    /// Cherry-picks several commits in the given order (oldest first) as one sequence, so a conflict stops it and
    /// Continue / Abort cover the rest. `mainline` picks the parent for a single merge commit.
    func cherryPick(_ revs: [String], mainline: Int? = nil) throws {
        guard !revs.isEmpty else { return }
        var args = ["cherry-pick"]
        if let mainline { args += ["-m", String(mainline)] }
        try git(args + revs)
    }

    /// Parent hashes of a commit (empty for a root commit).
    func parentHashes(_ rev: String) -> [String] {
        let line = (try? text(["rev-list", "--parents", "-n", "1", rev])) ?? ""
        return Array(line.split(whereSeparator: { $0 == " " || $0 == "\n" }).dropFirst().map(String.init))
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

    /// `-w` ignores whitespace-only changes; `-M`/`-C` follow moved/copied lines modestly (blame has no `--follow`).
    private static let blameArgs = ["blame", "--porcelain", "-w", "-M", "-C"]

    /// Compact blame of the working-tree file. Fails for untracked, ignored or uncommitted paths.
    func blameData(path: String) throws -> BlameData {
        Self.parseBlameData(try git(Self.blameArgs + ["--", path], optionalLocks: true))
    }

    func blame(path: String) throws -> [BlameLine] { try blameData(path: path).lines }

    /// Blame of an unsaved buffer: the content replaces the working copy (`--contents -`).
    func blameForBuffer(path: String, content: String) throws -> [BlameLine] {
        Self.parseBlameData(try git(Self.blameArgs + ["--contents", "-", "--", path], optionalLocks: true,
                                    input: Data(content.utf8))).lines
    }

    /// Parses `blame --porcelain` output byte-wise (20k lines in a few ms).
    static func parseBlameData(_ data: Data) -> BlameData {
        struct Key: Hashable { var a: UInt64, b: UInt64 }
        var out = BlameData()
        var index: [Key: Int] = [:]
        var cur = -1, finalLine = 0
        func hexValue(_ b: UInt8) -> UInt64? {
            switch b {
            case 48...57: return UInt64(b - 48)
            case 97...102: return UInt64(b - 87)
            default: return nil
            }
        }
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let p = raw.bindMemory(to: UInt8.self)
            let n = p.count
            guard let base = p.baseAddress else { return }
            var pos = 0
            func str(_ a: Int, _ b: Int) -> String { String(decoding: UnsafeBufferPointer(rebasing: p[a..<b]), as: UTF8.self) }
            while pos < n {
                var end = n
                if let nl = memchr(base + pos, 10, n - pos) { end = base.distance(to: nl.assumingMemoryBound(to: UInt8.self)) }
                if p[pos] == 9 {                     // content line
                    if cur >= 0, finalLine > 0 {
                        if finalLine > out.lineCommit.count {
                            out.lineCommit.append(contentsOf: repeatElement(UInt32.max, count: finalLine - out.lineCommit.count))
                        }
                        out.lineCommit[finalLine - 1] = UInt32(cur)
                    }
                    cur = -1; finalLine = 0
                } else if cur < 0 {                  // header: <hash> <orig> <final> [<count>]
                    var sp = pos
                    var valid = true
                    var ka: UInt64 = 0, kb: UInt64 = 0
                    while sp < end, p[sp] != 32 {
                        if let v = hexValue(p[sp]) {
                            let k = sp - pos
                            if k < 16 { ka = ka << 4 | v } else if k < 32 { kb = kb << 4 | v }
                        } else { valid = false }
                        sp += 1
                    }
                    let hl = sp - pos
                    if valid, hl == 40 || hl == 64 {
                        // second number after the hash is the final line number
                        var q = sp + 1, fields = 0, value = 0
                        while q < end, fields < 2 {
                            var num = 0
                            while q < end, p[q] >= 48, p[q] <= 57 { num = num * 10 + Int(p[q] - 48); q += 1 }
                            value = num; fields += 1; q += 1
                        }
                        finalLine = fields == 2 ? value : 0
                        let key = Key(a: ka, b: kb)
                        if let i = index[key] { cur = i } else {
                            cur = out.commits.count
                            index[key] = cur
                            out.commits.append(BlameCommit(hash: str(pos, sp)))
                        }
                    }
                } else {                             // key line of the current commit
                    var sp = pos
                    while sp < end, p[sp] != 32 { sp += 1 }
                    let key = str(pos, sp)
                    // only the first appearance of a commit carries details; skip work for anything else
                    switch key {
                    case "author", "author-mail", "author-time", "committer-time", "summary", "boundary", "previous", "filename": break
                    default: pos = end + 1; continue
                    }
                    let value = sp < end ? str(sp + 1, end) : ""
                    switch key {
                    case "author": out.commits[cur].author = value
                    case "author-mail": out.commits[cur].mail = value.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
                    case "author-time": out.commits[cur].authorTime = TimeInterval(value) ?? 0
                    case "committer-time": out.commits[cur].committerTime = TimeInterval(value) ?? 0
                    case "summary": out.commits[cur].summary = value
                    case "boundary": out.commits[cur].boundary = true
                    case "previous":
                        let parts = value.split(separator: " ", maxSplits: 1).map(String.init)
                        out.commits[cur].previousHash = parts.first
                        out.commits[cur].previousPath = parts.count > 1 ? parts[1] : nil
                    default: out.commits[cur].filename = value
                    }
                }
                pos = end + 1
            }
        }
        return out
    }

    // MARK: identity and commit details

    private static var identityCache: [String: (name: String, email: String)] = [:]
    private static var infoCache: [String: GitCommitInfo] = [:]
    private static let cacheLock = NSLock()

    /// `config user.name / user.email` of this repository (cached; used to show "You").
    func userIdentity() -> (name: String, email: String) {
        let key = root.path
        Self.cacheLock.lock(); let hit = Self.identityCache[key]; Self.cacheLock.unlock()
        if let hit { return hit }
        func cfg(_ k: String) -> String {
            ((try? text(["config", "--get", k])) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let id = (name: cfg("user.name"), email: cfg("user.email"))
        Self.cacheLock.lock(); Self.identityCache[key] = id; Self.cacheLock.unlock()
        return id
    }

    static func forgetCaches() {
        cacheLock.lock(); identityCache.removeAll(); infoCache.removeAll(); cacheLock.unlock()
    }

    /// Message body, author, parents and changed-files count of a commit (cached, at most 300 entries).
    func commitInfo(hash: String) throws -> GitCommitInfo {
        let key = root.path + "|" + hash
        Self.cacheLock.lock(); let hit = Self.infoCache[key]; Self.cacheLock.unlock()
        if let hit { return hit }
        let raw = try text(["show", "-s", "--no-color", "--format=%H%x1f%an%x1f%ae%x1f%at%x1f%P%x1f%B", hash])
        let f = raw.split(separator: "\u{1f}", maxSplits: 5, omittingEmptySubsequences: false).map(String.init)
        guard f.count >= 6 else { throw GitError(message: "Unknown commit") }
        let files = (try? commitFiles(hash).count) ?? 0
        let info = GitCommitInfo(hash: f[0].trimmingCharacters(in: .whitespacesAndNewlines), author: f[1], mail: f[2],
                                 authorTime: TimeInterval(f[3]) ?? 0,
                                 message: f[5].trimmingCharacters(in: .whitespacesAndNewlines), fileCount: files,
                                 parents: f[4].split(separator: " ").map(String.init))
        Self.cacheLock.lock()
        if Self.infoCache.count >= 300 { Self.infoCache.removeAll() }
        Self.infoCache[key] = info
        Self.cacheLock.unlock()
        return info
    }

    /// Current HEAD commit id ("" when there are no commits).
    func headOID() -> String {
        ((try? text(["rev-parse", "--verify", "-q", "HEAD"])) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
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
