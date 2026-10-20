import AppKit

/// Persistent "Structure" tool window (PhpStorm ⌘7): the outline of the current file that follows the caret. Built lazily on the
/// first ⌘7 and refreshed ONLY while it is on screen: the outline is extracted on a background queue after a short pause in
/// typing, and the caret-follow is a cheap lookup in the cached rows (no re-parse). Nothing runs while the panel is hidden.
final class StructurePanelController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    struct Row {
        let title: String
        let detail: String
        let icon: String
        let line: Int
        let level: Int
        let isNamespace: Bool
    }

    let view = NSView()
    private let table = SpeedTableView()
    private let speed = SpeedSearch()
    private let empty = NSTextField(labelWithString: "No structure for this file")
    private(set) var rows: [Row] = []
    private var generation = 0
    private var parseWork: DispatchWorkItem?
    private var followWork: DispatchWorkItem?
    /// Called with a 1-based line when a row is chosen (click or Return).
    var onGoTo: ((Int) -> Void)?

    override init() {
        super.init()
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("row"))
        col.resizingMask = .autoresizingMask
        table.addTableColumn(col)
        table.headerView = nil
        table.rowHeight = 22
        table.style = .plain
        table.backgroundColor = .clear
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(clicked)
        table.onReturn = { [weak self] in self?.chooseSelected() }
        speed.attach(to: table) { [weak self] row in
            guard let r = self?.rows, r.indices.contains(row) else { return nil }
            return r[row].title
        }
        speed.onReturn = { [weak self] in self?.chooseSelected() }
        table.speedSearch = speed
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        empty.textColor = .secondaryLabelColor
        empty.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        view.addSubview(empty)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            empty.centerXAnchor.constraint(equalTo: view.centerXAnchor), empty.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    // MARK: Updating (call only while visible)

    /// Re-extracts the outline now (tab switch / panel shown) or after a pause (typing).
    func refresh(text: String, fileExtension: String, caretLine: Int, delay: TimeInterval = 0) {
        parseWork?.cancel()
        generation += 1
        let gen = generation
        let work = DispatchWorkItem { [weak self] in
            DispatchQueue.global(qos: .userInitiated).async {
                let rows = Self.extract(text: text, fileExtension: fileExtension)
                DispatchQueue.main.async {
                    guard let self, gen == self.generation else { return }
                    self.rows = rows
                    self.table.reloadData()
                    self.empty.isHidden = !rows.isEmpty
                    self.follow(line: caretLine)
                }
            }
        }
        parseWork = work
        if delay <= 0 { work.perform() } else { DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work) }
    }

    /// Selects the declaration enclosing `line` (cached rows only; debounced by the caller via `scheduleFollow`).
    func follow(line: Int) {
        guard !rows.isEmpty else { return }
        var best: Int?
        for (i, r) in rows.enumerated() where r.line <= line && !r.isNamespace { best = i }
        guard let best, table.selectedRow != best else { return }
        table.selectRowIndexes(IndexSet(integer: best), byExtendingSelection: false)
        table.scrollRowToVisible(best)
    }

    func scheduleFollow(line: @escaping () -> Int) {
        followWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.follow(line: line()) }
        followWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    func cancelPending() {
        parseWork?.cancel(); followWork?.cancel()
        generation += 1
    }

    /// Outline rows in source order (also used by tests).
    static func extract(text: String, fileExtension: String) -> [Row] {
        var lines: [Int] = []
        let result = FileStructure.items(text: text, fileExtension: fileExtension, currentLine: 0) { lines.append($0) }
        var rows: [Row] = []
        for item in result.items {
            let before = lines.count
            item.run()
            guard lines.count > before else { continue }
            let markdown = PlanOutline.handles(fileExtension)
            let lead = item.title.prefix { $0 == " " }.count
            rows.append(Row(title: item.title.trimmingCharacters(in: .whitespaces), detail: markdown ? "" : item.detail, icon: item.symbol,
                            line: lines[before], level: markdown ? lead / 4 : (item.detail.isEmpty ? 0 : 1),
                            isNamespace: item.symbol == CodeSymbol.Kind.namespace.iconName))
        }
        return rows
    }

    // MARK: Table

    @objc private func clicked() { chooseSelected() }

    private func chooseSelected() {
        let r = table.selectedRow
        guard rows.indices.contains(r) else { return }
        onGoTo?(rows[r].line)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("structureCell")
        let cell = tableView.makeView(withIdentifier: id, owner: nil) as? StructureCell ?? { let c = StructureCell(); c.identifier = id; return c }()
        let r = rows[row]
        cell.configure(r, hits: speed.matchedIndices(in: r.title))
        return cell
    }
}

