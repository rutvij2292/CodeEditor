import AppKit
import SwiftTerm

// MARK: - Tab strip

private final class TerminalTabStrip: NSView {
    struct Item { var title: String; var unread: Bool; var done: Bool; var dead: Bool; var waiting = false }
    var items: [Item] = [] { didSet { needsDisplay = true } }
    var selected = 0 { didSet { needsDisplay = true } }
    /// Label of the Agent button when there is room ("Claude Code"); nil shows "Agent".
    var agentTitle: String? { didSet { needsDisplay = true } }
    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onNew: (() -> Void)?
    var onRun: ((NSPoint, NSView) -> Void)?
    var onAgent: (() -> Void)?
    var onAgentMenu: ((NSPoint, NSView) -> Void)?
    static let height: CGFloat = 24
    private let btnW: CGFloat = 26

    override var isFlipped: Bool { true }
    /// 0 = icons only (narrow docks), 1 = short labels, 2 = agent name too.
    private var mode: Int { bounds.width >= 430 ? 2 : (bounds.width >= 300 ? 1 : 0) }
    private var runW: CGFloat { mode == 0 ? 30 : 52 }
    private var agentLabel: String { mode == 0 ? "\u{2726}" : "\u{2726} " + (mode == 2 ? (agentTitle ?? "Agent") : "Agent") + " \u{25BE}" }
    private var agentW: CGFloat {
        mode == 0 ? 28 : min(150, ceil((agentLabel as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)]).width) + 14)
    }
    private var runRect: NSRect { NSRect(x: bounds.width - runW - 2, y: 2, width: runW, height: bounds.height - 4) }
    private var agentRect: NSRect { NSRect(x: runRect.minX - agentW - 3, y: 2, width: agentW, height: bounds.height - 4) }
    private var plusRect: NSRect { NSRect(x: agentRect.minX - btnW, y: 2, width: btnW, height: bounds.height - 4) }

    private func tabRects() -> [NSRect] {
        guard !items.isEmpty else { return [] }
        let avail = max(40, plusRect.minX - 4)
        let w = min(160, max(36, avail / CGFloat(items.count)))
        return items.indices.map { NSRect(x: 2 + CGFloat($0) * w, y: 0, width: w - 2, height: bounds.height) }
    }

    override func draw(_ dirtyRect: NSRect) {
        let pal = Theme.palette
        let dark = Theme.isDark
        (dark ? NSColor(white: 1, alpha: 0.05) : NSColor(white: 0, alpha: 0.04)).setFill()
        bounds.fill()
        pal.gutter.withAlphaComponent(0.25).setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
        let font = NSFont.systemFont(ofSize: 11)
        let fg = pal.foreground
        let para = NSMutableParagraphStyle(); para.lineBreakMode = .byTruncatingTail
        for (i, r) in tabRects().enumerated() {
            if i == selected {
                pal.tabSelected.setFill(); r.fill()
                NSColor.controlAccentColor.setFill(); NSRect(x: r.minX, y: r.maxY - 2, width: r.width, height: 2).fill()
            }
            let item = items[i]
            var x = r.minX + 8
            if item.unread || item.done {
                (item.waiting ? NSColor.systemRed : (item.done ? NSColor.systemGreen : NSColor.systemOrange)).setFill()
                NSBezierPath(ovalIn: NSRect(x: x, y: r.midY - 3, width: 6, height: 6)).fill()
                x += 10
            }
            let closeW: CGFloat = r.width > 70 ? 18 : 0
            let tr = NSRect(x: x, y: r.midY - 7, width: max(0, r.maxX - x - closeW - 4), height: 14)
            if tr.width > 8 {
                (item.title as NSString).draw(in: tr, withAttributes: [
                    .font: font, .paragraphStyle: para,
                    .foregroundColor: item.dead ? fg.withAlphaComponent(0.5) : fg])
            }
            if closeW > 0 {
                ("\u{00D7}" as NSString).draw(at: NSPoint(x: r.maxX - 15, y: r.midY - 8), withAttributes: [
                    .font: NSFont.systemFont(ofSize: 13), .foregroundColor: fg.withAlphaComponent(0.6)])
            }
        }
        ("+" as NSString).draw(at: NSPoint(x: plusRect.midX - 4, y: plusRect.midY - 9),
                               withAttributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: fg])
        func button(_ rect: NSRect, _ label: String, accent: Bool = false) {
            (accent ? NSColor.controlAccentColor.withAlphaComponent(0.20) : fg.withAlphaComponent(0.10)).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
            let ls = NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: fg])
            let sz = ls.size()
            ls.draw(at: NSPoint(x: rect.midX - sz.width / 2, y: rect.midY - sz.height / 2))
        }
        button(agentRect, agentLabel, accent: true)
        button(runRect, mode == 0 ? "\u{25B6}\u{25BE}" : "Run \u{25BE}")
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if runRect.contains(p) { onRun?(NSPoint(x: runRect.minX, y: runRect.maxY), self); return }
        if agentRect.contains(p) {
            // Narrow: the whole button is a menu. Otherwise the label starts the last agent and the arrow opens the menu.
            if mode == 0 || p.x > agentRect.maxX - 16 { onAgentMenu?(NSPoint(x: agentRect.minX, y: agentRect.maxY), self) } else { onAgent?() }
            return
        }
        if plusRect.contains(p) { onNew?(); return }
        for (i, r) in tabRects().enumerated() where r.contains(p) {
            if r.width > 70 && p.x > r.maxX - 20 { onClose?(i) } else { onSelect?(i) }
            return
        }
    }

    override func otherMouseDown(with event: NSEvent) {   // middle click closes
        let p = convert(event.locationInWindow, from: nil)
        for (i, r) in tabRects().enumerated() where r.contains(p) { onClose?(i); return }
    }
}

