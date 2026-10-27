import AppKit

/// Owns one tab's breadcrumb bar: debounced refresh, background outline builds, dropdown menus and context menu.
final class BreadcrumbController: NSObject, NSMenuDelegate {
    static let debounceDelay: TimeInterval = 0.12
    static let maxMenuEntries = 300

    let bar = BreadcrumbBar()
    private weak var tab: EditorTab?
    private(set) var outline: BreadcrumbOutline?
    private var outlineVersion = -1
    private var building = false
    private(set) var editVersion = 0
    /// Counters for tests: how many refreshes / background outline builds ran.
    private(set) var refreshCount = 0
    private(set) var buildCount = 0
    private var debounce: DispatchWorkItem?
    private let queue = DispatchQueue(label: "ce.breadcrumbs", qos: .utility)
    private var rootCache: (key: String, root: URL?)?
    /// Outline indices of the symbol segments currently shown.
    private(set) var chain: [Int] = []
    var onChange: (() -> Void)?                 // fired after the bar's segments changed (tests)

    init(tab: EditorTab) {
        self.tab = tab
        super.init()
        bar.menuProvider = { [weak self] i in self?.menu(forSegment: i) }
        bar.jumpProvider = { [weak self] i in
            guard let self, let show = self.tab?.onShowStructure, self.bar.segments.indices.contains(i) else { return false }
            switch self.bar.segments[i].kind {
            case .file, .symbol: show(); return true
            default: return false
            }
        }
        bar.contextMenuProvider = { [weak self] i in self?.contextMenu(forSegment: i) }
        bar.onEscape = { [weak self] in self?.returnFocus() }
    }

    // MARK: Triggers

    func noteEdit() { editVersion += 1; schedule() }
    func noteSelection() { schedule() }

