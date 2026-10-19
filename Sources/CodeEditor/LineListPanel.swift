import AppKit

/// Compact list tool panel (TODO, Bookmarks): one recycled row view per visible row, a status line, optional filter chips.
/// Rows are plain values; nothing is retained beyond the capped list the owner hands in.
final class LineListPanel: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    struct Row: Equatable {
        var tag: String          // filter bucket ("TODO", "FIXME", ...)
        var primary: String      // the line's text
        var secondary: String    // "relative/path.php:42"
        var path: String
        var line: Int
    }

    let view = NSView()
    private let table = NSTableView()
    private let status = NSTextField(labelWithString: "")
    private let refreshButton = NSButton()
    private let chips = NSSegmentedControl()
    private(set) var rows: [Row] = []
    private(set) var shown: [Row] = []
    private var filter = "All"
    var onOpen: ((Row) -> Void)?
    var onRefresh: (() -> Void)?
    var onDelete: ((Row) -> Void)?

    init(emptyMessage: String, showsRefresh: Bool) {
        super.init()
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("row"))
        col.resizingMask = .autoresizingMask
        table.addTableColumn(col)
        table.headerView = nil
        table.rowHeight = 22
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(activate)
        table.style = .plain
        table.backgroundColor = .clear
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.stringValue = emptyMessage
        status.lineBreakMode = .byTruncatingTail
        refreshButton.bezelStyle = .recessed
        refreshButton.isBordered = false
        refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")
        refreshButton.target = self
        refreshButton.action = #selector(refresh)
        refreshButton.toolTip = "Rescan"
        refreshButton.isHidden = !showsRefresh
        chips.segmentStyle = .roundRect
        chips.controlSize = .small
        chips.target = self
        chips.action = #selector(chipChanged)
        chips.isHidden = true

        let bar = NSStackView(views: [chips, status, refreshButton])
        bar.orientation = .horizontal
        bar.spacing = 8
        bar.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        for v in [bar, scroll] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(v) }
        status.setContentHuggingPriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.topAnchor), bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor), bar.heightAnchor.constraint(equalToConstant: 28),
            scroll.topAnchor.constraint(equalTo: bar.bottomAnchor), scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    /// Filter chips ("All" + the given tags); hidden when there is nothing to choose between.
    func setTags(_ tags: [String]) {
        let all = ["All"] + tags
        chips.segmentCount = all.count
        for (i, t) in all.enumerated() { chips.setLabel(t, forSegment: i); chips.setWidth(0, forSegment: i) }
        if !all.contains(filter) { filter = "All" }
        chips.selectedSegment = all.firstIndex(of: filter) ?? 0
        chips.isHidden = tags.count < 2
    }

    func setRows(_ new: [Row], status text: String) {
        rows = new
        status.stringValue = text
        applyFilter()
    }

    func setStatus(_ text: String) { status.stringValue = text }

    private func applyFilter() {
        shown = filter == "All" ? rows : rows.filter { $0.tag == filter }
        table.reloadData()
    }

    @objc private func chipChanged() {
        filter = chips.label(forSegment: chips.selectedSegment) ?? "All"
        applyFilter()
    }

    @objc private func refresh() { onRefresh?() }

    @objc private func activate() {
        let r = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
        if shown.indices.contains(r) { onOpen?(shown[r]) }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = tableView.makeView(withIdentifier: id, owner: nil) as? RowCell ?? { let c = RowCell(); c.identifier = id; return c }()
        let r = shown[row]
        cell.configure(r)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {}

    final class RowCell: NSView {
        private let tagLabel = NSTextField(labelWithString: "")
        private let primary = NSTextField(labelWithString: "")
        private let secondary = NSTextField(labelWithString: "")
        override init(frame: NSRect) {
            super.init(frame: frame)
            tagLabel.font = .systemFont(ofSize: 9, weight: .bold)
            tagLabel.alignment = .center
            tagLabel.wantsLayer = true
            tagLabel.layer?.cornerRadius = 3
            primary.font = .systemFont(ofSize: 12)
            primary.lineBreakMode = .byTruncatingTail
            secondary.font = .systemFont(ofSize: 11)
            secondary.textColor = .secondaryLabelColor
            secondary.lineBreakMode = .byTruncatingHead
            for v in [tagLabel, primary, secondary] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
            primary.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            NSLayoutConstraint.activate([
                tagLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10), tagLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                tagLabel.widthAnchor.constraint(equalToConstant: 48), tagLabel.heightAnchor.constraint(equalToConstant: 14),
                primary.leadingAnchor.constraint(equalTo: tagLabel.trailingAnchor, constant: 8), primary.centerYAnchor.constraint(equalTo: centerYAnchor),
                secondary.leadingAnchor.constraint(greaterThanOrEqualTo: primary.trailingAnchor, constant: 12),
                secondary.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10), secondary.centerYAnchor.constraint(equalTo: centerYAnchor),
                secondary.widthAnchor.constraint(lessThanOrEqualToConstant: 320),
            ])
        }
        required init?(coder: NSCoder) { fatalError() }

        func configure(_ r: Row) {
            let color: NSColor
            switch r.tag {
            case "FIXME": color = .systemRed
            case "HACK", "XXX": color = .systemOrange
            case "TODO": color = .systemBlue
            default: color = .systemGray
            }
            tagLabel.stringValue = r.tag.isEmpty ? "•" : r.tag
            tagLabel.textColor = color
            tagLabel.layer?.backgroundColor = color.withAlphaComponent(0.15).cgColor
            primary.stringValue = r.primary
            secondary.stringValue = r.secondary
        }
    }
}
