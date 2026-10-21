import AppKit

final class FileNode {
    let url: URL
    let isDirectory: Bool
    private var loaded: [FileNode]?
    init(url: URL) {
        self.url = url
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        if values?.isSymbolicLink == true {      // a symlink to a folder is a folder (also the project root itself)
            isDirectory = (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        } else {
            isDirectory = values?.isDirectory ?? false
        }
    }

    /// Children are read lazily on first expand, so large repos cost nothing until opened.
    var children: [FileNode] {
        if let loaded { return loaded }
        let items = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        // Sort keys computed once (lowercased UTF-8) and compared with a byte-level natural order: String comparison with
        // options / localizedStandardCompare inside the comparator cost 100+ ms for a 2k-file folder.
        var entries: [(node: FileNode, name: String, key: [UInt8], ascii: Bool)] = []
        entries.reserveCapacity(items.count)
        for item in items {
            let name = item.lastPathComponent
            if ProjectIndex.treeHidden.contains(name) { continue }
            let key = Array(name.lowercased().utf8)
            entries.append((FileNode(url: item), name, key, !key.contains { $0 >= 128 }))
        }
        entries.sort {
            if $0.node.isDirectory != $1.node.isDirectory { return $0.node.isDirectory }
            if $0.ascii && $1.ascii { return FileNode.naturalLess($0.key, $1.key) }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        let nodes = entries.map(\.node)
        loaded = nodes
        return nodes
    }

    /// Finder-like order on lowercased ASCII bytes: digit runs compare by value ("file2" < "file10").
    static func naturalLess(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        var i = 0, j = 0
        while i < a.count, j < b.count {
            let x = a[i], y = b[j]
            let xd = x >= 48 && x <= 57, yd = y >= 48 && y <= 57
            if xd && yd {
                var i2 = i, j2 = j
                while i2 < a.count, a[i2] == 48 { i2 += 1 }
                while j2 < b.count, b[j2] == 48 { j2 += 1 }
                var ie = i2, je = j2
                while ie < a.count, a[ie] >= 48, a[ie] <= 57 { ie += 1 }
                while je < b.count, b[je] >= 48, b[je] <= 57 { je += 1 }
                if ie - i2 != je - j2 { return ie - i2 < je - j2 }
                var k = 0
                while k < ie - i2 {
                    if a[i2 + k] != b[j2 + k] { return a[i2 + k] < b[j2 + k] }
                    k += 1
                }
                i = ie; j = je
                continue
            }
            if x != y { return x < y }
            i += 1; j += 1
        }
        return a.count - i < b.count - j
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
    var onCopy: (() -> Void)?
    var onCut: (() -> Void)?
    var onPaste: (() -> Void)?
    /// Typing a letter starts a speed search over the loaded rows (PhpStorm), instead of AppKit's invisible prefix type-select.
    var speedSearch: SpeedSearch?
    private var hoveredRow = -1

    /// The tree draws its own chevrons; clicking a folder row toggles it (FileTreeController.clicked).
    override func frameOfOutlineCell(atRow row: Int) -> NSRect { .zero }

    /// With the system triangle gone AppKit still reserves its column; place cells at exactly level × indent instead.
    override func frameOfCell(atColumn column: Int, row: Int) -> NSRect {
        var f = super.frameOfCell(atColumn: column, row: row)
        guard column == 0, row >= 0 else { return f }
        let x = TreeStyle.indent * CGFloat(max(0, level(forRow: row)))
        f.size.width += f.origin.x - x
        f.origin.x = x
        return f
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    private func setHover(_ row: Int) {
        guard row != hoveredRow else { return }
        if hoveredRow >= 0, let v = rowView(atRow: hoveredRow, makeIfNecessary: false) as? TreeRowView { v.isHovered = false }
        hoveredRow = row
        if row >= 0, let v = rowView(atRow: row, makeIfNecessary: false) as? TreeRowView { v.isHovered = true }
    }
    override func mouseMoved(with event: NSEvent) { setHover(row(at: convert(event.locationInWindow, from: nil))) }
    override func mouseExited(with event: NSEvent) { setHover(-1) }
    override func reloadData() { hoveredRow = -1; super.reloadData() }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: onReturn?()          // return, enter
        case 53: onEscape?()              // escape
        default:
            if speedSearch?.handleKeyDown(event) == true { return }
            super.keyDown(with: event)
        }
    }

    /// Menu key equivalents (Delete Line is Cmd-Backspace) would win over keyDown, so claim ours first.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.function, .numericPad, .capsLock])
        if flags == .command, event.keyCode == 51 { onDelete?(); return true }
        if flags == .command, event.charactersIgnoringModifiers == "n" { onNewFile?(); return true }
        if flags == .command, event.charactersIgnoringModifiers == "c" { onCopy?(); return true }
        if flags == .command, event.charactersIgnoringModifiers == "x" { onCut?(); return true }
        if flags == .command, event.charactersIgnoringModifiers == "v" { onPaste?(); return true }
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
    /// Typed query nothing in the loaded tree matched: the window widens it to Go to File.
    var onSearchEverywhere: ((String) -> Void)?
    /// "Open in Terminal": the window opens a tab of its own terminal in that folder (Terminal.app only when this is unset).
    var onOpenTerminal: ((URL) -> Void)?
    let speed = SpeedSearch()
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

    /// Asks before moving items to the Trash; the default shows an alert (declines when headless).
    var confirmTrash: ([URL]) -> Bool = { urls in
        guard !AppEnv.headless else { return false }
        let alert = NSAlert()
        alert.messageText = urls.count == 1 ? "Move “\(urls[0].lastPathComponent)” to the Trash?" : "Move \(urls.count) items to the Trash?"
        alert.informativeText = "You can restore \(urls.count == 1 ? "it" : "them") from the Trash."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    var rootURL: URL? { root?.url }
    /// Sidebar container: Explorer header + this tree.
    private(set) lazy var panel = FileTreePanel(tree: self)

    @objc func panelNewFile() { newFile(in: targetDirectory(for: selectedURL)) }
    @objc func panelNewFolder() { newFolder(in: targetDirectory(for: selectedURL)) }
    @objc func panelCollapseAll() { collapseAll() }
    /// Header Refresh button / context menu: rescans the whole project (tree, index, Git colours), same as Cmd-Opt-Y.
    var onReload: (() -> Void)?
    @objc func panelReload() { if let onReload { onReload() } else { refresh() } }

    override init() {
        super.init()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.rowSizeStyle = .custom
        outline.rowHeight = TreeStyle.rowHeight
        outline.intercellSpacing = .zero
        outline.indentationPerLevel = TreeStyle.indent
        outline.style = .plain
        outline.backgroundColor = .clear
        outline.selectionHighlightStyle = .regular
        column.resizingMask = .autoresizingMask
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.action = #selector(clicked)
        outline.onReturn = { [weak self] in self?.activateSelection() }
        outline.onEscape = { [weak self] in self?.onEscape?() }
        outline.onRename = { [weak self] in self?.renameSelection() }
        outline.onDelete = { [weak self] in self?.trashSelection() }
        outline.onCopy = { [weak self] in self?.copySelection(cut: false) }
        outline.onCut = { [weak self] in self?.copySelection(cut: true) }
        outline.onPaste = { [weak self] in self?.paste(into: self?.targetDirectory(for: self?.selectedURL)) }
        outline.onNewFile = { [weak self] in self?.newFile(in: self?.targetDirectory(for: self?.selectedURL)) }
        speed.attach(to: outline) { [weak self] row in (self?.outline.item(atRow: row) as? FileNode)?.url.lastPathComponent }
        speed.onReturn = { [weak self] in self?.activateSelection() }
        speed.onSearchEverywhere = { [weak self] q in self?.onSearchEverywhere?(q) }
        outline.speedSearch = speed
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

    /// Refreshes only when a changed path lives directly in the root or in an expanded folder: events inside collapsed
    /// folders (build output, caches, other branches' files) cost nothing.
    func refreshIfAffected(_ paths: Set<String>) {
        guard let rootURL = root?.url else { return }
        // FSEvents reports real paths; the project may be opened through a symlink (or a firmlink), so compare resolved paths.
        func real(_ p: String) -> String { URL(fileURLWithPath: p).resolvingSymlinksInPath().path }
        let base = real(rootURL.path)
        let expanded = Set(expandedPaths().map(real))
        let affected = paths.contains { p in
            let parent = (p as NSString).deletingLastPathComponent
            let r = real(parent)
            // Not under the project at all after resolving (odd mounts): refresh rather than risk a stale tree.
            return r == base || expanded.contains(r) || !(r + "/").hasPrefix(base + "/")
                || !FileManager.default.fileExists(atPath: parent)   // the whole folder vanished
        }
        if affected { refresh() }
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
        let mods = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
        guard mods.isDisjoint(with: [.shift, .command]), outline.selectedRowIndexes.count <= 1 else { return }
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
            make("Cut", #selector(menuCut), enabled: !isRoot),
            make("Copy", #selector(menuCopy), enabled: !isRoot),
            make("Paste", #selector(menuPaste), enabled: !pasteboardURLs().isEmpty),
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
            make("Reload from Disk", #selector(panelReload)),
            make("Collapse All", #selector(menuCollapseAll)),
        ]
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let row = outline.clickedRow
        if row >= 0, !outline.selectedRowIndexes.contains(row) { outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
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
    @objc private func menuCut() { copySelection(cut: true) }
    @objc private func menuCopy() { copySelection(cut: false) }
    @objc private func menuPaste() { paste(into: targetDirectory(for: contextURL)) }
    @objc private func menuRename() { if let u = contextURL { beginRename(u) } }
    @objc private func menuDuplicate() { if let u = contextURL { duplicate(u) } }
    @objc private func menuTrash() {
        let chosen = selectedURLs
        if chosen.count > 1, let u = contextURL, chosen.contains(u) { trash(chosen) } else if let u = contextURL { trash(u) }
    }
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
        if let embedded = onOpenTerminal { embedded(dir); return }
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

    func trash(_ url: URL) { trash([url]) }

    /// Moves every URL to the Trash after one confirmation; items inside another selected folder go with it.
    func trash(_ urls: [URL]) {
        let urls = urls.filter { u in !urls.contains { $0.path != u.path && FileOperations.isInside(u, of: $0) } }
        guard !urls.isEmpty, confirmTrash(urls) else { return }
        var changes: [FileChange] = []
        for url in urls {
            do { try FileOperations.trash(url); changes.append(.deleted(url)) } catch { self.alert(error) }
        }
        guard !changes.isEmpty else { return }
        refresh()
        changes.forEach { onChange?($0) }
    }

    private func trashSelection() { trash(selectedURLs) }
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

    // MARK: Copy / cut / paste

    /// Files cut with Cmd-X; the next paste moves them (and clears this).
    private var cutURLs: [URL] = []

    var selectedURLs: [URL] {
        outline.selectedRowIndexes.compactMap { (outline.item(atRow: $0) as? FileNode)?.url }.filter { $0.path != root?.url.path }
    }

    private func pasteboardURLs() -> [URL] {
        (NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    /// Puts the selected files on the pasteboard as file URLs, so they paste here, into Finder and into other apps.
    func copySelection(cut: Bool) {
        let chosen = selectedURLs
        guard !chosen.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(chosen as [NSURL])
        pb.addTypes([.string], owner: nil)
        pb.setString(chosen.map(\.path).joined(separator: "\n"), forType: .string)
        cutURLs = cut ? chosen : []
    }

    /// Copies (or, after Cut, moves) the pasteboard's files into `dir`. Pasting a copy beside its original makes
    /// "name copy.ext"; a name clash elsewhere asks before replacing.
    func paste(into dir: URL?) {
        guard let dir else { return }
        let urls = pasteboardURLs().filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { return }
        let isCut = !cutURLs.isEmpty && Set(cutURLs.map(\.path)) == Set(urls.map(\.path))
        if isCut {
            performDrop(urls: urls, into: dir, move: true)
            cutURLs = []
            NSPasteboard.general.clearContents()
            return
        }
        var rest: [URL] = []
        var changes: [FileChange] = []
        for url in urls {
            if url.deletingLastPathComponent().standardizedFileURL.path == dir.standardizedFileURL.path {
                do {
                    let dest = FileOperations.copyName(for: url, in: dir)
                    try FileManager.default.copyItem(at: url, to: dest)
                    changes.append(.created(dest))
                } catch { alert(error) }
            } else { rest.append(url) }
        }
        if !changes.isEmpty { refresh(); changes.forEach { onChange?($0) }; if let u = changes.last, case .created(let url) = u { reveal(url) } }
        if !rest.isEmpty { performDrop(urls: rest, into: dir, move: false) }
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

    func outlineView(_ o: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        let id = NSUserInterfaceItemIdentifier("treeRow")
        let row = o.makeView(withIdentifier: id, owner: nil) as? TreeRowView ?? { let r = TreeRowView(); r.identifier = id; return r }()
        row.level = max(0, o.level(forItem: item))
        row.isHovered = false
        return row
    }

    func outlineViewItemDidExpand(_ notification: Notification) { setChevron(notification, expanded: true) }
    func outlineViewItemDidCollapse(_ notification: Notification) { setChevron(notification, expanded: false) }

    private func setChevron(_ notification: Notification, expanded: Bool) {
        guard let node = notification.userInfo?["NSObject"] as? FileNode else { return }
        let row = outline.row(forItem: node)
        guard row >= 0, let cell = outline.view(atColumn: 0, row: row, makeIfNecessary: false) as? TreeCellView else { return }
        cell.chevron.expanded = expanded
        cell.imageView?.image = FileIcon.treeImage(name: node.url.lastPathComponent, isDirectory: true, expanded: expanded)
    }

    func outlineView(_ o: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let node = item as! FileNode
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = o.makeView(withIdentifier: id, owner: nil) as? TreeCellView ?? { let c = TreeCellView(); c.identifier = id; return c }()
        let name = node.url.lastPathComponent
        let color = statusKinds[node.url.path]?.color ?? TreeStyle.foreground
        let hits = speed.matchedIndices(in: name)
        var attributed: NSAttributedString?
        if !hits.isEmpty {
            let s = NSMutableAttributedString(string: name, attributes: [.font: TreeStyle.font, .foregroundColor: color])
            let bold = NSFont.systemFont(ofSize: TreeStyle.font.pointSize, weight: .bold)
            let len = name.utf16.count
            for i in hits where i < len {
                s.addAttributes([.font: bold, .foregroundColor: NSColor.controlAccentColor], range: NSRange(location: i, length: 1))
            }
            attributed = s
        }
        cell.textField?.isEditable = false
        let expanded = node.isDirectory && o.isItemExpanded(node)
        cell.configure(name: name, color: color, italic: node.isDirectory && name.hasPrefix("."), attributed: attributed)
        cell.chevron.visible = node.isDirectory
        cell.chevron.expanded = expanded
        cell.imageView?.image = FileIcon.treeImage(name: name, isDirectory: node.isDirectory, expanded: expanded)
        cell.imageView?.contentTintColor = nil
        return cell
    }
}
