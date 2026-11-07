import AppKit

/// Bottom-panel "Ledger": the user's memory of reviewed agent changes. Sessions newest first (search box above), and for the selected
/// session an editable note plus the changed files and methods; double-click a method to open it.
final class ChangeLedgerPanel: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate, NSSearchFieldDelegate {
    private enum SymbolRow { case file(LedgerFile), symbol(LedgerFile, LedgerSymbol) }

    let view = LedgerRootView()
    var openFile: ((URL, Int) -> Void)?
    /// Feature names that claim any of the paths, and how many of the paths no feature claims (set by the window).
    var featureLookup: (([String]) -> (names: [String], unmapped: Int))?
    let ledger: ChangeLedger
    private let root: URL
    private let search = NSSearchField()
    private let sessionsTable = SpeedTableView()
    private let sessionsScroll = NSScrollView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let touchesLabel = NSTextField(labelWithString: "")
    private let noteHint = NSTextField(labelWithString: "Your note: what does this do, in your words?")
    private let noteView = NSTextView()
    private let noteScroll = NSScrollView()
    private let symbolsTable = NSTableView()
    private let symbolsScroll = NSScrollView()
    private let emptyLabel = NSTextField(wrappingLabelWithString: "")
    private let divider = NSView()
    private var shown: [LedgerSession] = []
    private var symbolRows: [SymbolRow] = []
    private var selectedID: String?
    private var noteDirty = false

