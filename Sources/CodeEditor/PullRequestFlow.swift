import Foundation

// Pull-request conflict resolution: git logic only (UI lives in PullRequestUI.swift).
// Works with plain git (`refs/pull/N/head`) and is enriched by the GitHub CLI when it is installed and signed in.

struct PRError: Error, LocalizedError {
    enum Kind { case dirty, notFound, offline, noOrigin, protectedBranch, nonFastForward, permission, busy, noPushTarget, other }
    var kind: Kind
    var message: String
    var errorDescription: String? { message }

    /// Maps raw git/gh output to a friendly error.
    static func classify(_ raw: String) -> PRError {
        let m = raw.lowercased()
        if m.contains("could not resolve host") || m.contains("network is unreachable") || m.contains("timed out")
            || m.contains("unable to access") || m.contains("could not read from remote") && m.contains("connect") {
            return PRError(kind: .offline, message: "Can't reach the remote. Check your internet connection and try again.")
        }
        if m.contains("gh006") || m.contains("protected branch") {
            return PRError(kind: .protectedBranch, message: "The PR branch is protected, so GitHub refused the push. Ask a maintainer, or push to a different branch.")
        }
        if m.contains("non-fast-forward") || m.contains("fetch first") || m.contains("stale info") || m.contains("tip of your current branch is behind") {
            return PRError(kind: .nonFastForward, message: "Someone pushed to the PR branch after you started. Pull their changes and retry.")
        }
        if m.contains("permission denied") || m.contains("403") || m.contains("authentication failed") || m.contains("write access") || (m.contains("permission to") && m.contains("denied")) {
            return PRError(kind: .permission, message: "You don't have permission to push to the PR branch (fork PRs only allow it when the author enabled maintainer edits).")
        }
        return PRError(kind: .other, message: raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

struct PRReference: Equatable {
    var number: Int
    var owner: String?
    var repo: String?

    /// Accepts `123`, `#123`, `PR 123` and GitHub URLs such as https://github.com/o/r/pull/123/files.
    static func parse(_ text: String) -> PRReference? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let m = t.range(of: #"^https?://[^/]+/([^/]+)/([^/]+)/pull/(\d+)"#, options: .regularExpression) {
            let parts = t[m].split(separator: "/").map(String.init)      // ["https:", "host", owner, repo, "pull", n]
            if parts.count >= 6, let n = Int(parts[5]), n > 0 { return PRReference(number: n, owner: parts[2], repo: parts[3]) }
        }
        let digits = t.replacingOccurrences(of: "#", with: "").replacingOccurrences(of: "PR", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespaces)
        if let n = Int(digits), n > 0, digits.allSatisfy(\.isNumber) { return PRReference(number: n, owner: nil, repo: nil) }
        return nil
    }
}

enum PRStrategy: String { case merge, rebase }

struct PRInfo {
    var number: Int
    var title: String?
    var headRef: String?
    var baseRef: String?
    var headOwner: String?
    var headRepoName: String?
    var headCloneURL: String?         // explicit fork URL (tests); otherwise derived from origin's URL
    var isCrossRepository = false
    var url: String?
    var mergeable: String?
    var viaGH = false
}

enum PRConflictKind: Equatable {
    case text, binary
    case yoursDeleted, theirsDeleted      // "yours" = the PR branch, "theirs" = the base being merged in
    var needsChoice: Bool { self != .text }
}

struct PRSession {
    var info: PRInfo
    var strategy: PRStrategy
    var baseRef: String
    var localBranch: String
    var createdBranch: Bool
    var preBranch: String?             // nil when HEAD was detached
    var preHead: String
    var stashed: Bool
    var headRefName: String?           // branch name on the head repository (push target)
    var pushRemote: String?            // remote name or URL; nil when it cannot be determined
    var isFork: Bool
    var conflicts: [String]
    var noConflicts: Bool
    var notes: [String]
    var prHeadSHA: String
    var branchSHABefore: String

    var headLabel: String { isFork ? "\(info.headOwner.map { $0 + ":" } ?? "")\(headRefName ?? localBranch)" : (headRefName ?? localBranch) }
}

// MARK: GitHub CLI

enum GHCLI {
    /// Tests point this at a stub script.
    static var overridePath: String?
    private static var cached: String??

    static func path() -> String? {
        if let o = overridePath ?? AppEnv.value("CE_GH_PATH") { return FileManager.default.isExecutableFile(atPath: o) ? o : nil }
        if let c = cached { return c }
        var found: String?
        for p in ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"] where FileManager.default.isExecutableFile(atPath: p) { found = p; break }
        if found == nil, let out = run("/bin/zsh", ["-lc", "command -v gh"], in: nil, timeout: 5), out.status == 0 {
            let p = out.out.split(separator: "\n").last.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
            if p.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: p) { found = p }
        }
        cached = .some(found)
        return found
    }

    static func run(_ exe: String, _ args: [String], in dir: URL?, timeout: TimeInterval = 20) -> (status: Int32, out: String, err: String)? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.currentDirectoryURL = dir
        var env = ProcessInfo.processInfo.environment
        env["GH_PROMPT_DISABLED"] = "1"; env["NO_COLOR"] = "1"; env["GH_NO_UPDATE_NOTIFIER"] = "1"
        p.environment = env
        let o = Pipe(), e = Pipe()
        p.standardOutput = o; p.standardError = e; p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { errData = e.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let out = o.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        p.waitUntilExit()
        killer.cancel()
        return (p.terminationStatus, String(decoding: out, as: UTF8.self), String(decoding: errData, as: UTF8.self))
    }

    /// True when `gh` exists and reports a signed-in account.
    static func isSignedIn() -> Bool {
        guard let gh = path(), let r = run(gh, ["auth", "status"], in: nil, timeout: 8) else { return false }
        return r.status == 0
    }
}

// MARK: flow

enum PRFlow {
    static let lockfiles: [String: String] = [
        "composer.lock": "composer update --lock", "package-lock.json": "npm install", "yarn.lock": "yarn install",
        "pnpm-lock.yaml": "pnpm install", "Gemfile.lock": "bundle install", "Cargo.lock": "cargo update -w",
        "poetry.lock": "poetry lock", "Pipfile.lock": "pipenv lock",
    ]
    static func lockfileHint(for path: String) -> String? {
        lockfiles[(path as NSString).lastPathComponent].map {
            "This is a generated lockfile. The safest fix: keep either side here, then regenerate it with `\($0)` and commit the result. Kode never regenerates it for you."
        }
    }

