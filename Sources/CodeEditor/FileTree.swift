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
            .filter { !ProjectIndex.treeHidden.contains($0.lastPathComponent) }
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

/// Outline view with PhpStorm-style keys: Return opens, Escape hands focus back to the editor,
/// Shift-F6 renames, Cmd-Backspace deletes, Cmd-N creates a file in the selected folder.
final class KeyOutlineView: NSOutlineView {
    var onReturn: (() -> Void)?
    var onEscape: (() -> Void)?
    var onRename: (() -> Void)?
    var onDelete: (() -> Void)?
    var onNewFile: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: onReturn?()          // return, enter
        case 53: onEscape?()              // escape
        default: super.keyDown(with: event)
        }
    }

    /// Menu key equivalents (Delete Line is Cmd-Backspace) would win over keyDown, so claim ours first.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.function, .numericPad, .capsLock])
        if flags == .command, event.keyCode == 51 { onDelete?(); return true }
        if flags == .command, event.charactersIgnoringModifiers == "n" { onNewFile?(); return true }
        if flags == .shift, event.keyCode == 97 { onRename?(); return true }
        return super.performKeyEquivalent(with: event)
    }
}

final class FileTreeController: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate, NSTextFieldDelegate {
    let scrollView = NSScrollView()
    let outline = KeyOutlineView()
    private var root: FileNode?
    private var statusKinds: [String: VCSKind] = [:]
    private var contextURL: URL?
    private var renameCancelled = false
    private var renamingURL: URL?
    var onOpen: ((URL) -> Void)?
    var onEscape: (() -> Void)?
    /// Reports every file-system change the tree made, after the tree itself refreshed.
    var onChange: ((FileChange) -> Void)?
    /// Asks whether existing files may be replaced; the default shows an alert (declines when headless).
    var confirmOverwrite: ([String]) -> Bool = { names in
        guard !AppEnv.headless else { return false }
        let alert = NSAlert()
        alert.messageText = names.count == 1 ? "“\(names[0])” already exists in the destination." : "\(names.count) items already exist in the destination."
        alert.informativeText = "Do you want to replace them?"
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    var rootURL: URL? { root?.url }

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
        outline.onRename = { [weak self] in self?.renameSelection() }
        outline.onDelete = { [weak self] in self?.trashSelection() }
        outline.onNewFile = { [weak self] in self?.newFile(in: self?.targetDirectory(for: self?.selectedURL)) }
        outline.registerForDraggedTypes([.fileURL])
        outline.setDraggingSourceOperationMask([.move, .copy], forLocal: true)
        outline.setDraggingSourceOperationMask(.copy, forLocal: false)
        outline.draggingDestinationFeedbackStyle = .regular
        let menu = NSMenu()
        menu.delegate = self
        outline.menu = menu
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
        expand(paths: expanded)
        if let selected { reveal(selected) }
    }

    func expandedPaths() -> [String] {
        var paths: [String] = []
        for row in 0..<outline.numberOfRows {
            if let node = outline.item(atRow: row) as? FileNode, outline.isItemExpanded(node) { paths.append(node.url.path) }
        }
        return paths
    }

    /// Expands the given folders (parents first); paths that no longer exist are skipped.
    func expand(paths: [String]) {
        for path in paths.sorted(by: { $0.count < $1.count }) {
            if let node = node(forPath: path), node.isDirectory { outline.expandItem(node) }
        }
    }

    var selectedURL: URL? { (outline.item(atRow: outline.selectedRow) as? FileNode)?.url }

