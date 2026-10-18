import AppKit

final class FileNode {
    let url: URL
    let isDirectory: Bool
    private var loaded: [FileNode]?
    init(url: URL) {
        self.url = url
        isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    /// Children are read lazily on first expand, so large repos cost nothing until opened.
    var children: [FileNode] {
        if let loaded { return loaded }
        let items = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        let nodes = items
            .filter { !ProjectIndex.skipNames.contains($0.lastPathComponent) }
            .map(FileNode.init)
            .sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
            }
        loaded = nodes
        return nodes
    }

    func child(named name: String) -> FileNode? { children.first { $0.url.lastPathComponent == name } }
}

/// Outline view with PhpStorm-style keys: Return opens, Escape hands focus back to the editor.
final class KeyOutlineView: NSOutlineView {
    var onReturn: (() -> Void)?
    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: onReturn?()          // return, enter
        case 53: onEscape?()              // escape
        default: super.keyDown(with: event)
        }
    }
}

final class FileTreeController: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    let scrollView = NSScrollView()
    let outline = KeyOutlineView()
    private var root: FileNode?
    private var statusColors: [String: NSColor] = [:]
    var onOpen: ((URL) -> Void)?
    var onEscape: (() -> Void)?

    override init() {
        super.init()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.rowSizeStyle = .small
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.action = #selector(clicked)
        outline.onReturn = { [weak self] in self?.activateSelection() }
        outline.onEscape = { [weak self] in self?.onEscape?() }
        scrollView.documentView = outline
        scrollView.hasVerticalScroller = true
    }

    func setRoot(_ url: URL) {
        root = FileNode(url: url)
        outline.reloadData()
        outline.expandItem(nil)
    }

    /// Rebuilds the tree after files changed on disk, keeping expansion and selection.
    func refresh() {
        guard let rootURL = root?.url else { return }
        let expanded = expandedPaths()
        let selected = selectedURL
        root = FileNode(url: rootURL)
        outline.reloadData()
        for path in expanded.sorted(by: { $0.count < $1.count }) {
            if let node = node(forPath: path) { outline.expandItem(node) }
        }
        if let selected { reveal(selected) }
    }

    private func expandedPaths() -> [String] {
        var paths: [String] = []
        for row in 0..<outline.numberOfRows {
            if let node = outline.item(atRow: row) as? FileNode, outline.isItemExpanded(node) { paths.append(node.url.path) }
        }
        return paths
    }

    private var selectedURL: URL? { (outline.item(atRow: outline.selectedRow) as? FileNode)?.url }

    private func node(forPath path: String) -> FileNode? {
        guard let root else { return nil }
        let base = root.url.path
        if path == base { return root }
        guard path.hasPrefix(base + "/") else { return nil }
        var node = root
        for part in path.dropFirst(base.count + 1).split(separator: "/") {
            guard let next = node.child(named: String(part)) else { return nil }
            node = next
        }
        return node
    }

    /// Expands the ancestors of `url` and selects it.
    func reveal(_ url: URL) {
        guard let root else { return }
        let base = root.url.path
        guard url.path.hasPrefix(base + "/") else { return }
        var node = root
        for part in url.path.dropFirst(base.count + 1).split(separator: "/") {
            outline.expandItem(node)
            guard let next = node.child(named: String(part)) else { return }
            node = next
        }
        let row = outline.row(forItem: node)
        guard row >= 0 else { return }
        outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        outline.scrollRowToVisible(row)
    }

    func collapseAll() {
        guard let root else { return }
        for node in root.children where node.isDirectory { outline.collapseItem(node, collapseChildren: true) }
    }

    /// Colours changed files (and the folders containing them) by Git status.
    func setStatus(_ map: [String: GitChange], repoRoot: URL) {
        var colors: [String: NSColor] = [:]
        for (rel, change) in map {
            let color: NSColor
            if change.isConflict { color = .systemRed }
            else if change.isUntracked { color = .systemBrown }
            else if change.index == "A" { color = .systemGreen }
            else if change.index == "D" || change.work == "D" { continue }
            else { color = .systemBlue }
            var path = repoRoot.appendingPathComponent(rel).path
            colors[path] = color
            while let slash = path.lastIndex(of: "/"), path.count > repoRoot.path.count {
                path = String(path[..<slash])
                if colors[path] == nil { colors[path] = color }
            }
        }
        statusColors = colors
        outline.reloadData()
    }

    private func activateSelection() {
        guard let node = outline.item(atRow: outline.selectedRow) as? FileNode else { return }
        open(node)
    }

    @objc private func clicked() {
        guard let node = outline.item(atRow: outline.clickedRow) as? FileNode else { return }
        open(node)
    }

    private func open(_ node: FileNode) {
        if node.isDirectory {
            if outline.isItemExpanded(node) { outline.collapseItem(node) } else { outline.expandItem(node) }
        } else {
            onOpen?(node.url)
        }
    }

    func outlineView(_ o: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        ((item as? FileNode) ?? root)?.children.count ?? 0
    }
    func outlineView(_ o: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        ((item as? FileNode) ?? root!).children[index]
    }
    func outlineView(_ o: NSOutlineView, isItemExpandable item: Any) -> Bool { (item as! FileNode).isDirectory }

    func outlineView(_ o: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let node = item as! FileNode
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = o.makeView(withIdentifier: id, owner: nil) as? NSTableCellView ?? {
            let c = NSTableCellView()
            c.identifier = id
            let img = NSImageView(), text = NSTextField(labelWithString: "")
            img.translatesAutoresizingMaskIntoConstraints = false
            text.translatesAutoresizingMaskIntoConstraints = false
            text.lineBreakMode = .byTruncatingMiddle
            c.addSubview(img); c.addSubview(text)
            c.imageView = img; c.textField = text
            NSLayoutConstraint.activate([
                img.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 2),
                img.centerYAnchor.constraint(equalTo: c.centerYAnchor),
                img.widthAnchor.constraint(equalToConstant: 16), img.heightAnchor.constraint(equalToConstant: 16),
                text.leadingAnchor.constraint(equalTo: img.trailingAnchor, constant: 4),
                text.trailingAnchor.constraint(equalTo: c.trailingAnchor),
                text.centerYAnchor.constraint(equalTo: c.centerYAnchor),
            ])
            return c
        }()
        let ext = node.url.pathExtension
        cell.textField?.stringValue = node.url.lastPathComponent
        cell.textField?.textColor = statusColors[node.url.path] ?? .labelColor
        cell.imageView?.image = NSImage(systemSymbolName: node.isDirectory ? "folder.fill" : FileIcon.symbol(forExtension: ext),
                                        accessibilityDescription: nil)
        cell.imageView?.contentTintColor = node.isDirectory ? .systemBlue : FileIcon.tint(forExtension: ext)
        return cell
    }
}