private final class StructureCell: NSTableCellView {
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private var indent: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        title.lineBreakMode = .byTruncatingTail
        detail.lineBreakMode = .byTruncatingTail
        detail.font = .systemFont(ofSize: 11)
        for v in [icon, title, detail] as [NSView] { addSubview(v) }
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ r: StructurePanelController.Row, hits: Set<Int>) {
        indent = CGFloat(r.level) * 14
        icon.image = NSImage(systemSymbolName: r.icon, accessibilityDescription: nil)
        icon.contentTintColor = Theme.gutter
        let font = NSFont.systemFont(ofSize: 12)
        let s = NSMutableAttributedString(string: r.title, attributes: [.font: font, .foregroundColor: Theme.foreground])
        let bold = NSFont.systemFont(ofSize: 12, weight: .bold)
        let len = r.title.utf16.count
        for i in hits where i < len { s.addAttributes([.font: bold, .foregroundColor: NSColor.controlAccentColor], range: NSRange(location: i, length: 1)) }
        title.attributedStringValue = s
        detail.stringValue = r.detail
        detail.textColor = Theme.gutter
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        icon.frame = NSRect(x: 8 + indent, y: (h - 14) / 2, width: 14, height: 14)
        let x = 8 + indent + 14 + 6
        let tw = min(ceil(title.attributedStringValue.size().width) + 4, max(0, bounds.width - x - 8))
        title.frame = NSRect(x: x, y: (h - 16) / 2, width: tw, height: 16)
        detail.frame = NSRect(x: x + tw + 6, y: (h - 14) / 2, width: max(0, bounds.width - x - tw - 14), height: 14)
    }
}

extension ProjectWindow {
    var isStructureVisible: Bool { bottom.isVisible && bottom.selectedID == "structure" }

    /// Builds the panel and its observers on first use.
    func installStructurePanel() {
        guard !hasToolPanel("structure"), root != nil else { return }
        let panel = StructurePanelController()
        structurePanel = panel
        panel.onGoTo = { [weak self] line in
            guard let self, let tv = self.current?.textView else { return }
            tv.goToLine(line)
            self.focusEditor()
        }
        registerToolPanel(id: "structure", title: "Structure", view: panel.view)
        let nc = NotificationCenter.default
        structureObservers = [
            nc.addObserver(forName: NSTextView.didChangeSelectionNotification, object: nil, queue: .main) { [weak self] n in
                guard let self, self.isStructureVisible, let tv = n.object as? NSTextView, tv === self.current?.textView else { return }
                panel.scheduleFollow { [weak self] in self?.current?.textView.lineAndColumn.line ?? 1 }
            },
            nc.addObserver(forName: NSText.didChangeNotification, object: nil, queue: .main) { [weak self] n in
                guard let self, self.isStructureVisible, let tv = n.object as? NSTextView, tv === self.current?.textView else { return }
                self.refreshStructure(delay: 0.7)
            },
        ]
    }

    func refreshStructure(delay: TimeInterval = 0) {
        guard isStructureVisible, let panel = structurePanel, let editor = current else { return }
        panel.refresh(text: editor.textView.string, fileExtension: editor.url.pathExtension.lowercased(),
                      caretLine: editor.textView.lineAndColumn.line, delay: delay)
    }
}
