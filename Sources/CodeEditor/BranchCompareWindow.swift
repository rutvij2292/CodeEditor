import AppKit

/// "Compare with Current": commits on either side and the changed files; selecting a file shows the side-by-side diff
/// (reuses SideBySideDiffView).
final class BranchCompareWindow: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private enum CommitRow { case header(String); case commit(GitCommit) }

    let window: NSWindow
    private let repo: GitRepo
    private let cmp: BranchComparison
    private let current: String
    private let workingTree: Bool
    private var commitRows: [CommitRow] = []
    private let commitTable = NSTableView()
    private let fileTable = NSTableView()
    private let diff = SideBySideDiffView(frame: NSRect(x: 0, y: 0, width: 640, height: 600))
    private let hint = NSTextField(labelWithString: "Select a file to see the diff")

    init(repo: GitRepo, comparison: BranchComparison, current: String, workingTree: Bool = false) {
        self.workingTree = workingTree
        self.repo = repo
        self.cmp = comparison
        self.current = current
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 700), styleMask: [.titled, .closable, .resizable],
                          backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        DialogMemory.remember(window, as: "BranchCompare")
        window.title = workingTree ? "“\(comparison.other)” vs Working Tree" : "Compare “\(comparison.other)” with “\(current)”"
        if !workingTree { commitRows.append(.header("In \(comparison.other), not in \(current)  (\(comparison.onlyInOther.count))"))
        commitRows += comparison.onlyInOther.map { .commit($0) }
        commitRows.append(.header("In \(current), not in \(comparison.other)  (\(comparison.onlyInCurrent.count))"))
        commitRows += comparison.onlyInCurrent.map { .commit($0) } }

        func configure(_ t: NSTableView, _ id: String) {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            t.addTableColumn(col)
            t.headerView = nil
            t.rowHeight = 20
            t.dataSource = self
            t.delegate = self
            t.style = .plain
        }
        configure(commitTable, "commits"); configure(fileTable, "files")
        fileTable.target = self
        fileTable.action = #selector(fileSelected)
        func scroll(_ t: NSTableView, _ title: String) -> NSView {
            let sv = NSScrollView(); sv.documentView = t; sv.hasVerticalScroller = true; sv.drawsBackground = false
            let l = NSTextField(labelWithString: title)
            l.font = .systemFont(ofSize: 11, weight: .semibold); l.textColor = .secondaryLabelColor
            let box = NSStackView(views: [l, sv])
            box.orientation = .vertical; box.alignment = .leading; box.spacing = 4
            box.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 0, right: 0)
            sv.translatesAutoresizingMaskIntoConstraints = false
            sv.widthAnchor.constraint(equalTo: box.widthAnchor, constant: -8).isActive = true
            return box
        }
        let left = NSSplitView()
        left.isVertical = false
        left.dividerStyle = .thin
        left.addArrangedSubview(scroll(commitTable, "Commits"))
        left.addArrangedSubview(scroll(fileTable, "Changed files (\(comparison.files.count))"))
        let right = NSView()
        diff.translatesAutoresizingMaskIntoConstraints = false
        hint.textColor = .secondaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false
        right.addSubview(diff); right.addSubview(hint)
        NSLayoutConstraint.activate([
            diff.leadingAnchor.constraint(equalTo: right.leadingAnchor), diff.trailingAnchor.constraint(equalTo: right.trailingAnchor),
            diff.topAnchor.constraint(equalTo: right.topAnchor), diff.bottomAnchor.constraint(equalTo: right.bottomAnchor),
            hint.centerXAnchor.constraint(equalTo: right.centerXAnchor), hint.centerYAnchor.constraint(equalTo: right.centerYAnchor),
        ])
        diff.isHidden = true
        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.addArrangedSubview(left)
        split.addArrangedSubview(right)
        window.contentView = split
        left.widthAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true
        commitTable.reloadData(); fileTable.reloadData()
        DispatchQueue.main.async { split.setPosition(400, ofDividerAt: 0); left.setPosition(280, ofDividerAt: 0) }
    }

    func show() { window.makeKeyAndOrderFront(nil) }

    @objc private func fileSelected() {
        let r = fileTable.selectedRow
        guard r >= 0, r < cmp.files.count else { return }
        let f = cmp.files[r]
        let repo = self.repo, other = cmp.other
        DispatchQueue.global(qos: .userInitiated).async {
            let wt = self.workingTree
            let old = wt ? ((try? repo.content(of: f.oldPath ?? f.path, at: other)) ?? nil) : ((try? repo.content(of: f.oldPath ?? f.path, at: "HEAD")) ?? nil)
            let new = wt ? (try? String(contentsOf: repo.root.appendingPathComponent(f.path), encoding: .utf8)) : ((try? repo.content(of: f.path, at: other)) ?? nil)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.hint.isHidden = true
                self.diff.isHidden = false
                self.diff.show(old: old ?? "", new: new ?? "", oldTitle: self.workingTree ? other : self.current, newTitle: self.workingTree ? "Working Tree" : other,
                               fileExtension: (f.path as NSString).pathExtension)
            }
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { tableView === commitTable ? commitRows.count : cmp.files.count }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if tableView === commitTable, case .header = commitRows[row] { return false }
        return true
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byTruncatingTail
        if tableView === commitTable {
            switch commitRows[row] {
            case .header(let t):
                label.stringValue = t; label.font = .systemFont(ofSize: 11, weight: .semibold); label.textColor = .secondaryLabelColor
            case .commit(let c):
                label.font = .systemFont(ofSize: 12)
                let s = NSMutableAttributedString(string: c.shortHash + "  ", attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor])
                s.append(NSAttributedString(string: c.subject, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor]))
                s.append(NSAttributedString(string: "   \(c.author), \(c.relativeDate)", attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]))
                label.attributedStringValue = s
            }
        } else {
            let f = cmp.files[row]
            let color: NSColor = f.status == "A" ? .systemGreen : f.status == "D" ? .systemRed : .systemBlue
            let s = NSMutableAttributedString(string: f.status + "  ", attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold), .foregroundColor: color])
            s.append(NSAttributedString(string: f.path, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor]))
            label.attributedStringValue = s
        }
        return label
    }
}
