import Foundation

// MARK: models

/// One branch row of the branch popup (local or remote-tracking).
struct BranchEntry: Equatable {
    var name: String            // "feature/x" or "origin/feature/x"
    var isRemote: Bool
    var remote: String?         // "origin" for remote branches
    var upstream: String?       // "origin/main" for local branches that track something
    var upstreamGone = false
    var ahead = 0
    var behind = 0
    var hash = ""
    var subject = ""
    var timestamp: TimeInterval = 0
    var isCurrent = false

    /// Name without the remote prefix ("origin/feature/x" -> "feature/x").
    var shortName: String { remote.map { String(name.dropFirst($0.count + 1)) } ?? name }
}

struct BranchList {
    var local: [BranchEntry] = []
    var remote: [BranchEntry] = []
    var tags: [String] = []
    var remotes: [String] = []
    var current: String = ""        // "" when detached
    var detached = false
    var recent: [String] = []       // local branch names, most recent first (current excluded)
}

/// Result of a checkout attempt that did not simply succeed.
enum CheckoutFailure: Error {
    /// Tracked or untracked files that the switch would overwrite.
    case localChanges(files: [String], message: String)
    case other(String)
    var message: String {
        switch self {
        case .localChanges(let files, let m): return files.isEmpty ? m : "Local changes to \(files.count) file\(files.count == 1 ? "" : "s") would be overwritten."
        case .other(let m): return m
        }
    }
}

enum SmartCheckoutOutcome: Equatable {
    case clean                      // nothing needed stashing, or changes re-applied cleanly
    case conflicts([String])        // checkout done; unstashing conflicted, stash kept
}

struct BranchComparison {
    var other: String
    var onlyInOther: [GitCommit]    // commits reachable from `other` but not HEAD
    var onlyInCurrent: [GitCommit]
    var files: [GitFileChange]      // `git diff HEAD other`
}

// MARK: ref name rules

enum GitRefName {
    /// nil when valid, otherwise a short explanation (mirrors `git check-ref-format --branch`, without spawning a process).
    static func validate(_ raw: String) -> String? {
        let n = raw
        if n.isEmpty { return "Enter a branch name" }
        if n == "@" { return "“@” is not a valid branch name" }
        if n.hasPrefix("-") { return "Name cannot start with “-”" }
        if n.hasPrefix("/") || n.hasSuffix("/") { return "Name cannot start or end with “/”" }
        if n.hasSuffix(".") { return "Name cannot end with “.”" }
        if n.contains("..") { return "Name cannot contain “..”" }
        if n.contains("//") { return "Name cannot contain “//”" }
        if n.contains("@{") { return "Name cannot contain “@{”" }
        for ch in n.unicodeScalars {
            if ch.value < 0x20 || ch.value == 0x7f { return "Name cannot contain control characters" }
            if " ~^:?*[\\".unicodeScalars.contains(ch) { return ch == " " ? "Name cannot contain spaces" : "Name cannot contain “\(Character(ch))”" }
        }
        for part in n.split(separator: "/", omittingEmptySubsequences: false) {
            if part.hasPrefix(".") { return "A path part cannot start with “.”" }
            if part.hasSuffix(".lock") { return "A path part cannot end with “.lock”" }
        }
        return nil
    }
}

// MARK: favourites

enum BranchFavorites {
    private static var memory: [String: [String]] = [:]
    private static func key(_ root: URL) -> String { "branchFavorites:" + root.standardizedFileURL.path }

    static func all(for root: URL) -> Set<String> {
        let k = key(root)
        if AppEnv.headless { return Set(memory[k] ?? []) }
        return Set(UserDefaults.standard.stringArray(forKey: k) ?? [])
    }

    @discardableResult
    static func toggle(_ name: String, for root: URL) -> Bool {
        var set = all(for: root)
        let on = !set.contains(name)
        if on { set.insert(name) } else { set.remove(name) }
        let list = set.sorted()
        if AppEnv.headless { memory[key(root)] = list } else { UserDefaults.standard.set(list, forKey: key(root)) }
        return on
    }
}

