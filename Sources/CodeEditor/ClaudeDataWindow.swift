import AppKit

/// File > Claude Data for This Project…: shows what Claude Code has stored for the project (sessions with their size, date and first
/// prompt, memory notes, the project's `.claude` folder) and moves the ticked sessions to the Trash. Built on demand, released on close.
final class ClaudeDataWindowController: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private static var current: ClaudeDataWindowController?

    private let root: URL
    private var snap = ClaudeData.Snapshot()
    private var pickedSessions = Set<String>()
    private var pickedMemory = Set<String>()
    private var window: NSWindow?
    private let header = NSTextField(labelWithString: "Scanning…")
    private let sub = NSTextField(labelWithString: "")
    private let summary = NSTextField(labelWithString: "")
    private let sessions = NSTableView(), memory = NSTableView()
    private let trashButton = NSButton(title: "Move to Trash", target: nil, action: nil)
    private let localLabel = NSTextField(wrappingLabelWithString: "")
    private var memoryScroll: NSScrollView?
    private var memoryTitle: NSTextField?

    static func show(root: URL) {
        guard !AppEnv.headless else { return }
        if let c = current { c.window?.makeKeyAndOrderFront(nil); return }
        let c = ClaudeDataWindowController(root: root)
        current = c
        c.build()
    }

    private init(root: URL) { self.root = root }

    // MARK: window

    /// Headless render of the window for a given snapshot (verification only; nothing is shown).
    static func render(_ snap: ClaudeData.Snapshot, picked: Set<String>, to path: String) {
        let c = ClaudeDataWindowController(root: URL(fileURLWithPath: "/Users/dev/demo-project"))
        c.build(show: false)
        c.pickedSessions = picked
        c.apply(snap)
        guard let v = c.window?.contentView else { return }
        v.frame = NSRect(x: 0, y: 0, width: 780, height: 640)
        v.layoutSubtreeIfNeeded()
        v.appearance = NSAppearance(named: .aqua)
        if let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
            v.cacheDisplay(in: v.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
    }

    private func build(show: Bool = true) {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 640), styleMask: [.titled, .closable, .resizable, .miniaturizable],
                         backing: .buffered, defer: false)
        w.title = "Claude Data — \(root.lastPathComponent)"
        w.delegate = self
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 640, height: 480)
        window = w

        header.font = .systemFont(ofSize: 20, weight: .semibold)
        sub.font = .systemFont(ofSize: 12); sub.textColor = .secondaryLabelColor
        sub.lineBreakMode = .byTruncatingMiddle

        let quick = NSPopUpButton(frame: .zero, pullsDown: true)
        quick.addItem(withTitle: "Quick select")
        for (title, sel) in [("Older than 30 days", #selector(pickOlder30)), ("Older than 7 days", #selector(pickOlder7)), ("Larger than 20 MB", #selector(pickLarge)),
                             ("All except the newest 5", #selector(pickAllButNewest)), ("Clear selection", #selector(pickNone))] {
            let it = NSMenuItem(title: title, action: sel, keyEquivalent: ""); it.target = self; quick.menu?.addItem(it)
        }
        let top = NSStackView(views: [NSStackView(views: [header, sub]), quick])
        (top.views[0] as? NSStackView)?.orientation = .vertical
        (top.views[0] as? NSStackView)?.alignment = .leading
        (top.views[0] as? NSStackView)?.spacing = 2
        top.distribution = .fill
        top.alignment = .top

        configure(sessions, rowHeight: 50)
        configure(memory, rowHeight: 28)
        let sScroll = scroll(sessions)
        let mScroll = scroll(memory)
        memoryScroll = mScroll
        mScroll.heightAnchor.constraint(equalToConstant: 100).isActive = true
        let mTitle = NSTextField(labelWithString: "Memory — notes Claude reads in every session. Kept unless you tick them.")
        mTitle.font = .systemFont(ofSize: 12, weight: .medium); mTitle.textColor = .secondaryLabelColor
        memoryTitle = mTitle
        localLabel.font = .systemFont(ofSize: 11); localLabel.textColor = .secondaryLabelColor

        summary.font = .systemFont(ofSize: 13, weight: .medium)
        trashButton.target = self; trashButton.action = #selector(trash); trashButton.bezelStyle = .rounded; trashButton.keyEquivalent = "\r"
        trashButton.hasDestructiveAction = true
        let reveal = NSButton(title: "Reveal in Finder", target: self, action: #selector(revealFolder)); reveal.bezelStyle = .rounded
        let close = NSButton(title: "Close", target: self, action: #selector(closeWindow)); close.bezelStyle = .rounded
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [summary, spacer, reveal, close, trashButton])
        footer.spacing = 8

        let stack = NSStackView(views: [top, sScroll, mTitle, mScroll, localLabel, footer])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        for v in [top, sScroll, mScroll, footer] { v.translatesAutoresizingMaskIntoConstraints = false; v.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true }
        sScroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        w.contentView = stack
        guard show else { return }
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        reload()
    }

    private func configure(_ t: NSTableView, rowHeight: CGFloat) {
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c")); col.resizingMask = .autoresizingMask
        t.addTableColumn(col); t.headerView = nil; t.rowHeight = rowHeight
        t.dataSource = self; t.delegate = self; t.usesAlternatingRowBackgroundColors = true; t.selectionHighlightStyle = .none
        t.intercellSpacing = NSSize(width: 0, height: 0)
    }

    private func scroll(_ t: NSTableView) -> NSScrollView {
        let s = NSScrollView(); s.documentView = t; s.hasVerticalScroller = true; s.borderType = .bezelBorder
        return s
    }

    func windowWillClose(_ notification: Notification) { Self.current = nil; window = nil; snap = ClaudeData.Snapshot() }
    @objc private func closeWindow() { window?.close() }

    // MARK: data

    private func reload() {
        header.stringValue = "Scanning…"
        let root = self.root
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let s = ClaudeData.scan(projectRoot: root)
            DispatchQueue.main.async { self?.apply(s) }
        }
    }

    private func apply(_ s: ClaudeData.Snapshot) {
        snap = s
        pickedSessions = pickedSessions.intersection(Set(s.sessions.map(\.id)))
        pickedMemory = []
        header.stringValue = ClaudeData.format(s.totalBytes) + " of Claude data"
        let newest = s.sessions.first.map { RelativeDateTimeFormatter().localizedString(for: $0.modified, relativeTo: Date()) } ?? "none"
        sub.stringValue = s.projectDir == nil ? "Nothing stored for this project yet." : "\(s.sessions.count) sessions · newest \(newest) · \(s.projectDir!.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))"
        let hasMemory = !s.memory.isEmpty
        memoryScroll?.isHidden = !hasMemory; memoryTitle?.isHidden = !hasMemory
        localLabel.stringValue = s.local.isEmpty ? "" : "Project folder .claude (not touched here): " + s.local.map { "\($0.name) \(ClaudeData.format($0.bytes))" }.joined(separator: " · ")
        sessions.reloadData(); memory.reloadData()
        updateSummary()
    }

    private func updateSummary() {
        let chosen = snap.sessions.filter { pickedSessions.contains($0.id) }
        let mem = snap.memory.filter { pickedMemory.contains($0.name) }
        let bytes = chosen.reduce(Int64(0)) { $0 + $1.bytes } + mem.reduce(Int64(0)) { $0 + $1.bytes }
        if chosen.isEmpty && mem.isEmpty { summary.stringValue = "Nothing selected"; trashButton.isEnabled = false; trashButton.title = "Move to Trash"; return }
        summary.stringValue = "\(chosen.count) session\(chosen.count == 1 ? "" : "s")" + (mem.isEmpty ? "" : " + \(mem.count) memory") + " · frees \(ClaudeData.format(bytes))"
        trashButton.isEnabled = true
        trashButton.title = "Move \(ClaudeData.format(bytes)) to Trash"
    }

    // MARK: table

    func numberOfRows(in tableView: NSTableView) -> Int { tableView === sessions ? snap.sessions.count : snap.memory.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === sessions {
            let s = snap.sessions[row]
            let maxBytes = max(1, snap.sessions.map(\.bytes).max() ?? 1)
            return RowView(title: s.title, detail: "\(Self.dateText(s.modified)) · \(ClaudeData.format(s.bytes))" + (s.isActive ? " · active now" : ""),
                           fraction: CGFloat(Double(s.bytes) / Double(maxBytes)), checked: pickedSessions.contains(s.id), enabled: !s.isActive,
                           tint: s.bytes > 20 * 1_048_576 ? .systemOrange : .systemBlue) { [weak self] on in
                if on { self?.pickedSessions.insert(s.id) } else { self?.pickedSessions.remove(s.id) }
                self?.updateSummary()
            }
        }
        let m = snap.memory[row]
        return RowView(title: m.name, detail: ClaudeData.format(m.bytes), fraction: 0, checked: pickedMemory.contains(m.name), enabled: true, tint: .systemGreen) { [weak self] on in
            if on { self?.pickedMemory.insert(m.name) } else { self?.pickedMemory.remove(m.name) }
            self?.updateSummary()
        }
    }

    private static func dateText(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = Calendar.current.isDate(d, equalTo: Date(), toGranularity: .year) ? "d MMM, HH:mm" : "d MMM yyyy"
        return f.string(from: d)
    }

    // MARK: actions

    @objc private func pickOlder30() { pick(ClaudeData.olderThan(30, in: snap.sessions)) }
    @objc private func pickOlder7() { pick(ClaudeData.olderThan(7, in: snap.sessions)) }
    @objc private func pickLarge() { pick(ClaudeData.largerThan(20, in: snap.sessions)) }
    @objc private func pickAllButNewest() { pick(ClaudeData.allButNewest(5, in: snap.sessions)) }
    @objc private func pickNone() { pick([]) }
    private func pick(_ ids: Set<String>) { pickedSessions = ids; sessions.reloadData(); updateSummary() }

    @objc private func revealFolder() {
        if let d = snap.projectDir { NSWorkspace.shared.activateFileViewerSelecting([d]) }
    }

    @objc private func trash() {
        let chosen = snap.sessions.filter { pickedSessions.contains($0.id) }
        let mem = snap.memory.filter { pickedMemory.contains($0.name) }
        guard !chosen.isEmpty || !mem.isEmpty, let w = window else { return }
        let alert = NSAlert()
        alert.messageText = "Move \(chosen.count) session\(chosen.count == 1 ? "" : "s")" + (mem.isEmpty ? "" : " and \(mem.count) memory file\(mem.count == 1 ? "" : "s")") + " to the Trash?"
        alert.informativeText = "Claude can no longer resume these sessions" + (mem.isEmpty ? "" : ", and it forgets the ticked memory notes") + ". You can restore them from the Trash."
        alert.addButton(withTitle: "Move to Trash"); alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: w) { [weak self] r in
            guard r == .alertFirstButtonReturn, let self else { return }
            let res = ClaudeData.remove(sessions: chosen, memory: mem)
            self.pickedSessions = []
            self.reload()
            self.summary.stringValue = res.failed.isEmpty ? "Freed \(ClaudeData.format(res.freed))" : "Freed \(ClaudeData.format(res.freed)); \(res.failed.count) item(s) could not be moved"
        }
    }

    // MARK: row view

    private final class RowView: NSView {
        private let check = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        private let bar = BarView()
        private let onToggle: (Bool) -> Void

        init(title: String, detail: String, fraction: CGFloat, checked: Bool, enabled: Bool, tint: NSColor, onToggle: @escaping (Bool) -> Void) {
            self.onToggle = onToggle
            super.init(frame: .zero)
            check.state = checked ? .on : .off; check.isEnabled = enabled; check.target = self; check.action = #selector(toggled)
            let t = NSTextField(labelWithString: title); t.font = .systemFont(ofSize: 13, weight: .medium); t.lineBreakMode = .byTruncatingTail
            t.textColor = enabled ? .labelColor : .tertiaryLabelColor
            let d = NSTextField(labelWithString: detail); d.font = .systemFont(ofSize: 11); d.textColor = .secondaryLabelColor
            bar.fraction = fraction; bar.tint = tint
            let text = NSStackView(views: [t, d]); text.orientation = .vertical; text.alignment = .leading; text.spacing = 1
            for v in [check, text, bar] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
            t.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            NSLayoutConstraint.activate([
                check.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10), check.centerYAnchor.constraint(equalTo: centerYAnchor),
                text.leadingAnchor.constraint(equalTo: check.trailingAnchor, constant: 6), text.centerYAnchor.constraint(equalTo: centerYAnchor),
                bar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12), bar.centerYAnchor.constraint(equalTo: centerYAnchor),
                bar.widthAnchor.constraint(equalToConstant: fraction > 0 ? 150 : 0), bar.heightAnchor.constraint(equalToConstant: 8),
                text.trailingAnchor.constraint(lessThanOrEqualTo: bar.leadingAnchor, constant: -12),
            ])
        }
        required init?(coder: NSCoder) { fatalError() }
        @objc private func toggled() { onToggle(check.state == .on) }
    }

    /// A rounded proportional bar: how much of the project's biggest session this one is.
    private final class BarView: NSView {
        var fraction: CGFloat = 0
        var tint: NSColor = .systemBlue
        override func draw(_ dirtyRect: NSRect) {
            guard fraction > 0 else { return }
            NSColor.quaternaryLabelColor.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
            tint.setFill()
            NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: max(6, bounds.width * fraction), height: bounds.height), xRadius: 4, yRadius: 4).fill()
        }
    }
}

extension ProjectWindow {
    func showClaudeData() {
        guard let root else { return }
        ClaudeDataWindowController.show(root: root)
    }
}
