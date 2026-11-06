import AppKit

/// CE_SELFTEST: Git menu plumbing (tags, remotes, worktrees, patches, clone, reset, merge/rebase) on throwaway repos.
enum SelfTestGitMenu {
    private static func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check(name, ok()) }

    static func run(w: ProjectWindow) {
        let dir = SelfTestCommitPanel.makeRepo()
        let extra = dir.deletingLastPathComponent().appendingPathComponent(dir.lastPathComponent + "-wt")
        let cloneDest = dir.deletingLastPathComponent().appendingPathComponent(dir.lastPathComponent + "-clone")
        let patchFile = dir.deletingLastPathComponent().appendingPathComponent(dir.lastPathComponent + ".patch")
        defer { [dir, extra, cloneDest, patchFile].forEach { try? FileManager.default.removeItem(at: $0) } }
        let repo = GitRepo(root: dir)

        // the menu: every Git item is wired to a live action, and the PhpStorm set is present
        let gitMenu = NSApp.mainMenu?.items.first { $0.title == "Git" }?.submenu
        let titles = Set(gitMenu?.items.map(\.title) ?? [])
        let wanted = ["Merge…", "Rebase…", "Reset HEAD…", "Tag…", "Manage Remotes…", "Clone…", "Add Worktree…", "Open Worktree…",
                      "Create Patch from Local Changes…", "Apply Patch…", "Stash Changes…", "Show Git Log"]
        check("git menu: has every planned item", wanted.allSatisfy(titles.contains))
        check("git menu: every item is wired to a responding target",
              gitMenu?.items.filter { !$0.isSeparatorItem }.allSatisfy { $0.action != nil && ($0.target?.responds(to: $0.action) ?? false) } == true)
        let keys = (gitMenu?.items ?? []).filter { !$0.keyEquivalent.isEmpty }.map { "\($0.keyEquivalent)\($0.keyEquivalentModifierMask.rawValue)" }
        check("git menu: no duplicate shortcuts", keys.count == Set(keys).count)
        // the busy-form helper's validation path is pure; the ref-name rule it relies on rejects bad tags
        check("git menu: tag names are validated", GitRefName.validate("bad name") != nil && GitRefName.validate("v1.0") == nil)

        // tags
        try? repo.createTag("v1", at: nil, message: nil)
        try? repo.createTag("v2", at: "HEAD", message: "release two")
        check("git menu: tags lists lightweight and annotated tags", Set((try? repo.tags()) ?? []) == ["v1", "v2"])
        check("git menu: annotated tag keeps its message", ((try? repo.text(["tag", "-n1", "v2"])) ?? "").contains("release two"))
        try? repo.deleteTag("v1")
        check("git menu: delete tag", (try? repo.tags()) == ["v2"])

        // remotes
        try? repo.addRemote("origin", url: "https://example.invalid/x.git")
        check("git menu: add remote", (try? repo.remoteList()) == [GitRemote(name: "origin", url: "https://example.invalid/x.git")])
        try? repo.setRemoteURL("origin", url: "https://example.invalid/y.git")
        try? repo.renameRemote("origin", to: "up")
        check("git menu: edit + rename remote", (try? repo.remoteList()) == [GitRemote(name: "up", url: "https://example.invalid/y.git")])
        try? repo.removeRemote("up")
        check("git menu: remove remote", (try? repo.remoteList())?.isEmpty == true)

        // patch from local changes (a.txt modified, b.txt untracked), untracked files stay untracked
        let patch = (try? repo.patchOfLocalChanges()) ?? ""
        check("git menu: patch includes modified and untracked files", patch.contains("a.txt") && patch.contains("b.txt") && patch.contains("+two") && patch.contains("+new"))
        check("git menu: patch leaves untracked files untracked", ((try? repo.status()) ?? []).first { $0.path == "b.txt" }?.isUntracked == true)
        let only = (try? repo.patchOfLocalChanges(paths: ["a.txt"])) ?? ""
        check("git menu: patch limited to chosen paths", only.contains("a.txt") && !only.contains("b.txt"))
        try? patch.write(to: patchFile, atomically: true, encoding: .utf8)

        // commit everything, then worktrees on a new branch
        try? repo.git(["add", "."]); try? repo.git(["commit", "-qm", "two"])
        try? repo.addWorktree(at: extra.path, newBranch: "side", start: nil)
        let wts = (try? repo.worktreeList()) ?? []
        check("git menu: worktree list has main + linked", wts.count == 2 && wts[0].isMain && wts[1].branch == "side"
              && URL(fileURLWithPath: wts[1].path).resolvingSymlinksInPath().path == extra.resolvingSymlinksInPath().path)
        try? repo.removeWorktree(extra.path, force: false)
        check("git menu: remove worktree", ((try? repo.worktreeList()) ?? []).count == 1)

        // apply the saved patch on a clean reset
        try? repo.reset(to: "HEAD~1", mode: .hard)
        check("git menu: patch checks clean", (try? repo.applyPatch(patchFile, checkOnly: true)) != nil)
        try? repo.applyPatch(patchFile, checkOnly: false)
        check("git menu: patch applies", ((try? String(contentsOf: dir.appendingPathComponent("a.txt"))) ?? "").contains("two"))

        // clone
        try? repo.git(["checkout", "-q", "--", "."]); try? FileManager.default.removeItem(at: dir.appendingPathComponent("b.txt"))
        let cloned = try? GitRepo.clone(url: dir.path, into: cloneDest)
        check("git menu: clone creates a repo", cloned.flatMap { GitRepo.repoRoot(for: $0) } != nil)
        check("git menu: clone of a bad url throws", (try? GitRepo.clone(url: "/nonexistent/zzz", into: cloneDest.appendingPathExtension("x"))) == nil)
    }
}
