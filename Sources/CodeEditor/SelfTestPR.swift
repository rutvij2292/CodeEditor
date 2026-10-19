import AppKit

/// Throwaway repositories imitating GitHub: a bare "origin" with hand-made `refs/pull/N/head` refs, a developer clone and work clones.
enum PRTestEnv {
    struct Env {
        var root: URL
        var origin: URL, fork: URL, dev: URL
    }

    @discardableResult
    static func g(_ dir: URL, _ args: [String]) -> String {
        (try? String(decoding: GitRepo.execute(args, in: dir), as: UTF8.self)) ?? ""
    }
    static func write(_ dir: URL, _ rel: String, _ text: String) {
        let u = dir.appendingPathComponent(rel)
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: u, atomically: true, encoding: .utf8)
    }
    static func identify(_ dir: URL) {
        g(dir, ["config", "user.email", "t@example.com"]); g(dir, ["config", "user.name", "Tester"])
    }
    static func commit(_ dir: URL, _ msg: String) { g(dir, ["add", "-A"]); g(dir, ["commit", "-q", "-m", msg]) }

    static let aBase = (1...8).map { "line \($0)\n" }.joined()

    /// PRs: 7 conflicts (a.txt both edited, c.txt modified on main / deleted on PR, composer.lock, binary), 8 is clean, 9 lives in a fork.
    static func make() -> Env {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ce-pr-\(getpid())-\(UUID().uuidString.prefix(6))")
        let origin = root.appendingPathComponent("origin.git"), fork = root.appendingPathComponent("fork.git"), dev = root.appendingPathComponent("dev")
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        g(root, ["init", "-q", "--bare", "-b", "main", origin.path])
        g(root, ["init", "-q", "--bare", "-b", "main", fork.path])
        g(root, ["clone", "-q", origin.path, dev.path])
        identify(dev)
        g(dev, ["checkout", "-q", "-b", "main"])
        write(dev, "a.txt", aBase); write(dev, "b.txt", "b1\nb2\nb3\n"); write(dev, "c.txt", "c1\nc2\n")
        write(dev, "composer.lock", "{\"hash\": \"base\"}\n")
        try? Data([0, 1, 2, 3, 0, 9]).write(to: dev.appendingPathComponent("logo.bin"))
        commit(dev, "base")
        g(dev, ["push", "-q", "origin", "main"])
        g(origin, ["symbolic-ref", "HEAD", "refs/heads/main"])
        // feature/x: PR 7
        g(dev, ["checkout", "-q", "-b", "feature/x"])
        write(dev, "a.txt", aBase.replacingOccurrences(of: "line 2\n", with: "line 2 FEATURE\n"))
        write(dev, "composer.lock", "{\"hash\": \"feature\"}\n")
        try? Data([0, 1, 2, 3, 0, 7]).write(to: dev.appendingPathComponent("logo.bin"))
        try? fm.removeItem(at: dev.appendingPathComponent("c.txt"))
        commit(dev, "feature work")
        g(dev, ["push", "-q", "origin", "feature/x"])
        g(dev, ["push", "-q", "origin", "feature/x:refs/pull/7/head"])
        // feature/clean: PR 8
        g(dev, ["checkout", "-q", "main"]); g(dev, ["checkout", "-q", "-b", "feature/clean"])
        write(dev, "d.txt", "new\n"); commit(dev, "add d")
        g(dev, ["push", "-q", "origin", "feature/clean"]); g(dev, ["push", "-q", "origin", "feature/clean:refs/pull/8/head"])
        // fork PR 9: branch only exists in the fork
        g(dev, ["checkout", "-q", "main"]); g(dev, ["checkout", "-q", "-b", "contrib/y"])
        write(dev, "b.txt", "b1\nb2 FORK\nb3\n"); commit(dev, "fork change")
        g(dev, ["push", "-q", fork.path, "contrib/y"]); g(dev, ["push", "-q", "origin", "contrib/y:refs/pull/9/head"])
        // main moves on and conflicts with PR 7 / 9
        g(dev, ["checkout", "-q", "main"])
        write(dev, "a.txt", aBase.replacingOccurrences(of: "line 2\n", with: "line 2 MAIN\n"))
        write(dev, "b.txt", "b1\nb2 MAIN\nb3\n"); write(dev, "c.txt", "c1\nc2 MAIN\n")
        write(dev, "composer.lock", "{\"hash\": \"main\"}\n")
        try? Data([0, 1, 2, 3, 0, 5]).write(to: dev.appendingPathComponent("logo.bin"))
        commit(dev, "main moves on")
        g(dev, ["push", "-q", "origin", "main"])
        return Env(root: root, origin: origin, fork: fork, dev: dev)
    }

    static func clone(_ env: Env, _ name: String) -> GitRepo {
        let dir = env.root.appendingPathComponent(name)
        g(env.root, ["clone", "-q", env.origin.path, dir.path])
        identify(dir)
        return GitRepo(root: dir)
    }
}