    static func slug(ofRemoteURL u: String) -> (host: String, owner: String, repo: String)? {
        let pattern = #"^(?:[a-z+]+://)?(?:[^@/]+@)?([^:/]+)(?::\d+)?[:/]([^/]+)/([^/]+?)(?:\.git)?/?$"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: u, range: NSRange(u.startIndex..., in: u)), m.numberOfRanges == 4,
              u.contains("://") || u.contains("@") else { return nil }
        func g(_ i: Int) -> String { Range(m.range(at: i), in: u).map { String(u[$0]) } ?? "" }
        return (g(1), g(2), g(3))
    }

    static func forkURL(originURL: String, owner: String, name: String) -> String? {
        guard let s = slug(ofRemoteURL: originURL) else { return nil }
        return originURL.hasPrefix("http") ? "https://\(s.host)/\(owner)/\(name).git" : "git@\(s.host):\(owner)/\(name).git"
    }

    // MARK: metadata

    /// Resolves PR metadata; `note` explains degraded (git-only) mode.
    static func resolveInfo(repo: GitRepo, ref: PRReference) throws -> (info: PRInfo, note: String?) {
        guard let origin = try? repo.text(["remote", "get-url", "origin"]).trimmingCharacters(in: .whitespacesAndNewlines), !origin.isEmpty else {
            throw PRError(kind: .noOrigin, message: "This repository has no `origin` remote. Add one (git remote add origin <url>) and try again.")
        }
        if let o = ref.owner, let r = ref.repo, let s = slug(ofRemoteURL: origin),
           s.owner.lowercased() != o.lowercased() || s.repo.lowercased() != r.lowercased() {
            throw PRError(kind: .other, message: "That pull request belongs to \(o)/\(r), but this project's origin is \(s.owner)/\(s.repo).")
        }
        var info = PRInfo(number: ref.number)
        guard let gh = GHCLI.path() else {
            return (info, "GitHub CLI not found, using git only. Install it (brew install gh) and run `gh auth login` for the title and branches.")
        }
        let fields = "title,headRefName,baseRefName,headRepository,headRepositoryOwner,mergeable,url,isCrossRepository"
        guard let r = GHCLI.run(gh, ["pr", "view", String(ref.number), "--json", fields], in: repo.root) else {
            return (info, "Couldn't run the GitHub CLI, using git only.")
        }
        if r.status != 0 {
            let err = r.err.lowercased()
            if err.contains("could not resolve to a pullrequest") || err.contains("no pull requests found") {
                throw PRError(kind: .notFound, message: "Pull request #\(ref.number) was not found in this repository.")
            }
            let hint = err.contains("auth login") || err.contains("not logged") || err.contains("gh_token")
                ? "GitHub CLI isn't signed in, using git only. Run `gh auth login` for the title and branches."
                : "GitHub CLI couldn't read the PR, using git only."
            return (info, hint)
        }
        guard let obj = try? JSONSerialization.jsonObject(with: Data(r.out.utf8)) as? [String: Any] else { return (info, "Unreadable GitHub CLI output, using git only.") }
        info.title = obj["title"] as? String
        info.headRef = obj["headRefName"] as? String
        info.baseRef = obj["baseRefName"] as? String
        info.headRepoName = (obj["headRepository"] as? [String: Any])?["name"] as? String
        info.headOwner = (obj["headRepositoryOwner"] as? [String: Any])?["login"] as? String
        info.isCrossRepository = obj["isCrossRepository"] as? Bool ?? false
        info.url = obj["url"] as? String
        info.mergeable = obj["mergeable"] as? String
        info.viaGH = true
        return (info, nil)
    }

