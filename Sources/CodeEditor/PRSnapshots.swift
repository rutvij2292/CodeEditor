import AppKit

/// CE_SNAPSHOT=1 CE_PICKER=pr-prompt|pr-resolver|pr-success: renders the PR windows off-screen with sample data (never shown).
enum PRSnapshots {
    private static var keep: [AnyObject] = []

    static func render(_ picker: String, to shot: String) {
        let out = shot.replacingOccurrences(of: ".png", with: "_\(picker).png")
        if picker == "pr-prompt" {
            let p = PRPromptController()
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 360), styleMask: [.titled], backing: .buffered, defer: false)
            win.contentView = p.view
            p.setText("#482")
            p.setDefaultBase("main")
            p.setGHStatus(false)
            win.contentView?.layoutSubtreeIfNeeded()
            win.setContentSize(NSSize(width: 500, height: p.view.fittingSize.height))
            keep.append(win); keep.append(p)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            Verification.render(p.view, to: out)
            return
        }
        let env = PRTestEnv.make()
        let repo = PRTestEnv.clone(env, "snap")
        var info = PRInfo(number: 7)
        info.title = "Fix billing totals and add proration"; info.headRef = "feature/x"; info.baseRef = "main"
        info.isCrossRepository = false; info.mergeable = "CONFLICTING"; info.viaGH = true; info.url = "https://github.com/acme/app/pull/7"
        guard let s = try? PRFlow.prepare(repo: repo, info: info, strategy: .merge, baseOverride: nil, stashDirty: false) else {
            fputs("pr snapshot: prepare failed\n", stderr); return
        }
        try? PRFlow.resolveWholeFile(repo, path: "composer.lock", yours: false, strategy: .merge)
        try? PRFlow.resolveWholeFile(repo, path: "logo.bin", yours: true, strategy: .merge)
        if picker == "pr-success" {
            try? repo.markResolved(path: "a.txt", content: PRTestEnv.aBase)
            try? PRFlow.resolveWholeFile(repo, path: "c.txt", yours: false, strategy: .merge)
        }
        let c = PRResolverController(repo: repo, session: s, project: nil)
        c.window.setContentSize(NSSize(width: 1320, height: 840))
        c.present()
        keep.append(c)
        // Spin the run loop here (the caller terminates on a timer that may already be due).
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        if picker == "pr-success" { c.showSuccessForSnapshot() }
        c.window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        if let v = c.window.contentView { Verification.render(v, to: out) }
        try? FileManager.default.removeItem(at: env.root)
    }
}