private final class TerminalContainer: NSView {
    var onLayout: (() -> Void)?
    var onAttach: (() -> Void)?
    override var isFlipped: Bool { true }
    override func layout() { super.layout(); onLayout?() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if window != nil { onAttach?() } }
}

// MARK: - Controller

final class TerminalPanelController: NSObject, LocalProcessTerminalViewDelegate {
    // Settings live in `Prefs` (written by the Settings window); changes are applied to open terminals live.
    static var fontSize: CGFloat {
        get { CGFloat(Prefs.terminalFontSize) }
        set { Prefs.terminalFontSize = Double(newValue) }
    }
    static var cursorStyle: TerminalCursor {
        get { TerminalCursor(rawValue: Prefs.terminalCursorStyle) ?? .block }
        set { Prefs.terminalCursorStyle = newValue.rawValue }
    }
    static var scrollbackLines: Int {
        get { Prefs.terminalScrollback }
        set { Prefs.terminalScrollback = newValue }
    }
    /// Seconds of silence after output before a background tab counts as "done".
    static var idleSeconds: TimeInterval = 4
    /// Wait before typing/pasting into a freshly spawned shell (lets it print its prompt and enable bracketed paste).
    static var shellReadyDelay: TimeInterval = 0.8
    /// Is the user looking at this window right now? (tests override)
    static var isUserLooking: (NSWindow?) -> Bool = { w in NSApp.isActive && (w?.isKeyWindow ?? false) }
    /// Close a tab automatically when its shell exits (default: show "[Process completed]" and restart on key).
    static var closeOnExit: Bool {
        get { UserDefaults.standard.bool(forKey: "terminal.closeOnExit") }
        set { UserDefaults.standard.set(newValue, forKey: "terminal.closeOnExit") }
    }

    struct TestHooks {
        /// Run this instead of the login shell (e.g. /bin/echo, /bin/sh).
        var executable: String?
        var args: [String] = []
        var extraEnvironment: [String: String] = [:]
        /// Allow spawning the real login shell while AppEnv.headless is true.
        var allowHeadlessShell = false
    }
    static var testHooks = TestHooks()
    /// Per-window environment for new shells (Claude Code IDE bridge port); applies to tabs started or restarted afterwards.
    var extraEnvironment: [String: String] = [:]

    private static var nextTabID = 1

    private final class Tab {
        let id: Int
        let view: CETerminalView
        var title: String
        /// Agent tabs keep their name instead of following the shell's window-title escapes.
        var lockedTitle = false
        var unread = false
        var done = false
        /// Set by a hook / BEL / title signal (nil for plain idle detection).
        var alert: AgentAlertKind?
        /// Last window title looked like a working agent (spinner), so the next idle title means "finished".
        var titleWorking = false
        var exited = false
        var launchedAt = Date()
        init(view: CETerminalView, title: String) {
            id = TerminalPanelController.nextTabID; TerminalPanelController.nextTabID += 1
            self.view = view; self.title = title
        }
        var pid: pid_t { view.process?.shellPid ?? 0 }
    }

    let root: URL
    let view: NSView
    var onClose: (() -> Void)?
    var onTitleChange: ((String) -> Void)?
    /// Fires when `hasUnreadActivity` flips (a background tab produced output / was viewed).
    var onActivity: (() -> Void)?
    /// Absolute path, line, column. Wired by the integrator to ProjectWindow.open.
    var openPath: ((String, Int?, Int?) -> Void)?
    /// Files dropped on a terminal (from the file tree / Finder): the host pastes their @references.
    var onFilesDropped: (([URL]) -> Void)?