    private static let date: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; return f }()

    init(ledger: ChangeLedger, root: URL) {
        self.ledger = ledger
        self.root = root
        super.init()
        search.placeholderString = "Search title, note, files, methods"
        search.controlSize = .small
        search.delegate = self
        let col = NSTableColumn(identifier: .init("s")); col.resizingMask = .autoresizingMask
        sessionsTable.addTableColumn(col)
        sessionsTable.headerView = nil
        sessionsTable.rowHeight = 22
        sessionsTable.dataSource = self
        sessionsTable.delegate = self
        sessionsTable.backgroundColor = .clear
        sessionsTable.style = .plain
        sessionsScroll.documentView = sessionsTable
        sessionsScroll.hasVerticalScroller = true
        sessionsScroll.drawsBackground = false
        let scol = NSTableColumn(identifier: .init("y")); scol.resizingMask = .autoresizingMask
        symbolsTable.addTableColumn(scol)
        symbolsTable.headerView = nil
        symbolsTable.rowHeight = 20
        symbolsTable.dataSource = self
        symbolsTable.delegate = self
        symbolsTable.target = self
        symbolsTable.doubleAction = #selector(symbolDoubleClicked)
        symbolsTable.backgroundColor = .clear
        symbolsTable.style = .plain
        symbolsScroll.documentView = symbolsTable
        symbolsScroll.hasVerticalScroller = true
        symbolsScroll.drawsBackground = false
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        touchesLabel.font = .systemFont(ofSize: 10.5)
        touchesLabel.textColor = .secondaryLabelColor
        touchesLabel.lineBreakMode = .byTruncatingTail
        noteHint.font = .systemFont(ofSize: 10.5)
        noteHint.textColor = .secondaryLabelColor
        noteView.isRichText = false
        noteView.allowsUndo = true
        noteView.isAutomaticQuoteSubstitutionEnabled = false
        noteView.isAutomaticDashSubstitutionEnabled = false
        noteView.isAutomaticTextReplacementEnabled = false
        noteView.font = .systemFont(ofSize: 12)
        noteView.isVerticallyResizable = true
        noteView.autoresizingMask = [.width]
        noteView.textContainerInset = NSSize(width: 4, height: 4)
        noteView.delegate = self
        noteScroll.documentView = noteView
        noteScroll.hasVerticalScroller = true
        noteScroll.borderType = .bezelBorder
        emptyLabel.alignment = .center
        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .secondaryLabelColor
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.separatorColor.cgColor
        for v in [search, sessionsScroll, divider, titleLabel, touchesLabel, noteHint, noteScroll, symbolsScroll, emptyLabel] as [NSView] { view.addSubview(v) }
        view.search = search; view.sessionsScroll = sessionsScroll; view.divider = divider; view.titleLabel = titleLabel; view.touchesLabel = touchesLabel; view.noteHint = noteHint
        view.noteScroll = noteScroll; view.symbolsScroll = symbolsScroll; view.emptyLabel = emptyLabel
        ledger.onChange = { [weak self] in self?.reload() }
        updateRight()
    }

    // MARK: Data

    /// Sessions whose title, note, files or symbol names contain `query` (case-insensitive); a blank query keeps all.
    static func filter(_ sessions: [LedgerSession], query: String) -> [LedgerSession] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return q.isEmpty ? sessions : sessions.filter { $0.searchText.contains(q) }
    }

    func reload() {
        commitNote()
        shown = Self.filter(ledger.sessions, query: search.stringValue)
        sessionsTable.reloadData()
        if let id = selectedID, let i = shown.firstIndex(where: { $0.id == id }) { sessionsTable.selectRowIndexes([i], byExtendingSelection: false) }
        else { selectedID = nil; sessionsTable.deselectAll(nil) }
        updateRight()
        let none = ledger.sessions.isEmpty
        emptyLabel.stringValue = none ? "No reviewed agent changes yet. Accept changes in Claude Changes to start your ledger." : (shown.isEmpty ? "No ledger entries match." : "")
        view.emptyLabel.isHidden = emptyLabel.stringValue.isEmpty
        view.needsLayout = true
    }

    private func plural(_ n: Int, _ s: String) -> String { "\(n) \(s)\(n == 1 ? "" : "s")" }

    private func description(_ s: LedgerSession) -> String {
        var d = "\(Self.date.string(from: s.updated)) \(s.title) · \(plural(s.files.count, "file")) · \(plural(s.symbolCount, "symbol"))"
        if !s.note.isEmpty { d += " — " + String(s.note.replacingOccurrences(of: "\n", with: " ").prefix(60)) }
        return d
    }

    /// "Touches: A · B, 2 files not in any feature" (empty when there is nothing to say).
    static func touches(_ r: (names: [String], unmapped: Int)?) -> String {
        guard let r else { return "" }
        var parts: [String] = []
        if !r.names.isEmpty { parts.append("Touches: " + r.names.prefix(4).joined(separator: " · ") + (r.names.count > 4 ? " · +\(r.names.count - 4)" : "")) }
        if r.unmapped > 0 { parts.append("\(r.unmapped) file\(r.unmapped == 1 ? "" : "s") not in any feature") }
        return parts.joined(separator: ", ")
    }

    var touchesText: String { touchesLabel.isHidden ? "" : touchesLabel.stringValue }

    var rowDescriptions: [String] { shown.map(description) }
    var emptyText: String { emptyLabel.stringValue }
    var noteText: String { noteView.string }

    @discardableResult
    func selectSession(id: String) -> Bool {
        guard let i = shown.firstIndex(where: { $0.id == id }) else { return false }
        commitNote()
        selectedID = id
        sessionsTable.selectRowIndexes([i], byExtendingSelection: false)
        updateRight()
        return true
    }

    private var selectedSession: LedgerSession? { shown.first { $0.id == selectedID } }

    private func updateRight() {
        guard let s = selectedSession else {
            titleLabel.stringValue = ""
            noteView.string = ""
            symbolRows = []
            symbolsTable.reloadData()
            noteDirty = false
            for v in [titleLabel, touchesLabel, noteHint, noteScroll, symbolsScroll] as [NSView] { v.isHidden = true }
            return
        }
        for v in [titleLabel, touchesLabel, noteHint, noteScroll, symbolsScroll] as [NSView] { v.isHidden = false }
        titleLabel.stringValue = "\(s.title)  ·  \(Self.date.string(from: s.started))"
        touchesLabel.stringValue = Self.touches(featureLookup?(s.files.map { $0.rel }))
        touchesLabel.isHidden = touchesLabel.stringValue.isEmpty
        view.needsLayout = true
        if noteView.string != s.note { noteView.string = s.note }      // do not move the caret when nothing changed
        noteDirty = false
        symbolRows = s.files.flatMap { f in [SymbolRow.file(f)] + f.symbols.map { SymbolRow.symbol(f, $0) } }
        symbolsTable.reloadData()
    }

    var symbolRowDescriptions: [String] {
        symbolRows.map {
            switch $0 {
            case .file(let f): return "FILE \(f.rel) +\(f.added) −\(f.removed)"
            case .symbol(_, let y): return "  \(y.name) :\(y.line) +\(y.added) −\(y.removed)"
            }
        }
    }

    // MARK: Note editing

    func setNoteText(_ s: String) { noteView.string = s; noteDirty = true }

    func textDidChange(_ notification: Notification) { noteDirty = true }
    func textDidEndEditing(_ notification: Notification) { commitNote() }

    /// Saves the edited note of the selected session (no-op when unchanged).
    func commitNote() {
        guard noteDirty, let id = selectedID else { noteDirty = false; return }
        noteDirty = false
        guard let s = ledger.sessions.first(where: { $0.id == id }), s.note != noteView.string else { return }
        let saveSelection = selectedID
        ledger.onChange = nil          // our own edit must not rebuild the lists under the cursor
        ledger.setNote(noteView.string, for: id)
        ledger.onChange = { [weak self] in self?.reload() }
        shown = Self.filter(ledger.sessions, query: search.stringValue)
        selectedID = saveSelection
        sessionsTable.reloadData()
        if let i = shown.firstIndex(where: { $0.id == id }) { sessionsTable.selectRowIndexes([i], byExtendingSelection: false) }
    }

    // MARK: Open

    func openSymbol(row: Int) {
        guard symbolRows.indices.contains(row) else { return }
        switch symbolRows[row] {
        case .file(let f): openFile?(root.appendingPathComponent(f.rel), 1)
        case .symbol(let f, let y): openFile?(root.appendingPathComponent(f.rel), max(1, y.line))
        }
    }

    @objc private func symbolDoubleClicked() { openSymbol(row: symbolsTable.clickedRow) }

    // MARK: Search

    func controlTextDidChange(_ obj: Notification) { reload() }

    // MARK: Tables

    func numberOfRows(in tableView: NSTableView) -> Int { tableView === sessionsTable ? shown.count : symbolRows.count }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard (notification.object as? NSTableView) === sessionsTable else { return }
        commitNote()
        let r = sessionsTable.selectedRow
        selectedID = shown.indices.contains(r) ? shown[r].id : nil
        updateRight()
    }

    /// A session with a note gets a second line for it: the note is the point of the ledger.
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if tableView === sessionsTable, shown.indices.contains(row), !shown[row].note.isEmpty { return 40 }
        return tableView === sessionsTable ? 22 : 20
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let fg = Theme.foreground, dim = Theme.isDark ? NSColor(white: 0.62, alpha: 1) : NSColor(white: 0.40, alpha: 1)
        func styled(_ parts: [(String, NSColor, NSFont.Weight, Bool)]) -> NSAttributedString {
            let out = NSMutableAttributedString()
            for (text, color, weight, mono) in parts {
                out.append(NSAttributedString(string: text, attributes: [.foregroundColor: color,
                    .font: mono ? NSFont.monospacedSystemFont(ofSize: 11, weight: weight) : NSFont.systemFont(ofSize: 12, weight: weight)]))
            }
            return out
        }
        let cell = LedgerCell()
        if tableView === sessionsTable, shown.indices.contains(row) {
            let s = shown[row]
            cell.first.attributedStringValue = styled([(Self.date.string(from: s.updated) + "  ", dim, .regular, true), (s.title, fg, .semibold, false),
                                                       ("  \(plural(s.files.count, "file")) · \(plural(s.symbolCount, "symbol"))", dim, .regular, false)])
            cell.second.attributedStringValue = styled([(s.note.replacingOccurrences(of: "\n", with: " "), fg, .regular, false)])
            cell.second.isHidden = s.note.isEmpty
        } else if symbolRows.indices.contains(row) {
            switch symbolRows[row] {
            case .file(let f):
                cell.first.attributedStringValue = styled([(f.rel, fg, .semibold, false), ("  +\(f.added) −\(f.removed)", dim, .regular, false)])
            case .symbol(_, let y):
                cell.first.attributedStringValue = styled([("    " + y.name, fg, .regular, false), ("  :\(y.line)", dim, .regular, true),
                                                           ("  +\(y.added)", .systemGreen, .regular, false), (" −\(y.removed)", y.removed > 0 ? .systemRed : dim, .regular, false)])
            }
            cell.second.isHidden = true
        }
        return cell
    }

    // MARK: Snapshot

    func snapshot(to path: String, size: NSSize = NSSize(width: 900, height: 300)) {
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        view.layout()
        sessionsTable.reloadData(); symbolsTable.reloadData()
        for r in 0..<sessionsTable.numberOfRows { _ = sessionsTable.view(atColumn: 0, row: r, makeIfNecessary: true) }
        for r in 0..<symbolsTable.numberOfRows { _ = symbolsTable.view(atColumn: 0, row: r, makeIfNecessary: true) }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}

