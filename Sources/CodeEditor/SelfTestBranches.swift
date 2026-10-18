import Foundation

/// Branch workflow logic on throwaway repos (a local bare repo plays "origin"). Never touches a real project.
enum SelfTestBranches {
    private static func tmp(_ name: String) -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("ce-branches-\(getpid())-\(name)")
        try? FileManager.default.removeItem(at: u)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    @discardableResult
    private static func sh(_ repo: GitRepo, _ args: [String]) -> String {
        (try? repo.text(args)) ?? ""
    }

    private static func write(_ repo: GitRepo, _ file: String, _ text: String) {
        try? text.write(to: repo.root.appendingPathComponent(file), atomically: true, encoding: .utf8)
    }

    private static func commit(_ repo: GitRepo, _ file: String, _ text: String, _ msg: String) {
        write(repo, file, text)
        sh(repo, ["add", "-A"])
        sh(repo, ["commit", "-q", "-m", msg])
    }

    private static func configure(_ repo: GitRepo) {
        sh(repo, ["config", "user.name", "Test"]); sh(repo, ["config", "user.email", "t@example.com"])
        sh(repo, ["config", "commit.gpgsign", "false"]); sh(repo, ["config", "advice.detachedHead", "false"])
    }

    private static func clone(of origin: URL, into dir: URL) -> GitRepo {
        _ = try? GitRepo.execute(["clone", "-q", origin.path, dir.path], in: dir.deletingLastPathComponent())
        let r = GitRepo(root: dir)
        configure(r)
        return r
    }