    private let container = TerminalContainer()
    private let strip = TerminalTabStrip()
    private var tabs: [Tab] = []
    private var active = 0
    private var observers: [NSObjectProtocol] = []
    private var idleTracker = TerminalIdleTracker()
    private var idleTimer: Timer?
    private var findBar: TerminalFindBar?
    /// Clock for the idle detector (tests inject a fake one).
    var clock: () -> Date = Date.init
    private var appliedScrollback = TerminalPanelController.scrollbackLines
    /// Exact bytes of the most recent `paste` (verification).
    var lastPasteBytes: [UInt8] = []
    private static let live = NSHashTable<TerminalPanelController>.weakObjects()

    var tabCount: Int { tabs.count }
    var tabTitles: [String] { tabs.map(\.title) }
    var hasUnreadActivity: Bool { tabs.contains { $0.unread } }
    /// A background tab (or the app being away) saw output followed by silence, or a BEL.
    var hasDoneTabs: Bool { tabs.contains { $0.done } }
    var doneCount: Int { tabs.filter(\.done).count }
    enum Attention { case none, activity, done }
    var attention: Attention { hasDoneTabs ? .done : (hasUnreadActivity ? .activity : .none) }
    /// The active tab when it is an agent tab (Claude Code, Codex, ...); nil for a plain shell.
    var activeAgentTab: (id: Int, title: String)? {
        tabs.indices.contains(active) && tabs[active].lockedTitle && !tabs[active].exited ? (tabs[active].id, tabs[active].title) : nil
    }
    var activeTitle: String { tabs.indices.contains(active) ? tabs[active].title : "Terminal" }
    /// Shell PIDs of live tabs (verification).
    var shellPIDs: [pid_t] { tabs.map(\.pid).filter { $0 > 0 } }

