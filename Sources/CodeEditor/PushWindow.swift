import AppKit

/// What the Push Commits dialog decided.
struct PushRequest {
    var remote: String
    var target: String
    var setUpstream: Bool
    var tags: GitRepo.PushTags?
    var dontAskAgain: Bool
}

/// "Push Commits to <project>": the branch → remote : target line, the commits to send, the files they change as a folder
/// tree, and Push tags. Presented as a sheet; everything is loaded once and released with the window.
final class PushWindow: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private static var current: PushWindow?

    /// Shows the dialog over `parent` (modal if there is none). `done` gets nil on Cancel.
    static func present(over parent: NSWindow?, repo: GitRepo, preview: GitPushPreview, done: @escaping (PushRequest?) -> Void) {
        let w = PushWindow(repo: repo, preview: preview, done: done)
        current = w
        if let parent, parent.isVisible { parent.beginSheet(w.window) { _ in current = nil } }
        else { w.window.center(); NSApp.runModal(for: w.window); current = nil }
    }

    /// Verification (CE_PICKER=push): builds the dialog without showing it; `snapshotView` renders it.
    static func makeForSnapshot(repo: GitRepo, preview: GitPushPreview) { current = PushWindow(repo: repo, preview: preview) { _ in } }
    static var snapshotView: NSView? { current?.window.contentView }

    private let repo: GitRepo
    private let preview: GitPushPreview
    private let done: (PushRequest?) -> Void
    let window: NSWindow
    private let commitTable = NSTableView()
    private let fileOutline = NSOutlineView()
    private let targetField = NSTextField()
    private let tagsCheck = NSButton(checkboxWithTitle: "Push tags:", target: nil, action: nil)
    private let tagsMode = NSPopUpButton(frame: .zero, pullsDown: false)
    private let askCheck = NSButton(checkboxWithTitle: "Don't show this again", target: nil, action: nil)
    private let pushButton = NSButton(title: "Push", target: nil, action: nil)
    private let reader = DispatchQueue(label: "git.push-window", qos: .userInitiated)
    private var token = 0
    private var root: Node?

    private final class Node {
        let name: String
        var change: GitFileChange?
        var children: [Node] = []
        var fileCount = 0
        init(name: String, change: GitFileChange? = nil) { self.name = name; self.change = change }
        var isFolder: Bool { change == nil }
    }

    private init(repo: GitRepo, preview: GitPushPreview, done: @escaping (PushRequest?) -> Void) {
        self.repo = repo; self.preview = preview; self.done = done
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 480), styleMask: [.titled, .resizable],
                          backing: .buffered, defer: false)
        super.init()
        window.title = "Push Commits to \(repo.root.lastPathComponent)"
        window.minSize = NSSize(width: 620, height: 340)
        build()
        loadFiles(for: nil)
    }

    // MARK: build

    private func build() {
        let content = window.contentView!
        let remote = preview.remote ?? "origin"

        // header: branch → remote : target
        let branch = NSTextField(labelWithString: preview.branch)
        branch.font = .systemFont(ofSize: 13, weight: .semibold)
        let arrow = NSTextField(labelWithString: "→")
        let remoteLabel = NSTextField(labelWithString: remote)
        remoteLabel.textColor = .linkColor
        remoteLabel.font = .systemFont(ofSize: 13)
        let colon = NSTextField(labelWithString: ":")
        let existing = preview.upstream.flatMap { up -> String? in up.hasPrefix(remote + "/") ? String(up.dropFirst(remote.count + 1)) : nil }
        targetField.stringValue = existing ?? preview.branch
        targetField.font = .systemFont(ofSize: 13)
        targetField.bezelStyle = .roundedBezel
        targetField.toolTip = "Branch on \(remote) to push to"
        let newTag = NSTextField(labelWithString: preview.newBranch ? "new" : "")
        newTag.font = .systemFont(ofSize: 10, weight: .bold)
        newTag.textColor = .systemOrange
        let header = NSStackView(views: [branch, arrow, remoteLabel, colon, targetField, newTag])
        header.orientation = .horizontal
        header.spacing = 6
        header.alignment = .centerY
        header.edgeInsets = NSEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        targetField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // commits (left)
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c"))
        col.resizingMask = .autoresizingMask
        commitTable.addTableColumn(col)
        commitTable.headerView = nil
        commitTable.rowHeight = 24
        commitTable.dataSource = self
        commitTable.delegate = self
        commitTable.style = .plain
        commitTable.allowsEmptySelection = true
        let commitScroll = NSScrollView()
        commitScroll.documentView = commitTable
        commitScroll.hasVerticalScroller = true
        commitScroll.drawsBackground = false
        let title = NSTextField(labelWithString: "Push Commits to \(repo.root.lastPathComponent)")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        let titleRow = NSStackView(views: [title])
        titleRow.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 0, right: 14)
        let left = NSStackView(views: [titleRow, header, commitScroll])
        left.orientation = .vertical
        left.spacing = 0
        left.alignment = .leading
        header.widthAnchor.constraint(equalTo: left.widthAnchor).isActive = true
        commitScroll.widthAnchor.constraint(equalTo: left.widthAnchor).isActive = true

        // files (right)
        let fcol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("f"))
        fcol.resizingMask = .autoresizingMask
        fileOutline.addTableColumn(fcol)
        fileOutline.outlineTableColumn = fcol
        fileOutline.headerView = nil
        fileOutline.rowHeight = 22
        fileOutline.indentationPerLevel = 16
        fileOutline.dataSource = self
        fileOutline.delegate = self
        fileOutline.style = .plain
        let fileScroll = NSScrollView()
        fileScroll.documentView = fileOutline
        fileScroll.hasVerticalScroller = true
        fileScroll.drawsBackground = false

        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.addArrangedSubview(left)
        split.addArrangedSubview(fileScroll)
        split.setHoldingPriority(.init(260), forSubviewAt: 1)
        left.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        fileScroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true

        // bottom bar
        tagsMode.addItems(withTitles: ["All", "Current branch"])
        tagsMode.isEnabled = false
        tagsCheck.target = self; tagsCheck.action = #selector(tagsToggled)
        askCheck.font = .systemFont(ofSize: 11)
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancel.keyEquivalent = "\u{1b}"
        pushButton.target = self; pushButton.action = #selector(pushTapped)
        pushButton.keyEquivalent = "\r"
        pushButton.bezelStyle = .rounded
        pushButton.controlSize = .large
        cancel.controlSize = .large
        pushButton.isEnabled = !preview.commits.isEmpty || preview.newBranch
        let spacer = NSView()
        let bar = NSStackView(views: [tagsCheck, tagsMode, spacer, askCheck, cancel, pushButton])
        bar.orientation = .horizontal
        bar.spacing = 10
        bar.alignment = .centerY
        bar.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)

        let line = NSBox(); line.boxType = .separator
        for v in [split, line, bar] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(v) }
        NSLayoutConstraint.activate([
            split.topAnchor.constraint(equalTo: content.topAnchor), split.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            line.topAnchor.constraint(equalTo: split.bottomAnchor), line.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bar.topAnchor.constraint(equalTo: line.bottomAnchor), bar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor), bar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        window.defaultButtonCell = pushButton.cell as? NSButtonCell
        if preview.commits.isEmpty { return }
        commitTable.reloadData()
    }

    // MARK: actions

    @objc private func tagsToggled() { tagsMode.isEnabled = tagsCheck.state == .on }

    @objc private func cancelTapped() { finish(nil) }

    @objc private func pushTapped() {
        let remote = preview.remote ?? "origin"
        var target = targetField.stringValue.trimmingCharacters(in: .whitespaces)
        if target.isEmpty { target = preview.branch }
        let tags: GitRepo.PushTags? = tagsCheck.state == .on ? (tagsMode.indexOfSelectedItem == 0 ? .all : .followCurrent) : nil
        finish(PushRequest(remote: remote, target: target, setUpstream: preview.upstream != "\(remote)/\(target)", tags: tags,
                           dontAskAgain: askCheck.state == .on))
    }

    private func finish(_ request: PushRequest?) {
        if window.sheetParent != nil { window.sheetParent?.endSheet(window) } else { NSApp.stopModal(); window.orderOut(nil) }
        done(request)
    }

    // MARK: files

    private func loadFiles(for commit: GitCommit?) {
        token += 1
        let mine = token
        let repo = repo, preview = preview
        reader.async {
            let files = commit.map { (try? repo.commitFiles($0.hash)) ?? [] } ?? repo.pushChangedFiles(preview)
            DispatchQueue.main.async { [weak self] in
                guard let self, mine == self.token else { return }
                self.root = Self.buildTree(files)
                self.fileOutline.reloadData()
                self.fileOutline.expandItem(nil, expandChildren: true)
            }
        }
    }

    /// Folder tree with single-child folder chains merged ("js/Layouts/Includes") and file counts per folder.
    private static func buildTree(_ files: [GitFileChange]) -> Node {
        let top = Node(name: "")
        for f in files {
            var node = top
            let parts = f.path.split(separator: "/").map(String.init)
            for dir in parts.dropLast() {
                if let next = node.children.first(where: { $0.isFolder && $0.name == dir }) { node = next }
                else { let n = Node(name: dir); node.children.append(n); node = n }
            }
            node.children.append(Node(name: parts.last ?? f.path, change: f))
        }
        func finalize(_ n: Node) {
            n.children.forEach(finalize)
            n.fileCount = n.children.reduce(0) { $0 + ($1.isFolder ? $1.fileCount : 1) }
            n.children.sort { $0.isFolder != $1.isFolder ? $0.isFolder : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        finalize(top)
        func compress(_ n: Node) {
            for (i, c) in n.children.enumerated() where c.isFolder {
                var cur = c
                var name = c.name
                while cur.children.count == 1, let only = cur.children.first, only.isFolder { name += "/" + only.name; cur = only }
                let merged = Node(name: name); merged.children = cur.children; merged.fileCount = cur.fileCount
                n.children[i] = merged
                compress(merged)
            }
        }
        compress(top)
        let all = Node(name: "\(top.fileCount) file\(top.fileCount == 1 ? "" : "s")")
        all.children = top.children; all.fileCount = top.fileCount
        let wrapper = Node(name: "")
        wrapper.children = top.fileCount == 0 ? [] : [all]
        return wrapper
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { ((item as? Node) ?? root)?.children.count ?? 0 }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { ((item as? Node) ?? root!).children[index] }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { (item as! Node).isFolder }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let n = item as! Node
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = outlineView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView ?? {
            let c = NSTableCellView(); c.identifier = id
            let img = NSImageView(), text = NSTextField(labelWithString: "")
            img.translatesAutoresizingMaskIntoConstraints = false; text.translatesAutoresizingMaskIntoConstraints = false
            text.lineBreakMode = .byTruncatingMiddle
            c.addSubview(img); c.addSubview(text); c.imageView = img; c.textField = text
            NSLayoutConstraint.activate([
                img.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 2), img.centerYAnchor.constraint(equalTo: c.centerYAnchor),
                img.widthAnchor.constraint(equalToConstant: 16), img.heightAnchor.constraint(equalToConstant: 16),
                text.leadingAnchor.constraint(equalTo: img.trailingAnchor, constant: 5), text.trailingAnchor.constraint(equalTo: c.trailingAnchor),
                text.centerYAnchor.constraint(equalTo: c.centerYAnchor),
            ])
            return c
        }()
        cell.imageView?.image = FileIcon.treeImage(name: n.name, isDirectory: n.isFolder)
        if n.isFolder {
            let s = NSMutableAttributedString(string: n.name + "  ", attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor])
            if !n.name.hasSuffix(" files") && !n.name.hasSuffix(" file") {
                s.append(NSAttributedString(string: "\(n.fileCount) file\(n.fileCount == 1 ? "" : "s")",
                                            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]))
            } else { s.setAttributedString(NSAttributedString(string: n.name, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor])) }
            cell.textField?.attributedStringValue = s
        } else {
            let st = n.change?.status ?? "M"
            cell.textField?.stringValue = n.name
            cell.textField?.textColor = st == "A" ? .systemGreen : st == "D" ? .systemGray : .systemBlue
            cell.textField?.font = .systemFont(ofSize: 12)
        }
        return cell
    }

    // MARK: commits

    func numberOfRows(in tableView: NSTableView) -> Int { preview.commits.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("commit")
        let cell = tableView.makeView(withIdentifier: id, owner: nil) as? NSTextField ?? {
            let f = NSTextField(labelWithString: ""); f.identifier = id; f.lineBreakMode = .byTruncatingTail; return f
        }()
        let c = preview.commits[row]
        let s = NSMutableAttributedString(string: c.subject, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor])
        s.append(NSAttributedString(string: "   \(c.shortHash)", attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor]))
        cell.attributedStringValue = s
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let r = commitTable.selectedRow
        loadFiles(for: preview.commits.indices.contains(r) ? preview.commits[r] : nil)
    }
}
