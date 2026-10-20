import AppKit

/// Scroll view that turns vertical wheel movement into horizontal scrolling (tab strip).
private final class HorizontalScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
            let clip = contentView
            let maxX = max(0, (documentView?.frame.width ?? 0) - clip.bounds.width)
            let x = min(max(0, clip.bounds.origin.x - event.scrollingDeltaY), maxX)
            clip.scroll(to: NSPoint(x: x, y: 0))
            reflectScrolledClipView(clip)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

/// One tab in the strip. Updated in place: title, dirty dot (becomes × on hover), VCS colour, selection.
final class TabItemView: NSView {
    let id: String
    weak var host: TabHost?
    private let label = NSTextField(labelWithString: "")
    private let button = NSButton()
    private var hovering = false { didSet { refresh() } }
    private(set) var title = ""
    private(set) var isDirty = false
    private(set) var isSelected = false
    private(set) var tint: NSColor?
    private var tracking: NSTrackingArea?

    init(id: String) {
        self.id = id
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5
        label.lineBreakMode = .byTruncatingTail
        label.isSelectable = false
        button.isBordered = false
        button.imageScaling = .scaleProportionallyDown
        button.target = self
        button.action = #selector(closeClicked)
        button.setButtonType(.momentaryChange)
        for v in [label, button] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            button.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 5),
            button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            button.centerYAnchor.constraint(equalTo: centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 14), button.heightAnchor.constraint(equalToConstant: 14),
            widthAnchor.constraint(lessThanOrEqualToConstant: 240),
            heightAnchor.constraint(equalToConstant: 24),
        ])
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, dirty: Bool, selected: Bool, tint: NSColor?) {
        self.title = title; isDirty = dirty; isSelected = selected; self.tint = tint
        refresh()
    }

    func refresh() {
        let color = tint ?? (isSelected ? Theme.foreground : Theme.gutter)
        label.attributedStringValue = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: isSelected ? .semibold : .regular),
            .foregroundColor: color])
        let showDot = isDirty && !hovering
        let symbol = showDot ? "circle.fill" : "xmark"
        let config = NSImage.SymbolConfiguration(pointSize: showDot ? 7 : 9, weight: .bold)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: showDot ? "Unsaved changes" : "Close")?
            .withSymbolConfiguration(config)
        button.contentTintColor = showDot ? Theme.foreground.withAlphaComponent(0.75) : Theme.gutter
        button.alphaValue = (isSelected || hovering || isDirty) ? 1 : 0
        button.toolTip = showDot ? "Unsaved changes" : "Close"
        layer?.backgroundColor = isSelected ? Theme.palette.tabSelected.cgColor
            : hovering ? Theme.foreground.withAlphaComponent(0.06).cgColor : nil
        toolTip = id
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { host?.userSelected(id) }
    override func mouseDragged(with event: NSEvent) { host?.drag(id, event: event) }
    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2, bounds.contains(convert(event.locationInWindow, from: nil)) { host?.onClose?(id) }
    }
    override func menu(for event: NSEvent) -> NSMenu? { host?.menuProvider?(id) }
    @objc private func closeClicked() { host?.onClose?(id) }
}