    init(root: URL) {
        self.root = root
        self.view = container
        super.init()
        container.addSubview(strip)
        container.onLayout = { [weak self] in self?.layoutAll() }
        container.onAttach = { [weak self] in if self?.container.isHiddenOrHasHiddenAncestor == false { self?.ensureStarted() } }
        strip.onSelect = { [weak self] in self?.select($0) }
        strip.onClose = { [weak self] in self?.closeTab(at: $0) }
        strip.onNew = { [weak self] in self?.newTab() }
        strip.onRun = { [weak self] pt, v in self?.showRunMenu(at: pt, in: v) }
        strip.onAgent = { [weak self] in self?.startPrimaryAgent() }
        strip.onAgentMenu = { [weak self] pt, v in self?.agentMenu().popUp(positioning: nil, at: pt, in: v) }
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: Theme.didChange, object: nil, queue: .main) { [weak self] _ in self?.applyTheme() })
        observers.append(nc.addObserver(forName: Prefs.didChange, object: nil, queue: .main) { [weak self] note in
            if ((note.userInfo?["key"] as? String) ?? "").hasPrefix("terminal") { self?.applyTheme() }
        })
        for name in [NSApplication.didBecomeActiveNotification, NSWindow.didBecomeKeyNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.clearIfWatched() })
        }
        Self.live.add(self)
    }

    deinit {
        idleTimer?.invalidate()
        observers.forEach(NotificationCenter.default.removeObserver)
        for t in tabs { Self.kill(t, wait: false) }
    }

    // MARK: Public API

    /// Starts the first shell if none exists yet (called when the terminal becomes visible).
    func startIfNeeded() { ensureStarted() }

    func focusTerminal() {
        ensureStarted()
        guard tabs.indices.contains(active) else { return }
        clearUnread(active)
        if let w = tabs[active].view.window { w.makeFirstResponder(tabs[active].view) }
    }

    /// Types the command and presses Return in the active tab.
    func runCommand(_ command: String) {
        ensureStarted()
        guard tabs.indices.contains(active), !command.isEmpty else { return }
        let tab = tabs[active]
        if tab.exited { restart(tab) }
        whenShellReady(tab) { $0.view.send(txt: command + "\r") }
    }

    private func whenShellReady(_ tab: Tab, _ work: @escaping (Tab) -> Void) {
        let age = Date().timeIntervalSince(tab.launchedAt)
        if age < Self.shellReadyDelay {
            DispatchQueue.main.asyncAfter(deadline: .now() + (Self.shellReadyDelay - age)) { [weak tab] in if let tab { work(tab) } }
        } else { work(tab) }
    }

    /// Inserts `text` into the active tab like a paste (bracketed when the program enabled it) WITHOUT pressing Return.
    /// Lazily starts the shell; restarts an exited tab first.
    func paste(_ text: String) {
        guard !text.isEmpty else { return }
        ensureStarted()
        guard tabs.indices.contains(active) else { return }
        let tab = tabs[active]
        if tab.exited { restart(tab) }
        whenShellReady(tab) { [weak self] t in
            self?.lastPasteBytes = TerminalBridge.pasteBytes(text, bracketed: t.view.terminal.bracketedPasteMode)
            guard self?.canSpawn == true else { return }
            t.view.pasteText(text)
        }
    }

    /// Opens a NEW tab titled with the agent's name and runs its command in the project root.
    func startAgent(_ agent: TerminalAgent) {
        TerminalAgents.lastUsedCommand = agent.command
        let tab = addTab(title: agent.title)
        tab.lockedTitle = true
        select(tabs.count - 1)
        runCommand(agent.command)
    }

    /// True when the active tab is a live Claude Code tab.
    var isClaudeTabActive: Bool { activeAgentTab?.title.hasPrefix("Claude") == true }

    /// Cmd-3: selects the first live Claude Code tab, or starts one (plain `claude`, else the primary agent) when there is none.
    func selectOrStartClaude() {
        if let i = tabs.firstIndex(where: { $0.lockedTitle && !$0.exited && $0.title.hasPrefix("Claude") }) { select(i); return }
        let agents = TerminalAgents.all()
        if let a = agents.first(where: { $0.command == "claude" }) ?? TerminalAgents.primary(in: agents) { startAgent(a) }
    }

    /// The Agent button: last used (or first available) agent; the menu when none is installed.
    func startPrimaryAgent() {
        if let a = TerminalAgents.primary(in: TerminalAgents.all()) { startAgent(a); focusTerminal() }
        else if let v = strip.superview { agentMenu().popUp(positioning: nil, at: NSPoint(x: strip.frame.maxX - 120, y: strip.frame.maxY), in: v) }
    }

    /// All launchable agents (detected CLIs on the login PATH, `Prefs.terminalAgents`, legacy `terminal.agentCommand`).
    func agentMenu() -> NSMenu {
        let menu = NSMenu(title: "AI agents")
        let agents = TerminalAgents.all()
        if agents.isEmpty {
            let mi = NSMenuItem(title: "No AI CLI found on PATH", action: nil, keyEquivalent: ""); mi.isEnabled = false
            menu.addItem(mi)
        }
        for a in agents {
            let mi = NSMenuItem(title: a.title, action: #selector(agentMenuItem(_:)), keyEquivalent: "")
            mi.target = self; mi.representedObject = AgentBox(a)
            menu.addItem(mi)
        }
        return menu
    }

    private final class AgentBox: NSObject { let agent: TerminalAgent; init(_ a: TerminalAgent) { agent = a } }

    @objc private func agentMenuItem(_ sender: NSMenuItem) {
        if let box = sender.representedObject as? AgentBox { startAgent(box.agent); focusTerminal() }
    }

    func newTab() {
        _ = addTab()
        select(tabs.count - 1)
    }

    func closeTab() { closeTab(at: active) }

    func closeTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        let tab = tabs.remove(at: index)
        idleTracker.clear(tab.id)
        Self.kill(tab, wait: false)
        tab.view.removeFromSuperview()
        if tab.done { Self.refreshNotifier(newlyDone: false) }
        if tabs.isEmpty {
            active = 0
            refreshStrip()
            onClose?()
            return
        }
        if active >= tabs.count || index < active { active = max(0, min(active - (index < active ? 1 : 0), tabs.count - 1)) }
        select(active)
    }

    /// Kills every shell (process groups) and frees all views. Safe to call repeatedly.
    func terminate() {
        let hadDone = hasDoneTabs
        closeFind(refocus: false)
        for t in tabs { Self.kill(t, wait: false); t.view.removeFromSuperview(); idleTracker.clear(t.id) }
        tabs.removeAll()
        active = 0
        idleTimer?.invalidate(); idleTimer = nil
        refreshStrip()
        if hadDone { Self.refreshNotifier(newlyDone: false) }
    }

    static func terminateAll() {
        for c in live.allObjects {
            for t in c.tabs { kill(t, wait: true); t.view.removeFromSuperview() }
            c.tabs.removeAll()
        }
        AgentAlertServer.shared.stop()
    }

    /// Ctrl-Tab / Shift-Cmd-] style cycling, wrapping at both ends.
    func cycleTab(_ delta: Int) {
        guard tabs.count > 1 else { return }
        select((active + delta + tabs.count) % tabs.count)
    }

    func select(_ index: Int) {
        guard tabs.indices.contains(index) else { return }
        if index != active { closeFind(refocus: false) }
        active = index
        for (i, t) in tabs.enumerated() { t.view.isHidden = i != index }
        clearUnread(index)
        refreshStrip()
        layoutAll()
        onTitleChange?(tabs[index].title)
        if let w = tabs[index].view.window { w.makeFirstResponder(tabs[index].view) }
    }

    /// The Run dropdown contents: AI agents section first, then detected project commands.
    func runMenu() -> NSMenu {
        let menu = NSMenu(title: "Run")
        let agents = TerminalAgents.all()
        if !agents.isEmpty {
            let header = NSMenuItem(title: "AI agents", action: nil, keyEquivalent: ""); header.isEnabled = false
            menu.addItem(header)
            for a in agents {
                let mi = NSMenuItem(title: a.title, action: #selector(agentMenuItem(_:)), keyEquivalent: "")
                mi.target = self; mi.representedObject = AgentBox(a); mi.indentationLevel = 1
                menu.addItem(mi)
            }
        }
        let items = TerminalRunCommands.detect(root: root)
        if !items.isEmpty {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            for it in items {
                let mi = NSMenuItem(title: it.title, action: #selector(runMenuItem(_:)), keyEquivalent: "")
                mi.target = self; mi.representedObject = it.command
                menu.addItem(mi)
            }
        }
        return menu
    }

    // MARK: Internals

    @objc private func runMenuItem(_ sender: NSMenuItem) {
        if let c = sender.representedObject as? String { runCommand(c); focusTerminal() }
    }

    private func showRunMenu(at pt: NSPoint, in v: NSView) {
        runMenu().popUp(positioning: nil, at: pt, in: v)
    }

    private func ensureStarted() {
        guard tabs.isEmpty else { return }
        _ = addTab()
        select(0)
    }

    private var canSpawn: Bool { !AppEnv.headless || Self.testHooks.allowHeadlessShell || Self.testHooks.executable != nil }

    @discardableResult
    private func addTab(title: String? = nil) -> Tab {
        let opts = TerminalOptions(cols: 80, rows: 24, cursorStyle: Self.cursorStyle.style, scrollback: Self.scrollbackLines)
        let tv = CETerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 300), font: Self.font(), options: opts)
        tv.processDelegate = self
        tv.optionAsMetaKey = true
        let shell = Self.testHooks.executable ?? TerminalEnvironment.resolvedShell
        let tab = Tab(view: tv, title: title ?? (shell as NSString).lastPathComponent)
        tv.onData = { [weak self, weak tab] in if let self, let tab { self.dataArrived(tab) } }
        tv.onRestartKey = { [weak self, weak tab] in if let self, let tab { self.restart(tab) } }
        tv.onNewTab = { [weak self] in self?.newTab() }
        tv.onCloseTab = { [weak self] in self?.closeTab() }
        tv.onCycleTab = { [weak self] d in self?.cycleTab(d) }
        tv.onLink = { [weak self] in self?.handleLink($0) }
        tv.onFind = { [weak self] in self?.showFind() }
        tv.onBell = { [weak self, weak tab] in if let self, let tab { self.bellRang(tab) } }
        tv.onFileDrop = { [weak self] in self?.onFilesDropped?($0) }
        tv.enableFileDrops()
        tabs.append(tab)
        container.addSubview(tv)
        TerminalPalette.apply(to: tv, dark: Theme.isDark)
        if canSpawn { spawn(tab) } else {
            tv.feed(text: "[terminal disabled in headless mode]\r\n")
        }
        refreshStrip()
        layoutAll()
        return tab
    }

    private func spawn(_ tab: Tab) {
        let hooks = Self.testHooks
        let exe: String, args: [String]
        if let e = hooks.executable { exe = e; args = hooks.args } else { exe = TerminalEnvironment.resolvedShell; args = ["-l", "-i"] }
        let extra = hooks.extraEnvironment.merging(extraEnvironment) { _, new in new }
            .merging(AgentAlerts.environment(tabID: tab.id)) { _, new in new }
        let env = TerminalEnvironment.build(base: ProcessInfo.processInfo.environment,
                                            path: TerminalEnvironment.effectivePath(), extra: extra)
        tab.exited = false; tab.view.dead = false; tab.launchedAt = Date()
        tab.view.startProcess(executable: exe, args: args, environment: env, execName: nil, currentDirectory: root.path)
    }

    private func restart(_ tab: Tab) {
        guard tab.exited else { return }
        tab.view.terminal.resetToInitialState()
        tab.view.feed(text: "\u{1b}[2J\u{1b}[H")
        spawn(tab)
        refreshStrip()
    }

    private static func font() -> NSFont {
        let size = fontSize
        let name = Prefs.terminalFontName.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty, let f = NSFont(name: name, size: size) { return f }
        return NSFont(descriptor: Theme.font.fontDescriptor, size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// Re-applies theme colours, font, cursor and scrollback to every open tab (called for Theme and terminal-pref changes).
    private func applyTheme() {
        let font = Self.font()
        let scrollback = Self.scrollbackLines
        for t in tabs {
            TerminalPalette.apply(to: t.view, dark: Theme.isDark)
            if t.view.font.fontName != font.fontName || t.view.font.pointSize != font.pointSize { t.view.font = font }
            t.view.terminal.setCursorStyle(Self.cursorStyle.style)
            if scrollback != appliedScrollback { t.view.changeScrollback(scrollback) }
        }
        appliedScrollback = scrollback
        container.needsDisplay = true
        strip.needsDisplay = true
        layoutAll()
    }

    private func layoutAll() {
        let b = container.bounds
        let h = TerminalTabStrip.height
        strip.frame = NSRect(x: 0, y: 0, width: b.width, height: h)
        let bg = tabs.first?.view.nativeBackgroundColor ?? Theme.background
        container.layer?.backgroundColor = bg.cgColor
        for (i, t) in tabs.enumerated() where i == active {
            t.view.frame = NSRect(x: 4, y: h, width: max(40, b.width - 4), height: max(20, b.height - h))
        }
        if let bar = findBar {
            let w = min(TerminalFindBar.size.width, max(200, b.width - 24))
            bar.frame = NSRect(x: b.width - w - 14, y: h + 4, width: w, height: TerminalFindBar.size.height)
        }
    }

    private func refreshStrip() {
        strip.items = tabs.map { .init(title: $0.title, unread: $0.unread, done: $0.done, dead: $0.exited, waiting: $0.alert == .waiting) }
        strip.selected = active
        strip.agentTitle = TerminalAgents.primary(in: TerminalAgents.detected())?.title
    }

    /// Visible, in the key window of an active app: nothing to notify about.
    private func isWatched(_ tab: Tab) -> Bool {
        tabs.indices.contains(active) && tabs[active] === tab && tab.view.window != nil
            && !container.isHiddenOrHasHiddenAncestor && Self.isUserLooking(tab.view.window)
    }

    private func dataArrived(_ tab: Tab) {
        let watched = isWatched(tab)
        if Prefs.terminalNotifyOnIdle {
            idleTracker.idleSeconds = Self.idleSeconds
            idleTracker.output(tab.id, at: clock(), watched: watched)
            if idleTracker.anyPending { startIdleTimer() }
        }
        guard !watched, !tab.unread else { return }
        tab.unread = true
        refreshStrip()
        onActivity?()
    }

    private func bellRang(_ tab: Tab) {
        if Prefs.terminalAgentAlerts { raiseAlert(tab, .waiting); return }
        guard Prefs.terminalNotifyOnIdle else { return }
        if idleTracker.bell(tab.id, watched: isWatched(tab)) { markDone([tab.id]) }
    }

    private func markDone(_ ids: [Int]) {
        for t in tabs where ids.contains(t.id) && !t.done { t.done = true; t.unread = true }
        refreshStrip()
        onActivity?()
        Self.refreshNotifier(newlyDone: true)
    }

    /// Hook event from `AgentAlertServer` (tab ids are process-wide). Returns whether a tab took it.
    @discardableResult
    static func deliverAlert(tab id: Int, kind: AgentAlertKind) -> Bool {
        for c in live.allObjects { if let t = c.tabs.first(where: { $0.id == id }) { c.raiseAlert(t, kind); return true } }
        return false
    }

    /// An agent tab finished a turn or wants input: dot on the tab, dock badge / bounce (app inactive) and a user notification.
    /// Nothing happens while the user is looking at that tab. A "waiting" alert replaces "finished", never the other way round.
    private func raiseAlert(_ tab: Tab, _ kind: AgentAlertKind) {
        guard Prefs.terminalAgentAlerts, !isWatched(tab) else { return }
        if tab.done, tab.alert == kind || tab.alert == .waiting { return }
        idleTracker.bell(tab.id, watched: false)   // keeps the idle detector from alerting a second time
        tab.alert = kind; tab.done = true; tab.unread = true
        refreshStrip()
        onActivity?()
        Self.refreshNotifier(newlyDone: true)
        AgentNotifier.post(title: tab.title, body: "\(tab.lockedTitle ? tab.title : "The terminal") \(kind.message)")
    }

    private func startIdleTimer() {
        guard idleTimer == nil else { return }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.processIdle(at: self?.clock() ?? Date()) }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        idleTimer = t
    }

    /// Advances the idle detector (the 1 s timer calls this; tests call it with a fake time).
    func processIdle(at now: Date) {
        let fired = idleTracker.tick(at: now)
        if !fired.isEmpty { markDone(fired) }
        if !idleTracker.anyPending { idleTimer?.invalidate(); idleTimer = nil }
    }

    /// The user came back (app/window activated) while looking at the visible tab: clear its markers.
    private func clearIfWatched() {
        guard tabs.indices.contains(active), isWatched(tabs[active]) else { return }
        clearUnread(active)
    }

    private func clearUnread(_ i: Int) {
        guard tabs.indices.contains(i) else { return }
        let t = tabs[i]
        idleTracker.clear(t.id)
        guard t.unread || t.done else { return }
        let wasDone = t.done
        t.unread = false; t.done = false; t.alert = nil
        refreshStrip()
        onActivity?()
        if wasDone { Self.refreshNotifier(newlyDone: false) }
    }

    /// Dock-tile badge = finished tabs across all windows.
    private static func refreshNotifier(newlyDone: Bool) {
        TerminalNotifier.update(doneCount: live.allObjects.reduce(0) { $0 + $1.doneCount }, newlyDone: newlyDone)
    }

    private func handleLink(_ text: String) {
        guard let link = TerminalLinks.parse(text) else {
            if let u = URL(string: text), u.scheme != nil { NSWorkspace.shared.open(u) }
            return
        }
        guard let url = TerminalLinks.resolve(link, root: root) else { return }
        openPath?(url.path, link.line, link.column)
    }

    private func tab(for source: TerminalView) -> Tab? { tabs.first { $0.view === source } }

    // MARK: Process lifecycle

    /// SIGHUP the whole process group, escalate to SIGKILL, and reap (no zombies).
    private static func kill(_ tab: Tab, wait: Bool) {
        let view = tab.view
        view.processDelegate = nil
        view.onData = nil; view.onLink = nil; view.onRestartKey = nil
        view.onNewTab = nil; view.onCloseTab = nil; view.onCycleTab = nil; view.onFind = nil; view.onBell = nil
        let pid = view.process?.shellPid ?? 0
        let running = view.process?.running ?? false
        view.terminate()   // closes the pty (kernel HUPs the foreground group), SIGTERM to shell
        guard pid > 0, running else { return }
        killpg(pid, SIGHUP)
        let reap = {
            var st: Int32 = 0
            for _ in 0..<(wait ? 6 : 30) {
                if waitpid(pid, &st, WNOHANG) != 0 { if killpg(pid, 0) == 0 { killpg(pid, SIGKILL) }; return }
                usleep(wait ? 50_000 : 100_000)
            }
            killpg(pid, SIGKILL); Darwin.kill(pid, SIGKILL)
            waitpid(pid, &st, 0)
        }
        if wait { reap() } else { DispatchQueue.global(qos: .utility).async(execute: reap) }
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let t = self.tab(for: source) else { return }
            let clean = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
            if t.lockedTitle {   // fallback signal: the agent's spinner title went idle
                let state = AgentAlertProtocol.titleState(clean)
                if state == .working { t.titleWorking = true }
                else if state == .idle, t.titleWorking { t.titleWorking = false; self.raiseAlert(t, .finished) }
            }
            guard !t.lockedTitle, !clean.isEmpty, clean != t.title else { return }
            t.title = clean
            self.refreshStrip()
            if self.tabs.indices.contains(self.active), self.tabs[self.active] === t { self.onTitleChange?(clean) }
        }
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let t = self.tab(for: source), !t.exited else { return }
            t.exited = true
            if Self.closeOnExit, let i = self.tabs.firstIndex(where: { $0 === t }) {
                self.closeTab(at: i); return
            }
            t.view.dead = true
            t.view.feed(text: "\r\n[Process completed] \u{2014} press any key to restart\r\n")
            self.refreshStrip()
        }
    }

    // MARK: Find

    var isFindOpen: Bool { findBar != nil }

    /// Cmd-F in the terminal: opens (or refocuses) the find bar. Nothing is allocated until then.
    func showFind() {
        guard tabs.indices.contains(active) else { return }
        if let bar = findBar { bar.focus(); return }
        let bar = TerminalFindBar(frame: NSRect(origin: .zero, size: TerminalFindBar.size))
        bar.onChange = { [weak self] q, cs in self?.runFind(q, caseSensitive: cs, forward: true, restart: true) }
        bar.onStep = { [weak self] fwd, q, cs in self?.runFind(q, caseSensitive: cs, forward: fwd, restart: false) }
        bar.onClose = { [weak self] in self?.closeFind(refocus: true) }
        findBar = bar
        container.addSubview(bar)
        layoutAll()
        let sel = tabs[active].view.getSelection() ?? ""
        if !sel.isEmpty, !sel.contains("\n") { bar.field.stringValue = String(sel.prefix(200)) }
        bar.focus()
        if !bar.query.isEmpty { runFind(bar.query, caseSensitive: bar.caseSensitive, forward: true, restart: true) }
    }

    func closeFind(refocus: Bool) {
        guard let bar = findBar else { return }
        findBar = nil
        bar.removeFromSuperview()
        guard tabs.indices.contains(active) else { return }
        tabs[active].view.clearSearch()
        if refocus, let w = tabs[active].view.window { w.makeFirstResponder(tabs[active].view) }
    }

    /// Selects the next / previous match (SwiftTerm scrolls it into view) and updates the "n/total" label.
    @discardableResult
    func runFind(_ query: String, caseSensitive: Bool, forward: Bool, restart: Bool) -> Bool {
        guard tabs.indices.contains(active) else { return false }
        let v = tabs[active].view
        if query.isEmpty { v.clearSearch(); findBar?.setCount("", found: true); return false }
        let opts = SearchOptions(caseSensitive: caseSensitive)
        if restart { v.clearSearch() }
        let found = forward ? v.findNext(query, options: opts) : v.findPrevious(query, options: opts)
        let summary = v.searchMatchSummary(query, options: opts, limit: 1000)
        findBar?.setCount(found ? "\(summary.index)/\(summary.total)\(summary.total >= 1000 ? "+" : "")" : "No matches", found: found)
        return found
    }

    /// Current selection of the active tab (verification).
    var activeSelectionText: String { tabs.indices.contains(active) ? (tabs[active].view.getSelection() ?? "") : "" }
    var findCountText: String { findBar?.countText ?? "" }
    func simulateFindBar(query: String, caseSensitive: Bool = false) {
        showFind()
        findBar?.field.stringValue = query
        findBar?.setCaseSensitive(caseSensitive)
        findBar?.onChange?(query, caseSensitive)
    }
    func simulateFindStep(forward: Bool) { if let b = findBar { b.onStep?(forward, b.query, b.caseSensitive) } }
    func tabAlert(_ i: Int) -> AgentAlertKind? { tabs.indices.contains(i) ? tabs[i].alert : nil }
    func tabID(_ i: Int) -> Int? { tabs.indices.contains(i) ? tabs[i].id : nil }
    func simulateTitle(_ title: String, tab i: Int) { if tabs.indices.contains(i) { setTerminalTitle(source: tabs[i].view, title: title) } }
    func setTabLocked(_ i: Int) { if tabs.indices.contains(i) { tabs[i].lockedTitle = true } }

    // MARK: Verification helpers

    var activeBufferText: String { tabs.indices.contains(active) ? tabs[active].view.bufferText() : "" }
    func bufferText(tab i: Int) -> String { tabs.indices.contains(i) ? tabs[i].view.bufferText() : "" }
    var activeScrollbackLines: Int { tabs.indices.contains(active) ? tabs[active].view.scrollbackLineCount : 0 }
    var activeTerminalSize: (cols: Int, rows: Int) {
        tabs.indices.contains(active) ? (tabs[active].view.terminal.cols, tabs[active].view.terminal.rows) : (0, 0)
    }
    func simulateKey(restartTab i: Int) { if tabs.indices.contains(i) { restart(tabs[i]) } }
    func simulateLink(_ text: String) { handleLink(text) }
    /// Feeds text straight into the active tab's screen (snapshots, sample content).
    func feedSample(_ text: String) { if tabs.indices.contains(active) { tabs[active].view.feed(text: text) } }
    func tabDone(_ i: Int) -> Bool { tabs.indices.contains(i) ? tabs[i].done : false }
    func tabUnread(_ i: Int) -> Bool { tabs.indices.contains(i) ? tabs[i].unread : false }
    var activeIndex: Int { active }
    /// The active terminal view (to prove docks move the very same view).
    var activeTerminalView: NSView? { tabs.indices.contains(active) ? tabs[active].view : nil }
    func simulateBell(tab i: Int) { if tabs.indices.contains(i) { bellRang(tabs[i]) } }
    func simulateOutput(tab i: Int) { if tabs.indices.contains(i) { dataArrived(tabs[i]) } }
    func simulateDrop(_ urls: [URL]) { onFilesDropped?(urls) }
    func send(_ text: String, tab i: Int? = nil) { let t = tabs[i ?? active]; t.view.send(txt: text) }
}