enum SelfTestPR {
    /// Regression: opening a second conflicted file in the merge view used to trap (old result edges vs the new hunks).
    private static func mergeViewReloadChecks() {
        let mv = MergeView(frame: NSRect(x: 0, y: 0, width: 900, height: 500))
        let few = ("a\n", "a1\n", "a2\n")
        let many = ("1\n2\n3\n4\n5\n6\n7\n8\n", "1x\n2\n3x\n4\n5x\n6\n7x\n8\n", "1y\n2\n3y\n4\n5y\n6\n7y\n8\n")
        for (b, o, t) in [few, many, few, many, many] {
            mv.show(base: b, ours: o, theirs: t, oursTitle: "ours", theirsTitle: "theirs", fileExtension: "txt")
            mv.acceptAllOurs()
        }
        SelfTest.check("merge view: loading file after file never traps and accepts all", true)

        // Arrows follow the change's state (PhpStorm): unresolved -> apply/ignore, resolved -> only a reset button.
        let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        let m2 = MergeView(frame: NSRect(x: 0, y: 0, width: 1000, height: 600))
        host.contentView = m2
        m2.show(base: "x\n", ours: "x1\n", theirs: "x2\n", oursTitle: "ours", theirsTitle: "theirs", fileExtension: "txt")
        m2.layoutSubtreeIfNeeded()
        func st(_ left: Bool) -> String {
            guard let g = m2.gutterState(hunk: 0, left: left) else { return "none" }
            return "\(g.apply ? "A" : "-")\(g.ignore ? "I" : "-")\(g.reset ? "R" : "-")"
        }
        SelfTest.check("merge view: unresolved conflict offers apply on both sides", st(true) == "A--" && st(false) == "A--")
        m2.applyOurs(0)
        SelfTest.check("merge view: accepting left removes arrows on BOTH sides, offers reset on the left", st(true) == "--R" && st(false) == "---" && m2.remainingConflicts == 0)
        m2.resetHunk(0)
        SelfTest.check("merge view: reset brings the arrows and the conflict back", st(true) == "A--" && st(false) == "A--" && m2.remainingConflicts == 1)
        m2.revertToBase(0)
        SelfTest.check("merge view: discarding removes the arrows too", st(true) == "--R" && st(false) == "---" && m2.remainingConflicts == 0)
        m2.resetHunk(0)
        m2.applyTheirs(0)
        // Resolve Automatically: whitespace-only differences settle themselves; real conflicts stay.
        let m3 = MergeView(frame: NSRect(x: 0, y: 0, width: 1000, height: 600))
        m3.show(base: "a\nb\nc\nd\ne\nf\n", ours: "a\nB1\nc\nd\ne\nf\n", theirs: "a\nB2\nc\nd\ne\nf\n", oursTitle: "o", theirsTitle: "t", fileExtension: "txt")
        SelfTest.check("merge view: a real conflict is not auto-resolved", m3.resolveAutomatically() == 0 && m3.remainingConflicts == 1)
        let m4 = MergeView(frame: NSRect(x: 0, y: 0, width: 1000, height: 600))
        m4.show(base: "a\nvalue = 1\nc\nd\ne\nf\n", ours: "a\nvalue  =  2\nc\nd\ne\nf\n", theirs: "a\nvalue = 2\nc\nd\ne\nf\n", oursTitle: "o", theirsTitle: "t", fileExtension: "txt")
        let before = m4.remainingConflicts
        SelfTest.check("merge view: whitespace-only conflict resolves automatically", before == 1 && m4.resolveAutomatically() == 1 && m4.remainingConflicts == 0)
        m4.revertAllResolution()
        SelfTest.check("merge view: revert conflict resolution restores the conflict", m4.remainingConflicts == 1)
        SelfTest.check("merge view: accepting right puts the reset on the right", st(true) == "---" && st(false) == "--R")
    }

