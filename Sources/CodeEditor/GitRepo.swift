import Foundation

struct GitError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct GitChange: Equatable {
    let path: String
    let origPath: String?
    let index: Character
    let work: Character
    var isConflict: Bool
    var isUntracked: Bool
    var isStaged: Bool
}

final class GitRepo {
    enum Kind { case added, modified, deleted }
    typealias BranchInfo = (name: String, upstream: String?, ahead: Int, behind: Int, detached: Bool)

    let root: URL
    static let maxTextBytes = 2_000_000
    private static let gitPath = "/usr/bin/git"

    init(root: URL) { self.root = root }

    static func repoRoot(for url: URL) -> URL? {
        guard FileManager.default.isExecutableFile(atPath: gitPath) else { return nil }
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        let dir = exists && !isDir.boolValue ? url.deletingLastPathComponent() : url
        guard let out = try? execute(["rev-parse", "--show-toplevel"], in: dir, optionalLocks: true) else { return nil }
        let path = String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : URL(fileURLWithPath: path)
    }

    // MARK: process

    @discardableResult
    private static func execute(_ args: [String], in dir: URL, optionalLocks: Bool = false) throws -> Data {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: gitPath)
        p.arguments = ["-c", "core.quotepath=off"] + args
        p.currentDirectoryURL = dir
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_EDITOR"] = "true"
        env["GIT_MERGE_AUTOEDIT"] = "no"
        if env["GIT_SSH_COMMAND"] == nil { env["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes" }
        if optionalLocks { env["GIT_OPTIONAL_LOCKS"] = "0" }
        p.environment = env
        let outPipe = Pipe(), errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { throw GitError(message: "Cannot launch git: \(error.localizedDescription)") }
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { errData = errPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        let out = outPipe.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            var msg = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if msg.isEmpty { msg = String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
            throw GitError(message: msg.isEmpty ? "git \(args.first ?? "") failed (exit \(p.terminationStatus))" : msg)
        }
        return out
    }

    @discardableResult
    private func git(_ args: [String], optionalLocks: Bool = false) throws -> Data {
        try Self.execute(args, in: root, optionalLocks: optionalLocks)
    }

    private func text(_ args: [String]) throws -> String {
        String(decoding: try git(args), as: UTF8.self)
    }

    private func decode(_ data: Data) throws -> String {
        if data.count > Self.maxTextBytes { throw GitError(message: "File too large to diff") }
        if data.prefix(8000).contains(0) { throw GitError(message: "Binary file") }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }

    // MARK: status

    func status() throws -> [GitChange] { try statusAndBranch().changes }
    func branchInfo() throws -> BranchInfo { try statusAndBranch().info }

    func statusMap() throws -> [String: GitChange] {
        var map: [String: GitChange] = [:]
        for c in try status() { map[c.path] = c }
        return map
    }

    func statusAndBranch() throws -> (changes: [GitChange], info: BranchInfo) {
        let data = try git(["status", "--porcelain=v2", "-z", "--branch", "--untracked-files=all"], optionalLocks: true)
        let tokens = data.split(separator: 0, omittingEmptySubsequences: true).map { String(decoding: $0, as: UTF8.self) }
        var changes: [GitChange] = []
        var head = "", oid = "", upstream: String?, ahead = 0, behind = 0
        var i = 0
        func field(_ s: String, _ n: Int) -> String {
            // path is the remainder after n space-separated fields
            var idx = s.startIndex, count = 0
            while count < n, let sp = s[idx...].firstIndex(of: " ") { idx = s.index(after: sp); count += 1 }
            return String(s[idx...])
        }
        while i < tokens.count {
            let t = tokens[i]; i += 1
            if t.hasPrefix("# ") {
                let parts = t.dropFirst(2).split(separator: " ", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                switch parts[0] {
                case "branch.head": head = parts[1]
                case "branch.oid": oid = parts[1]
                case "branch.upstream": upstream = parts[1]
                case "branch.ab":
                    let ab = parts[1].split(separator: " ")
                    if ab.count == 2 { ahead = Int(ab[0].dropFirst()) ?? 0; behind = Int(ab[1].dropFirst()) ?? 0 }
                default: break
                }
                continue
            }
            let chars = Array(t)
            guard chars.count > 3 else { continue }
            switch chars[0] {
            case "1":
                let xy = Array(field(t, 1).prefix(2))
                changes.append(GitChange(path: field(t, 8), origPath: nil, index: xy[0], work: xy[1],
                                         isConflict: false, isUntracked: false, isStaged: xy[0] != "."))
            case "2":
                let xy = Array(field(t, 1).prefix(2))
                let orig = i < tokens.count ? tokens[i] : nil
                i += 1
                changes.append(GitChange(path: field(t, 9), origPath: orig, index: xy[0], work: xy[1],
                                         isConflict: false, isUntracked: false, isStaged: xy[0] != "."))
            case "u":
                let xy = Array(field(t, 1).prefix(2))
                changes.append(GitChange(path: field(t, 10), origPath: nil, index: xy[0], work: xy[1],
                                         isConflict: true, isUntracked: false, isStaged: false))
            case "?":
                changes.append(GitChange(path: String(t.dropFirst(2)), origPath: nil, index: "?", work: "?",
                                         isConflict: false, isUntracked: true, isStaged: false))
            default: break
            }
        }
        let detached = head == "(detached)"
        let name = detached ? String(oid.prefix(8)) : head
        return (changes, (name, upstream, ahead, behind, detached))
    }

    // MARK: branches

    func branches() throws -> (local: [String], remote: [String]) {
        func refs(_ ns: String) throws -> [String] {
            try text(["for-each-ref", "--format=%(refname:short)", ns]).split(separator: "\n").map(String.init)
        }
        let remote = try refs("refs/remotes").filter { !$0.hasSuffix("/HEAD") && $0.contains("/") }
        return (try refs("refs/heads"), remote)
    }

    func checkout(_ branch: String) throws {
        // "origin/foo" -> create tracking branch foo
        if let slash = branch.firstIndex(of: "/"), (try? branches().remote.contains(branch)) == true {
            let local = String(branch[branch.index(after: slash)...])
            if (try? branches().local.contains(local)) == true { try git(["checkout", local]) }
            else { try git(["checkout", "--track", branch]) }
            return
        }
        try git(["checkout", branch])
    }

    func createBranch(_ name: String, checkout: Bool) throws {
        if checkout { try git(["checkout", "-b", name]) } else { try git(["branch", name]) }
    }

    // MARK: index / working tree

    func stage(_ paths: [String]) throws {
        // skip paths git no longer knows (e.g. the old name of an already staged rename)
        let tracked = Set(try text(["ls-files", "-z", "--"] + paths).split(separator: "\0").map(String.init))
        let live = paths.filter { tracked.contains($0) || FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path) }
        guard !live.isEmpty else { return }
        try git(["add", "-A", "--"] + live)
    }

    func unstage(_ paths: [String]) throws {
        guard !paths.isEmpty else { return }
        if hasHead { try git(["reset", "-q", "HEAD", "--"] + paths) }
        else { try git(["rm", "-r", "-q", "--cached", "--"] + paths) }
    }

    func discard(_ paths: [String]) throws {
        let map = try statusMap()
        var restore: [String] = [], remove: [String] = []
        for p in paths {
            guard let c = map[p] else { continue }
            if c.isUntracked {
                try? FileManager.default.removeItem(at: root.appendingPathComponent(p))
            } else if c.index == "A" || c.index == "R" || c.index == "C" {
                remove.append(p)
                if let o = c.origPath, c.index == "R" { restore.append(o) }
            } else { restore.append(p) }
        }
        if !remove.isEmpty { try git(["rm", "-r", "-f", "-q", "--"] + remove) }
        if !restore.isEmpty { try git(["restore", "--source=HEAD", "--staged", "--worktree", "--"] + restore) }
    }

    var hasHead: Bool { (try? git(["rev-parse", "--verify", "-q", "HEAD"])) != nil }
    var isMerging: Bool { FileManager.default.fileExists(atPath: gitDir.appendingPathComponent("MERGE_HEAD").path) }

    private var gitDir: URL {
        let p = (try? text(["rev-parse", "--git-dir"]))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ".git"
        return p.hasPrefix("/") ? URL(fileURLWithPath: p) : root.appendingPathComponent(p)
    }

    func lastCommitMessage() throws -> String {
        try text(["log", "-1", "--format=%B"]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func commit(message: String, paths: [String]?, amend: Bool) throws {
        var args = ["commit"]
        let msg = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if msg.isEmpty {
            guard amend else { throw GitError(message: "Commit message is empty") }
            args.append("--no-edit")
        } else { args += ["-m", msg] }
        if amend { args.append("--amend") }
        guard let paths, !paths.isEmpty else { try git(args); return }
        try stage(paths)
        // a partial commit is refused while merging; everything staged is committed then
        if isMerging { try git(args); return }
        let tracked = Set(try text(["ls-files", "-z", "--"] + paths).split(separator: "\0").map(String.init))
        let unknown = paths.contains { !tracked.contains($0) && !FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path) }
        if !unknown { try git(args + ["--only", "--"] + paths); return }
        // staged rename: the old name is gone from the index, so --only cannot name it; park the other staged files instead
        let staged = try text(["diff", "--cached", "--name-only", "--no-renames", "-z"]).split(separator: "\0").map(String.init)
        let others = staged.filter { !paths.contains($0) }
        if !others.isEmpty { try git(["reset", "-q", "--"] + others) }
        defer { if !others.isEmpty { try? stage(others) } }
        try git(args)
    }

    // MARK: remotes

    func fetch() throws { try git(["fetch", "--all", "--prune"]) }
    func pull() throws { try git(["pull", "--no-rebase", "--no-edit"]) }

    func push() throws {
        let info = try branchInfo()
        if info.upstream != nil { try git(["push"]); return }
        let remotes = try text(["remote"]).split(separator: "\n").map(String.init)
        guard let remote = remotes.contains("origin") ? "origin" : remotes.first else {
            throw GitError(message: "No remote configured")
        }
        try git(["push", "-u", remote, "HEAD"])
    }

    // MARK: contents

    private func show(_ spec: String) throws -> String? {
        guard let data = try? git(["show", spec]) else { return nil }
        return try decode(data)
    }

    func headContent(of path: String) throws -> String? { try show("HEAD:\(path)") }
    func indexContent(of path: String) throws -> String? { try show(":0:\(path)") }

    func workingContent(of path: String) throws -> String? {
        let url = root.appendingPathComponent(path)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try decode(data)
    }

    func conflictVersions(of path: String) throws -> (base: String?, ours: String?, theirs: String?) {
        (try show(":1:\(path)"), try show(":2:\(path)"), try show(":3:\(path)"))
    }

    func markResolved(path: String, content: String) throws {
        let url = root.appendingPathComponent(path)
        do { try content.write(to: url, atomically: true, encoding: .utf8) }
        catch { throw GitError(message: "Cannot write \(path): \(error.localizedDescription)") }
        try git(["add", "--", path])
    }

    /// Resolution where the chosen side deleted the file.
    func markResolvedDeleted(path: String) throws {
        try git(["rm", "-q", "-f", "--", path])
    }

    func changedLineRanges(of path: String) throws -> [(kind: Kind, range: Range<Int>)] {
        if !hasHead || (try? git(["cat-file", "-e", "HEAD:\(path)"])) == nil {
            guard let content = try workingContent(of: path), !content.isEmpty else { return [] }
            let n = content.split(separator: "\n", omittingEmptySubsequences: false).count - (content.hasSuffix("\n") ? 1 : 0)
            return n > 0 ? [(.added, 1..<(n + 1))] : []
        }
        let diff = try text(["diff", "-U0", "--no-color", "--no-ext-diff", "HEAD", "--", path])
        var result: [(kind: Kind, range: Range<Int>)] = []
        for line in diff.split(separator: "\n") where line.hasPrefix("@@") {
            // @@ -a[,b] +c[,d] @@
            let parts = line.split(separator: " ")
            guard parts.count >= 3 else { continue }
            func nums(_ s: Substring) -> (Int, Int) {
                let p = s.dropFirst().split(separator: ",")
                return (Int(p.first ?? "") ?? 0, p.count > 1 ? Int(p[1]) ?? 1 : 1)
            }
            let (_, oldCount) = nums(parts[1])
            let (start, count) = nums(parts[2])
            if count == 0 { let at = max(start + 1, 1); result.append((.deleted, at..<(at + 1))) }
            else if oldCount == 0 { result.append((.added, start..<(start + count))) }
            else { result.append((.modified, start..<(start + count))) }
        }
        return result
    }
}