    private func node(forPath path: String) -> FileNode? {
        guard let root else { return nil }
        // /var and /private/var name the same folder; children may report either spelling.
        let base = VCSKind.canonical(root.url.path), path = VCSKind.canonical(path)
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
    /// Folders take the strongest class inside: conflict > modified > added > untracked.
    func setStatus(_ map: [String: GitChange], repoRoot: URL) {
        statusKinds = VCSKind.kinds(for: map, repoRoot: repoRoot)
        outline.reloadData()
    }

    func statusKind(forPath path: String) -> VCSKind? { statusKinds[path] }

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

    // MARK: Context menu

    /// The tree's context menu for `url` (nil = empty area, i.e. the project root).
    func menuItems(for url: URL?) -> [NSMenuItem] {
        let isRoot = url == nil || url?.path == root?.url.path
        func make(_ title: String, _ action: Selector, enabled: Bool = true) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.isEnabled = enabled
            return item
        }
        return [
            make("New File…", #selector(menuNewFile)),
            make("New Folder…", #selector(menuNewFolder)),
            .separator(),
            make("Rename…", #selector(menuRename), enabled: !isRoot),
            make("Duplicate", #selector(menuDuplicate), enabled: !isRoot),
            make("Move to Trash…", #selector(menuTrash), enabled: !isRoot),
            .separator(),
            make("Reveal in Finder", #selector(menuReveal)),
            make("Copy Path", #selector(menuCopyPath)),
            make("Copy Relative Path", #selector(menuCopyRelativePath)),
            make("Open in Terminal", #selector(menuTerminal)),
            .separator(),
            make("Collapse All", #selector(menuCollapseAll)),
        ]
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let row = outline.clickedRow
        if row >= 0 { outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        contextURL = row >= 0 ? (outline.item(atRow: row) as? FileNode)?.url : nil
        menu.removeAllItems()
        menuItems(for: contextURL).forEach(menu.addItem)
    }

    private var menuURL: URL? { contextURL ?? root?.url }

    /// New items go into the folder itself, beside a file, or in the root.
    func targetDirectory(for url: URL?) -> URL? {
        guard let url else { return root?.url }
        return (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true ? url : url.deletingLastPathComponent()
    }

    @objc private func menuNewFile() { newFile(in: targetDirectory(for: contextURL)) }
    @objc private func menuNewFolder() { newFolder(in: targetDirectory(for: contextURL)) }
    @objc private func menuRename() { if let u = contextURL { beginRename(u) } }
    @objc private func menuDuplicate() { if let u = contextURL { duplicate(u) } }
    @objc private func menuTrash() { if let u = contextURL { trash(u) } }
    @objc private func menuReveal() { if let u = menuURL { NSWorkspace.shared.activateFileViewerSelecting([u]) } }
    @objc private func menuCollapseAll() { collapseAll() }

    @objc private func menuCopyPath() {
        guard let u = menuURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(u.path, forType: .string)
    }

    @objc private func menuCopyRelativePath() {
        guard let u = menuURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(FileOperations.relativePath(u, to: root?.url), forType: .string)
    }

    @objc private func menuTerminal() {
        guard let u = menuURL, let dir = targetDirectory(for: u) else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-a", "Terminal", dir.path]
        try? p.run()
    }

    // MARK: Operations (UI wrappers around FileOperations)

    private func alert(_ error: Error) {
        guard !AppEnv.headless else { return }
        NSAlert(error: error).runModal()
    }

    private func promptForName(title: String, initial: String = "") -> String? {
        guard !AppEnv.headless else { return nil }
        let alert = NSAlert()
        alert.messageText = title
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = initial
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    func newFile(in dir: URL?) {
        guard let dir, let name = promptForName(title: "New File") else { return }
        perform { let url = try FileOperations.createFile(named: name, in: dir); return .created(url) }
        if let url = selectedURL, url.lastPathComponent == name { onOpen?(url) }
    }

    func newFolder(in dir: URL?) {
        guard let dir, let name = promptForName(title: "New Folder") else { return }
        perform { let url = try FileOperations.createFolder(named: name, in: dir); return .created(url) }
    }

    func duplicate(_ url: URL) {
        perform { .created(try FileOperations.duplicate(url)) }
    }

    func trash(_ url: URL) {
        guard !AppEnv.headless else { return }
        let alert = NSAlert()
        alert.messageText = "Move “\(url.lastPathComponent)” to the Trash?"
        alert.informativeText = "You can restore it from the Trash."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        perform { try FileOperations.trash(url); return .deleted(url) }
    }

    private func trashSelection() { if let u = selectedURL, u.path != root?.url.path { trash(u) } }
    private func renameSelection() { if let u = selectedURL, u.path != root?.url.path { beginRename(u) } }

    private func perform(_ op: () throws -> FileChange) {
        do {
            let change = try op()
            refresh()
            if case .created(let url) = change { reveal(url) }
            onChange?(change)
        } catch {
            alert(error)
        }
    }

    // MARK: Inline rename

    func beginRename(_ url: URL) {
        reveal(url)
        let row = outline.selectedRow
        guard row >= 0, let cell = outline.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView,
              let field = cell.textField else { return }
        renamingURL = url
        renameCancelled = false
        field.isEditable = true
        field.delegate = self
        outline.window?.makeFirstResponder(field)
        let stem = (url.deletingPathExtension().lastPathComponent as NSString).length
        field.currentEditor()?.selectedRange = NSRange(location: 0, length: url.hasDirectoryPath || stem == 0 ? (field.stringValue as NSString).length : stem)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            renameCancelled = true
            control.abortEditing()
            outline.window?.makeFirstResponder(outline)
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, let url = renamingURL else { return }
        renamingURL = nil
        field.isEditable = false
        let newName = field.stringValue.trimmingCharacters(in: .whitespaces)
        field.stringValue = url.lastPathComponent
        guard !renameCancelled, newName != url.lastPathComponent else { return }
        perform {
            let dest = try FileOperations.rename(url, to: newName)
            return .moved(from: url, to: dest)
        }
    }

    // MARK: Drag and drop

    /// Moves (internal drags) or copies (from Finder) `urls` into `dir`, asking before replacing anything.
    /// Returns the changes made; already-in-place items and refusals are skipped.
    @discardableResult
    func performDrop(urls: [URL], into dir: URL, move: Bool) -> [FileChange] {
        let clashes = urls.filter {
            let dest = dir.appendingPathComponent($0.lastPathComponent)
            return dest.path != $0.path && FileManager.default.fileExists(atPath: dest.path)
        }
        var overwrite = false
        if !clashes.isEmpty {
            guard confirmOverwrite(clashes.map(\.lastPathComponent)) else { return [] }
            overwrite = true
        }
        var changes: [FileChange] = []
        for url in urls {
            do {
                if move {
                    let dest = try FileOperations.move(url, toDirectory: dir, overwrite: overwrite)
                    if dest.path != url.path { changes.append(.moved(from: url, to: dest)) }
                } else {
                    changes.append(.created(try FileOperations.copy(url, toDirectory: dir, overwrite: overwrite)))
                }
            } catch {
                alert(error)
            }
        }
        if !changes.isEmpty {
            refresh()
            changes.forEach { onChange?($0) }
        }
        return changes
    }

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        (item as? FileNode)?.url as NSURL?
    }

    private func droppedURLs(_ info: NSDraggingInfo) -> [URL] {
        (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?,
                     proposedChildIndex index: Int) -> NSDragOperation {
        let urls = droppedURLs(info)
        guard !urls.isEmpty, let root else { return [] }
        var target = (item as? FileNode) ?? root
        if !target.isDirectory {
            // Dropping on a file means "into its folder".
            guard let parent = node(forPath: target.url.deletingLastPathComponent().path) else { return [] }
            target = parent
        }
        let internalDrag = info.draggingSource as? NSOutlineView === outline
        for url in urls {
            if FileOperations.isInside(target.url, of: url) { return [] }
            if internalDrag, url.deletingLastPathComponent().path == target.url.path { return [] }
        }
        outlineView.setDropItem(target === root ? nil : target, dropChildIndex: NSOutlineViewDropOnItemIndex)
        return internalDrag ? .move : .copy
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        guard let dir = (item as? FileNode)?.url ?? root?.url else { return false }
        let internalDrag = info.draggingSource as? NSOutlineView === outline
        return !performDrop(urls: droppedURLs(info), into: dir, move: internalDrag).isEmpty
    }

    // MARK: Data source

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
        cell.textField?.isEditable = false
        cell.textField?.textColor = statusKinds[node.url.path]?.color ?? .labelColor
        cell.imageView?.image = NSImage(systemSymbolName: node.isDirectory ? "folder.fill" : FileIcon.symbol(forExtension: ext),
                                        accessibilityDescription: nil)
        cell.imageView?.contentTintColor = node.isDirectory ? .systemBlue : FileIcon.tint(forExtension: ext)
        return cell
    }
}