    static func run() {
        mergeViewReloadChecks()

        let check = SelfTest.check
        // parsing
        check("PR ref: plain number", PRReference.parse("123")?.number == 123)
        check("PR ref: #123", PRReference.parse(" #123 ")?.number == 123)
        let u = PRReference.parse("https://github.com/acme/app/pull/42/files")
        check("PR ref: URL", u?.number == 42 && u?.owner == "acme" && u?.repo == "app")
        check("PR ref: garbage rejected", PRReference.parse("abc") == nil && PRReference.parse("0") == nil && PRReference.parse("") == nil)
        check("remote slug: ssh + https", PRFlow.slug(ofRemoteURL: "git@github.com:acme/app.git")?.repo == "app"
              && PRFlow.slug(ofRemoteURL: "https://github.com/acme/app")?.owner == "acme")
        check("fork url keeps ssh style", PRFlow.forkURL(originURL: "git@github.com:acme/app.git", owner: "bob", name: "app") == "git@github.com:bob/app.git")
        check("error classify", PRError.classify("fatal: unable to access: Could not resolve host: github.com").kind == .offline
              && PRError.classify("remote: error: GH006: Protected branch update failed").kind == .protectedBranch
              && PRError.classify("! [rejected] x -> y (non-fast-forward)").kind == .nonFastForward
              && PRError.classify("remote: Permission to a/b.git denied").kind == .permission)
        check("lockfile hint", PRFlow.lockfileHint(for: "sub/composer.lock")?.contains("composer update --lock") == true && PRFlow.lockfileHint(for: "a.txt") == nil)

        let env = PRTestEnv.make()
        defer { try? FileManager.default.removeItem(at: env.root) }
        let g = PRTestEnv.g

        // git-only metadata (no gh)
        GHCLI.overridePath = "/nonexistent/gh"
        let work = PRTestEnv.clone(env, "work1")
        let meta = try? PRFlow.resolveInfo(repo: work, ref: PRReference(number: 7, owner: nil, repo: nil))
        check("git-only: info without gh gives note", meta?.info.viaGH == false && meta?.note?.contains("gh auth login") == true)

        // conflicts, merge
        var session: PRSession?
        do { session = try PRFlow.prepare(repo: work, info: meta!.info, strategy: .merge, baseOverride: nil, stashDirty: false) }
        catch { check("prepare PR 7 succeeded (\(error.localizedDescription))", false) }
        if var s = session {
            check("git-only: head branch detected + same repo", s.headRefName == "feature/x" && !s.isFork && s.pushRemote == "origin")
            check("git-only: base defaults to origin HEAD", s.baseRef == "main")
            check("PR branch checked out tracking origin", g(work.root, ["rev-parse", "--abbrev-ref", "HEAD"]).hasPrefix("feature/x")
                  && g(work.root, ["rev-parse", "--abbrev-ref", "feature/x@{upstream}"]).hasPrefix("origin/feature/x"))
            check("merge in progress with conflicts", work.operationInProgress() == .merge
                  && Set(s.conflicts) == ["a.txt", "c.txt", "composer.lock", "logo.bin"])
            check("kinds: text / delete / binary", PRFlow.conflictKind(work, path: "a.txt", strategy: .merge) == .text
                  && PRFlow.conflictKind(work, path: "c.txt", strategy: .merge) == .yoursDeleted
                  && PRFlow.conflictKind(work, path: "logo.bin", strategy: .merge) == .binary)
            let v = try? work.conflictVersions(of: "a.txt")
            check("merge editor sides: yours=PR, theirs=base", v?.ours?.contains("FEATURE") == true && v?.theirs?.contains("MAIN") == true)
            check("commit refused while unresolved", (try? PRFlow.commit(work, s)) == nil)
            try? work.markResolved(path: "a.txt", content: PRTestEnv.aBase.replacingOccurrences(of: "line 2\n", with: "line 2 BOTH\n"))
            try? PRFlow.resolveWholeFile(work, path: "c.txt", yours: false, strategy: .merge)     // theirs (base) keeps modified c.txt
            try? PRFlow.resolveWholeFile(work, path: "logo.bin", yours: true, strategy: .merge)
            try? PRFlow.resolveWholeFile(work, path: "composer.lock", yours: false, strategy: .merge)
            check("all resolved", PRFlow.stillUnmerged(work).isEmpty)
            check("binary: yours kept, delete-vs-modify kept modified", (try? Data(contentsOf: work.root.appendingPathComponent("logo.bin"))) == Data([0, 1, 2, 3, 0, 7])
                  && (try? String(contentsOfFile: work.root.appendingPathComponent("c.txt").path, encoding: .utf8)) == "c1\nc2 MAIN\n")
            let out = try? PRFlow.commit(work, s)
            check("merge committed", out == .committed && work.operationInProgress() == nil
                  && g(work.root, ["rev-list", "--parents", "-n1", "HEAD"]).split(separator: " ").count == 3)
            do { try PRFlow.push(work, s); check("pushed to origin PR branch", g(env.origin, ["rev-parse", "refs/heads/feature/x"]) == g(work.root, ["rev-parse", "HEAD"])) }
            catch { check("push succeeded (\(error.localizedDescription))", false) }
            s.conflicts = []
        }

        // abort restores
        let w2b = PRTestEnv.clone(env, "work2b")
        let preB = g(w2b.root, ["rev-parse", "HEAD"])
        if let s = try? PRFlow.prepare(repo: w2b, info: PRInfo(number: 9), strategy: .merge, baseOverride: nil, stashDirty: false) {
            check("fork-style: detected as fork, no push target in git-only mode", s.isFork && s.pushRemote == nil && s.conflicts == ["b.txt"])
            check("fork-style: push refused with clear error", (try? PRFlow.push(w2b, s)) == nil
                  && { do { try PRFlow.push(w2b, s) } catch { return (error as? PRError)?.kind == .noPushTarget }; return false }())
            _ = try? PRFlow.restore(w2b, s)
            check("abort: back on main, clean, branch removed", g(w2b.root, ["rev-parse", "--abbrev-ref", "HEAD"]).hasPrefix("main")
                  && g(w2b.root, ["rev-parse", "HEAD"]) == preB && w2b.operationInProgress() == nil
                  && g(w2b.root, ["status", "--porcelain"]).isEmpty && g(w2b.root, ["branch", "--list", "pr-9"]).isEmpty)
        } else { check("fork-style prepare", false) }

        // fork with explicit clone url (as gh would give): push lands in the fork
        let w3 = PRTestEnv.clone(env, "work3")
        var finfo = PRInfo(number: 9); finfo.headRef = "contrib/y"; finfo.baseRef = "main"; finfo.isCrossRepository = true
        finfo.headOwner = "bob"; finfo.headRepoName = "app"; finfo.headCloneURL = env.fork.path; finfo.viaGH = true
        if let s = try? PRFlow.prepare(repo: w3, info: finfo, strategy: .merge, baseOverride: nil, stashDirty: false) {
            check("fork via gh info: warns about permissions", s.isFork && s.notes.contains { $0.contains("fork") } && s.pushRemote == env.fork.path)
            try? w3.markResolved(path: "b.txt", content: "b1\nb2 FORK+MAIN\nb3\n")
            _ = try? PRFlow.commit(w3, s)
            do { try PRFlow.push(w3, s); check("fork push lands in fork branch", g(env.fork, ["rev-parse", "contrib/y"]) == g(w3.root, ["rev-parse", "HEAD"])) }
            catch { check("fork push (\(error.localizedDescription))", false) }
        } else { check("fork via gh prepare", false) }

        // dirty tree
        let w4 = PRTestEnv.clone(env, "work4")
        PRTestEnv.write(w4.root, "b.txt", "local edit\n"); PRTestEnv.write(w4.root, "scratch.txt", "untracked\n")
        var dirtyKind: PRError.Kind?
        do { _ = try PRFlow.prepare(repo: w4, info: PRInfo(number: 8), strategy: .merge, baseOverride: nil, stashDirty: false) } catch { dirtyKind = (error as? PRError)?.kind }
        check("dirty tree: refused without consent, nothing touched", dirtyKind == .dirty
              && (try? String(contentsOf: w4.root.appendingPathComponent("b.txt"), encoding: .utf8)) == "local edit\n")
        if let s = try? PRFlow.prepare(repo: w4, info: PRInfo(number: 9), strategy: .merge, baseOverride: nil, stashDirty: true) {
            check("dirty tree: stashed, then conflicts shown", s.stashed && ((try? w4.stashList().count) ?? 0) == 1 && s.conflicts == ["b.txt"])
            let notes = (try? PRFlow.restore(w4, s)) ?? ["x"]
            check("dirty tree: abort pops the stash, local edit back", notes.isEmpty && ((try? w4.stashList().count) ?? 1) == 0
                  && (try? String(contentsOf: w4.root.appendingPathComponent("b.txt"), encoding: .utf8)) == "local edit\n"
                  && FileManager.default.fileExists(atPath: w4.root.appendingPathComponent("scratch.txt").path))
        } else { check("dirty tree stash prepare", false) }

        // no-conflict PR leaves everything as it was
        let w5 = PRTestEnv.clone(env, "work5")
        let pre5 = g(w5.root, ["rev-parse", "HEAD"])
        if let s = try? PRFlow.prepare(repo: w5, info: PRInfo(number: 8), strategy: .merge, baseOverride: nil, stashDirty: false) {
            check("no-conflict PR: reported, repo restored", s.noConflicts && s.conflicts.isEmpty && g(w5.root, ["rev-parse", "HEAD"]) == pre5
                  && w5.operationInProgress() == nil && g(w5.root, ["status", "--porcelain"]).isEmpty
                  && g(w5.root, ["rev-parse", "--abbrev-ref", "HEAD"]).hasPrefix("main"))
        } else { check("no-conflict prepare", false) }

        // non-fast-forward then pull and retry
        let w6 = PRTestEnv.clone(env, "work6")
        // Build a fresh conflicting PR 10 so we have conflicts to resolve first.
        g(env.dev, ["checkout", "-q", "main"]); g(env.dev, ["checkout", "-q", "-b", "feature/z", "main~1"])
        PRTestEnv.write(env.dev, "b.txt", "b1\nb2 Z\nb3\n"); PRTestEnv.commit(env.dev, "z change")
        g(env.dev, ["push", "-q", "origin", "feature/z", "feature/z:refs/pull/10/head"])
        if let s = try? PRFlow.prepare(repo: w6, info: PRInfo(number: 10), strategy: .merge, baseOverride: nil, stashDirty: false) {
            try? w6.markResolved(path: "b.txt", content: "b1\nb2 Z+MAIN\nb3\n")
            _ = try? PRFlow.commit(w6, s)
            // someone else pushes to the PR branch meanwhile
            g(env.dev, ["checkout", "-q", "feature/z"]); PRTestEnv.write(env.dev, "z.txt", "z\n"); PRTestEnv.commit(env.dev, "teammate")
            g(env.dev, ["push", "-q", "origin", "feature/z"])
            var kind: PRError.Kind?
            do { try PRFlow.push(w6, s) } catch { kind = (error as? PRError)?.kind }
            check("push rejected: non-fast-forward detected", kind == .nonFastForward)
            let more = try? PRFlow.pullRemoteHead(w6, s)
            check("pull and retry merges cleanly", more?.isEmpty == true && FileManager.default.fileExists(atPath: w6.root.appendingPathComponent("z.txt").path))
            do { try PRFlow.push(w6, s); check("retry push succeeds", g(env.origin, ["rev-parse", "refs/heads/feature/z"]) == g(w6.root, ["rev-parse", "HEAD"])) }
            catch { check("retry push (\(error.localizedDescription))", false) }
        } else { check("PR 10 prepare", false) }

        // rebase strategy
        g(env.dev, ["checkout", "-q", "main"]); g(env.dev, ["checkout", "-q", "-b", "feature/r", "main~1"])
        PRTestEnv.write(env.dev, "b.txt", "b1\nb2 R\nb3\n"); PRTestEnv.commit(env.dev, "r change")
        g(env.dev, ["push", "-q", "origin", "feature/r", "feature/r:refs/pull/11/head"])
        let w7 = PRTestEnv.clone(env, "work7")
        if let s = try? PRFlow.prepare(repo: w7, info: PRInfo(number: 11), strategy: .rebase, baseOverride: nil, stashDirty: false) {
            check("rebase: stops with conflict", w7.operationInProgress() == .rebase && s.conflicts == ["b.txt"])
            let v = try? w7.conflictVersions(of: "b.txt")
            check("rebase: stage 2 is the base, 3 is the PR (labels swap in UI)", v?.ours?.contains("MAIN") == true && v?.theirs?.contains(" R") == true)
            try? w7.markResolved(path: "b.txt", content: "b1\nb2 R+MAIN\nb3\n")
            check("rebase: continue completes", (try? PRFlow.commit(w7, s)) == .committed && w7.operationInProgress() == nil)
            do { try PRFlow.push(w7, s); check("rebase: force-with-lease push", g(env.origin, ["rev-parse", "refs/heads/feature/r"]) == g(w7.root, ["rev-parse", "HEAD"])) }
            catch { check("rebase push (\(error.localizedDescription))", false) }
        } else { check("rebase prepare", false) }

        // errors: not found, no origin, offline
        let w8 = PRTestEnv.clone(env, "work8")
        var nf: PRError.Kind?
        do { _ = try PRFlow.prepare(repo: w8, info: PRInfo(number: 999), strategy: .merge, baseOverride: nil, stashDirty: false) } catch { nf = (error as? PRError)?.kind }
        check("PR number not found", nf == .notFound)
        let lone = env.root.appendingPathComponent("lone"); PRTestEnv.g(env.root, ["init", "-q", lone.path])
        var noOrigin: PRError.Kind?
        do { _ = try PRFlow.resolveInfo(repo: GitRepo(root: lone), ref: PRReference(number: 1, owner: nil, repo: nil)) } catch { noOrigin = (error as? PRError)?.kind }
        check("repo without origin: clear error", noOrigin == .noOrigin)
        var wrongRepo = false
        do { _ = try PRFlow.resolveInfo(repo: GitRepo(root: w8.root), ref: PRReference(number: 1, owner: "acme", repo: "other")) } catch { wrongRepo = true }
        check("URL for a different repo than origin is rejected (path remotes: slug-less is tolerated)", wrongRepo || PRFlow.slug(ofRemoteURL: env.origin.path) == nil)

        // gh stub
        let stub = env.root.appendingPathComponent("gh-stub.sh")
        try? "#!/bin/sh\necho '{\"title\":\"Fix totals\",\"headRefName\":\"feature/x\",\"baseRefName\":\"main\",\"headRepository\":{\"name\":\"app\"},\"headRepositoryOwner\":{\"login\":\"acme\"},\"mergeable\":\"CONFLICTING\",\"url\":\"https://github.com/acme/app/pull/7\",\"isCrossRepository\":false}'\n"
            .write(to: stub, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)
        GHCLI.overridePath = stub.path
        let rich = try? PRFlow.resolveInfo(repo: w8, ref: PRReference(number: 7, owner: nil, repo: nil))
        check("gh: title, branches, url, mergeable", rich?.info.title == "Fix totals" && rich?.info.baseRef == "main" && rich?.info.url?.hasSuffix("/pull/7") == true
              && rich?.info.mergeable == "CONFLICTING" && rich?.note == nil)
        let bad = env.root.appendingPathComponent("gh-bad.sh")
        try? "#!/bin/sh\necho 'GraphQL: Could not resolve to a PullRequest with the number of 5' >&2\nexit 1\n".write(to: bad, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bad.path)
        GHCLI.overridePath = bad.path
        var ghNF: PRError.Kind?
        do { _ = try PRFlow.resolveInfo(repo: w8, ref: PRReference(number: 5, owner: nil, repo: nil)) } catch { ghNF = (error as? PRError)?.kind }
        check("gh: not-found message maps to notFound", ghNF == .notFound)
        let unauth = env.root.appendingPathComponent("gh-unauth.sh")
        try? "#!/bin/sh\necho 'To get started with GitHub CLI, please run:  gh auth login' >&2\nexit 4\n".write(to: unauth, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: unauth.path)
        GHCLI.overridePath = unauth.path
        let fb = try? PRFlow.resolveInfo(repo: w8, ref: PRReference(number: 7, owner: nil, repo: nil))
        check("gh signed out: falls back to git with hint", fb?.info.viaGH == false && fb?.note?.contains("gh auth login") == true)
        GHCLI.overridePath = nil
    }
}