    static func run() {
        let check = SelfTest.check
        let fm = FileManager.default
        let base = tmp("base")
        defer { try? fm.removeItem(at: base) }

        // ref-name validation agrees with git
        let names = ["feature/ok", "bugfix/a-b_c.d", "a", "", " ", "has space", "a..b", "-lead", "end.", "x.lock", "a/.hidden", "a//b",
                     "tilde~1", "caret^", "colon:x", "q?", "star*", "br[ack", "back\\slash", "at@{x","/lead", "trail/", "sp ace/x", "ünï/çode"]
        for n in names {
            let git = (try? GitRepo.execute(["check-ref-format", "--branch", n], in: base)) != nil
            let ours = GitRefName.validate(n) == nil
            // git rejects "" and a lone "-x" the same way; only compare where git gives a definite answer for non-empty names
            if !n.isEmpty { check("ref name “\(n)” validates like git", git == ours) }
        }
        check("empty name is rejected", GitRefName.validate("") != nil)

        // set up origin + two clones
        let origin = base.appendingPathComponent("origin.git")
        try? fm.createDirectory(at: origin, withIntermediateDirectories: true)
        _ = try? GitRepo.execute(["init", "-q", "--bare", "-b", "main"], in: origin)
        let seed = base.appendingPathComponent("seed")
        try? fm.createDirectory(at: seed, withIntermediateDirectories: true)
        _ = try? GitRepo.execute(["init", "-q", "-b", "main"], in: seed)
        let sr = GitRepo(root: seed); configure(sr)
        commit(sr, "f.txt", "base\n", "base commit")
        commit(sr, "g.txt", "g\n", "second commit")
        sh(sr, ["remote", "add", "origin", origin.path])
        sh(sr, ["push", "-q", "-u", "origin", "main"])
        let work = base.appendingPathComponent("work")
        let r = clone(of: origin, into: work)
        let other = clone(of: origin, into: base.appendingPathComponent("other"))

        var list = (try? r.branchList()) ?? BranchList()
        check("branchList finds main as current", list.current == "main" && list.local.first?.isCurrent == true && list.local.map(\.name) == ["main"])
        check("branchList finds origin/main and the remote", list.remote.map(\.name) == ["origin/main"] && list.remotes == ["origin"])
        check("branch entry has subject and hash", list.local.first?.subject == "second commit" && !(list.local.first?.hash.isEmpty ?? true))
        check("remote entry knows its remote and short name", list.remote.first?.remote == "origin" && list.remote.first?.shortName == "main")
        check("tracking branch has upstream, no ahead/behind", list.local.first?.upstream == "origin/main" && list.local.first?.ahead == 0 && list.local.first?.behind == 0)

        // create
        do { try r.createBranch(named: "feature/a", from: nil, checkout: true, overwrite: false) } catch { check("create+checkout feature/a: \(error)", false) }
        list = (try? r.branchList()) ?? BranchList()
        check("create checks out the new branch", list.current == "feature/a")
        check("new branch is a local entry", list.local.contains { $0.name == "feature/a" && $0.isCurrent })
        check("create rejects an existing name", (try? r.createBranch(named: "feature/a", from: nil, checkout: false, overwrite: false)) == nil)
        check("create rejects an invalid name", (try? r.createBranch(named: "bad name", from: nil, checkout: false, overwrite: false)) == nil)
        commit(r, "a.txt", "a\n", "commit on feature/a")
        check("create without checkout leaves HEAD", (try? r.createBranch(named: "side", from: "main", checkout: false, overwrite: false)) != nil && ((try? r.branchList())?.current == "feature/a"))
        check("create at a start point", sh(r, ["rev-parse", "side"]) == sh(r, ["rev-parse", "main"]))
        check("overwrite resets an existing branch", (try? r.createBranch(named: "side", from: "feature/a", checkout: false, overwrite: true)) != nil
              && sh(r, ["rev-parse", "side"]) == sh(r, ["rev-parse", "feature/a"]))
        check("create from a tag/commit", {
            sh(r, ["tag", "v1", "main"])
            return (try? r.createBranch(named: "from-tag", from: "v1", checkout: false, overwrite: false)) != nil && sh(r, ["rev-parse", "from-tag"]) == sh(r, ["rev-parse", "v1"])
        }())
        check("resolves() knows branches, tags and hashes", r.resolves("main") && r.resolves("v1") && r.resolves(String(sh(r, ["rev-parse", "HEAD"]).prefix(7))) && !r.resolves("nope"))
        check("localBranchExists", r.localBranchExists("side") && !r.localBranchExists("nope"))

        // ahead / behind
        sh(r, ["push", "-q", "-u", "origin", "feature/a"])
        commit(r, "a2.txt", "a2\n", "second on feature/a")
        list = (try? r.branchList()) ?? BranchList()
        check("ahead count after a local commit", list.local.first { $0.name == "feature/a" }?.ahead == 1)
        sh(other, ["fetch", "-q"]); sh(other, ["checkout", "-q", "-b", "feature/a", "origin/feature/a"])
        commit(other, "o.txt", "o\n", "remote-side commit")
        sh(other, ["push", "-q"])
        sh(other, ["checkout", "-q", "-b", "feature/remote-only", "main"])
        commit(other, "ro.txt", "ro\n", "remote only branch commit")
        sh(other, ["push", "-q", "-u", "origin", "feature/remote-only"])
        try? r.fetch()
        list = (try? r.branchList()) ?? BranchList()
        let fa = list.local.first { $0.name == "feature/a" }
        check("ahead and behind after fetch", fa?.ahead == 1 && fa?.behind == 1)
        check("status info agrees with branch list", (try? r.branchInfo())?.ahead == 1 && (try? r.branchInfo())?.behind == 1)

        // remote tracking checkout
        check("remote-only branch is listed", list.remote.contains { $0.name == "origin/feature/remote-only" })
        check("no local branch for it yet", !r.localBranchExists("feature/remote-only"))
        do { try r.checkoutTarget("origin/feature/remote-only") } catch { check("remote checkout: \(error)", false) }
        list = (try? r.branchList()) ?? BranchList()
        check("remote checkout creates a tracking local branch", list.current == "feature/remote-only"
              && list.local.first { $0.name == "feature/remote-only" }?.upstream == "origin/feature/remote-only")
        try? r.checkoutTarget("main")
        do { try r.checkoutTarget("origin/feature/remote-only") } catch { check("remote checkout with existing local: \(error)", false) }
        check("remote checkout with an existing local just switches", ((try? r.branchList())?.current) == "feature/remote-only")
        check("recent branches lists previous checkouts", { let l = (try? r.branchList()) ?? BranchList(); return l.recent.contains("main") && !l.recent.contains("feature/remote-only") }())

        // detached checkout of a tag / revision
        do { try r.checkoutTarget("v1") } catch { check("tag checkout: \(error)", false) }
        list = (try? r.branchList()) ?? BranchList()
        check("tag checkout detaches HEAD", list.detached && list.current == "")
        try? r.checkoutTarget("main")

        // compare
        if let cmp = try? r.compare(with: "feature/a") {
            check("compare: commits only in the other branch", cmp.onlyInOther.map(\.subject) == ["second on feature/a", "commit on feature/a"])
            check("compare: no commits only in main", cmp.onlyInCurrent.isEmpty)
            check("compare: changed files", Set(cmp.files.map(\.path)) == ["a.txt", "a2.txt"] && cmp.files.allSatisfy { $0.status == "A" })
        } else { check("compare works", false) }

        // merge
        do { try r.mergeIntoCurrent("feature/a") } catch { check("merge: \(error)", false) }
        check("merge brings the other branch's files in", fm.fileExists(atPath: work.appendingPathComponent("a2.txt").path))

        // rebase
        sh(r, ["checkout", "-q", "-b", "topic", "v1"])
        commit(r, "t.txt", "t\n", "topic commit")
        sh(r, ["checkout", "-q", "main"])
        commit(r, "m.txt", "m\n", "main moved")
        do { try r.checkoutAndRebase("topic") } catch { check("checkout and rebase: \(error)", false) }
        check("checkout and rebase puts topic on top of main", (try? r.branchList())?.current == "topic"
              && fm.fileExists(atPath: work.appendingPathComponent("m.txt").path) && fm.fileExists(atPath: work.appendingPathComponent("t.txt").path)
              && sh(r, ["log", "-1", "--format=%s"]).hasPrefix("topic commit"))
        sh(r, ["checkout", "-q", "main"])
        sh(r, ["checkout", "-q", "-b", "topic2", "v1"])
        commit(r, "t2.txt", "t2\n", "topic2 commit")
        do { try r.rebaseCurrent(onto: "main") } catch { check("rebase current onto selected: \(error)", false) }
        check("rebase current onto selected", (try? r.git(["merge-base", "--is-ancestor", "main", "topic2"])) != nil)
        // conflicting rebase leaves the operation in progress and reports it
        sh(r, ["checkout", "-q", "main"])
        commit(r, "c.txt", "main side\n", "main c")
        sh(r, ["checkout", "-q", "-b", "conflicting", "v1"])
        commit(r, "c.txt", "branch side\n", "branch c")
        sh(r, ["checkout", "-q", "main"])
        check("conflicting checkout+rebase throws", (try? r.checkoutAndRebase("conflicting")) == nil)
        check("conflicting rebase is reported as in progress", r.operationInProgress() == .rebase)
        try? r.abortOperation(.rebase)
        check("abort returns to a clean state", r.operationInProgress() == nil)
        sh(r, ["checkout", "-q", "main"])

        // push / upstream
        sh(r, ["checkout", "-q", "main"])
        try? r.createBranch(named: "to-push", from: nil, checkout: false, overwrite: false)
        list = (try? r.branchList()) ?? BranchList()
        if let e = list.local.first(where: { $0.name == "to-push" }) {
            do { try r.pushBranch(e) } catch { check("push new branch: \(error)", false) }
            list = (try? r.branchList()) ?? BranchList()
            check("push sets upstream", list.local.first { $0.name == "to-push" }?.upstream == "origin/to-push" && list.remote.contains { $0.name == "origin/to-push" })
        } else { check("to-push branch exists", false) }

        // rename
        do { try r.renameBranch("to-push", to: "pushed") } catch { check("rename: \(error)", false) }
        check("rename moves the branch", r.localBranchExists("pushed") && !r.localBranchExists("to-push"))
        check("rename refuses an existing name", (try? r.renameBranch("pushed", to: "main")) == nil)
        check("rename refuses an invalid name", (try? r.renameBranch("pushed", to: "a b")) == nil)

        // delete
        check("delete refuses an unmerged branch", { do { try r.deleteLocalBranch("conflicting", force: false); return false } catch { return GitRepo.isUnmergedRefusal(error) } }())
        check("force delete removes it", (try? r.deleteLocalBranch("conflicting", force: true)) != nil && !r.localBranchExists("conflicting"))
        check("delete refuses the current branch", (try? r.deleteLocalBranch("main", force: true)) == nil)
        check("delete merged branch", (try? r.deleteLocalBranch("side", force: false)) != nil && !r.localBranchExists("side"))
        list = (try? r.branchList()) ?? BranchList()
        if let remote = list.remote.first(where: { $0.name == "origin/to-push" }) {
            check("delete remote branch", (try? r.deleteRemoteBranch(remote)) != nil)
            try? r.fetch()
            check("remote branch gone after fetch", !((try? r.branchList())?.remote.contains { $0.name == "origin/to-push" } ?? true))
        } else { check("origin/to-push listed before delete", false) }

        // dirty tree: normal checkout carries unrelated changes, refuses conflicting ones, then smart / force
        sh(r, ["checkout", "-q", "main"])
        sh(r, ["checkout", "-q", "-b", "edits-f", "main"])
        commit(r, "f.txt", "changed on branch\n", "edit f on branch")
        sh(r, ["checkout", "-q", "main"])
        write(r, "f.txt", "my local edit\n")
        write(r, "untracked.txt", "u\n")
        check("dirty tree is detected", r.hasLocalChanges())
        var overwritten: [String] = []
        do { try r.checkoutTarget("edits-f"); check("conflicting checkout is refused", false) }
        catch let f as CheckoutFailure { if case .localChanges(let files, _) = f { overwritten = files }; check("conflicting checkout is refused with the file list", overwritten == ["f.txt"]) }
        catch { check("conflicting checkout failure type: \(error)", false) }
        check("refused checkout stays on the branch with changes intact", (try? r.branchList())?.current == "main" && ((try? String(contentsOf: work.appendingPathComponent("f.txt"))) ?? "") == "my local edit\n")
        do {
            let out = try r.smartCheckout("edits-f")
            check("smart checkout reports conflicts", out == .conflicts(["f.txt"]))
        } catch { check("smart checkout: \(error)", false) }
        check("smart checkout switched branch and kept the stash on conflict", (try? r.branchList())?.current == "edits-f" && !((try? r.stashList()) ?? []).isEmpty)
        check("smart checkout restored the untracked file", fm.fileExists(atPath: work.appendingPathComponent("untracked.txt").path))
        // clean up the conflicted state, then test the clean smart path
        sh(r, ["checkout", "-q", "--", "."]); sh(r, ["reset", "-q", "--hard"])
        for _ in 0..<5 where !((try? r.stashList()) ?? []).isEmpty { try? r.stashDrop(index: 0) }
        try? r.checkoutTarget("main")
        write(r, "g.txt", "local change to g\n")
        do {
            let out = try r.smartCheckout("feature/a")
            check("smart checkout re-applies changes cleanly", out == .clean && ((try? String(contentsOf: work.appendingPathComponent("g.txt"))) ?? "") == "local change to g\n")
        } catch { check("smart checkout (clean): \(error)", false) }
        check("smart checkout leaves no stash behind", ((try? r.stashList()) ?? []).isEmpty)
        sh(r, ["checkout", "-q", "--", "."])
        try? r.checkoutTarget("main")
        write(r, "f.txt", "to be discarded\n")
        do { try r.checkoutTarget("edits-f", force: true) } catch { check("force checkout: \(error)", false) }
        check("force checkout discards local changes", (try? r.branchList())?.current == "edits-f"
              && ((try? String(contentsOf: work.appendingPathComponent("f.txt"))) ?? "") == "changed on branch\n")
        check("smart checkout on a clean tree is a plain checkout", { (try? r.smartCheckout("main")) == .clean && (try? r.branchList())?.current == "main" }())

        // pull into current (merge) from a remote branch
        sh(r, ["checkout", "-q", "main"])
        if let e = ((try? r.branchList())?.remote.first { $0.name == "origin/feature/a" }) {
            sh(r, ["reset", "-q", "--hard", "v1"])
            do { try r.pullIntoCurrent(e, rebase: false) } catch { check("pull into current: \(error)", false) }
            check("pull into current merges the remote branch", fm.fileExists(atPath: work.appendingPathComponent("o.txt").path))
        } else { check("origin/feature/a listed", false) }

        // favourites persist per repo
        check("favourites start empty", BranchFavorites.all(for: work).isEmpty)
        BranchFavorites.toggle("main", for: work)
        check("favourite toggles on", BranchFavorites.all(for: work) == ["main"] && BranchFavorites.all(for: seed).isEmpty)
        BranchFavorites.toggle("main", for: work)
        check("favourite toggles off", BranchFavorites.all(for: work).isEmpty)
        check("age labels", BranchAge.short(Date().timeIntervalSince1970 - 90) == "1m" && BranchAge.short(Date().timeIntervalSince1970 - 3 * 86_400) == "3d")
    }
}
