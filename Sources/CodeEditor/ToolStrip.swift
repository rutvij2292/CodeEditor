import AppKit

/// PhpStorm-style slim icon strip on the far left of the project window. Every button runs the same action as its menu item /
/// number key; the active highlight follows the real visibility (sidebar, bottom panel, terminal). Event driven: it re-reads the
/// state on the split-view resize and BottomPanel change notifications, never on a timer.
final class ToolStripView: NSView {
    static let width: CGFloat = 40

    enum Kind { case sidebar, commit, pullRequests, bottom(String), terminal, claude, routes }

    struct Entry {
        let id: String
        let symbol: String
        let title: String
        let shortcut: String?
        let kind: Kind
        var tooltip: String { shortcut.map { KeymapStore.retip("\(title) (\($0))") } ?? title }
    }

    static let top: [Entry] = [
        Entry(id: "project", symbol: "folder", title: "Project", shortcut: "⌘1", kind: .sidebar),
        Entry(id: "commit", symbol: "checkmark.circle", title: "Commit", shortcut: "⌘K", kind: .commit),
        Entry(id: "pulls", symbol: "arrow.triangle.pull", title: "Pull Requests", shortcut: "⌥⇧⌘P", kind: .pullRequests),
    ]
    static let middle: [Entry] = [
        Entry(id: "structure", symbol: "list.bullet.indent", title: "Structure", shortcut: "⌘7", kind: .bottom("structure")),
        Entry(id: "bookmarks", symbol: "bookmark", title: "Bookmarks", shortcut: "⌥⌘2", kind: .bottom("bookmarks")),
    ]
    static let overflow: [Entry] = [
        Entry(id: "claude", symbol: "sparkles", title: "Claude Code", shortcut: "⌘3", kind: .claude),
        Entry(id: "find", symbol: "magnifyingglass", title: "Find", shortcut: "⌘4", kind: .bottom("find")),
        Entry(id: "todo", symbol: "checklist", title: "TODO", shortcut: "⌘8", kind: .bottom("todo")),
        Entry(id: "http", symbol: "network", title: "HTTP Client", shortcut: "⌥⌘8", kind: .bottom("http")),
        Entry(id: "claude-changes", symbol: "doc.badge.gearshape", title: "Claude Changes", shortcut: nil, kind: .bottom("claude-changes")),
        Entry(id: "terminal", symbol: "terminal", title: "Terminal", shortcut: "⌥F12", kind: .terminal),
    ]
    static let bottomGroup: [Entry] = [
        Entry(id: "laravel", symbol: "map", title: "Laravel Routes", shortcut: nil, kind: .routes),
        Entry(id: "tests", symbol: "play", title: "Run / Tests", shortcut: "⌘6", kind: .bottom("tests")),
        Entry(id: "problems", symbol: "exclamationmark.circle", title: "Problems", shortcut: "⌘5", kind: .bottom("problems")),
        Entry(id: "git", symbol: "arrow.triangle.branch", title: "Git", shortcut: "⌘9", kind: .bottom("git")),
    ]

    weak var project: ProjectWindow?
    private(set) var buttons: [String: NSButton] = [:]
    private let badgeDot = NSView()
    private let divider = NSView()
    private var separator: NSView?
    private var widthConstraint: NSLayoutConstraint!
    private var observers: [NSObjectProtocol] = []
    private(set) var isLaravel = false

    func entry(id: String) -> Entry? { (Self.top + Self.middle + Self.bottomGroup + Self.overflow).first { $0.id == id } }

