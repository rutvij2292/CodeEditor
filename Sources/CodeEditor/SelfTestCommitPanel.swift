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
}