    // MARK: git helpers

    private static func sha(_ repo: GitRepo, _ rev: String) -> String? {
        (try? repo.text(["rev-parse", "--verify", "-q", rev]))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static func isAncestor(_ repo: GitRepo, _ a: String, _ b: String) -> Bool {
        (try? repo.git(["merge-base", "--is-ancestor", a, b])) != nil
    }
    private static func unmerged(_ repo: GitRepo) -> [String] {
        ((try? repo.text(["diff", "--name-only", "--diff-filter=U"])) ?? "").split(separator: "\n").map(String.init)
    }
    static func originDefaultBranch(_ repo: GitRepo) -> String? {
        if let s = try? repo.text(["symbolic-ref", "--short", "refs/remotes/origin/HEAD"]) {
            let b = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if b.hasPrefix("origin/") { return String(b.dropFirst(7)) }
        }
        if let s = try? repo.text(["ls-remote", "--symref", "origin", "HEAD"]), let line = s.split(separator: "\n").first, line.hasPrefix("ref:") {
            let ref = line.dropFirst(4).split(separator: "\t").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            if ref.hasPrefix("refs/heads/") { return String(ref.dropFirst(11)) }
        }
        return ["main", "master", "develop"].first { sha(repo, "refs/remotes/origin/\($0)") != nil }
    }

    /// Fetches, checks out the PR head locally and starts the merge/rebase of the base into it.
    static func prepare(repo: GitRepo, info: PRInfo, strategy: PRStrategy, baseOverride: String?, stashDirty: Bool,
                        progress: (String) -> Void = { _ in }) throws -> PRSession {
        let n = info.number
        guard let originURL = try? repo.text(["remote", "get-url", "origin"]).trimmingCharacters(in: .whitespacesAndNewlines), !originURL.isEmpty else {
            throw PRError(kind: .noOrigin, message: "This repository has no `origin` remote. Add one (git remote add origin <url>) and try again.")
        }
        if let op = repo.operationInProgress() {
            throw PRError(kind: .busy, message: "A \(op.title.lowercased()) is already in progress. Finish or abort it first.")
        }
        var notes: [String] = []
        progress("Fetching pull request #\(n)…")
        let prRef = "refs/kode/pr/\(n)"
        do { try repo.git(["fetch", "origin", "+refs/pull/\(n)/head:\(prRef)"]) }
        catch let e as GitError {
            let m = e.message.lowercased()
            if m.contains("couldn't find remote ref") || m.contains("couldn’t find remote ref") {
                throw PRError(kind: .notFound, message: "Pull request #\(n) was not found on origin.")
            }
            throw PRError.classify(e.message)
        }
        progress("Fetching branches…")
        do { try repo.git(["fetch", "origin", "--prune"]) } catch let e as GitError { throw PRError.classify(e.message) }
        guard let prSHA = sha(repo, prRef) else { throw PRError(kind: .notFound, message: "Pull request #\(n) could not be fetched.") }

        // Base branch.
        guard let base = info.baseRef ?? baseOverride.flatMap({ $0.isEmpty ? nil : $0 }) ?? originDefaultBranch(repo) else {
            throw PRError(kind: .other, message: "Couldn't work out the base branch. Enter it in the Base branch field.")
        }
        guard sha(repo, "refs/remotes/origin/\(base)") != nil else {
            throw PRError(kind: .other, message: "Base branch “\(base)” doesn't exist on origin.")
        }

        // Head branch and fork detection (git-only: the origin branch whose tip is the PR head).
        var headRef = info.headRef
        var isFork = info.viaGH ? info.isCrossRepository : false
        if !info.viaGH {
            let heads = ((try? repo.text(["for-each-ref", "--points-at", prSHA, "--format=%(refname:short)", "refs/remotes/origin"])) ?? "")
                .split(separator: "\n").map(String.init).filter { $0 != "origin" && $0 != "origin/HEAD" && $0.hasPrefix("origin/") }
            if let h = heads.first(where: { $0 != "origin/\(base)" }) ?? heads.first { headRef = String(h.dropFirst(7)) } else { isFork = true }
        }
        var pushRemote: String?
        if !isFork { pushRemote = "origin" }
        else if let u = info.headCloneURL { pushRemote = u }
        else if let o = info.headOwner, let name = info.headRepoName, let u = forkURL(originURL: originURL, owner: o, name: name) { pushRemote = u }
        if isFork {
            notes.append(pushRemote == nil
                ? "This pull request comes from a fork. Kode can't determine where to push, so you can resolve and commit, but pushing must be done manually."
                : "This pull request comes from a fork. Pushing only works if the author allowed edits from maintainers.")
        }

        // Pre-state + dirty tree.
        let preBranch = (try? repo.text(["symbolic-ref", "--short", "-q", "HEAD"]))?.trimmingCharacters(in: .whitespacesAndNewlines)
        let preHead = sha(repo, "HEAD") ?? ""
        let dirty = ((try? repo.text(["status", "--porcelain", "--untracked-files=no"])) ?? "").split(separator: "\n").count
        var stashed = false
        if dirty > 0 {
            if !stashDirty {
                throw PRError(kind: .dirty, message: "You have \(dirty) uncommitted change\(dirty == 1 ? "" : "s"). They need to be set aside before switching branches.")
            }
            progress("Stashing your changes…")
            try repo.stashPush(message: "Kode: before resolving PR #\(n)", includeUntracked: true)
            stashed = true
        }

        var session = PRSession(info: info, strategy: strategy, baseRef: base, localBranch: "", createdBranch: false,
                                preBranch: preBranch.flatMap { $0.isEmpty ? nil : $0 }, preHead: preHead, stashed: stashed,
                                headRefName: headRef, pushRemote: pushRemote, isFork: isFork, conflicts: [], noConflicts: false,
                                notes: notes, prHeadSHA: prSHA, branchSHABefore: prSHA)
        do {
            progress("Checking out the PR branch…")
            try checkoutBranch(repo, &session)
            progress("\(strategy == .merge ? "Merging" : "Rebasing onto") origin/\(base)…")
            session.branchSHABefore = sha(repo, "HEAD") ?? prSHA
            try startIntegration(repo, &session)
        } catch {
            _ = try? restore(repo, session)
            throw (error as? PRError) ?? PRError.classify((error as? GitError)?.message ?? error.localizedDescription)
        }
        if session.noConflicts { _ = try? restore(repo, session) }
        return session
    }

    private static func checkoutBranch(_ repo: GitRepo, _ s: inout PRSession) throws {
        let n = s.info.number
        let prRef = "refs/kode/pr/\(n)"
        let wanted = s.isFork ? "pr-\(n)" : (s.headRefName ?? "pr-\(n)")
        if sha(repo, "refs/heads/\(wanted)") != nil {
            let local = sha(repo, "refs/heads/\(wanted)")!
            if isAncestor(repo, local, s.prHeadSHA) {                         // behind the PR: fast-forward
                try repo.git(["checkout", wanted])
                if local != s.prHeadSHA { try repo.git(["merge", "--ff-only", prRef]) }
                s.localBranch = wanted
            } else if isAncestor(repo, s.prHeadSHA, local) {                  // local has extra commits
                try repo.git(["checkout", wanted])
                s.localBranch = wanted
                s.notes.append("Your local \(wanted) has commits that are not on the PR yet; they will be included.")
            } else {                                                          // diverged: don't touch it
                let alt = "kode/pr-\(n)"
                if sha(repo, "refs/heads/\(alt)") != nil { try repo.git(["branch", "-f", alt, prRef]) }
                try repo.git(["checkout"] + (sha(repo, "refs/heads/\(alt)") != nil ? [alt] : ["-b", alt, prRef]))
                s.localBranch = alt
                s.createdBranch = true
                s.notes.append("Your local \(wanted) has diverged from the PR, so Kode used \(alt) instead.")
            }
        } else {
            try repo.git(["checkout", "-b", wanted, prRef])
            s.localBranch = wanted
            s.createdBranch = true
        }
        if !s.isFork, let h = s.headRefName, sha(repo, "refs/remotes/origin/\(h)") != nil {
            _ = try? repo.git(["branch", "--set-upstream-to=origin/\(h)", s.localBranch])
        }
    }

    private static func startIntegration(_ repo: GitRepo, _ s: inout PRSession) throws {
        let target = "refs/remotes/origin/\(s.baseRef)"
        switch s.strategy {
        case .merge:
            do { try repo.git(["merge", "--no-commit", "--no-ff", target]) } catch let e as GitError {
                guard repo.operationInProgress() == .merge, !unmerged(repo).isEmpty else { throw e }
            }
            if repo.operationInProgress() == .merge, unmerged(repo).isEmpty {
                // Clean merge: nothing to resolve. Undo the staged merge.
                try repo.git(["merge", "--abort"])
                s.noConflicts = true
            } else if repo.operationInProgress() == nil { s.noConflicts = true }
        case .rebase:
            do { try repo.git(["rebase", target]) } catch let e as GitError {
                guard repo.operationInProgress() == .rebase, !unmerged(repo).isEmpty else {
                    if repo.operationInProgress() == .rebase { _ = try? repo.git(["rebase", "--abort"]) }
                    throw e
                }
            }
            if repo.operationInProgress() == nil {
                try repo.git(["reset", "--hard", s.branchSHABefore])    // rebased cleanly: put the branch back
                s.noConflicts = true
            }
        }
        s.conflicts = unmerged(repo)
    }

    /// Aborts any merge/rebase and returns to the state before `prepare` (also pops the stash we made).
    @discardableResult
    static func restore(_ repo: GitRepo, _ s: PRSession) throws -> [String] {
        var notes: [String] = []
        if let op = repo.operationInProgress() { try? repo.abortOperation(op) }
        if let pre = s.preBranch { _ = try? repo.git(["checkout", "-q", pre]) }
        else if !s.preHead.isEmpty { _ = try? repo.git(["checkout", "-q", "--detach", s.preHead]) }
        if s.createdBranch, !s.localBranch.isEmpty, s.localBranch != s.preBranch { _ = try? repo.git(["branch", "-D", s.localBranch]) }
        if s.stashed {
            let list = (try? repo.stashList()) ?? []
            if let i = list.firstIndex(where: { $0.message.contains("Kode: before resolving PR #\(s.info.number)") }) {
                do { try repo.stashPop(index: i) } catch {
                    notes.append("Your stashed changes could not be re-applied automatically; they are still in the stash.")
                }
            }
        }
        return notes
    }

    // MARK: per-file resolution

    private static func stagesPresent(_ repo: GitRepo, _ path: String) -> Set<Int> {
        Set(((try? repo.text(["ls-files", "-u", "--", path])) ?? "").split(separator: "\n").compactMap { line in
            line.split(separator: "\t").first?.split(separator: " ").last.flatMap { Int($0) }
        })
    }

    static func conflictKind(_ repo: GitRepo, path: String, strategy: PRStrategy) -> PRConflictKind {
        let stages = stagesPresent(repo, path)
        let yoursStage = strategy == .merge ? 2 : 3, theirsStage = strategy == .merge ? 3 : 2
        if !stages.contains(yoursStage) { return .yoursDeleted }
        if !stages.contains(theirsStage) { return .theirsDeleted }
        if (try? repo.conflictVersions(of: path)) == nil { return .binary }
        return .text
    }

    /// Takes one whole side (binary files, delete-vs-modify). A side that deleted the file removes it.
    static func resolveWholeFile(_ repo: GitRepo, path: String, yours: Bool, strategy: PRStrategy) throws {
        let stage = (strategy == .merge) == yours ? 2 : 3
        let present = stagesPresent(repo, path).contains(stage)
        if present {
            try repo.git(["checkout", stage == 2 ? "--ours" : "--theirs", "--", path])
            try repo.git(["add", "--", path])
        } else {
            try repo.markResolvedDeleted(path: path)
        }
    }

    /// Conflicted files that still have unmerged index entries.
    static func stillUnmerged(_ repo: GitRepo) -> Set<String> { Set(unmerged(repo)) }

    // MARK: finishing

    enum CommitOutcome: Equatable { case committed, moreConflicts([String]) }

    static func commit(_ repo: GitRepo, _ s: PRSession) throws -> CommitOutcome {
        let left = unmerged(repo)
        if !left.isEmpty { throw PRError(kind: .other, message: "\(left.count) file\(left.count == 1 ? " is" : "s are") still unresolved.") }
        switch s.strategy {
        case .merge:
            do { try repo.git(["commit", "--no-edit"]) } catch let e as GitError { throw PRError.classify(e.message) }
            return .committed
        case .rebase:
            do { try repo.git(["rebase", "--continue"]) } catch let e as GitError {
                let more = unmerged(repo)
                if repo.operationInProgress() == .rebase, !more.isEmpty { return .moreConflicts(more) }
                throw PRError.classify(e.message)
            }
            return repo.operationInProgress() == .rebase ? .moreConflicts(unmerged(repo)) : .committed
        }
    }

    static func push(_ repo: GitRepo, _ s: PRSession) throws {
        guard let remote = s.pushRemote, let head = s.headRefName else {
            throw PRError(kind: .noPushTarget, message: "Kode can't tell which branch this PR comes from, so it can't push. Commit here and push from the PR's fork.")
        }
        var args = ["push"]
        if s.strategy == .rebase { args.append("--force-with-lease=refs/heads/\(head):refs/kode/pr/\(s.info.number)") }
        if remote == "origin" { args += ["-u", "origin", "\(s.localBranch):refs/heads/\(head)"] }
        else { args += [remote, "HEAD:refs/heads/\(head)"] }
        do { try repo.git(args) } catch let e as GitError { throw PRError.classify(e.message) }
        _ = try? repo.git(["update-ref", "refs/kode/pr/\(s.info.number)", "HEAD"])
    }

    /// After a rejected push: bring the remote head branch into the local branch. Returns new conflicts (empty = merged cleanly).
    static func pullRemoteHead(_ repo: GitRepo, _ s: PRSession) throws -> [String] {
        guard let remote = s.pushRemote, let head = s.headRefName else { throw PRError(kind: .noPushTarget, message: "Nothing to pull from.") }
        do { try repo.git(["fetch", remote, head]) } catch let e as GitError { throw PRError.classify(e.message) }
        if remote == "origin" { _ = try? repo.git(["update-ref", "refs/kode/pr/\(s.info.number)", "refs/remotes/origin/\(head)"]) }
        else { _ = try? repo.git(["update-ref", "refs/kode/pr/\(s.info.number)", "FETCH_HEAD"]) }
        do { try repo.git(["merge", "--no-edit", "FETCH_HEAD"]) } catch let e as GitError {
            if repo.operationInProgress() == .merge { return unmerged(repo) }
            throw PRError.classify(e.message)
        }
        return []
    }

    /// Restores the stash made by `prepare` once the user is done (success path, branch stays checked out).
    static func popStash(_ repo: GitRepo, _ s: PRSession) -> String? {
        guard s.stashed, let list = try? repo.stashList(),
              let i = list.firstIndex(where: { $0.message.contains("Kode: before resolving PR #\(s.info.number)") }) else { return nil }
        do { try repo.stashPop(index: i); return nil } catch { return "Your stashed changes are still in the stash (they conflict with the PR branch)." }
    }
}
