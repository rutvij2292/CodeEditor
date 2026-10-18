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
            .filter { !["node_modules", ".git", ".DS_Store", "vendor", ".build"].contains($0.lastPathComponent) }
            .map(FileNode.init)
            .sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
            }
        loaded = nodes
        return nodes
    }
}

final class FileTreeController: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    let scrollView = NSScrollView()
    let outline = NSOutlineView()
    private var root: FileNode?
    var onOpen: ((URL) -> Void)?

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
        scrollView.documentView = outline
        scrollView.hasVerticalScroller = true
    }

    func setRoot(_ url: URL) {
        root = FileNode(url: url)
        outline.reloadData()
        outline.expandItem(nil)
    }

    @objc private func clicked() {
        guard let node = outline.item(atRow: outline.clickedRow) as? FileNode else { return }
        if node.isDirectory {
            if outline.isItemExpanded(node) { outline.collapseItem(node) } else { outline.expandItem(node) }
        } else {
            onOpen?(node.url)
        }
    }

    func outlineView(_ o: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = (item as? FileNode) ?? root else { return 0 }
        return node === root && item == nil ? node.children.count : node.children.count
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
        cell.textField?.stringValue = node.url.lastPathComponent
        cell.imageView?.image = NSImage(systemSymbolName: node.isDirectory ? "folder" : "doc.text", accessibilityDescription: nil)
        return cell
    }
}