/// Tab strip + content host. Replaces NSTabView, which draws a bezel and insets we don't want.
/// The strip scrolls horizontally and shows a "…" menu of all tabs when they overflow.
final class TabHost: NSView {
    struct Entry {
        var id: String
        var title: String
        let view: NSView
        var isDirty = false
        var tint: NSColor?
    }
    private let scroll = HorizontalScrollView()
    private let strip = NSStackView()
    private let overflow = NSButton()
    private let content = NSView()
    private let barLine = NSView()
    private let hint = NSTextField(wrappingLabelWithString: """
        Go to File          ⌘⇧O
        Recent Files        ⌘E
        Search Everywhere   ⇧⇧
        Find Action         ⌘⇧A
        Open Project        ⌃⌘O
        Tree  ⌘1   Editor  ⌘2   Claude  ⌘3   Git  ⌘9
        Terminal  ⌃`   Back to editor  ⎋
        """)
    private(set) var entries: [Entry] = []
    private(set) var selectedID: String?
    private var items: [String: TabItemView] = [:]
    var onSelect: ((String) -> Void)?
    var onClose: ((String) -> Void)?
    /// Context menu for a tab (built by the window).
    var menuProvider: ((String) -> NSMenu?)?
    /// Files or folders dropped on the strip or empty area.
    var onDropURLs: (([URL]) -> Void)?
    var onReorder: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        hint.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        hint.alignment = .left
        hint.translatesAutoresizingMaskIntoConstraints = false
        restyle()
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: Theme.didChange, object: nil)
        strip.orientation = .horizontal
        strip.spacing = 2
        strip.alignment = .centerY
        strip.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)
        strip.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = strip
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.horizontalScrollElasticity = .none
        scroll.verticalScrollElasticity = .none
        overflow.isBordered = false
        overflow.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "All tabs")
        overflow.imageScaling = .scaleProportionallyDown
        overflow.target = self
        overflow.action = #selector(showOverflow(_:))
        overflow.toolTip = "All tabs"
        overflow.isHidden = true
        barLine.wantsLayer = true
        for v in [scroll, overflow, content, barLine] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        content.addSubview(hint)
        let clip = scroll.contentView
        NSLayoutConstraint.activate([
            hint.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            hint.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 28),
            scroll.trailingAnchor.constraint(equalTo: overflow.leadingAnchor),
            overflow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            overflow.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            overflow.widthAnchor.constraint(equalToConstant: 20), overflow.heightAnchor.constraint(equalToConstant: 20),
            strip.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            strip.topAnchor.constraint(equalTo: clip.topAnchor),
            strip.bottomAnchor.constraint(equalTo: clip.bottomAnchor),
            barLine.topAnchor.constraint(equalTo: scroll.bottomAnchor), barLine.leadingAnchor.constraint(equalTo: leadingAnchor),
            barLine.trailingAnchor.constraint(equalTo: trailingAnchor), barLine.heightAnchor.constraint(equalToConstant: 1),
            content.topAnchor.constraint(equalTo: barLine.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }

    // The overflow button appears only when the tabs are wider than the strip.
    override func layout() {
        super.layout()
        updateOverflow()
    }

    var isOverflowing: Bool { strip.fittingSize.width > scroll.bounds.width + 0.5 }

    private func updateOverflow() { overflow.isHidden = entries.isEmpty || !isOverflowing }

    @objc private func themeChanged() {
        restyle()
        for e in entries { refreshItem(e.id) }
        overflow.contentTintColor = Theme.gutter
    }

    private func restyle() {
        layer?.backgroundColor = Theme.background.cgColor
        barLine.layer?.backgroundColor = Theme.foreground.withAlphaComponent(0.08).cgColor
        hint.textColor = Theme.gutter
        overflow.contentTintColor = Theme.gutter
    }

    // MARK: Split (two tabs side by side; each tab keeps its single view, so a split costs one NSSplitView and no buffers)

    private var split: (left: String, right: String)?
    private var splitView: NSSplitView?
    private let leftBox = NSView(), rightBox = NSView()
    private var splitMonitor: Any?

    var isSplit: Bool { split != nil }
    var splitIDs: (left: String, right: String)? { split }

    private func fill(_ box: NSView, with view: NSView) {
        box.subviews.forEach { $0.removeFromSuperview() }
        view.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: box.topAnchor), view.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: box.leadingAnchor), view.trailingAnchor.constraint(equalTo: box.trailingAnchor),
        ])
    }

    /// Shows the selected tab and `other` side by side. When already split, `other` replaces the inactive pane.
    @discardableResult
    func splitWith(_ other: String) -> Bool {
        guard let active = selectedID, other != active,
              let a = entries.first(where: { $0.id == active }), let b = entries.first(where: { $0.id == other }) else { return false }
        if let sp = split {
            // replace whichever pane does not hold the active tab
            if sp.left == active { fill(rightBox, with: b.view); split = (active, other) }
            else { fill(leftBox, with: b.view); split = (other, active) }
            return true
        }
        content.subviews.filter { $0 !== hint }.forEach { $0.removeFromSuperview() }
        let sv = NSSplitView()
        sv.isVertical = true
        sv.dividerStyle = .thin
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.addArrangedSubview(leftBox)
        sv.addArrangedSubview(rightBox)
        content.addSubview(sv)
        NSLayoutConstraint.activate([
            sv.topAnchor.constraint(equalTo: content.topAnchor), sv.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sv.leadingAnchor.constraint(equalTo: content.leadingAnchor), sv.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ])
        fill(leftBox, with: a.view)
        fill(rightBox, with: b.view)
        splitView = sv
        split = (active, other)
        sv.layoutSubtreeIfNeeded()
        sv.setPosition(sv.bounds.width / 2, ofDividerAt: 0)
        splitMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            self?.activatePane(for: event)
            return event
        }
        return true
    }

    /// A click inside a pane makes that pane's tab the selected one.
    private func activatePane(for event: NSEvent) {
        guard let sp = split, event.window === window else { return }
        let p = event.locationInWindow
        for (box, id) in [(leftBox, sp.left), (rightBox, sp.right)] where id != selectedID {
            if box.convert(box.bounds, to: nil).contains(p) { select(id); return }
        }
    }

    private func tearDownSplit() {
        if let m = splitMonitor { NSEvent.removeMonitor(m); splitMonitor = nil }
        leftBox.subviews.forEach { $0.removeFromSuperview() }
        rightBox.subviews.forEach { $0.removeFromSuperview() }
        splitView?.removeFromSuperview()
        splitView = nil
        split = nil
    }

    /// Back to one editor: the selected tab fills the area.
    func unsplit() {
        guard split != nil else { return }
        tearDownSplit()
        if let id = selectedID { select(id) }
    }

    // MARK: Model

    func add(id: String, title: String, view: NSView) {
        entries.append(Entry(id: id, title: title, view: view))
        let item = TabItemView(id: id)
        item.host = self
        items[id] = item
        strip.addArrangedSubview(item)
        hint.isHidden = true
        refreshItem(id)
        select(id)
    }

    func setTitle(_ title: String, for id: String) {
        guard let i = entries.firstIndex(where: { $0.id == id }), entries[i].title != title else { return }
        entries[i].title = title
        refreshItem(id)
        needsLayout = true
    }

    func setDirty(_ dirty: Bool, for id: String) {
        guard let i = entries.firstIndex(where: { $0.id == id }), entries[i].isDirty != dirty else { return }
        entries[i].isDirty = dirty
        refreshItem(id)
    }

    func setTint(_ color: NSColor?, for id: String) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        if entries[i].tint == color { return }
        entries[i].tint = color
        refreshItem(id)
    }

    /// Gives a tab a new identity (file renamed/moved) without rebuilding anything.
    func retarget(_ id: String, to newID: String, title: String) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].id = newID
        entries[i].title = title
        if let item = items.removeValue(forKey: id) {
            let fresh = TabItemView(id: newID)
            fresh.host = self
            if let at = strip.arrangedSubviews.firstIndex(of: item) {
                strip.removeArrangedSubview(item); item.removeFromSuperview()
                strip.insertArrangedSubview(fresh, at: at)
            }
            items[newID] = fresh
        }
        if selectedID == id { selectedID = newID }
        if let sp = split { split = (sp.left == id ? newID : sp.left, sp.right == id ? newID : sp.right) }
        refreshItem(newID)
    }

    private func refreshItem(_ id: String) {
        guard let e = entries.first(where: { $0.id == id }) else { return }
        items[id]?.configure(title: e.title, dirty: e.isDirty, selected: id == selectedID, tint: e.tint)
    }

    func remove(_ id: String) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        var survivor: String?
        if let sp = split, id == sp.left || id == sp.right {
            survivor = id == sp.left ? sp.right : sp.left
            tearDownSplit()
            if selectedID == id { selectedID = survivor }   // the other pane's tab stays selected
        }
        entries.remove(at: i)
        if let item = items.removeValue(forKey: id) { strip.removeArrangedSubview(item); item.removeFromSuperview() }
        if let survivor, selectedID == survivor { select(survivor); needsLayout = true; return }
        if selectedID == id {
            selectedID = nil
            if let next = entries.indices.contains(i) ? entries[i] : entries.last { select(next.id) } else {
                content.subviews.filter { $0 !== hint }.forEach { $0.removeFromSuperview() }
                hint.isHidden = false
            }
        }
        needsLayout = true
    }

    func select(_ id: String) {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        let previous = selectedID
        selectedID = id
        if let sp = split {
            if id != sp.left, id != sp.right {
                // the new tab takes over the pane that was active
                if previous == sp.right { fill(rightBox, with: entry.view); split = (sp.left, id) }
                else { fill(leftBox, with: entry.view); split = (id, sp.right) }
            }
        } else if previous != id || entry.view.superview !== content {
            content.subviews.filter { $0 !== hint }.forEach { $0.removeFromSuperview() }
            entry.view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(entry.view)
            NSLayoutConstraint.activate([
                entry.view.topAnchor.constraint(equalTo: content.topAnchor),
                entry.view.bottomAnchor.constraint(equalTo: content.bottomAnchor),
                entry.view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                entry.view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            ])
        }
        if let previous { refreshItem(previous) }
        refreshItem(id)
        revealSelected()
        onSelect?(id)
    }

    private func revealSelected() {
        guard let id = selectedID, let item = items[id] else { return }
        DispatchQueue.main.async { [weak self, weak item] in
            guard let self, let item else { return }
            self.layoutSubtreeIfNeeded()
            self.strip.scrollToVisible(item.frame.insetBy(dx: -24, dy: 0))
        }
    }

    // MARK: Reordering and bulk helpers

    func move(_ id: String, toIndex target: Int) {
        guard let from = entries.firstIndex(where: { $0.id == id }) else { return }
        let to = min(max(0, target), entries.count - 1)
        guard from != to else { return }
        let entry = entries.remove(at: from)
        entries.insert(entry, at: to)
        if let item = items[id] {
            strip.removeArrangedSubview(item)
            strip.insertArrangedSubview(item, at: to)
        }
        onReorder?()
    }

    func ids(toRightOf id: String) -> [String] {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return [] }
        return entries[(i + 1)...].map(\.id)
    }

    func ids(except id: String) -> [String] { entries.map(\.id).filter { $0 != id } }

    func itemView(for id: String) -> TabItemView? { items[id] }

    fileprivate func userSelected(_ id: String) { select(id) }

    fileprivate func drag(_ id: String, event: NSEvent) {
        let x = strip.convert(event.locationInWindow, from: nil).x
        let views = strip.arrangedSubviews
        guard let current = views.firstIndex(where: { ($0 as? TabItemView)?.id == id }) else { return }
        var target = current
        for (i, v) in views.enumerated() where x >= v.frame.minX && x < v.frame.maxX { target = i }
        if x < (views.first?.frame.minX ?? 0) { target = 0 }
        if x >= (views.last?.frame.maxX ?? 0) { target = views.count - 1 }
        if target != current { move(id, toIndex: target) }
    }

    @objc private func showOverflow(_ sender: NSButton) {
        let menu = NSMenu()
        for e in entries {
            let item = NSMenuItem(title: e.title, action: #selector(overflowPicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = e.id
            item.state = e.id == selectedID ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 2), in: sender)
    }

    @objc private func overflowPicked(_ item: NSMenuItem) { if let id = item.representedObject as? String { select(id) } }

    // MARK: Drops (files from Finder/tree open as tabs; folders as projects)

    private func fileURLs(_ info: NSDraggingInfo) -> [URL] {
        (info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { fileURLs(sender).isEmpty ? [] : .copy }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { fileURLs(sender).isEmpty ? [] : .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(sender)
        guard !urls.isEmpty else { return false }
        onDropURLs?(urls)
        return true
    }
}