// MARK: git operations

extension GitRepo {
    private static let fieldSep = "\u{1f}"

    /// All branches in one `for-each-ref` call (ahead/behind, subject and date included), plus tags, remotes and recents.
    func branchList() throws -> BranchList {
        let fmt = ["%(refname)", "%(upstream:short)", "%(upstream:track)", "%(objectname:short)", "%(committerdate:unix)", "%(HEAD)", "%(subject)"]
            .joined(separator: "%1f")
        let out = try text(["for-each-ref", "--format=" + fmt, "refs/heads", "refs/remotes"])
        var list = BranchList()
        let info = try? branchInfo()
        list.current = (info?.detached ?? false) ? "" : (info?.name ?? "")
        list.detached = info?.detached ?? false
        list.remotes = (try? text(["remote"]))?.split(separator: "\n").map(String.init) ?? []
        for line in out.split(separator: "\n") {
            let f = line.split(separator: Character(Self.fieldSep), maxSplits: 6, omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 7 else { continue }
            var e = BranchEntry(name: "", isRemote: false)
            e.hash = f[3]; e.timestamp = TimeInterval(f[4]) ?? 0; e.subject = f[6]; e.isCurrent = f[5] == "*"
            if f[0].hasPrefix("refs/heads/") {
                e.name = String(f[0].dropFirst("refs/heads/".count))
                if !f[1].isEmpty { e.upstream = f[1] }
                let track = f[2]
                if track.contains("gone") { e.upstreamGone = true }
                e.ahead = Self.number(after: "ahead ", in: track)
                e.behind = Self.number(after: "behind ", in: track)
                list.local.append(e)
            } else if f[0].hasPrefix("refs/remotes/") {
                let full = String(f[0].dropFirst("refs/remotes/".count))
                guard !full.hasSuffix("/HEAD"), let slash = full.firstIndex(of: "/") else { continue }
                e.name = full
                e.isRemote = true
                e.remote = String(full[..<slash])
                list.remote.append(e)
            }
        }
        list.tags = (try? text(["for-each-ref", "--sort=-creatordate", "--format=%(refname:short)", "refs/tags"]))?
            .split(separator: "\n").map(String.init) ?? []
        list.recent = recentBranches(existing: Set(list.local.map(\.name)), excluding: list.current)
        return list
    }

    private static func number(after key: String, in s: String) -> Int {
        guard let r = s.range(of: key) else { return 0 }
        return Int(s[r.upperBound...].prefix { $0.isNumber }) ?? 0
    }

    /// Branches recently checked out, newest first (parsed from the HEAD reflog).
    func recentBranches(existing: Set<String>, excluding current: String, limit: Int = 5) -> [String] {
        guard let out = try? text(["reflog", "-n", "400", "--format=%gs"]) else { return [] }
        var seen = Set<String>(), result: [String] = []
        for line in out.split(separator: "\n") {
            guard line.hasPrefix("checkout: moving from "), let to = line.range(of: " to ") else { continue }
            let from = String(line[line.index(line.startIndex, offsetBy: "checkout: moving from ".count)..<to.lowerBound])
            let dest = String(line[to.upperBound...])
            for b in [dest, from] where existing.contains(b) && b != current && seen.insert(b).inserted { result.append(b) }
            if result.count >= limit { break }
        }
        return Array(result.prefix(limit))
    }

    func localBranchExists(_ name: String) -> Bool {
        (try? git(["show-ref", "--verify", "--quiet", "refs/heads/" + name], optionalLocks: true)) != nil
    }

    func resolves(_ rev: String) -> Bool {
        !rev.isEmpty && !rev.hasPrefix("-") && (try? git(["rev-parse", "--verify", "--quiet", rev + "^{commit}"], optionalLocks: true)) != nil
    }

    func hasLocalChanges() -> Bool {
        guard let out = try? git(["status", "--porcelain", "--untracked-files=no"], optionalLocks: true) else { return false }
        return !out.isEmpty
    }

    // MARK: create

    /// Creates `name` at `start` (default: HEAD). `overwrite` resets an existing branch (`-B` / `branch -f`).
    func createBranch(named name: String, from start: String?, checkout: Bool, overwrite: Bool) throws {
        if let problem = GitRefName.validate(name) { throw GitError(message: problem) }
        if !overwrite, localBranchExists(name) { throw GitError(message: "A branch named “\(name)” already exists.") }
        var args = checkout ? ["checkout", overwrite ? "-B" : "-b", name] : ["branch"]
        if !checkout, overwrite { args.append("-f") }
        if !checkout { args.append(name) }
        if let start, !start.isEmpty { args.append(start) }
        try git(args)
    }

    // MARK: checkout

    /// Local name a remote branch is checked out as ("origin/feature/x" -> "feature/x").
    func localName(forRemote full: String, remotes: [String]) -> String {
        if let r = remotes.first(where: { full.hasPrefix($0 + "/") }) { return String(full.dropFirst(r.count + 1)) }
        return full.firstIndex(of: "/").map { String(full[full.index(after: $0)...]) } ?? full
    }

    /// Checks out a local branch, a remote branch (tracking branch created, or the existing local one used), a tag or a revision.
    func checkoutTarget(_ target: String, force: Bool = false) throws {
        let list = try branchList()
        var args = ["checkout"]
        if force { args.append("-f") }
        if list.local.contains(where: { $0.name == target }) {
            args.append(target)
        } else if list.remote.contains(where: { $0.name == target }) {
            let local = localName(forRemote: target, remotes: list.remotes)
            if list.local.contains(where: { $0.name == local }) { args.append(local) }
            else { args += ["--track", "-b", local, target] }
        } else {
            args += ["--detach", target]
        }
        do { try git(args) } catch let e as GitError { throw Self.classifyCheckoutFailure(e.message) }
    }

    static func classifyCheckoutFailure(_ message: String) -> CheckoutFailure {
        guard message.contains("would be overwritten") else { return .other(message) }
        var files: [String] = []
        var collecting = false
        for line in message.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.contains("would be overwritten") { collecting = true; continue }
            if collecting {
                if line.hasPrefix("\t") || line.hasPrefix("    ") { files.append(line.trimmingCharacters(in: .whitespaces)) }
                else if !line.trimmingCharacters(in: .whitespaces).isEmpty { collecting = false }
            }
        }
        return .localChanges(files: files, message: message)
    }

