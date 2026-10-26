import AppKit

/// Headless checks for the docked terminal / AI-CLI workspace package.
extension SelfTest {
    /// Polls on the main queue (the checks run inside a main-queue block, so they cannot spin the run loop).
    private static func waitUntil(_ timeout: TimeInterval, _ cond: @escaping () -> Bool, then: @escaping () -> Void) {
        let end = Date().addingTimeInterval(timeout)
        func poll() {
            if cond() || Date() > end { then() } else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { poll() } }
        }
        poll()
    }

    /// Screen text with soft-wrap line breaks removed.
    private static func flat(_ term: TerminalPanelController) -> String { term.activeBufferText.replacingOccurrences(of: "\n", with: "") }

    private static func alive(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 }

    static func terminalChecks(app: AppDelegate, w: ProjectWindow, dir: URL, done: @escaping () -> Void) {
        terminalPureChecks(dir: dir)
        terminalWindowChecks(app: app, w: w, dir: dir, done: done)
    }

    // MARK: Pure logic

    private static func terminalPureChecks(dir: URL) {
        let esc: UInt8 = 0x1b
        let wrapped = TerminalBridge.pasteBytes("hi\nthere", bracketed: true)
        check("paste: bracketed wraps in ESC[200~ ... ESC[201~ and keeps newlines",
              wrapped == [esc, 0x5b, 0x32, 0x30, 0x30, 0x7e] + Array("hi\nthere".utf8) + [esc, 0x5b, 0x32, 0x30, 0x31, 0x7e])
        check("paste: unbracketed never contains a newline/return",
              TerminalBridge.pasteBytes("a\nb\r\n\nc\n", bracketed: false) == Array("a b c ".utf8)
              && !TerminalBridge.pasteBytes("x\ny", bracketed: false).contains(10))
        check("paste: plain @ref unbracketed is verbatim", TerminalBridge.pasteBytes("@a.php ", bracketed: false) == Array("@a.php ".utf8))

        let root = URL(fileURLWithPath: "/tmp/proj")
        check("relative path inside root", TerminalBridge.relativePath(URL(fileURLWithPath: "/tmp/proj/app/A.php"), root: root) == "app/A.php")
        check("path outside root stays absolute", TerminalBridge.relativePath(URL(fileURLWithPath: "/etc/hosts"), root: root) == "/etc/hosts")
        check("sibling prefix is not inside root", TerminalBridge.relativePath(URL(fileURLWithPath: "/tmp/proj2/a"), root: root) == "/tmp/proj2/a")
        check("mention plain", TerminalBridge.mention("app/A.php") == "@app/A.php")
        check("mention with spaces is quoted", TerminalBridge.mention("my dir/A b.php") == "@\"my dir/A b.php\"")
        check("file references: several files, trailing space",
              TerminalBridge.fileReferences([root.appendingPathComponent("a.php"), root.appendingPathComponent("x y/b.js")], root: root)
              == "@a.php @\"x y/b.js\" ")
        let text = "one\ntwo\nthree\nfour\n" as NSString
        check("line range: caret only", TerminalBridge.lineRange(in: text, selection: NSRange(location: 5, length: 0)) == (2, 2))
        check("line range: selection across lines", TerminalBridge.lineRange(in: text, selection: NSRange(location: 4, length: 9)) == (2, 3))
        check("line range: trailing newline excluded", TerminalBridge.lineRange(in: text, selection: NSRange(location: 4, length: 4)) == (2, 2))
        check("line range: whole file", TerminalBridge.lineRange(in: text, selection: NSRange(location: 0, length: text.length)) == (1, 4))
        check("selection reference: range / single line / quoted",
              TerminalBridge.selectionReference(path: "app/A.php", start: 3, end: 9) == "@app/A.php:3-9 "
              && TerminalBridge.selectionReference(path: "app/A.php", start: 3, end: 3) == "@app/A.php:3 "
              && TerminalBridge.selectionReference(path: "a b/A.php", start: 1, end: 2) == "@\"a b/A.php:1-2\" ")
        check("fenced block exact",
              TerminalBridge.fencedBlock(path: "app/A.php", start: 2, end: 3, text: "$a = 1;\nreturn $a;\n")
              == "app/A.php:2-3\n```php\n$a = 1;\nreturn $a;\n```\n")
        check("fenced block uses a longer fence around ```",
              TerminalBridge.fencedBlock(path: "n.md", start: 1, end: 1, text: "```x```").hasPrefix("n.md:1\n````markdown\n"))
        let d1 = FileProblems.Diagnostic(severity: 1, message: "Undefined variable $x", line: 12, column: 5, endLine: 12, endColumn: 7,
                                         source: "intelephense", code: "P1008")
        let d2 = FileProblems.Diagnostic(severity: 2, message: "Unused\nimport", line: 3, column: 1, endLine: 3, endColumn: 4, source: nil, code: nil)
        check("problems text exact",
              TerminalBridge.problemsText(path: "app/A.php", diagnostics: [d1, d2])
              == "Problems in app/A.php (1 error, 1 warning):\napp/A.php:12:5 error: Undefined variable $x [intelephense P1008]\napp/A.php:3:1 warning: Unused import\n")
        let c1 = GitChange(path: "app/A.php", origPath: nil, index: " ", work: "M", isConflict: false, isUntracked: false, isStaged: false)
        let c2 = GitChange(path: "new.txt", origPath: nil, index: "?", work: "?", isConflict: false, isUntracked: true, isStaged: false)
        check("change summary",
              TerminalBridge.changeSummary(branch: "main", changes: [c1, c2], stat: " app/A.php | 2 +-\n 1 file changed\n")
              == "Changed files on main (2):\n  M app/A.php\n ?? new.txt\n\n app/A.php | 2 +-\n 1 file changed\n")

        // Dock geometry.
        check("dock math: default is 42% of editor area, min 320",
              TerminalDockMath.defaultWidth(total: 1200, sidebar: 260) == 395 && TerminalDockMath.defaultWidth(total: 700, sidebar: 200) == 320)
        check("dock math: auto-collapse when editor < 400",
              TerminalDockMath.fits(total: 1200, sidebar: 260, terminal: 395) && !TerminalDockMath.fits(total: 900, sidebar: 260, terminal: 395)
              && TerminalDockMath.fits(total: 1100, sidebar: 0, terminal: 320))
        check("dock math: clamp keeps terminal >= 320 and leaves the editor room",
              TerminalDockMath.clamp(900, total: 1200, sidebar: 260) == 538 && TerminalDockMath.clamp(100, total: 1200, sidebar: 260) == 320
              && TerminalDockMath.clamp(500, total: 700, sidebar: 260) == 320)

        // Idle / bell state machine with a fake clock.
        var t = TerminalIdleTracker(); t.idleSeconds = 4
        let t0 = Date(timeIntervalSince1970: 1000)
        t.output(1, at: t0, watched: true)
        check("idle: watched output never goes pending", !t.anyPending)
        t.output(1, at: t0, watched: false)
        check("idle: unwatched output is pending, not done", t.isPending(1) && !t.isDone(1))
        check("idle: not done before N seconds", t.tick(at: t0.addingTimeInterval(3.9)).isEmpty)
        t.output(1, at: t0.addingTimeInterval(3.9), watched: false)
        check("idle: more output postpones", t.tick(at: t0.addingTimeInterval(7.0)).isEmpty)
        check("idle: done after N quiet seconds", t.tick(at: t0.addingTimeInterval(7.9)) == [1] && t.isDone(1) && !t.isPending(1))
        check("idle: fires once", t.tick(at: t0.addingTimeInterval(20)).isEmpty)
        t.output(1, at: t0.addingTimeInterval(21), watched: false)
        check("idle: done stays done on later output", t.isDone(1) && !t.isPending(1))
        t.clear(1)
        check("idle: clear resets", !t.isDone(1) && !t.anyPending)
        check("bell: marks done immediately", t.bell(2, watched: false) && t.isDone(2) && !t.bell(2, watched: false))
        check("bell: ignored while watched", !t.bell(3, watched: true) && !t.isDone(3))

        // Agents: fake CLIs on a temp PATH.
        let bin = dir.appendingPathComponent("fakebin")
        try? FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        for n in ["claude", "gemini"] {
            let f = bin.appendingPathComponent(n)
            try? "#!/bin/sh\necho \(n)\n".write(to: f, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: f.path)
        }
        try? "not executable".write(to: bin.appendingPathComponent("codex"), atomically: true, encoding: .utf8)
        let found = TerminalAgents.detected(path: bin.path)
        check("agents: only CLIs on PATH are offered (claude x3, gemini; not the non-executable codex)",
              found.map(\.title) == ["Claude Code", "Claude Code: continue", "Claude Code: resume", "Gemini CLI"]
              && found.map(\.command) == ["claude", "claude --continue", "claude --resume", "gemini"])
        check("agents: nothing found on an empty PATH", TerminalAgents.detected(path: "/nonexistent").isEmpty)
        let custom = TerminalAgents.parseCustom("# my tools\nAider Sonnet | aider --model sonnet\n\nllm chat\nbroken |\n")
        check("agents: custom Title|command parsing",
              custom == [TerminalAgent(title: "Aider Sonnet", command: "aider --model sonnet"), TerminalAgent(title: "llm chat", command: "llm chat")])
        let all = TerminalAgents.all(path: bin.path, custom: "Gem | gemini\nMine|mine --x", legacy: "legacy-cli")
        check("agents: detected + custom + legacy, duplicates dropped",
              all.map(\.title) == ["Claude Code", "Claude Code: continue", "Claude Code: resume", "Gemini CLI", "Mine", "AI agent: legacy-cli"])
        TerminalAgents.lastUsedCommand = "gemini"
        check("agents: button primary is the last used agent", TerminalAgents.primary(in: found)?.command == "gemini")
        TerminalAgents.lastUsedCommand = "gone"
        check("agents: primary falls back to the first agent", TerminalAgents.primary(in: found)?.command == "claude")
        TerminalAgents.lastUsedCommand = nil
    }

    // MARK: Window / controller

    private static func terminalWindowChecks(app: AppDelegate, w: ProjectWindow, dir: URL, done: @escaping () -> Void) {
        let fm = FileManager.default
        let savedHooks = TerminalPanelController.testHooks
        let savedDelay = TerminalPanelController.shellReadyDelay
        let savedLooking = TerminalPanelController.isUserLooking
        let savedPrefDock = Prefs.terminalDock
        TerminalPanelController.testHooks.executable = "/bin/cat"
        TerminalPanelController.shellReadyDelay = 0
        TerminalPanelController.isUserLooking = { _ in false }
        var badges: [(String?, Bool)] = []
        TerminalNotifier.sink = { badge, attention in badges.append((badge, attention)) }
        TerminalNotifier.appIsActive = { false }
        Prefs.terminalDock = "right"
        Prefs.terminalNotifyOnIdle = true
        let restoreGlobals = {
            TerminalPanelController.testHooks = savedHooks
            TerminalPanelController.shellReadyDelay = savedDelay
            TerminalPanelController.isUserLooking = savedLooking
            TerminalNotifier.sink = nil
            TerminalNotifier.appIsActive = { NSApp?.isActive ?? false }
            Prefs.terminalDock = savedPrefDock
        }

        let project = dir.appendingPathComponent("termproj")
        let spaced = project.appendingPathComponent("dir with space/a b.php")
        let plain = project.appendingPathComponent("app/Http/Ctl.php")
        for (url, body) in [(spaced, "<?php\n// space\n"), (plain, "<?php\nclass Ctl\n{\n    function a() {}\n}\n")] {
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? body.write(to: url, atomically: true, encoding: .utf8)
        }
        let savedDir = SessionStore.directory
        SessionStore.directory = dir.appendingPathComponent("term-sessions")
        SessionStore.forceEnabled = true

        let tw = app.openProject(project)
        tw.window.setContentSize(NSSize(width: 1400, height: 900))
        tw.window.contentView?.layoutSubtreeIfNeeded()
        tw.mainSplit.splitView.setPosition(260, ofDividerAt: 0)
        tw.window.contentView?.layoutSubtreeIfNeeded()
        guard let term = tw.terminalPanel else { check("terminal controller exists", false); restoreGlobals(); done(); return }
        check("terminal: lazy start (no shell before first show)", term.tabCount == 0 && !tw.isTerminalVisible && tw.terminalDockSide == "right")
        check("terminal: right dock is a third split item with min width 320",
              tw.termDock.terminalItem.minimumThickness == 320 && tw.termDock.terminalItem.isCollapsed)

        // Right dock.
        tw.showTerminalPanel(focus: false)
        tw.window.contentView?.layoutSubtreeIfNeeded()
        check("terminal: show right dock starts exactly one shell", tw.isTerminalVisible && term.tabCount == 1 && term.shellPIDs.count == 1)
        let width = tw.terminalDockWidth
        check("terminal: default width ~42% of the editor area (>= 320)", width >= 320 && abs(width - TerminalDockMath.defaultWidth(total: tw.mainSplit.splitView.bounds.width, sidebar: tw.termDock.sidebarItem.viewController.view.frame.width)) < 3)
        check("terminal: terminal view lives in the right host", term.view.superview === tw.termDock.host)
        let pid = term.shellPIDs[0], view0 = term.activeTerminalView
        let editorWidth = tw.tabs.frame.width
        check("terminal: editor keeps >= 400 pt at 1400", editorWidth >= 400)

        // Live dock switch keeps the same view and process.
        Prefs.terminalDock = "bottom"
        check("dock switch: right -> bottom keeps view, shell and visibility",
              tw.terminalDockSide == "bottom" && tw.isTerminalVisible && term.activeTerminalView === view0
              && term.shellPIDs == [pid] && alive(pid) && tw.termDock.terminalItem.isCollapsed
              && tw.bottom.selectedID == "terminal" && term.view.isDescendant(of: tw.bottom.view))
        Prefs.terminalDock = "right"
        tw.window.contentView?.layoutSubtreeIfNeeded()
        check("dock switch: bottom -> right keeps view, shell and visibility",
              tw.terminalDockSide == "right" && tw.isTerminalVisible && term.activeTerminalView === view0
              && term.shellPIDs == [pid] && alive(pid) && !tw.bottom.has("terminal") && term.view.superview === tw.termDock.host
              && !tw.bottom.isVisible)
        tw.toggleTerminal()
        check("toggle: hides (process keeps running)", !tw.isTerminalVisible && alive(pid) && term.tabCount == 1)
        Prefs.terminalDock = "bottom"
        check("dock switch while hidden stays hidden", tw.terminalDockSide == "bottom" && !tw.isTerminalVisible && tw.bottom.has("terminal"))
        tw.toggleTerminal()
        check("bottom dock: toggle shows the bottom Terminal tab, same shell", tw.isTerminalVisible && tw.bottom.isVisible && term.shellPIDs == [pid])
        tw.maximizeTerminal()
        check("maximize (bottom): editor split collapses", tw.isTerminalMaximized && tw.termDock.mainItem.isCollapsed)
        tw.maximizeTerminal()
        check("maximize (bottom): toggles back", !tw.isTerminalMaximized && !tw.termDock.mainItem.isCollapsed)
        Prefs.terminalDock = "right"
        tw.window.contentView?.layoutSubtreeIfNeeded()
        tw.hideTerminal()
        tw.showTerminalPanel(focus: false)
        tw.window.contentView?.layoutSubtreeIfNeeded()

        // Maximize (right) and restore.
        tw.maximizeTerminal()
        tw.window.contentView?.layoutSubtreeIfNeeded()
        check("maximize (right): sidebar + editor collapse, terminal fills the width",
              tw.isTerminalMaximized && tw.termDock.sidebarItem.isCollapsed && tw.termDock.contentItem.isCollapsed
              && tw.termDock.host.frame.width > 1300)
        tw.maximizeTerminal()
        tw.window.contentView?.layoutSubtreeIfNeeded()
        check("maximize (right): restores sidebar, editor and width",
              !tw.isTerminalMaximized && !tw.termDock.sidebarItem.isCollapsed && !tw.termDock.contentItem.isCollapsed
              && abs(tw.terminalDockWidth - width) < 6 && tw.tabs.frame.width >= 400)

        // Auto-collapse on a narrow window and restore.
        tw.window.setContentSize(NSSize(width: 820, height: 700))
        tw.window.contentView?.layoutSubtreeIfNeeded()
        tw.reevaluateTerminalFit()
        check("auto-collapse: narrow window folds the terminal away", tw.isTerminalAutoCollapsed && !tw.isTerminalVisible && alive(pid))
        check("auto-collapse: still remembered as visible for the session", tw.captureTerminalState().visible)
        tw.window.setContentSize(NSSize(width: 1400, height: 900))
        tw.window.contentView?.layoutSubtreeIfNeeded()
        tw.reevaluateTerminalFit()
        tw.window.contentView?.layoutSubtreeIfNeeded()
        check("auto-collapse: wide again restores terminal at its old width",
              !tw.isTerminalAutoCollapsed && tw.isTerminalVisible && abs(tw.terminalDockWidth - width) < 6)

        // Persistence round trip (CE_RESTORE-style).
        tw.open(plain)
        tw.termDock.width = 420
        tw.saveSession()
        let saved = SessionStore.load(for: project)
        check("session stores terminal dock, width and visibility",
              saved?.terminal?.dock == "right" && saved?.terminal?.visible == true && abs((saved?.terminal?.width ?? 0) - Double(tw.terminalDockWidth)) < 1)
        let legacy = try? JSONDecoder().decode(Session.self, from: Data("{\"tabs\":[],\"expanded\":[]}".utf8))
        check("old session files without a terminal key still load", legacy != nil && legacy?.terminal == nil)
        tw.hideTerminal()
        tw.restoreTerminalState(Session.TerminalState(dock: "bottom", width: 500, visible: true))
        check("restore: dock side and width come back, the terminal stays closed by default",
              tw.terminalDockSide == "bottom" && !tw.isTerminalVisible && tw.termDock.width == 500 && term.shellPIDs == [pid])
        Prefs.reopenTerminal = true
        tw.restoreTerminalState(Session.TerminalState(dock: "bottom", width: 500, visible: true))
        check("restore: with 'reopen terminal' on, it comes back", tw.terminalDockSide == "bottom" && tw.isTerminalVisible && term.shellPIDs == [pid])
        Prefs.reopenTerminal = false
        tw.hideTerminal()
        tw.restoreTerminalState(Session.TerminalState(dock: "right", width: 500, visible: false))
        check("restore: hidden right dock", tw.terminalDockSide == "right" && !tw.isTerminalVisible && alive(pid))
        tw.showTerminalPanel(focus: false)
        tw.window.contentView?.layoutSubtreeIfNeeded()

        // Editor <-> terminal bridge.
        func pastedAfter(_ action: () -> String?) -> (String?, [UInt8]) {
            term.lastPasteBytes = []
            let r = action()
            return (r, term.lastPasteBytes)
        }
        tw.open(plain)
        tw.window.makeFirstResponder(tw.current?.textView)
        let (ref, refBytes) = pastedAfter { tw.sendFileReference() }
        check("bridge: @file reference pasted verbatim, no Return", ref == "@app/Http/Ctl.php " && refBytes == Array("@app/Http/Ctl.php ".utf8))
        check("bridge: pasting shows the terminal", tw.isTerminalVisible)
        tw.open(spaced)
        let (sref, _) = pastedAfter { tw.sendFileReference() }
        check("bridge: path with spaces is quoted", sref == "@\"dir with space/a b.php\" ")
        tw.open(plain)
        if let tv = tw.current?.textView {
            tv.setSelectedRange(NSRange(location: 6, length: 24))   // "class Ctl\n{\n    function" spans lines 2-4
            let (sel, _) = pastedAfter { tw.sendSelectionReference() }
            check("bridge: selection reference with 1-based range", sel == "@app/Http/Ctl.php:2-4 ")
            let (blk, _) = pastedAfter { tw.sendSelectionText() }
                check("bridge: selection text fenced with header line",
                  blk == "app/Http/Ctl.php:2-4\n```php\nclass Ctl\n{\n    function\n```\n")
            tv.setSelectedRange(NSRange(location: 8, length: 0))
            let (cur, _) = pastedAfter { tw.sendSelectionReference() }
            check("bridge: caret only refers to the current line", cur == "@app/Http/Ctl.php:2 ")
        } else { check("bridge: editor available", false) }
        check("bridge: no problems -> nothing pasted", tw.sendProblems() == nil)
        tw.window.makeFirstResponder(tw.tree.outline)
        tw.tree.reveal(plain)
        let (treeRef, _) = pastedAfter { tw.sendFileReference() }
        check("bridge: tree selection is referenced when the tree has focus", treeRef == "@app/Http/Ctl.php ")
        term.lastPasteBytes = []
        term.simulateDrop([plain, spaced])
        check("bridge: dropping files pastes their @references",
              String(decoding: term.lastPasteBytes, as: UTF8.self) == "@app/Http/Ctl.php @\"dir with space/a b.php\" ")

        // Bracketed paste once the program enabled it; real pty round trip without Return.
        term.feedSample("\u{1b}[?2004h")
        term.paste("@x.php ")
        check("paste: bracketed when the program enabled mode 2004",
              term.lastPasteBytes == [0x1b, 0x5b, 0x32, 0x30, 0x30, 0x7e] + Array("@x.php ".utf8) + [0x1b, 0x5b, 0x32, 0x30, 0x31, 0x7e])
        term.feedSample("\u{1b}[?2004l")
        term.paste("MARKER_PASTE_123")
        waitUntil(2.0, { flat(term).contains("MARKER_PASTE_123") }) {
        let occurrences = flat(term).components(separatedBy: "MARKER_PASTE_123").count - 1
        check("paste: reaches the shell and is NOT submitted (only the tty echo, cat never printed it back)", occurrences == 1)

        // Agents in the terminal.
        let tabsBefore = term.tabCount
        term.startAgent(TerminalAgent(title: "Claude Code", command: "echo AGENT_STARTED_42"))
        waitUntil(2.0, { flat(term).contains("AGENT_STARTED_42") }) {
        check("agent: opens a NEW tab titled with the agent name and types the command",
              term.tabCount == tabsBefore + 1 && term.activeTitle == "Claude Code" && flat(term).contains("echo AGENT_STARTED_42"))
        check("agent: remembered as last used", TerminalAgents.lastUsedCommand == "echo AGENT_STARTED_42")
        TerminalAgents.lastUsedCommand = nil
        let menuTitles = term.runMenu().items.map(\.title)
        check("run menu lists agent section and project commands", menuTitles.contains("php -v"))
        check("agent menu never empty-crashes", !term.agentMenu().items.isEmpty)

        // Notifications with a fake clock.
        var now = Date(timeIntervalSince1970: 5000)
        term.clock = { now }
        badges.removeAll()
        term.newTab()
        let bg = term.activeIndex
        term.select(0)
        term.simulateOutput(tab: bg)
        check("notify: background output marks unread, not done", term.tabUnread(bg) && !term.tabDone(bg) && term.attention == .activity)
        term.processIdle(at: now.addingTimeInterval(2))
        check("notify: still quiet-waiting at 2 s", !term.tabDone(bg))
        term.processIdle(at: now.addingTimeInterval(5))
        check("notify: done after 4 s of silence, dock badge + attention request",
              term.tabDone(bg) && term.attention == .done && badges.last?.0 == "1" && badges.last?.1 == true)
        check("notify: status bar shows the dot", tw.statusBar.terminalDotVisible && tw.statusBar.terminalAttention == .done)
        term.select(bg)
        check("notify: focusing the tab clears done and the dock badge", !term.tabDone(bg) && !term.tabUnread(bg) && badges.last?.0 == nil)
        term.select(0)
        term.cycleTab(1)
        check("tabs: cycling forward moves to the next tab", term.activeIndex == 1)
        term.cycleTab(1); term.cycleTab(1)
        check("tabs: cycling wraps around", term.activeIndex == (1 + 2) % term.tabCount)
        term.select(0); term.cycleTab(-1)
        check("tabs: cycling back from the first wraps to the last", term.activeIndex == term.tabCount - 1)
        term.select(0)
        badges.removeAll()
        term.simulateBell(tab: bg)
        check("notify: BEL marks the tab done immediately", term.tabDone(bg) && badges.last?.0 == "1")
        term.select(bg)
        TerminalPanelController.isUserLooking = { _ in true }
        term.simulateOutput(tab: bg)
        check("notify: output in the watched visible tab is ignored", !term.tabUnread(bg))
        TerminalPanelController.isUserLooking = { _ in false }
        now = now.addingTimeInterval(100)
        Prefs.terminalNotifyOnIdle = false; Prefs.terminalAgentAlerts = false
        term.select(0)
        term.simulateBell(tab: bg)
        check("notify: disabled by Prefs.terminalNotifyOnIdle", !term.tabDone(bg))
        Prefs.terminalNotifyOnIdle = true; Prefs.terminalAgentAlerts = true

        // Status bar toggle.
        tw.statusBar.clickTerminalButton()
        check("status bar: toggle button hides the terminal", !tw.isTerminalVisible)
        tw.statusBar.clickTerminalButton()
        check("status bar: toggle button shows it again", tw.isTerminalVisible)
        tw.window.makeFirstResponder(tw.current?.textView)
        tw.toggleTerminalFocus()
        check("focus toggle: focuses the terminal", tw.isTerminalFocused)
        tw.toggleTerminalFocus()
        check("focus toggle: back to the editor", !tw.isTerminalFocused && tw.window.firstResponder === tw.current?.textView)

        // Sidebar toggle and Cmd-1 tree focus.
        let sidebarWasVisible = tw.isSidebarVisible
        tw.window.makeFirstResponder(tw.current?.textView)
        tw.toggleSidebar()
        check("sidebar: toggle hides it", tw.isSidebarVisible != sidebarWasVisible)
        tw.toggleSidebar()
        check("sidebar: toggle shows it again", tw.isSidebarVisible == sidebarWasVisible)
        tw.toggleProjectTree()
        check("cmd-1: shows the sidebar and focuses the tree", tw.isSidebarVisible && tw.isTreeFocused)
        tw.toggleProjectTree()
        check("cmd-1 again: hides the tree and returns to the editor", !tw.isSidebarVisible && tw.window.firstResponder === tw.current?.textView)
        tw.toggleProjectTree()
        check("cmd-1 from hidden: brings it back with focus", tw.isSidebarVisible && tw.isTreeFocused)
        tw.toggleSidebar()
        check("sidebar: hiding while the tree has focus moves focus to the editor", !tw.isTreeFocused && tw.window.firstResponder === tw.current?.textView)
        if !sidebarWasVisible { tw.toggleSidebar(); tw.toggleSidebar() } else { tw.toggleSidebar() }

        // Live prefs.
        Prefs.terminalFontSize = 17
        Prefs.terminalFontName = "Menlo"
        let f = (term.activeTerminalView as? CETerminalView)?.font
        check("live prefs: font size and family reach open terminals", f?.pointSize == 17 && f?.fontName.contains("Menlo") == true)
        Prefs.terminalCursorStyle = "beam"
        check("live prefs: cursor style applied", (term.activeTerminalView as? CETerminalView)?.terminal.options.cursorStyle == .steadyBar)
        Prefs.terminalFontSize = 12; Prefs.terminalFontName = ""; Prefs.terminalCursorStyle = "block"
        Prefs.terminalScrollback = 800
        Prefs.terminalScrollback = 5000
        Prefs.terminalShell = "/bin/sh"
        check("live prefs: shell preference resolves for new tabs", TerminalEnvironment.resolvedShell == "/bin/sh")
        Prefs.terminalShell = "/definitely/missing"
        check("live prefs: missing shell falls back to $SHELL", TerminalEnvironment.resolvedShell == TerminalEnvironment.userShell)
        Prefs.terminalShell = ""

        // Shutdown: process groups die, nothing is left behind as a zombie.
        let pids = term.shellPIDs
        check("shutdown: shells alive before closing", !pids.isEmpty && pids.allSatisfy(alive))
        tw.window.close()
        waitUntil(5.0, { pids.allSatisfy { !alive($0) } }) {
        check("shutdown: closing the window kills every shell and reaps it (no zombies)", pids.allSatisfy { !alive($0) } && term.tabCount == 0)
        check("shutdown: dock badge cleared", badges.last?.0 == nil)

        // CE_RESTORE-style reopen: fresh window restores the dock side.
        let again = app.openProject(project)
        check("restore: reopened project returns to the saved terminal state", again.terminalDockSide == "right" || again.terminalDockSide == "bottom")
        again.window.close()
        try? fm.removeItem(at: project)
        restoreGlobals()
        SessionStore.directory = savedDir; SessionStore.forceEnabled = false
        done()
        }   // shutdown wait
        }   // agent wait
        }   // paste wait
    }
}
