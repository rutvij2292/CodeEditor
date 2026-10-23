import AppKit

/// Headless checks for agent attention alerts (hook socket, bell / title fallbacks) and the terminal find bar.
extension SelfTest {
    private static func alertWait(_ timeout: TimeInterval, _ cond: @escaping () -> Bool, then: @escaping () -> Void) {
        let end = Date().addingTimeInterval(timeout)
        func poll() {
            if cond() || Date() > end { then() } else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { poll() } }
        }
        poll()
    }

    static func terminalAlertChecks(app: AppDelegate, dir: URL, done: @escaping () -> Void) {
        // Pure protocol.
        check("alerts: parse stop / input lines", AgentAlertProtocol.parse("7 stop")?.kind == .finished && AgentAlertProtocol.parse("7 stop")?.tab == 7
              && AgentAlertProtocol.parse("12 Notification")?.kind == .waiting)
        check("alerts: parse rejects garbage", AgentAlertProtocol.parse("") == nil && AgentAlertProtocol.parse("x stop") == nil
              && AgentAlertProtocol.parse("3 bogus") == nil && AgentAlertProtocol.parse("0 stop") == nil)
        check("alerts: title states", AgentAlertProtocol.titleState("\u{2802} Fixing") == .working
              && AgentAlertProtocol.titleState("\u{2733} Claude Code") == .idle && AgentAlertProtocol.titleState("zsh") == .other)

        let savedHooks = TerminalPanelController.testHooks
        let savedDelay = TerminalPanelController.shellReadyDelay
        let savedLooking = TerminalPanelController.isUserLooking
        let savedAlerts = Prefs.terminalAgentAlerts
        TerminalPanelController.testHooks.executable = "/bin/cat"
        TerminalPanelController.shellReadyDelay = 0
        TerminalPanelController.isUserLooking = { _ in false }
        Prefs.terminalAgentAlerts = true
        AgentAlertServer.allowHeadless = true
        var badges: [(String?, Bool)] = []
        var posted: [(String, String)] = []
        TerminalNotifier.sink = { badge, attention in badges.append((badge, attention)) }
        TerminalNotifier.appIsActive = { false }
        AgentNotifier.sink = { posted.append(($0, $1)) }

        let project = dir.appendingPathComponent("alertproj")
        try? FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let tw = app.openProject(project)
        tw.window.setContentSize(NSSize(width: 1200, height: 800))
        let finish = {
            tw.window.close()
            AgentAlertServer.shared.stop()
            AgentAlertServer.shared.onEvent = nil
            AgentAlertServer.allowHeadless = false
            AgentNotifier.sink = nil
            TerminalNotifier.sink = nil
            TerminalNotifier.appIsActive = { NSApp?.isActive ?? false }
            TerminalPanelController.testHooks = savedHooks
            TerminalPanelController.shellReadyDelay = savedDelay
            TerminalPanelController.isUserLooking = savedLooking
            Prefs.terminalAgentAlerts = savedAlerts
            try? FileManager.default.removeItem(at: project)
            done()
        }
        guard let term = tw.terminalPanel else { check("alerts: terminal controller exists", false); finish(); return }
        tw.showTerminalPanel(focus: false)
        term.newTab()
        term.select(0)
        guard let bg = term.tabID(1), let fg = term.tabID(0), let sock = AgentAlertServer.shared.path else {
            check("alerts: server started with tab ids", false); finish(); return
        }
        check("alerts: socket exists, owner-only", (try? FileManager.default.attributesOfItem(atPath: sock)[.posixPermissions] as? Int) == 0o600)
        let env = AgentAlerts.environment(tabID: bg)
        check("alerts: shells get KODE_ALERT_SOCK and KODE_TAB_ID", env["KODE_ALERT_SOCK"] == sock && env["KODE_TAB_ID"] == String(bg))

        badges.removeAll()
        check("alerts: hook line is delivered", AgentAlertServer.send(to: sock, line: "\(bg) stop"))
        alertWait(2, { term.tabAlert(1) != nil }) {
        check("alerts: Stop hook marks the background tab finished, badges the dock and bounces",
              term.tabAlert(1) == .finished && term.tabDone(1) && badges.last?.0 == "1" && badges.last?.1 == true)
        check("alerts: user notification posted", posted.count == 1 && posted[0].1.contains("finished"))
        AgentAlertServer.send(to: sock, line: "\(bg) input")
        alertWait(2, { term.tabAlert(1) == .waiting }) {
        check("alerts: Notification hook upgrades to waiting with a second notification", term.tabAlert(1) == .waiting && posted.count == 2
              && posted[1].1.contains("waiting"))
        AgentAlertServer.send(to: sock, line: "\(bg) stop")
        alertWait(0.3, { false }) {
        check("alerts: finished never downgrades waiting", term.tabAlert(1) == .waiting && posted.count == 2)
        term.select(1)
        check("alerts: focusing the tab clears the indicator and the dock badge", term.tabAlert(1) == nil && !term.tabDone(1) && badges.last?.0 == nil)

        // Watched tab: no alert at all.
        TerminalPanelController.isUserLooking = { _ in true }
        let before = posted.count
        TerminalPanelController.deliverAlert(tab: bg, kind: .finished)
        check("alerts: skipped while the user is looking at that tab", term.tabAlert(1) == nil && posted.count == before)
        TerminalPanelController.isUserLooking = { _ in false }
        check("alerts: unknown tab id is ignored", !TerminalPanelController.deliverAlert(tab: 999_999, kind: .finished))

        // Bell fallback.
        term.select(0)
        term.simulateBell(tab: 1)
        check("alerts: BEL falls back to a waiting alert", term.tabAlert(1) == .waiting && posted.count == before + 1)
        term.select(1); term.select(0)

        // Title fallback (agent tabs only).
        term.setTabLocked(1)
        term.simulateTitle("\u{2802} Working", tab: 1)
        term.simulateTitle("\u{2733} Claude Code", tab: 1)
        alertWait(2, { term.tabAlert(1) != nil }) {
        check("alerts: spinner -> idle title falls back to finished", term.tabAlert(1) == .finished)
        term.select(1); term.select(0)

        // Toggle off.
        Prefs.terminalAgentAlerts = false
        TerminalPanelController.deliverAlert(tab: bg, kind: .finished)
        term.simulateBell(tab: 1)
        check("alerts: Settings toggle off silences hook and bell", term.tabAlert(1) == nil)
        Prefs.terminalAgentAlerts = true
        _ = fg

        // Find bar.
        term.select(0)
        check("find: nothing allocated until opened", !term.isFindOpen)
        term.feedSample("alpha beta\r\nGamma ALPHA\r\n")
        term.simulateFindBar(query: "alpha")
        check("find: bar opens and selects the first match", term.isFindOpen && term.activeSelectionText.lowercased() == "alpha" && term.findCountText == "1/2")
        term.simulateFindStep(forward: true)
        check("find: next moves to the second match", term.findCountText == "2/2")
        term.simulateFindStep(forward: false)
        check("find: previous goes back", term.findCountText == "1/2")
        term.simulateFindBar(query: "alpha", caseSensitive: true)
        check("find: case toggle narrows matches", term.findCountText == "1/1" && term.activeSelectionText == "alpha")
        term.simulateFindBar(query: "zzzz")
        check("find: no match is reported", term.findCountText == "No matches")
        term.closeFind(refocus: false)
        check("find: close releases the bar and clears the highlight", !term.isFindOpen && term.activeSelectionText.isEmpty)
        finish()
        }   // title
        }   // downgrade
        }   // waiting
        }   // finished
    }
}
