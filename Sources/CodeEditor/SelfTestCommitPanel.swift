import AppKit

/// CE_SELFTEST: the left-sidebar Commit panel (layouts, swap, diff preview tab, Commit/Stash tabs).
enum SelfTestCommitPanel {
    private static func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check(name, ok()) }

    /// A throwaway repo with one committed file `a.txt` that has an uncommitted edit, plus an untracked `b.txt`.
    static func makeRepo() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ce-commitpanel-\(getpid())-\(Int.random(in: 0..<99999))")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        func git(_ args: [String]) {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/git"); p.arguments = args; p.currentDirectoryURL = dir
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            try? p.run(); p.waitUntilExit()
        }
        git(["init", "-q"]); git(["config", "user.email", "t@t"]); git(["config", "user.name", "t"])
        try? "one\n".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        git(["add", "."]); git(["commit", "-qm", "init"])
        try? "one\ntwo\n".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try? "new\n".write(to: dir.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        return dir
    }

    static func descendants(of v: NSView) -> [NSView] { v.subviews + v.subviews.flatMap { descendants(of: $0) } }

    /// Spins the main run loop until `cond` holds or `seconds` pass.
    static func wait(_ seconds: Double = 5, _ cond: () -> Bool) {
        let end = Date().addingTimeInterval(seconds)
        while !cond(), Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    }

    static func run(w: ProjectWindow) {
        let repo = makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        layoutChecks(repo: repo)
        swapChecks(w: w, repo: repo)
        diffTabChecks(w: w, repo: repo)
        tabChecks(repo: repo)
        reviewChecks(w: w, repo: repo)
    }

    private static func layoutChecks(repo: URL) {
        let side = GitPanelController(root: repo, layout: .sidebar) { _ in }
        let log = GitPanelController(root: repo, layout: .log) { _ in }
        let sideViews = descendants(of: side.view), logViews = descendants(of: log.view)
        check("commit panel: sidebar layout has no Log/Changes mode switch", !sideViews.contains { $0 is NSSegmentedControl && ($0 as! NSSegmentedControl).label(forSegment: 1) == "Log" })
        check("commit panel: sidebar layout detaches the diff view", side.diffHost.superview == nil)
        check("commit panel: sidebar layout has the commit message box", sideViews.contains { $0 is NSTextView })
        check("commit panel: log layout has no commit message box", !logViews.contains { $0 is NSTextView && ($0 as! NSTextView).isEditable })
        side.reloadNowForTests()
        check("commit panel: hasDiff sees a modified and an untracked file", side.hasDiff(for: "a.txt") && side.hasDiff(for: "b.txt") && !side.hasDiff(for: "zzz.txt"))
    }

    private static func swapChecks(w: ProjectWindow, repo: URL) {
        let side = w.commitSidebar
        side.show(repo: repo)
        check("commit panel: Cmd-K swaps the panel in place of the file tree", side.isShowing && w.tree.panel.isHidden && side.panel?.view.isHidden == false)
        check("commit panel: the sidebar is expanded while it shows", !w.termDock.sidebarItem.isCollapsed)
        side.hide(restoreFocus: false)
        check("commit panel: hiding swaps the file tree back", !side.isShowing && !w.tree.panel.isHidden && side.panel?.view.isHidden == true)

        w.termDock.sidebarItem.isCollapsed = true
        side.show(repo: repo)
        check("commit panel: a collapsed sidebar expands for the panel", !w.termDock.sidebarItem.isCollapsed)
        side.hide(restoreFocus: false)
        check("commit panel: and collapses again when the panel hides", w.termDock.sidebarItem.isCollapsed)
        w.termDock.sidebarItem.isCollapsed = false

        side.show(repo: repo); side.show(repo: repo)
        check("commit panel: showing twice keeps one panel in the container", side.container.subviews.filter { $0 === side.panel?.view }.count == 1)
        side.hide(restoreFocus: false)
    }

    private static func diffTabChecks(w: ProjectWindow, repo: URL) {
        let side = w.commitSidebar, id = CommitSidebar.diffTabID
        func entries() -> [TabHost.Entry] { w.tabs.entries.filter { $0.id == id } }
        side.show(repo: repo)
        guard let panel = side.panel else { check("commit panel: panel exists for the diff tab checks", false); return }
        panel.reloadNowForTests()
        panel.select(path: "a.txt")
        check("commit panel: clicking a file opens one diff preview tab titled after it", entries().count == 1 && entries().first?.title == "a.txt (diff)")
        panel.select(path: "b.txt")
        check("commit panel: a second file reuses the same preview tab", entries().count == 1 && entries().first?.title == "b.txt (diff)")
        check("commit panel: the diff tab is not persisted in sessions", !w.captureSession().tabs.contains { $0.path == id })
        try? FileManager.default.removeItem(at: repo.appendingPathComponent("b.txt"))
        panel.reloadNowForTests()
        check("commit panel: the preview closes when its file has no changes left", entries().isEmpty)
        panel.select(path: "a.txt")
        side.hide(restoreFocus: false)
        check("commit panel: hiding the panel leaves the diff tab open", entries().count == 1)
        _ = w.close(id)
        check("commit panel: the diff tab closes like a viewer tab", entries().isEmpty)
    }

    private static func tabChecks(repo: URL) {
        let gp = GitPanelController(root: repo, layout: .sidebar) { _ in }
        gp.reloadNowForTests()
        check("commit panel: starts on the Commit tab", gp.sidebarTab == .commit && gp.commitTabVisible && !gp.stashTabContainsStashList)
        gp.showTab(.stash)
        check("commit panel: the Stash tab replaces the tree and message box with the stash list", !gp.commitTabVisible && gp.stashTabContainsStashList)
        gp.showTab(.commit)
        check("commit panel: back to the Commit tab", gp.commitTabVisible && !gp.stashTabContainsStashList)
        check("commit panel: groups start expanded", gp.groupCount > 0 && gp.expandedGroupCount == gp.groupCount)
        gp.collapseAllTapped()
        check("commit panel: Collapse All collapses every group", gp.expandedGroupCount == 0)
        gp.expandAllTapped()
        check("commit panel: Expand All expands every group", gp.expandedGroupCount == gp.groupCount)
    }

    /// Regressions the whole-branch review found.
    private static func reviewChecks(w: ProjectWindow, repo: URL) {
        let side = w.commitSidebar
        // Cmd-1 / focus-tree entry points swap the file tree back instead of focusing a hidden tree.
        side.show(repo: repo)
        w.toggleProjectTree()
        check("commit panel: Cmd-1 swaps the file tree back", !side.isShowing && !w.tree.panel.isHidden && !w.termDock.sidebarItem.isCollapsed)

        // Cmd-K with the panel showing but not focused focuses it; only a focused panel hides.
        side.show(repo: repo)
        w.window.makeFirstResponder(nil)
        side.toggle()
        check("commit panel: Cmd-K on an unfocused panel keeps it showing", side.isShowing)
        side.panel?.focusCommitMessage()
        side.toggle()
        check("commit panel: Cmd-K inside the panel hides it", !side.isShowing)

        // Hiding while the terminal is maximized must not bring the sidebar back.
        side.show(repo: repo)
        w.termDock.maximized = true
        w.termDock.sidebarItem.isCollapsed = true
        side.hide(restoreFocus: false)
        check("commit panel: hiding while the terminal is maximized leaves the sidebar collapsed", w.termDock.sidebarItem.isCollapsed)
        w.termDock.maximized = false
        w.termDock.sidebarItem.isCollapsed = false

        // The inline Stash tab has a real height (its buttons are clickable).
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
        let sv = GitStashView(inline: true)
        sv.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(sv)
        NSLayoutConstraint.activate([sv.topAnchor.constraint(equalTo: host.topAnchor), sv.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                                     sv.trailingAnchor.constraint(equalTo: host.trailingAnchor)])
        sv.show(stashes: [])
        host.layoutSubtreeIfNeeded()
        check("commit panel: the inline stash view has a non-zero height", sv.frame.height > 20)

        // RAM: the sidebar never builds the heavy Log view; the log layout does.
        let gs = GitPanelController(root: repo, layout: .sidebar) { _ in }
        let gl = GitPanelController(root: repo, layout: .log) { _ in }
        check("commit panel: the sidebar layout builds no Log view", !descendants(of: gs.view).contains { $0 is GitLogView })
        check("commit panel: the log layout has its Log view", descendants(of: gl.view).contains { $0 is GitLogView })
    }
}