    init(project: ProjectWindow) {
        self.project = project
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.toolbar)
        setAccessibilityLabel("Tool window icons")
        translatesAutoresizingMaskIntoConstraints = false
        widthConstraint = widthAnchor.constraint(equalToConstant: Self.width)
        widthConstraint.isActive = true
        build()
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: BottomPanel.stateDidChange, object: project.bottom, queue: .main) { [weak self] _ in self?.refresh() })
        observers.append(nc.addObserver(forName: NSSplitView.didResizeSubviewsNotification, object: project.mainSplit.splitView, queue: .main) { [weak self] _ in self?.refresh() })
        observers.append(nc.addObserver(forName: Theme.didChange, object: nil, queue: .main) { [weak self] _ in self?.restyle() })
        observers.append(nc.addObserver(forName: Prefs.didChange, object: nil, queue: .main) { [weak self] n in
            if n.userInfo?["key"] as? String == "showToolStrip" { self?.applyPref() }
        })
        buttons["laravel"]?.isHidden = true
        applyPref()
        restyle()
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    // MARK: Build

    private func makeButton(_ e: Entry) -> NSButton {
        let b = NSButton()
        b.isBordered = false
        b.imagePosition = .imageOnly
        b.imageScaling = .scaleNone
        b.image = Self.icon(e.symbol, e.title)
        b.toolTip = e.tooltip
        b.setAccessibilityLabel(e.title)
        if let s = e.shortcut { b.setAccessibilityHelp(KeymapStore.retip("Shortcut (\(s))")) }
        b.identifier = NSUserInterfaceItemIdentifier(e.id)
        b.target = self
        b.action = #selector(clicked(_:))
        b.wantsLayer = true
        b.layer?.cornerRadius = 7
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 30).isActive = true
        b.heightAnchor.constraint(equalToConstant: 30).isActive = true
        buttons[e.id] = b
        return b
    }

    static func icon(_ symbol: String, _ label: String) -> NSImage? {
        let cfg = NSImage.SymbolConfiguration(pointSize: 16, weight: .light)
        return NSImage(systemSymbolName: symbol, accessibilityDescription: label)?.withSymbolConfiguration(cfg)
    }

    private func build() {
        let topStack = NSStackView(views: Self.top.map(makeButton))
        let sep = NSView()
        sep.wantsLayer = true
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.heightAnchor.constraint(equalToConstant: 1).isActive = true
        sep.widthAnchor.constraint(equalToConstant: 20).isActive = true
        topStack.addArrangedSubview(sep)
        separator = sep
        for e in Self.middle { topStack.addArrangedSubview(makeButton(e)) }
        let more = makeButton(Entry(id: "more", symbol: "ellipsis", title: "More Tool Windows", shortcut: nil, kind: .sidebar))
        more.action = #selector(showOverflow(_:))
        topStack.addArrangedSubview(more)
        let bottomStack = NSStackView(views: Self.bottomGroup.map(makeButton))
        for s in [topStack, bottomStack] {
            s.orientation = .vertical
            s.spacing = 4
            s.alignment = .centerX
            s.translatesAutoresizingMaskIntoConstraints = false
            addSubview(s)
        }
        divider.wantsLayer = true
        divider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(divider)
        badgeDot.wantsLayer = true
        badgeDot.layer?.cornerRadius = 4
        badgeDot.translatesAutoresizingMaskIntoConstraints = false
        badgeDot.isHidden = true
        if let p = buttons["problems"] {
            p.addSubview(badgeDot)
            NSLayoutConstraint.activate([badgeDot.widthAnchor.constraint(equalToConstant: 8), badgeDot.heightAnchor.constraint(equalToConstant: 8),
                                         badgeDot.topAnchor.constraint(equalTo: p.topAnchor, constant: 3),
                                         badgeDot.trailingAnchor.constraint(equalTo: p.trailingAnchor, constant: -3)])
        }
        NSLayoutConstraint.activate([
            topStack.topAnchor.constraint(equalTo: topAnchor, constant: 8), topStack.centerXAnchor.constraint(equalTo: centerXAnchor, constant: -0.5),
            bottomStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8), bottomStack.centerXAnchor.constraint(equalTo: centerXAnchor, constant: -0.5),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor), divider.topAnchor.constraint(equalTo: topAnchor),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor), divider.widthAnchor.constraint(equalToConstant: 1),
        ])
    }

    // MARK: State

    private func applyPref() {
        let on = Prefs.showToolStrip
        isHidden = !on
        widthConstraint.constant = on ? Self.width : 0
        if on { refresh() }
    }

    /// Shows the Laravel button only for projects with an `artisan` file.
    func projectChanged() {
        guard let root = project?.root else { return }
        isLaravel = FileManager.default.fileExists(atPath: root.appendingPathComponent("artisan").path)
        buttons["laravel"]?.isHidden = !isLaravel
    }

    func isActive(_ e: Entry) -> Bool {
        guard let p = project else { return false }
        switch e.kind {
        case .sidebar: return p.isSidebarVisible
        case .bottom(let id): return p.bottom.isVisible && p.bottom.selectedID == id
        case .terminal: return p.isTerminalVisible
        case .claude: return p.isTerminalVisible && (p.terminalPanel?.isClaudeTabActive ?? false)
        case .commit, .pullRequests, .routes: return false
        }
    }

    /// Re-reads visibility and the Problems badge; cheap, called from notifications only.
    func refresh() {
        guard !isHidden else { return }
        for e in Self.top + Self.middle + Self.bottomGroup {
            guard let b = buttons[e.id] else { continue }
            let on = isActive(e)
            b.layer?.backgroundColor = on ? highlight.cgColor : nil
            b.contentTintColor = on ? Theme.foreground : Theme.gutter
            b.setAccessibilityValue(on ? "active" : "inactive")
        }
        if let n = project?.bottom.badge(for: "problems") {
            badgeDot.isHidden = false
            buttons["problems"]?.toolTip = "Problems, \(n) (⌘5)"
            buttons["problems"]?.setAccessibilityLabel("Problems, \(n)")
        } else {
            badgeDot.isHidden = true
            buttons["problems"]?.toolTip = entry(id: "problems")?.tooltip
            buttons["problems"]?.setAccessibilityLabel("Problems")
        }
        buttons["more"]?.contentTintColor = Theme.gutter
    }

    private var highlight: NSColor { Theme.foreground.withAlphaComponent(Theme.isDark ? 0.16 : 0.10) }

    func restyle() {
        layer?.backgroundColor = Theme.palette.sidebarBackground.cgColor
        divider.layer?.backgroundColor = Theme.palette.divider.cgColor
        separator?.layer?.backgroundColor = Theme.palette.divider.cgColor
        badgeDot.layer?.backgroundColor = NSColor.systemRed.cgColor
        refresh()
    }

    // MARK: Actions

    @objc private func clicked(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue, let e = entry(id: id) else { return }
        perform(e)
    }

    /// Runs a tool's action: shows it, or hides it when it is already the visible tool.
    func perform(_ e: Entry) {
        guard let p = project, p.root != nil else { return }
        let wasActive = isActive(e)
        switch e.kind {
        case .sidebar:
            if wasActive { p.toggleSidebar() } else { p.toggleProjectTree() }
        case .commit: p.showCommitWindow()
        case .pullRequests: (NSApp.delegate as? AppDelegate)?.resolvePullRequest(nil)
        case .routes: p.showRouteBrowser()
        case .terminal: p.toggleTerminal()
        case .claude:
            if wasActive { p.hideTerminal(); p.focusEditor() } else { p.toggleClaude() }
        case .bottom(let id):
            if wasActive { p.bottom.hide(); p.focusEditor(); return }
            if id == "structure" { p.installStructurePanel() }
            guard p.bottom.has(id) else { return }
            p.bottom.show(id) { [weak p] in p?.focusTool(id) }
        }
    }

    @objc private func showOverflow(_ sender: NSButton) {
        let menu = NSMenu()
        for e in Self.overflow {
            let item = NSMenuItem(title: e.title, action: #selector(overflowPicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = e.id
            item.image = Self.icon(e.symbol, e.title)
            item.state = isActive(e) ? .on : .off
            if let s = e.shortcut { item.toolTip = KeymapStore.retip("\(e.title) (\(s))") }
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: sender.bounds.maxX + 4, y: sender.bounds.maxY), in: sender)
    }

    @objc private func overflowPicked(_ item: NSMenuItem) {
        if let id = item.representedObject as? String, let e = entry(id: id) { perform(e) }
    }
}

/// Container that puts the strip left of the window's root split.
final class ToolStripContainerController: NSViewController {
    let strip: ToolStripView
    private let content: NSViewController

    init(strip: ToolStripView, content: NSViewController) {
        self.strip = strip
        self.content = content
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let host = NSView()
        addChild(content)
        content.view.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(strip)
        host.addSubview(content.view)
        NSLayoutConstraint.activate([
            strip.leadingAnchor.constraint(equalTo: host.leadingAnchor), strip.topAnchor.constraint(equalTo: host.topAnchor),
            strip.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            content.view.leadingAnchor.constraint(equalTo: strip.trailingAnchor), content.view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            content.view.topAnchor.constraint(equalTo: host.topAnchor), content.view.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
        view = host
    }
}