/// Frame layout of the Ledger panel: sessions on the left (search box above), note and methods on the right.
final class LedgerRootView: NSView {
    var search: NSView!, sessionsScroll: NSView!, divider: NSView!, titleLabel: NSView!, touchesLabel: NSView!, noteHint: NSView!
    var noteScroll: NSView!, symbolsScroll: NSView!, emptyLabel: NSView!
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        let leftW = max(260, w * 0.45)
        search.frame = NSRect(x: 8, y: 6, width: leftW - 16, height: 22)
        sessionsScroll.frame = NSRect(x: 0, y: 34, width: leftW, height: max(0, h - 34))
        divider.frame = NSRect(x: leftW, y: 0, width: 1, height: h)
        let rx = leftW + 10, rw = max(0, w - leftW - 18)
        titleLabel.frame = NSRect(x: rx, y: 8, width: rw, height: 18)
        let t = touchesLabel.isHidden ? 0 : CGFloat(16)
        touchesLabel.frame = NSRect(x: rx, y: 26, width: rw, height: 14)
        noteHint.frame = NSRect(x: rx, y: 28 + t, width: rw, height: 14)
        noteScroll.frame = NSRect(x: rx, y: 44 + t, width: rw, height: min(96, max(40, h * 0.3)))
        let sy = noteScroll.frame.maxY + 8
        symbolsScroll.frame = NSRect(x: leftW + 1, y: sy, width: w - leftW - 1, height: max(0, h - sy))
        emptyLabel.frame = NSRect(x: 12, y: h / 2 - 20, width: leftW - 24, height: 40)
    }
}


/// One or two truncating lines (sessions: title line and the note line).
final class LedgerCell: NSTableCellView {
    let first = NSTextField(labelWithString: "")
    let second = NSTextField(labelWithString: "")
    override init(frame: NSRect) {
        super.init(frame: frame)
        first.lineBreakMode = .byTruncatingTail
        second.lineBreakMode = .byTruncatingTail
        addSubview(first); addSubview(second)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        if second.isHidden { first.frame = NSRect(x: 4, y: (bounds.height - 17) / 2, width: bounds.width - 8, height: 17) }
        else {
            first.frame = NSRect(x: 4, y: bounds.height - 20, width: bounds.width - 8, height: 17)
            second.frame = NSRect(x: 4, y: 2, width: bounds.width - 8, height: 17)
        }
    }
}
