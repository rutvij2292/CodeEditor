import AppKit
import SwiftTerm

// MARK: - Tab strip

private final class TerminalTabStrip: NSView {
    struct Item { var title: String; var unread: Bool; var dead: Bool }
    var items: [Item] = [] { didSet { needsDisplay = true } }
    var selected = 0 { didSet { needsDisplay = true } }
    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onNew: (() -> Void)?
    var onRun: ((NSPoint, NSView) -> Void)?
    static let height: CGFloat = 24
    private let btnW: CGFloat = 26

    override var isFlipped: Bool { true }
    private var compactRun: Bool { bounds.width < 300 }
    private var runW: CGFloat { compactRun ? 30 : 52 }
    private var runRect: NSRect { NSRect(x: bounds.width - runW - 2, y: 2, width: runW, height: bounds.height - 4) }
    private var plusRect: NSRect { NSRect(x: runRect.minX - btnW, y: 2, width: btnW, height: bounds.height - 4) }

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
            if item.unread {
                NSColor.systemOrange.setFill()
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
        let rr = runRect
        fg.withAlphaComponent(0.10).setFill()
        NSBezierPath(roundedRect: rr, xRadius: 4, yRadius: 4).fill()
        let label = compactRun ? "\u{25B6}\u{25BE}" : "Run \u{25BE}"
        let ls = NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: fg])
        let sz = ls.size()
        ls.draw(at: NSPoint(x: rr.midX - sz.width / 2, y: rr.midY - sz.height / 2))
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if runRect.contains(p) { onRun?(NSPoint(x: runRect.minX, y: runRect.maxY), self); return }
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
    // Settings (persisted)
    static let settingsDidChange = Notification.Name("CodeEditor.terminalSettingsDidChange")
    static var fontSize: CGFloat {
        get { let v = UserDefaults.standard.double(forKey: "terminal.fontSize"); return v >= 8 ? CGFloat(v) : 12 }
        set { UserDefaults.standard.set(Double(min(max(newValue, 8), 28)), forKey: "terminal.fontSize")
              NotificationCenter.default.post(name: settingsDidChange, object: nil) }
    }
    static var cursorStyle: TerminalCursor {
        get { TerminalCursor(rawValue: UserDefaults.standard.string(forKey: "terminal.cursorStyle") ?? "") ?? .block }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "terminal.cursorStyle")
              NotificationCenter.default.post(name: settingsDidChange, object: nil) }
    }
    static var scrollbackLines: Int {
        get { let v = UserDefaults.standard.integer(forKey: "terminal.scrollback"); return v > 0 ? v : 5000 }
        set { UserDefaults.standard.set(newValue, forKey: "terminal.scrollback") }
    }
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

    private final class Tab {
        let view: CETerminalView
        var title: String
        var unread = false
        var exited = false
        var launchedAt = Date()
        init(view: CETerminalView, title: String) { self.view = view; self.title = title }
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

    private let container = TerminalContainer()
    private let strip = TerminalTabStrip()
    private var tabs: [Tab] = []
    private var active = 0
    private var observers: [NSObjectProtocol] = []
    private static let live = NSHashTable<TerminalPanelController>.weakObjects()

    var tabCount: Int { tabs.count }
    var tabTitles: [String] { tabs.map(\.title) }
    var hasUnreadActivity: Bool { tabs.contains { $0.unread } }
    var activeTitle: String { tabs.indices.contains(active) ? tabs[active].title : "Terminal" }
    /// Shell PIDs of live tabs (verification).
    var shellPIDs: [pid_t] { tabs.map(\.pid).filter { $0 > 0 } }

    init(root: URL) {
        self.root = root
        self.view = container
        super.init()
        container.addSubview(strip)
        container.onLayout = { [weak self] in self?.layoutAll() }
        container.onAttach = { [weak self] in self?.ensureStarted() }
        strip.onSelect = { [weak self] in self?.select($0) }
        strip.onClose = { [weak self] in self?.closeTab(at: $0) }
        strip.onNew = { [weak self] in self?.newTab() }
        strip.onRun = { [weak self] pt, v in self?.showRunMenu(at: pt, in: v) }
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: Theme.didChange, object: nil, queue: .main) { [weak self] _ in self?.applyTheme() })
        observers.append(nc.addObserver(forName: Self.settingsDidChange, object: nil, queue: .main) { [weak self] _ in self?.applyTheme() })
        Self.live.add(self)
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        for t in tabs { Self.kill(t, wait: false) }
    }

    // MARK: Public API

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
        let send: () -> Void = { [weak tab] in tab?.view.send(txt: command + "\r") }
        let age = Date().timeIntervalSince(tab.launchedAt)
        if age < 0.8 { DispatchQueue.main.asyncAfter(deadline: .now() + (0.8 - age)) { send() } } else { send() }
    }

    func newTab() {
        addTab()
        select(tabs.count - 1)
    }

    func closeTab() { closeTab(at: active) }

    func closeTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        let tab = tabs.remove(at: index)
        Self.kill(tab, wait: false)
        tab.view.removeFromSuperview()
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
        for t in tabs { Self.kill(t, wait: false); t.view.removeFromSuperview() }
        tabs.removeAll()
        active = 0
        refreshStrip()
    }

    static func terminateAll() {
        for c in live.allObjects {
            for t in c.tabs { kill(t, wait: true); t.view.removeFromSuperview() }
            c.tabs.removeAll()
        }
    }

    func select(_ index: Int) {
        guard tabs.indices.contains(index) else { return }
        active = index
        for (i, t) in tabs.enumerated() { t.view.isHidden = i != index }
        clearUnread(index)
        refreshStrip()
        layoutAll()
        onTitleChange?(tabs[index].title)
        if let w = tabs[index].view.window { w.makeFirstResponder(tabs[index].view) }
    }

    /// The Run dropdown contents (detected project commands, then AI entries).
    func runMenu() -> NSMenu {
        let menu = NSMenu(title: "Run")
        func add(_ items: [TerminalRunItem]) {
            guard !items.isEmpty else { return }
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            for it in items {
                let mi = NSMenuItem(title: it.title, action: it.command.isEmpty ? nil : #selector(runMenuItem(_:)), keyEquivalent: "")
                mi.target = self; mi.representedObject = it.command; mi.isEnabled = !it.command.isEmpty
                menu.addItem(mi)
            }
        }
        add(TerminalRunCommands.agentItems())
        add(TerminalRunCommands.detect(root: root))
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
        addTab()
        select(0)
    }

    private var canSpawn: Bool { !AppEnv.headless || Self.testHooks.allowHeadlessShell || Self.testHooks.executable != nil }

    private func addTab() {
        let opts = TerminalOptions(cols: 80, rows: 24, cursorStyle: Self.cursorStyle.style, scrollback: Self.scrollbackLines)
        let tv = CETerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 300), font: Self.font(), options: opts)
        tv.processDelegate = self
        tv.optionAsMetaKey = true
        let shell = Self.testHooks.executable ?? TerminalEnvironment.userShell
        let tab = Tab(view: tv, title: (shell as NSString).lastPathComponent)
        tv.onData = { [weak self, weak tab] in if let self, let tab { self.dataArrived(tab) } }
        tv.onRestartKey = { [weak self, weak tab] in if let self, let tab { self.restart(tab) } }
        tv.onLink = { [weak self] in self?.handleLink($0) }
        tabs.append(tab)
        container.addSubview(tv)
        TerminalPalette.apply(to: tv, dark: Theme.isDark)
        if canSpawn { spawn(tab) } else {
            tv.feed(text: "[terminal disabled in headless mode]\r\n")
        }
        refreshStrip()
        layoutAll()
    }

    private func spawn(_ tab: Tab) {
        let hooks = Self.testHooks
        let exe: String, args: [String]
        if let e = hooks.executable { exe = e; args = hooks.args } else { exe = TerminalEnvironment.userShell; args = ["-l", "-i"] }
        let env = TerminalEnvironment.build(base: ProcessInfo.processInfo.environment,
                                            path: TerminalEnvironment.effectivePath(), extra: hooks.extraEnvironment)
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
        NSFont(descriptor: Theme.font.fontDescriptor, size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    private func applyTheme() {
        for t in tabs {
            TerminalPalette.apply(to: t.view, dark: Theme.isDark)
            if t.view.font.pointSize != Self.fontSize { t.view.font = Self.font() }
            t.view.terminal.setCursorStyle(Self.cursorStyle.style)
        }
        container.needsDisplay = true
        strip.needsDisplay = true
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
    }

    private func refreshStrip() {
        strip.items = tabs.map { .init(title: $0.title, unread: $0.unread, dead: $0.exited) }
        strip.selected = active
    }

    private func dataArrived(_ tab: Tab) {
        let visible = tabs.indices.contains(active) && tabs[active] === tab && tab.view.window != nil
            && !container.isHiddenOrHasHiddenAncestor
        guard !visible, !tab.unread else { return }
        tab.unread = true
        refreshStrip()
        onActivity?()
    }

    private func clearUnread(_ i: Int) {
        guard tabs.indices.contains(i), tabs[i].unread else { return }
        tabs[i].unread = false
        refreshStrip()
        onActivity?()
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
            guard !clean.isEmpty, clean != t.title else { return }
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

    // MARK: Verification helpers

    var activeBufferText: String { tabs.indices.contains(active) ? tabs[active].view.bufferText() : "" }
    func bufferText(tab i: Int) -> String { tabs.indices.contains(i) ? tabs[i].view.bufferText() : "" }
    var activeScrollbackLines: Int { tabs.indices.contains(active) ? tabs[active].view.scrollbackLineCount : 0 }
    var activeTerminalSize: (cols: Int, rows: Int) {
        tabs.indices.contains(active) ? (tabs[active].view.terminal.cols, tabs[active].view.terminal.rows) : (0, 0)
    }
    func simulateKey(restartTab i: Int) { if tabs.indices.contains(i) { restart(tabs[i]) } }
    func simulateLink(_ text: String) { handleLink(text) }
    func send(_ text: String, tab i: Int? = nil) { let t = tabs[i ?? active]; t.view.send(txt: text) }
}