    private var stashTop: String { ((try? text(["rev-parse", "-q", "--verify", "refs/stash"])) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Stash (including untracked) -> checkout -> unstash. The stash is kept when unstashing conflicts.
    func smartCheckout(_ target: String) throws -> SmartCheckoutOutcome {
        let before = stashTop
        try git(["stash", "push", "--include-untracked", "-m", "Linnet smart checkout to \(target)"])
        let stashed = stashTop != before
        do { try checkoutTarget(target) } catch {
            if stashed { _ = try? git(["stash", "pop"]) }       // put the work back before reporting
            throw error
        }
        guard stashed else { return .clean }
        do { try git(["stash", "pop"]); return .clean } catch {
            let conflicted = ((try? status()) ?? []).filter(\.isConflict).map(\.path)
            if conflicted.isEmpty { throw GitError(message: "Checked out \(target), but restoring your changes failed: \((error as? GitError)?.message ?? "unknown error"). They remain in the stash.") }
            return .conflicts(conflicted)
        }
    }

    // MARK: history ops

    func rebaseCurrent(onto other: String) throws { try git(["rebase", other]) }
    func mergeIntoCurrent(_ other: String) throws { try git(["merge", "--no-edit", other]) }

    /// Checks out `branch` and rebases it onto what was current.
    func checkoutAndRebase(_ branch: String) throws {
        let list = try branchList()
        let base = list.detached ? try text(["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines) : list.current
        try checkoutTarget(branch)
        try git(["rebase", base])
    }

    /// Pulls `branch` (a remote branch, or a local branch's upstream) into the current branch.
    func pullIntoCurrent(_ entry: BranchEntry, rebase: Bool) throws {
        let full = entry.isRemote ? entry.name : entry.upstream
        guard let full, let remote = (try branchList().remotes).first(where: { full.hasPrefix($0 + "/") }) else {
            throw GitError(message: "“\(entry.name)” has no remote branch to pull from.")
        }
        let branch = String(full.dropFirst(remote.count + 1))
        try git(["pull", rebase ? "--rebase" : "--no-rebase", "--no-edit", remote, branch])
    }

    // MARK: remote ops

    /// Pushes a local branch, setting its upstream when it has none.
    func pushBranch(_ entry: BranchEntry) throws {
        let remotes = (try? text(["remote"]))?.split(separator: "\n").map(String.init) ?? []
        if let up = entry.upstream, let remote = remotes.first(where: { up.hasPrefix($0 + "/") }) {
            try git(["push", remote, "\(entry.name):\(up.dropFirst(remote.count + 1))"])
            return
        }
        guard let remote = remotes.contains("origin") ? "origin" : remotes.first else { throw GitError(message: "No remote configured") }
        try git(["push", "-u", remote, entry.name])
    }

    func deleteRemoteBranch(_ entry: BranchEntry) throws {
        guard let remote = entry.remote else { return }
        try git(["push", remote, "--delete", entry.shortName])
    }

    // MARK: rename / delete

    func renameBranch(_ old: String, to new: String) throws {
        if let problem = GitRefName.validate(new) { throw GitError(message: problem) }
        if localBranchExists(new) { throw GitError(message: "A branch named “\(new)” already exists.") }
        try git(["branch", "-m", old, new])
    }

    /// `-d` (refuses unmerged work) or `-D`. The message of a refusal contains "not fully merged".
    func deleteLocalBranch(_ name: String, force: Bool) throws { try git(["branch", force ? "-D" : "-d", name]) }

    static func isUnmergedRefusal(_ error: Error) -> Bool { ((error as? GitError)?.message ?? "").contains("not fully merged") }

    // MARK: compare

    func compare(with other: String, limit: Int = 200) throws -> BranchComparison {
        let fmtDiff = try text(["diff", "--name-status", "-M", "HEAD", other])
        var files: [GitFileChange] = []
        for line in fmtDiff.split(separator: "\n") {
            let p = line.split(separator: "\t").map(String.init)
            guard p.count >= 2 else { continue }
            files.append(GitFileChange(status: String(p[0].prefix(1)), path: p.last!, oldPath: p.count > 2 ? p[1] : nil))
        }
        return BranchComparison(other: other,
                                onlyInOther: try logCommits(["HEAD..\(other)"], limit: limit),
                                onlyInCurrent: try logCommits(["\(other)..HEAD"], limit: limit),
                                files: files)
    }

    // MARK: background fetch (throttled)

    private static var lastFetch: [String: Date] = [:]
    private static var fetching = Set<String>()
    private static let fetchLock = NSLock()

    /// Fetches all remotes at low priority unless one ran within `minInterval` seconds. `done(true)` when a fetch happened.
    func fetchThrottled(minInterval: TimeInterval = 60, force: Bool = false, done: @escaping (Bool, String?) -> Void) {
        let key = root.path
        Self.fetchLock.lock()
        let recent = Self.lastFetch[key].map { Date().timeIntervalSince($0) < minInterval } ?? false
        let busy = Self.fetching.contains(key)
        if (!force && recent) || busy { Self.fetchLock.unlock(); DispatchQueue.main.async { done(false, nil) }; return }
        Self.fetching.insert(key)
        Self.fetchLock.unlock()
        DispatchQueue.global(qos: .background).async {
            var err: String?
            do { try self.git(["fetch", "--all", "--prune", "--quiet"]) } catch { err = (error as? GitError)?.message ?? "\(error)" }
            Self.fetchLock.lock(); Self.fetching.remove(key); if err == nil { Self.lastFetch[key] = Date() }; Self.fetchLock.unlock()
            DispatchQueue.main.async { done(true, err) }
        }
    }

    static func resetFetchThrottle() { fetchLock.lock(); lastFetch = [:]; fetchLock.unlock() }
}