    func schedule() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + PowerState.shared.scaled(Self.debounceDelay), execute: work)
    }

    private var grammarKey: String? {
        guard let tab, !tab.isLargeFile else { return nil }
        let key = Languages.key(forFileName: tab.url.lastPathComponent)
        return BreadcrumbOutlineBuilder.supports(key: key) ? key : nil
    }

    var pathSegments: [BreadcrumbSegment] {
        guard let tab else { return [] }
        let explicit = tab.projectRoot?()
        let key = tab.url.path + "|" + (explicit?.path ?? "")
        if rootCache?.key != key { rootCache = (key, BreadcrumbPath.root(for: tab.url, explicit: explicit)) }
        return BreadcrumbPath.segments(for: tab.url, root: rootCache?.root)
    }

    /// Recomputes the segments now (the debounce target; also called directly by tests and on show).
    func refresh() { Perf.measure("breadcrumb.refresh") { refreshImpl() } }

    private func refreshImpl() {
        debounce?.cancel(); debounce = nil
        if PowerState.deferWhileHidden(tab?.textView, { [weak self] in self?.refresh() }) { return }
        refreshCount += 1
        guard let tab, Prefs.showBreadcrumbs else { return }
        var segments = pathSegments
        chain = []
        if let key = grammarKey {
            if let outline {
                chain = outline.chain(at: min(tab.textView.selectedRange().location, tab.textView.textStorage?.length ?? 0))
                if key == "vue" { chain = Self.vueTrail(chain, outline.nodes) }
                for i in chain where outline.nodes.indices.contains(i) {
                    segments.append(BreadcrumbSegment(title: outline.nodes[i].name, kind: .symbol(outline.nodes[i].kind), url: nil, node: i))
                }
            }
            if outlineVersion != editVersion { rebuildOutline(key: key) }
        }
        bar.set(segments: segments)
        onChange?()
    }

    /// Vue SFC trail: the block, components and named slots, and the innermost element; plain wrapper divs are left out and the template
    /// part keeps at most 4 nodes (outermost dropped first). Script symbols are untouched.
    static func vueTrail(_ chain: [Int], _ nodes: [BreadcrumbNode]) -> [Int] {
        var kept: [Int] = []
        for (n, i) in chain.enumerated() where nodes.indices.contains(i) {
            let node = nodes[i]
            if node.parent < 0 || node.kind != .tag || n == chain.count - 1 { kept.append(i) }
        }
        let inner = kept.filter { nodes[$0].parent >= 0 && (nodes[$0].kind == .tag || nodes[$0].kind == .component) }
        guard inner.count > 4 else { return kept }
        let drop = Set(inner.prefix(inner.count - 4))
        return kept.filter { !drop.contains($0) }
    }

    private func rebuildOutline(key: String) {
        guard !building, let tab else { return }
        building = true
        let version = editVersion
        let text = tab.textView.string
        let languages = BreadcrumbOutlineBuilder.languages(for: key)         // grammar cache is main-thread only
        buildCount += 1
        queue.async { [weak self] in
            let built = BreadcrumbOutlineBuilder.build(text: text, key: key, languages: languages)
            DispatchQueue.main.async {
                guard let self else { return }
                self.building = false
                self.outline = built
                self.outlineVersion = version
                self.refresh()               // picks up the new outline (and rebuilds again if more edits arrived meanwhile)
            }
        }
    }

    /// Synchronous build for tests/previews.
    func rebuildOutlineNow() {
        guard let key = grammarKey, let tab else { return }
        outline = BreadcrumbOutlineBuilder.build(text: tab.textView.string, key: key, languages: BreadcrumbOutlineBuilder.languages(for: key))
        outlineVersion = editVersion
    }

    func returnFocus() {
        if let tv = tab?.textView { tv.window?.makeFirstResponder(tv) }
    }

    // MARK: Dropdowns

    /// Keeps menu actions alive on the item.
    private final class Action: NSObject { let run: () -> Void; init(_ run: @escaping () -> Void) { self.run = run } }
    private final class LazyMenu: NSMenu { var populate: ((NSMenu) -> Void)? }

    @objc private func fire(_ sender: NSMenuItem) { (sender.representedObject as? Action)?.run() }

    private func item(_ title: String, symbol: String?, tint: NSColor? = nil, checked: Bool = false, _ run: (() -> Void)?) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: run == nil ? nil : #selector(fire(_:)), keyEquivalent: "")
        it.target = self
        if let run { it.representedObject = Action(run) }
        if let symbol, let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
                .applying(.init(paletteColors: [tint ?? .secondaryLabelColor]))
            it.image = img.withSymbolConfiguration(cfg)
        }
        if checked { it.state = .on }
        return it
    }

    /// Folder contents: folders first, then files, each alphabetically; hidden housekeeping entries skipped.
    static func directoryEntries(_ dir: URL) -> [(url: URL, isDir: Bool)] {
        let keys: [URLResourceKey] = [.isDirectoryKey]
        let list = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys)) ?? []
        let entries = list.filter { $0.lastPathComponent != ".git" && $0.lastPathComponent != ".DS_Store" }
            .map { ($0, (try? $0.resourceValues(forKeys: Set(keys)))?.isDirectory == true) }
        return entries.sorted {
            if $0.1 != $1.1 { return $0.1 }
            return $0.0.lastPathComponent.localizedCaseInsensitiveCompare($1.0.lastPathComponent) == .orderedAscending
        }.map { (url: $0.0, isDir: $0.1) }
    }

    /// Menu items for a folder; folders get a lazily filled submenu ("descend"), files open through `onOpenURL`.
    func directoryItems(_ dir: URL, current: URL?) -> [NSMenuItem] {
        let entries = Self.directoryEntries(dir)
        var items: [NSMenuItem] = []
        for e in entries.prefix(Self.maxMenuEntries) {
            let name = e.url.lastPathComponent
            if e.isDir {
                let it = item(name, symbol: "folder", tint: .systemBlue, checked: e.url.standardizedFileURL == current?.standardizedFileURL, nil)
                let sub = LazyMenu(title: name)
                sub.delegate = self
                sub.populate = { [weak self] m in
                    guard let self else { return }
                    for child in self.directoryItems(e.url, current: nil) { m.addItem(child) }
                    if m.items.isEmpty { let empty = NSMenuItem(title: "Empty", action: nil, keyEquivalent: ""); empty.isEnabled = false; m.addItem(empty) }
                }
                it.submenu = sub
                items.append(it)
            } else {
                let ext = (name as NSString).pathExtension
                items.append(item(name, symbol: FileIcon.symbol(forExtension: ext), tint: FileIcon.tint(forExtension: ext),
                                  checked: e.url.standardizedFileURL == current?.standardizedFileURL) { [weak self] in self?.tab?.onOpenURL?(e.url) })
            }
        }
        if entries.count > Self.maxMenuEntries {
            let more = NSMenuItem(title: "… \(entries.count - Self.maxMenuEntries) more", action: nil, keyEquivalent: "")
            more.isEnabled = false
            items.append(more)
        }
        return items
    }

    func symbolItems(forNode node: Int) -> [NSMenuItem] {
        guard let outline, outline.nodes.indices.contains(node) else { return [] }
        return outline.siblings(of: node).prefix(Self.maxMenuEntries).map { i in
            let n = outline.nodes[i]
            return item(n.name, symbol: n.kind.iconName, checked: i == node) { [weak self] in self?.jump(to: n) }
        }
    }

    /// Puts the caret on the first character of the construct (so the chain at the caret includes it).
    func jump(to node: BreadcrumbNode) {
        guard let tv = tab?.textView else { return }
        let ns = tv.string as NSString
        var column = 1
        if node.range.location <= ns.length {
            column = node.range.location - ns.lineRange(for: NSRange(location: node.range.location, length: 0)).location + 1
        }
        tv.goToLine(node.line, column: column)
        tv.window?.makeFirstResponder(tv)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let lazy = menu as? LazyMenu, let populate = lazy.populate else { return }
        lazy.populate = nil
        populate(lazy)
    }

    /// Dropdown for a segment: siblings of a path component (the project root lists its own contents),
    /// siblings of a symbol, or (-1) the hidden middle segments each with their own dropdown.
    func menu(forSegment i: Int) -> NSMenu? {
        let menu = NSMenu()
        if i == -1 {
            for hidden in bar.collapsedIndices {
                let s = bar.segments[hidden]
                let it = item(s.title, symbol: bar.iconName(for: s), nil)
                if let sub = self.menu(forSegment: hidden) { it.submenu = sub }
                menu.addItem(it)
            }
            return menu.items.isEmpty ? nil : menu
        }
        guard bar.segments.indices.contains(i) else { return nil }
        let s = bar.segments[i]
        switch s.kind {
        case .symbol:
            guard let node = s.node else { return nil }
            symbolItems(forNode: node).forEach(menu.addItem)
        case .root:
            guard let url = s.url else { return nil }
            directoryItems(url, current: tab?.url).forEach(menu.addItem)
        case .folder, .file:
            guard let url = s.url else { return nil }
            directoryItems(url.deletingLastPathComponent(), current: url).forEach(menu.addItem)
        }
        return menu.items.isEmpty ? nil : menu
    }

    // MARK: Context menu / copy

    func path(forSegment i: Int) -> String? {
        guard bar.segments.indices.contains(i) else { return nil }
        return bar.segments[i].url?.path ?? tab?.url.path
    }

    func relativePath(forSegment i: Int) -> String? {
        guard let full = path(forSegment: i) else { return nil }
        guard let root = rootCache?.root?.path, full == root || full.hasPrefix(root + "/") else { return full }
        return full == root ? "." : String(full.dropFirst(root.count + 1))
    }

    func contextMenu(forSegment i: Int) -> NSMenu? {
        guard path(forSegment: i) != nil else { return nil }
        let menu = NSMenu()
        menu.addItem(item("Copy Path", symbol: "doc.on.doc") { [weak self] in self?.copy(self?.path(forSegment: i)) })
        menu.addItem(item("Copy Relative Path", symbol: "doc.on.doc") { [weak self] in self?.copy(self?.relativePath(forSegment: i)) })
        menu.addItem(item("Reveal in Finder", symbol: "folder") { [weak self] in
            if let p = self?.path(forSegment: i) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)]) }
        })
        return menu
    }

    private func copy(_ string: String?) {
        guard let string else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
